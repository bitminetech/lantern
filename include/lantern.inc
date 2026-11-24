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
.set CONFIG_MIN_GENESIS_TIME, 392 + 16 * 32 + 8
.set CONFIG_MIN_GENESIS_ACTIVE_VALIDATOR_COUNT, 392 + 16 * 32 + 16
.set CONFIG_GENESIS_DELAY, 392 + 16 * 32 + 24
.set CONFIG_TERMINAL_TOTAL_DIFFICULTY, 392 + 16 * 32 + 32          /* Uint256, little endian */
.set CONFIG_TERMINAL_BLOCK_HASH, 392 + 16 * 32 + 64                /* Hash32 */
.set CONFIG_TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH, 392 + 16 * 32 + 96
.set CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE, 392 + 16 * 32 + 104
.set CONFIG_BLOB_SIDECAR_SUBNET_COUNT, 392 + 16 * 32 + 112
.set CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA, 392 + 16 * 32 + 120
.set CONFIG_MAX_REQUEST_BLOCKS, 392 + 16 * 32 + 128
.set CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY, 392 + 16 * 32 + 136   /* DomainType, 4 bytes */
.set CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY, 392 + 16 * 32 + 144     /* DomainType, 4 bytes */
.set CONFIG_STATE_CACHE, 392 + 16 * 32 + 152    /* the address of a StateCache, or 0 (docs/reference/state.md) */
.set CONFIG_COMMITTEE_CACHE, 392 + 16 * 32 + 160    /* the address of a CommitteeCache, or 0 (block-processing.md) */
.set CONFIG_PUBKEY_CACHE, 392 + 16 * 32 + 168   /* the address of a PubkeyCache, or 0 (block-processing.md) */
.set CONFIG_SECONDS_PER_ETH1_BLOCK, 392 + 16 * 32 + 176
.set CONFIG_ETH1_FOLLOW_DISTANCE, 392 + 16 * 32 + 184
.set CONFIG_DEPOSIT_CHAIN_ID, 392 + 16 * 32 + 192
.set CONFIG_DEPOSIT_NETWORK_ID, 392 + 16 * 32 + 200
.set CONFIG_ATTESTATION_SUBNET_COUNT, 392 + 16 * 32 + 208
.set CONFIG_DEPOSIT_CONTRACT_ADDRESS, 392 + 16 * 32 + 216    /* 20 bytes, then 12 zero bytes */
.set CONFIG_PRESET_BASE, 392 + 16 * 32 + 248                 /* a text: its length, then 64 bytes */
.set CONFIG_CONFIG_NAME, 392 + 16 * 32 + 320                 /* a text: its length, then 64 bytes */
.set CONFIG_TEXT_MAX, 64
.set CONFIG_SIZE, 392 + 16 * 32 + 392


/* CommitteeCache and CommitteeEntry (docs/reference/block-processing.md). */
.set CommitteeCache_size, 0
.set CommitteeCache_validators, 8
.set CommitteeCache_next, 16
.set CommitteeCache_entries, 24
.set COMMITTEE_CACHE_FIXED, 24
.set COMMITTEE_CACHE_ENTRIES, 4
.set CommitteeEntry_valid, 0
.set CommitteeEntry_epoch, 8
.set CommitteeEntry_count, 16
.set CommitteeEntry_seed, 24
.set CommitteeEntry_decision_root, 56
.set CommitteeEntry_genesis_validators_root, 88
.set CommitteeEntry__mem, 128
.set KeySum_status, 0                   /* a KeySum of a CommitteeCache (block-processing.md) */
.set KeySum_point, 8
.set KeySum__mem, 152
.set KEYSUM_BLOCK_BYTES, SLOTS_PER_EPOCH * MAX_COMMITTEES_PER_SLOT * KeySum__mem
.ifdef PRESET_MINIMAL                    /* additions the key sums must save before they are used */
.set KEYSUM_MIN_SAVED, 0                /* minimal: always, so the test vectors run every branch */
.else
.set KEYSUM_MIN_SAVED, 128              /* the summed key's check costs about as many additions */
.endif

/* StateCache and CacheTree (docs/reference/state.md). */
.set StateCache_size, 0
.set StateCache_validators, 8
.set StateCache_trees, 16
.set STATE_CACHE_TREES, 16
.set CacheTree_capacity, 0
.set CacheTree_count, 8
.set CacheTree_nodes, 16
.set CacheTree_dirty, 24
.set CacheTree_copies, 32
.set CacheTree_copy, 40
.set CacheTree__mem, 48
.set STATE_CACHE_FIXED, 16 + 48 * 16
.set STATE_CACHE_HISTORICAL_ROOTS, 4096         /* leaves of the historical_roots tree */
.set STATE_CACHE_LIST, 65536                    /* leaves of the historical_summaries and two pending trees */
.set STATE_CACHE_PENDING_DEPOSITS, 262144       /* leaves of the pending_deposits tree */
.set STATE_CACHE_COPY_Validator, 128            /* the __mem of each element type of a tree */
.set STATE_CACHE_COPY_Eth1Data, 72
.set STATE_CACHE_COPY_HistoricalSummary, 64
.set STATE_CACHE_COPY_PendingDeposit, 192
.set STATE_CACHE_COPY_PendingPartialWithdrawal, 24
.set STATE_CACHE_COPY_PendingConsolidation, 16

/*
 * The keys of a network config file that lantern_config_parse reads (docs/reference/config.md):
 * m name, its CONFIG_* offset, its kind. BLOB_SCHEDULE has its own rules.
 */
.set CONFIG_KIND_U64, 0
.set CONFIG_KIND_VERSION, 1           /* 0x and 8 hex digits: 4 bytes, then 4 zero bytes */
.set CONFIG_KIND_UINT256, 2           /* decimal, little endian */
.set CONFIG_KIND_HASH32, 3            /* 0x and 64 hex digits */
.set CONFIG_KIND_ADDRESS, 4           /* 0x and 40 hex digits: 20 bytes, then 12 zero bytes */
.set CONFIG_KIND_TEXT, 5              /* 0 to 64 bytes 0x20 to 0x7e but " and \: the count, then 64 bytes */
.set CONFIG_KEY_NAME_MAX, 48
.macro CONFIG_KEYS m
    \m GENESIS_FORK_VERSION, CONFIG_GENESIS_FORK_VERSION, CONFIG_KIND_VERSION
    \m ALTAIR_FORK_VERSION, CONFIG_ALTAIR_FORK_VERSION, CONFIG_KIND_VERSION
    \m ALTAIR_FORK_EPOCH, CONFIG_ALTAIR_FORK_EPOCH, CONFIG_KIND_U64
    \m BELLATRIX_FORK_VERSION, CONFIG_BELLATRIX_FORK_VERSION, CONFIG_KIND_VERSION
    \m BELLATRIX_FORK_EPOCH, CONFIG_BELLATRIX_FORK_EPOCH, CONFIG_KIND_U64
    \m CAPELLA_FORK_VERSION, CONFIG_CAPELLA_FORK_VERSION, CONFIG_KIND_VERSION
    \m CAPELLA_FORK_EPOCH, CONFIG_CAPELLA_FORK_EPOCH, CONFIG_KIND_U64
    \m DENEB_FORK_VERSION, CONFIG_DENEB_FORK_VERSION, CONFIG_KIND_VERSION
    \m DENEB_FORK_EPOCH, CONFIG_DENEB_FORK_EPOCH, CONFIG_KIND_U64
    \m ELECTRA_FORK_VERSION, CONFIG_ELECTRA_FORK_VERSION, CONFIG_KIND_VERSION
    \m ELECTRA_FORK_EPOCH, CONFIG_ELECTRA_FORK_EPOCH, CONFIG_KIND_U64
    \m FULU_FORK_VERSION, CONFIG_FULU_FORK_VERSION, CONFIG_KIND_VERSION
    \m FULU_FORK_EPOCH, CONFIG_FULU_FORK_EPOCH, CONFIG_KIND_U64
    \m SLOT_DURATION_MS, CONFIG_SLOT_DURATION_MS, CONFIG_KIND_U64
    \m MIN_VALIDATOR_WITHDRAWABILITY_DELAY, CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY, CONFIG_KIND_U64
    \m SHARD_COMMITTEE_PERIOD, CONFIG_SHARD_COMMITTEE_PERIOD, CONFIG_KIND_U64
    \m EJECTION_BALANCE, CONFIG_EJECTION_BALANCE, CONFIG_KIND_U64
    \m MIN_PER_EPOCH_CHURN_LIMIT, CONFIG_MIN_PER_EPOCH_CHURN_LIMIT, CONFIG_KIND_U64
    \m CHURN_LIMIT_QUOTIENT, CONFIG_CHURN_LIMIT_QUOTIENT, CONFIG_KIND_U64
    \m MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT, CONFIG_MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT, CONFIG_KIND_U64
    \m MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, CONFIG_MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, CONFIG_KIND_U64
    \m MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, CONFIG_MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, CONFIG_KIND_U64
    \m INACTIVITY_SCORE_BIAS, CONFIG_INACTIVITY_SCORE_BIAS, CONFIG_KIND_U64
    \m INACTIVITY_SCORE_RECOVERY_RATE, CONFIG_INACTIVITY_SCORE_RECOVERY_RATE, CONFIG_KIND_U64
    \m MAX_BLOBS_PER_BLOCK_ELECTRA, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA, CONFIG_KIND_U64
    \m PROPOSER_SCORE_BOOST, CONFIG_PROPOSER_SCORE_BOOST, CONFIG_KIND_U64
    \m REORG_HEAD_WEIGHT_THRESHOLD, CONFIG_REORG_HEAD_WEIGHT_THRESHOLD, CONFIG_KIND_U64
    \m REORG_PARENT_WEIGHT_THRESHOLD, CONFIG_REORG_PARENT_WEIGHT_THRESHOLD, CONFIG_KIND_U64
    \m REORG_MAX_EPOCHS_SINCE_FINALIZATION, CONFIG_REORG_MAX_EPOCHS_SINCE_FINALIZATION, CONFIG_KIND_U64
    \m PROPOSER_REORG_CUTOFF_BPS, CONFIG_PROPOSER_REORG_CUTOFF_BPS, CONFIG_KIND_U64
    \m ATTESTATION_DUE_BPS, CONFIG_ATTESTATION_DUE_BPS, CONFIG_KIND_U64
    \m AGGREGATE_DUE_BPS, CONFIG_AGGREGATE_DUE_BPS, CONFIG_KIND_U64
    \m SYNC_MESSAGE_DUE_BPS, CONFIG_SYNC_MESSAGE_DUE_BPS, CONFIG_KIND_U64
    \m CONTRIBUTION_DUE_BPS, CONFIG_CONTRIBUTION_DUE_BPS, CONFIG_KIND_U64
    \m SAMPLES_PER_SLOT, CONFIG_SAMPLES_PER_SLOT, CONFIG_KIND_U64
    \m NUMBER_OF_CUSTODY_GROUPS, CONFIG_NUMBER_OF_CUSTODY_GROUPS, CONFIG_KIND_U64
    \m CUSTODY_REQUIREMENT, CONFIG_CUSTODY_REQUIREMENT, CONFIG_KIND_U64
    \m DATA_COLUMN_SIDECAR_SUBNET_COUNT, CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT, CONFIG_KIND_U64
    \m MAX_REQUEST_BLOCKS_DENEB, CONFIG_MAX_REQUEST_BLOCKS_DENEB, CONFIG_KIND_U64
    \m MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS, CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS, CONFIG_KIND_U64
    \m MAX_PAYLOAD_SIZE, CONFIG_MAX_PAYLOAD_SIZE, CONFIG_KIND_U64
    \m MAXIMUM_GOSSIP_CLOCK_DISPARITY, CONFIG_MAXIMUM_GOSSIP_CLOCK_DISPARITY, CONFIG_KIND_U64
    \m SUBNETS_PER_NODE, CONFIG_SUBNETS_PER_NODE, CONFIG_KIND_U64
    \m EPOCHS_PER_SUBNET_SUBSCRIPTION, CONFIG_EPOCHS_PER_SUBNET_SUBSCRIPTION, CONFIG_KIND_U64
    \m ATTESTATION_SUBNET_EXTRA_BITS, CONFIG_ATTESTATION_SUBNET_EXTRA_BITS, CONFIG_KIND_U64
    \m VALIDATOR_CUSTODY_REQUIREMENT, CONFIG_VALIDATOR_CUSTODY_REQUIREMENT, CONFIG_KIND_U64
    \m BALANCE_PER_ADDITIONAL_CUSTODY_GROUP, CONFIG_BALANCE_PER_ADDITIONAL_CUSTODY_GROUP, CONFIG_KIND_U64
    \m MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS, CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS, CONFIG_KIND_U64
    \m MAX_BLOBS_PER_BLOCK, CONFIG_MAX_BLOBS_PER_BLOCK, CONFIG_KIND_U64
    \m MIN_GENESIS_TIME, CONFIG_MIN_GENESIS_TIME, CONFIG_KIND_U64
    \m MIN_GENESIS_ACTIVE_VALIDATOR_COUNT, CONFIG_MIN_GENESIS_ACTIVE_VALIDATOR_COUNT, CONFIG_KIND_U64
    \m GENESIS_DELAY, CONFIG_GENESIS_DELAY, CONFIG_KIND_U64
    \m TERMINAL_TOTAL_DIFFICULTY, CONFIG_TERMINAL_TOTAL_DIFFICULTY, CONFIG_KIND_UINT256
    \m TERMINAL_BLOCK_HASH, CONFIG_TERMINAL_BLOCK_HASH, CONFIG_KIND_HASH32
    \m TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH, CONFIG_TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH, CONFIG_KIND_U64
    \m ATTESTATION_PROPAGATION_SLOT_RANGE, CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE, CONFIG_KIND_U64
    \m BLOB_SIDECAR_SUBNET_COUNT, CONFIG_BLOB_SIDECAR_SUBNET_COUNT, CONFIG_KIND_U64
    \m BLOB_SIDECAR_SUBNET_COUNT_ELECTRA, CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA, CONFIG_KIND_U64
    \m MAX_REQUEST_BLOCKS, CONFIG_MAX_REQUEST_BLOCKS, CONFIG_KIND_U64
    \m MESSAGE_DOMAIN_INVALID_SNAPPY, CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY, CONFIG_KIND_VERSION
    \m MESSAGE_DOMAIN_VALID_SNAPPY, CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY, CONFIG_KIND_VERSION
    \m SECONDS_PER_ETH1_BLOCK, CONFIG_SECONDS_PER_ETH1_BLOCK, CONFIG_KIND_U64
    \m ETH1_FOLLOW_DISTANCE, CONFIG_ETH1_FOLLOW_DISTANCE, CONFIG_KIND_U64
    \m DEPOSIT_CHAIN_ID, CONFIG_DEPOSIT_CHAIN_ID, CONFIG_KIND_U64
    \m DEPOSIT_NETWORK_ID, CONFIG_DEPOSIT_NETWORK_ID, CONFIG_KIND_U64
    \m ATTESTATION_SUBNET_COUNT, CONFIG_ATTESTATION_SUBNET_COUNT, CONFIG_KIND_U64
    \m DEPOSIT_CONTRACT_ADDRESS, CONFIG_DEPOSIT_CONTRACT_ADDRESS, CONFIG_KIND_ADDRESS
    \m PRESET_BASE, CONFIG_PRESET_BASE, CONFIG_KIND_TEXT
    \m CONFIG_NAME, CONFIG_CONFIG_NAME, CONFIG_KIND_TEXT
