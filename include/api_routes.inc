/*
 * The operations of beacon-APIs v4.0.0 (commit 88fc940) and the names of their parameters, for
 * lantern_api_route (docs/reference/beacon-api.md). The same on every ISA. tests/generator/api_route.py
 * reads the operations from the spec itself, so its cases check this table.
 */

/* API_OP_*: the operations, in the order of `paths` in beacon-node-oapi.yaml, GET before POST. */
.set API_OP_GET_GENESIS, 1
.set API_OP_GET_STATE_ROOT, 2
.set API_OP_GET_STATE_FORK, 3
.set API_OP_GET_STATE_FINALITY_CHECKPOINTS, 4
.set API_OP_GET_STATE_VALIDATORS, 5
.set API_OP_POST_STATE_VALIDATORS, 6
.set API_OP_GET_STATE_VALIDATOR, 7
.set API_OP_GET_STATE_VALIDATOR_BALANCES, 8
.set API_OP_POST_STATE_VALIDATOR_BALANCES, 9
.set API_OP_POST_STATE_VALIDATOR_IDENTITIES, 10
.set API_OP_GET_EPOCH_COMMITTEES, 11
.set API_OP_GET_EPOCH_SYNC_COMMITTEES, 12
.set API_OP_GET_STATE_RANDAO, 13
.set API_OP_GET_PENDING_CONSOLIDATIONS, 14
.set API_OP_GET_PENDING_DEPOSITS, 15
.set API_OP_GET_PENDING_PARTIAL_WITHDRAWALS, 16
.set API_OP_GET_PROPOSER_LOOKAHEAD, 17
.set API_OP_GET_BLOCK_HEADERS, 18
.set API_OP_GET_BLOCK_HEADER, 19
.set API_OP_PUBLISH_BLINDED_BLOCK_V2, 20
.set API_OP_PUBLISH_BLOCK_V2, 21
.set API_OP_GET_BLOCK_V2, 22
.set API_OP_GET_BLOCK_ROOT, 23
.set API_OP_GET_BLOCK_ATTESTATIONS_V2, 24
.set API_OP_GET_BLOB_SIDECARS, 25
.set API_OP_GET_BLOBS, 26
.set API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS, 27
.set API_OP_GET_SYNC_COMMITTEE_REWARDS, 28
.set API_OP_GET_BLOCK_REWARDS, 29
.set API_OP_GET_ATTESTATIONS_REWARDS, 30
.set API_OP_GET_BLINDED_BLOCK, 31
.set API_OP_GET_LIGHT_CLIENT_BOOTSTRAP, 32
.set API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE, 33
.set API_OP_GET_LIGHT_CLIENT_FINALITY_UPDATE, 34
.set API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE, 35
.set API_OP_GET_POOL_ATTESTATIONS_V2, 36
.set API_OP_SUBMIT_POOL_ATTESTATIONS_V2, 37
.set API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, 38
.set API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2, 39
.set API_OP_GET_POOL_PROPOSER_SLASHINGS, 40
.set API_OP_SUBMIT_POOL_PROPOSER_SLASHINGS, 41
.set API_OP_SUBMIT_POOL_SYNC_COMMITTEE_SIGNATURES, 42
.set API_OP_GET_POOL_VOLUNTARY_EXITS, 43
.set API_OP_SUBMIT_POOL_VOLUNTARY_EXIT, 44
.set API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES, 45
.set API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE, 46
.set API_OP_GET_STATE_V2, 47
.set API_OP_GET_DEBUG_CHAIN_HEADS_V2, 48
.set API_OP_GET_DEBUG_FORK_CHOICE, 49
.set API_OP_GET_NETWORK_IDENTITY, 50
.set API_OP_GET_PEERS, 51
.set API_OP_GET_PEER, 52
.set API_OP_GET_PEER_COUNT, 53
.set API_OP_GET_NODE_VERSION, 54
.set API_OP_GET_SYNCING_STATUS, 55
.set API_OP_GET_HEALTH, 56
.set API_OP_GET_FORK_SCHEDULE, 57
.set API_OP_GET_SPEC, 58
.set API_OP_GET_DEPOSIT_CONTRACT, 59
.set API_OP_GET_ATTESTER_DUTIES, 60
.set API_OP_GET_PROPOSER_DUTIES, 61
.set API_OP_GET_SYNC_COMMITTEE_DUTIES, 62
.set API_OP_PRODUCE_BLOCK_V3, 63
.set API_OP_PRODUCE_ATTESTATION_DATA, 64
.set API_OP_GET_AGGREGATED_ATTESTATION_V2, 65
.set API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2, 66
.set API_OP_PREPARE_BEACON_COMMITTEE_SUBNET, 67
.set API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS, 68
.set API_OP_SUBMIT_BEACON_COMMITTEE_SELECTIONS, 69
.set API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, 70
.set API_OP_SUBMIT_SYNC_COMMITTEE_SELECTIONS, 71
.set API_OP_PUBLISH_CONTRIBUTION_AND_PROOFS, 72
.set API_OP_PREPARE_BEACON_PROPOSER, 73
.set API_OP_REGISTER_VALIDATOR, 74
.set API_OP_GET_LIVENESS, 75
.set API_OP_EVENTSTREAM, 76
.set API_OPS, 76

