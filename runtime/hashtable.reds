Red/System [
	Title:	"A Hash Table Implementation"
	Author: "Xie Qingtian"
	File: 	%hashtable.reds
	Tabs:	4
	Rights: "Copyright (C) 2014 Xie Qingtian. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/dockimbel/Red/blob/master/BSL-License.txt
	}
	Notes: {
		Algorithm: Open addressing, quadratic probing.
	}
]

#define _HT_HASH_UPPER	0.77

#define _BUCKET_IS_EMPTY(flags i s)			[flags/i >> s and 2 = 2]
#define _BUCKET_IS_NOT_EMPTY(flags i s)		[flags/i >> s and 2 <> 2]
#define _BUCKET_IS_DEL(flags i s)			[flags/i >> s and 1 = 1]
#define _BUCKET_IS_NOT_DEL(flags i s)		[flags/i >> s and 1 <> 1]
#define _BUCKET_IS_EITHER(flags i s)		[flags/i >> s and 3 > 0]
#define _BUCKET_IS_CLEARED(flags i s)		[flags/i >> s and 3 = 0]
#define _BUCKET_SET_DEL_TRUE(flags i s)		[flags/i: 1 << s or flags/i]
#define _BUCKET_SET_DEL_FALSE(flags i s)	[flags/i: (not 1 << s) and flags/i]
#define _BUCKET_SET_EMPTY_FALSE(flags i s)	[flags/i: (not 2 << s) and flags/i]
#define _BUCKET_SET_BOTH_FALSE(flags i s)	[flags/i: (not 3 << s) and flags/i]

#define _HT_CAL_FLAG_INDEX(i idx shift) [
	idx: i >> 4 + 1
	shift: i and 0Fh << 1
]

#define MURMUR_HASH_3_X86_32_C1		CC9E2D51h
#define MURMUR_HASH_3_X86_32_C2		1B873593h

#define MURMUR_HASH_ROTL_32(x r) [
	x << r or (x >>> (32 - r))
]

hash-string: func [
	str					[red-string!]
	case-insensitive?	[logic!]
	return: 			[integer!]
	/local series s unit p p4 k1 h1 tail len head
][
	s: GET_BUFFER(str)
	unit: GET_UNIT(s)
	head: either TYPE_OF(str) = TYPE_SYMBOL [-1][str/head]
	p: (as byte-ptr! s/offset) + (head << (unit >> 1))
	tail: as byte-ptr! s/tail
	len: (as-integer tail - p) >> (unit >> 1) << 2
	h1: 42								;-- seed

	;-- body
	while [p < tail][
		k1: switch unit [
			Latin1 [as-integer p/value]
			UCS-2  [(as-integer p/2) << 8 + p/1]
			UCS-4  [p4: as int-ptr! p p4/value]
		]
		if case-insensitive? [k1: case-folding/folding-case k1 yes]
		k1: k1 * MURMUR_HASH_3_X86_32_C1
		k1: MURMUR_HASH_ROTL_32(k1 15)
		k1: k1 * MURMUR_HASH_3_X86_32_C2

		h1: h1 xor k1
		h1: MURMUR_HASH_ROTL_32(h1 13)
		h1: h1 * 5 + E6546B64h
		p: p + unit
	]

	;-- finalization
	h1: h1 xor len
	h1: h1 >>> 16 xor h1
	h1: h1 * 85EBCA6Bh
	h1: h1 >>> 13 xor h1
	h1: h1 * C2B2AE35h
	h1: h1 >>> 16 xor h1
	h1
]