.endm

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
.set LANTERN_INVALID_MERGE_BLOCK, 47            /* validate_merge_block: the terminal PoW block conditions */
.set LANTERN_INVALID_TOPIC, 48                  /* lantern_gossip_topic, lantern_gossip_topic_parse: not a gossip topic */
.set LANTERN_INVALID_PROTOCOL, 49               /* lantern_reqresp_protocol_parse, lantern_reqresp_protocol_id: not a req/resp protocol */
.set LANTERN_INVALID_CHUNK, 50                  /* lantern_reqresp_read_header, lantern_reqresp_read_payload: invalid input */

/* lantern_reqresp_read_header, lantern_reqresp_read_payload: the stream's bytes end before the chunk does. */
.set LANTERN_REQRESP_MORE, 51
.set LANTERN_INVALID_HTTP, 52                   /* lantern_http_parse_response: not a valid HTTP/1.1 response */

/* lantern_http_parse_response: the connection's bytes end before the response does. */
.set LANTERN_HTTP_MORE, 53

.set LANTERN_INVALID_JSON, 54                   /* lantern_engine_parse_response: not a JSON-RPC response of the method; lantern_json_decode: the text breaks a rule */

/* EngineResponse (engine-api.md) */
.set EngineResponse_id, 0
.set EngineResponse_error, 8
.set EngineResponse_error_code, 16
.set EngineResponse_status, 24
.set EngineResponse_has_latest_valid_hash, 32
.set EngineResponse_latest_valid_hash, 40
.set EngineResponse_has_payload_id, 72
.set EngineResponse_payload_id, 80
.set EngineResponse_capabilities, 88
.set EngineResponse_result_offset, 96
.set EngineResponse_result_length, 104
.set EngineResponse__mem, 112
.set ENGINE_METHOD_NEW_PAYLOAD, 1
.set ENGINE_METHOD_FORKCHOICE_UPDATED, 2
.set ENGINE_METHOD_EXCHANGE_CAPABILITIES, 3
.set ENGINE_METHOD_GET_PAYLOAD, 4
.set ENGINE_METHOD_ETH_BLOCK, 5          /* eth_getBlockByNumber: the eth1 follower (eth1.md) */
.set ENGINE_METHOD_ETH_LOGS, 6           /* eth_getLogs of the DepositEvent logs */

/* ProduceDraft (node.md): the body draft of a produceBlockV3, filled in place by its fold works */
.set ProduceDraft_aggregates, 0
.set ProduceDraft_ops, 8
.set ProduceDraft_sync_set, 16
.set ProduceDraft_sync_bits, 24
.set ProduceDraft_sync_signature, 24 + SYNC_COMMITTEE_SIZE / 8
.set PRODUCE_DRAFT_AGGREGATES, (24 + SYNC_COMMITTEE_SIZE / 8 + 96 + 7) / 8 * 8
.set PRODUCE_DRAFT_AGGREGATE_COUNT, MAX_COMMITTEES_PER_SLOT * SLOTS_PER_EPOCH
.set DraftAggregate_data, 0
.set DraftAggregate_committee_index, 128
.set DraftAggregate_length, 136
.set DraftAggregate_order, 144
.set DraftAggregate_bits, 152
.set DraftAggregate_signature, 152 + MAX_VALIDATORS_PER_COMMITTEE / 8
.set DraftAggregate__mem, 248 + MAX_VALIDATORS_PER_COMMITTEE / 8
.set PRODUCE_DRAFT_OPS, PRODUCE_DRAFT_AGGREGATES + PRODUCE_DRAFT_AGGREGATE_COUNT * DraftAggregate__mem
.set PRODUCE_SLASHINGS_ROOM, MAX_ATTESTER_SLASHINGS * (24 + 8 + 2 * (232 + 8 * MAX_VALIDATORS_PER_COMMITTEE))
.set PRODUCE_SLASHINGS_ROOM_ELECTRA, MAX_ATTESTER_SLASHINGS_ELECTRA * (24 + 8 + 2 * (232 + 8 * MAX_VALIDATORS_PER_COMMITTEE * MAX_COMMITTEES_PER_SLOT))
.if PRODUCE_SLASHINGS_ROOM_ELECTRA > PRODUCE_SLASHINGS_ROOM
.set PRODUCE_SLASHINGS_ROOM, PRODUCE_SLASHINGS_ROOM_ELECTRA
.endif
.set PRODUCE_DRAFT_OPS_ROOM, MAX_PROPOSER_SLASHINGS * (24 + 416) + PRODUCE_SLASHINGS_ROOM + MAX_VOLUNTARY_EXITS * (24 + 112) + MAX_BLS_TO_EXECUTION_CHANGES * (24 + 176)
.set PRODUCE_DRAFT_ETH1, PRODUCE_DRAFT_OPS + PRODUCE_DRAFT_OPS_ROOM   /* eth1_set, eth1_data (72), deposit_count, the deposits */
.set PRODUCE_DRAFT_DEPOSIT, 33 * 32 + 184     /* a Deposit in SSZ: its proof, then its DepositData */
.set ProduceDraft__size, PRODUCE_DRAFT_ETH1 + 88 + MAX_DEPOSITS * PRODUCE_DRAFT_DEPOSIT

/* PayloadAttributes (engine-api.md) */
.set PayloadAttributes_timestamp, 0
.set PayloadAttributes_prev_randao, 8
.set PayloadAttributes_suggested_fee_recipient, 40
.set PayloadAttributes_parent_beacon_block_root, 64
.set PayloadAttributes_withdrawals, 96
.set PAYLOAD_ATTRIBUTES_WITHDRAWAL, 104
.set PAYLOAD_ATTRIBUTES_WITHDRAWAL_SIZE, 44
.set PayloadAttributes__mem, 104 + 44 * MAX_WITHDRAWALS_PER_PAYLOAD
.set PAYLOAD_ATTRIBUTES_ROOM, (PayloadAttributes__mem + 7) / 8 * 8   /* its bytes in scratch */
.set FCU_JSON_ATTRIBUTES, 24 + 1024 + 192 * MAX_WITHDRAWALS_PER_PAYLOAD  /* the room of an engine_forkchoiceUpdated with attributes */
.set ENGINE_STATUS_VALID, 1
.set ENGINE_STATUS_INVALID, 2
.set ENGINE_STATUS_SYNCING, 3
.set ENGINE_STATUS_ACCEPTED, 4
.set ENGINE_STATUS_INVALID_BLOCK_HASH, 5

/* HttpResponse (engine-api.md) */
.set HttpResponse_status, 0
.set HttpResponse_consumed, 8

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
.set BlockNode_finalized_epoch, 216    /* finalized_checkpoint.epoch of the block's post-state */
.set BlockNode__mem, 224

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
.set BlockOptions_pow_block, 16       /* bellatrix: get_pow_block(payload.parent_hash), a PowBlock, or 0 for None */
.set BlockOptions_pow_parent, 24      /* bellatrix: get_pow_block(pow_block.parent_hash), or 0 for None */
.set BlockOptions_slots_done, 32      /* 1: the state may be at the block's slot already, after an upgrade */
.set BlockOptions__size, 40

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
.set SEEN_BLOB_SIDECAR, 11             /* blob_sidecar_tuples: (slot, proposer index, blob index) */

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
 * The list limits of the req/resp message types that are config values: the values of the
 * mainnet and minimal configs (include/types.inc, Req/resp messages).
 */
.set REQUEST_BLOCKS_LIMIT, 1024                    /* MAX_REQUEST_BLOCKS */
.set REQUEST_BLOCKS_LIMIT_DENEB, 128               /* MAX_REQUEST_BLOCKS_DENEB */
.set REQUEST_BLOB_SIDECARS_LIMIT, 128 * 6          /* MAX_REQUEST_BLOCKS_DENEB * MAX_BLOBS_PER_BLOCK */
.set REQUEST_BLOB_SIDECARS_LIMIT_ELECTRA, 128 * 9  /* MAX_REQUEST_BLOCKS_DENEB * MAX_BLOBS_PER_BLOCK_ELECTRA */

/* ReqRespProtocol: a req/resp method and its version (req-resp.md) */
.set ReqRespProtocol_method, 0         /* REQRESP_* */
.set ReqRespProtocol_version, 8
.set ReqRespProtocol__mem, 16
.set REQRESP_STATUS, 1
.set REQRESP_GOODBYE, 2
.set REQRESP_BEACON_BLOCKS_BY_RANGE, 3
.set REQRESP_BEACON_BLOCKS_BY_ROOT, 4
.set REQRESP_PING, 5
.set REQRESP_METADATA, 6
.set REQRESP_BLOB_SIDECARS_BY_RANGE, 7
.set REQRESP_BLOB_SIDECARS_BY_ROOT, 8
.set REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, 9
.set REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, 10
.set REQRESP_BEACON_BLOCKS_BY_HEAD, 11
.set REQRESP_LIGHT_CLIENT_BOOTSTRAP, 12
.set REQRESP_LIGHT_CLIENT_UPDATES_BY_RANGE, 13
.set REQRESP_LIGHT_CLIENT_FINALITY_UPDATE, 14
.set REQRESP_LIGHT_CLIENT_OPTIMISTIC_UPDATE, 15
.set REQRESP_METHODS, 15

/* ChunkHeader: the parts of a req/resp chunk before its payload (req-resp.md) */
.set ChunkHeader_kind, 0               /* CHUNK_REQUEST or CHUNK_RESPONSE */
.set ChunkHeader_context_length, 8     /* 0 or 4 */
.set ChunkHeader_result, 16
.set ChunkHeader_context, 24           /* ForkDigest in the low 4 bytes */
.set ChunkHeader_length, 32
.set ChunkHeader_header_bytes, 40
.set ChunkHeader__mem, 48
.set CHUNK_REQUEST, 0
.set CHUNK_RESPONSE, 1

/* SizeBounds: the least and most SSZ bytes of a type (req-resp.md) */
.set SizeBounds_min, 0
.set SizeBounds_max, 8

/* GossipTopic: a gossip topic (networking.md) */
.set GossipTopic_fork_digest, 0        /* ForkDigest in the low 4 bytes */
.set GossipTopic_name, 8               /* GOSSIP_* */
.set GossipTopic_subnet_id, 16
.set GossipTopic__mem, 24
.set GOSSIP_BEACON_BLOCK, 1
.set GOSSIP_BEACON_AGGREGATE_AND_PROOF, 2
.set GOSSIP_BEACON_ATTESTATION, 3      /* beacon_attestation_{subnet_id} */
.set GOSSIP_VOLUNTARY_EXIT, 4
.set GOSSIP_PROPOSER_SLASHING, 5
.set GOSSIP_ATTESTER_SLASHING, 6
.set GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, 7
.set GOSSIP_SYNC_COMMITTEE, 8          /* sync_committee_{subnet_id} */
.set GOSSIP_BLS_TO_EXECUTION_CHANGE, 9
.set GOSSIP_BLOB_SIDECAR, 10           /* blob_sidecar_{subnet_id} */
.set GOSSIP_DATA_COLUMN_SIDECAR, 11    /* data_column_sidecar_{subnet_id} */
.set GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE, 12
.set GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE, 13
.set GOSSIP_NAMES, 13

/*
 * Scratch of lantern_verify_data_column_sidecar_kzg_proofs for a sidecar of n
 * commitments: DA_SCRATCH_FIXED + n * DA_SCRATCH_PER_BLOB. Its four input lists
 * (commitments, cell indices, cells, proofs) and asm-crypto's own scratch.
 * Needs asm-crypto's kzg.inc first.
 */
.set DA_SCRATCH_FIXED, 8 + 4 * LIST_FIXED + CRYPTO_KZG_SCRATCH
.set DA_SCRATCH_PER_BLOB, 48 + 8 + CRYPTO_KZG_CELL_SIZE + 48 + CRYPTO_KZG_SCRATCH_PER_ENTRY

/* ------------------------------------------------------------ Node (node.md) */