/* API_PARAM_*: the parameters; bit n of ApiRoute.present, and ApiRoute.fault. */
.set API_PARAM_STATE_ID, 1
.set API_PARAM_BLOCK_ID, 2
.set API_PARAM_BLOCK_ROOT, 3
.set API_PARAM_VALIDATOR_ID, 4
.set API_PARAM_PEER_ID, 5
.set API_PARAM_EPOCH, 6
.set API_PARAM_SLOT, 7
.set API_PARAM_ID, 8
.set API_PARAM_STATUS, 9
.set API_PARAM_INDEX, 10
.set API_PARAM_COMMITTEE_INDEX, 11
.set API_PARAM_SUBCOMMITTEE_INDEX, 12
.set API_PARAM_PARENT_ROOT, 13
.set API_PARAM_INDICES, 14
.set API_PARAM_VERSIONED_HASHES, 15
.set API_PARAM_BROADCAST_VALIDATION, 16
.set API_PARAM_START_PERIOD, 17
.set API_PARAM_COUNT, 18
.set API_PARAM_STATE, 19
.set API_PARAM_DIRECTION, 20
.set API_PARAM_SYNCING_STATUS, 21
.set API_PARAM_RANDAO_REVEAL, 22
.set API_PARAM_GRAFFITI, 23
.set API_PARAM_SKIP_RANDAO_VERIFICATION, 24
.set API_PARAM_BUILDER_BOOST_FACTOR, 25
.set API_PARAM_ATTESTATION_DATA_ROOT, 26
.set API_PARAM_BEACON_BLOCK_ROOT, 27
.set API_PARAM_TOPICS, 28
.set API_PARAM_CONSENSUS_VERSION, 29
.set API_PARAMS, 29

/* Bits of ApiRoute.statuses, peer_states, peer_directions and topics. */
.set API_STATUS_PENDING_INITIALIZED, 0
.set API_STATUS_PENDING_QUEUED, 1
.set API_STATUS_ACTIVE_ONGOING, 2
.set API_STATUS_ACTIVE_EXITING, 3
.set API_STATUS_ACTIVE_SLASHED, 4
.set API_STATUS_EXITED_UNSLASHED, 5
.set API_STATUS_EXITED_SLASHED, 6
.set API_STATUS_WITHDRAWAL_POSSIBLE, 7
.set API_STATUS_WITHDRAWAL_DONE, 8
.set API_PEER_DISCONNECTED, 0
.set API_PEER_CONNECTING, 1
.set API_PEER_CONNECTED, 2
.set API_PEER_DISCONNECTING, 3
.set API_DIRECTION_INBOUND, 0
.set API_DIRECTION_OUTBOUND, 1
.set API_TOPIC_HEAD, 0
.set API_TOPIC_BLOCK, 1
.set API_TOPIC_BLOCK_GOSSIP, 2
.set API_TOPIC_ATTESTATION, 3
.set API_TOPIC_SINGLE_ATTESTATION, 4
.set API_TOPIC_VOLUNTARY_EXIT, 5
.set API_TOPIC_BLS_TO_EXECUTION_CHANGE, 6
.set API_TOPIC_PROPOSER_SLASHING, 7
.set API_TOPIC_ATTESTER_SLASHING, 8
.set API_TOPIC_FINALIZED_CHECKPOINT, 9
.set API_TOPIC_CHAIN_REORG, 10
.set API_TOPIC_CONTRIBUTION_AND_PROOF, 11
.set API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE, 12
.set API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE, 13
.set API_TOPIC_PAYLOAD_ATTRIBUTES, 14
.set API_TOPIC_BLOB_SIDECAR, 15
.set API_TOPIC_DATA_COLUMN_SIDECAR, 16

/* An operation's flags (api_routes): the responses it lists. */
.set API_FLAG_SSZ_RESPONSE, 1        /* 406: Accept chooses JSON or SSZ */
.set API_FLAG_SSZ_BODY, 2            /* 415: Content-Type chooses JSON or SSZ */
.set API_FLAG_VERSION, 4             /* Eth-Consensus-Version is required */
.set API_FLAG_ID_MAX, 8              /* 414: at most 64 ids */
.set API_FLAG_IDS_OBJECT, 16         /* the body: {"ids":[…],"statuses":[…]} */
.set API_FLAG_IDS_ARRAY, 32          /* the body: an array of ids */