murmur3-x86-32: func [
	key		[byte-ptr!]
	len		[integer!]
	return: [integer!]
	/local data nblocks blocks p i k1 h1 tail n
][
	assert len > 0

	data: key
	nblocks: len / 4
	h1: 42								;-- seed

	;-- body
	blocks: as int-ptr! (data + (nblocks * 4))
	i: negate nblocks
	while [negative? i][
		p: blocks + i
		k1: p/value						;@@ do endian-swapping if needed
		k1: k1 * MURMUR_HASH_3_X86_32_C1
		k1: MURMUR_HASH_ROTL_32(k1 15)
		k1: k1 * MURMUR_HASH_3_X86_32_C2

		h1: h1 xor k1
		h1: MURMUR_HASH_ROTL_32(h1 13)
		h1: h1 * 5 + E6546B64h
		i: i + 1
	]

	;-- tail
	n: len and 3
	if positive? n [
		k1: 0
		tail: data + (nblocks * 4)
		if n = 3 [k1: (as-integer tail/3) << 16 xor k1]
		if n > 1 [k1: (as-integer tail/2) << 8  xor k1]
		k1: (as-integer tail/1) xor k1
		k1: k1 * MURMUR_HASH_3_X86_32_C1
		k1: MURMUR_HASH_ROTL_32(k1 15)
		k1: k1 * MURMUR_HASH_3_X86_32_C2
		h1: h1 xor k1
	]

	;-- finalization
	h1: h1 xor len
	h1: h1 >>> 16 xor h1
	h1: h1 * 85EBCA6Bh
	h1: h1 >>> 13 xor h1
	h1: h1 * C2B2AE35h
	h1: h1 >>> 16 xor h1
	h1
]