/* Node: the state of the node */
.set Node_next_id, 8                   /* the next BufferId */
.set Node_time_ms, 16
.set Node_head_root, 24
.set Node_anchor_state_id, 56
.set Node_blocks, 64                   /* PartRef of NodeBlock */
.set Node_checkpoints, 80              /* PartRef of NodeCheckpoint */
.set Node_pow_blocks, 96               /* PartRef of PowBlock values, 96 bytes each */
.set Node_flags, 112                   /* NODE_FLAG_* */
.set NODE_FLAG_OPTIMISTIC, 1           /* import payloads as NOT_VALIDATED until the execution engine answers */
.set NODE_FLAG_JUSTIFIED_PENDING, 2    /* a JUSTIFIED_STATE work is queued */
.set NODE_FLAG_SUBSCRIBED, 4           /* the gossip topics of fork_digest are subscribed */
.set NODE_FLAG_SYNCING, 8              /* a BeaconBlocksByRange request of the node is open */
.set NODE_FLAG_ENGINE, 16              /* the node drives an execution engine over the Engine API */
.set NODE_FLAG_FCU, 32                 /* an engine_forkchoiceUpdated is due */
.set NODE_FLAG_DISCV5, 64              /* the shell runs discv5 for the node: it takes NODE_ACT_DISCV5 and gives NODE_EV_ENR */
.set NODE_FLAG_DB, 128                 /* the node archives the finalized history: it gives NODE_ACT_DB_APPEND and serves NODE_DB_REF records */
.set NODE_FLAG_FEW_STATES, 256         /* the node keeps the post-states of the head, the justified root, F and the blocks with no child only */
.set NODE_FLAG_EL_OFFLINE, 512         /* the last connection to the execution engine failed before an answer */
.set NODE_FLAG_SUPERNODE, 1024         /* the node custodies every custody group */
.set NODE_FLAG_BUILDER, 2048           /* the node has a builder: it makes the builder calls of builder-specs v0.6.1 */
.set NODE_FLAG_ETH1, 4096             /* with NODE_FLAG_ENGINE, the node follows the deposit contract's chain (node.md, the eth1 follower) */
.set Node_peers, 120                   /* PartRef of NodePeer */
.set Node_streams, 136                 /* PartRef of NodeStream entries of Node_stream_bytes each */
.set Node_p2p_out, 152                 /* PartRef of bytes: libp2p events the node made for its next libp2p step */
.set Node_stream_bytes, 168            /* NodeStream__fixed + the request room, a multiple of 8 */
.set Node_metadata_seq, 176            /* MetaData.seq_number */
.set Node_genesis_validators_root, 184
.set Node_earliest_slot, 216           /* the slot of the anchor: the first block the node serves */
.set Node_messages, 224                /* PartRef of NodeMessage */
.set Node_fork_digest, 240             /* the ForkDigest of the subscribed topics, 4 bytes */
.set Node_sync_slot, 248               /* the first slot of the next BeaconBlocksByRange request, at least */
.set Node_blobs, 256                   /* PartRef of NodeBlob */
.set Node_jwt_secret, 272              /* the 32 byte key of the jwt-secret file */
.set Node_engine_host_len, 304
.set Node_engine_host, 312             /* the Host header of the Engine API requests, at most 64 bytes */
.set Node_engine_id, 376               /* the JSON-RPC id of the next call */
.set Node_engine_method, 384            /* ENGINE_METHOD_* of the call in flight, or 0 */
.set Node_engine_target, 392           /* engine_newPayload in flight: the NodeBlock index */
.set Node_engine_wait, 400             /* after a failed call but forkchoiceUpdated: the slot from which calls go again */
.set Node_engine_in, 408               /* PartRef of bytes: one ByteList of the bytes the execution engine sent */
.set Node_lookup_ms, 424               /* the time of the last discv5 lookup the node asked for */
.set Node_dialing, 432                 /* the node's dials not yet connected or failed */
.set Node_columns, 440                /* the columns the node samples: bit i % 8 of byte i / 8 for column i, 16 bytes */
.set Node_pruned_epoch, 456          /* the finalized epoch of the store at the last prune */
.set Node_db, 464                     /* PartRef: one Db, the history the node archived; the last part */
.set Node_db_next_slot, 480           /* with NODE_FLAG_DB: the canonical blocks below this slot are in the Db */
.set Node_db_block_segment, 488       /* the block segment of the last block record, or 2^64 - 1 */
.set Node_db_block_end, 496           /* the bytes of that segment */
.set Node_db_sidecar_segment, 504     /* the sidecar segment of the last sidecar record, or 2^64 - 1 */
.set Node_db_sidecar_end, 512         /* the bytes of that segment */
.set Node_status_ms, 520               /* the time of the node's last Status request of node_sync, or 0 */
.set Node_next_digest, 528             /* the ForkDigest whose topics the node joined ahead, or 0 */
.set Node_old_digest, 536              /* the ForkDigest whose topics leave from old_epoch on, or 0 */
.set Node_old_fork, 544                /* the fork of those topics */
.set Node_old_epoch, 552
.set Node_backfill_handle, 560        /* the stream of the node's backfill request: its tag, then its handle; 0 for none */
.set Node_backfill_slot, 568          /* the backfill looks for blocks below this slot */
.set Node_backfill_root, 576          /* the root of the next block of the backfill; zero after the genesis block */
.set Node_backfill_segment, 608       /* the block segment of the last backfill record, or 2^64 - 1 */
.set Node_backfill_end, 616           /* the bytes of that segment */
.set Node_backfill_next, 624         /* the end slot of the next backfill request */
.set Node_backfill_ms, 632            /* the time from which the next backfill request may go */
.set Node_backfill_peer, 640          /* the peers part index of the peer of the next backfill request */
.set Node_backfill_start, 648         /* the start slot of the last backfill request, 2^64 - 1 once it is weighed */
.set Node_backfill_got, 656           /* the blocks the last backfill request gave */
.set Node_backfill_sidecar_segment, 664  /* the sidecar segment of the last backfill sidecar record, or 2^64 - 1 */
.set Node_backfill_sidecar_end, 672   /* the bytes of that segment */
.set Node_node_id, 680                /* the anchor's node ID: the node ID of the node's key */
.set Node_attnets, 712                /* the attestation subnets the node is subscribed to: bit i for subnet i */
.set Node_sidecar_floor, 720          /* with NODE_FLAG_DB: the Db holds no sidecar below this slot */
.set Node_config, 728
.set Node_api_identity, 728 + CONFIG_SIZE  /* ApiIdentity of the last NODE_EV_API_IDENTITY */
.set Node_api, 728 + CONFIG_SIZE + 936     /* PartRef: NodeApi entries */
.set Node_event_head, Node_api + 16        /* the head of the last head event */
.set Node_event_slot, Node_api + 48        /* its block's slot */
.set Node_event_epoch, Node_api + 56       /* the store's finalized epoch at the last finalized_checkpoint event */
.set Node_event_votes, Node_api + 64       /* BLOCK_ATTESTATION and BLOCK_SLASHING works queued and not done */
.set Node_pool, Node_api + 72              /* PartRef: NodePool entries, the pool */
.set Node_subnets, Node_api + 88           /* the beacon_attestation subnets the node is subscribed to: attnets, and an aggregator's */
.set Node_syncnets, Node_api + 96          /* the sync_committee subnets the node is subscribed to */
.set Node_sync_until, Node_api + 104       /* SYNC_COMMITTEE_SUBNET_COUNT u64: each sync subnet stays below this epoch */
.set Node_subnet_until, Node_sync_until + 8 * SYNC_COMMITTEE_SUBNET_COUNT  /* ATTESTATION_SUBNET_COUNT u64: each subnet stays below this slot */
.set Node_proposers, Node_subnet_until + 8 * ATTESTATION_SUBNET_COUNT   /* PartRef: NodeProposer entries */
.set Node_payload_slot, Node_proposers + 16  /* the slot of the last payload preparation, or 0 */
.set Node_payload_root, Node_proposers + 24  /* Root: the head it built on */
.set Node_payload_id, Node_proposers + 56    /* 8 bytes: the payloadId, with NODE_PAYLOAD_READY */
.set Node_payload_status, Node_proposers + 64    /* NODE_PAYLOAD_* */
.set Node_payload_proposer, Node_proposers + 72  /* the proposer's validator index */
.set Node_lc_finality_slot, Node_proposers + 80   /* the finalized slot of the last light client finality update forwarded */
.set Node_lc_finality_super, Node_proposers + 88  /* 1 when it had a supermajority */
.set Node_lc_optimistic_slot, Node_proposers + 96 /* the attested slot of the last optimistic update forwarded */
.set Node_lc_pending, Node_proposers + 104 /* the light client topics whose update waits for its due time: 1 finality, 2 optimistic */
.set Node_lc_due, Node_proposers + 112     /* the Unix time in ms from which they may go */
.set Node_builder_host_len, Node_proposers + 120  /* with NODE_FLAG_BUILDER */
.set Node_builder_host, Node_proposers + 128      /* the Host of the Builder API requests, at most 64 bytes */
.set Node_builder_calls, Node_proposers + 192     /* NODE_BUILDER_CALLS entries: kind (0 free), the NodeApi entry, the time_ms it went out */
.set NODE_BUILDER_CALLS, 4
.set NODE_BUILDER_CALL_SIZE, 24
.set NODE_BUILDER_REGISTER, 1          /* registerValidator: POST /eth/v1/builder/validators */
.set NODE_BUILDER_HEADER, 2            /* getHeader: GET /eth/v1/builder/header/<slot>/<parent_hash>/<pubkey> */
.set NODE_BUILDER_SUBMIT, 3            /* submitBlindedBlockV2: POST /eth/v2/builder/blinded_blocks */
.set GOSSIP_BLINDED_BLOCK, 64          /* lantern_node_gossip: publishBlindedBlockV2's checks, no gossip topic */
.set PUBLISH_BLINDED, 64               /* the cursor of a publish entry: 1 for a blinded block */
.set PUBLISH_CALL, 72                  /* its NODE_BUILDER_SUBMIT call + 1 while in flight, else 0 */
.set DOMAIN_APPLICATION_BUILDER, 0x01000000  /* builder-specs bellatrix builder.md: DomainType('0x00000001'), its bytes as a little endian u32 */
.set BUILDER_PROPOSAL_DELAY_TOLERANCE_MS, 1000  /* builder-specs bellatrix validator.md: 1 second */
.set BUILDER_FALLBACK_SKIPS, 3         /* the liveness failsafe (beacon-api.md, produceBlockV3): Lighthouse v8.3.3's defaults */
.set BUILDER_FALLBACK_SKIPS_PER_EPOCH, 8
.set BUILDER_FALLBACK_EPOCHS_SINCE_FINALIZATION, 3
.set PRODUCE_BOOST, 136                /* the cursor of a produceBlockV3 entry: builder_boost_factor */
.set PRODUCE_CALL, 152                 /* its NODE_BUILDER_HEADER call + 1 while in flight, else 0 */
.set PRODUCE_BID, 160                  /* the id of the builder's answer, then of its valid bid; 0 for none */
.set PRODUCE_FEE, 168                  /* the fee recipient of the proposer's registration: 20 bytes */
.set Node_base_slot, Node_proposers + 192 + NODE_BUILDER_CALLS * NODE_BUILDER_CALL_SIZE  /* the slot of the base state, anchor_state_id */
.set Node_replay_root, Node_base_slot + 8        /* Root: the block of the last replay (node.md, the replay) */
.set Node_replay_slot, Node_base_slot + 40       /* its slot */
.set Node_replay_state, Node_base_slot + 48      /* its post-state once queued whole, or 0 */
.set Node_replay_copy, Node_base_slot + 56       /* the copy of the replay in flight, or 0 */
.set Node_replay_copy_slot, Node_base_slot + 64  /* its slot */
.set Node_replay_next, Node_base_slot + 72       /* the slot from which it queues its next block */
.set Node_eth1_state, Node_base_slot + 80      /* the eth1 follower (node.md): 0 unchecked, 1 it runs, 2 it waits */
.set Node_eth1_head, Node_base_slot + 88       /* the eth1 chain's latest block number */
.set Node_eth1_head_ms, Node_base_slot + 96    /* the time it was read, or 0 */
.set Node_eth1_logs_to, Node_base_slot + 104   /* the deposit logs of the blocks below it are in */
.set Node_eth1_call, Node_base_slot + 112      /* the eth1 call in flight: the block asked (2^64 - 1 latest), or the logs' last block */
.set Node_eth1_deposit_index, Node_base_slot + 120  /* eth1_deposit_index of the head's post-state at the last check */
.set Node_eth1_tree, Node_base_slot + 128      /* DepositTree of the deposits */
.set Node_eth1_blocks, Node_base_slot + 1160   /* PartRef: Eth1Block entries by number */
.set Node_eth1_deposits, Node_base_slot + 1176 /* PartRef: Eth1Deposit entries by index */
.set Node_eth1_leaves, Node_base_slot + 1192   /* PartRef: their leaves */
.set Node_eth1_counts, Node_base_slot + 1208   /* PartRef: Eth1Count entries */
.set Node_eth1_check_epoch, Node_base_slot + 1224  /* the store's epoch + 1 at the last ETH1_CHECK, or 0 */
.set Node_archive_slots, Node_base_slot + 1232   /* the archive (node.md): 0 for no state records */
.set Node_archive_slot, Node_base_slot + 1240    /* the slot of the last state record, or 2^64 - 1 */
.set Node_archive_first, Node_base_slot + 1248   /* the lowest slot of a state record, or 2^64 - 1 */
.set Node_archive_segment, Node_base_slot + 1256 /* the state segment of the last state record, or 2^64 - 1 */
.set Node_archive_end, Node_base_slot + 1264     /* its bytes */
.set Node_archive_busy, Node_base_slot + 1272    /* 1 while a NODE_ACT_DB_ARCHIVE waits for its NODE_EV_DB_ARCHIVE */
.set Node_replay_loading, Node_base_slot + 1280  /* 1 while the replay's NODE_WORK_ARCHIVE_LOAD is out */
.set Node_custody_count, Node_base_slot + 1288  /* the custody group count (fulu validator custody): it never falls */
.set Node_custody_slot, Node_base_slot + 1296   /* the store's slot at its last raise, or the anchor's */
.set Node_custody_need, Node_base_slot + 1304   /* the count of the node's validators at the last CUSTODY work */
.set Node_custody_epoch, Node_base_slot + 1312  /* the store's epoch + 1 at the last CUSTODY work, or 0 */
.set Node_recon_root, Node_base_slot + 1320    /* Root: the block of the reconstruction (fulu das-core.md) */
.set Node_recon_slot, Node_base_slot + 1352    /* its slot */
.set Node_recon_state, Node_base_slot + 1360   /* 0 none, 1 its work queued, 2 its sidecars due, 3 a PUBLISH_SIDECAR of them queued */
.set Node_recon_buffer, Node_base_slot + 1368  /* the BufferId of the rebuilt sidecars */
.set Node_recon_next, Node_base_slot + 1376    /* the column from which the next missing one is looked for */
.set Node_recon_failed, Node_base_slot + 1384  /* Root: of the last reconstruction that failed, or zero */
.set Node_responses, Node_base_slot + 1416  /* PartRef: NodeResponse entries of Node_response_bytes each, all made at the start */
.set Node_response_bytes, Node_base_slot + 1432  /* NodeResponse__fixed + the response room, a multiple of 8 */
.set Node_sync_start, Node_base_slot + 1440  /* the start slot of the open BeaconBlocksByRange of the sync */
.set Node_sync_got, Node_base_slot + 1448    /* the slot after its highest block so far, or 0 */
.set Node_sync_peer, Node_base_slot + 1456   /* the peers part index the next BeaconBlocksByRange of the sync looks from */
.set Node_status_peer, Node_base_slot + 1464 /* the same for the next Status request of the sync */
.set Node_sidecar_ms, Node_base_slot + 1472  /* the time_ms of the last sidecar retry, or 0 */
.set Node_sidecar_peer, Node_base_slot + 1480  /* the peers part index the sidecar requests look from */
.set Node_gossip_states, Node_base_slot + 1488  /* NODE_GOSSIP_STATES NodeGossipState entries: shared proposer states of gossip */
.set Node_head_due, Node_base_slot + 1600  /* 1 when the store may have changed since the last get_head */
.set Node_head_slot, Node_base_slot + 1608  /* the store's slot at the last get_head */
.set Node_fcu_wait, Node_base_slot + 1616  /* after a failed engine_forkchoiceUpdated, the slot from which the next goes */
.set NODE_FIXED, Node_base_slot + 1624
.set Eth1Count_number, 0               /* Eth1Count (node.md) */
.set Eth1Count_count, 8
.set Eth1Count_root, 16
.set Eth1Count__mem, 48
.set Eth1Snapshot_blocks, 0            /* Eth1Snapshot (node.md) */
.set Eth1Snapshot_deposits, 8
.set Eth1Snapshot_leaves, 16
.set Eth1Snapshot__fixed, 24
.set NODE_ETH1_LOG_BLOCKS, 1000        /* the most blocks of one eth_getLogs */
.set NODE_ETH1_ROOM, 1024              /* the eth1_deposits entries free while the follower runs */
.set NODE_REPLAY_CHUNK, 64             /* the most blocks a replay queues in a step */
.set NODE_PAYLOAD_NONE, 0
.set NODE_PAYLOAD_PREPARING, 1             /* its PREPARE_PAYLOAD work is queued */
.set NODE_PAYLOAD_SENT, 2                  /* its engine_forkchoiceUpdated is in flight */
.set NODE_PAYLOAD_READY, 3                 /* payload_id holds the engine's payloadId */
.set NODE_LOOKUP_MS, 10000             /* the least time between two lookups of the node */
.set NODE_STATUS_MS, 12000             /* the least time between two Status requests of node_sync */
.set NODE_SIDECAR_RETRY_MS, 4000       /* the least time between two sidecar retries */
.set NODE_REQUEST_MS, 10000            /* a request of the node with no response bytes for this long goes (node.md, the request timeout) */
.set NODE_COLUMN_PEERS, 2              /* a sampled column with fewer peers of its custody is short (node.md); the code counts to 2 with two masks */
.set NODE_PEER_SPARE_SHIFT, 3          /* the spare room of the peers part: its capacity >> this */
.set NODE_HEAD_WORKS, (1 << NODE_WORK_IMPORT_BLOCK) | (1 << NODE_WORK_JUSTIFIED_STATE) | (1 << NODE_WORK_ATTESTATION) | (1 << NODE_WORK_ATTESTER_SLASHING) | (1 << NODE_WORK_BLOCK_ATTESTATION) | (1 << NODE_WORK_BLOCK_SLASHING) | (1 << NODE_WORK_GOSSIP_VOTE)  /* the works that write the store */
.set NODE_GOSSIP_STATES, 2             /* the shared proposer states of gossip (node.md, NodeGossipState) */
.set NodeGossipState_state, 0          /* BufferId of the state, 0 for none */
.set NodeGossipState_root, 8           /* the parent root of its messages */
.set NodeGossipState_slot, 40          /* the slot of its messages */
.set NodeGossipState_uses, 48          /* NODE_WORK_GOSSIP works of it not done yet */
.set NodeGossipState__mem, 56
.set NODE_SUBSCRIBE_AHEAD, 2           /* epochs: the topics of a new ForkDigest join this early, the old ones leave this late */
.set NODE_STATE_KEEP_SLOTS, 4          /* the post-states of blocks of this many slots before the store's stay */
.set NODE_DIAL_TAG, 0x4000000000000000 /* the bit of a DIAL tag of the node */
.set NODE_ENGINE_HOST_MAX, 64
.set NODE_STATE_SLOT, 48               /* BeaconState.slot in the value of every fork */
.set NODE_STATE_GVR, 16                /* BeaconState.genesis_validators_root in the value of every fork */
.set NODE_STATE_HEADER, 72             /* BeaconState.latest_block_header in the value of every fork */
.set NODE_BLOCK_STATE_ROOT, 56         /* BeaconBlock.state_root in the value of every fork */