/* Kinds of parameter (api_params). */
.set API_KIND_NUMBER, 1
.set API_KIND_STATE_ID, 2
.set API_KIND_BLOCK_ID, 3
.set API_KIND_BLOCK_ROOT, 4
.set API_KIND_VALIDATOR, 5
.set API_KIND_PEER_ID, 6
.set API_KIND_SYNCING, 7
.set API_KIND_ROOT, 8
.set API_KIND_RANDAO, 9
.set API_KIND_GRAFFITI, 10
.set API_KIND_FLAG, 11
.set API_KIND_WORD, 12
.set API_KIND_SET, 13
.set API_KIND_ID_LIST, 14
.set API_KIND_INDEX_LIST, 15
.set API_KIND_HASH_LIST, 16
.set API_KIND_HEADER, 17

/*
 * API_ROUTE_DATA, in RODATA:
 * api_routes: API_OPS entries of 32 bytes: the template's offset from api_route_text; its length
 * + method << 16 + flags << 24; the query parameters it takes, bit API_PARAM_*; those required.
 * A template is the path with each {name} one byte, its API_PARAM_*.
 * api_params: API_PARAMS + 1 entries of 32 bytes, entry n for API_PARAM n (entry 0 empty): the
 * name's offset from api_param_text; its length;
 * API_KIND_*; the ApiRoute field it sets.
 * api_words: API_WORDS entries of 32 bytes: API_PARAM_*; the word's offset from api_word_text; its
 * length; its value (a kind, a set's bits, a FORK_*).
 */
.macro API_ROUTE_DATA
    RODATA
    .p2align 3