_hashtable: context [
	hashtable!: alias struct! [
		size		[integer!]
		indexes		[node!]
		flags		[node!]
		keys		[node!]
		blk			[node!]
		n-occupied	[integer!]
		n-buckets	[integer!]
		upper-bound	[integer!]
	]

	round-up: func [
		n		[integer!]
		return: [integer!]
	][
		n: n - 1
		n: n >> 1 or n
		n: n >> 2 or n
		n: n >> 4 or n
		n: n >> 8 or n
		n: n >> 16 or n
		n + 1
	]

	hash-value?: func [
		key		[red-value!]
		return:	[logic!]
	][
		switch TYPE_OF(key) [
			TYPE_STRING
			TYPE_FILE
			TYPE_URL
			TYPE_CHAR
			TYPE_INTEGER
			TYPE_FLOAT
			TYPE_WORD
			TYPE_SET_WORD
			TYPE_LIT_WORD
			TYPE_GET_WORD
			TYPE_REFINEMENT
			TYPE_ISSUE
			TYPE_POINT [true]
			default    [false]
		]
	]

	hash-value: func [
		key			[red-value!]
		multi-key?	[logic!]
		return: 	[integer!]
		/local sym s
	][
		len: 0
		switch TYPE_OF(key) [
			TYPE_STRING
			TYPE_FILE
			TYPE_URL   [
				hash-string as red-string! key multi-key?
			]
			TYPE_CHAR
			TYPE_INTEGER [key/data2]
			TYPE_FLOAT [
				murmur3-x86-32 (as byte-ptr! key) + 8 8
			]
			TYPE_WORD
			TYPE_SET_WORD
			TYPE_LIT_WORD
			TYPE_GET_WORD
			TYPE_REFINEMENT
			TYPE_ISSUE [
				s: GET_BUFFER(symbols)
				sym: as red-string! s/offset + key/data2 - 1
				hash-string sym multi-key?
			]
			TYPE_POINT [
				murmur3-x86-32 (as byte-ptr! key) + 4 12
			]
			default [
				fire [
					TO_ERROR(script invalid-type)
					datatype/push TYPE_OF(key)
				]
				0
			]
		]
	]

	put-all: func [
		node	[node!]
		head	[integer!]
		skip	[integer!]
		/local s h i end value
	][
		s: as series! node/value
		h: as hashtable! s/offset
		
		s: as series! h/blk/value
		end: s/tail
		i: head
		while [
			value: s/offset + i
			value < end
		][
			put node value no
			i: i + skip
		]
	]

	init: func [
		size	[integer!]
		blk		[red-block!]
		map?	[logic!]
		return: [node!]
		/local node s ss h f-buckets fsize i value skip end
	][
		node: alloc-bytes-filled size? hashtable! #"^(00)"
		s: as series! node/value
		h: as hashtable! s/offset

		if size < 3 [size: 3]
		fsize: integer/to-float size
		f-buckets: fsize / _HT_HASH_UPPER
		skip: either map? [f-buckets: f-buckets / 2.0 2][1]
		h/n-buckets: round-up float/to-integer f-buckets
		f-buckets: integer/to-float h/n-buckets
		h/upper-bound: float/to-integer f-buckets * _HT_HASH_UPPER
		h/flags: alloc-bytes-filled h/n-buckets >> 2 #"^(AA)"
		h/keys: alloc-bytes h/n-buckets * size? int-ptr!
		h/blk: blk/node

		s: GET_BUFFER(blk)
		end: s/tail
		unless map? [
			h/indexes: alloc-bytes-filled size * size? integer! #"^(FF)"
			i: (as-integer (end - s/offset)) >> 4 - blk/head
			ss: as series! h/indexes/value
			ss/tail: as cell! (as int-ptr! ss/tail) + i
		]
		put-all node blk/head skip
		node
	]

	resize: func [
		node			[node!]
		new-buckets		[integer!]
		/local
			s h x k v i j site last mask step keys vals hash n-buckets blk
			new-size tmp break? flags new-flags new-flags-node ii sh f idx
			multi-key?
	][
		s: as series! node/value
		h: as hashtable! s/offset
		multi-key?: h/indexes <> null
		s: as series! h/blk/value
		blk: s/offset
		s: as series! h/flags/value
		flags: as int-ptr! s/offset
		n-buckets: h/n-buckets
		j: 0
		new-buckets: round-up new-buckets
		f: integer/to-float new-buckets
		new-size: float/to-integer f * _HT_HASH_UPPER
		if new-buckets < 4 [new-buckets: 4]
		either h/size >= new-size [j: 1][
			new-flags-node: alloc-bytes-filled new-buckets >> 2 #"^(AA)"
			s: as series! new-flags-node/value
			new-flags: as int-ptr! s/offset
			if n-buckets < new-buckets [
				expand-series as series! h/keys/value new-buckets * size? int-ptr!
			]
		]
		if zero? j [
			step: 0
			s: as series! h/keys/value
			keys: as int-ptr! s/offset
			until [
				_HT_CAL_FLAG_INDEX(j ii sh)
				j: j + 1
				if _BUCKET_IS_CLEARED(flags ii sh) [
					idx: keys/j
					mask: new-buckets - 1
					_BUCKET_SET_DEL_TRUE(flags ii sh)
					break?: no
					until [									;-- kick-out process
						k: blk + (idx and 7FFFFFFFh)
						hash: hash-value k multi-key?
						i: hash and mask
						_HT_CAL_FLAG_INDEX(i ii sh)
						while [_BUCKET_IS_NOT_EMPTY(new-flags ii sh)][
							step: step + 1
							i: i + step and mask
							_HT_CAL_FLAG_INDEX(i ii sh)
						]
						i: i + 1
						_BUCKET_SET_EMPTY_FALSE(new-flags ii sh)
						either all [
							i <= n-buckets
							_BUCKET_IS_CLEARED(flags ii sh)
						][
							tmp: keys/i keys/i: idx idx: tmp
							_BUCKET_SET_DEL_TRUE(flags ii sh)
						][
							keys/i: idx
							break?: yes
						]
						break?
					]
				]
				j = n-buckets
			]
			;@@ if h/n-buckets > new-buckets []			;-- shrink the hash table
			free-series memory/s-head h/flags
			h/flags: new-flags-node
			h/n-buckets: new-buckets
			h/n-occupied: h/size
			h/upper-bound: new-size
		]
	]

	put: func [
		node	[node!]
		key 	[red-value!]
		store?	[logic!]
		return: [red-value!]
		/local
			s h x i site last mask step keys hash n-buckets flags op
			ii sh continue? blk idx multi-key? del? indexes end ss k
	][
		s: as series! node/value
		h: as hashtable! s/offset
		multi-key?: h/indexes <> null
		if all [
			multi-key?
			not hash-value? key
		][return key]

		if h/n-occupied >= h/upper-bound [			;-- update the hash table
			n-buckets: h/n-buckets + either h/n-buckets > (h/size << 1) [-1][1]
			resize node n-buckets
		]

		s: as series! h/blk/value
		if store? [key: copy-cell key as cell! alloc-tail-unit s 2 * size? cell!]
		s: GET_BUFFER(s)
		idx: (as-integer (key - s/offset)) >> 4
		blk: s/offset

		op: either multi-key? [
			ss: as series! h/indexes/value
			indexes: as int-ptr! ss/offset
			COMP_EQUAL
		][COMP_STRICT_EQUAL]

		s: as series! h/keys/value
		keys: as int-ptr! s/offset
		s: as series! h/flags/value
		flags: as int-ptr! s/offset
		n-buckets: h/n-buckets + 1
		x:	  n-buckets
		site: n-buckets
		mask: n-buckets - 2
		hash: hash-value key multi-key?
		i: hash and mask
		_HT_CAL_FLAG_INDEX(i ii sh)
		i: i + 1									;-- 1-based index
		either _BUCKET_IS_EMPTY(flags ii sh) [x: i][
			step: 0
			last: i
			continue?: yes
			while [
				del?: _BUCKET_IS_DEL(flags ii sh)
				all [
					continue?
					_BUCKET_IS_NOT_EMPTY(flags ii sh)
					any [
						del?
						either multi-key? [true][
							not actions/compare blk + keys/i key op
						]
					]
				]
			][
				if del? [site: i]
				k: blk + (keys/i and 7FFFFFFFh)
				if all [
					multi-key?
					TYPE_OF(k) = TYPE_OF(key)
					actions/compare k key op
				][keys/i: keys/i or 80000000h]

				i: i + step and mask
				_HT_CAL_FLAG_INDEX(i ii sh)
				i: i + 1
				step: step + 1
				if i = last [x: site continue?: no]
			]
			if x = n-buckets [
				x: either all [
					_BUCKET_IS_EMPTY(flags ii sh)
					site <> n-buckets
				][site][i]
			]
		]
		_HT_CAL_FLAG_INDEX((x - 1) ii sh)
		either _BUCKET_IS_EMPTY(flags ii sh) [
			keys/x: idx
			_BUCKET_SET_BOTH_FALSE(flags ii sh)
			h/size: h/size + 1
			h/n-occupied: h/n-occupied + 1
		][
			if _BUCKET_IS_DEL(flags ii sh) [
				keys/x: idx
				_BUCKET_SET_BOTH_FALSE(flags ii sh)
				h/size: h/size + 1
			]
		]
		if multi-key? [idx: idx + 1 indexes/idx: x]
		key
	]

	get: func [
		node	 [node!]
		key		 [red-value!]
		head	 [integer!]
		skip	 [integer!]
		case?	 [logic!]
		last?	 [logic!]
		reverse? [logic!]
		return:  [red-value!]
		/local
			s h i flags last mask step keys hash n-buckets ii sh blk multi-key?
			idx last-idx op find? reverse-head k
	][
		op: either case? [COMP_STRICT_EQUAL][COMP_EQUAL]
		s: as series! node/value
		h: as hashtable! s/offset
		assert h/n-buckets > 0

		multi-key?: h/indexes <> null
		s: as series! h/blk/value
		if reverse? [
			last?: yes
		]
		last-idx: either last? [-1][(as-integer (s/tail - s/offset)) >> 4]
		blk: s/offset

		s: as series! h/keys/value
		keys: as int-ptr! s/offset
		s: as series! h/flags/value
		flags: as int-ptr! s/offset
		n-buckets: h/n-buckets + 1
		mask: n-buckets - 2
		hash: hash-value key multi-key?
		i: hash and mask
		_HT_CAL_FLAG_INDEX(i ii sh)
		i: i + 1
		last: i
		step: 0
		find?: no
		while [
			all [
				_BUCKET_IS_NOT_EMPTY(flags ii sh)
				any [
					_BUCKET_IS_DEL(flags ii sh)
					either multi-key? [true][
						not actions/compare blk + keys/i key op
					]
				]
			]
		][
			if multi-key? [
				idx: keys/i and 7FFFFFFFh
				k: blk + idx
				if all [
					_BUCKET_IS_NOT_DEL(flags ii sh)
					TYPE_OF(k) = TYPE_OF(key)
					actions/compare blk + idx key op
					idx - head % skip = 0
				][
					either reverse? [
						if all [idx < head idx > last-idx][last-idx: idx find?: yes]
					][
						if idx >= head [
							either last? [
								if idx > last-idx [last-idx: idx find?: yes]
							][
								if idx < last-idx [last-idx: idx find?: yes]
							]
						]
					]
					if all [keys/i and 80000000h = 0 find?][
						return blk + last-idx
					]
				]
			]

			i: i + step and mask
			_HT_CAL_FLAG_INDEX(i ii sh)
			i: i + 1
			step: step + 1
			if i = last [
				return either find? [blk + last-idx][null]
			]
		]

		if find? [return blk + last-idx]
		either _BUCKET_IS_EITHER(flags ii sh) [null][blk + keys/i]
	]

	delete: func [
		node	[node!]
		key		[red-value!]
		/local s h i ii sh flags indexes
	][
		s: as series! node/value
		h: as hashtable! s/offset
		assert h/n-buckets > 0

		either h/indexes = null [				;-- map!
			key: key + 1
			set-type key TYPE_NONE
		][										;-- hash!
			unless hash-value? key [exit]
			s: as series! h/flags/value
			flags: as int-ptr! s/offset
			s: as series! h/blk/value
			i: (as-integer key - s/offset) >> 4 + 1
			s: as series! h/indexes/value
			indexes: as int-ptr! s/offset
			i: indexes/i
			_HT_CAL_FLAG_INDEX(i ii sh)
			_BUCKET_SET_DEL_TRUE(flags ii sh)
		]
		h/size: h/size - 1
	]

	copy: func [
		node	[node!]
		blk		[node!]
		return: [node!]
		/local s h ss hh new
	][
		s: as series! node/value
		h: as hashtable! s/offset

		new: copy-series s
		ss: as series! new/value
		hh: as hashtable! ss/offset

		hh/flags: copy-series as series! h/flags/value
		hh/keys: copy-series as series! h/keys/value
		hh/blk: blk
		new
	]

	clear: func [
		node	[node!]
		head	[integer!]
		size	[integer!]
		/local s h flags n i ii sh indexes
	][
		if zero? size [exit]
		s: as series! node/value
		h: as hashtable! s/offset

		h/n-occupied: h/n-occupied - size
		h/size: h/size - size
		s: as series! h/flags/value
		flags: as int-ptr! s/offset
		s: as series! h/indexes/value
		indexes: (as int-ptr! s/offset) + head
		until [
			i: indexes/value
			if i <> -1 [
				i: i - 1
				_HT_CAL_FLAG_INDEX(i ii sh)
				_BUCKET_SET_DEL_TRUE(flags ii sh)
				indexes/value: -1
			]
			indexes: indexes + 1
			size: size - 1
			zero? size
		]
	]

	refresh: func [
		node	[node!]
		offset	[integer!]
		head	[integer!]
		/local s h indexes i end keys index part flags ii sh
	][
		s: as series! node/value
		h: as hashtable! s/offset
		assert h/indexes <> null
		assert h/n-buckets > 0

		s: as series! h/indexes/value
		indexes: as int-ptr! s/offset
		end: as int-ptr! s/tail
		if indexes = end [exit]
		s: as series! h/keys/value
		keys: as int-ptr! s/offset
		ii: head						;-- save head

		while [
			index: indexes + head
			index < end
		][
			i: index/value
			unless i = -1 [keys/i: keys/i + offset]
			head: head + 1
		]

		if negative? offset [			;-- need to delete some entries
			head: ii					;-- restore head
			part: offset
			s: as series! h/flags/value
			flags: as int-ptr! s/offset
			while [negative? part][
				index: indexes + head + part
				i: index/value - 1
				_HT_CAL_FLAG_INDEX(i ii sh)
				_BUCKET_SET_DEL_TRUE(flags ii sh)
				h/size: h/size - 1
				part: part + 1
			]
			if indexes + head < end [
				move-memory
					as byte-ptr! (indexes + head + offset)
					as byte-ptr! indexes + head
					as-integer end - (indexes + head + 1)
			]
			s: as series! h/indexes/value
			s/tail: as red-value! end + offset
		]
	]
]