/* NodeBlock: a block the node knows */
.set NodeBlock_root, 0
.set NodeBlock_parent_root, 32
.set NodeBlock_slot, 64
.set NodeBlock_data_id, 72             /* the SignedBeaconBlock's SSZ bytes */
.set NodeBlock_state_id, 80            /* its post-state, 0 until imported */
.set NodeBlock_status, 88              /* NODE_BLOCK_* */
.set NodeBlock_data_available, 96
.set NodeBlock_result, 104             /* the result of its import */
.set NodeBlock_blobs, 112              /* from the network: the length of its body's blob_kzg_commitments, 0 before deneb */
.set NodeBlock_payload_status, 120     /* PAYLOAD_STATUS_* its import takes, from the execution engine's answer */
.set NodeBlock_retry, 128              /* the slot from which its engine_newPayload may go again */
.set NodeBlock_length, 136             /* the bytes of its SSZ bytes */
.set NodeBlock__mem, 144
.set NODE_BLOCK_WAITING, 1             /* its parent is not imported yet */
.set NODE_BLOCK_IMPORTING, 2           /* an IMPORT_BLOCK work is queued */
.set NODE_BLOCK_IMPORTED, 3
.set NODE_BLOCK_INVALID, 4
.set NODE_BLOCK_HASHING, 5             /* from a response: a SYNC_BLOCK work of its root is queued; root 0 */
.set NODE_BLOCK_BLOBS, 6               /* from the network: it needs blob sidecars the node does not hold */
.set NODE_BLOCK_PAYLOAD, 7             /* with NODE_FLAG_ENGINE: its engine_newPayload is due */
.set NODE_BLOCK_EXECUTING, 8           /* its engine_newPayload is queued or sent */
.set NODE_BLOCK_FREE, 9                /* no block: root and parent_root all 0xff bytes, slot 2^64 - 1 */
.set NODE_BLOCK_BF_CHECKING, 10        /* of the backfill: its BACKFILL work is queued */
.set NODE_BLOCK_BACKFILL, 11           /* of the backfill: root and signature checked; it waits to join the Db */

/* NodeBlob: a blob sidecar the node holds */
.set NodeBlob_block_root, 0            /* hash_tree_root of its signed_block_header.message */
.set NodeBlob_index, 32
.set NodeBlob_slot, 40                 /* the slot of its block header */
.set NodeBlob_data_id, 48              /* the BlobSidecar's SSZ bytes */
.set NodeBlob_status, 56               /* NODE_BLOB_* */
.set NodeBlob_length, 64               /* the bytes of its SSZ bytes */
.set NodeBlob__mem, 72
.set NODE_BLOB_VERIFYING, 1            /* from a response: a BLOB work is queued; block_root 0 */
.set NODE_BLOB_VALID, 2
.set NODE_BLOB_FREE, 4                 /* no sidecar: block_root all 0xff bytes, slot 2^64 - 1 */
.set NODE_BLOB_MAX, 64                 /* a block of more blob commitments than this or its fork's limit needs no sidecars */

/* NodeCheckpoint: store.checkpoint_states */
.set NodeCheckpoint_epoch, 0
.set NodeCheckpoint_root, 8
.set NodeCheckpoint_state_id, 40
.set NodeCheckpoint__mem, 48
.set POW_BLOCK_BYTES, 96

/* NodePeer: a connected libp2p peer */
.set NodePeer_handle, 0                /* the libp2p peer Handle */
.set NodePeer_direction, 8             /* LIBP2P_INBOUND or LIBP2P_OUTBOUND */
.set NodePeer_flags, 16                /* NODE_PEER_* */
.set NODE_PEER_STATUS, 1               /* a Status of the peer was read */
.set NODE_PEER_METADATA_ASKED, 2       /* the node sent it a GetMetaData v3 */
.set NODE_PEER_METADATA, 4             /* its MetaData v3 was read: custody holds its columns */
.set NodePeer_fork_digest, 24          /* Status: 4 bytes */
.set NodePeer_finalized_root, 32
.set NodePeer_finalized_epoch, 64
.set NodePeer_head_root, 72
.set NodePeer_head_slot, 104
.set NodePeer_earliest_slot, 112       /* Status v2: earliest_available_slot */
.set NodePeer_id_len, 120
.set NodePeer_id, 128                  /* the peer ID, at most 48 bytes */
.set NodePeer_custody, 176             /* with NODE_PEER_METADATA: the columns it custodies, as Node_columns */
.set NodePeer_address, 192             /* PEER_CONNECTED: the asm-libp2p Address of its connection */
.set NodePeer_transport, 224           /* PEER_CONNECTED: LIBP2P_TCP or LIBP2P_QUIC */
.set NodePeer__mem, 232

/* NodeStream: an open req/resp stream; the request bytes follow the fixed fields */
.set NodeStream_handle, 0              /* the libp2p stream Handle */
.set NodeStream_peer, 8                /* the libp2p peer Handle */
.set NodeStream_method, 16             /* REQRESP_* */
.set NodeStream_version, 24
.set NodeStream_state, 32              /* NODE_STREAM_* */
.set NODE_STREAM_REQUEST, 1            /* the request is being read */
.set NODE_STREAM_EOF, 2                /* the request is being read; the peer closed its side */
.set NODE_STREAM_SERVE, 3              /* the next block of the list is due */
.set NODE_STREAM_SERVING, 4            /* a SERVE work of the next block is queued */
.set NODE_STREAM_OPENING, 5            /* the node's request: OPEN_STREAM is sent; handle holds its tag */
.set NODE_STREAM_RESPONSE, 6           /* the node's request is sent; list holds the response bytes; next 1 after STREAM_EOF */
.set NODE_STREAM_TAG, 0x8000000000000000  /* the bit of an OPEN_STREAM tag of the node */
.set NODE_SYNC_BATCH, 64               /* the most blocks of one BeaconBlocksByRange request of the node */
.set NodeStream_next, 40               /* SERVE: the index of the next BufferId of the list */
.set NodeStream_response, 48           /* a request of the node: the index + 1 of its NodeResponse, or 0 */
.set NodeStream_list, 56               /* a ByteList: the request bytes, then the BufferIds of the blocks to send */
.set NodeStream_request, 80
.set NodeStream__fixed, 80
.set NodeResponse_used, 0              /* NodeResponse (node.md): 0 free, else max(time_ms, 1) at the open and at each STREAM_DATA */
.set NodeResponse_list, 8              /* a ByteList: the response bytes not read yet */
.set NodeResponse__fixed, 32

/* NodeMessage: a gossip message the node holds */
.set NodeMessage_handle, 0             /* the libp2p message Handle */
.set NodeMessage_peer, 8               /* the libp2p peer Handle */
.set NodeMessage_topic, 16             /* GOSSIP_*, or 0 for a topic of no name */
.set NodeMessage_subnet, 24
.set NodeMessage_data_id, 32           /* BufferId of the uncompressed bytes, or 0 */
.set NodeMessage_state, 40             /* NODE_MESSAGE_* */
.set NodeMessage_slot, 48              /* the slot of its block or block header */
.set NodeMessage_parent_root, 56       /* the parent root of its block or block header */
.set NodeMessage_length, 88           /* the bytes of its uncompressed data */
.set NodeMessage__mem, 96
.set NODE_MESSAGE_ID, 1                /* its MESSAGE_ID is sent */
.set NODE_MESSAGE_VALIDATING, 2        /* a GOSSIP work is queued */
.set NODE_MESSAGE_NO_ROOM, 3           /* the bytes did not fit in the actions: IGNORE */
.set NODE_MESSAGE_CORRUPT, 4           /* the data is no Snappy block of at most MAX_PAYLOAD_SIZE bytes: REJECT */
.set NODE_MESSAGE_OTHER_DIGEST, 5      /* a topic of another ForkDigest than fork_digest: IGNORE, its data unread */
.set NODE_MESSAGE_VOTE, 6              /* a valid aggregate: its vote goes to fork choice once its slot is past */
.set NODE_MESSAGE_VOTING, 7            /* a valid aggregate: its GOSSIP_VOTE work is queued */

