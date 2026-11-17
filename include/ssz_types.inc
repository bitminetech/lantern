/*
 * Macros that define SSZ types and write asm-ssz type descriptors.
 * The layout rules are asm-ssz's (asm-ssz docs/reference/serialization.md,
 * Type Value and Type TypeDescriptor), with its constants from ssz.inc.
 *
 * Defining a type T sets these symbols:
 *   T__kind    SSZ_KIND_* of the type
 *   T__len     byte width, vector length, list limit or field count
 *   T__ssz     SSZ size of a fixed size type, else 0
 *   T__mem     bytes the type takes in place: 16 for a variable size type
 *   T__align   alignment it takes in place
 *   T__fixed   in a value of the type, where its parts start
 *   T__chunks  Merkle leaves at the type's own level
 *   T__work    work bytes of ssz_level_root for the type
 *   T__basic   1 for Uint and Boolean, else 0
 * A container field F of T also sets T_F (its offset in a value of T),
 * T_F__mem (the bytes it takes in place), T_F__ssz (its offset in the SSZ
 * fixed part) and T_F__var (1 when its type has a variable size).
 *
 * The macros SSZ_UINT to SSZ_END define types under the names that the last
 * SSZ_NAMES set: SSZ_NAMES PRE_ puts PRE_ before each type name, so that one
 * object can hold the layouts of two forks; SSZ_NAMES with no prefix gives the
 * names as written. Each passes its names to the SSZ_DEF_ macro of its kind.
 */

/* sym = ceil(log2(n)), and 0 when n is 1 or less. */
.macro SSZ_DEPTH sym, n
    .set \sym, 0
    .irp k, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62
    .if (\n) > (1 << (\k - 1))
    .set \sym, \k
    .endif
    .endr
.endm

/* T__work for a type with no child values among its leaves. */
.macro SSZ_WORK_LEAVES T
    SSZ_DEPTH \T\()__depth, \T\()__chunks
    .set \T\()__work, 8 + 32 * (\T\()__depth + 2)
.endm

/* T__work for a type whose leaves are child values; child is the one with the most work. */
.macro SSZ_WORK_CHILDREN T, work
    SSZ_DEPTH \T\()__depth, \T\()__chunks
    .set \T\()__work, 8 + 32 * (\T\()__depth + 2) + 8 + SSZ_LEVEL_SIZE + (\work)
.endm

.set SSZ_LEVEL_SIZE, 96             /* asm-ssz: bytes of a Level */
.set SSZ_LIST_FIXED, 24             /* asm-ssz: size, then the PartRef */

/* Uint of width 1, 4, 8 or 32 bytes. */
.macro SSZ_DEF_UINT T, width
    .set \T\()__kind, SSZ_KIND_UINT
    .set \T\()__len, \width
    .set \T\()__ssz, \width
    .set \T\()__mem, \width
    .if \width > 8
    .set \T\()__align, 8
    .else
    .set \T\()__align, \width
    .endif
    .set \T\()__fixed, \width
    .set \T\()__chunks, 1
    .set \T\()__basic, 1
    SSZ_WORK_LEAVES \T
.endm

.macro SSZ_DEF_BOOLEAN T
    .set \T\()__kind, SSZ_KIND_BOOLEAN
    .set \T\()__len, 1
    .set \T\()__ssz, 1
    .set \T\()__mem, 1
    .set \T\()__align, 1
    .set \T\()__fixed, 1
    .set \T\()__chunks, 1
    .set \T\()__basic, 1
    SSZ_WORK_LEAVES \T
.endm

/* ByteVector[n]. */
.macro SSZ_DEF_BYTE_VECTOR T, n
    .set \T\()__kind, SSZ_KIND_BYTE_VECTOR
    .set \T\()__len, \n
    .set \T\()__ssz, \n
    .set \T\()__mem, \n
    .set \T\()__align, 1
    .set \T\()__fixed, \n
    .set \T\()__chunks, ((\n) + 31) / 32
    .set \T\()__basic, 0
    SSZ_WORK_LEAVES \T
.endm

/* ByteList[limit]. */
.macro SSZ_DEF_BYTE_LIST T, limit
    .set \T\()__kind, SSZ_KIND_BYTE_LIST
    .set \T\()__len, \limit
    .set \T\()__ssz, 0
    .set \T\()__mem, SSZ_PART_REF_SIZE
    .set \T\()__align, 8
    .set \T\()__fixed, SSZ_LIST_FIXED
    .set \T\()__chunks, ((\limit) + 31) / 32
    .set \T\()__basic, 0
    SSZ_WORK_LEAVES \T
