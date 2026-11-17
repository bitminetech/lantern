/*
 * lantern constants, in assembler syntax.
 * Spec constants are those of consensus-specs v1.7.0-beta.4 (aa16bb4) that
 * are neither preset nor config values. A 4-byte DomainType or prefix is the
 * little endian number of its bytes, so a 4-byte store writes the spec bytes.
 */

/* ------------------------------------------------------------ Status codes (ARCHITECTURE.md section 6) */

.set LANTERN_OK, 0
.set LANTERN_BUFFER_TOO_SMALL, 1

/* ------------------------------------------------------------ phase0 */

.set UINT64_MAX, 0xffffffffffffffff
.set UINT64_MAX_SQRT, 4294967295
.set GENESIS_SLOT, 0
.set GENESIS_EPOCH, 0
.set FAR_FUTURE_EPOCH, 0xffffffffffffffff
.set BASE_REWARDS_PER_EPOCH, 4
.set JUSTIFICATION_BITS_LENGTH, 4
.set BLS_WITHDRAWAL_PREFIX, 0x00
.set ETH1_ADDRESS_WITHDRAWAL_PREFIX, 0x01
.set DOMAIN_BEACON_PROPOSER, 0x00000000
.set DOMAIN_BEACON_ATTESTER, 0x00000001
.set DOMAIN_RANDAO, 0x00000002
.set DOMAIN_DEPOSIT, 0x00000003
.set DOMAIN_VOLUNTARY_EXIT, 0x00000004
.set DOMAIN_SELECTION_PROOF, 0x00000005
.set DOMAIN_AGGREGATE_AND_PROOF, 0x00000006
.set DOMAIN_APPLICATION_MASK, 0x01000000
.set DEPOSIT_CONTRACT_TREE_DEPTH, 32
.set BASIS_POINTS, 10000
.set NODE_ID_BITS, 256
.set MAX_CONCURRENT_REQUESTS, 2
.set TARGET_AGGREGATORS_PER_COMMITTEE, 16
.set ETH_TO_GWEI, 1000000000
.set SAFETY_DECAY, 10
/* A config value that sets the length of the Attnets type; lantern requires 64. */
.set ATTESTATION_SUBNET_COUNT, 64

/* ------------------------------------------------------------ altair */

.set TIMELY_SOURCE_FLAG_INDEX, 0
.set TIMELY_TARGET_FLAG_INDEX, 1
.set TIMELY_HEAD_FLAG_INDEX, 2
.set TIMELY_SOURCE_WEIGHT, 14
.set TIMELY_TARGET_WEIGHT, 26
.set TIMELY_HEAD_WEIGHT, 14
.set SYNC_REWARD_WEIGHT, 2
.set PROPOSER_WEIGHT, 8
.set WEIGHT_DENOMINATOR, 64
.set DOMAIN_SYNC_COMMITTEE, 0x00000007
.set DOMAIN_SYNC_COMMITTEE_SELECTION_PROOF, 0x00000008
.set DOMAIN_CONTRIBUTION_AND_PROOF, 0x00000009
.set TARGET_AGGREGATORS_PER_SYNC_SUBCOMMITTEE, 16
.set SYNC_COMMITTEE_SUBNET_COUNT, 4

/* ------------------------------------------------------------ bellatrix */

.set SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY, 128
.set PAYLOAD_STATUS_VALID, 0
.set PAYLOAD_STATUS_INVALIDATED, 1
.set PAYLOAD_STATUS_NOT_VALIDATED, 2

/* ------------------------------------------------------------ capella */

.set DOMAIN_BLS_TO_EXECUTION_CHANGE, 0x0000000a

/* ------------------------------------------------------------ deneb */

.set VERSIONED_HASH_VERSION_KZG, 0x01
.set BYTES_PER_FIELD_ELEMENT, 32

/* ------------------------------------------------------------ electra */

.set UNSET_DEPOSIT_REQUESTS_START_INDEX, 0xffffffffffffffff
.set FULL_EXIT_REQUEST_AMOUNT, 0
.set COMPOUNDING_WITHDRAWAL_PREFIX, 0x02
.set DEPOSIT_REQUEST_TYPE, 0x00
.set WITHDRAWAL_REQUEST_TYPE, 0x01
.set CONSOLIDATION_REQUEST_TYPE, 0x02