/* NodeGossip: the inputs of lantern_node_gossip */
.set NodeGossip_seen, 0
.set NodeGossip_store, 8
.set NodeGossip_time_ms, 16
.set NodeGossip_topic, 24              /* GOSSIP_* */
.set NodeGossip_subnet, 32
.set NodeGossip_head, 40               /* head_state */
.set NodeGossip_proposer, 48           /* proposer_state, or 0 */
.set NodeGossip_justified, 56          /* justified_state, or 0 */
.set NodeGossip_settings, 64           /* asm-crypto KzgSettings, or 0 */
.set NodeGossip_config, 72             /* the node's Config */
.set NodeGossip__mem, 80

/* NodeAnchor: the input of lantern_node_init */
.set NodeAnchor_root, 0                /* hash_tree_root of the anchor block */
.set NodeAnchor_slot, 32
.set NodeAnchor_genesis_validators_root, 40
.set NodeAnchor_jwt_secret, 72         /* with NODE_FLAG_ENGINE */
.set NodeAnchor_engine_host_len, 104   /* at most NODE_ENGINE_HOST_MAX */
.set NodeAnchor_engine_host, 112
.set NodeAnchor_node_id, 176           /* NodeID of the node's key: keccak256 of its point, reversed */
.set NodeAnchor_history_slot, 208     /* the first slot of the Db: at most the anchor's slot, rounded down to a segment */
.set NodeAnchor_builder_host_len, 216  /* with NODE_FLAG_BUILDER, at most NODE_ENGINE_HOST_MAX */
.set NodeAnchor_builder_host, 224
.set NodeAnchor_archive_slots, 288    /* with NODE_FLAG_DB: a state record each run of this many slots of F; 0 none */
.set NodeAnchor_custody_count, 296   /* the custody group count advertised last, 0 for none */
.set NodeAnchor_custody_slot, 304
.set NodeAnchor__mem, 312
.set NODE_P2P_ROUNDS, 8                /* libp2p steps of one node step for the node's own events, at most */

/* NodeRoom: the capacities of a Node */
.set NodeRoom_blocks, 0
.set NodeRoom_checkpoints, 8
.set NodeRoom_pow_blocks, 16
.set NodeRoom_peers, 24
.set NodeRoom_streams, 32
.set NodeRoom_request_bytes, 40        /* request bytes each stream holds */
.set NodeRoom_p2p_out, 48              /* bytes of libp2p events the node holds for its next libp2p step */
.set NodeRoom_messages, 56
.set NodeRoom_blobs, 64
.set NodeRoom_engine_bytes, 72         /* bytes of the execution engine's answers the node holds */
.set NodeRoom_db_slots, 80             /* a DbRoom: the slots of the Db */
.set NodeRoom_db_roots, 88             /* its root table, a power of two */
.set NodeRoom_api_streams, 96          /* NodeApi entries: answers the node streams */
.set NodeRoom_pool, 104                /* NodePool entries: the pool's operations */
.set NodeRoom_proposers, 112           /* NodeProposer entries: the fee recipients of prepareBeaconProposer */
.set NodeRoom_eth1_blocks, 120         /* Eth1Block entries: the eth1 follower's window */
.set NodeRoom_eth1_deposits, 128       /* Eth1Deposit entries, and as many leaves and Eth1Count entries */
.set NodeRoom_responses, 136           /* NodeResponse entries: the requests of the node but Status and GetMetaData open at once */
.set NodeRoom_response_bytes, 144      /* response bytes each NodeResponse holds */
.set NODE_ROOM_FIELDS, 19

/* NodeProposer: a validator's fee recipient (beacon-api.md, prepareBeaconProposer) */
.set NodeProposer_validator_index, 0
.set NodeProposer_until_epoch, 8          /* the entry holds while the store's epoch is below it; 0 for a free entry */
.set NodeProposer_fee_recipient, 16       /* ExecutionAddress: 20 bytes */
.set NodeProposer_registered, 40           /* 1 with the validator's latest registration (beacon-api.md, registerValidator) */
.set NodeProposer_registration_fee_recipient, 48   /* ExecutionAddress: 20 bytes */
.set NodeProposer_gas_limit, 72
.set NodeProposer_timestamp, 80
.set NodeProposer_pubkey, 88            /* BLSPubkey: 48 bytes of the registration */
.set NodeProposer__mem, 136

/* NodeStepResult: the output of lantern_node_step */
.set NodeStepResult_accepted, 0        /* events handled, from the first */
.set NodeStepResult_wakeup, 8          /* monotonic ms by which the next step is due; 2^64 - 1 for none */
.set NodeStepResult_short, 16          /* with LANTERN_BUFFER_TOO_SMALL: NODE_SHORT_* */
.set NodeStepResult_room, 24           /* with NODE_SHORT_NODE: the offset in NodeRoom of the capacity that is short */
.set NodeStepResult__size, 32
.set NODE_SHORT_ACTIONS, 1             /* the room of actions, or libp2p_step's */
.set NODE_SHORT_NODE, 2                /* a part of the node */
.set NODE_SHORT_SCRATCH, 3             /* the room of scratch, or lantern_node_block_root's */

/* NodeEvent kinds, after the size and kind header */
.set NODE_EV_TICK, 1                   /* 16 time_ms */
.set NODE_EV_BLOCK, 2                  /* 16 data_available, 24 a ByteList of the SSZ bytes */
.set NODE_EV_ATTESTATION, 3            /* 16 is_from_block, 24 a ByteList of the SSZ bytes */
.set NODE_EV_ATTESTER_SLASHING, 4      /* 24 a ByteList of the SSZ bytes */
.set NODE_EV_POW_BLOCK, 5              /* 24 a ByteList of the SSZ bytes */
.set NODE_EV_PAYLOAD_STATUS, 6         /* 16 block_hash, 48 status, 56 has_latest, 64 latest_valid_hash */
.set NODE_EV_WORK_DONE, 7              /* the work's fields from 16 (as NodeAction), then 72 result, 80 checkpoint epoch, 88 root, 120 index */
.set NODE_EV_P2P, 8                    /* 16 a libp2p shell result Event */
.set NODE_EV_ENGINE, 9                 /* 16 0: 24 a ByteList of bytes the execution engine sent; 16 1: the connection failed */
.set NODE_EV_ENR, 10                   /* 24 a ByteList of a node record discv5 found */
.set NODE_EV_API, 11                   /* 16 the connection, 24 a ByteList of an HttpRequest */
.set NODE_EV_API_IDENTITY, 12          /* 24 a ByteList of an ApiIdentity */
.set NODE_EV_API_SENT, 13             /* 16 the connection: the shell has room for its next chunk */
.set NODE_EV_API_CLOSED, 14           /* 16 the connection: it closed */
.set NODE_EV_BUILDER, 15              /* 16 a builder call, + 256 for a failure; 24 a ByteList of the builder's whole answer */
.set NODE_EV_DB_ARCHIVE, 16            /* 16 a state segment, 24 an offset, 32 the DbRecord written, kind 0 for none */
.set NODE_EV_LAST, 16
.set NODE_EV_DB_ARCHIVE_SIZE, 112
.set NodeEvent_result, 72
.set NodeEvent_checkpoint, 80
.set NODE_EV_WORK_DONE_SIZE, 128
.set NodeEvent_bytes, 24               /* a ByteList whose bytes start at its offset 24 */

/* NodeAction kinds, after the size and kind header */
.set NODE_ACT_BYTES_PUT, 1             /* 16 id, 24 a ByteList of the bytes */
.set NODE_ACT_STATE_COPY, 2            /* 16 source id, 24 new id */
.set NODE_ACT_STATE_FREE, 3            /* 16 id */
.set NODE_ACT_BYTES_FREE, 4            /* 16 id */
.set NODE_ACT_WORK, 5                  /* 16 kind, 24 state_a, 32 state_b, 40 state_c, 48 data, 56 target, 64 arg */
.set NODE_ACT_P2P_LIST, 6              /* 16 a ByteList of libp2p Actions: the shell does its shell requests in order */
.set NODE_ACT_ENGINE, 7                /* 24 a ByteList of an HTTP request: the shell writes it to the execution engine's connection */
.set NODE_ACT_DISCV5, 8                /* 24 a ByteList of asm-discv5 events: the shell passes them to discv5_step */
.set NODE_ACT_DB_APPEND, 9             /* 16 BufferId, 24 segment, 32 sidecars, 40 offset, 48 DbRecord: the shell appends the record */
.set NODE_ACT_DB_APPEND_SIZE, 128
.set NODE_ACT_DB_STATE, 10              /* 16 a state's BufferId, 24 its block's BufferId, 32 the slot: the finalized block, for a restart */
.set NODE_ACT_DB_STATE_SIZE, 56
.set NODE_ACT_DB_DROP, 11              /* 16 a segment, 24 1 for a sidecar segment: the shell deletes its file */
.set NODE_ACT_DB_DROP_SIZE, 32
.set NODE_ACT_API_SEND, 12             /* 16 the connection, 24 last, 32 a ByteList of the bytes */
.set NODE_ACT_API_CLOSE, 13            /* 16 the connection */
.set NODE_ACT_API_CLOSE_SIZE, 24
.set NODE_ACT_STATE_BYTES, 14         /* 16 a state's id, 24 a new id: the shell keeps the state's SSZ bytes as it */
.set NODE_ACT_STATE_BYTES_SIZE, 32
.set NODE_ACT_BYTES_NEW, 15            /* 16 a new id, 24 a size: the shell keeps a ByteList of that size, offset 24, its bytes zero */
.set NODE_ACT_BYTES_NEW_SIZE, 32
.set NODE_ACT_BUILDER, 16              /* 16 a builder call, 24 a ByteList of an HTTP request: the shell writes it to a new connection to the builder */
.set NODE_ACT_DB_ARCHIVE, 17           /* 16 a state's BufferId, 24 a state segment, 32 an offset, 40 a DbRecord: the shell writes the state's record */
.set NODE_ACT_DB_ARCHIVE_SIZE, 120
.set NODE_ACT_BYTES_JOIN, 18            /* 16 a new id, 24 a count, then the ids: the shell keeps their ByteLists one after another */
.set NODE_DB_REF, 1 << 63              /* a BufferId of a Db record: bit 62 a sidecar segment, bit 61 a state segment, segment << 44, the offset below */
.set NODE_DB_SIDECARS, 1 << 62
.set NODE_DB_STATES, 1 << 61
.set NODE_DB_SEGMENT_SHIFT, 44         /* a NODE_DB_REF's segment: 17 bits from here */
.set DB_SEGMENT_SHIFT, 13              /* slot >> DB_SEGMENT_SHIFT: its segment */
.set NodeAction_work_kind, 16
.set NodeAction_state_a, 24
.set NodeAction_state_b, 32
.set NodeAction_state_c, 40
.set NodeAction_data, 48
.set NodeAction_target, 56
.set NodeAction_arg, 64
.set NODE_ACT_WORK_SIZE, 72