.endm

/* BitVector[n]. */
.macro SSZ_DEF_BIT_VECTOR T, n
    .set \T\()__kind, SSZ_KIND_BIT_VECTOR
    .set \T\()__len, \n
    .set \T\()__ssz, ((\n) + 7) / 8
    .set \T\()__mem, ((\n) + 7) / 8
    .set \T\()__align, 1
    .set \T\()__fixed, ((\n) + 7) / 8
    .set \T\()__chunks, ((\n) + 255) / 256
    .set \T\()__basic, 0
    SSZ_WORK_LEAVES \T
.endm

/* BitList[limit]. */
.macro SSZ_DEF_BIT_LIST T, limit
    .set \T\()__kind, SSZ_KIND_BIT_LIST
    .set \T\()__len, \limit
    .set \T\()__ssz, 0
    .set \T\()__mem, SSZ_PART_REF_SIZE
    .set \T\()__align, 8
    .set \T\()__fixed, SSZ_LIST_FIXED
    .set \T\()__chunks, ((\limit) + 255) / 256
    .set \T\()__basic, 0
    SSZ_WORK_LEAVES \T
.endm

/* Chunks of n entries of E: packed when E is basic, else one per entry. */
.macro SSZ_ENTRY_CHUNKS T, E, n
    .if \E\()__basic
    .set \T\()__chunks, ((\n) * \E\()__ssz + 31) / 32
    SSZ_WORK_LEAVES \T
    .else
    .set \T\()__chunks, \n
    SSZ_WORK_CHILDREN \T, \E\()__work
    .endif
.endm

/* Vector[E, n]. */
.macro SSZ_DEF_VECTOR T, E, n
    .set \T\()__kind, SSZ_KIND_VECTOR
    .set \T\()__len, \n
    .if \E\()__ssz
    .set \T\()__ssz, (\n) * \E\()__ssz
    .set \T\()__mem, (\n) * \E\()__mem
    .set \T\()__align, \E\()__align
    .set \T\()__fixed, (\n) * \E\()__mem
    .else
    .set \T\()__ssz, 0
    .set \T\()__mem, SSZ_PART_REF_SIZE
    .set \T\()__align, 8
    .set \T\()__fixed, SSZ_LIST_FIXED
    .endif
    .set \T\()__basic, 0
    SSZ_ENTRY_CHUNKS \T, \E, \n
.endm

/* List[E, limit]. */
.macro SSZ_DEF_LIST T, E, limit
    .set \T\()__kind, SSZ_KIND_LIST
    .set \T\()__len, \limit
    .set \T\()__ssz, 0
    .set \T\()__mem, SSZ_PART_REF_SIZE
    .set \T\()__align, 8
    .set \T\()__fixed, SSZ_LIST_FIXED
    .set \T\()__basic, 0
    SSZ_ENTRY_CHUNKS \T, \E, \limit
.endm

/*
 * Container T: SSZ_CONTAINER T, var; then SSZ_FIELD for each field in spec
 * order; then SSZ_END T. var is 1 when a field has a variable size; SSZ_END
 * checks it.
 */
.macro SSZ_DEF_CONTAINER T, var
    .set \T\()__kind, SSZ_KIND_CONTAINER
    .set \T\()__var, \var
    .set \T\()__seen_var, 0
    .set \T\()__at, 8 * (\var)
    .set \T\()__ssz_at, 0
    .set \T\()__largest, 1
    .set \T\()__len, 0
    .set \T\()__most_work, 0
    .set \T\()__basic, 0
.endm

.macro SSZ_DEF_FIELD T, name, F
    .set \T\()__at, (\T\()__at + \F\()__align - 1) / \F\()__align * \F\()__align
    .set \T\()_\name, \T\()__at
    .set \T\()_\name\()__mem, \F\()__mem
    .set \T\()_\name\()__ssz, \T\()__ssz_at
    .set \T\()__at, \T\()__at + \F\()__mem
    .if \F\()__ssz
    .set \T\()_\name\()__var, 0
    .set \T\()__ssz_at, \T\()__ssz_at + \F\()__ssz
    .else
    .set \T\()_\name\()__var, 1
    .set \T\()__seen_var, 1
    .set \T\()__ssz_at, \T\()__ssz_at + 4
    .endif
    .if \F\()__align > \T\()__largest
    .set \T\()__largest, \F\()__align
    .endif
    .if \F\()__work > \T\()__most_work
    .set \T\()__most_work, \F\()__work
    .endif
    .set \T\()__len, \T\()__len + 1
.endm