/* ------------------------------------------------------------ Config (docs/reference/state-transition.md, Type Config) */

/* Fork versions are 4-byte Versions in the low bytes of a u64. BLOB_SCHEDULE holds up to 32 entries. */
.set CONFIG_GENESIS_FORK_VERSION, 0
.set CONFIG_ALTAIR_FORK_VERSION, 8
.set CONFIG_ALTAIR_FORK_EPOCH, 16
.set CONFIG_BELLATRIX_FORK_VERSION, 24
.set CONFIG_BELLATRIX_FORK_EPOCH, 32
.set CONFIG_CAPELLA_FORK_VERSION, 40
.set CONFIG_CAPELLA_FORK_EPOCH, 48
.set CONFIG_DENEB_FORK_VERSION, 56
.set CONFIG_DENEB_FORK_EPOCH, 64
.set CONFIG_ELECTRA_FORK_VERSION, 72
.set CONFIG_ELECTRA_FORK_EPOCH, 80
.set CONFIG_FULU_FORK_VERSION, 88
.set CONFIG_FULU_FORK_EPOCH, 96
.set CONFIG_SLOT_DURATION_MS, 104
.set CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY, 112
.set CONFIG_SHARD_COMMITTEE_PERIOD, 120
.set CONFIG_EJECTION_BALANCE, 128
.set CONFIG_MIN_PER_EPOCH_CHURN_LIMIT, 136
.set CONFIG_CHURN_LIMIT_QUOTIENT, 144
.set CONFIG_MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT, 152
.set CONFIG_MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, 160
.set CONFIG_MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, 168
.set CONFIG_INACTIVITY_SCORE_BIAS, 176
.set CONFIG_INACTIVITY_SCORE_RECOVERY_RATE, 184
.set CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA, 192
.set CONFIG_PROPOSER_SCORE_BOOST, 200
.set CONFIG_REORG_HEAD_WEIGHT_THRESHOLD, 208
.set CONFIG_REORG_PARENT_WEIGHT_THRESHOLD, 216
.set CONFIG_REORG_MAX_EPOCHS_SINCE_FINALIZATION, 224
.set CONFIG_PROPOSER_REORG_CUTOFF_BPS, 232
.set CONFIG_ATTESTATION_DUE_BPS, 240
.set CONFIG_AGGREGATE_DUE_BPS, 248
.set CONFIG_SYNC_MESSAGE_DUE_BPS, 256
.set CONFIG_CONTRIBUTION_DUE_BPS, 264
.set CONFIG_SAMPLES_PER_SLOT, 272
.set CONFIG_NUMBER_OF_CUSTODY_GROUPS, 280
.set CONFIG_CUSTODY_REQUIREMENT, 288
.set CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT, 296
.set CONFIG_MAX_REQUEST_BLOCKS_DENEB, 304
.set CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS, 312
.set CONFIG_MAX_PAYLOAD_SIZE, 320
.set CONFIG_MAXIMUM_GOSSIP_CLOCK_DISPARITY, 328
.set CONFIG_SUBNETS_PER_NODE, 336
.set CONFIG_EPOCHS_PER_SUBNET_SUBSCRIPTION, 344
.set CONFIG_ATTESTATION_SUBNET_EXTRA_BITS, 352
.set CONFIG_VALIDATOR_CUSTODY_REQUIREMENT, 360
.set CONFIG_BALANCE_PER_ADDITIONAL_CUSTODY_GROUP, 368
.set CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS, 376
.set CONFIG_BLOB_SCHEDULE_COUNT, 384
.set CONFIG_BLOB_SCHEDULE, 392          /* entries of (EPOCH, MAX_BLOBS_PER_BLOCK), 16 bytes each */
.set CONFIG_BLOB_SCHEDULE_MAX, 32
.set CONFIG_MAX_BLOBS_PER_BLOCK, 392 + 16 * 32  /* deneb's limit, after the schedule */
.set CONFIG_SIZE, 392 + 16 * 32 + 8

/* ------------------------------------------------------------ Results of spec checks */