api_routes:
    .quad   api_t_0 - api_route_text, 22 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getGenesis */
    .quad   api_t_1 - api_route_text, 28 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getStateRoot */
    .quad   api_t_2 - api_route_text, 28 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getStateFork */
    .quad   api_t_3 - api_route_text, 44 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getStateFinalityCheckpoints */
    .quad   api_t_4 - api_route_text, 34 + (1 << 16) + (8 << 24), 0x300, 0x0   /* getStateValidators */
    .quad   api_t_4 - api_route_text, 34 + (2 << 16) + (16 << 24), 0x0, 0x0   /* postStateValidators */
    .quad   api_t_5 - api_route_text, 36 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getStateValidator */
    .quad   api_t_6 - api_route_text, 42 + (1 << 16) + (8 << 24), 0x100, 0x0   /* getStateValidatorBalances */
    .quad   api_t_6 - api_route_text, 42 + (2 << 16) + (32 << 24), 0x0, 0x0   /* postStateValidatorBalances */
    .quad   api_t_7 - api_route_text, 44 + (2 << 16) + (33 << 24), 0x0, 0x0   /* postStateValidatorIdentities */
    .quad   api_t_8 - api_route_text, 34 + (1 << 16) + (0 << 24), 0x4c0, 0x0   /* getEpochCommittees */
    .quad   api_t_9 - api_route_text, 39 + (1 << 16) + (0 << 24), 0x40, 0x0   /* getEpochSyncCommittees */
    .quad   api_t_10 - api_route_text, 30 + (1 << 16) + (0 << 24), 0x40, 0x0   /* getStateRandao */
    .quad   api_t_11 - api_route_text, 46 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getPendingConsolidations */
    .quad   api_t_12 - api_route_text, 40 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getPendingDeposits */
    .quad   api_t_13 - api_route_text, 51 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getPendingPartialWithdrawals */
    .quad   api_t_14 - api_route_text, 42 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getProposerLookahead */
    .quad   api_t_15 - api_route_text, 22 + (1 << 16) + (0 << 24), 0x2080, 0x0   /* getBlockHeaders */
    .quad   api_t_16 - api_route_text, 24 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getBlockHeader */
    .quad   api_t_17 - api_route_text, 29 + (2 << 16) + (6 << 24), 0x10000, 0x0   /* publishBlindedBlockV2 */
    .quad   api_t_18 - api_route_text, 21 + (2 << 16) + (6 << 24), 0x10000, 0x0   /* publishBlockV2 */
    .quad   api_t_19 - api_route_text, 23 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getBlockV2 */
    .quad   api_t_20 - api_route_text, 28 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getBlockRoot */
    .quad   api_t_21 - api_route_text, 36 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getBlockAttestationsV2 */
    .quad   api_t_22 - api_route_text, 30 + (1 << 16) + (1 << 24), 0x4000, 0x0   /* getBlobSidecars */
    .quad   api_t_23 - api_route_text, 22 + (1 << 16) + (1 << 24), 0x8000, 0x0   /* getBlobs */
    .quad   api_t_24 - api_route_text, 43 + (1 << 16) + (1 << 24), 0x4000, 0x0   /* getDebugDataColumnSidecars */
    .quad   api_t_25 - api_route_text, 39 + (2 << 16) + (32 << 24), 0x0, 0x0   /* getSyncCommitteeRewards */
    .quad   api_t_26 - api_route_text, 31 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getBlockRewards */
    .quad   api_t_27 - api_route_text, 37 + (2 << 16) + (32 << 24), 0x0, 0x0   /* getAttestationsRewards */
    .quad   api_t_28 - api_route_text, 31 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getBlindedBlock */
    .quad   api_t_29 - api_route_text, 39 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getLightClientBootstrap */
    .quad   api_t_30 - api_route_text, 35 + (1 << 16) + (1 << 24), 0x60000, 0x60000   /* getLightClientUpdatesByRange */
    .quad   api_t_31 - api_route_text, 43 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getLightClientFinalityUpdate */
    .quad   api_t_32 - api_route_text, 45 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getLightClientOptimisticUpdate */
    .quad   api_t_33 - api_route_text, 32 + (1 << 16) + (0 << 24), 0x880, 0x0   /* getPoolAttestationsV2 */
    .quad   api_t_33 - api_route_text, 32 + (2 << 16) + (6 << 24), 0x0, 0x0   /* submitPoolAttestationsV2 */
    .quad   api_t_34 - api_route_text, 38 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getPoolAttesterSlashingsV2 */
    .quad   api_t_34 - api_route_text, 38 + (2 << 16) + (4 << 24), 0x0, 0x0   /* submitPoolAttesterSlashingsV2 */
    .quad   api_t_35 - api_route_text, 38 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getPoolProposerSlashings */
    .quad   api_t_35 - api_route_text, 38 + (2 << 16) + (0 << 24), 0x0, 0x0   /* submitPoolProposerSlashings */
    .quad   api_t_36 - api_route_text, 35 + (2 << 16) + (0 << 24), 0x0, 0x0   /* submitPoolSyncCommitteeSignatures */
    .quad   api_t_37 - api_route_text, 35 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getPoolVoluntaryExits */
    .quad   api_t_37 - api_route_text, 35 + (2 << 16) + (0 << 24), 0x0, 0x0   /* submitPoolVoluntaryExit */
    .quad   api_t_38 - api_route_text, 44 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getPoolBLSToExecutionChanges */
    .quad   api_t_38 - api_route_text, 44 + (2 << 16) + (0 << 24), 0x0, 0x0   /* submitPoolBLSToExecutionChange */
    .quad   api_t_39 - api_route_text, 29 + (1 << 16) + (1 << 24), 0x0, 0x0   /* getStateV2 */
    .quad   api_t_40 - api_route_text, 26 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getDebugChainHeadsV2 */
    .quad   api_t_41 - api_route_text, 25 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getDebugForkChoice */
    .quad   api_t_42 - api_route_text, 21 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getNetworkIdentity */
    .quad   api_t_43 - api_route_text, 18 + (1 << 16) + (0 << 24), 0x180000, 0x0   /* getPeers */
    .quad   api_t_44 - api_route_text, 20 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getPeer */
    .quad   api_t_45 - api_route_text, 23 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getPeerCount */
    .quad   api_t_46 - api_route_text, 20 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getNodeVersion */
    .quad   api_t_47 - api_route_text, 20 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getSyncingStatus */
    .quad   api_t_48 - api_route_text, 19 + (1 << 16) + (0 << 24), 0x200000, 0x0   /* getHealth */
    .quad   api_t_49 - api_route_text, 28 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getForkSchedule */
    .quad   api_t_50 - api_route_text, 19 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getSpec */
    .quad   api_t_51 - api_route_text, 31 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getDepositContract */
    .quad   api_t_52 - api_route_text, 35 + (2 << 16) + (32 << 24), 0x0, 0x0   /* getAttesterDuties */
    .quad   api_t_53 - api_route_text, 35 + (1 << 16) + (0 << 24), 0x0, 0x0   /* getProposerDuties */
    .quad   api_t_54 - api_route_text, 31 + (2 << 16) + (32 << 24), 0x0, 0x0   /* getSyncCommitteeDuties */
    .quad   api_t_55 - api_route_text, 26 + (1 << 16) + (1 << 24), 0x3c00000, 0x400000   /* produceBlockV3 */
    .quad   api_t_56 - api_route_text, 34 + (1 << 16) + (1 << 24), 0x880, 0x880   /* produceAttestationData */
    .quad   api_t_57 - api_route_text, 39 + (1 << 16) + (1 << 24), 0x4000880, 0x4000880   /* getAggregatedAttestationV2 */
    .quad   api_t_58 - api_route_text, 38 + (2 << 16) + (6 << 24), 0x0, 0x0   /* publishAggregateAndProofsV2 */
    .quad   api_t_59 - api_route_text, 48 + (2 << 16) + (0 << 24), 0x0, 0x0   /* prepareBeaconCommitteeSubnet */
    .quad   api_t_60 - api_route_text, 46 + (2 << 16) + (0 << 24), 0x0, 0x0   /* prepareSyncCommitteeSubnets */
    .quad   api_t_61 - api_route_text, 45 + (2 << 16) + (0 << 24), 0x0, 0x0   /* submitBeaconCommitteeSelections */
    .quad   api_t_62 - api_route_text, 45 + (1 << 16) + (0 << 24), 0x8001080, 0x8001080   /* produceSyncCommitteeContribution */
    .quad   api_t_63 - api_route_text, 43 + (2 << 16) + (0 << 24), 0x0, 0x0   /* submitSyncCommitteeSelections */
    .quad   api_t_64 - api_route_text, 41 + (2 << 16) + (0 << 24), 0x0, 0x0   /* publishContributionAndProofs */
    .quad   api_t_65 - api_route_text, 41 + (2 << 16) + (0 << 24), 0x0, 0x0   /* prepareBeaconProposer */
    .quad   api_t_66 - api_route_text, 36 + (2 << 16) + (2 << 24), 0x0, 0x0   /* registerValidator */
    .quad   api_t_67 - api_route_text, 28 + (2 << 16) + (32 << 24), 0x0, 0x0   /* getLiveness */
    .quad   api_t_68 - api_route_text, 14 + (1 << 16) + (0 << 24), 0x10000000, 0x10000000   /* eventstream */