.macro SSZ_DEF_END T
    .if \T\()__seen_var != \T\()__var
    .error "SSZ_CONTAINER: the variable size flag is wrong"
    .endif
    .set \T\()__chunks, \T\()__len
    .if \T\()__var
    .set \T\()__ssz, 0
    .set \T\()__mem, SSZ_PART_REF_SIZE
    .set \T\()__align, 8
    .set \T\()__fixed, (\T\()__at + 7) / 8 * 8
    .else
    .set \T\()__ssz, \T\()__ssz_at
    .set \T\()__align, \T\()__largest
    .set \T\()__mem, (\T\()__at + \T\()__largest - 1) / \T\()__largest * \T\()__largest
    .set \T\()__fixed, \T\()__mem
    .endif
    SSZ_WORK_CHILDREN \T, \T\()__most_work
.endm

/* The type macros, with prefix p before each type name. SSZ_NAMES_SET marks a first definition. */
.macro SSZ_NAMES p
.ifdef SSZ_NAMES_SET
.purgem SSZ_UINT
.purgem SSZ_BOOLEAN
.purgem SSZ_BYTE_VECTOR
.purgem SSZ_BYTE_LIST
.purgem SSZ_BIT_VECTOR
.purgem SSZ_BIT_LIST
.purgem SSZ_VECTOR
.purgem SSZ_LIST
.purgem SSZ_CONTAINER
.purgem SSZ_FIELD
.purgem SSZ_END
.endif
.set SSZ_NAMES_SET, 1
.macro SSZ_UINT T, width
    SSZ_DEF_UINT \p\()\T, \width
.endm
.macro SSZ_BOOLEAN T
    SSZ_DEF_BOOLEAN \p\()\T
.endm
.macro SSZ_BYTE_VECTOR T, n
    SSZ_DEF_BYTE_VECTOR \p\()\T, \n
.endm
.macro SSZ_BYTE_LIST T, limit
    SSZ_DEF_BYTE_LIST \p\()\T, \limit
.endm
.macro SSZ_BIT_VECTOR T, n
    SSZ_DEF_BIT_VECTOR \p\()\T, \n
.endm
.macro SSZ_BIT_LIST T, limit
    SSZ_DEF_BIT_LIST \p\()\T, \limit
.endm
.macro SSZ_VECTOR T, E, n
    SSZ_DEF_VECTOR \p\()\T, \p\()\E, \n
.endm
.macro SSZ_LIST T, E, limit
    SSZ_DEF_LIST \p\()\T, \p\()\E, \limit
.endm
.macro SSZ_CONTAINER T, var
    SSZ_DEF_CONTAINER \p\()\T, \var
.endm
.macro SSZ_FIELD T, name, F
    SSZ_DEF_FIELD \p\()\T, \name, \p\()\F
.endm
.macro SSZ_END T
    SSZ_DEF_END \p\()\T
.endm
.endm

/*
 * Descriptor of root type T: SSZ_DESC T, nodes, fields; then nodes SSZ_NODE
 * lines, the first for T itself; then fields SSZ_DFIELD lines; then
 * SSZ_DESC_END T, nodes, fields, which checks both counts. The label is
 * lantern_type_T. Node indices are written by hand: a type has a lower index
 * than every type inside it, and a container's fields are consecutive.
 */
.macro SSZ_DESC T, nodes, fields
    .p2align 3
lantern_type_\T:
    .quad SSZ_DESC_FIXED + (\nodes) * SSZ_NODE_STRIDE + (\fields) * SSZ_FIELD_STRIDE
    .quad SSZ_DESC_FIXED
    .quad \nodes
    .quad SSZ_DESC_FIXED + (\nodes) * SSZ_NODE_STRIDE
    .quad \fields
    .quad 0
.endm

/* One TypeNode for type T. element: the element's node, or a container's first field record. */
.macro SSZ_NODE T, element=0
    .quad \T\()__kind, \T\()__len, \element, \T\()__ssz, \T\()__mem, \T\()__align
    .quad \T\()__fixed, \T\()__chunks, SSZ_SCR_WORK + \T\()__work
.endm

/* One TypeField: field name of container T, of the type at node index node. */
.macro SSZ_DFIELD node, T, name
    .quad \node, \T\()_\name, \T\()_\name\()__ssz, \T\()_\name\()__var
.endm

.macro SSZ_DESC_END T, nodes, fields
    .if (. - lantern_type_\T) != SSZ_DESC_FIXED + (\nodes) * SSZ_NODE_STRIDE + (\fields) * SSZ_FIELD_STRIDE
    .error "SSZ_DESC_END: the node or field count is wrong"
    .endif
.endm