/*
 * A failed spec check. A function that changes no state returns the code as
 * its status; a function that changes a state returns LANTERN_OK and writes
 * the code to its result output. 0 in a result means every check held.
 */
.set LANTERN_VALID, 0
.set LANTERN_INVALID_BLOCK_ROOT_SLOT, 2         /* get_block_root_at_slot: slot out of range */
.set LANTERN_INVALID_PARTICIPATION_EPOCH, 3     /* get_unslashed_participating_indices: epoch not previous or current */
.set LANTERN_INVALID_OVERFLOW, 4                /* a Uint64 result of the spec leaves 0 to 2^64 - 1 */
.set LANTERN_INVALID_SHUFFLED_INDEX, 5          /* compute_shuffled_index: index not below index_count */
.set LANTERN_INVALID_NO_INDICES, 6              /* compute_proposer_index, get_next_sync_committee_indices: no candidates */
.set LANTERN_INVALID_AGGREGATE_PUBKEYS, 7       /* eth_aggregate_pubkeys: a public key does not validate */
.set LANTERN_INVALID_BLOCK_SLOT, 8              /* process_block_header: block.slot is not state.slot */
.set LANTERN_INVALID_BLOCK_OLDER, 9             /* process_block_header: block.slot is not after the latest header */
.set LANTERN_INVALID_PROPOSER_INDEX, 10         /* process_block_header: not the expected proposer */
.set LANTERN_INVALID_PARENT_ROOT, 11            /* process_block_header: parent_root is not the latest header's root */
.set LANTERN_INVALID_PROPOSER_SLASHED, 12       /* process_block_header: the proposer is slashed */
.set LANTERN_INVALID_WITHDRAWALS_LIMIT, 13      /* get_*_withdrawals: prior withdrawals over the limit */
.set LANTERN_INVALID_WITHDRAWALS, 14            /* process_withdrawals: the payload's withdrawals are not the expected ones */
.set LANTERN_INVALID_PAYLOAD_PARENT_HASH, 15    /* process_execution_payload: parent_hash */
.set LANTERN_INVALID_PAYLOAD_PREV_RANDAO, 16    /* process_execution_payload: prev_randao */
.set LANTERN_INVALID_PAYLOAD_TIMESTAMP, 17      /* process_execution_payload: timestamp */
.set LANTERN_INVALID_BLOB_COUNT, 18             /* process_execution_payload: too many blob commitments */
.set LANTERN_INVALID_PAYLOAD, 19                /* process_execution_payload: the execution engine rejects the payload */
.set LANTERN_INVALID_RANDAO_REVEAL, 20          /* process_randao: the reveal's signature */
.set LANTERN_INVALID_DEPOSITS, 21               /* process_operations: the body's number of deposits */
.set LANTERN_INVALID_PROPOSER_SLASHING, 22      /* process_proposer_slashing: a check */
.set LANTERN_INVALID_ATTESTER_SLASHING, 23      /* process_attester_slashing, on_attester_slashing: a check */
.set LANTERN_INVALID_ATTESTATION, 24            /* process_attestation: a check; on_attestation: the indexed attestation */
.set LANTERN_INVALID_SOURCE, 25                 /* get_attestation_participation_flag_indices: the source is not justified */
.set LANTERN_INVALID_VOLUNTARY_EXIT, 26         /* process_voluntary_exit: a check */
.set LANTERN_INVALID_BLS_CHANGE, 27             /* process_bls_to_execution_change: a check */
.set LANTERN_INVALID_SYNC_AGGREGATE, 28         /* process_sync_aggregate: the signature */
.set LANTERN_INVALID_STATE_ROOT, 29             /* state_transition: block.state_root */
.set LANTERN_INVALID_SLOT, 30                   /* process_slots: slot is not after state.slot */
.set LANTERN_INVALID_VALIDATOR_INDEX, 31        /* an index from the block names no validator */
.set LANTERN_INVALID_BLOCK_SIGNATURE, 32        /* state_transition: the block's signature */
.set LANTERN_INVALID_UNKNOWN_BLOCK, 33          /* fork choice: a root the spec looks up is not in store.blocks */
.set LANTERN_INVALID_FUTURE_SLOT, 34            /* on_block, validate_on_attestation: the store's time is before the slot */
.set LANTERN_INVALID_NOT_FINALIZED, 35          /* on_block: not after the finalized slot, or not a descendant of the finalized block */
.set LANTERN_INVALID_DATA_UNAVAILABLE, 36       /* on_block: is_data_available is false */
.set LANTERN_INVALID_ATTESTATION_TARGET, 37     /* validate_on_attestation: the target epoch or root */
.set LANTERN_INVALID_ATTESTATION_SLOT, 38       /* validate_on_attestation: the head vote's block is after the slot */
.set LANTERN_INVALID_ANCHOR, 39                 /* get_forkchoice_store: anchor_block.state_root is not the anchor state's root */
.set LANTERN_INVALID_PROPOSER_BOOST, 40         /* get_proposer_head: the head holds the proposer boost */