/* Work kinds of lantern_node_run */
.set NODE_WORK_IMPORT_BLOCK, 1         /* a: a copy of the parent's post-state; data: the block */
.set NODE_WORK_JUSTIFIED_STATE, 2      /* a: the justified checkpoint state */
.set NODE_WORK_TARGET_STATE, 3         /* a: a copy of the target root's block state */
.set NODE_WORK_ATTESTATION, 4          /* a: the target checkpoint state, or 0; data: the attestation */
.set NODE_WORK_ATTESTER_SLASHING, 5    /* a: the justified root's block state; data: the slashing */
.set NODE_WORK_SERVE, 6                /* data: a block's or sidecar's SSZ bytes; target: the stream Handle; arg: the protocol version + 256 * the method */
.set NODE_WORK_GOSSIP, 7               /* a: head state; b: proposer state; c: justified state; data: the message; target: its Handle; arg: topic + 256 * subnet */
.set NODE_WORK_SYNC_BLOCK, 8           /* data: a block's SSZ bytes from a response; target: its NodeBlock index */
.set NODE_WORK_BLOB, 9                 /* data: a sidecar's SSZ bytes from a response; target: its NodeBlob index; arg: 0 BlobSidecar, 1 DataColumnSidecar */
.set NODE_WORK_NEW_PAYLOAD, 10         /* data: a block's SSZ bytes; target: its NodeBlock index; arg: the JSON-RPC id */
.set NODE_WORK_FORKCHOICE, 11          /* arg: the JSON-RPC id */
.set NODE_WORK_SLOTS, 12               /* a: a state; arg: the slot to process it to */
.set NODE_WORK_UPGRADE, 13             /* a: a state at the fork's first slot; b: the buffer for the upgraded state; arg: the fork */
.set NODE_WORK_REPLAY, 14              /* a: the post-state of a block's parent; data: the block, imported before */
.set NODE_WORK_BACKFILL, 15            /* a: F's post-state; data: a block of the backfill; target: its NodeBlock index */
.set NODE_WORK_BLOCK_ATTESTATION, 16   /* a: the target checkpoint state, or 0; data: an imported block; arg: the index of an attestation of its body */
.set NODE_WORK_BLOCK_SLASHING, 17      /* a: the justified root's post-state; data: an imported block; arg: the index of an attester slashing of its body */
.set NODE_WORK_GOSSIP_VOTE, 18         /* a: the target checkpoint state, or 0; data: a valid SignedAggregateAndProof; target: its message Handle */
.set NODE_WORK_API_ENCODE, 19          /* a: the block's post-state; data: its bytes, a NODE_DB_REF or 0; target: the connection; arg: op + 256 * flags + 65536 * NodeBlock index */
.set NODE_WORK_API_CHUNK, 20           /* data: the SSZ bytes, or a NODE_DB_REF; target: the connection; arg: the NodeApi index */
.set NODE_WORK_API_LOOKUP, 21          /* a: the head's post-state; target: the connection; arg: the NodeApi index */
.set NODE_WORK_API_EVENT, 22           /* a: a block's post-state, or 0; data: its bytes, or 0; arg: topic + 256 * values + 65536 * epoch */
.set NODE_WORK_API_SUBMIT, 23          /* a: the head's post-state; data: a request's body; target: the connection; arg: op + 256 * flags + 65536 * fork */
.set NODE_WORK_POOL_CHECK, 24          /* a: the head's post-state; data: a pool entry's bytes; target: its index; arg: its topic */
.set NODE_WORK_PREPARE_PAYLOAD, 25     /* a: the head's post-state at the next slot; arg: the engine id */
.set NODE_WORK_PRODUCE_CHECK, 26       /* a: the state of a produceBlockV3; target: its NodeApi index */
.set NODE_WORK_GET_PAYLOAD, 27         /* target: the NodeApi index of a produceBlockV3; arg: the engine id */
.set NODE_WORK_PRODUCE_FOLD, 28        /* a: the state; b: a pool entry's bytes; data: the draft, or 0; target: the NodeApi index */
.set NODE_WORK_PRODUCE_BLOCK, 29       /* a: the state; b: the engine's result, or 0; c: the bid, or 0; data: the draft; target: the NodeApi index */
.set NODE_PRODUCE_STATE, 1             /* NodeApi member of a produceBlockV3: its phase */
.set NODE_PRODUCE_PAYLOAD, 2
.set NODE_PRODUCE_FOLD, 3
.set NODE_PRODUCE_BUILD, 4
.set NODE_PRODUCE_BID, 5               /* after the folds: the header call in flight, or the bid's check */
.set NODE_PRODUCE_ETH1, 6              /* after the folds: the eth1 vote and deposits (node.md) */
.set PRODUCE_ETH1_SNAP, 192            /* the cursor of a produceBlockV3 entry: its Eth1Snapshot's id while its work is in flight */
.set NODE_WORK_PUBLISH_DECODE, 30      /* data: a publishBlockV2 body; target: its NodeApi index; arg: the fork + 2^8 for SSZ */
.set NODE_WORK_PUBLISH_SIDECARS, 31    /* b: the sidecars' buffer; data: the body; target: the NodeApi index; arg: the fork + 2^8 for SSZ */
.set NODE_WORK_PUBLISH_CHECK, 32       /* a: the parent's post-state at the slot; b: the sidecars, or 0; c: the head's post-state; data: the block; arg: the level */
.set NODE_WORK_PUBLISH_SIDECAR, 33     /* b: the sidecars; target: the NodeApi index; arg: the sidecar's place */
.set NODE_WORK_LC_BLOCK, 34            /* a: an imported block's post-state; c: the light client store; data: the block */
.set NODE_WORK_LC_HEAD, 35             /* c: the light client store */
.set NODE_WORK_LC_SERVE, 36            /* c: the light client store; data: the request bytes, or 0; target: the stream handle; arg: the method */
.set NODE_WORK_LC_GOSSIP, 37           /* c: the light client store; data: a message's bytes; target: its handle; arg: the topic */
.set NODE_WORK_LC_PUBLISH, 38          /* c: the light client store; arg: the topic */
.set NODE_WORK_PRODUCE_BID, 39         /* a: the state of a produceBlockV3; data: the builder's answer; target: the NodeApi index */
.set NODE_WORK_ETH1_CHECK, 40          /* a: the head's post-state */
.set NODE_WORK_PRODUCE_ETH1, 41        /* a: the state of a produceBlockV3; b: its Eth1Snapshot; data: its draft; target: the NodeApi index */
.set NODE_WORK_ARCHIVE_LOAD, 42        /* a: the state to write; b: with a diff, the full record's NODE_DB_REF; data: the record's NODE_DB_REF */
.set NODE_WORK_CUSTODY, 43             /* a: F's post-state: the custody group count of the node's validators */
.set NODE_WORK_RECONSTRUCT, 44         /* b: the sidecars' buffer; data: the held sidecars, joined */
.set NODE_LC_ID, 2                     /* the BufferId of the light client store (lantern_node_init: Caller must) */
.set NODE_PUBLISH_DECODE, 1            /* NodeApi member of a publishBlockV2: its phase */
.set NODE_PUBLISH_SIDECARS, 2
.set NODE_PUBLISH_CHECK, 3
.set NODE_PUBLISH_IMPORT, 4
.set NODE_PUBLISH_SUBMIT, 5            /* a blinded block: its submitBlindedBlockV2 call in flight */
.set PUB_BLOB_BYTES, FIELD_ELEMENTS_PER_BLOB * BYTES_PER_FIELD_ELEMENT    /* a Blob */
.set PUB_CELL_BYTES, FIELD_ELEMENTS_PER_CELL * BYTES_PER_FIELD_ELEMENT    /* a Cell */
.set PUB_HEADER_BYTES, 208             /* a SignedBeaconBlockHeader */
.set PUB_BLOB_SIDECAR, 8 + PUB_BLOB_BYTES + 96 + PUB_HEADER_BYTES + 32 * KZG_COMMITMENT_INCLUSION_PROOF_DEPTH   /* a BlobSidecar */
.set PUB_COLUMN_FIXED, 8 + 12 + PUB_HEADER_BYTES + 32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH  /* a DataColumnSidecar's fixed part; each blob adds a cell and two 48-byte items */
.set PUB_COMMITMENTS_GINDEX, 16 + 11   /* blob_kzg_commitments: field 11 of the 16 leaves of BeaconBlockBody, deneb to fulu */
.if 4 + 1 + 12 - KZG_COMMITMENT_INCLUSION_PROOF_DEPTH || MAX_BLOB_COMMITMENTS_PER_BLOCK - 4096 || 4 - KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH
.error "the inclusion proofs are not of field 11 of 16 leaves and 4096 commitments"
.endif
.set NODE_VOTES_MAX, 130               /* MAX_ATTESTATIONS + MAX_ATTESTER_SLASHINGS: the votes of a block the node takes */
.set NodeEvent_root, NodeEvent_checkpoint + 8  /* GOSSIP of a valid beacon_block, SYNC_BLOCK: its root; of a valid blob_sidecar, BLOB: the root of its block header */
.set NodeEvent_index, NodeEvent_root + 32      /* GOSSIP of a valid beacon_block, SYNC_BLOCK: its blob commitments; of a valid blob_sidecar: its index */
.set NodeEvent_chunk, NODE_EV_WORK_DONE_SIZE   /* SERVE: a ByteList of the response chunk after the WORK_DONE fields; NEW_PAYLOAD, FORKCHOICE: of the HTTP request */
.set NodeEvent_api, NodeEvent_chunk           /* API_CHUNK: sent, flags, a JsonCursor, after the chunk */
.set NodeEvent_api_bytes, NodeEvent_api + 616 /* API_CHUNK: a ByteList of the chunk's bytes */
.set LANTERN_NEED_TARGET_STATE, 55     /* lantern_node_run: an attestation needs its target checkpoint state */
.set LANTERN_INVALID_ENCODING, 56     /* lantern_node_run, the node hooks: the bytes are not an SSZ encoding of the type; lantern_get_execution_requests: a list the spec rejects */
.set LANTERN_INVALID_EVENT, 57        /* lantern_node_step: an event breaks the rules of its kind */
.set LANTERN_INVALID_BLOB_SIDECAR, 58  /* lantern_node_blob_sidecar: the index, the inclusion proof or the KZG proof fails */
.set LANTERN_NO_PAYLOAD, 59            /* lantern_node_new_payload: the block has no execution payload to send */
.set LANTERN_INVALID_CONFIG, 60        /* lantern_config_parse: a faulty line */
.set LANTERN_INVALID_OPTION, 61        /* lantern_app_options: a faulty argument */
.set LANTERN_INVALID_COLUMN_SIDECAR, 62 /* lantern_node_column_sidecar: verify_data_column_sidecar, the inclusion proof or the KZG proofs fail */
.set LANTERN_INVALID_RECORD, 63        /* lantern_db_add: a record breaks a rule of docs/reference/db.md */
.set LANTERN_NO_STATE_ANSWER, 66       /* lantern_node_randao, lantern_node_sync_committee, lantern_node_proposer_lookahead: the state holds no answer */
.set LANTERN_NO_BID, 67                /* NODE_WORK_PRODUCE_BID: the builder's answer is not 200 */
.set LANTERN_INVALID_BID, 68           /* lantern_node_produce_bid: the bid fails a check */
.set LANTERN_INVALID_DEPOSIT_LOG, 69   /* lantern_eth1_deposit_logs: a log's data is not the deposit contract's encoding */
.set LANTERN_INVALID_INDEX, 70         /* lantern_deposit_proof: the index is not below the count */
.set Eth1Block_number, 0               /* Eth1Block (eth1.md) */
.set Eth1Block_timestamp, 8
.set Eth1Block_deposit_count, 16
.set Eth1Block_hash, 24
.set Eth1Block_deposit_root, 56
.set Eth1Block__mem, 88
.set Eth1Deposit_block_number, 0       /* Eth1Deposit (eth1.md) */
.set Eth1Deposit_index, 8
.set Eth1Deposit_data, 16              /* DepositData: pubkey 48, withdrawal_credentials 32, amount 8, signature 96 */
.set Eth1Deposit__mem, 200
.set DepositTree_count, 0              /* DepositTree (eth1.md) */
.set DepositTree_branch, 8
.set DepositTree__mem, 8 + 32 * DEPOSIT_CONTRACT_TREE_DEPTH

/* Db: the index of the stored history (docs/reference/db.md) */
.set Db_first_slot, 8
.set Db_end_slot, 16
.set Db_slots, 24                      /* PartRef of DbSlot; count: the capacity */
.set Db_roots, 40                      /* PartRef of u64; count: the capacity, a power of two */
.set Db_blocks, 56
.set DB_FIXED, 64
.set DbRoom_slots, 0
.set DbRoom_roots, 8
.set DbSlot_root, 0
.set DbSlot_block, 32                  /* 0, or the offset + 1 of the block record */
.set DbSlot_sidecars, 40               /* 0, or the offset + 1 of the first sidecar record */
.set DbSlot_sidecar_count, 48
.set DbSlot_sidecar_end, 56
.set DbSlot_sidecar_last, 64
.set DbSlot_indices, 72                /* bit i % 8 of byte i / 8 for each sidecar index i */
.set DbSlot_state, 88                  /* 0, or the offset + 1 of the state record */
.set DbSlot__mem, 96
.set DbRecord_kind, 0
.set DbRecord_slot, 8
.set DbRecord_index, 16
.set DbRecord_root, 24
.set DbRecord_bytes, 56               /* a ByteList header of the SSZ bytes after the record's header: size 24 + length, offset 24, count */
.set DbRecord_length, 72              /* its count: the SSZ bytes */
.set DbRecord__mem, 80
.set DB_BLOCK, 1
.set DB_BLOB_SIDECAR, 2
.set DB_COLUMN_SIDECAR, 3
.set DB_STATE, 4                        /* the full state of a state segment, at offset 0 */
.set DB_STATE_DIFF, 5                   /* a diff against it */
.set DB_OFFSET_MAX, 1 << 44             /* a record's offset is below this */
.set DB_ARCHIVE_DIFF, 256               /* the app's archive_slots with --archive */
.set DB_SEGMENT_SLOTS, 8192
.set DB_RECORD_MAX, 1 << 32
.set DB_SIDECAR_INDICES, 128           /* a sidecar's index is below this */