api_params:
    .quad   0, 0, 0, 0                         /* entry 0: no parameter */
    .quad   api_p_1 - api_param_text, 8, API_KIND_STATE_ID, ApiRoute_id_kind
    .quad   api_p_2 - api_param_text, 8, API_KIND_BLOCK_ID, ApiRoute_id_kind
    .quad   api_p_3 - api_param_text, 10, API_KIND_BLOCK_ROOT, ApiRoute_id_kind
    .quad   api_p_4 - api_param_text, 12, API_KIND_VALIDATOR, ApiRoute_validator
    .quad   api_p_5 - api_param_text, 7, API_KIND_PEER_ID, ApiRoute_peer_id
    .quad   api_p_6 - api_param_text, 5, API_KIND_NUMBER, ApiRoute_epoch
    .quad   api_p_7 - api_param_text, 4, API_KIND_NUMBER, ApiRoute_slot
    .quad   api_p_8 - api_param_text, 2, API_KIND_ID_LIST, ApiRoute_list
    .quad   api_p_9 - api_param_text, 6, API_KIND_SET, ApiRoute_statuses
    .quad   api_p_10 - api_param_text, 5, API_KIND_NUMBER, ApiRoute_index
    .quad   api_p_11 - api_param_text, 15, API_KIND_NUMBER, ApiRoute_committee_index
    .quad   api_p_12 - api_param_text, 18, API_KIND_NUMBER, ApiRoute_subcommittee_index
    .quad   api_p_13 - api_param_text, 11, API_KIND_ROOT, ApiRoute_root
    .quad   api_p_14 - api_param_text, 7, API_KIND_INDEX_LIST, ApiRoute_list
    .quad   api_p_15 - api_param_text, 16, API_KIND_HASH_LIST, ApiRoute_list
    .quad   api_p_16 - api_param_text, 20, API_KIND_WORD, ApiRoute_broadcast_validation
    .quad   api_p_17 - api_param_text, 12, API_KIND_NUMBER, ApiRoute_start_period
    .quad   api_p_18 - api_param_text, 5, API_KIND_NUMBER, ApiRoute_count
    .quad   api_p_19 - api_param_text, 5, API_KIND_SET, ApiRoute_peer_states
    .quad   api_p_20 - api_param_text, 9, API_KIND_SET, ApiRoute_peer_directions
    .quad   api_p_21 - api_param_text, 14, API_KIND_SYNCING, ApiRoute_syncing_status
    .quad   api_p_22 - api_param_text, 13, API_KIND_RANDAO, ApiRoute_randao_reveal
    .quad   api_p_23 - api_param_text, 8, API_KIND_GRAFFITI, ApiRoute_graffiti
    .quad   api_p_24 - api_param_text, 24, API_KIND_FLAG, 0
    .quad   api_p_25 - api_param_text, 20, API_KIND_NUMBER, ApiRoute_builder_boost_factor
    .quad   api_p_26 - api_param_text, 21, API_KIND_ROOT, ApiRoute_root
    .quad   api_p_27 - api_param_text, 17, API_KIND_ROOT, ApiRoute_root
    .quad   api_p_28 - api_param_text, 6, API_KIND_SET, ApiRoute_topics
    .quad   api_p_29 - api_param_text, 21, API_KIND_HEADER, ApiRoute_consensus_version