/*
 * Not a spec check: a fork choice function that reads the justified checkpoint
 * state finds the store's balances from another checkpoint (docs/reference/fork-choice.md).
 */
.set LANTERN_NEED_JUSTIFIED_STATE, 41

.set LANTERN_INVALID_CUSTODY_GROUP, 42          /* get_custody_groups, compute_columns_for_custody_group: above NUMBER_OF_CUSTODY_GROUPS */
.set LANTERN_INVALID_PARENT_PAYLOAD, 43         /* on_block: the parent's payload is INVALIDATED (bellatrix optimistic-sync.md) */
.set LANTERN_GOSSIP_IGNORE, 44                  /* a gossip validation function: an [IGNORE] check fails (GossipIgnore) */
.set LANTERN_GOSSIP_REJECT, 45                  /* a gossip validation function: a [REJECT] check fails (GossipReject) */
.set LANTERN_INVALID_DEPOSIT, 46                /* process_deposit: the deposit's Merkle proof */

/* ------------------------------------------------------------ Scratch (docs/reference/helpers.md, Type Scratch) */

.set LANTERN_SCRATCH_FIXED, 1048576       /* bytes of scratch for fixed size work, on top of the index lists */

/* ------------------------------------------------------------ Lists of u64 (docs/reference/helpers.md, Type IndexList) */

.set LIST_SIZE, 0          /* total buffer size */
.set LIST_OFFSET, 8        /* where the entries start: 24 */
.set LIST_COUNT, 16        /* number of entries */
.set LIST_FIXED, 24        /* the entries start here */

/* ------------------------------------------------------------ Fork choice (docs/reference/fork-choice.md) */

.set NODE_NONE, 0xffffffffffffffff     /* no node: a parent outside the store, or no latest message */

/* Store */
.set Store_time_ms, 8
.set Store_genesis_time_ms, 16
.set Store_justified_checkpoint, 24
.set Store_finalized_checkpoint, 64
.set Store_unrealized_justified_checkpoint, 104
.set Store_unrealized_finalized_checkpoint, 144
.set Store_proposer_boost_root, 184
.set Store_balances_checkpoint, 216
.set Store_balances_total, 256
.set Store_blocks, 264                 /* PartRef of BlockNode */
.set Store_validators, 280             /* PartRef of StoreValidator */
.set Store_config, 296
.set STORE_FIXED, 296 + CONFIG_SIZE

/* BlockNode */
.set BlockNode_root, 0
.set BlockNode_parent_root, 32
.set BlockNode_slot, 64
.set BlockNode_proposer_index, 72
.set BlockNode_parent, 80
.set BlockNode_justified_checkpoint, 88
.set BlockNode_unrealized_justified_checkpoint, 128
.set BlockNode_timely, 168
.set BlockNode_block_hash, 176         /* body.execution_payload.block_hash */
.set BlockNode_payload_status, 208     /* PAYLOAD_STATUS_*: the execution engine's answer for the payload */
.set BlockNode__mem, 216

/* StoreValidator */
.set StoreValidator_latest_epoch, 0
.set StoreValidator_latest_node, 8
.set StoreValidator_effective_balance, 16
.set StoreValidator_flags, 24
.set StoreValidator__mem, 32
.set STORE_ACTIVE_UNSLASHED, 1         /* active at the justified state's epoch and not slashed */
.set STORE_EQUIVOCATING, 2             /* in store.equivocating_indices */
.set STORE_IN_REGISTRY, 4              /* below the justified state's validator count */