/* ApiView: the values the node's Beacon API answers show (beacon-api.md, Common rules), in scratch; internal. A text field is a length, then its bytes. */
.set ApiView_genesis_time, 0
.set ApiView_genesis_validators_root, 8
.set ApiView_genesis_fork_version, 40
.set ApiView_head_slot, 48
.set ApiView_head_root, 56
.set ApiView_proposer_index, 88
.set ApiView_parent_root, 96
.set ApiView_state_root, 128
.set ApiView_body_root, 160
.set ApiView_signature, 192
.set ApiView_previous_justified, 288
.set ApiView_current_justified, 328
.set ApiView_finalized, 368
.set ApiView_current_slot, 408
.set ApiView_is_syncing, 416
.set ApiView_is_optimistic, 424
.set ApiView_el_offline, 432
.set ApiView_peers, 440
.set ApiView_seq_number, 448
.set ApiView_attnets, 456
.set ApiView_syncnets, 464
.set ApiView_custody_group_count, 472
.set ApiView_fork, 480
.set ApiView_peer_id, 488                /* the ApiIdentity, from here to the end: 64 bytes of text */
.set ApiView_enr, 560                    /* 512 */
.set ApiView_p2p_address, 1080           /* 128 */
.set ApiView_discovery_address, 1216     /* 128 */
.set ApiView_version, 1352               /* 64 */
.set ApiView_head_finalized, 1424        /* 1 when the block or the state is finalized (beacon-api.md) */
.set ApiView_canonical, 1432             /* lookup: 1 when the block is on the chain */
.set ApiView_look_index, 1440            /* lookup: the block's NodeBlock index, or 2^64 - 1 */
.set ApiView_look_data, 1448             /* lookup: the block's bytes (BufferId or NODE_DB_REF), or 0 */
.set ApiView_look_state, 1456            /* lookup: the state's id (the block's post-state, a checkpoint state, a copy), or 0 */
.set ApiView_look_state_slot, 1464       /* lookup: that state's slot */
.set ApiView_look_copy, 1472             /* lookup: 1 when look_state is a copy that goes after its use */
.set ApiView_state_fork, 1480            /* getStateFork: the Fork, 16 bytes */
.set ApiView_config, 1496               /* the address of the node's config */
.set ApiView_val_state, 1504            /* getStateValidator: the state */
.set ApiView_val_index, 1512            /* getStateValidator: the validator's index */
.set ApiView_duties, 1520               /* getProposerDuties: lantern_node_proposers's out, 32 + 8 * SLOTS_PER_EPOCH bytes */
.set ApiView_event_slot, ApiView_duties + 32 + 8 * SLOTS_PER_EPOCH  /* an event (beacon-api.md, eventstream): its slot */
.set ApiView_event_epoch, ApiView_event_slot + 8
.set ApiView_event_flags, ApiView_event_slot + 16   /* 1 epoch_transition, 2 execution_optimistic */
.set ApiView_event_block, ApiView_event_slot + 24   /* lantern_node_event_roots's out: block, state, previous, current */
.set ApiView_event_state, ApiView_event_slot + 56
.set ApiView_event_previous, ApiView_event_slot + 88
.set ApiView_event_current, ApiView_event_slot + 120
.set ApiView_event_old_block, ApiView_event_previous   /* chain_reorg: the old head's root, in the place of the head's dependent roots */
.set ApiView_event_old_state, ApiView_event_current    /* chain_reorg: the old head block's state_root */
.set ApiView_att, ApiView_event_slot + 152      /* produceAttestationData: lantern_node_attestation_data's out, 128 bytes */
.set ApiView_ad_out, ApiView_att + 128       /* getAttesterDuties: lantern_node_attester_duties's out */
.set ApiView_ad_count, ApiView_att + 136     /* its items */
.set ApiView_status, ApiView_att + 144       /* a work's answer: 0 for 200, else its error status */
.set ApiView_randao, ApiView_att + 152       /* getStateRandao: lantern_node_randao's out, 32 bytes */
.set ApiView_sync_out, ApiView_att + 184     /* getEpochSyncCommittees: the address of lantern_node_sync_committee's out */
.set ApiView_lookahead, ApiView_att + 192    /* getProposerLookahead: lantern_node_proposer_lookahead's out */
.set API_LOOKAHEAD_SLOTS, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH
.set ApiView_heads, ApiView_lookahead + 8 * API_LOOKAHEAD_SLOTS  /* getDebugChainHeadsV2: a byte for each store node, at the end of scratch */
.set ApiView_weights, ApiView_heads + 8   /* getDebugForkChoice: lantern_node_weights's out, at the end of scratch */
.set ApiView_peer_states, ApiView_weights + 8      /* getPeers: the state set, all bits with none */
.set ApiView_peer_directions, ApiView_weights + 16 /* getPeers: the direction set, all bits with none */
.set ApiView_peer, ApiView_weights + 24            /* getPeer: its NodePeer */
.set ApiView_node, ApiView_weights + 32            /* getPeers: the Node */
.set ApiView_next_period, ApiView_weights + 40     /* getSyncCommitteeDuties: 1, API_VALUE_NEXT_PERIOD of the work */
.set ApiView_sd_ids, ApiView_weights + 48          /* getSyncCommitteeDuties, getLiveness: the address of the work's ValidatorRef items */
.set ApiView_live_out, ApiView_weights + 56        /* getLiveness: lantern_node_liveness's out, a byte for each item */
.set ApiView_lc_bytes, ApiView_weights + 64        /* the light client reads: the ByteList of the object's SSZ bytes */
.set ApiView_lc_json, ApiView_weights + 72         /* as JSON: the ByteList of its JSON, else 0 */
.set ApiView_lc_store, ApiView_weights + 80        /* getLightClientUpdatesByRange: the LcStore */
.set ApiView_lc_cursor, ApiView_weights + 88       /* its JsonCursor */
.set ApiView_lc_start, ApiView_weights + 96        /* its first period */
.set ApiView_lc_end, ApiView_weights + 104         /* the period after its last */
.set ApiView_lc_ssz, ApiView_weights + 112         /* 1 for an SSZ answer */
.set ApiView_look_replay, ApiView_weights + 120   /* 1: node_api_state may start the replay and answer 1 (wait) */
.set ApiView__size, ApiView_weights + 128
.set MAX_REQUEST_LIGHT_CLIENT_UPDATES, 128         /* altair light-client p2p-interface.md, Configuration */
.set ApiIdentity_peer_id, 0              /* ApiIdentity (beacon-api.md): texts, each a length and its room */
.set ApiIdentity_enr, 72
.set ApiIdentity_p2p_address, 592
.set ApiIdentity_discovery_address, 728
.set ApiIdentity_version, 864
.set API_IDENTITY_SIZE, 936
.set API_ANSWER_CLOSE, 1                 /* the answer flags of a NODE_WORK_API_ENCODE's arg, times 256 */
.set API_ANSWER_HTTP10, 2
.set API_ANSWER_SSZ, 4                   /* produceAttestationData: the answer is SSZ */
.set NODE_API_SCRATCH, 8192              /* the step's scratch for a NODE_EV_API, and 4 bytes per byte of its query */
.set NODE_API_CHUNK, 65536               /* the most bytes of a NODE_ACT_API_SEND of a stream */
.set NODE_API_FIRST_ROOM, 1024           /* the least room for the first chunk of a stream */
.set NodeApi_connection, 0               /* NodeApi (node.md): an answer the node streams; 0 for a free entry */
.set NodeApi_op, 8
.set NodeApi_flags, 16                   /* API_STREAM_* */
.set NodeApi_data, 24                    /* the BufferId of the SSZ bytes, or a NODE_DB_REF */
.set NodeApi_fork, 32
.set NodeApi_sent, 40                    /* SSZ: the bytes of data sent */
.set NodeApi_cursor, 48                  /* JSON: a JsonCursor */
.set NodeApi_slot, 648                   /* the slot of the block or the state */
.set NodeApi_state, 656                  /* the validator streams: the id of their state */
.set NodeApi_member, 664                 /* a pool stream: the member of the entry at slot */
.set NodeApi_filter_slot, 672            /* a pool stream: the slot of its entries, or 2^64 - 1 */
.set NodeApi_filter_index, 680           /* a pool stream: the committee index of its entries, or 2^64 - 1 */
.set NodeApi_root, 688                   /* a sidecar stream: the block's root */
.set NodeApi__mem, 720
.set NodeApi_position, NodeApi_cursor    /* the validator streams: the next index */
.set NodeApi_statuses, NodeApi_cursor + 8   /* the validator streams: the status bits */
.set API_STREAM_CLOSE, 1
.set API_STREAM_HTTP10, 2
.set API_STREAM_SSZ, 4
.set API_STREAM_OWN, 8
.set API_STREAM_BUSY, 16
.set API_STREAM_GONE, 32
.set API_STREAM_STARTED, 64
.set API_STREAM_CHUNKED, 128
.set API_STREAM_OPTIMISTIC, 256
.set API_STREAM_FINALIZED, 512
.set API_STREAM_DONE, 1024
.set API_STREAM_LOOKUP, 2048           /* the entry waits for a NODE_WORK_API_LOOKUP */
.set API_STREAM_OWN_STATE, 4096        /* the stream frees its state at its end */
.set API_STREAM_ITEMS, 8192            /* a pool stream wrote an entry */
.set API_STREAM_ITEM_DONE, 16384       /* in a WORK_DONE only: the chunk ends a pool entry */
.set API_STREAM_FOLD, 32768             /* getAggregatedAttestationV2: its chunks fold the pool's entries, sending nothing */
.set API_STREAM_PRODUCE_OWN, 65536     /* produceBlockV3: the pool entry bytes of its fold in flight (root) are its to free */
.set API_STREAM_PRODUCE_FORCED, 131072  /* produceBlockV3: it made a preparation of its slot */
.set API_STREAM_BLOB_SKIP, 262144      /* in a WORK_DONE only: the blob stream skips the rest of a blob */
.set API_STREAM_PRODUCE_BLINDED, 524288  /* a produceBlockV3 answers a blinded block */
.set API_STREAM_REPLAY, 1048576       /* a lookup entry waits for the replay (node.md) */
.set API_REPLAY_SLOT, 136              /* the cursor of a lookup entry that waits for the replay: the slot of its state_id */
.set LC_BRANCH_CURRENT_SYNC_COMMITTEE, 0   /* lantern_state_branch (light-client.md): the field */
.set LC_BRANCH_NEXT_SYNC_COMMITTEE, 1
.set LC_BRANCH_FINALIZED_ROOT, 2
.set EXECUTION_PAYLOAD_GINDEX, 25          /* capella light-client/sync-protocol.md: execution_payload of BeaconBlockBody */