api_words:
    .quad   API_PARAM_STATE_ID, api_w_0 - api_word_text, 4, 0x1
    .quad   API_PARAM_STATE_ID, api_w_1 - api_word_text, 7, 0x2
    .quad   API_PARAM_STATE_ID, api_w_2 - api_word_text, 9, 0x3
    .quad   API_PARAM_STATE_ID, api_w_3 - api_word_text, 9, 0x4
    .quad   API_PARAM_BLOCK_ID, api_w_4 - api_word_text, 4, 0x1
    .quad   API_PARAM_BLOCK_ID, api_w_5 - api_word_text, 7, 0x2
    .quad   API_PARAM_BLOCK_ID, api_w_6 - api_word_text, 9, 0x3
    .quad   API_PARAM_BROADCAST_VALIDATION, api_w_7 - api_word_text, 6, 0x1
    .quad   API_PARAM_BROADCAST_VALIDATION, api_w_8 - api_word_text, 9, 0x2
    .quad   API_PARAM_BROADCAST_VALIDATION, api_w_9 - api_word_text, 26, 0x3
    .quad   API_PARAM_STATUS, api_w_10 - api_word_text, 19, 0x1
    .quad   API_PARAM_STATUS, api_w_11 - api_word_text, 14, 0x2
    .quad   API_PARAM_STATUS, api_w_12 - api_word_text, 14, 0x4
    .quad   API_PARAM_STATUS, api_w_13 - api_word_text, 14, 0x8
    .quad   API_PARAM_STATUS, api_w_14 - api_word_text, 14, 0x10
    .quad   API_PARAM_STATUS, api_w_15 - api_word_text, 16, 0x20
    .quad   API_PARAM_STATUS, api_w_16 - api_word_text, 14, 0x40
    .quad   API_PARAM_STATUS, api_w_17 - api_word_text, 19, 0x80
    .quad   API_PARAM_STATUS, api_w_18 - api_word_text, 15, 0x100
    .quad   API_PARAM_STATUS, api_w_19 - api_word_text, 7, 0x3
    .quad   API_PARAM_STATUS, api_w_20 - api_word_text, 6, 0x1c
    .quad   API_PARAM_STATUS, api_w_21 - api_word_text, 6, 0x60
    .quad   API_PARAM_STATUS, api_w_22 - api_word_text, 10, 0x180
    .quad   API_PARAM_STATE, api_w_23 - api_word_text, 12, 0x1
    .quad   API_PARAM_STATE, api_w_24 - api_word_text, 10, 0x2
    .quad   API_PARAM_STATE, api_w_25 - api_word_text, 9, 0x4
    .quad   API_PARAM_STATE, api_w_26 - api_word_text, 13, 0x8
    .quad   API_PARAM_DIRECTION, api_w_27 - api_word_text, 7, 0x1
    .quad   API_PARAM_DIRECTION, api_w_28 - api_word_text, 8, 0x2
    .quad   API_PARAM_TOPICS, api_w_29 - api_word_text, 4, 0x1
    .quad   API_PARAM_TOPICS, api_w_30 - api_word_text, 5, 0x2
    .quad   API_PARAM_TOPICS, api_w_31 - api_word_text, 12, 0x4
    .quad   API_PARAM_TOPICS, api_w_32 - api_word_text, 11, 0x8
    .quad   API_PARAM_TOPICS, api_w_33 - api_word_text, 18, 0x10
    .quad   API_PARAM_TOPICS, api_w_34 - api_word_text, 14, 0x20
    .quad   API_PARAM_TOPICS, api_w_35 - api_word_text, 23, 0x40
    .quad   API_PARAM_TOPICS, api_w_36 - api_word_text, 17, 0x80
    .quad   API_PARAM_TOPICS, api_w_37 - api_word_text, 17, 0x100
    .quad   API_PARAM_TOPICS, api_w_38 - api_word_text, 20, 0x200
    .quad   API_PARAM_TOPICS, api_w_39 - api_word_text, 11, 0x400
    .quad   API_PARAM_TOPICS, api_w_40 - api_word_text, 22, 0x800
    .quad   API_PARAM_TOPICS, api_w_41 - api_word_text, 28, 0x1000
    .quad   API_PARAM_TOPICS, api_w_42 - api_word_text, 30, 0x2000
    .quad   API_PARAM_TOPICS, api_w_43 - api_word_text, 18, 0x4000
    .quad   API_PARAM_TOPICS, api_w_44 - api_word_text, 12, 0x8000
    .quad   API_PARAM_TOPICS, api_w_45 - api_word_text, 19, 0x10000
    .quad   API_PARAM_CONSENSUS_VERSION, api_w_46 - api_word_text, 6, 0x0
    .quad   API_PARAM_CONSENSUS_VERSION, api_w_47 - api_word_text, 6, 0x1
    .quad   API_PARAM_CONSENSUS_VERSION, api_w_48 - api_word_text, 9, 0x2
    .quad   API_PARAM_CONSENSUS_VERSION, api_w_49 - api_word_text, 7, 0x3
    .quad   API_PARAM_CONSENSUS_VERSION, api_w_50 - api_word_text, 5, 0x4
    .quad   API_PARAM_CONSENSUS_VERSION, api_w_51 - api_word_text, 7, 0x5
    .quad   API_PARAM_CONSENSUS_VERSION, api_w_52 - api_word_text, 4, 0x6
api_route_text:
api_t_0:
    .ascii  "/eth/v1/beacon/genesis"
api_t_1:
    .ascii  "/eth/v1/beacon/states/\001/root"
api_t_2:
    .ascii  "/eth/v1/beacon/states/\001/fork"
api_t_3:
    .ascii  "/eth/v1/beacon/states/\001/finality_checkpoints"
