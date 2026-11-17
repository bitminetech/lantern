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
.set CONFIG_SIZE, 392 + 16 * 32 + 152

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

.set LANTERN_INVALID_JSON, 54                   /* lantern_engine_parse_response: not a JSON-RPC response of the method */

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
.set EngineResponse__mem, 96
.set ENGINE_METHOD_NEW_PAYLOAD, 1
.set ENGINE_METHOD_FORKCHOICE_UPDATED, 2
.set ENGINE_METHOD_EXCHANGE_CAPABILITIES, 3
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
.set BlockOptions_pow_block, 16       /* bellatrix: get_pow_block(payload.parent_hash), a PowBlock, or 0 for None */
.set BlockOptions_pow_parent, 24      /* bellatrix: get_pow_block(pow_block.parent_hash), or 0 for None */

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
.set REQRESP_METHODS, 11

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
.set GOSSIP_NAMES, 11

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
.set Node_config, 256
.set NODE_FIXED, 256 + CONFIG_SIZE
.set NODE_STATE_SLOT, 48               /* BeaconState.slot in the value of every fork */

/* NodeBlock: a block the node knows */
.set NodeBlock_root, 0
.set NodeBlock_parent_root, 32
.set NodeBlock_slot, 64
.set NodeBlock_data_id, 72             /* the SignedBeaconBlock's SSZ bytes */
.set NodeBlock_state_id, 80            /* its post-state, 0 until imported */
.set NodeBlock_status, 88              /* NODE_BLOCK_* */
.set NodeBlock_data_available, 96
.set NodeBlock_result, 104             /* the result of its import */
.set NodeBlock__mem, 112
.set NODE_BLOCK_WAITING, 1             /* its parent is not imported yet */
.set NODE_BLOCK_IMPORTING, 2           /* an IMPORT_BLOCK work is queued */
.set NODE_BLOCK_IMPORTED, 3
.set NODE_BLOCK_INVALID, 4
.set NODE_BLOCK_HASHING, 5             /* from a response: a SYNC_BLOCK work of its root is queued; root 0 */

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
.set NodePeer_fork_digest, 24          /* Status: 4 bytes */
.set NodePeer_finalized_root, 32
.set NodePeer_finalized_epoch, 64
.set NodePeer_head_root, 72
.set NodePeer_head_slot, 104
.set NodePeer_earliest_slot, 112       /* Status v2: earliest_available_slot */
.set NodePeer_id_len, 120
.set NodePeer_id, 128                  /* the peer ID, at most 48 bytes */
.set NodePeer__mem, 176

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
.set NodeStream_list, 48               /* a ByteList: the request bytes, then the BufferIds of the blocks to send */
.set NodeStream_request, 72
.set NodeStream__fixed, 72

/* NodeMessage: a gossip message the node holds */
.set NodeMessage_handle, 0             /* the libp2p message Handle */
.set NodeMessage_peer, 8               /* the libp2p peer Handle */
.set NodeMessage_topic, 16             /* GOSSIP_*, or 0 for a topic of no name */
.set NodeMessage_subnet, 24
.set NodeMessage_data_id, 32           /* BufferId of the uncompressed bytes, or 0 */
.set NodeMessage_state, 40             /* NODE_MESSAGE_* */
.set NodeMessage_slot, 48              /* the slot of its block or block header */
.set NodeMessage_parent_root, 56       /* the parent root of its block or block header */
.set NodeMessage__mem, 88
.set NODE_MESSAGE_ID, 1                /* its MESSAGE_ID is sent */
.set NODE_MESSAGE_VALIDATING, 2        /* a GOSSIP work is queued */
.set NODE_MESSAGE_NO_ROOM, 3           /* the bytes did not fit in the actions: IGNORE */
.set NODE_MESSAGE_CORRUPT, 4           /* the data is no Snappy block of at most MAX_PAYLOAD_SIZE bytes: REJECT */

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
.set NodeAnchor__mem, 72
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

/* NodeStepResult: the output of lantern_node_step */
.set NodeStepResult_accepted, 0        /* events handled, from the first */
.set NodeStepResult_wakeup, 8          /* monotonic ms by which the next step is due; 2^64 - 1 for none */

/* NodeEvent kinds, after the size and kind header */
.set NODE_EV_TICK, 1                   /* 16 time_ms */
.set NODE_EV_BLOCK, 2                  /* 16 data_available, 24 a ByteList of the SSZ bytes */
.set NODE_EV_ATTESTATION, 3            /* 16 is_from_block, 24 a ByteList of the SSZ bytes */
.set NODE_EV_ATTESTER_SLASHING, 4      /* 24 a ByteList of the SSZ bytes */
.set NODE_EV_POW_BLOCK, 5              /* 24 a ByteList of the SSZ bytes */
.set NODE_EV_PAYLOAD_STATUS, 6         /* 16 block_hash, 48 status, 56 has_latest, 64 latest_valid_hash */
.set NODE_EV_WORK_DONE, 7              /* the work's fields from 16 (as NodeAction), then 72 result, 80 checkpoint epoch, 88 root */
.set NODE_EV_P2P, 8                    /* 16 a libp2p shell result Event */
.set NODE_EV_LAST, 8
.set NodeEvent_result, 72
.set NodeEvent_checkpoint, 80
.set NODE_EV_WORK_DONE_SIZE, 120
.set NodeEvent_bytes, 24               /* a ByteList whose bytes start at its offset 24 */

/* NodeAction kinds, after the size and kind header */
.set NODE_ACT_BYTES_PUT, 1             /* 16 id, 24 a ByteList of the bytes */
.set NODE_ACT_STATE_COPY, 2            /* 16 source id, 24 new id */
.set NODE_ACT_STATE_FREE, 3            /* 16 id */
.set NODE_ACT_BYTES_FREE, 4            /* 16 id */
.set NODE_ACT_WORK, 5                  /* 16 kind, 24 state_a, 32 state_b, 40 state_c, 48 data, 56 target, 64 arg */
.set NODE_ACT_P2P_LIST, 6              /* 16 a ByteList of libp2p Actions: the shell does its shell requests in order */
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
.set NODE_WORK_SERVE, 6                /* data: a block's SSZ bytes; target: the stream Handle; arg: the protocol version */
.set NODE_WORK_GOSSIP, 7               /* a: head state; b: proposer state; c: justified state; data: the message; target: its Handle; arg: topic + 256 * subnet */
.set NODE_WORK_SYNC_BLOCK, 8           /* data: a block's SSZ bytes from a response; target: its NodeBlock index */
.set NodeEvent_root, NodeEvent_checkpoint + 8  /* GOSSIP of a valid beacon_block: its root */
.set NodeEvent_chunk, NODE_EV_WORK_DONE_SIZE   /* SERVE: a ByteList of the response chunk after the WORK_DONE fields */
.set LANTERN_NEED_TARGET_STATE, 55     /* lantern_node_run: an attestation needs its target checkpoint state */
.set LANTERN_INVALID_ENCODING, 56     /* lantern_node_run, the node hooks: the bytes are not an SSZ encoding of the type */
.set LANTERN_INVALID_EVENT, 57        /* lantern_node_step: an event breaks the rules of its kind */