/* Light client objects and the LcStore (docs/reference/light-client.md) */
.set LC_OBJECT_BOOTSTRAP, 0                /* lantern_lc_object, lantern_lc_read: the kind */
.set LC_OBJECT_UPDATE, 1
.set LC_OBJECT_FINALITY_UPDATE, 2
.set LC_OBJECT_OPTIMISTIC_UPDATE, 3
.set LC_FREE, 0                            /* the state of an LcStore record */
.set LC_USED, 1
.set LC_MARKED, 2
.set LC_AGGREGATE, SYNC_COMMITTEE_SIZE / 8 + 96             /* the SSZ bytes of a SyncAggregate */
.set LC_AGGREGATE_ROOM, (LC_AGGREGATE + 7) & ~7
.set LC_COMMITTEE, 48 * SYNC_COMMITTEE_SIZE + 48            /* the SSZ bytes of a SyncCommittee */
.set LC_HEADER_ROOM, 864                   /* a LightClientHeader: 244, a deneb ExecutionPayloadHeader's fixed part, MAX_EXTRA_DATA_BYTES */
.set LC_UPDATE_ROOM, (4 + LC_COMMITTEE + 192 + 4 + 224 + LC_AGGREGATE + 8 + 2 * LC_HEADER_ROOM + 7) & ~7   /* the most bytes of an update, up to a multiple of 8 */
/* The fields of each kind for lantern_lc_object: 3 bits each, the first field lowest. */
.set LCO_HEADER, 1
.set LCO_COMMITTEE, 2
.set LCO_BRANCH, 3
.set LCO_FINALIZED, 4
.set LCO_FINALITY, 5
.set LCO_AGGREGATE, 6
.set LCO_SLOT, 7
.set LCO_BOOTSTRAP_FIELDS, LCO_HEADER | (LCO_COMMITTEE << 3) | (LCO_BRANCH << 6)
.set LCO_UPDATE_FIELDS, LCO_HEADER | (LCO_COMMITTEE << 3) | (LCO_BRANCH << 6) | (LCO_FINALIZED << 9) | (LCO_FINALITY << 12) | (LCO_AGGREGATE << 15) | (LCO_SLOT << 18)
.set LCO_FINALITY_FIELDS, LCO_HEADER | (LCO_FINALIZED << 3) | (LCO_FINALITY << 6) | (LCO_AGGREGATE << 9) | (LCO_SLOT << 12)
.set LCO_OPTIMISTIC_FIELDS, LCO_HEADER | (LCO_AGGREGATE << 3) | (LCO_SLOT << 6)
.set LcParts_header, 0
.set LcParts_sync_committee, 8
.set LcParts_branch, 16
.set LcParts_branch_count, 24
.set LcParts_finalized_header, 32
.set LcParts_finality_branch, 40
.set LcParts_finality_count, 48
.set LcParts_sync_aggregate, 56
.set LcParts_signature_slot, 64
.set LcParts__mem, 72
.set LcRoom_blocks, 0
.set LcRoom_finalized, 8
.set LcRoom_periods, 16
.set LcRoom_bootstraps, 24
.set LcRoom_headers, 32
.set LcRoom_committees, 40
.set LcRoom_updates, 48
.set LcRoom__mem, 56
.set LcStore_tail_slot, 8
.set LcStore_historical_tail_slot, 16
.set LcStore_latest_finalized_epoch, 24
.set LcStore_latest_finalized_slot, 32
.set LcStore_latest_finalized_root, 40
.set LcStore_latest, 72
.set LcStore_room, 80
.set LcStore_blocks, 136                   /* the entry counts of the parts, in LcRoom order */
.set LcStore_finalized, 144
.set LcStore_periods, 152
.set LcStore_bootstraps, 160
.set LC_STORE_FIXED, 168
.set LC_PART_BLOCKS, 0                     /* the parts of an LcStore, in order */
.set LC_PART_FINALIZED, 1
.set LC_PART_PERIODS, 2
.set LC_PART_BOOTSTRAPS, 3
.set LC_PART_HEADERS, 4
.set LC_PART_COMMITTEES, 5
.set LC_PART_UPDATES, 6
.set LcBlock_root, 0
.set LcBlock_parent_root, 32
.set LcBlock_slot, 64
.set LcBlock_parent, 72
.set LcBlock_data, 80
.set LcBlock_header, 88
.set LcBlock_current_sync_committee, 96
.set LcBlock_next_sync_committee, 104
.set LcBlock_best, 112
.set LcBlock_finalized_slot, 120
.set LcBlock_latest_signature_slot, 128
.set LcBlock_sync_aggregate, 136
.set LcBlock_current_branch, 136 + LC_AGGREGATE_ROOM
.set LcBlock_next_branch, 328 + LC_AGGREGATE_ROOM
.set LcBlock_finality_branch, 520 + LC_AGGREGATE_ROOM
.set LcBlock__mem, 744 + LC_AGGREGATE_ROOM
.set LcFinalized_slot, 0
.set LcFinalized_root, 8
.set LcFinalized__mem, 40
.set LcPeriod_period, 0
.set LcPeriod_update, 8
.set LcPeriod__mem, 16
.set LcBootstrap_root, 0
.set LcBootstrap_slot, 32
.set LcBootstrap_header, 40
.set LcBootstrap_sync_committee, 48
.set LcBootstrap_branch, 56
.set LcBootstrap__mem, 248
.set LcHeader_state, 0
.set LcHeader_fork, 8
.set LcHeader_header, 16
.set LcHeader__mem, 40 + LC_HEADER_ROOM
.set LcCommittee_state, 0
.set LcCommittee_committee, 8
.set LcCommittee__mem, 8 + LC_COMMITTEE
.set LcUpdate_state, 0
.set LcUpdate_fork, 8
.set LcUpdate_attested_header, 16
.set LcUpdate_finalized_header, 24
.set LcUpdate_next_sync_committee, 32
.set LcUpdate_signature_slot, 40
.set LcUpdate_next_branch, 48
.set LcUpdate_finality_branch, 240
.set LcUpdate_sync_aggregate, 464
.set LcUpdate__mem, 464 + LC_AGGREGATE_ROOM
.set LC_COMPARE_SCRATCH, 8 + 2 * (24 + LC_UPDATE_ROOM) + 2 * (24 + LC_HEADER_ROOM)   /* lantern_lc_on_block: the scratch of a comparison */
.set API_VALUE_CANONICAL, 1              /* the values of a NODE_WORK_API_ENCODE's arg, times 2^16 */
.set API_VALUE_FINALIZED, 2
.set API_VALUE_OPTIMISTIC, 4
.set API_VALUE_NEXT_PERIOD, 8            /* getSyncCommitteeDuties: the epoch's period is the next of the state's */
.set NODE_STATE_FORK, 56               /* BeaconState.fork in the value of every fork */
.set NODE_STATE_VALIDATORS, 296 + 64 * SLOTS_PER_HISTORICAL_ROOT   /* BeaconState.validators, a PartRef, in every fork */
.set NODE_STATE_BALANCES, NODE_STATE_VALIDATORS + 16                /* BeaconState.balances, a PartRef of u64 */
.set NODE_STATE_FINALIZED, NODE_STATE_VALIDATORS + 32 + 32 * EPOCHS_PER_HISTORICAL_VECTOR + 8 * EPOCHS_PER_SLASHINGS_VECTOR + 32 + 8 + 80   /* BeaconState.finalized_checkpoint in the value of every fork */
.set NODE_STATE_CURRENT_SYNC_COMMITTEE, NODE_STATE_FINALIZED + 40 + 16   /* BeaconState.current_sync_committee from altair: its SSZ bytes */
.set NODE_STATE_NEXT_SYNC_COMMITTEE, NODE_STATE_CURRENT_SYNC_COMMITTEE + 48 * SYNC_COMMITTEE_SIZE + 48
.set NODE_VALIDATOR_MEM, 128           /* a Validator in a state's value: its fields at these offsets */
.set NODE_VALIDATOR_CREDENTIALS, 48
.set NODE_VALIDATOR_EFFECTIVE_BALANCE, 80
.set NODE_VALIDATOR_SLASHED, 88
.set NODE_VALIDATOR_ELIGIBILITY, 96
.set NODE_VALIDATOR_ACTIVATION, 104
.set NODE_VALIDATOR_EXIT, 112
.set NODE_VALIDATOR_WITHDRAWABLE, 120
.set NODE_STATE_STATE_ROOTS, 184 + 32 * SLOTS_PER_HISTORICAL_ROOT  /* BeaconState.state_roots in the value of every fork */
.set NODE_JSON_BLOCK, 0                  /* lantern_node_json: a SignedBeaconBlock */
.set NODE_JSON_STATE, 1                  /* a BeaconState */
.set NODE_JSON_EXIT, 2                   /* a SignedVoluntaryExit */
.set NODE_JSON_PROPOSER_SLASHING, 3      /* a ProposerSlashing */
.set NODE_JSON_ATTESTER_SLASHING, 4      /* an AttesterSlashing */
.set NODE_JSON_BLS_CHANGE, 5             /* a SignedBLSToExecutionChange, from capella */
.set NODE_JSON_ATTESTATION, 6            /* an Attestation */
.set NODE_JSON_SINGLE_ATTESTATION, 7     /* a SingleAttestation, from electra */
.set NODE_JSON_ATTESTATIONS, 8           /* an Attestations list, a block body's */
.set NODE_JSON_BLINDED_BLOCK, 9          /* a SignedBlindedBeaconBlock from bellatrix, a SignedBeaconBlock before */
.set NODE_JSON_BLOB_SIDECAR, 10          /* a BlobSidecar, of deneb and electra */
.set NODE_JSON_DATA_COLUMN_SIDECAR, 11   /* a DataColumnSidecar, from fulu */
.set NODE_JSON_AGGREGATE_AND_PROOF, 12   /* a SignedAggregateAndProof */
.set NODE_JSON_SYNC_COMMITTEE_MESSAGE, 13 /* a SyncCommitteeMessage, from altair */
.set NODE_JSON_SYNC_CONTRIBUTION, 14     /* a SyncCommitteeContribution, from altair */
.set NODE_JSON_CONTRIBUTION_AND_PROOF, 15 /* a SignedContributionAndProof, from altair */
.set NODE_JSON_COMMITTEE_SUBSCRIPTION, 16 /* lantern's BeaconCommitteeSubscription */
.set NODE_JSON_SYNC_SUBSCRIPTION, 17     /* lantern's SyncCommitteeSubscription, from altair */
.set NODE_JSON_PROPOSER_PREPARATION, 18  /* lantern's ProposerPreparation */
.set NODE_JSON_BEACON_BLOCK, 19          /* a BeaconBlock (produceBlockV3 before deneb) */
.set NODE_JSON_LC_BOOTSTRAP, 21         /* a LightClientBootstrap, from altair */
.set NODE_JSON_LC_UPDATE, 22            /* a LightClientUpdate, from altair */
.set NODE_JSON_LC_FINALITY_UPDATE, 23   /* a LightClientFinalityUpdate, from altair */
.set NODE_JSON_LC_OPTIMISTIC_UPDATE, 24 /* a LightClientOptimisticUpdate, from altair */
.set NODE_JSON_VALIDATOR_REGISTRATION, 25   /* a SignedValidatorRegistrationV1 of builder-specs */
.set NODE_JSON_BLINDED_BEACON_BLOCK, 26    /* a BlindedBeaconBlock from bellatrix (produceBlockV3), a BeaconBlock before */
.set NODE_JSON_BUILDER_BID, 27             /* a SignedBuilderBid of builder-specs, from bellatrix */
.set NODE_JSON_BLOCK_CONTENTS, 20        /* lantern's BlockContents, from deneb */
.set NodePool_topic, 0                   /* NodePool (node.md): GOSSIP_* of the operation; 0 for a free entry */
.set NodePool_state, 8                   /* NODE_POOL_* */
.set NodePool_data_id, 16                /* the BufferId of its SSZ bytes */
.set NodePool_length, 24
.set NodePool_fork, 32                   /* FORK_* of the type it was decoded with */
.set NodePool_slot, 40                   /* an attestation: its data.slot */
.set NodePool_index, 48                  /* an attestation: its committee index */
.set NodePool_member, 56                 /* a SingleAttestation: its place + 2^16 x its committee's length */
.set NodePool__mem, 64
.set NODE_POOL_ATTESTATION_ROOM, 1024    /* scratch of the electra Attestation of a SingleAttestation */
.set NODE_POOL_ATTESTATION_FIXED, 4 + 128 + 96 + (MAX_COMMITTEES_PER_SLOT + 7) / 8   /* electra Attestation: offset, data, signature, committee_bits */
.set NODE_POOL_KEPT, 1
.set NODE_POOL_CHECKING, 2               /* its NODE_WORK_POOL_CHECK is queued */

/* HttpLimits and HttpRequest (docs/reference/beacon-api.md): lantern_http_request. */
.set HttpLimits_head_max, 0
.set HttpLimits_body_max, 8
.set HTTP_METHOD_GET, 1
.set HTTP_METHOD_POST, 2
.set HTTP_METHOD_OTHER, 3
.set HttpRequest_size, 0
.set HttpRequest_status, 8
.set HttpRequest_used, 16
.set HttpRequest_method, 24
.set HttpRequest_version, 32
.set HttpRequest_close, 40
.set HttpRequest_path, 48                 /* PartRef; then query, accept, content_type, consensus_version, body */
.set HttpRequest_query, 64
.set HttpRequest_accept, 80
.set HttpRequest_content_type, 96
.set HttpRequest_consensus_version, 112
.set HttpRequest_body, 128
.set HTTP_REQUEST_FIXED, 144

/* ApiRoute and ValidatorRef (docs/reference/beacon-api.md): lantern_api_route. */
.set LANTERN_INVALID_ROUTE, 64          /* lantern_api_route: the request breaks a rule; ApiRoute.status is the HTTP status */
.set API_TYPE_JSON, 1
.set API_TYPE_SSZ, 2
.set API_ID_HEAD, 1
.set API_ID_GENESIS, 2
.set API_ID_FINALIZED, 3
.set API_ID_JUSTIFIED, 4
.set API_ID_SLOT, 5
.set API_ID_ROOT, 6
.set API_VALIDATOR_INDEX, 1
.set API_VALIDATOR_PUBKEY, 2
.set ValidatorRef_kind, 0
.set ValidatorRef_index, 8
.set ValidatorRef_pubkey, 16
.set ValidatorRef__size, 64
.set ApiRoute_size, 0
.set ApiRoute_status, 8
.set ApiRoute_op, 16
.set ApiRoute_allow, 24
.set ApiRoute_fault, 32
.set ApiRoute_present, 40
.set ApiRoute_response, 48
.set ApiRoute_body, 56
.set ApiRoute_consensus_version, 64
.set ApiRoute_id_kind, 72
.set ApiRoute_id_slot, 80
.set ApiRoute_id_root, 88
.set ApiRoute_validator, 120              /* ValidatorRef */
.set ApiRoute_epoch, 184
.set ApiRoute_slot, 192
.set ApiRoute_index, 200
.set ApiRoute_committee_index, 208
.set ApiRoute_subcommittee_index, 216
.set ApiRoute_start_period, 224
.set ApiRoute_count, 232
.set ApiRoute_syncing_status, 240
.set ApiRoute_builder_boost_factor, 248
.set ApiRoute_broadcast_validation, 256
.set ApiRoute_statuses, 264
.set ApiRoute_peer_states, 272
.set ApiRoute_peer_directions, 280
.set ApiRoute_topics, 288
.set ApiRoute_root, 296
.set ApiRoute_randao_reveal, 328
.set ApiRoute_graffiti, 424
.set ApiRoute_list, 456                   /* PartRef: ValidatorRef, u64 or Root items */
.set ApiRoute_peer_id, 472                /* PartRef of bytes */
.set API_ROUTE_FIXED, 488

/* JsonCursor (docs/reference/beacon-api.md): lantern_json_encode. */
.set LANTERN_JSON_MORE, 65              /* lantern_json_encode: out is full; the cursor goes on */
.set JsonCursor_depth, 0
.set JsonCursor_done, 8
.set JsonCursor_whole, 16
.set JsonCursor_levels, 24
.set JSON_LEVELS, 12
.set JsonLevel_node, 0
.set JsonLevel_step, 8
.set JsonLevel_item, 16
.set JsonLevel_count, 24
.set JsonLevel_base, 32
.set JsonLevel_next, 40
.set JSON_LEVEL_SIZE, 48
.set JSON_CURSOR_SIZE, 24 + JSON_LEVELS * JSON_LEVEL_SIZE
.set JsonFault_kind, 0                    /* JsonFault (docs/reference/beacon-api.md): lantern_json_decode */
.set JsonFault_offset, 8
.set JsonFault_size, 16
.set JsonFault_depth, 24
.set JsonFault_path, 32
.set JSON_FAULT_SIZE, 128
.set JSON_FAULT_SYNTAX, 1
.set JSON_FAULT_TYPE, 2
.set JSON_FAULT_NUMBER, 3
.set JSON_FAULT_HEX, 4
.set JSON_FAULT_LENGTH, 5
.set JSON_FAULT_FIELD, 6
.set JSON_FAULT_MISSING, 7
.set JSON_DECODE_SCRATCH, 64 + JSON_LEVELS * 512  /* the field tables of lantern_json_decode, 64 fields a level */

/* ArgList, Arg and AppOptions (docs/reference/app.md): a text field is an Arg (start, length) of the ArgList's bytes. */
.set ArgList_args, 8
.set ArgList_bytes, 24
.set ArgList__fixed, 40
.set Arg_start, 0
.set Arg_length, 8
.set Arg__mem, 16
.set AppOptions_network_dir, 0
.set AppOptions_execution, 16
.set AppOptions_jwt_secret, 32
.set AppOptions_boot_nodes, 48
.set AppOptions_port, 64
.set AppOptions_enr_address, 72
.set AppOptions_http_port, 80
.set AppOptions_target_peers, 88
.set AppOptions_data_dir, 96
.set AppOptions_checkpoint_state, 112
.set AppOptions_checkpoint_block, 128
.set AppOptions_log_level, 144          /* 0 error, 1 warn, 2 info, 3 debug */
.set AppOptions_http_address, 152       /* IPv4, its 4 bytes in network order in the low bytes */
.set AppOptions_http_max_connections, 160
.set AppOptions_supernode, 168        /* 1 with --supernode */
.set AppOptions_builder, 176          /* host:port of the builder, without http:// */
.set AppOptions_archive, 192          /* 1 with --archive */
.set AppOptions__size, 200
.set APP_DEFAULT_PORT, 9000
.set APP_DEFAULT_HTTP_PORT, 5052
.set APP_DEFAULT_TARGET_PEERS, 64
.set APP_DEFAULT_LOG_LEVEL, 2           /* info */
.set APP_MAX_TARGET_PEERS, 1024
.set APP_DEFAULT_HTTP_ADDRESS, 0x0100007f  /* 127.0.0.1 */
.set APP_DEFAULT_HTTP_CONNECTIONS, 64
.set APP_MAX_HTTP_CONNECTIONS, 4096

.if DB_SEGMENT_SLOTS != 1 << DB_SEGMENT_SHIFT
.error "DB_SEGMENT_SHIFT is not the log of DB_SEGMENT_SLOTS"
.endif