api_t_4:
    .ascii  "/eth/v1/beacon/states/\001/validators"
api_t_5:
    .ascii  "/eth/v1/beacon/states/\001/validators/\004"
api_t_6:
    .ascii  "/eth/v1/beacon/states/\001/validator_balances"
api_t_7:
    .ascii  "/eth/v1/beacon/states/\001/validator_identities"
api_t_8:
    .ascii  "/eth/v1/beacon/states/\001/committees"
api_t_9:
    .ascii  "/eth/v1/beacon/states/\001/sync_committees"
api_t_10:
    .ascii  "/eth/v1/beacon/states/\001/randao"
api_t_11:
    .ascii  "/eth/v1/beacon/states/\001/pending_consolidations"
api_t_12:
    .ascii  "/eth/v1/beacon/states/\001/pending_deposits"
api_t_13:
    .ascii  "/eth/v1/beacon/states/\001/pending_partial_withdrawals"
api_t_14:
    .ascii  "/eth/v1/beacon/states/\001/proposer_lookahead"
api_t_15:
    .ascii  "/eth/v1/beacon/headers"
api_t_16:
    .ascii  "/eth/v1/beacon/headers/\002"
api_t_17:
    .ascii  "/eth/v2/beacon/blinded_blocks"
api_t_18:
    .ascii  "/eth/v2/beacon/blocks"
api_t_19:
    .ascii  "/eth/v2/beacon/blocks/\002"
api_t_20:
    .ascii  "/eth/v1/beacon/blocks/\002/root"
api_t_21:
    .ascii  "/eth/v2/beacon/blocks/\002/attestations"
api_t_22:
    .ascii  "/eth/v1/beacon/blob_sidecars/\002"
api_t_23:
    .ascii  "/eth/v1/beacon/blobs/\002"
api_t_24:
    .ascii  "/eth/v1/debug/beacon/data_column_sidecars/\002"
api_t_25:
    .ascii  "/eth/v1/beacon/rewards/sync_committee/\002"
api_t_26:
    .ascii  "/eth/v1/beacon/rewards/blocks/\002"
api_t_27:
    .ascii  "/eth/v1/beacon/rewards/attestations/\006"
api_t_28:
    .ascii  "/eth/v1/beacon/blinded_blocks/\002"
api_t_29:
    .ascii  "/eth/v1/beacon/light_client/bootstrap/\003"
api_t_30:
    .ascii  "/eth/v1/beacon/light_client/updates"
api_t_31:
    .ascii  "/eth/v1/beacon/light_client/finality_update"
api_t_32:
    .ascii  "/eth/v1/beacon/light_client/optimistic_update"
api_t_33:
    .ascii  "/eth/v2/beacon/pool/attestations"
api_t_34:
    .ascii  "/eth/v2/beacon/pool/attester_slashings"
api_t_35:
    .ascii  "/eth/v1/beacon/pool/proposer_slashings"
api_t_36:
    .ascii  "/eth/v1/beacon/pool/sync_committees"
api_t_37:
    .ascii  "/eth/v1/beacon/pool/voluntary_exits"
api_t_38:
    .ascii  "/eth/v1/beacon/pool/bls_to_execution_changes"
api_t_39:
    .ascii  "/eth/v2/debug/beacon/states/\001"
api_t_40:
    .ascii  "/eth/v2/debug/beacon/heads"
api_t_41:
    .ascii  "/eth/v1/debug/fork_choice"
api_t_42:
    .ascii  "/eth/v1/node/identity"
api_t_43:
    .ascii  "/eth/v1/node/peers"
api_t_44:
    .ascii  "/eth/v1/node/peers/\005"
api_t_45:
    .ascii  "/eth/v1/node/peer_count"
api_t_46:
    .ascii  "/eth/v1/node/version"
api_t_47:
    .ascii  "/eth/v1/node/syncing"
api_t_48:
    .ascii  "/eth/v1/node/health"
api_t_49:
    .ascii  "/eth/v1/config/fork_schedule"
api_t_50:
    .ascii  "/eth/v1/config/spec"
api_t_51:
    .ascii  "/eth/v1/config/deposit_contract"
api_t_52:
    .ascii  "/eth/v1/validator/duties/attester/\006"
api_t_53:
    .ascii  "/eth/v1/validator/duties/proposer/\006"
api_t_54:
    .ascii  "/eth/v1/validator/duties/sync/\006"
api_t_55:
    .ascii  "/eth/v3/validator/blocks/\007"
api_t_56:
    .ascii  "/eth/v1/validator/attestation_data"
api_t_57:
    .ascii  "/eth/v2/validator/aggregate_attestation"
api_t_58:
    .ascii  "/eth/v2/validator/aggregate_and_proofs"
api_t_59:
    .ascii  "/eth/v1/validator/beacon_committee_subscriptions"
api_t_60:
    .ascii  "/eth/v1/validator/sync_committee_subscriptions"