/* StoreRoom */
.set StoreRoom_nodes, 0
.set StoreRoom_validators, 8

/* BlockOptions */
.set BlockOptions_payload_status, 0   /* PAYLOAD_STATUS_*: the execution engine's answer for the payload */
.set BlockOptions_data_available, 8

/* ------------------------------------------------------------ Gossip (docs/reference/networking.md) */

/* Seen */
.set Seen_keys, 8                      /* PartRef of SeenKey */
.set Seen_bits, 24                     /* PartRef of SeenBits */
.set Seen_blocks, 40                   /* PartRef of SeenBlock */
.set Seen_headers, 56                  /* PartRef of SeenHeader, back to back */
.set Seen_header_bytes, 72             /* bytes of the headers part in use */
.set SEEN_FIXED, 80

/* SeenRoom */
.set SeenRoom_keys, 0
.set SeenRoom_bits, 8
.set SeenRoom_blocks, 16
.set SeenRoom_header_bytes, 24

/* SeenKey: the sets of the spec's Seen whose entries are numbers */
.set SeenKey_kind, 0
.set SeenKey_a, 8
.set SeenKey_b, 16
.set SeenKey_c, 24
.set SeenKey__mem, 32
.set SEEN_PROPOSER_SLOT, 1             /* proposer_slots: (slot, proposer index) */
.set SEEN_AGGREGATOR_EPOCH, 2          /* aggregator_epochs: (epoch, aggregator index) */
.set SEEN_VOLUNTARY_EXIT, 3            /* voluntary_exit_indices */
.set SEEN_PROPOSER_SLASHING, 4         /* proposer_slashing_indices */
.set SEEN_ATTESTER_SLASHING, 5         /* attester_slashing_indices */
.set SEEN_ATTESTATION, 6               /* attestation_validator_epochs: (epoch, validator index) */
.set SEEN_SYNC_CONTRIBUTION, 7         /* sync_contribution_aggregator_slots: (slot, aggregator index, subcommittee index) */
.set SEEN_SYNC_MESSAGE, 8              /* sync_message_validator_slots: (slot, validator index, subnet ID) */
.set SEEN_BLS_CHANGE, 9                /* bls_to_execution_change_indices */
.set SEEN_DATA_COLUMN, 10              /* data_column_sidecar_tuples: (slot, proposer index, column index) */

/* SeenBits: aggregate_data_roots and sync_contribution_data */
.set SeenBits_kind, 0
.set SeenBits_root, 8
.set SeenBits_a, 40
.set SeenBits_b, 48
.set SeenBits_length, 56
.set SeenBits_bits, 64
.set SeenBits__mem, 320
.set SEEN_BITS_BYTES, 256              /* MAX_VALIDATORS_PER_COMMITTEE bits */
.set SEEN_AGGREGATE, 1                 /* (data root, committee index) */
.set SEEN_CONTRIBUTION, 2              /* (beacon_block_root, slot, subcommittee index) */

/* SeenBlock: a root of store.blocks without a post-state */
.set SeenBlock_root, 0
.set SeenBlock_payload_status, 32
.set SeenBlock__mem, 40

/* SeenHeader: partial_data_column_headers */
.set SeenHeader_block_root, 0
.set SeenHeader_header_root, 32
.set SeenHeader_header, 64

/*
 * Scratch of lantern_verify_data_column_sidecar_kzg_proofs for a sidecar of n
 * commitments: DA_SCRATCH_FIXED + n * DA_SCRATCH_PER_BLOB. Its four input lists
 * (commitments, cell indices, cells, proofs) and asm-crypto's own scratch.
 * Needs asm-crypto's kzg.inc first.
 */
.set DA_SCRATCH_FIXED, 8 + 4 * LIST_FIXED + CRYPTO_KZG_SCRATCH
.set DA_SCRATCH_PER_BLOB, 48 + 8 + CRYPTO_KZG_CELL_SIZE + 48 + CRYPTO_KZG_SCRATCH_PER_ENTRY