api_t_61:
    .ascii  "/eth/v1/validator/beacon_committee_selections"
api_t_62:
    .ascii  "/eth/v1/validator/sync_committee_contribution"
api_t_63:
    .ascii  "/eth/v1/validator/sync_committee_selections"
api_t_64:
    .ascii  "/eth/v1/validator/contribution_and_proofs"
api_t_65:
    .ascii  "/eth/v1/validator/prepare_beacon_proposer"
api_t_66:
    .ascii  "/eth/v1/validator/register_validator"
api_t_67:
    .ascii  "/eth/v1/validator/liveness/\006"
api_t_68:
    .ascii  "/eth/v1/events"
api_param_text:
api_p_1:
    .ascii  "state_id"
api_p_2:
    .ascii  "block_id"
api_p_3:
    .ascii  "block_root"
api_p_4:
    .ascii  "validator_id"
api_p_5:
    .ascii  "peer_id"
api_p_6:
    .ascii  "epoch"
api_p_7:
    .ascii  "slot"
api_p_8:
    .ascii  "id"
api_p_9:
    .ascii  "status"
api_p_10:
    .ascii  "index"
api_p_11:
    .ascii  "committee_index"
api_p_12:
    .ascii  "subcommittee_index"
api_p_13:
    .ascii  "parent_root"
api_p_14:
    .ascii  "indices"
api_p_15:
    .ascii  "versioned_hashes"
api_p_16:
    .ascii  "broadcast_validation"
api_p_17:
    .ascii  "start_period"
api_p_18:
    .ascii  "count"
api_p_19:
    .ascii  "state"
api_p_20:
    .ascii  "direction"
api_p_21:
    .ascii  "syncing_status"
api_p_22:
    .ascii  "randao_reveal"
api_p_23:
    .ascii  "graffiti"
api_p_24:
    .ascii  "skip_randao_verification"
api_p_25:
    .ascii  "builder_boost_factor"
api_p_26:
    .ascii  "attestation_data_root"
api_p_27:
    .ascii  "beacon_block_root"
api_p_28:
    .ascii  "topics"
api_p_29:
    .ascii  "eth-consensus-version"
api_word_text:
api_w_0:
    .ascii  "head"
api_w_1:
    .ascii  "genesis"
api_w_2:
    .ascii  "finalized"
api_w_3:
    .ascii  "justified"
api_w_4:
    .ascii  "head"
api_w_5:
    .ascii  "genesis"
api_w_6:
    .ascii  "finalized"
api_w_7:
    .ascii  "gossip"
api_w_8:
    .ascii  "consensus"
api_w_9:
    .ascii  "consensus_and_equivocation"
api_w_10:
    .ascii  "pending_initialized"
api_w_11:
    .ascii  "pending_queued"
api_w_12:
    .ascii  "active_ongoing"
api_w_13:
    .ascii  "active_exiting"
api_w_14:
    .ascii  "active_slashed"
api_w_15:
    .ascii  "exited_unslashed"
api_w_16:
    .ascii  "exited_slashed"
api_w_17:
    .ascii  "withdrawal_possible"
api_w_18:
    .ascii  "withdrawal_done"
api_w_19:
    .ascii  "pending"
api_w_20:
    .ascii  "active"
api_w_21:
    .ascii  "exited"
api_w_22:
    .ascii  "withdrawal"
api_w_23:
    .ascii  "disconnected"
api_w_24:
    .ascii  "connecting"
api_w_25:
    .ascii  "connected"
api_w_26:
    .ascii  "disconnecting"
api_w_27:
    .ascii  "inbound"
api_w_28:
    .ascii  "outbound"
api_w_29:
    .ascii  "head"
api_w_30:
    .ascii  "block"
api_w_31:
    .ascii  "block_gossip"
api_w_32:
    .ascii  "attestation"
api_w_33:
    .ascii  "single_attestation"
api_w_34:
    .ascii  "voluntary_exit"
api_w_35:
    .ascii  "bls_to_execution_change"
api_w_36:
    .ascii  "proposer_slashing"
api_w_37:
    .ascii  "attester_slashing"
api_w_38:
    .ascii  "finalized_checkpoint"
api_w_39:
    .ascii  "chain_reorg"
api_w_40:
    .ascii  "contribution_and_proof"
api_w_41:
    .ascii  "light_client_finality_update"
api_w_42:
    .ascii  "light_client_optimistic_update"
api_w_43:
    .ascii  "payload_attributes"
api_w_44:
    .ascii  "blob_sidecar"
api_w_45:
    .ascii  "data_column_sidecar"
api_w_46:
    .ascii  "phase0"
api_w_47:
    .ascii  "altair"
api_w_48:
    .ascii  "bellatrix"
api_w_49:
    .ascii  "capella"
api_w_50:
    .ascii  "deneb"
api_w_51:
    .ascii  "electra"
api_w_52:
    .ascii  "fulu"
    .p2align 3
.endm
.set API_WORDS, 53
