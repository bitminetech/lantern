/*
 * lantern vector runner. Test code: lantern itself is assembly.
 *
 * Usage: runner-<preset>-<fork> VECTOR_DIR FILE ...
 *
 * Reads the case files that tests/generator/ writes (format in its README),
 * calls the lantern functions of one fork for every case and compares the
 * results. Files of another preset or fork are skipped; a file of a kind the
 * runner has no handler for prints a SKIP line. It exits with status 0 only
 * when every case of every file it runs passes.
 *
 * Buffers are allocated at the size each function asks for, with guard bytes
 * after them, and output buffers start filled with 0xA5, so a write out of
 * bounds or a read of old output contents shows up as a failure.
 *
 * Every lantern call goes through abi_call (tests/runner/abi_<ISA>.s), which
 * checks the registers the ABI says the callee keeps, and measures the stack.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) && defined(__x86_64__)
#define ABI __attribute__((sysv_abi))
#else
#define ABI
#endif

#ifndef PRESET
#error "build with -DPRESET=\"mainnet\" or -DPRESET=\"minimal\""
#endif

/* The forks of include/forks.inc. */
#define FORK_PHASE0 0
#define FORK_ALTAIR 1
#define FORK_BELLATRIX 2
#define FORK_CAPELLA 3
#define FORK_DENEB 4
#define FORK_ELECTRA 5
#define FORK_FULU 6
#if !defined(FORK) || !defined(FORK_NAME)
#error "build with -DFORK=<FORK_* number> -DFORK_NAME=<fork>, for example -DFORK=6 -DFORK_NAME=fulu"
#endif

#define STR_(x) #x
#define STR(x) STR_(x)
#define CAT_(a, b, c) a##b##c
#define CAT(a, b, c) CAT_(a, b, c)
/* LF(name): lantern_<fork>_<name>, the export of the fork that this runner tests. */
#define LF(name) CAT(lantern_, FORK_NAME, _##name)

/* ---------------------------------------------------------------- Interfaces */

/* asm-ssz, at the pin in platform/deps.sh. */
ABI uint64_t ssz_serialize(const void *type, const void *value, void *scratch, void *serialized);
ABI uint64_t ssz_serialize_size(const void *type, const void *value, void *scratch, void *size);
ABI uint64_t ssz_deserialize(const void *type, const void *serialized, void *scratch, void *value);
ABI uint64_t ssz_deserialize_size(const void *type, const void *serialized, void *scratch, void *size);
ABI uint64_t ssz_hash_tree_root(const void *type, const void *value, void *scratch, void *root);

/* lantern: include/descriptors.inc. */
extern const uint8_t LF(types)[];

#if FORK > FORK_PHASE0
/* The fork before, for the fork and transition files: docs/reference/fork-upgrades.md. */
#if FORK == FORK_ALTAIR
#define PREV_FORK_NAME phase0
#elif FORK == FORK_BELLATRIX
#define PREV_FORK_NAME altair
#elif FORK == FORK_CAPELLA
#define PREV_FORK_NAME bellatrix
#elif FORK == FORK_DENEB
#define PREV_FORK_NAME capella
#elif FORK == FORK_ELECTRA
#define PREV_FORK_NAME deneb
#else
#define PREV_FORK_NAME electra
#endif
/* LP(name): lantern_<fork before>_<name>. UPGRADE: lantern_<fork>_upgrade_to_<fork>. */
#define LP(name) CAT(lantern_, PREV_FORK_NAME, _##name)
#define UPGRADE CAT(CAT(lantern_, FORK_NAME, _upgrade_to_), FORK_NAME, )
extern const uint8_t LP(types)[];
ABI uint64_t LP(beacon_state_copy_size)(const void *state, const void *room, void *size);
ABI uint64_t LP(beacon_state_copy)(const void *state, const void *room, void *out);
ABI uint64_t LP(process_slots)(void *state, const void *slot, const void *config, void *scratch, void *result);
ABI uint64_t LP(state_transition)(void *state, const void *signed_block, const void *options, const void *config,
                                      void *scratch, void *result);
ABI uint64_t LF(upgrade_size)(const void *pre, const void *room, void *size);
ABI uint64_t LF(verify_block_signature)(const void *state, const void *signed_block, void *scratch, void *out);
ABI uint64_t LF(process_block)(void *state, const void *block, const void *execution_valid, const void *config,
                                   void *scratch, void *result);
ABI uint64_t UPGRADE(const void *pre, const void *room, const void *config, void *scratch, void *out);
/* The node's start at a state of the fork before: docs/reference/node.md, Test vectors. */
ABI uint64_t LP(node_anchor)(const void *data, const void *room, void *scratch, void *state, void *block);
ABI uint64_t LP(node_state_bytes)(const void *state, void *scratch, void *out, void *size);
ABI uint64_t LP(get_forkchoice_store)(const void *anchor_state, const void *anchor_block, const void *config,
                                          const void *room, void *scratch, void *store);
#endif
#if FORK == FORK_PHASE0
/* Genesis: docs/reference/genesis.md. */
ABI uint64_t LF(initialize_beacon_state_from_eth1_size)(const void *deposit_count, const void *room, void *size);
ABI uint64_t LF(initialize_beacon_state_from_eth1)(const void *eth1_block_hash, const void *eth1_timestamp,
                                                       const void *deposits, const void *deposit_count,
                                                       const void *room, const void *config, void *scratch, void *out);
ABI uint64_t LF(is_valid_genesis_state)(const void *state, const void *config, void *out);
#endif

/* The state transition of every fork: docs/reference/. */
ABI uint64_t LF(beacon_state_copy_size)(const void *state, const void *room, void *size);
ABI uint64_t LF(node_anchor)(const void *data, const void *room, void *scratch, void *state, void *block);
ABI uint64_t LF(node_anchor_block)(const void *data, const void *room, void *scratch, void *state, void *block);
ABI uint64_t LF(node_state_bytes)(const void *state, void *scratch, void *out, void *size);
ABI uint64_t LF(node_block_header)(const void *data, void *scratch, void *out);
ABI uint64_t LF(node_state_checkpoints)(const void *state, void *out);
ABI uint64_t LF(beacon_state_copy)(const void *state, const void *room, void *out);
ABI uint64_t LF(state_cache_size)(const void *validators, void *size);
ABI uint64_t LF(state_cache_init)(const void *validators, void *cache);
ABI uint64_t LF(state_root)(const void *state, void *cache, void *scratch, void *out);
ABI uint64_t LF(state_branch)(const void *state, uint64_t field, void *cache, void *scratch, void *out);
ABI uint64_t LF(execution_branch)(const void *body, void *scratch, void *out);
ABI uint64_t LF(is_better_update)(const void *new_update, const void *old_update, void *out);
ABI uint64_t LF(block_to_light_client_header)(const void *block, void *scratch, void *out);
ABI uint64_t LF(upgrade_lc_header)(const void *header, uint64_t from, void *out);
ABI uint64_t LF(committee_cache_size)(const void *validators, void *size);
ABI uint64_t LF(committee_cache_init)(const void *validators, void *cache);
ABI uint64_t LF(pubkey_cache_size)(const void *validators, void *size);
ABI uint64_t LF(pubkey_cache_init)(const void *validators, void *cache);

ABI uint64_t LF(compute_shuffled_permutation)(const void *index_count, const void *seed, void *scratch, void *out);
ABI uint64_t LF(compute_shuffled_index)(const void *index, const void *index_count, const void *seed, void *scratch,
                                            void *out);
#if FORK >= FORK_ALTAIR
ABI uint64_t LF(get_flag_index_deltas)(const void *state, const void *flag_index, void *scratch, void *rewards,
                                           void *penalties);
#else
/* A phase0 component of the attestation deltas: (state, scratch, rewards, penalties). */
typedef ABI uint64_t (*deltas_fn)(const void *state, void *scratch, void *rewards, void *penalties);
ABI uint64_t LF(get_source_deltas)(const void *state, void *scratch, void *rewards, void *penalties);
ABI uint64_t LF(get_target_deltas)(const void *state, void *scratch, void *rewards, void *penalties);
ABI uint64_t LF(get_head_deltas)(const void *state, void *scratch, void *rewards, void *penalties);
ABI uint64_t LF(get_inclusion_delay_deltas)(const void *state, void *scratch, void *rewards, void *penalties);
#endif
ABI uint64_t LF(get_inactivity_penalty_deltas)(const void *state, const void *config, void *scratch, void *rewards,
                                                   void *penalties);

/* An operation: (state, operation, config, scratch, result). The operations of this runner's fork. */
typedef ABI uint64_t (*op_fn)(void *state, const void *op, const void *config, void *scratch, void *result);
#if FORK >= FORK_BELLATRIX
ABI uint64_t LF(process_execution_payload)(void *state, const void *body, const void *execution_valid,
                                               const void *config, void *scratch, void *result);
#endif
#if FORK >= FORK_CAPELLA
#define OPS_CAPELLA(X)                                                                                         \
    X(withdrawals, withdrawals, execution_payload, ExecutionPayload)                                           \
    X(bls_to_execution_change, bls_to_execution_change, address_change, SignedBLSToExecutionChange)
#else
#define OPS_CAPELLA(X)
#endif
#if FORK >= FORK_ELECTRA
#define OPS_ELECTRA(X)                                                                                         \
    X(deposit_request, deposit_request, deposit_request, DepositRequest)                                       \
    X(withdrawal_request, withdrawal_request, withdrawal_request, WithdrawalRequest)                           \
    X(consolidation_request, consolidation_request, consolidation_request, ConsolidationRequest)
#else
#define OPS_ELECTRA(X)
#endif
#if FORK <= FORK_ELECTRA
#define OPS_DEPOSIT(X) X(deposit, deposit, deposit, Deposit)
#else
#define OPS_DEPOSIT(X)
#endif
#if FORK >= FORK_ALTAIR
#define OPS_ALTAIR(X) X(sync_aggregate, sync_aggregate, sync_aggregate, SyncAggregate)
#else
#define OPS_ALTAIR(X)
#endif
#define OP_FN(handler, fn, part, type) ABI uint64_t LF(process_##fn)(void *, const void *, const void *, void *, void *);
#define OPERATIONS(X)                                                                                          \
    X(block_header, block_header, block, BeaconBlock)                                                          \
    X(voluntary_exit, voluntary_exit, voluntary_exit, SignedVoluntaryExit)                                     \
    X(proposer_slashing, proposer_slashing, proposer_slashing, ProposerSlashing)                               \
    X(attester_slashing, attester_slashing, attester_slashing, AttesterSlashing)                               \
    X(attestation, attestation, attestation, Attestation)                                                      \
    OPS_ALTAIR(X) OPS_CAPELLA(X) OPS_DEPOSIT(X) OPS_ELECTRA(X)
OPERATIONS(OP_FN)

ABI uint64_t LF(process_slots)(void *state, const void *slot, const void *config, void *scratch, void *result);
ABI uint64_t LF(state_transition)(void *state, const void *signed_block, const void *options, const void *config,
                                      void *scratch, void *result);

/* An epoch processing function: (state, config, scratch, result). The steps of this runner's fork. */
typedef ABI uint64_t (*epoch_fn)(void *state, const void *config, void *scratch, void *result);
#define EPOCH_FN(name) ABI uint64_t LF(process_##name)(void *, const void *, void *, void *);
#if FORK >= FORK_ALTAIR
#define EPOCH_ALTAIR(X) X(inactivity_updates) X(participation_flag_updates) X(sync_committee_updates)
#else
#define EPOCH_ALTAIR(X) X(participation_record_updates)
#endif
#if FORK >= FORK_CAPELLA
#define EPOCH_HISTORY(X) X(historical_summaries_update)
#else
#define EPOCH_HISTORY(X) X(historical_roots_update)
#endif
#if FORK >= FORK_ELECTRA
#define EPOCH_ELECTRA(X) X(pending_deposits) X(pending_consolidations)
#else
#define EPOCH_ELECTRA(X)
#endif
#if FORK >= FORK_FULU
#define EPOCH_FULU(X) X(proposer_lookahead)
#else
#define EPOCH_FULU(X)
#endif
#define EPOCH_FUNCTIONS(X)                                                                                     \
    X(justification_and_finalization)                                                                          \
    X(rewards_and_penalties)                                                                                   \
    X(registry_updates)                                                                                        \
    X(slashings)                                                                                               \
    X(eth1_data_reset)                                                                                         \
    X(effective_balance_updates)                                                                               \
    X(slashings_reset)                                                                                         \
    X(randao_mixes_reset)                                                                                      \
    EPOCH_ALTAIR(X) EPOCH_HISTORY(X) EPOCH_ELECTRA(X) EPOCH_FULU(X)                                            \
    X(epoch)
EPOCH_FUNCTIONS(EPOCH_FN)

/* Fork choice: docs/reference/fork-choice.md. */
ABI uint64_t LF(get_forkchoice_store)(const void *anchor_state, const void *anchor_block, const void *config,
                                          const void *room, void *scratch, void *store);
ABI uint64_t lantern_store_size(const void *room, void *size);
ABI uint64_t lantern_store_copy(const void *store, const void *room, void *out);
ABI uint64_t LF(store_justified_checkpoint_state)(void *store, const void *state);
ABI uint64_t LF(get_current_slot)(const void *store, void *out);
ABI uint64_t LF(on_tick)(void *store, const void *time_ms, void *result);
ABI uint64_t LF(get_head)(const void *store, void *scratch, void *out);
ABI uint64_t LF(get_filtered_node_tree)(const void *store, void *scratch, void *out);
ABI uint64_t LF(get_weight)(const void *store, const void *node, void *out);
ABI uint64_t LF(node_weights)(const void *store, void *scratch, void *out);
ABI uint64_t LF(node_liveness)(const void *state, const void *config, const void *seen, const void *ids, uint64_t epoch,
                               void *scratch, void *out);
ABI uint64_t LF(node_block_rewards)(const void *pre, const void *block, const void *early, const void *late,
                                    const void *config, void *scratch, void *out);
ABI uint64_t LF(node_sync_rewards)(const void *pre, const void *block, void *scratch, void *out);
ABI uint64_t LF(node_reward_totals)(const void *state, const void *config, uint64_t mode, void *scratch, void *out);
ABI uint64_t LF(node_attestation_rewards)(const void *state, const void *config, const void *totals, uint64_t first,
                                          uint64_t count, void *scratch, void *out);
ABI uint64_t LF(node_ideal_reward)(const void *totals, uint64_t effective_balance, void *out);
ABI uint64_t LF(node_data_root)(const void *data, void *scratch, void *root);
ABI uint64_t LF(on_block)(void *store, const void *signed_block, void *state, const void *options, void *scratch,
                              void *result);
ABI uint64_t LF(validate_on_attestation)(const void *store, const void *attestation, const void *is_from_block);
ABI uint64_t LF(store_target_checkpoint_state)(void *state, const void *target, const void *config, void *scratch,
                                                   void *result);
ABI uint64_t LF(on_attestation)(void *store, const void *attestation, const void *is_from_block,
                                    const void *target_state, void *scratch, void *result);
ABI uint64_t LF(on_attester_slashing)(void *store, const void *attester_slashing, const void *state, void *scratch,
                                          void *result);
ABI uint64_t lantern_store_payload_status(void *store, const void *node, const void *payload_status, void *result);
ABI uint64_t LF(get_proposer_head)(const void *store, const void *head, const void *slot, const void *head_state,
                                       void *scratch, void *out);

/* The light client store: docs/reference/light-client.md. */
ABI uint64_t lantern_lc_store_size(const void *room, void *size);
ABI uint64_t lantern_lc_store_init(const void *room, const void *config, const void *state, const void *block, void *scratch,
                                   void *lc);
ABI uint64_t lantern_lc_store_copy(const void *lc, const void *room, void *out);
ABI uint64_t lantern_lc_on_block(void *lc, const void *config, const void *state, const void *block, void *cache,
                                 void *scratch);
ABI uint64_t lantern_lc_on_head(void *lc, const void *config, const void *head, const void *checkpoint, void *scratch);
ABI uint64_t lantern_lc_read(const void *lc, uint64_t kind, uint64_t key, void *out, void *fork);
#define LC_NO_ANSWER 66 /* LANTERN_NO_STATE_ANSWER */

/* The node core: docs/reference/node.md. */
ABI uint64_t lantern_node_size(const void *room, void *size);
ABI uint64_t lantern_node_init(const void *room, const void *config, const void *anchor, const void *flags, void *node);
ABI uint64_t lantern_node_copy(const void *node, const void *room, void *out);
ABI uint64_t lantern_node_step(void *node, void *store, void *p2p, const void *tick, const void *events, void *scratch,
                               void *actions, void *result);
ABI uint64_t lantern_node_protocols(void *out, void *count);
ABI uint64_t lantern_node_run(void *node, void *store, void *seen, const void *work, void *state_a, void *state_b,
                              void *state_c, const void *data, const void *settings, void *scratch, void *event);
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
ABI uint64_t LF(is_data_available)(const void *blob_kzg_commitments, const void *blobs, const void *proofs,
                                       const void *settings, void *scratch, void *out);
#elif FORK >= FORK_FULU
ABI uint64_t LF(is_data_available)(const void *sidecars, const void *settings, const void *config, void *scratch,
                                       void *out);
#endif

/* asm-crypto, at the pin in platform/deps.sh. */
ABI uint64_t crypto_kzg_trusted_setup_of_bytes(const void *g1_lagrange, const void *g1_monomial,
                                               const void *g2_monomial, void *settings);
ABI uint64_t crypto_secp256k1_public_key(const void *private_key, void *public_key);
ABI uint64_t crypto_secp256k1_decompress(const void *public_key, void *point);
ABI uint64_t crypto_keccak256(const void *message, void *digest);
ABI uint64_t crypto_sha256(const void *message, void *digest);
ABI uint64_t crypto_kzg_blob_to_kzg_commitment(const void *settings, const void *blob, void *scratch, void *commitment);
ABI uint64_t crypto_bls_sign(const void *secret_key, const void *message, void *scratch, void *signature);
ABI uint64_t LF(get_attesting_indices)(const void *state, const void *attestation, void *cache, void *scratch, void *out);
ABI uint64_t LF(get_domain)(const void *state, const void *domain_type, const void *epoch, void *scratch, void *out);

#if FORK == FORK_FULU
/* Networking rules: docs/reference/networking.md. */
ABI uint64_t LF(get_custody_groups)(const void *node_id, const void *custody_group_count, const void *config,
                                        void *out);
ABI uint64_t LF(compute_columns_for_custody_group)(const void *custody_group, const void *config, void *out);
ABI uint64_t LF(verify_partial_data_column_header_inclusion_proof)(const void *header, void *scratch, void *out);
#endif

/* Gossip: docs/reference/networking.md. */
ABI uint64_t lantern_seen_size(const void *room, void *size);
ABI uint64_t lantern_seen_init(const void *room, void *seen);
ABI uint64_t lantern_seen_copy(const void *seen, const void *room, void *out);
ABI uint64_t lantern_seen_add_block(void *seen, const void *root, const void *payload_status);
#if FORK == FORK_BELLATRIX
ABI uint64_t LF(validate_beacon_block_gossip)(void *seen, const void *store, const void *block, const void *now,
                                                  const void *head_state, const void *proposer_state,
                                                  const void *justified_state, void *scratch, void *result);
#else
ABI uint64_t LF(validate_beacon_block_gossip)(void *seen, const void *store, const void *block, const void *now,
                                                  const void *head_state, const void *proposer_state, void *scratch, void *result);
#endif
ABI uint64_t LF(validate_beacon_aggregate_and_proof_gossip)(void *seen, const void *store, const void *aggregate,
                                                                const void *now, const void *head_state, void *scratch,
                                                                void *result);
ABI uint64_t LF(validate_beacon_attestation_gossip)(void *seen, const void *store, const void *attestation, const void *now,
                                                        const void *subnet_id, const void *head_state, void *scratch,
                                                        void *result);
ABI uint64_t LF(validate_voluntary_exit_gossip)(void *seen, const void *store, const void *exit, const void *now,
                                                    const void *head_state, void *scratch, void *result);
ABI uint64_t LF(validate_proposer_slashing_gossip)(void *seen, const void *store, const void *slashing, const void *head_state,
                                                       void *scratch, void *result);
ABI uint64_t LF(validate_attester_slashing_gossip)(void *seen, const void *store, const void *slashing, const void *head_state,
                                                       void *scratch, void *result);
#if FORK >= FORK_ALTAIR
ABI uint64_t LF(validate_sync_committee_contribution_and_proof_gossip)(void *seen, const void *store, const void *contribution,
                                                                           const void *now, const void *head_state, void *scratch,
                                                                           void *result);
ABI uint64_t LF(validate_sync_committee_message_gossip)(void *seen, const void *store, const void *message, const void *now,
                                                            const void *subnet_id, const void *head_state, void *scratch,
                                                            void *result);
#define GOSSIP_ALTAIR(X)                                                                                       \
    X(sync_committee_contribution_and_proof, SignedContributionAndProof)                                       \
    X(sync_committee_message, SyncCommitteeMessage)
#else
#define GOSSIP_ALTAIR(X)
#endif
#if FORK >= FORK_CAPELLA
ABI uint64_t LF(validate_bls_to_execution_change_gossip)(void *seen, const void *store, const void *change, const void *now,
                                                             const void *head_state, void *scratch, void *result);
#define GOSSIP_CAPELLA(X) X(bls_to_execution_change, SignedBLSToExecutionChange)
#else
#define GOSSIP_CAPELLA(X)
#endif
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
ABI uint64_t LF(verify_blob_sidecar_inclusion_proof)(const void *sidecar, void *out);
ABI uint64_t LF(compute_subnet_for_blob_sidecar)(const void *blob_index, const void *config, void *out);
ABI uint64_t LF(validate_blob_sidecar_gossip)(void *seen, const void *store, const void *sidecar, const void *now,
                                                  const void *subnet_id, const void *head_state, const void *proposer_state,
                                                  const void *settings, void *scratch, void *result);
#define GOSSIP_BLOBS(X) X(blob_sidecar, BlobSidecar)
#else
#define GOSSIP_BLOBS(X)
#endif
#if FORK >= FORK_FULU
ABI uint64_t LF(validate_data_column_sidecar_gossip)(void *seen, const void *store, const void *sidecar, const void *now,
                                                         const void *subnet_id, const void *head_state, const void *proposer_state,
                                                         const void *settings, void *scratch, void *result);
ABI uint64_t LF(validate_partial_data_column_sidecar_gossip)(void *seen, const void *store, const void *sidecar, const void *now,
                                                                 const void *group_id, const void *column_index,
                                                                 const void *head_state, const void *proposer_state,
                                                                 const void *settings, void *scratch, void *result);
#define GOSSIP_COLUMNS(X)                                                                                      \
    X(data_column_sidecar, DataColumnSidecar)                                                                  \
    X(partial_data_column_sidecar, PartialDataColumnSidecar)
#else
#define GOSSIP_COLUMNS(X)
#endif
#if FORK >= FORK_ELECTRA
#define ATTESTATION_TYPE SingleAttestation
#else
#define ATTESTATION_TYPE Attestation
#endif
#define GOSSIP_TOPICS(X)                                                                                       \
    X(beacon_block, SignedBeaconBlock)                                                                         \
    X(beacon_aggregate_and_proof, SignedAggregateAndProof)                                                     \
    X(beacon_attestation, ATTESTATION_TYPE)                                                                    \
    X(voluntary_exit, SignedVoluntaryExit)                                                                     \
    X(proposer_slashing, ProposerSlashing)                                                                     \
    X(attester_slashing, AttesterSlashing)                                                                     \
    GOSSIP_ALTAIR(X) GOSSIP_CAPELLA(X) GOSSIP_BLOBS(X) GOSSIP_COLUMNS(X)

/* P2p helpers: docs/reference/networking.md. */
ABI uint64_t LF(compute_fork_version)(const void *epoch, const void *config, void *out);
ABI uint64_t LF(compute_fork_digest)(const void *root, const void *epoch, const void *config, void *scratch, void *out);
ABI uint64_t LF(compute_attestation_subnet_prefix_bits)(const void *config, void *out);
ABI uint64_t LF(compute_min_epochs_for_block_requests)(const void *config, void *out);
ABI uint64_t LF(max_compressed_len)(const void *n, void *out);
ABI uint64_t LF(max_message_size)(const void *config, void *out);
ABI uint64_t LF(compute_subscribed_subnet)(const void *node_id, const void *epoch, const void *index, const void *config,
                                               void *scratch, void *out);
ABI uint64_t LF(compute_subscribed_subnets)(const void *node_id, const void *epoch, const void *config, void *scratch,
                                                void *out);
ABI uint64_t LF(compute_enr_fork_id)(const void *root, const void *epoch, const void *config, void *scratch, void *out);
ABI uint64_t LF(compute_message_id)(const void *topic, const void *data, const void *config, void *scratch, void *out);
ABI uint64_t lantern_gossip_topic(const void *topic, void *out);
ABI uint64_t lantern_gossip_topic_parse(const void *string, void *out);
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
ABI uint64_t LF(compute_max_request_blob_sidecars)(const void *config, void *out);
#endif
#if FORK >= FORK_FULU
ABI uint64_t LF(compute_max_request_data_column_sidecars)(const void *config, void *out);
ABI uint64_t LF(compute_next_fork_digest)(const void *root, const void *epoch, const void *config, void *scratch, void *out);
#endif

/* Req/resp encoding: docs/reference/req-resp.md. */
ABI uint64_t lantern_reqresp_protocol_parse(const void *id, void *out);
ABI uint64_t lantern_reqresp_protocol_id(const void *protocol, void *out);
ABI uint64_t lantern_reqresp_chunk_size(const void *n, void *out);
ABI uint64_t lantern_reqresp_write_chunk(const void *header, const void *payload, void *scratch, void *out);
ABI uint64_t lantern_reqresp_read_header(const void *input, void *header);
ABI uint64_t lantern_reqresp_read_payload(const void *input, const void *start, const void *length, const void *eof,
                                          void *scratch, void *out, void *consumed);
ABI uint64_t lantern_ssz_size_bounds(const void *type, void *out);

/* Beacon API: docs/reference/beacon-api.md. */
ABI uint64_t lantern_http_request(const void *bytes, const void *limits, void *out);
ABI uint64_t lantern_api_route(const void *request, void *out);
ABI uint64_t lantern_json_encode(const void *type, const void *value, void *cursor, void *out);
ABI uint64_t lantern_json_encode_ssz(const void *type, const void *ssz, void *cursor, void *out);
ABI uint64_t lantern_json_decode(const void *type, const void *json, void *scratch, void *out, void *fault);
ABI uint64_t lantern_engine_json_decode(const void *type, const void *json, void *scratch, void *out, void *fault);

/* Application: docs/reference/app.md. */
ABI uint64_t lantern_app_options(const void *args, void *options, void *fault);

/* Network config: docs/reference/config.md. */
ABI uint64_t lantern_config_parse(const void *text, void *config, void *line);
/* The database index: docs/reference/db.md. */
ABI uint64_t lantern_db_size(const void *room, void *size);
ABI uint64_t lantern_db_init(const void *room, const void *slot, void *db);
ABI uint64_t lantern_db_copy(const void *db, const void *room, void *out);
ABI uint64_t lantern_db_scan(void *db, const void *segment, const void *sidecars, const void *bytes, void *valid);
ABI uint64_t lantern_eth_get_block_by_number(const void *number, const void *id, void *out);
ABI uint64_t lantern_eth_get_deposit_logs(const void *address, const void *from, const void *to, const void *id, void *out);
ABI uint64_t lantern_eth1_block(const void *json, void *out);
ABI uint64_t lantern_eth1_deposit_logs(const void *json, void *out);
ABI uint64_t lantern_deposit_leaf(const void *data, void *out);
ABI uint64_t lantern_deposit_tree_push(void *tree, const void *leaf);
ABI uint64_t lantern_deposit_tree_root(const void *tree, void *out);
ABI uint64_t lantern_deposit_proof(const void *leaves, const void *count, const void *index, void *scratch, void *out);
ABI uint64_t lantern_node_db_scan(void *node, const void *segment, const void *sidecars, const void *bytes, void *valid);
ABI uint64_t lantern_db_find_root(const void *db, const void *root, void *slot);
ABI uint64_t lantern_db_prune(void *db, const void *slot);
ABI uint64_t lantern_db_drop_sidecars(void *db, const void *slot);
ABI uint64_t lantern_db_add(void *db, const void *record, const void *offset);
ABI uint64_t lantern_db_state_diff(const void *base, const void *state, void *out, void *size);
ABI uint64_t lantern_db_state_patch(const void *base, const void *diff, void *out, void *size);

/* Engine API client: docs/reference/engine-api.md. */
ABI uint64_t lantern_jwt_token(const void *secret, const void *iat, void *scratch, void *out);
ABI uint64_t lantern_http_post(const void *host, const void *token, const void *body, void *out);
ABI uint64_t lantern_http_parse_response(const void *input, const void *eof, void *body, void *out);
ABI uint64_t lantern_engine_exchange_capabilities(const void *id, void *out);
ABI uint64_t lantern_engine_parse_response(const void *body, const void *method, void *out);
#if FORK >= FORK_BELLATRIX
ABI uint64_t LF(engine_new_payload_size)(const void *block, void *out);
ABI uint64_t LF(engine_new_payload)(const void *block, const void *id, void *scratch, void *out);
ABI uint64_t LF(engine_forkchoice_updated)(const void *state, const void *attributes, const void *id, void *out);
ABI uint64_t LF(engine_get_payload)(const void *payload_id, const void *id, void *out);
ABI uint64_t LF(get_payload_attributes)(const void *state, const void *fee_recipient, const void *config, void *scratch, void *out);
#endif
#if FORK >= FORK_ELECTRA
ABI uint64_t LF(get_execution_requests_list)(const void *requests, void *out);
ABI uint64_t LF(get_execution_requests)(const void *list, void *out);
#endif

/* ---------------------------------------------------------------- ABI check */

#define STACK_CAP 65536 /* README: stack per call */
#define PAINT_BYTES (STACK_CAP + 4096)

typedef struct {
    uint64_t fn, arg[5], paint, status, fault, stack, scratch[4], arg5, more[5]; /* more: arguments 7 to 11 */
} abi_ctx;
ABI void abi_call(abi_ctx *ctx);

typedef struct {
    const char *name;
    uint64_t peak, fault, calls;
} fn_stats;

#define MAX_FUNCTIONS 512
static fn_stats stats[MAX_FUNCTIONS];
static int stats_count;

static fn_stats *stats_for(const char *name) {
    for (int i = 0; i < stats_count; i++)
        if (!strcmp(stats[i].name, name)) return &stats[i];
    if (stats_count == MAX_FUNCTIONS) {
        fprintf(stderr, "too many functions\n");
        exit(2);
    }
    stats[stats_count].name = name;
    return &stats[stats_count++];
}

/* Call lantern function f, named name, with up to 11 pointer arguments. */
__attribute__((unused)) static uint64_t checked_call(const char *name, uint64_t f, const void *const *args, size_t n) {
    abi_ctx c;
    memset(&c, 0, sizeof c);
    c.fn = f;
    if (n > 11) {
        fprintf(stderr, "%s: more than 11 arguments\n", name);
        exit(2);
    }
    for (size_t i = 0; i < n && i < 5; i++) c.arg[i] = (uint64_t)(uintptr_t)args[i];
    if (n > 5) c.arg5 = (uint64_t)(uintptr_t)args[5];
    for (size_t i = 6; i < n; i++) c.more[i - 6] = (uint64_t)(uintptr_t)args[i];
    c.paint = PAINT_BYTES;
    abi_call(&c);
    fn_stats *s = stats_for(name);
    if (c.stack > s->peak) s->peak = c.stack;
    s->fault |= c.fault;
    s->calls++;
    return c.status;
}

#define CALL(f, ...)                                                                                           \
    checked_call(STR(f), (uint64_t)(uintptr_t)(f), (const void *const[]){__VA_ARGS__},                             \
                 sizeof((const void *const[]){__VA_ARGS__}) / sizeof(const void *))

/* ---------------------------------------------------------------- Bytes and buffers */

#define GUARD 64
#define FILL 0xA5

static uint64_t rd64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

static void wr64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

static void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    return p;
}

/* A buffer of n bytes, filled, with GUARD guard bytes after it. */
static uint8_t *buffer(uint64_t n) {
    uint8_t *b = xmalloc((size_t)(n + GUARD));
    memset(b, FILL, (size_t)(n + GUARD));
    return b;
}

static int guard_ok(const uint8_t *b, uint64_t n) {
    for (uint64_t i = 0; i < GUARD; i++)
        if (b[n + i] != FILL) return 0;
    return 1;
}

/* ---------------------------------------------------------------- Case files */

enum { T_INT = 1, T_BYTES, T_STRING, T_BOOL, T_LIST, T_MAP, T_NULL, T_UINT256, T_NEG_INT };
typedef const uint8_t *tv; /* a tagged value: its tag byte, then its payload */
static tv case_events; /* the node-events case of the fork choice case that runs, or NULL */
static tv case_reads;  /* the node-reads case of the fork choice or transition case that runs, or NULL */

static tv tv_skip(tv v) {
    switch (*v) {
    case T_INT:
    case T_NEG_INT: return v + 9;
    case T_BYTES:
    case T_STRING: return v + 9 + rd64(v + 1);
    case T_BOOL: return v + 2;
    case T_NULL: return v + 1;
    case T_UINT256: return v + 33;
    case T_LIST: {
        uint64_t n = rd64(v + 1);
        tv p = v + 9;
        while (n--) p = tv_skip(p);
        return p;
    }
    case T_MAP: {
        uint64_t n = rd64(v + 1);
        tv p = v + 9;
        while (n--) p = tv_skip(p + 8 + rd64(p));
        return p;
    }
    default: fprintf(stderr, "bad tag %d\n", *v); exit(2);
    }
}

/* The value of key in map m, or NULL. */
static tv tv_get(tv m, const char *key) {
    if (!m || *m != T_MAP) return NULL;
    uint64_t n = rd64(m + 1), klen = strlen(key);
    tv p = m + 9;
    while (n--) {
        uint64_t len = rd64(p);
        if (len == klen && !memcmp(p + 8, key, klen)) return p + 8 + len;
        p = tv_skip(p + 8 + len);
    }
    return NULL;
}

static uint64_t tv_u64(tv v) {
    if (!v || *v != T_INT) {
        fprintf(stderr, "expected an integer\n");
        exit(2);
    }
    return rd64(v + 1);
}

static const uint8_t *tv_bytes(tv v, uint64_t *len) {
    if (!v || *v != T_BYTES) {
        fprintf(stderr, "expected bytes\n");
        exit(2);
    }
    *len = rd64(v + 1);
    return v + 9;
}

typedef struct {
    uint8_t *data;
    uint64_t size, count, at; /* at: offset of the next case */
} case_file;

static int read_file(const char *dir, const char *name, case_file *f) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) return 0;
    fseek(fp, 0, SEEK_END);
    long n = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    f->data = xmalloc((size_t)n);
    f->size = (uint64_t)n;
    if (fread(f->data, 1, (size_t)n, fp) != (size_t)n || n < 16 || memcmp(f->data, "LANTVEC1", 8)) {
        fprintf(stderr, "%s: not a case file\n", path);
        exit(2);
    }
    fclose(fp);
    f->count = rd64(f->data + 8);
    f->at = 16;
    return 1;
}

/* The committee cache of the process (block-processing.md, Test vectors), emptied before each case. */
static uint8_t *committee_cache;
static uint64_t committee_validators = 4096;

/* The file and case that run now, for the crash report of Windows. */
#ifdef _WIN32
static const char *current_file = "", *current_case = "";
static uint64_t current_case_len;
#define NOTE_CASE(n, l) (current_case = (n), current_case_len = (l))
#define NOTE_FILE(f) (current_file = (f))
#else
#define NOTE_CASE(n, l) ((void)0)
#define NOTE_FILE(f) ((void)0)
#endif

/* The next case: its name (not zero ended) and its parts map. */
static tv next_case(case_file *f, const char **name, uint64_t *name_len) {
    if (committee_cache) CALL(LF(committee_cache_init), &committee_validators, committee_cache);
    *name_len = rd64(f->data + f->at);
    *name = (const char *)(f->data + f->at + 8);
    NOTE_CASE(*name, *name_len);
    tv parts = f->data + f->at + 8 + *name_len;
    f->at = (uint64_t)(tv_skip(parts) - f->data);
    return parts;
}

/* ---------------------------------------------------------------- lantern types */

typedef struct {
    const char *name;
    const uint8_t *desc;
} lantern_type;

/* The root type named name in the type table types of a fork, or NULL. */
static const uint8_t *type_in(const uint8_t *types, const char *name) {
    uint64_t n = rd64(types);
    for (uint64_t i = 0; i < n; i++) {
        const uint8_t *e = types + 8 + 16 * i;
        const char *tname = (const char *)(types - rd64(e + 8));
        if (!strcmp(tname, name)) return types - rd64(e);
    }
    return NULL;
}

/* The root type of this runner's fork named name, or NULL. */
static const uint8_t *type_by_name(const char *name) { return type_in(LF(types), name); }

static const uint8_t *node_of(const uint8_t *d, uint64_t i) { return d + rd64(d + 8) + 72 * i; }
static const uint8_t *field_of(const uint8_t *d, uint64_t i) { return d + rd64(d + 24) + 32 * i; }
static const uint8_t *root_node(const uint8_t *d) { return node_of(d, rd64(d + 40)); }

static uint64_t scratch_size(const uint8_t *d) { return rd64(root_node(d) + 64); }
static uint64_t ssz_size(const uint8_t *d) { return rd64(root_node(d) + 24); }

/*
 * Compare type node ia of descriptor a with node ib of descriptor b: every
 * number of the node, then the elements or fields, to any depth. Writes the
 * first difference to why.
 */
static int same_node(const uint8_t *a, uint64_t ia, const uint8_t *b, uint64_t ib, char *why, size_t whylen,
                     const char *path) {
    static const char *const names[] = {"kind", "length", "element", "ssz", "mem", "align", "fixed", "chunks", "scratch"};
    const uint8_t *na = node_of(a, ia), *nb = node_of(b, ib);
    for (int k = 0; k < 9; k++) {
        if (k == 2) continue;
        if (rd64(na + 8 * k) != rd64(nb + 8 * k)) {
            snprintf(why, whylen, "%s: %s %llu, expected %llu", path, names[k], (unsigned long long)rd64(na + 8 * k),
                     (unsigned long long)rd64(nb + 8 * k));
            return 0;
        }
    }
    uint64_t kind = rd64(na);
    char sub[512];
    if (kind == 7 || kind == 8) {
        snprintf(sub, sizeof sub, "%s[]", path);
        return same_node(a, rd64(na + 16), b, rd64(nb + 16), why, whylen, sub);
    }
    if (kind == 9) {
        for (uint64_t k = 0; k < rd64(na + 8); k++) {
            const uint8_t *fa = field_of(a, rd64(na + 16) + k), *fb = field_of(b, rd64(nb + 16) + k);
            snprintf(sub, sizeof sub, "%s.%llu", path, (unsigned long long)k);
            for (int j = 1; j < 4; j++)
                if (rd64(fa + 8 * j) != rd64(fb + 8 * j)) {
                    snprintf(why, whylen, "%s: field word %d is %llu, expected %llu", sub, j,
                             (unsigned long long)rd64(fa + 8 * j), (unsigned long long)rd64(fb + 8 * j));
                    return 0;
                }
            if (!same_node(a, rd64(fa), b, rd64(fb), why, whylen, sub)) return 0;
        }
    }
    return 1;
}

/* ---------------------------------------------------------------- Results */

static int failures, passes;

static void report(const char *file, const char *name, uint64_t name_len, int ok, const char *why) {
    if (ok) {
        passes++;
        return;
    }
    failures++;
    printf("FAIL %s %.*s: %s\n", file, (int)name_len, name, why ? why : "");
}

/* ---------------------------------------------------------------- Handlers */

/* The reference descriptor of every type that lantern also defines. */
static void run_descriptors(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name;
        uint64_t len;
        tv parts = next_case(f, &name, &len);
        char tname[256];
        snprintf(tname, sizeof tname, "%.*s", (int)len, name);
        const uint8_t *ours = type_by_name(tname);
        if (!ours) continue;
        uint64_t dlen;
        const uint8_t *ref = tv_bytes(tv_get(parts, "descriptor"), &dlen);
        char why[512] = "";
        int ok = same_node(ours, rd64(ours + 40), ref, rd64(ref + 40), why, sizeof why, tname);
        report(file, name, len, ok, why);
    }
}

/* A serialized value as asm-ssz takes it: size, offset 24, count, then the bytes. */
static uint8_t *serialized(const uint8_t *enc, uint64_t len, uint64_t *size) {
    *size = 24 + len;
    uint8_t *s = buffer(*size);
    wr64(s, *size);
    wr64(s + 8, 24);
    wr64(s + 16, len);
    memcpy(s + 24, enc, (size_t)len);
    return s;
}

static uint8_t *scratch_for(const uint8_t *desc, uint64_t *size) {
    *size = scratch_size(desc);
    uint8_t *s = buffer(*size);
    wr64(s, *size);
    return s;
}

/* Decode enc into a new value of type desc. Returns NULL with a reason on failure. */
static uint8_t *decode(const uint8_t *desc, const uint8_t *enc, uint64_t len, uint64_t *vsize, const char **why) {
    uint64_t ssize, scsize, size = 0;
    uint8_t *ser = serialized(enc, len, &ssize), *scr = scratch_for(desc, &scsize), *value = NULL;
    if (ssz_deserialize_size(desc, ser, scr, &size) != 0) *why = "deserialize_size status";
    else {
        value = buffer(size);
        if (ssz_size(desc) == 0) wr64(value, size);
        if (ssz_deserialize(desc, ser, scr, value) != 0) *why = "deserialize status";
        else if (!guard_ok(value, size)) *why = "deserialize wrote out of bounds";
        else *vsize = size;
        if (*why) {
            free(value);
            value = NULL;
        }
    }
    free(ser);
    free(scr);
    return value;
}

static uint8_t *fresh_scratch(void);

/* ssz_static: decode, encode and root of one type, through lantern's descriptor. */
static void run_ssz_static(const char *file, const char *type_name, case_file *f) {
    const uint8_t *desc = type_by_name(type_name);
    if (!desc) {
        printf("SKIP %s: lantern has no type %s\n", file, type_name);
        return;
    }
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, elen, vsize = 0, scsize;
        tv parts = next_case(f, &name, &len);
        const uint8_t *enc = tv_bytes(tv_get(parts, "serialized"), &elen);
        const uint8_t *root = tv_bytes(tv_get(tv_get(parts, "roots"), "root"), &vsize);
        uint8_t *value = decode(desc, enc, elen, &vsize, &why);
        if (value) {
            uint8_t *scr = scratch_for(desc, &scsize), got[32 + GUARD];
            uint64_t need = 0;
            memset(got, FILL, sizeof got);
            if (ssz_serialize_size(desc, value, scr, &need) != 0 || need != 24 + elen) why = "serialize_size";
            else {
                uint8_t *out = buffer(need);
                wr64(out, need);
                if (ssz_serialize(desc, value, scr, out) != 0 || memcmp(out + 24, enc, (size_t)elen))
                    why = "serialize bytes";
                else if (ssz_hash_tree_root(desc, value, scr, got) != 0 || memcmp(got, root, 32))
                    why = "hash_tree_root";
                else if (!strcmp(type_name, "AttestationData")) { /* lantern_node_data_root of the SSZ bytes */
                    memset(got, FILL, sizeof got);
                    if (CALL(LF(node_data_root), enc, fresh_scratch(), got) != 0 || memcmp(got, root, 32))
                        why = "lantern_node_data_root";
                    else if (!guard_ok(got, 32)) why = "lantern_node_data_root wrote out of bounds";
                }
                free(out);
            }
            free(scr);
            free(value);
        }
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Config */

/* include/lantern.inc: CONFIG_* offsets. Kind 0: a u64; kind 1: a 4-byte Version. */
/* A config value: kind 0 a u64, 1 a Version, 2 a Uint256, 3 a Hash32, 4 an Address, 5 a text. */
static const struct {
    const char *name;
    uint64_t offset;
    int kind;
} CONFIG_FIELDS[] = {
    {"GENESIS_FORK_VERSION", 0, 1},
    {"ALTAIR_FORK_VERSION", 8, 1},
    {"ALTAIR_FORK_EPOCH", 16, 0},
    {"BELLATRIX_FORK_VERSION", 24, 1},
    {"BELLATRIX_FORK_EPOCH", 32, 0},
    {"CAPELLA_FORK_VERSION", 40, 1},
    {"CAPELLA_FORK_EPOCH", 48, 0},
    {"DENEB_FORK_VERSION", 56, 1},
    {"DENEB_FORK_EPOCH", 64, 0},
    {"ELECTRA_FORK_VERSION", 72, 1},
    {"ELECTRA_FORK_EPOCH", 80, 0},
    {"FULU_FORK_VERSION", 88, 1},
    {"FULU_FORK_EPOCH", 96, 0},
    {"SLOT_DURATION_MS", 104, 0},
    {"MIN_VALIDATOR_WITHDRAWABILITY_DELAY", 112, 0},
    {"SHARD_COMMITTEE_PERIOD", 120, 0},
    {"EJECTION_BALANCE", 128, 0},
    {"MIN_PER_EPOCH_CHURN_LIMIT", 136, 0},
    {"CHURN_LIMIT_QUOTIENT", 144, 0},
    {"MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT", 152, 0},
    {"MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA", 160, 0},
    {"MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT", 168, 0},
    {"INACTIVITY_SCORE_BIAS", 176, 0},
    {"INACTIVITY_SCORE_RECOVERY_RATE", 184, 0},
    {"MAX_BLOBS_PER_BLOCK_ELECTRA", 192, 0},
    {"PROPOSER_SCORE_BOOST", 200, 0},
    {"REORG_HEAD_WEIGHT_THRESHOLD", 208, 0},
    {"REORG_PARENT_WEIGHT_THRESHOLD", 216, 0},
    {"REORG_MAX_EPOCHS_SINCE_FINALIZATION", 224, 0},
    {"PROPOSER_REORG_CUTOFF_BPS", 232, 0},
    {"ATTESTATION_DUE_BPS", 240, 0},
    {"AGGREGATE_DUE_BPS", 248, 0},
    {"SYNC_MESSAGE_DUE_BPS", 256, 0},
    {"CONTRIBUTION_DUE_BPS", 264, 0},
    {"SAMPLES_PER_SLOT", 272, 0},
    {"NUMBER_OF_CUSTODY_GROUPS", 280, 0},
    {"CUSTODY_REQUIREMENT", 288, 0},
    {"DATA_COLUMN_SIDECAR_SUBNET_COUNT", 296, 0},
    {"MAX_REQUEST_BLOCKS_DENEB", 304, 0},
    {"MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS", 312, 0},
    {"MAX_PAYLOAD_SIZE", 320, 0},
    {"MAXIMUM_GOSSIP_CLOCK_DISPARITY", 328, 0},
    {"SUBNETS_PER_NODE", 336, 0},
    {"EPOCHS_PER_SUBNET_SUBSCRIPTION", 344, 0},
    {"ATTESTATION_SUBNET_EXTRA_BITS", 352, 0},
    {"VALIDATOR_CUSTODY_REQUIREMENT", 360, 0},
    {"BALANCE_PER_ADDITIONAL_CUSTODY_GROUP", 368, 0},
    {"MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS", 376, 0},
    {"MAX_BLOBS_PER_BLOCK", 392 + 16 * 32, 0},
    {"MIN_GENESIS_TIME", 392 + 16 * 32 + 8, 0},
    {"MIN_GENESIS_ACTIVE_VALIDATOR_COUNT", 392 + 16 * 32 + 16, 0},
    {"GENESIS_DELAY", 392 + 16 * 32 + 24, 0},
    {"TERMINAL_TOTAL_DIFFICULTY", 392 + 16 * 32 + 32, 2},
    {"TERMINAL_BLOCK_HASH", 392 + 16 * 32 + 64, 3},
    {"TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH", 392 + 16 * 32 + 96, 0},
    {"ATTESTATION_PROPAGATION_SLOT_RANGE", 392 + 16 * 32 + 104, 0},
    {"BLOB_SIDECAR_SUBNET_COUNT", 392 + 16 * 32 + 112, 0},
    {"BLOB_SIDECAR_SUBNET_COUNT_ELECTRA", 392 + 16 * 32 + 120, 0},
    {"MAX_REQUEST_BLOCKS", 392 + 16 * 32 + 128, 0},
    {"MESSAGE_DOMAIN_INVALID_SNAPPY", 392 + 16 * 32 + 136, 1},
    {"MESSAGE_DOMAIN_VALID_SNAPPY", 392 + 16 * 32 + 144, 1},
    {"SECONDS_PER_ETH1_BLOCK", 392 + 16 * 32 + 176, 0},
    {"ETH1_FOLLOW_DISTANCE", 392 + 16 * 32 + 184, 0},
    {"DEPOSIT_CHAIN_ID", 392 + 16 * 32 + 192, 0},
    {"DEPOSIT_NETWORK_ID", 392 + 16 * 32 + 200, 0},
    {"ATTESTATION_SUBNET_COUNT", 392 + 16 * 32 + 208, 0},
    {"DEPOSIT_CONTRACT_ADDRESS", 392 + 16 * 32 + 216, 4},
    {"PRESET_BASE", 392 + 16 * 32 + 248, 5},
    {"CONFIG_NAME", 392 + 16 * 32 + 320, 5},
};
#define CONFIG_BLOB_SCHEDULE_COUNT 384
#define CONFIG_SUBNETS_PER_NODE 336
#define CONFIG_BLOB_SCHEDULE 392
#define CONFIG_STATE_CACHE (392 + 16 * 32 + 152)
#define CONFIG_COMMITTEE_CACHE (392 + 16 * 32 + 160)
#define CONFIG_PUBKEY_CACHE (392 + 16 * 32 + 168)
#define CONFIG_SIZE (392 + 16 * 32 + 392)

static uint8_t config[CONFIG_SIZE];

/* Fill config from a config map; with overrides set, a value the map does not hold stays. */
static void config_from_map(tv map, int overrides) {
    for (size_t i = 0; i < sizeof CONFIG_FIELDS / sizeof CONFIG_FIELDS[0]; i++) {
        tv v = tv_get(map, CONFIG_FIELDS[i].name);
        if (!v && overrides) continue;
        if (!v) {
            fprintf(stderr, "config: no %s\n", CONFIG_FIELDS[i].name);
            exit(2);
        }
        uint8_t *dst = config + CONFIG_FIELDS[i].offset;
        if (CONFIG_FIELDS[i].kind == 1) {
            /* YAML reads an unquoted 0x00000000 as a number: its 4 bytes, big endian. */
            memset(dst, 0, 8);
            if (*v == T_INT) {
                uint64_t n = tv_u64(v);
                for (int b = 0; b < 4; b++) dst[b] = (uint8_t)(n >> (24 - 8 * b));
            } else {
                uint64_t len;
                const uint8_t *b = tv_bytes(v, &len);
                memcpy(dst, b, len < 4 ? len : 4);
            }
        } else if (CONFIG_FIELDS[i].kind == 2) { /* little endian */
            memset(dst, 0, 32);
            if (*v == T_UINT256) memcpy(dst, v + 1, 32);
            else wr64(dst, tv_u64(v));
        } else if (CONFIG_FIELDS[i].kind == 3 || CONFIG_FIELDS[i].kind == 4) {
            /* an unquoted 0x... hash or address reads as a number: its bytes, big endian */
            int n = CONFIG_FIELDS[i].kind == 3 ? 32 : 20;
            uint8_t le[32] = {0};
            memset(dst, 0, 32);
            if (*v == T_UINT256) memcpy(le, v + 1, 32);
            else if (*v == T_INT) wr64(le, tv_u64(v));
            else {
                uint64_t len;
                const uint8_t *b = tv_bytes(v, &len);
                memcpy(dst, b, len < (uint64_t)n ? len : (uint64_t)n);
                continue;
            }
            for (int b = 0; b < n; b++) dst[b] = le[n - 1 - b];
        } else if (CONFIG_FIELDS[i].kind == 5) { /* a text: its length, then 64 bytes */
            if (*v != T_STRING && *v != T_BYTES) {
                fprintf(stderr, "config: %s is no text\n", CONFIG_FIELDS[i].name);
                exit(2);
            }
            uint64_t len = rd64(v + 1);
            const uint8_t *b = v + 9;
            memset(dst, 0, 72);
            wr64(dst, len);
            memcpy(dst + 8, b, len < 64 ? len : 64);
        } else {
            wr64(config + CONFIG_FIELDS[i].offset, tv_u64(v));
        }
    }
    tv sched = tv_get(map, "BLOB_SCHEDULE");
    if (!sched && overrides) return;
    uint64_t n = sched && *sched == T_LIST ? rd64(sched + 1) : 0;
    if (n > 32) {
        fprintf(stderr, "config: BLOB_SCHEDULE has more than 32 entries\n");
        exit(2);
    }
    wr64(config + CONFIG_BLOB_SCHEDULE_COUNT, n);
    tv e = n ? sched + 9 : NULL;
    for (uint64_t i = 0; i < n; i++) {
        wr64(config + CONFIG_BLOB_SCHEDULE + 16 * i, tv_u64(tv_get(e, "EPOCH")));
        wr64(config + CONFIG_BLOB_SCHEDULE + 16 * i + 8, tv_u64(tv_get(e, "MAX_BLOBS_PER_BLOCK")));
        e = tv_skip(e);
    }
}

/* The config of <preset>-config.bin, and a copy of it for the cases that override values. */
static uint8_t base_config[CONFIG_SIZE];
static uint8_t *state_cache;
static unsigned long cached_roots;
static void load_config(const char *dir) {
    case_file f;
    char name[64];
    snprintf(name, sizeof name, "%s-config.bin", PRESET);
    if (!read_file(dir, name, &f)) {
        fprintf(stderr, "%s/%s: missing\n", dir, name);
        exit(2);
    }
    const char *cname;
    uint64_t clen;
    config_from_map(next_case(&f, &cname, &clen), 0);
    /* One StateCache for the process (state.md, Test vectors): every call's config names it. */
    uint64_t validators = 4096, csize = 0;
    CALL(LF(state_cache_size), &validators, &csize);
    state_cache = buffer(csize);
    wr64(state_cache, csize);
    if (CALL(LF(state_cache_init), &validators, state_cache) != 0) {
        fprintf(stderr, "state_cache_init status\n");
        exit(2);
    }
    wr64(config + CONFIG_STATE_CACHE, (uint64_t)(uintptr_t)state_cache);
    CALL(LF(committee_cache_size), &committee_validators, &csize);
    committee_cache = buffer(csize);
    wr64(committee_cache, csize);
    if (CALL(LF(committee_cache_init), &committee_validators, committee_cache) != 0) {
        fprintf(stderr, "committee_cache_init status\n");
        exit(2);
    }
    wr64(config + CONFIG_COMMITTEE_CACHE, (uint64_t)(uintptr_t)committee_cache);
#ifndef BLS_OFF /* the spec's tests with signatures off check no key: no PubkeyCache there (block-processing.md) */
    CALL(LF(pubkey_cache_size), &committee_validators, &csize);
    uint8_t *pubkey_cache = buffer(csize);
    wr64(pubkey_cache, csize);
    if (CALL(LF(pubkey_cache_init), &committee_validators, pubkey_cache) != 0) {
        fprintf(stderr, "pubkey_cache_init status\n");
        exit(2);
    }
    wr64(config + CONFIG_PUBKEY_CACHE, (uint64_t)(uintptr_t)pubkey_cache);
#endif
    memcpy(base_config, config, CONFIG_SIZE);
    free(f.data);
}


/* ---------------------------------------------------------------- States */


/*
 * Whether this is the signatures-off runner. bls_setting 2 cases were made with
 * signature checks off: runner-<preset>-<fork> skips them, and
 * runner-<preset>-<fork>-bls-off (built with BLS_OFF and tests/runner/bls_off.c)
 * runs only them. skipped counts the cases this runner skips.
 */
#ifdef BLS_OFF
static const int bls_off = 1;
#else
static const int bls_off = 0;
#endif
static int skipped;

/*
 * Bytes of the scratch buffer. The runner fills all of it before every call, so its size sets most of the
 * runner's own time: it is the largest need of any call of the vectors, rounded up (tests/runner/README.md).
 */
#ifndef SCRATCH_BYTES
#define SCRATCH_BYTES (4u << 20)
#endif
static uint8_t *scratch_buf;

/* The bls_setting of a case: 0 when it has none. */
static uint64_t bls_setting(tv parts) {
    tv v = tv_get(tv_get(parts, "meta"), "bls_setting");
    return v ? tv_u64(v) : 0;
}

/* Whether this runner skips a case, by its bls_setting. */
static int skip_case(tv parts) {
#ifdef BLS_OFF
    int skip = bls_setting(parts) != 2;
#else
    int skip = bls_setting(parts) == 2;
#endif
    skipped += skip;
    return skip;
}

/* A fresh scratch for one call: filled, with its size set. The buffer is made at the first call. */
static uint8_t *fresh_scratch(void) {
    if (!scratch_buf) scratch_buf = buffer(SCRATCH_BYTES);
    memset(scratch_buf, FILL, SCRATCH_BYTES + GUARD);
    wr64(scratch_buf, SCRATCH_BYTES);
    return scratch_buf;
}

/* A fresh scratch of size bytes, as fresh_scratch: past SCRATCH_BYTES, a larger buffer kept for the next such call. */
static uint8_t *sized_scratch(uint64_t size) {
    static uint8_t *big;
    static uint64_t big_size;
    if (size <= SCRATCH_BYTES) return fresh_scratch();
    if (size > big_size) {
        free(big);
        big = buffer(size);
        big_size = size;
    }
    memset(big, FILL, (size_t)(size + GUARD));
    wr64(big, size);
    return big;
}

/* A state decoded from enc and copied with room in each list. NULL with a reason on failure. */
static uint8_t *load_state(const uint8_t *enc, uint64_t len, uint64_t *size, const char **why) {
    const uint8_t *desc = type_by_name("BeaconState");
    uint64_t vsize = 0;
    uint8_t *value = decode(desc, enc, len, &vsize, why);
    if (!value) return NULL;
    uint64_t room[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}, need = 0; /* StateRoom: docs/reference/state.md */
    CALL(LF(beacon_state_copy_size), value, room, &need);
    uint8_t *state = buffer(need + 4096);
    wr64(state, need + 4096);
    if (CALL(LF(beacon_state_copy), value, room, state) != 0) {
        *why = STR(LF(beacon_state_copy)) " status";
        free(state);
        state = NULL;
    } else if (!guard_ok(state, need + 4096)) {
        *why = STR(LF(beacon_state_copy)) " wrote out of bounds";
        free(state);
        state = NULL;
    }
    *size = need + 4096;
    free(value);
    return state;
}

/*
 * The resize step of ARCHITECTURE.md section 6: copy state into a new buffer
 * with each list's room times growth. The old buffer is freed.
 */
static uint8_t *regrow(uint8_t *state, uint64_t *size, uint64_t growth, const char **why) {
    uint64_t room[8] = {64 * growth, 2048 * growth, 4 * growth,  9000 * growth,
                        64 * growth, 64 * growth,   4 * growth, 4096 * growth}, need = 0;
    CALL(LF(beacon_state_copy_size), state, room, &need);
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(LF(beacon_state_copy), state, room, out) != 0) {
        *why = "regrow: copy status";
        free(out);
        return state;
    }
    free(state);
    *size = need;
    return out;
}

/* Whether state encodes to the bytes want. */
static int state_equals(const uint8_t *state, const uint8_t *want, uint64_t len, const char **why) {
    const uint8_t *desc = type_by_name("BeaconState");
    uint64_t scsize, need = 0;
    uint8_t *scr = scratch_for(desc, &scsize);
    int ok = 0;
    if (ssz_serialize_size(desc, state, scr, &need) != 0) *why = "post state: serialize_size status";
    else {
        uint8_t *out = buffer(need);
        wr64(out, need);
        if (ssz_serialize(desc, state, scr, out) != 0) *why = "post state: serialize status";
        else if (need != 24 + len) *why = "post state: length differs";
        else if (memcmp(out + 24, want, (size_t)len)) *why = "post state: bytes differ";
        else ok = 1;
        free(out);
    }
    if (ok) { /* lantern_state_root, with the process's cache and with 0, against ssz_hash_tree_root */
        uint8_t want_root[32], got[32];
        if (ssz_hash_tree_root(desc, state, scr, want_root) != 0) *why = "post state: hash_tree_root status", ok = 0;
        else if (CALL(LF(state_root), state, state_cache, fresh_scratch(), got) != 0) *why = "post state: state_root status", ok = 0;
        else if (memcmp(got, want_root, 32)) *why = "post state: state_root with the cache differs", ok = 0;
        else if (CALL(LF(state_root), state, NULL, fresh_scratch(), got) != 0) *why = "post state: state_root status", ok = 0;
        else if (memcmp(got, want_root, 32)) *why = "post state: state_root with no cache differs", ok = 0;
        else cached_roots++;
    }
    free(scr);
    return ok;
}

/* ---------------------------------------------------------------- Epoch processing */

static const struct {
    const char *handler, *name;
    epoch_fn fn;
} EPOCH[] = {
#define EPOCH_ENTRY(name) {#name, STR(LF(process_##name)), LF(process_##name)},
    EPOCH_FUNCTIONS(EPOCH_ENTRY)
    {NULL, NULL, NULL}};

static void run_epoch(const char *file, const char *handler, case_file *f) {
    int k = 0;
    while (EPOCH[k].handler && strcmp(EPOCH[k].handler, handler)) k++;
    if (!EPOCH[k].handler) {
        printf("SKIP %s: lantern has no process_%s\n", file, handler);
        return;
    }
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        tv post = tv_get(parts, "post");
        uint8_t *state = load_state(pre, plen, &size, &why);
        if (state) {
            uint64_t result = 0xA5A5A5A5A5A5A5A5u;
            uint64_t st = checked_call(EPOCH[k].name, (uint64_t)(uintptr_t)EPOCH[k].fn,
                                       (const void *const[]){state, config, fresh_scratch(), &result}, 4);
            if (st != 0) why = "status not 0";
            else if (!guard_ok(state, size)) why = "wrote past the state";
            else if (!guard_ok(scratch_buf, SCRATCH_BYTES)) why = "wrote past the scratch";
            else if (post) {
                uint64_t qlen;
                const uint8_t *want = tv_bytes(post, &qlen);
                if (result != 0) why = "result not valid";
                else state_equals(state, want, qlen, &why);
            } else if (result == 0) why = "expected an invalid result";
            free(state);
        }
        /* The whole epoch, where the case has its states before and after. */
        tv pre_epoch = tv_get(parts, "pre_epoch");
        if (!why && pre_epoch) {
            uint64_t elen;
            const uint8_t *e = tv_bytes(pre_epoch, &elen);
            tv post_epoch = tv_get(parts, "post_epoch");
            state = load_state(e, elen, &size, &why);
            if (state) {
                uint64_t result = 0xA5A5A5A5A5A5A5A5u;
                uint64_t st = CALL(LF(process_epoch), state, config, fresh_scratch(), &result);
                if (st != 0) why = "process_epoch: status not 0";
                else if (post_epoch) {
                    uint64_t qlen;
                    const uint8_t *want = tv_bytes(post_epoch, &qlen);
                    if (result != 0) why = "process_epoch: result not valid";
                    else if (!state_equals(state, want, qlen, &why)) why = why ? why : "process_epoch: post state";
                } else if (result == 0) why = "process_epoch: expected an invalid result";
                free(state);
            }
        }
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Operations */

static const struct {
    const char *handler, *name, *part, *type;
    op_fn fn;
} OPS[] = {
#define OP_ENTRY(handler, fn, part, type) {#handler, STR(LF(process_##fn)), #part, #type, LF(process_##fn)},
    OPERATIONS(OP_ENTRY)
    {NULL, NULL, NULL, NULL, NULL}};

static void run_operations(const char *file, const char *handler, case_file *f) {
    int k = 0, payload = !strcmp(handler, "execution_payload");
    while (OPS[k].handler && strcmp(OPS[k].handler, handler)) k++;
    if (!payload && !OPS[k].handler) {
        printf("SKIP %s: lantern has no handler %s\n", file, handler);
        return;
    }
    const char *part = payload ? "body" : OPS[k].part, *type = payload ? "BeaconBlockBody" : OPS[k].type;
    const uint8_t *desc = type_by_name(type);
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, olen, size, vsize;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        const uint8_t *enc = tv_bytes(tv_get(parts, part), &olen);
        tv post = tv_get(parts, "post");
        uint8_t *state = load_state(pre, plen, &size, &why), *op = NULL;
        if (state) op = decode(desc, enc, olen, &vsize, &why);
        if (state && op) {
            uint64_t result = 0xA5A5A5A5A5A5A5A5u, st;
            if (payload) {
#if FORK >= FORK_BELLATRIX
                tv ex = tv_get(tv_get(parts, "execution"), "execution_valid");
                uint64_t valid = ex && *ex == T_BOOL ? ex[1] : 1;
                st = CALL(LF(process_execution_payload), state, op, &valid, config, fresh_scratch(), &result);
#else
                st = 1;
                why = "the fork has no execution payload";
#endif
            } else {
                st = checked_call(OPS[k].name, (uint64_t)(uintptr_t)OPS[k].fn,
                                  (const void *const[]){state, op, config, fresh_scratch(), &result}, 5);
            }
            if (st != 0) why = "status not 0";
            else if (!guard_ok(state, size)) why = "wrote past the state";
            else if (!guard_ok(scratch_buf, SCRATCH_BYTES)) why = "wrote past the scratch";
            else if (post) {
                uint64_t qlen;
                const uint8_t *want = tv_bytes(post, &qlen);
                if (result != 0) {
                    static char msg[64];
                    snprintf(msg, sizeof msg, "result %llu, expected valid", (unsigned long long)result);
                    why = msg;
                } else state_equals(state, want, qlen, &why);
            } else if (result == 0) why = "expected an invalid result";
        }
        free(op);
        free(state);
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Sanity, finality, random */

/* sanity/slots: process_slots by the case's slot count. */
static void run_slots(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        uint8_t *state = load_state(pre, plen, &size, &why);
        if (state) {
            const uint8_t *desc = type_by_name("BeaconState");
            uint64_t slot_off = 0;
            /* BeaconState.slot: the u64 after genesis_time and genesis_validators_root. */
            (void)desc;
            slot_off = 8 + 8 + 32;
            uint64_t slot = rd64(state + slot_off) + tv_u64(tv_get(parts, "slots")), result = 1, st;
            uint8_t *before = buffer(size);
            for (uint64_t growth = 2;; growth *= 2) {
                memcpy(before, state, (size_t)size);
                st = CALL(LF(process_slots), state, &slot, config, fresh_scratch(), &result);
                if (st != 1 || growth > 1024) break;
                if (memcmp(before, state, (size_t)size)) {
                    why = "BUFFER_TOO_SMALL changed the state";
                    break;
                }
                state = regrow(state, &size, growth, &why);
                free(before);
                before = buffer(size);
            }
            free(before);
            uint64_t qlen;
            const uint8_t *want = tv_bytes(tv_get(parts, "post"), &qlen);
            if (why) {
            } else if (st != 0) why = "status not 0";
            else if (result != 0) why = "result not valid";
            else state_equals(state, want, qlen, &why);
            free(state);
        }
        report(file, name, len, why == NULL, why);
    }
}

/* sanity/blocks, finality, random: state_transition of each block in turn. */
static void run_blocks(const char *file, case_file *f) {
    const uint8_t *desc = type_by_name("SignedBeaconBlock");
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        tv post = tv_get(parts, "post");
        uint64_t blocks = tv_u64(tv_get(tv_get(parts, "meta"), "blocks_count"));
        uint8_t *state = load_state(pre, plen, &size, &why);
        int invalid = 0;
        for (uint64_t b = 0; state && !why && !invalid && b < blocks; b++) {
            char key[32];
            snprintf(key, sizeof key, "blocks_%llu", (unsigned long long)b);
            uint64_t blen, vsize;
            const uint8_t *enc = tv_bytes(tv_get(parts, key), &blen);
            uint8_t *block = decode(desc, enc, blen, &vsize, &why);
            if (!block) break;
            uint64_t options[3] = {1, 1, 0}, result = 0xA5A5A5A5A5A5A5A5u, st; /* TransitionOptions */
            for (uint64_t growth = 2;; growth *= 2) {
                st = CALL(LF(state_transition), state, block, options, config, fresh_scratch(), &result);
                if (st != 1 || growth > 1024) break;
                state = regrow(state, &size, growth, &why);
            }
            if (st != 0) {
                static char msg[64];
                snprintf(msg, sizeof msg, "block %llu: status %llu", (unsigned long long)b, (unsigned long long)st);
                why = msg;
            } else if (result != 0) {
                invalid = 1;
                if (post) {
                    static char msg[64];
                    snprintf(msg, sizeof msg, "block %llu: result %llu", (unsigned long long)b, (unsigned long long)result);
                    why = msg;
                }
            }
            free(block);
        }
        if (state && !why) {
            if (post) {
                uint64_t qlen;
                const uint8_t *want = tv_bytes(post, &qlen);
                state_equals(state, want, qlen, &why);
            } else if (!invalid) why = "expected an invalid block";
        }
        free(state);
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Fork upgrades and transitions */

#if FORK > FORK_PHASE0
/* The slots of an epoch in this runner's preset. */
static uint64_t slots_per_epoch(void) { return strcmp(PRESET, "minimal") ? 32 : 8; }

/* A state of the fork before, decoded from enc and copied with room in each list. NULL with a reason on failure. */
static uint8_t *load_prev_state(const uint8_t *enc, uint64_t len, uint64_t *size, const char **why) {
    const uint8_t *desc = type_in(LP(types), "BeaconState");
    uint64_t vsize = 0;
    uint8_t *value = decode(desc, enc, len, &vsize, why);
    if (!value) return NULL;
    uint64_t room[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}, need = 0; /* StateRoom: docs/reference/state.md */
    CALL(LP(beacon_state_copy_size), value, room, &need);
    uint8_t *state = buffer(need + 4096);
    wr64(state, need + 4096);
    if (CALL(LP(beacon_state_copy), value, room, state) != 0 || !guard_ok(state, need + 4096)) {
        *why = STR(LP(beacon_state_copy)) " failed";
        free(state);
        state = NULL;
    }
    *size = need + 4096;
    free(value);
    return state;
}

/* regrow with the copy of the fork before. */
static uint8_t *regrow_prev(uint8_t *state, uint64_t *size, uint64_t growth, const char **why) {
    uint64_t room[8] = {64 * growth, 2048 * growth, 4 * growth,  9000 * growth,
                        64 * growth, 64 * growth,   4 * growth, 4096 * growth}, need = 0;
    CALL(LP(beacon_state_copy_size), state, room, &need);
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(LP(beacon_state_copy), state, room, out) != 0) {
        *why = "regrow: copy status";
        free(out);
        return state;
    }
    free(state);
    *size = need;
    return out;
}

/* The state of this runner's fork that the upgrade writes from pre, a state of the fork before. NULL with a reason on failure. */
static uint8_t *upgrade_state(const uint8_t *pre, uint64_t *size, const char **why) {
    uint64_t room[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}, need = 0;
    CALL(LF(upgrade_size), pre, room, &need);
    uint8_t *out = buffer(need + 4096);
    wr64(out, need + 4096);
    uint64_t st = CALL(UPGRADE, pre, room, config, fresh_scratch(), out);
    if (st != 0) {
        static char msg[64];
        snprintf(msg, sizeof msg, "upgrade: status %llu", (unsigned long long)st);
        *why = msg;
    } else if (!guard_ok(out, need + 4096)) *why = "upgrade: wrote past the state";
    else if (!guard_ok(scratch_buf, SCRATCH_BYTES)) *why = "upgrade: wrote past the scratch";
    if (*why) {
        free(out);
        return NULL;
    }
    *size = need + 4096;
    return out;
}

/* fork/fork: the upgrade of pre equals post. */
static void run_fork(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, qlen, size, osize;
        tv parts = next_case(f, &name, &len);
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        const uint8_t *want = tv_bytes(tv_get(parts, "post"), &qlen);
        uint8_t *state = load_prev_state(pre, plen, &size, &why), *out = NULL;
        if (state) out = upgrade_state(state, &osize, &why);
        if (out) state_equals(out, want, qlen, &why);
        free(out);
        free(state);
        report(file, name, len, why == NULL, why);
    }
}

/* The fork at the first slot of fork_epoch: process_slots of the fork before, then the upgrade. */
static uint8_t *fork_over(uint8_t *state, uint64_t *size, uint64_t fork_epoch, const char **why) {
    uint64_t slot = fork_epoch * slots_per_epoch(), result = 0, st = 0;
    if (rd64(state + 48) < slot) { /* BeaconState.slot: after the size, genesis_time and genesis_validators_root */
        for (uint64_t growth = 2;; growth *= 2) {
            st = CALL(LP(process_slots), state, &slot, config, fresh_scratch(), &result);
            if (st != 1 || growth > 1024) break;
            state = regrow_prev(state, size, growth, why);
        }
    }
    if (st != 0 || result != 0) {
        *why = "process_slots to the fork failed";
        return state;
    }
    uint8_t *out = upgrade_state(state, size, why);
    if (!out) return state;
    free(state);
    return out;
}

/* The offset of field i of the container type name of this runner's fork. */
static uint64_t field_at(const char *name, uint64_t i) {
    const uint8_t *d = type_by_name(name);
    return rd64(field_of(d, rd64(root_node(d) + 16) + i) + 8);
}

/*
 * The block on the fork slot: the slots up to it ran before the upgrade, so the state transition
 * runs without process_slots: the signature, process_block, the state root.
 */
static void block_on_fork_slot(uint8_t **state, uint64_t *size, const uint8_t *signed_block, const char **why) {
    const uint8_t *block = signed_block + rd64(signed_block + field_at("SignedBeaconBlock", 0));
    uint64_t valid = 0, execution_valid = 1, result = 0, st = 0;
    if (CALL(LF(verify_block_signature), *state, signed_block, fresh_scratch(), &valid) != 0 || valid != 1) {
        *why = "fork slot block: signature";
        return;
    }
    for (uint64_t growth = 2;; growth *= 2) {
        st = CALL(LF(process_block), *state, block, &execution_valid, config, fresh_scratch(), &result);
        if (st != 1 || growth > 1024) break;
        *state = regrow(*state, size, growth, why);
    }
    if (st != 0 || result != 0) {
        *why = "fork slot block: process_block";
        return;
    }
    const uint8_t *desc = type_by_name("BeaconState");
    uint64_t scsize;
    uint8_t *scr = scratch_for(desc, &scsize), root[32];
    if (ssz_hash_tree_root(desc, *state, scr, root) != 0) *why = "fork slot block: state root status";
    else if (memcmp(root, block + field_at("BeaconBlock", 3), 32)) *why = "fork slot block: state root differs";
    free(scr);
}

static void transition_node_case(tv parts, uint64_t fork_epoch, int *ran, const char **why);

/*
 * transition/core: the blocks up to fork_block with the fork before, the fork, then the other blocks; then
 * through the node, with the node-reads case "transition/" and the case's name after its blocks.
 */
static void run_transition(const char *file, const char *dir, case_file *f) {
    const uint8_t *pre_desc = type_in(LP(types), "SignedBeaconBlock"), *post_desc = type_by_name("SignedBeaconBlock");
    case_file reads = {0};
    if (!read_file(dir, PRESET "-" STR(FORK_NAME) "-node-reads.bin", &reads)) {
        fprintf(stderr, "%s/%s-%s-node-reads.bin: missing\n", dir, PRESET, STR(FORK_NAME));
        exit(2);
    }
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        case_reads = NULL;
        reads.at = 16;
        for (uint64_t r = 0; r < reads.count && !case_reads; r++) {
            const char *rname;
            uint64_t rlen;
            tv rparts = next_case(&reads, &rname, &rlen);
            if (rlen == 11 + len && !memcmp(rname, "transition/", 11) && !memcmp(rname + 11, name, (size_t)len)) case_reads = rparts;
        }
        tv meta = tv_get(parts, "meta"), fb = tv_get(meta, "fork_block");
        uint64_t blocks = tv_u64(tv_get(meta, "blocks_count")), fork_epoch = tv_u64(tv_get(meta, "fork_epoch"));
        int64_t fork_block = fb ? (int64_t)tv_u64(fb) : -1;
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        uint8_t *state = load_prev_state(pre, plen, &size, &why);
        int upgraded = 0;
        for (uint64_t b = 0; state && !why && b < blocks; b++) {
            if (!upgraded && (int64_t)b > fork_block) {
                state = fork_over(state, &size, fork_epoch, &why);
                upgraded = 1;
                if (why) break;
            }
            char key[32];
            snprintf(key, sizeof key, "blocks_%llu", (unsigned long long)b);
            uint64_t blen, vsize;
            const uint8_t *enc = tv_bytes(tv_get(parts, key), &blen);
            uint8_t *block = decode(upgraded ? post_desc : pre_desc, enc, blen, &vsize, &why);
            if (!block) break;
            if (upgraded) { /* BeaconBlock.slot: after the message's size */
                const uint8_t *msg = block + rd64(block + field_at("SignedBeaconBlock", 0));
                if (rd64(msg + field_at("BeaconBlock", 0)) == rd64(state + 48)) {
                    block_on_fork_slot(&state, &size, block, &why);
                    free(block);
                    continue;
                }
            }
            uint64_t options[3] = {1, 1, 0}, result = 0xA5A5A5A5A5A5A5A5u, st; /* TransitionOptions */
            for (uint64_t growth = 2;; growth *= 2) {
                st = upgraded ? CALL(LF(state_transition), state, block, options, config, fresh_scratch(), &result)
                              : CALL(LP(state_transition), state, block, options, config, fresh_scratch(), &result);
                if (st != 1 || growth > 1024) break;
                state = upgraded ? regrow(state, &size, growth, &why) : regrow_prev(state, &size, growth, &why);
            }
            if (st != 0 || result != 0) {
                static char msg[80];
                snprintf(msg, sizeof msg, "block %llu: status %llu, result %llu", (unsigned long long)b,
                         (unsigned long long)st, (unsigned long long)result);
                why = msg;
            }
            free(block);
        }
        if (state && !why && !upgraded) state = fork_over(state, &size, fork_epoch, &why);
        if (state && !why) {
            uint64_t qlen;
            const uint8_t *want = tv_bytes(tv_get(parts, "post"), &qlen);
            state_equals(state, want, qlen, &why);
        }
        free(state);
        report(file, name, len, why == NULL, why);
        int ran = 0;
        const char *nwhy = NULL;
        transition_node_case(parts, fork_epoch, &ran, &nwhy);
        case_reads = NULL;
        if (ran) {
            char nname[256];
            int nlen = snprintf(nname, sizeof nname, "%.*s (node)", (int)len, name);
            report(file, nname, (uint64_t)nlen, nwhy == NULL, nwhy);
        }
    }
    free(reads.data);
}
#endif

/* ---------------------------------------------------------------- Genesis */

#if FORK == FORK_PHASE0
/* genesis/initialization: the state from the eth1 block and the deposits equals state. */
static void run_genesis_init(const char *file, case_file *f) {
    const uint8_t *ddesc = type_by_name("Deposit");
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, hlen, qlen;
        tv parts = next_case(f, &name, &len);
        tv eth1 = tv_get(parts, "eth1");
        const uint8_t *hash = tv_bytes(tv_get(eth1, "eth1_block_hash"), &hlen);
        uint64_t timestamp = tv_u64(tv_get(eth1, "eth1_timestamp"));
        uint64_t n = tv_u64(tv_get(tv_get(parts, "meta"), "deposits_count")), stride = 0;
        uint8_t *deposits = NULL;
        for (uint64_t d = 0; d < n && !why; d++) {
            char key[32];
            snprintf(key, sizeof key, "deposits_%llu", (unsigned long long)d);
            uint64_t dlen, vsize;
            const uint8_t *enc = tv_bytes(tv_get(parts, key), &dlen);
            uint8_t *value = decode(ddesc, enc, dlen, &vsize, &why);
            if (!value) break;
            if (!deposits) deposits = buffer(n * (stride = vsize));
            if (vsize != stride) why = "deposit: value sizes differ";
            else memcpy(deposits + d * stride, value, (size_t)stride);
            free(value);
        }
        if (!why && hlen != 32) why = "eth1_block_hash: not 32 bytes";
        if (!why) {
            uint64_t room[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}, need = 0;
            CALL(LF(initialize_beacon_state_from_eth1_size), &n, room, &need);
            uint8_t *state = buffer(need + 4096);
            wr64(state, need + 4096);
            uint64_t st = CALL(LF(initialize_beacon_state_from_eth1), hash, &timestamp, deposits ? deposits : state, &n,
                               room, config, fresh_scratch(), state);
            if (st != 0) why = "status not 0";
            else if (!guard_ok(state, need + 4096)) why = "wrote past the state";
            else if (!guard_ok(scratch_buf, SCRATCH_BYTES)) why = "wrote past the scratch";
            else state_equals(state, tv_bytes(tv_get(parts, "state"), &qlen), qlen, &why);
            free(state);
        }
        free(deposits);
        report(file, name, len, why == NULL, why);
    }
}

/* genesis/validity: is_valid_genesis_state of genesis equals is_valid. */
static void run_genesis_validity(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        const uint8_t *enc = tv_bytes(tv_get(parts, "genesis"), &plen);
        tv want = tv_get(parts, "is_valid");
        uint8_t *state = load_state(enc, plen, &size, &why);
        if (state) {
            uint64_t out = 2;
            if (CALL(LF(is_valid_genesis_state), state, config, &out) != 0) why = "status not 0";
            else if (out != (uint64_t)(want && *want == T_BOOL && want[1])) why = "is_valid differs";
        }
        free(state);
        report(file, name, len, why == NULL, why);
    }
}
#endif

/* ---------------------------------------------------------------- Shuffling */

static void run_shuffling(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, slen;
        tv m = tv_get(next_case(f, &name, &len), "mapping");
        const uint8_t *seed = tv_bytes(tv_get(m, "seed"), &slen);
        uint64_t count = tv_u64(tv_get(m, "count"));
        tv mapping = tv_get(m, "mapping");
        if (count > 0) {
            uint64_t osize = 24 + 8 * count;
            uint8_t *out = buffer(osize);
            wr64(out, osize);
            if (CALL(LF(compute_shuffled_permutation), &count, seed, fresh_scratch(), out) != 0) why = "status";
            else if (!guard_ok(out, osize)) why = "wrote past out";
            else if (rd64(out + 16) != count) why = "count";
            else {
                tv e = mapping + 9;
                for (uint64_t k = 0; k < count && !why; k++, e = tv_skip(e))
                    if (rd64(out + 24 + 8 * k) != tv_u64(e)) why = "permutation differs";
            }
            /* compute_shuffled_index of the first and last index */
            uint64_t idx[2] = {0, count - 1};
            for (int k = 0; k < 2 && !why; k++) {
                uint64_t got = 0;
                if (CALL(LF(compute_shuffled_index), &idx[k], &count, seed, fresh_scratch(), &got) != 0)
                    why = "shuffled_index status";
                else if (got != rd64(out + 24 + 8 * idx[k])) why = "shuffled_index differs";
            }
            uint64_t bad = count;
            if (!why && CALL(LF(compute_shuffled_index), &bad, &count, seed, fresh_scratch(), &bad) != 5)
                why = "shuffled_index: index == count not rejected";
            free(out);
        }
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Custody */

/* The 32 little endian bytes of an integer value: tag 1 (u64) or tag 8 (Uint256). */
static void tv_uint256(tv v, uint8_t out[32]) {
    memset(out, 0, 32);
    if (v && *v == T_UINT256) memcpy(out, v + 1, 32);
    else wr64(out, tv_u64(v));
}

/* Whether IndexList out holds the integers of the list want. */
static int list_equals(const uint8_t *out, tv want) {
    if (!want || *want != T_LIST || rd64(out + 16) != rd64(want + 1)) return 0;
    tv e = want + 9;
    for (uint64_t k = 0; k < rd64(want + 1); k++, e = tv_skip(e))
        if (rd64(out + 24 + 8 * k) != tv_u64(e)) return 0;
    return 1;
}

/* networking-get_custody_groups and networking-compute_columns_for_custody_group. */
#if FORK == FORK_FULU
static void run_custody(const char *file, const char *handler, case_file *f) {
    int groups = !strcmp(handler, "get_custody_groups");
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len;
        tv m = tv_get(next_case(f, &name, &len), "meta");
        tv want = tv_get(m, "result");
        uint64_t n = rd64(want + 1), osize = 24 + 8 * n, st;
        uint8_t *out = buffer(osize);
        wr64(out, osize);
        if (groups) {
            uint8_t node_id[32];
            tv_uint256(tv_get(m, "node_id"), node_id);
            uint64_t count = tv_u64(tv_get(m, "custody_group_count"));
            st = CALL(LF(get_custody_groups), node_id, &count, config, out);
            /* One entry less room than the count: BUFFER_TOO_SMALL. */
            if (!st && n > 0) {
                uint8_t *small = buffer(osize - 8);
                wr64(small, osize - 8);
                if (CALL(LF(get_custody_groups), node_id, &count, config, small) != 1) why = "short out accepted";
                free(small);
            }
        } else {
            uint64_t group = tv_u64(tv_get(m, "custody_group"));
            st = CALL(LF(compute_columns_for_custody_group), &group, config, out);
        }
        /* NUMBER_OF_CUSTODY_GROUPS (+ 1 for a count) fails the spec's assert. */
        uint64_t over = rd64(config + 280) + groups, got = 0;
        uint8_t node0[32] = {0};
        uint64_t bad = groups ? CALL(LF(get_custody_groups), node0, &over, config, &got)
                              : CALL(LF(compute_columns_for_custody_group), &over, config, &got);
        if (bad != 42) why = "assert not checked";
        if (st != 0) why = "status";
        else if (!guard_ok(out, osize)) why = "wrote past out";
        else if (rd64(out + 8) != 24) why = "offset";
        else if (!list_equals(out, want)) why = "result differs";
        free(out);
        report(file, name, len, why == NULL, why);
    }
}

#endif

/* ---------------------------------------------------------------- Rewards */

/* Whether the IndexList pair (rewards, penalties) equals the SSZ Deltas in want. */
#define INVALID_ENCODING_STATUS 56 /* LANTERN_INVALID_ENCODING, include/lantern.inc */
static uint64_t field_offset(const char *name, uint64_t i);

/*
 * The items of lantern_node_attestation_rewards of every validator of the state, in windows of
 * `window` validators (a last one of the rest), after lantern_node_reward_totals of mode; NULL with why.
 */
static uint8_t *attestation_rewards_of(const uint8_t *state, uint64_t mode, uint64_t window, uint8_t *totals, const char **why) {
    uint64_t n = rd64(state + field_offset("BeaconState", 11) + 8);
    uint8_t *items = buffer(48 * n + 48);
    memset(totals, FILL, 96 + GUARD);
    if (CALL(LF(node_reward_totals), state, config, (const void *)(uintptr_t)mode, fresh_scratch(), totals) != 0) {
        *why = "lantern_node_reward_totals: status";
    } else if (!guard_ok(totals, 96)) {
        *why = "lantern_node_reward_totals: wrote past out";
    }
    memset(items, FILL, (size_t)(48 * n + 48 + GUARD));
    for (uint64_t first = 0; first < n && !*why; first += window) {
        uint64_t count = n - first < window ? n - first : window;
        uint64_t st = CALL(LF(node_attestation_rewards), state, config, totals, (const void *)(uintptr_t)first,
                           (const void *)(uintptr_t)count, fresh_scratch(), items + 48 * first);
        if (st != 0) {
            static char msg[96];
            snprintf(msg, sizeof msg, "lantern_node_attestation_rewards: status %llu", (unsigned long long)st);
            *why = msg;
        }
    }
    if (!*why && !guard_ok(items, 48 * n)) *why = "lantern_node_attestation_rewards: wrote past out";
    if (!*why) { /* a window past the validators */
        uint8_t one[48 + GUARD];
        if (CALL(LF(node_attestation_rewards), state, config, totals, (const void *)(uintptr_t)n, (const void *)(uintptr_t)1,
                 fresh_scratch(), one) != INVALID_ENCODING_STATUS)
            *why = "lantern_node_attestation_rewards: a window past the validators is not LANTERN_INVALID_ENCODING";
    }
    if (*why) {
        free(items);
        return NULL;
    }
    return items;
}

static int deltas_equal(const uint8_t *rewards, const uint8_t *penalties, tv want) {
    uint64_t wlen;
    const uint8_t *w = tv_bytes(want, &wlen);
    if (wlen < 8) return 0;
    uint64_t o1 = w[0] | (uint64_t)w[1] << 8 | (uint64_t)w[2] << 16 | (uint64_t)w[3] << 24;
    uint64_t o2 = w[4] | (uint64_t)w[5] << 8 | (uint64_t)w[6] << 16 | (uint64_t)w[7] << 24;
    if (o1 != 8 || o2 < o1 || o2 > wlen) return 0;
    if (rd64(rewards + 16) * 8 != o2 - o1 || rd64(penalties + 16) * 8 != wlen - o2) return 0;
    return !memcmp(rewards + 24, w + o1, (size_t)(o2 - o1)) && !memcmp(penalties + 24, w + o2, (size_t)(wlen - o2));
}

#if FORK >= FORK_ALTAIR
#define DELTAS_COUNT 4
#else
#define DELTAS_COUNT 5
#endif
static void run_rewards(const char *file, case_file *f) {
#if FORK >= FORK_ALTAIR
    static const char *const names[4] = {"source_deltas", "target_deltas", "head_deltas", "inactivity_penalty_deltas"};
#else
    static const char *const names[5] = {"source_deltas", "target_deltas", "head_deltas", "inclusion_delay_deltas",
                                         "inactivity_penalty_deltas"};
    static const struct {
        const char *name;
        deltas_fn fn;
    } COMPONENTS[4] = {{STR(LF(get_source_deltas)), LF(get_source_deltas)},
                       {STR(LF(get_target_deltas)), LF(get_target_deltas)},
                       {STR(LF(get_head_deltas)), LF(get_head_deltas)},
                       {STR(LF(get_inclusion_delay_deltas)), LF(get_inclusion_delay_deltas)}};
#endif
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        uint8_t *state = load_state(pre, plen, &size, &why);
        if (state) {
            uint64_t lsize = 24 + 8 * 4096 * 64;
            uint8_t *rw = buffer(lsize), *pn = buffer(lsize);
            for (uint64_t flag = 0; flag < DELTAS_COUNT && !why; flag++) {
                wr64(rw, lsize);
                wr64(pn, lsize);
#if FORK >= FORK_ALTAIR
                uint64_t st = flag < 3 ? CALL(LF(get_flag_index_deltas), state, &flag, fresh_scratch(), rw, pn)
                                       : CALL(LF(get_inactivity_penalty_deltas), state, config, fresh_scratch(), rw, pn);
#else
                uint64_t st = flag < 4 ? checked_call(COMPONENTS[flag].name, (uint64_t)(uintptr_t)COMPONENTS[flag].fn,
                                                      (const void *const[]){state, fresh_scratch(), rw, pn}, 4)
                                       : CALL(LF(get_inactivity_penalty_deltas), state, config, fresh_scratch(), rw, pn);
#endif
                if (st != 0) {
                    static char msg[96];
                    snprintf(msg, sizeof msg, "%s: status %llu", names[flag], (unsigned long long)st);
                    why = msg;
                } else if (!deltas_equal(rw, pn, tv_get(parts, names[flag]))) why = names[flag];
            }
            free(rw);
            free(pn);
            /* lantern_node_attestation_rewards in mode 0: each validator's reward less penalty of each delta (node.md) */
            static const int item_at[5] = {16, 8, 0, 24, 32}; /* source, target, head, inclusion (phase0), inactivity */
            for (uint64_t window = 7; window && !why; window = window == 7 ? 1u << 20 : 0) {
                uint8_t totals[96 + GUARD];
                uint8_t *items = attestation_rewards_of(state, 0, window, totals, &why);
                for (uint64_t flag = 0; items && flag < DELTAS_COUNT && !why; flag++) {
                    if (DELTAS_COUNT == 5 && flag == 3) continue; /* phase0: the attester's part, in node-attrewards */
                    uint64_t wlen;
                    const uint8_t *w = tv_bytes(tv_get(parts, names[flag]), &wlen);
                    uint64_t o2 = w[4] | (uint64_t)w[5] << 8 | (uint64_t)w[6] << 16 | (uint64_t)w[7] << 24, n = (o2 - 8) / 8;
                    for (uint64_t v = 0; v < n && !why; v++) {
                        int64_t want = (int64_t)(rd64(w + 8 + 8 * v) - rd64(w + o2 + 8 * v));
                        if (flag == DELTAS_COUNT - 1) want = -(int64_t)rd64(w + o2 + 8 * v);
                        if ((int64_t)rd64(items + 48 * v + item_at[flag == DELTAS_COUNT - 1 ? 4 : flag]) != want) {
                            static char msg[160];
                            snprintf(msg, sizeof msg, "lantern_node_attestation_rewards, windows of %llu: %s of validator %llu",
                                     (unsigned long long)window, names[flag], (unsigned long long)v);
                            why = msg;
                        }
                    }
                }
                free(items);
            }
            free(state);
        }
        report(file, name, len, why == NULL, why);
    }
}


/* ---------------------------------------------------------------- Fork choice */

/*
 * The fork choice tests: tests/formats/fork_choice/README.md of the spec. The
 * runner plays the node: it keeps store.block_states and store.checkpoint_states
 * (docs/reference/fork-choice.md, Common rules), grows the store and the states
 * when lantern asks for room, and gives the justified checkpoint state when
 * lantern asks for it.
 */

/* include/lantern.inc: Store, BlockNode and status codes. */
#define STORE_TIME_MS 8
#define STORE_GENESIS_TIME_MS 16
#define STORE_JUSTIFIED 24
#define STORE_FINALIZED 64
#define STORE_BOOST_ROOT 184
#define STORE_BLOCKS 264
#define STORE_VALIDATORS 280
#define STORE_CONFIG 296 /* include/lantern.inc: Store_config */
#define NODE_BYTES 224
#define NODE_FINALIZED_EPOCH 216
#define NODE_PARENT 80
#define NODE_BLOCK_HASH 176
#define NODE_PAYLOAD_STATUS 208
enum { PAYLOAD_VALID = 0, PAYLOAD_INVALIDATED = 1, PAYLOAD_NOT_VALIDATED = 2 };
#define NODE_SLOT 64
#define NODE_PARENT 80
#define LANTERN_NEED_JUSTIFIED_STATE 41
#define KZG_SETTINGS_BYTES 1198368

#if FORK >= FORK_DENEB
static uint8_t *kzg_settings;

/* Decode the trusted setup of <preset>-kzg_setup.bin into kzg_settings, once. */
static void load_kzg_settings(const char *dir) {
    if (kzg_settings) return;
    case_file f;
    char name[64];
    snprintf(name, sizeof name, "%s-kzg_setup.bin", PRESET);
    if (!read_file(dir, name, &f)) {
        fprintf(stderr, "%s/%s: missing\n", dir, name);
        exit(2);
    }
    const char *cname;
    uint64_t clen, len[3], size[3];
    tv parts = next_case(&f, &cname, &clen);
    static const char *const keys[3] = {"g1_lagrange", "g1_monomial", "g2_monomial"};
    uint8_t *lists[3];
    for (int k = 0; k < 3; k++) {
        const uint8_t *b = tv_bytes(tv_get(parts, keys[k]), &len[k]);
        lists[k] = serialized(b, len[k], &size[k]);
    }
    kzg_settings = buffer(KZG_SETTINGS_BYTES);
    if (CALL(crypto_kzg_trusted_setup_of_bytes, lists[0], lists[1], lists[2], kzg_settings) != 0) {
        fprintf(stderr, "kzg setup: status not 0\n");
        exit(2);
    }
    for (int k = 0; k < 3; k++) free(lists[k]);
    free(f.data);
}
#endif

/* The mem offset of field i of the container type named name. */
static uint64_t field_offset(const char *name, uint64_t i) {
    const uint8_t *d = type_by_name(name);
    return rd64(field_of(d, rd64(root_node(d) + 16) + i) + 8);
}

/* The value at a PartRef with count 1: a nested value of a container. */
static const uint8_t *nested(const uint8_t *value, uint64_t ref) { return value + rd64(value + ref); }

typedef struct {
    uint8_t root[32];
    uint64_t epoch; /* checkpoint states only */
    uint8_t *state;
    uint64_t size;
} kept_state;

typedef struct {
    uint8_t *store;
    uint64_t size;
    kept_state *blocks, *checkpoints;
    size_t nblocks, ncheckpoints;
    uint8_t *anchor;  /* a valid state to pass where on_block reads none */
    uint64_t anchor_size;
    int compliance;   /* the compliance runner's rules: invalid operations inside a valid block are ignored */
    struct {          /* the payload_status steps: the execution engine's answer for a payload */
        uint8_t block_hash[32], latest_valid_hash[32];
        uint64_t status, has_latest, el; /* el: ENGINE_STATUS_* of the step's string */
    } payloads[64];
    size_t npayloads;
    uint8_t *pow[16];  /* the pow_block steps: PowBlock values */
    size_t npow;
    struct node_shell *shell; /* node mode: the store is the node's, and the node keeps the states */
    /* node-payload: with watch, each engine call counts, and must be the forkchoiceUpdated whose text
       from ',"method":' on is tail; its answer's payloadId is pid (8 bytes), else null */
    int watch;
    uint64_t engine_calls, tail_len, pid_len;
    const uint8_t *tail, *pid;
    /* node-produce: the forkchoiceUpdated's payloadId is pid, and engine_getPayload answers result */
    int produce;
    uint64_t result_len;
    const uint8_t *result;
} fc_node;

#if FORK >= FORK_BELLATRIX
/* The PowBlock of the case with block_hash hash, or NULL (get_pow_block). */
static const uint8_t *find_pow(const fc_node *n, const uint8_t *hash) {
    for (size_t i = 0; i < n->npow; i++)
        if (!memcmp(n->pow[i], hash, 32)) return n->pow[i];
    return NULL;
}
#endif

static uint8_t *copy_of(const uint8_t *b, uint64_t size) {
    uint8_t *c = buffer(size);
    memcpy(c, b, (size_t)size);
    return c;
}

static kept_state *find_kept(kept_state *v, size_t n, const uint8_t *root, uint64_t epoch, int with_epoch) {
    for (size_t i = 0; i < n; i++)
        if (!memcmp(v[i].root, root, 32) && (!with_epoch || v[i].epoch == epoch)) return &v[i];
    return NULL;
}

static void keep(kept_state **v, size_t *n, const uint8_t *root, uint64_t epoch, uint8_t *state, uint64_t size) {
    *v = realloc(*v, (*n + 1) * sizeof **v);
    if (!*v) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    memcpy((*v)[*n].root, root, 32);
    (*v)[*n].epoch = epoch;
    (*v)[*n].state = state;
    (*v)[*n].size = size;
    (*n)++;
}

/* The resize step for the store: copy it with twice the capacity of each part. */
static uint64_t node_capacity(const uint8_t *store);
static void grow_store(fc_node *n, const char **why) {
    uint64_t room[2] = {2 * node_capacity(n->store), 2 * rd64(n->store + STORE_VALIDATORS + 8)}, need = 0;
    if (CALL(lantern_store_size, room, &need) != 0) {
        *why = "lantern_store_size status";
        return;
    }
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(lantern_store_copy, n->store, room, out) != 0) {
        *why = "lantern_store_copy status";
        free(out);
        return;
    }
    if (!guard_ok(out, need)) *why = "lantern_store_copy wrote out of bounds";
    free(n->store);
    n->store = out;
    n->size = need;
}

/* store.checkpoint_states[checkpoint at cp], made by store_target_checkpoint_state when missing. */
static kept_state *checkpoint_state(fc_node *n, const uint8_t *cp, const char **why) {
    uint64_t epoch = rd64(cp);
    kept_state *k = find_kept(n->checkpoints, n->ncheckpoints, cp + 8, epoch, 1);
    if (k) return k;
    kept_state *base = find_kept(n->blocks, n->nblocks, cp + 8, 0, 0);
    if (!base) {
        *why = "no block state for a checkpoint";
        return NULL;
    }
    uint64_t size = base->size, result = 1, st = 1;
    uint8_t *state = copy_of(base->state, size);
    for (uint64_t growth = 2; growth <= 1024; growth *= 2) {
        st = CALL(LF(store_target_checkpoint_state), state, cp, config, fresh_scratch(), &result);
        if (st != 1) break;
        state = regrow(state, &size, growth, why);
    }
    if (st != 0 || result != 0) {
        *why = "store_target_checkpoint_state failed";
        free(state);
        return NULL;
    }
    keep(&n->checkpoints, &n->ncheckpoints, cp + 8, epoch, state, size);
    return &n->checkpoints[n->ncheckpoints - 1];
}

/*
 * Call a fork choice function again while it asks for the justified checkpoint
 * state or for room in the store. Returns its last status.
 */
/*
 * Call a fork choice function again while it asks for the justified checkpoint
 * state or for room. A non-zero status must leave the store, and the buffer
 * extra of extra_size bytes (or NULL), byte for byte unchanged. Returns the
 * last status.
 */
#define FC_RETRY(n, why, expr, on_small, extra, extra_size)                                                    \
    ({                                                                                                         \
        uint64_t st_ = 0;                                                                                      \
        for (int try_ = 0; try_ < 32 && !*(why); try_++) {                                                     \
            uint8_t *snap_ = copy_of((n)->store, (n)->size), *xsnap_ = (extra) ? copy_of((extra), (extra_size)) : NULL; \
            st_ = (expr);                                                                                      \
            if ((st_ == 1 || st_ == LANTERN_NEED_JUSTIFIED_STATE) &&                                           \
                (memcmp(snap_, (n)->store, (size_t)(n)->size) ||                                               \
                 ((extra) && memcmp(xsnap_, (extra), (size_t)(extra_size)))))                                  \
                *(why) = "a non-zero status changed a state";                                                  \
            free(snap_);                                                                                       \
            free(xsnap_);                                                                                      \
            if (*(why)) break;                                                                                 \
            if (st_ == LANTERN_NEED_JUSTIFIED_STATE) {                                                         \
                kept_state *k_ = checkpoint_state((n), (n)->store + STORE_JUSTIFIED, (why));                    \
                if (!k_) break;                                                                                \
                uint64_t s2_;                                                                                  \
                while ((s2_ = CALL(LF(store_justified_checkpoint_state), (n)->store, k_->state)) == 1 &&       \
                       !*(why))                                                                                \
                    grow_store((n), (why));                                                                    \
                if (s2_ != 0) *(why) = "store_justified_checkpoint_state status";                              \
            } else if (st_ == 1) {                                                                             \
                on_small;                                                                                      \
            } else                                                                                             \
                break;                                                                                         \
        }                                                                                                      \
        st_;                                                                                                   \
    })

/* The capacity of the blocks part of the store. */
static uint64_t node_capacity(const uint8_t *store) {
    return (rd64(store + STORE_VALIDATORS) - rd64(store + STORE_BLOCKS)) / NODE_BYTES;
}

static uint64_t node_count(const fc_node *n) { return rd64(n->store + STORE_BLOCKS + 8); }
static const uint8_t *node_at(const fc_node *n, uint64_t i) {
    return n->store + rd64(n->store + STORE_BLOCKS) + NODE_BYTES * i;
}

/* on_attestation as the node runs it: validate, make the target state, then the call. */
static uint64_t fc_attestation(fc_node *n, const uint8_t *att, uint64_t from_block, const char **why) {
    uint64_t st = CALL(LF(validate_on_attestation), n->store, att, &from_block);
    if (st != 0) return st;
    const uint8_t *target = att + field_offset("Attestation", 1) + field_offset("AttestationData", 4);
    kept_state *k = checkpoint_state(n, target, why);
    if (!k) return 0;
    uint64_t result = 0xA5A5A5A5A5A5A5A5u;
    st = FC_RETRY(n, why, CALL(LF(on_attestation), n->store, att, &from_block, k->state, fresh_scratch(), &result),
                  grow_store(n, why), NULL, 0);
    if (st != 0) {
        *why = "on_attestation: status not 0";
        return 0;
    }
    return result;
}

static uint64_t fc_attester_slashing(fc_node *n, const uint8_t *slashing, const char **why) {
    kept_state *k = find_kept(n->blocks, n->nblocks, n->store + STORE_JUSTIFIED + 8, 0, 0);
    if (!k) {
        *why = "no state for the justified root";
        return 0;
    }
    uint64_t result = 0xA5A5A5A5A5A5A5A5u;
    uint64_t st = FC_RETRY(n, why, CALL(LF(on_attester_slashing), n->store, slashing, k->state, fresh_scratch(), &result),
                           grow_store(n, why), NULL, 0);
    if (st != 0) {
        *why = "on_attester_slashing: status not 0";
        return 0;
    }
    return result;
}

#if FORK == FORK_FULU
/* The ColumnSidecars value of the column files named in list names. */
static uint8_t *column_sidecars(tv parts, tv names, uint64_t *size, const char **why) {
    const uint8_t *desc = type_by_name("DataColumnSidecar");
    uint64_t count = rd64(names + 1), total = 24;
    uint8_t **values = xmalloc(sizeof *values * (count ? count : 1));
    uint64_t *sizes = xmalloc(sizeof *sizes * (count ? count : 1));
    tv e = names + 9;
    for (uint64_t i = 0; i < count; i++, e = tv_skip(e)) {
        uint64_t elen;
        char key[128];
        snprintf(key, sizeof key, "%.*s", (int)rd64(e + 1), (const char *)(e + 9));
        const uint8_t *enc = tv_bytes(tv_get(parts, key), &elen);
        values[i] = decode(desc, enc, elen, &sizes[i], why);
        if (!values[i]) return NULL;
        total += (sizes[i] + 7) & ~(uint64_t)7;
    }
    uint8_t *list = buffer(total);
    wr64(list, total);
    wr64(list + 8, 24);
    wr64(list + 16, count);
    uint64_t at = 24;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t sz = (sizes[i] + 7) & ~(uint64_t)7;
        memset(list + at, 0, (size_t)sz);
        memcpy(list + at, values[i], (size_t)sizes[i]);
        wr64(list + at, sz);
        at += sz;
        free(values[i]);
    }
    free(values);
    free(sizes);
    *size = total;
    return list;
}
#elif FORK >= FORK_DENEB
/* An asm-crypto list (size, offset 24, count, then the entries) of count entries of width bytes from bytes. */
static uint8_t *kzg_list(const uint8_t *bytes, uint64_t count, uint64_t width) {
    uint64_t total = 24 + ((count * width + 7) & ~(uint64_t)7);
    uint8_t *list = buffer(total);
    wr64(list, total);
    wr64(list + 8, 24);
    wr64(list + 16, count);
    if (count) memcpy(list + 24, bytes, (size_t)(count * width));
    return list;
}

/* is_data_available of a block: the blobs and proofs of the step against the body's blob_kzg_commitments. */
static uint64_t blobs_available(tv parts, tv step, const uint8_t *body, const char **why) {
    tv bname = tv_get(step, "blobs"), proofs = tv_get(step, "proofs");
    const uint8_t *blob_bytes = NULL;
    uint64_t blen = 0, nproofs = proofs && *proofs == T_LIST ? rd64(proofs + 1) : 0, out = 0;
    if (bname && *bname == T_STRING) {
        char key[128];
        snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
        blob_bytes = tv_bytes(tv_get(parts, key), &blen);
    }
    uint8_t *pbytes = buffer(48 * (nproofs ? nproofs : 1));
    tv e = nproofs ? proofs + 9 : NULL;
    for (uint64_t i = 0; i < nproofs; i++, e = tv_skip(e)) {
        uint64_t plen;
        const uint8_t *p = tv_bytes(e, &plen);
        if (plen == 48) memcpy(pbytes + 48 * i, p, 48);
    }
    uint64_t ref = field_offset("BeaconBlockBody", 11);
    uint8_t *commitments = kzg_list(body + rd64(body + ref), rd64(body + ref + 8), 48);
    uint8_t *blobs = kzg_list(blob_bytes, blen / 131072, 131072);
    uint8_t *plist = kzg_list(pbytes, nproofs, 48);
    if (CALL(LF(is_data_available), commitments, blobs, plist, kzg_settings, fresh_scratch(), &out) != 0)
        *why = "is_data_available: status not 0";
    free(commitments);
    free(blobs);
    free(plist);
    free(pbytes);
    return out;
}
#endif

/* is_data_available of the block of a step whose body is body: the blobs or columns of the step, 1 before deneb. */
static uint64_t step_data_available(tv parts, tv step, const uint8_t *body, const char **why) {
    uint64_t out = 1;
    (void)parts;
    (void)step;
    (void)body;
    (void)why;
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    out = blobs_available(parts, step, body, why);
#endif
#if FORK == FORK_FULU
    tv columns = tv_get(step, "columns");
    if (columns) {
        if (rd64(columns + 1) == 0) out = 0; /* retrieve_column_sidecars raises: not enough data */
        else {
            uint64_t lsize;
            uint8_t *list = column_sidecars(parts, columns, &lsize, why);
            if (!list) return 0;
            if (CALL(LF(is_data_available), list, kzg_settings, config, fresh_scratch(), &out) != 0)
                *why = "is_data_available: status not 0";
            free(list);
        }
    }
#endif
    return out;
}

/* An on_block step, then the block's attestations and attester slashings when it is valid. */
/*
 * A payload_status step: the execution engine's answer for the payload of block_hash from now on.
 * bellatrix optimistic-sync.md: SYNCING and ACCEPTED are NOT_VALIDATED, INVALID and
 * INVALID_BLOCK_HASH INVALIDATED.
 */
static void fc_payload_step(fc_node *n, tv step, const char **why) {
    static const char *const names[5] = {"VALID", "INVALID", "SYNCING", "ACCEPTED", "INVALID_BLOCK_HASH"};
    tv ps = tv_get(step, "payload_status"), st = tv_get(ps, "status"), lvh = tv_get(ps, "latest_valid_hash");
    uint64_t hlen, slen = rd64(st + 1), el = 0;
    const uint8_t *h = tv_bytes(tv_get(step, "block_hash"), &hlen);
    for (uint64_t k = 0; k < 5; k++)
        if (slen == strlen(names[k]) && !memcmp(st + 9, names[k], (size_t)slen)) el = k + 1;
    if (n->npayloads == 64 || hlen != 32 || !el) {
        *why = "payload_status step";
        return;
    }
    memcpy(n->payloads[n->npayloads].block_hash, h, 32);
    n->payloads[n->npayloads].el = el;
    n->payloads[n->npayloads].status = el == 1 ? PAYLOAD_VALID : el == 3 || el == 4 ? PAYLOAD_NOT_VALIDATED : PAYLOAD_INVALIDATED;
    n->payloads[n->npayloads].has_latest = lvh && *lvh == T_BYTES;
    if (n->payloads[n->npayloads].has_latest) memcpy(n->payloads[n->npayloads].latest_valid_hash, lvh + 9, 32);
    n->npayloads++;
}

static void header_check(const uint8_t *enc, uint64_t len, const char **why);
static void fc_block(fc_node *n, tv parts, tv step, const char **why) {
    char key[128];
    uint64_t blen, vsize;
    tv bname = tv_get(step, "block");
    snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
    tv v = tv_get(step, "valid");
    int valid = !v || (*v == T_BOOL && v[1]);
    const uint8_t *benc = tv_bytes(tv_get(parts, key), &blen);
    header_check(benc, blen, why);
    if (*why) return;
    uint8_t *signed_block = decode(type_by_name("SignedBeaconBlock"), benc, blen, &vsize, why);
    if (!signed_block) return;
    const uint8_t *block = nested(signed_block, field_offset("SignedBeaconBlock", 0));
    const uint8_t *parent_root = block + field_offset("BeaconBlock", 2);

    /* BlockOptions: the engine's answer for the payload (optimistic sync tests), VALID when the case gives none. */
    const uint8_t *body0 = nested(block, field_offset("BeaconBlock", 4));
    uint64_t options[5] = {PAYLOAD_VALID, 1, 0, 0, 0}; /* BlockOptions */
#if FORK >= FORK_BELLATRIX
    const uint8_t *payload = nested(body0, field_offset("BeaconBlockBody", 9));
    const uint8_t *hash = payload + field_offset("ExecutionPayload", 12);
    /* get_pow_block: the PowBlocks of the case's pow_block steps, by hash. */
    const uint8_t *pow = find_pow(n, payload + field_offset("ExecutionPayload", 0));
    options[2] = (uint64_t)(uintptr_t)pow;
    options[3] = pow ? (uint64_t)(uintptr_t)find_pow(n, pow + 32) : 0;
#else
    static const uint8_t no_hash[32];
    const uint8_t *hash = no_hash;
#endif
    for (size_t k = 0; k < n->npayloads; k++) {
        if (memcmp(n->payloads[k].block_hash, hash, 32)) continue;
        options[0] = n->payloads[k].status;
        /* INVALID with latestValidHash: the harness invalidates the chain down to that hash. */
        kept_state *p = n->payloads[k].status == PAYLOAD_INVALIDATED && n->payloads[k].has_latest
                            ? find_kept(n->blocks, n->nblocks, parent_root, 0, 0) : NULL;
        static const uint8_t zero[32];
        for (uint64_t i = 0; p && i < node_count(n); i++) {
            if (memcmp(node_at(n, i), parent_root, 32)) continue;
            uint64_t node = i, result = 1;
            while (node != UINT64_MAX && memcmp(node_at(n, node) + NODE_BLOCK_HASH, n->payloads[k].latest_valid_hash, 32) &&
                   memcmp(node_at(n, node) + NODE_BLOCK_HASH, zero, 32)) {
                uint64_t status = PAYLOAD_INVALIDATED;
                if (CALL(lantern_store_payload_status, n->store, &node, &status, &result) != 0 || result != 0)
                    *why = "store_payload_status";
                node = rd64(node_at(n, node) + NODE_PARENT);
            }
            break;
        }
    }
    options[1] = step_data_available(parts, step, body0, why);

    kept_state *parent = find_kept(n->blocks, n->nblocks, parent_root, 0, 0);
    uint64_t size = parent ? parent->size : n->anchor_size, result = 0xA5A5A5A5A5A5A5A5u, st = 0;
    uint8_t *state = copy_of(parent ? parent->state : n->anchor, size);
    uint64_t before = node_count(n), growth = 2;
    /* BUFFER_TOO_SMALL: the store when it is full, else the state's lists. */
    st = FC_RETRY(n, why, CALL(LF(on_block), n->store, signed_block, state, options, fresh_scratch(), &result),
                  if (node_count(n) == node_capacity(n->store)) grow_store(n, why);
                  else { state = regrow(state, &size, growth, why); growth *= 2; }, state, size);
    if (*why) {
    } else if (st != 0) {
        static char msg[64];
        snprintf(msg, sizeof msg, "on_block: status %llu", (unsigned long long)st);
        *why = msg;
    } else if (valid && result != 0) {
        static char msg[64];
        snprintf(msg, sizeof msg, "on_block: result %llu, expected valid", (unsigned long long)result);
        *why = msg;
    } else if (!valid && result == 0) *why = "on_block: expected an invalid block";
    if (!*why && result == 0 && node_count(n) == before + 1) {
        keep(&n->blocks, &n->nblocks, node_at(n, before), 0, state, size);
        state = NULL;
    }
    free(state);
    if (!*why && valid) {
        const uint8_t *body = nested(block, field_offset("BeaconBlock", 4));
        uint64_t ref = field_offset("BeaconBlockBody", 5);
        const uint8_t *a = body + rd64(body + ref);
        for (uint64_t i = 0, c = rd64(body + ref + 8); i < c && !*why; i++, a += rd64(a))
            if (fc_attestation(n, a, 1, why) != 0 && !*why && !n->compliance) *why = "a block attestation is not valid";
        ref = field_offset("BeaconBlockBody", 4);
        a = body + rd64(body + ref);
        for (uint64_t i = 0, c = rd64(body + ref + 8); i < c && !*why; i++, a += rd64(a))
            if (fc_attester_slashing(n, a, why) != 0 && !*why && !n->compliance)
                *why = "a block attester slashing is not valid";
    }
    free(signed_block);
}

static uint64_t shell_head(fc_node *n, const char **why);
static const uint8_t *shell_state_of(fc_node *n, const uint8_t *root);

/* The head node, through the retry rule. Node mode: the node's head. */
static uint64_t fc_head(fc_node *n, const char **why) {
    if (n->shell) return shell_head(n, why);
    uint64_t head = 0;
    uint64_t st = FC_RETRY(n, why, CALL(LF(get_head), n->store, fresh_scratch(), &head), break, NULL, 0);
    if (!*why && st != 0) *why = "get_head: status not 0";
    return head;
}

static int hex_root_equals(tv v, const uint8_t *root) {
    uint64_t len;
    const uint8_t *b = tv_bytes(v, &len);
    return len == 32 && !memcmp(b, root, 32);
}

/*
 * viable_for_head_roots_and_weights: the leaves of get_filtered_node_tree below
 * the justified node, or the justified node when the tree is empty, each with
 * get_weight. The check is a set of {root, weight}.
 */
static void fc_viable(fc_node *n, tv want, const char **why) {
    uint64_t count = node_count(n), lsize = 24 + 8 * count, nleaves = 0;
    uint8_t *tree = buffer(lsize), *in = xmalloc(count), *parent_of = xmalloc(count);
    uint64_t *leaves = xmalloc(sizeof *leaves * (count ? count : 1));
    wr64(tree, lsize);
    memset(in, 0, count);
    memset(parent_of, 0, count);
    if (CALL(LF(get_filtered_node_tree), n->store, fresh_scratch(), tree) != 0) *why = "get_filtered_node_tree status";
    for (uint64_t k = 0; !*why && k < rd64(tree + 16); k++) in[rd64(tree + 24 + 8 * k)] = 1;
    for (uint64_t i = 0; !*why && i < count; i++) {
        uint64_t p = rd64(node_at(n, i) + NODE_PARENT);
        if (in[i] && p < count && in[p]) parent_of[p] = 1;
    }
    for (uint64_t i = 0; !*why && i < count; i++)
        if (in[i] && !parent_of[i]) leaves[nleaves++] = i;
    if (!*why && rd64(tree + 16) == 0)
        for (uint64_t i = 0; i < count; i++)
            if (!memcmp(node_at(n, i), n->store + STORE_JUSTIFIED + 8, 32)) leaves[nleaves++] = i;
    if (!*why && (*want != T_LIST || rd64(want + 1) != nleaves)) *why = "check viable_for_head_roots_and_weights: count";
    for (uint64_t k = 0; !*why && k < nleaves; k++) {
        uint64_t node = leaves[k], weight = 0, found = 0;
        uint64_t st = FC_RETRY(n, why, CALL(LF(get_weight), n->store, &node, &weight), break, NULL, 0);
        if (*why) break;
        if (st != 0) {
            *why = "get_weight: status not 0";
            break;
        }
        tv e = want + 9;
        for (uint64_t j = 0; j < nleaves; j++, e = tv_skip(e))
            if (hex_root_equals(tv_get(e, "root"), node_at(n, node)) && tv_u64(tv_get(e, "weight")) == weight) found = 1;
        if (!found) *why = "check viable_for_head_roots_and_weights";
    }
    if (!*why) { /* lantern_node_weights: lantern_get_weight of each node, so the leaves' weights of the check */
        uint64_t wsize = 8 * (count ? count : 1);
        uint8_t *ws = buffer(wsize);
        uint64_t st = FC_RETRY(n, why, CALL(LF(node_weights), n->store, fresh_scratch(), ws), break, NULL, 0);
        if (!*why && st != 0) *why = "lantern_node_weights: status not 0";
        if (!*why && !guard_ok(ws, wsize)) *why = "lantern_node_weights wrote out of bounds";
        for (uint64_t i = 0; !*why && i < count; i++) {
            uint64_t node = i, weight = 0;
            if (CALL(LF(get_weight), n->store, &node, &weight) != 0) *why = "get_weight: status not 0";
            else if (rd64(ws + 8 * i) != weight) *why = "lantern_node_weights: not lantern_get_weight of a node";
        }
        free(ws);
    }
    free(tree);
    free(in);
    free(parent_of);
    free(leaves);
}

static void fc_checks(fc_node *n, tv checks, const char **why) {
    uint64_t count = rd64(checks + 1);
    tv p = checks + 9;
    for (uint64_t i = 0; i < count && !*why; i++) {
        uint64_t klen = rd64(p);
        char key[64];
        snprintf(key, sizeof key, "%.*s", (int)klen, (const char *)(p + 8));
        tv v = p + 8 + klen;
        p = tv_skip(v);
        if (!strcmp(key, "head")) {
            uint64_t head = fc_head(n, why);
            if (*why) break;
            const uint8_t *node = node_at(n, head);
            if (rd64(node + NODE_SLOT) != tv_u64(tv_get(v, "slot")) || !hex_root_equals(tv_get(v, "root"), node))
                *why = "check head";
            /* The head is in get_filtered_node_tree, or is the justified node when the tree is empty. */
            uint64_t lsize = 24 + 8 * node_count(n);
            uint8_t *tree = buffer(lsize);
            wr64(tree, lsize);
            if (!*why && CALL(LF(get_filtered_node_tree), n->store, fresh_scratch(), tree) != 0)
                *why = "get_filtered_node_tree: status not 0";
            else if (!*why) {
                uint64_t count = rd64(tree + 16), found = 0;
                for (uint64_t k = 0; k < count; k++) {
                    uint64_t e = rd64(tree + 24 + 8 * k);
                    if (e >= node_count(n) || (k && e <= rd64(tree + 16 + 8 * k))) *why = "filtered tree: bad entry";
                    if (e == head) found = 1;
                }
                if (!*why && !found && (count || memcmp(node, n->store + STORE_JUSTIFIED + 8, 32)))
                    *why = "filtered tree: head missing";
                if (!*why && !guard_ok(tree, lsize)) *why = "filtered tree: wrote out of bounds";
            }
            free(tree);
        } else if (!strcmp(key, "time")) {
            if (rd64(n->store + STORE_TIME_MS) / 1000 != tv_u64(v)) *why = "check time";
        } else if (!strcmp(key, "genesis_time")) {
            if (rd64(n->store + STORE_GENESIS_TIME_MS) / 1000 != tv_u64(v)) *why = "check genesis_time";
        } else if (!strcmp(key, "justified_checkpoint") || !strcmp(key, "finalized_checkpoint")) {
            const uint8_t *cp = n->store + (key[0] == 'j' ? STORE_JUSTIFIED : STORE_FINALIZED);
            if (rd64(cp) != tv_u64(tv_get(v, "epoch")) || !hex_root_equals(tv_get(v, "root"), cp + 8))
                *why = key[0] == 'j' ? "check justified_checkpoint" : "check finalized_checkpoint";
        } else if (!strcmp(key, "proposer_boost_root")) {
            if (!hex_root_equals(v, n->store + STORE_BOOST_ROOT)) *why = "check proposer_boost_root";
        } else if (!strcmp(key, "viable_for_head_roots_and_weights")) {
            fc_viable(n, v, why);
        } else if (!strcmp(key, "get_proposer_head")) {
            uint64_t head = fc_head(n, why), slot = 0, out = 0;
            if (*why) break;
            if (CALL(LF(get_current_slot), n->store, &slot) != 0) {
                *why = "get_current_slot status";
                break;
            }
            kept_state *k = find_kept(n->blocks, n->nblocks, node_at(n, head), 0, 0);
            const uint8_t *head_state = n->shell ? shell_state_of(n, node_at(n, head)) : k ? k->state : NULL;
            if (!head_state) {
                *why = "no state for the head";
                break;
            }
            uint64_t st = FC_RETRY(n, why, CALL(LF(get_proposer_head), n->store, &head, &slot, head_state, fresh_scratch(), &out),
                                   break, NULL, 0);
            if (*why) break;
            if (st != 0) *why = "get_proposer_head: status not 0";
            else if (!hex_root_equals(v, node_at(n, out))) *why = "check get_proposer_head";
        } else {
            static char msg[96];
            snprintf(msg, sizeof msg, "unknown check %s", key);
            *why = msg;
        }
    }
}

static void root_of(const char *type, const uint8_t *value, uint8_t root[32], const char **why);

/*
 * The anchor state, the anchor block and the store of a case. Returns the anchor block, or NULL with a reason.
 */
static const uint8_t *bf_state, *bf_block; /* with them, the anchor of the next node: a state value and a BeaconBlock value */
static int drop_room, drop_ran; /* set: the next node has a Db of three segments and NODE_FLAG_DB; the drop check ran */
static uint64_t bf_state_size;
static uint8_t *fc_setup(fc_node *n, tv parts, const char **why) {
    uint64_t slen, blen, vsize;
    uint8_t *anchor_block;
    if (bf_state) {
        n->anchor = copy_of(bf_state, bf_state_size);
        n->anchor_size = bf_state_size;
        anchor_block = copy_of(bf_block, rd64(bf_block));
    } else {
        const uint8_t *enc = tv_bytes(tv_get(parts, "anchor_state"), &slen);
        n->anchor = load_state(enc, slen, &n->anchor_size, why);
        if (!n->anchor) return NULL;
        anchor_block = decode(type_by_name("BeaconBlock"), tv_bytes(tv_get(parts, "anchor_block"), &blen), blen, &vsize, why);
        if (!anchor_block) return NULL;
    }
    /* Small capacities, so that the store grows through lantern_store_copy. */
    uint64_t room[2] = {2, 1}, need = 0;
    CALL(lantern_store_size, room, &need);
    n->store = buffer(need);
    n->size = need;
    wr64(n->store, need);
    uint64_t st;
    while ((st = CALL(LF(get_forkchoice_store), n->anchor, anchor_block, config, room, fresh_scratch(), n->store)) == 1 &&
           room[1] < (1u << 24)) {
        room[1] *= 2;
        CALL(lantern_store_size, room, &need);
        free(n->store);
        n->store = buffer(need);
        n->size = need;
        wr64(n->store, need);
    }
    if (st != 0) *why = "get_forkchoice_store: status not 0";
    else if (!guard_ok(n->store, n->size)) *why = "get_forkchoice_store wrote out of bounds";
    if (*why) {
        free(anchor_block);
        return NULL;
    }
    return anchor_block;
}

/* ---------------------------------------------------------------- Node mode */

/*
 * The fork_choice files a second time, through the node core (docs/reference/node.md). The runner
 * plays the shell: it maps each BufferId to a buffer, does the actions of lantern_node_step in
 * order, runs each WORK action with lantern_node_run when it comes to it, and passes the events
 * that run writes to the next step, until a step gives no work. It sends a valid block's
 * attestations and attester slashings as events, as the direct runner calls them. The checks read
 * the store and the node's head. Cases with payload_status steps are left to the direct runner.
 */

/* include/lantern.inc: Node, NodeBlock, the events, the actions and the work kinds. */
#define NODE_HEAD_ROOT 24
#define NODE_BLOCKS 64
#define NODE_BLOCK_BYTES 144
#define NB_STATE_ID 80
#define NB_STATUS 88
enum { NB_WAITING = 1, NB_IMPORTING, NB_IMPORTED, NB_INVALID, NB_HASHING, NB_BLOBS, NB_PAYLOAD, NB_EXECUTING };
#define NODE_FLAG_ENGINE 16
#define NODE_TIME_MS 16
#define NODE_BLOBS 256 /* Node_blobs: NodeBlob entries of 72 bytes: block_root, index, slot, data_id, status, length */
#define NODE_BLOB_BYTES 72
#define NBLOB_VALID 2
enum { EV_TICK = 1, EV_BLOCK, EV_ATTESTATION, EV_ATTESTER_SLASHING, EV_POW_BLOCK, EV_PAYLOAD_STATUS, EV_WORK_DONE, EV_P2P, EV_ENGINE, EV_ENR, EV_API,
       EV_API_IDENTITY, EV_API_SENT, EV_API_CLOSED, EV_BUILDER };
enum { ACT_BYTES_PUT = 1, ACT_STATE_COPY, ACT_STATE_FREE, ACT_BYTES_FREE, ACT_WORK, ACT_P2P_LIST, ACT_ENGINE, ACT_DISCV5, ACT_DB_APPEND, ACT_DB_STATE, ACT_DB_DROP,
       ACT_API_SEND, ACT_API_CLOSE, ACT_STATE_BYTES, ACT_BYTES_NEW, ACT_BUILDER };
#define NODE_FLAG_DISCV5 64
#define NODE_FLAG_DB 128
#define NODE_FLAG_FEW_STATES 256
#define NODE_FLAG_SUPERNODE 1024
static int force_supernode; /* set: the next node has NODE_FLAG_SUPERNODE */
#define NODE_FLAGS 112       /* include/lantern.inc: Node_flags */
#define NODE_FLAG_SYNCING 8 /* the view's is_syncing: the api cases set it for their requests marked syncing */
#define NODE_DB 464 /* Node_db: the PartRef of the node's Db */
#define NODE_DB_REF (1ull << 63)
#define DB_SLOT_BYTES 96 /* DbSlot__mem */
#define NODE_DB_SIDECARS (1ull << 62)
#define NODE_DB_STATES (1ull << 61)
#define NODE_ARCHIVE (728 + CONFIG_SIZE + 936 + 1624 + 8 * (4 + 64)) /* Node_archive_slots, then archive_slot, archive_first, archive_segment, archive_end */
#define WORK_ARCHIVE_LOAD 42
#define WORK_RECONSTRUCT 44
#define ACT_BYTES_JOIN 18
#define ACT_DB_ARCHIVE 17
#define EV_DB_ARCHIVE 16
#define NODE_ANCHOR_SIZE 312
#define NODE_DB_SEGMENTS 256 /* the segments one node's runner keeps */
enum { WORK_IMPORT_BLOCK = 1, WORK_JUSTIFIED_STATE, WORK_TARGET_STATE, WORK_ATTESTATION, WORK_ATTESTER_SLASHING, WORK_SERVE, WORK_GOSSIP,
       WORK_SYNC_BLOCK, WORK_BLOB, WORK_NEW_PAYLOAD, WORK_FORKCHOICE, WORK_SLOTS, WORK_UPGRADE, WORK_REPLAY, WORK_BACKFILL,
       WORK_BLOCK_ATTESTATION, WORK_BLOCK_SLASHING, WORK_GOSSIP_VOTE, WORK_API_ENCODE, WORK_API_CHUNK, WORK_API_LOOKUP, WORK_API_EVENT,
       WORK_API_SUBMIT, WORK_POOL_CHECK, WORK_PREPARE_PAYLOAD, WORK_PRODUCE_CHECK, WORK_GET_PAYLOAD, WORK_PRODUCE_FOLD,
       WORK_PRODUCE_BLOCK, WORK_PUBLISH_DECODE, WORK_PUBLISH_SIDECARS, WORK_PUBLISH_CHECK, WORK_PUBLISH_SIDECAR,
       WORK_LC_BLOCK, WORK_LC_HEAD, WORK_LC_SERVE, WORK_LC_GOSSIP, WORK_LC_PUBLISH, WORK_PRODUCE_BID };
#define EV_API_BYTES (128 + 616) /* NodeEvent_api_bytes: the chunk's ByteList in the WORK_DONE of an API_CHUNK */
#define NODE_API_CHUNK 65536
#define NODE_API_PART (728 + CONFIG_SIZE + 936) /* Node_api: the PartRef of the NodeApi entries */
#define NODE_POOL_PART (NODE_API_PART + 72)    /* Node_pool: the PartRef of the NodePool entries */
#define NODE_POOL_MEM 64

/* The pool entries in use (topic not 0) of the node: each keeps a buffer. */
static uint64_t node_pool_held(const uint8_t *node) {
    uint64_t off = rd64(node + NODE_POOL_PART), count = rd64(node + NODE_POOL_PART + 8), held = 0;
    for (uint64_t i = 0; i < count; i++) held += rd64(node + off + NODE_POOL_MEM * i) != 0;
    return held;
}
/* The runner buffers the node holds: each NodeBlock's bytes and post-state, each NodeBlob's bytes, each pool entry's. */
static uint64_t node_held_ids(const uint8_t *node) {
    uint64_t held = node_pool_held(node);
    for (int part = 0; part < 2; part++) {
        uint64_t at = part ? NODE_BLOBS : NODE_BLOCKS, mem = part ? NODE_BLOB_BYTES : NODE_BLOCK_BYTES;
        uint64_t off = rd64(node + at), count = rd64(node + at + 8);
        for (uint64_t i = 0; i < count; i++) {
            const uint8_t *e = node + off + mem * i;
            held += part ? rd64(e + 48) != 0 : (rd64(e + 72) != 0) + (rd64(e + NB_STATE_ID) != 0); /* data_id; data_id, state_id */
        }
    }
    return held;
}
static unsigned long node_replays; /* the REPLAY works the nodes ran: post-states they rebuilt */
#define EV_RESULT 72
#define EV_WORK_DONE_SIZE 128
#define LANTERN_NEED_TARGET_STATE 55
#define SHELL_RESULTS 1024
#define ENGINE_HOST "localhost:8551" /* the node's execution engine: the runner */
#define BUILDER_HOST "localhost:18550" /* the node's builder, with NODE_FLAG_BUILDER: the runner */
#define NODE_FLAG_BUILDER 2048
#define NODE_FLAG_ETH1 4096
static int force_eth1; /* set: the next node has NODE_FLAG_ENGINE and NODE_FLAG_ETH1, with room for the eth1 follower */
static int force_builder; /* set: the next node has NODE_FLAG_BUILDER */

typedef struct {
    uint64_t id, size;
    uint8_t *b;
} shell_buf;

#define NODE_ROOM_FIELDS 19 /* NodeRoom: blocks, checkpoints, pow_blocks, peers, streams, request_bytes, p2p_out, messages, blobs, engine_bytes, db_slots, db_roots, api_streams, pool, proposers, eth1_blocks, eth1_deposits, responses, response_bytes */

struct p2p_net;

struct node_shell {
    struct p2p_net *net; /* node-p2p: the network of the node's libp2p state */
    uint8_t *seen;       /* the Seen of the node's gossip */
    uint64_t seen_size, seen_room[4];
    uint8_t *node, *actions;
    uint64_t node_size, room[NODE_ROOM_FIELDS], actions_size;
    shell_buf *bufs;
    size_t nbufs;
    uint8_t *pending; /* the events of the next step */
    uint64_t pending_len, pending_cap;
    uint64_t results[2][SHELL_RESULTS]; /* the last results of the ATTESTATION and ATTESTER_SLASHING works */
    size_t nresults[2];
    struct {             /* the node's NODE_ACT_DISCV5: the last value of each record key it set, and its lookups */
        char key[17];
        uint8_t value[64];
        uint64_t len;
    } entries[8];
    size_t nentries, lookups;
    struct { /* NODE_FLAG_DB: the segment files of the node's Db, in memory */
        uint64_t sidecars, number, len, cap;
        uint8_t *b;
    } segs[NODE_DB_SEGMENTS];
    size_t nsegs;
    uint8_t anchor[NODE_ANCHOR_SIZE], ncfg[CONFIG_SIZE]; /* the node's NodeAnchor and config, for a new node of the same start */
    uint8_t *bld;                           /* with NODE_FLAG_BUILDER: the requests of the node's builder calls, as they came */
    uint64_t bld_len, bld_cap, bld_calls;
    tv bids;                                /* node-produce: the case's answers to the getHeader calls, or NULL */
    uint64_t nbids, bid_calls;              /* their count; the getHeader calls so far */
    tv submits;                             /* node-publish: the case's answers to the blinded_blocks calls, or NULL */
    uint64_t nsubmits, submit_calls;
    const uint8_t *eth1_blocks, *eth1_deposits, *eth1_contract; /* node-eth1: the chain (number, timestamp, hash), its deposits */
    uint64_t eth1_nblocks, eth1_ndeposits, eth1_calls;
    uint64_t flags, db_states;              /* its flags; the NODE_ACT_DB_STATE actions */
    uint64_t drops[16];                     /* the NODE_ACT_DB_DROP actions: bit 63 for sidecars, the segment */
    size_t ndrops;
    struct { /* the Beacon API: the bytes of the connection's NODE_ACT_API_SEND actions, in order */
        uint64_t conn, len, cap, sends, lasts, closes, late; /* late: a send or a close after the close, or a send after the last */
        uint8_t *b;
        uint64_t room;     /* the bytes after the chunk's ByteList header in the event of an API_CHUNK; 0: NODE_API_CHUNK */
        int cut, gone;     /* cut: the connection closes after the first chunk; gone: it closed */
        uint64_t ids[16];  /* the ids of the NODE_ACT_STATE_BYTES actions */
        size_t nids;
    } api;
    struct { /* the event streams of a node-events case: the bytes of each connection's sends */
        uint64_t conn, len, cap, seen, sends, lasts, closes, late, total; /* seen: the bytes checked; total: sent with no SENT */
        uint8_t *b;
        int nosent, gone, closed; /* nosent: no NODE_EV_API_SENT; closed: the node closed it, as it must */
    } ev[3];
    int nev;
};

/* The records the nodes archived, and the works that served one from the Db: printed as a NOTE. */
static const struct node_shell *qsort_seg;
static int seg_order(const void *a, const void *b) {
    size_t x = *(const size_t *)a, y = *(const size_t *)b;
    uint64_t kx = qsort_seg->segs[x].sidecars << 32 | qsort_seg->segs[x].number, ky = qsort_seg->segs[y].sidecars << 32 | qsort_seg->segs[y].number;
    return kx < ky ? -1 : kx > ky;
}
static unsigned long node_db_records, node_db_serves, node_db_states;

/* The segment of the node's Db, made empty when it is new and make is set; NULL when it is not there. */
static uint8_t **shell_segment(struct node_shell *s, uint64_t sidecars, uint64_t number, uint64_t **len, int make) {
    size_t k = 0;
    while (k < s->nsegs && !(s->segs[k].sidecars == sidecars && s->segs[k].number == number)) k++;
    if (k == s->nsegs) {
        if (!make || k == NODE_DB_SEGMENTS) return NULL;
        memset(&s->segs[k], 0, sizeof s->segs[k]);
        s->segs[k].sidecars = sidecars;
        s->segs[k].number = number;
        s->nsegs++;
    }
    *len = &s->segs[k].len;
    return &s->segs[k].b;
}

/* NODE_ACT_DB_APPEND: the record (its 80-byte header, the bytes of the id, zero bytes to a multiple of 8) at the offset, the segment's end. */
static shell_buf *shell_find(struct node_shell *s, uint64_t id);
static void shell_db_append(struct node_shell *s, const uint8_t *act, const char **why) {
    shell_buf *b = shell_find(s, rd64(act + 16));
    uint64_t *len, sidecars = rd64(act + 32), number = rd64(act + 24), offset = rd64(act + 40), length = rd64(act + 48 + 72);
    uint8_t **seg = shell_segment(s, sidecars, number, &len, 1);
    if (!b) *why = "DB_APPEND names no buffer";
    else if (!seg) *why = "DB_APPEND: too many segments for the runner";
    else if (sidecars > 1 || offset != *len) *why = "DB_APPEND: the offset is not the segment's end";
    else if (rd64(b->b + 16) != length) *why = "DB_APPEND: the record's length is not the bytes'";
    else if (number != rd64(act + 48 + 8) >> 13) *why = "DB_APPEND: the record's slot is not of the segment";
    else if (rd64(act + 48 + 56) != 24 + length || rd64(act + 48 + 64) != 24) *why = "DB_APPEND: the record's ByteList header is not of its bytes";
    else {
        uint64_t size = 80 + ((length + 7) & ~7ull), k;
        for (k = 0; k < s->nsegs && &s->segs[k].b != seg; k++) {}
        if (*len + size > s->segs[k].cap) {
            s->segs[k].cap = 2 * (*len + size);
            *seg = realloc(*seg, (size_t)s->segs[k].cap);
            if (!*seg) {
                fprintf(stderr, "out of memory\n");
                exit(2);
            }
        }
        memset(*seg + *len, 0, (size_t)size);
        memcpy(*seg + *len, act + 48, 80);
        memcpy(*seg + *len + 80, b->b + rd64(b->b + 8), (size_t)length);
        *len += size;
        node_db_records++;
    }
}

/* The ByteList in place of the SSZ bytes of the Db record of a NODE_DB_REF, in its segment: the record's header at 56; NULL when there is none. */
static uint8_t *shell_db_view(struct node_shell *s, uint64_t ref) {
    uint64_t *len, offset = ref & ((1ull << 44) - 1);
    if ((ref & NODE_DB_SIDECARS) && (ref & NODE_DB_STATES)) return NULL;
    uint8_t **seg = shell_segment(s, (ref & NODE_DB_SIDECARS) ? 1 : (ref & NODE_DB_STATES) ? 2 : 0, (ref >> 44) & 0x1ffff, &len, 0);
    if (!seg || offset + 80 > *len || rd64(*seg + offset + 72) > *len - offset - 80) return NULL;
    uint8_t *h = *seg + offset + 56;
    if (rd64(h) != 24 + rd64(h + 16) || rd64(h + 8) != 24) return NULL;
    return h;
}

/* lantern_node_state_bytes of the fork of the state's slot: the runner's, or the fork before. */
static uint64_t shell_state_bytes(const struct node_shell *s, const uint8_t *state, uint8_t *out, uint64_t *size) {
#if FORK > FORK_PHASE0
    uint64_t f = FORK_FULU, per_epoch = strcmp(PRESET, "minimal") ? 32 : 8, slot = rd64(state + 48);
    while (f > 0 && slot / per_epoch < rd64(s->ncfg + 16 * f)) f--;
    if (f < FORK) return CALL(LP(node_state_bytes), state, fresh_scratch(), out, size);
#endif
    (void)s;
    return CALL(LF(node_state_bytes), state, fresh_scratch(), out, size);
}

static uint8_t *shell_append(struct node_shell *s, uint64_t size);
static unsigned long node_db_archives, node_db_loads;
static unsigned long node_recons; /* the reconstructions of valid result */

/*
 * NODE_ACT_DB_ARCHIVE: at its state segment's end, of a state of the record's slot, a DB_STATE at
 * offset 0 or a DB_STATE_DIFF above it. The record as the shell writes it (the state's bytes, or
 * their diff against the record at offset 0), then a NODE_EV_DB_ARCHIVE of it for the next step.
 */
static void shell_db_archive(struct node_shell *s, const uint8_t *act, const char **why) {
    shell_buf *st = shell_find(s, rd64(act + 16));
    uint64_t *len, number = rd64(act + 24), offset = rd64(act + 32), kind = rd64(act + 40), slot = rd64(act + 48);
    uint8_t **seg = shell_segment(s, 2, number, &len, 1), *bytes = NULL, *diff = NULL, small[24] = {0};
    if (!st) *why = "DB_ARCHIVE names no buffer";
    else if (!seg) *why = "DB_ARCHIVE: too many segments for the runner";
    else if (offset != *len) *why = "DB_ARCHIVE: the offset is not the state segment's end";
    else if (kind != (offset ? 5u : 4u)) *why = "DB_ARCHIVE: not a full state at offset 0 and a diff above it";
    else if (number != slot >> 13) *why = "DB_ARCHIVE: the record's slot is not of the segment";
    else if (rd64(st->b + 48) != slot) *why = "DB_ARCHIVE: the state is not of the record's slot"; /* NODE_STATE_SLOT 48 */
    else if (rd64(act + 40 + 16) || rd64(act + 40 + 56) || rd64(act + 40 + 64) || rd64(act + 40 + 72))
        *why = "DB_ARCHIVE: the record's index, bytes and length are not 0";
    uint64_t need = 0, size = 0;
    wr64(small, 24);
    if (!*why && (shell_state_bytes(s, st->b, small, &need) != 1 || need <= 24))
        *why = "lantern_node_state_bytes: a short buffer is not LANTERN_BUFFER_TOO_SMALL with the size";
    if (!*why) {
        bytes = buffer(need);
        wr64(bytes, need);
        if (shell_state_bytes(s, st->b, bytes, &size) != 0 || size != need) *why = "lantern_node_state_bytes: status";
    }
    uint8_t *rec = bytes;
    if (!*why && offset) {
        uint8_t *full = shell_db_view(s, NODE_DB_REF | NODE_DB_STATES | number << 44);
        uint64_t dneed = 0;
        if (!full) *why = "DB_ARCHIVE: no full state at offset 0 of the segment";
        else if (CALL(lantern_db_state_diff, full, bytes, small, &dneed) != 1 || dneed < 32)
            *why = "lantern_db_state_diff: a short buffer is not LANTERN_BUFFER_TOO_SMALL with the size";
        else {
            diff = buffer(dneed);
            wr64(diff, dneed);
            if (CALL(lantern_db_state_diff, full, bytes, diff, &size) != 0 || size != dneed) *why = "lantern_db_state_diff: status";
            else if (!guard_ok(diff, dneed)) *why = "lantern_db_state_diff wrote out of bounds";
            rec = diff;
        }
    }
    if (!*why) {
        uint64_t length = rd64(rec + 16), rsize = 80 + ((length + 7) & ~7ull), k;
        for (k = 0; k < s->nsegs && &s->segs[k].b != seg; k++) {}
        if (*len + rsize > s->segs[k].cap) {
            s->segs[k].cap = 2 * (*len + rsize);
            *seg = realloc(*seg, (size_t)s->segs[k].cap);
            if (!*seg) {
                fprintf(stderr, "out of memory\n");
                exit(2);
            }
        }
        uint8_t *h = *seg + *len;
        memset(h, 0, (size_t)rsize);
        memcpy(h, act + 40, 80);
        wr64(h + 56, 24 + length);
        wr64(h + 64, 24);
        wr64(h + 72, length);
        memcpy(h + 80, rec + 24, (size_t)length);
        *len += rsize;
        node_db_archives++;
        uint8_t *e = shell_append(s, 112);
        memset(e, 0, 112);
        wr64(e, 112);
        wr64(e + 8, EV_DB_ARCHIVE);
        wr64(e + 16, number);
        wr64(e + 24, offset);
        memcpy(e + 32, h, 80);
    }
    free(bytes);
    free(diff);
}

/*
 * A node with a Db: a new node of the same start, given the segments in order of number, blocks
 * first, with lantern_node_db_scan, must take every record and hold the same index, the same
 * segments to append to, and db_next_slot past the Db's last block.
 */
static int seg_order(const void *a, const void *b);
static void shell_db_rescan(struct node_shell *s, const char **why) {
    if (!(s->flags & NODE_FLAG_DB)) return;
    uint64_t need = 0, flags = s->flags;
    if (CALL(lantern_node_size, s->room, &need) != 0) {
        *why = "rescan: lantern_node_size status";
        return;
    }
    uint8_t *node = buffer(need);
    wr64(node, need);
    if (CALL(lantern_node_init, s->room, s->ncfg, s->anchor, &flags, node) != 0) *why = "rescan: lantern_node_init status";
    size_t order[NODE_DB_SEGMENTS];
    for (size_t k = 0; k < s->nsegs; k++) order[k] = k;
    qsort_seg = s;
    qsort(order, s->nsegs, sizeof order[0], seg_order);
    for (size_t i = 0; i < s->nsegs && !*why; i++) {
        size_t k = order[i];
        uint64_t len = s->segs[k].len, valid = UINT64_MAX;
        uint8_t *list = buffer(24 + len);
        wr64(list, 24 + len);
        wr64(list + 8, 24);
        wr64(list + 16, len);
        memcpy(list + 24, s->segs[k].b, (size_t)len);
        if (CALL(lantern_node_db_scan, node, &s->segs[k].number, &s->segs[k].sidecars, list, &valid) != 0)
            *why = "rescan: lantern_node_db_scan status";
        else if (valid != len) *why = "rescan: a record of a segment is not taken";
        free(list);
    }
    const uint8_t *a = s->node + rd64(s->node + NODE_DB), *b = node + rd64(node + NODE_DB);
    uint64_t first = rd64(a + 8), end = rd64(a + 16);
    if (!*why && (rd64(b + 8) != first || rd64(b + 16) != end || rd64(b + 56) != rd64(a + 56) ||
                  memcmp(a + rd64(a + 24), b + rd64(b + 24), (size_t)(DB_SLOT_BYTES * (end - first)))))
        *why = "rescan: the index is not the node's";
    uint64_t next = rd64(s->anchor + 32) + 1;
    if (end > next) next = end;
    if (!*why && rd64(node + 480) != next) *why = "rescan: db_next_slot is not past the Db's last block";
    if (!*why && memcmp(node + 488, s->node + 488, 32)) *why = "rescan: the segments to append to are not the node's";
    if (!*why && !rd64(s->node + NODE_ARCHIVE + 40) && memcmp(node + NODE_ARCHIVE + 8, s->node + NODE_ARCHIVE + 8, 32))
        *why = "rescan: the archive's state records are not the node's";
    free(node);
}

/*
 * A NODE_ACT_DB_STATE's state and block as a later start reads them: lantern_node_state_bytes of
 * the state, then lantern_node_anchor_block of those bytes and the block's must give a state and
 * a block of the same roots.
 */
static void root_of(const char *type, const uint8_t *value, uint8_t *root, const char **why);
#define INVALID_ANCHOR 39
#define ANCHOR_BLOCK_BYTES 65536
static void shell_db_anchor(const shell_buf *st, const shell_buf *bl, const char **why) {
    uint64_t need = 0, size = 0;
    uint8_t small[24] = {0};
    wr64(small, 24);
    if (CALL(LF(node_state_bytes), st->b, fresh_scratch(), small, &need) != 1 || need <= 24) {
        *why = "lantern_node_state_bytes: a short buffer is not LANTERN_BUFFER_TOO_SMALL with the size";
        return;
    }
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(LF(node_state_bytes), st->b, fresh_scratch(), out, &size) != 0 || size != need || rd64(out + 8) != 24 ||
        rd64(out + 16) != need - 24 || !guard_ok(out, need))
        *why = "lantern_node_state_bytes: not the state's bytes";
    /* the anchor's bytes: two ByteLists at multiples of 8, the state's SSZ bytes, then the block's message's */
    uint64_t first = (need + 7) & ~7ull, m = rd64(bl->b + 16) - 100, total = 24 + first + 24 + m;
    uint8_t *data = buffer(total), *state = NULL, *block = NULL, r1[32], r2[32];
    if (!*why) {
        memset(data + 24, 0, (size_t)(total - 24));
        wr64(data, total);
        wr64(data + 8, 24);
        wr64(data + 16, total - 24);
        memcpy(data + 24, out, (size_t)need);
        wr64(data + 24 + first, 24 + m);
        wr64(data + 24 + first + 8, 24);
        wr64(data + 24 + first + 16, m);
        memcpy(data + 24 + first + 24, bl->b + rd64(bl->b + 8) + 100, (size_t)m);
        uint64_t room[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}, ssize = 0; /* StateRoom: docs/reference/state.md */
        CALL(LF(beacon_state_copy_size), st->b, room, &ssize);
        state = buffer(ssize);
        wr64(state, ssize);
        block = buffer(ANCHOR_BLOCK_BYTES);
        wr64(block, ANCHOR_BLOCK_BYTES);
        if (CALL(LF(node_anchor_block), data, room, fresh_scratch(), state, block) != 0) *why = "lantern_node_anchor_block: status not 0";
        else if (!guard_ok(state, ssize) || !guard_ok(block, ANCHOR_BLOCK_BYTES)) *why = "lantern_node_anchor_block wrote out of bounds";
        else {
            root_of("BeaconState", st->b, r1, why);
            root_of("BeaconState", state, r2, why);
            if (!*why && memcmp(r1, r2, 32)) *why = "lantern_node_anchor_block: the state is not the saved state";
            if (!*why) {
                root_of("BeaconBlock", block, r1, why);
                uint64_t vsize = 0;
                uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), bl->b + rd64(bl->b + 8), m + 100, &vsize, why);
                if (sb) {
                    root_of("BeaconBlock", nested(sb, field_offset("SignedBeaconBlock", 0)), r2, why);
                    if (!*why && memcmp(r1, r2, 32)) *why = "lantern_node_anchor_block: the block is not the saved block";
                    free(sb);
                }
            }
        }
        if (!*why) { /* the block's state_root: bytes 48 to 80 of its message */
            data[24 + first + 24 + 48] ^= 1;
            wr64(state, ssize);
            wr64(block, ANCHOR_BLOCK_BYTES);
            if (CALL(LF(node_anchor_block), data, room, fresh_scratch(), state, block) != INVALID_ANCHOR)
                *why = "lantern_node_anchor_block: another state_root is not LANTERN_INVALID_ANCHOR";
        }
    }
    free(out);
    free(data);
    free(state);
    free(block);
}

/* The slot of the block of the root in the node's Db, or 2^64 - 1. */
static uint64_t shell_db_slot(const struct node_shell *s, const uint8_t *root) {
    uint64_t slot = UINT64_MAX;
    if (CALL(lantern_db_find_root, s->node + rd64(s->node + NODE_DB), root, &slot) != 0) return UINT64_MAX;
    return slot;
}

static shell_buf *shell_find(struct node_shell *s, uint64_t id) {
    for (size_t i = 0; i < s->nbufs; i++)
        if (s->bufs[i].id == id) return &s->bufs[i];
    return NULL;
}

/* node.md, gossip test: each NODE_WORK_GOSSIP of a block or sidecar with a proposer state names the
 * state of the earlier such work of the same parent root and slot while that state is kept. */
static struct { const struct node_shell *s; uint8_t key[40]; uint64_t id; } gshare[256];
static int ngshare;
static unsigned long gshare_works, gshare_states;

/* node.md, the head: with head_due 0 and the store's slot at head_slot, the store has not changed
 * since the node's last get_head, so its head_root is get_head of the store. */
#define NODE_HEAD_DUE (728 + CONFIG_SIZE + 936 + 1992 + 8 * (4 + 64)) /* include/lantern.inc: Node_head_due, then head_slot */
static unsigned long head_due_checks;
static void gshare_forget(const struct node_shell *s) { /* a new shell at the address of an old one */
    for (int i = 0; i < ngshare; i++)
        if (gshare[i].s == s) gshare[i].s = NULL;
}
static void gossip_share_check(struct node_shell *s, const uint8_t *act, const char **why) {
    uint64_t kind = rd64(act + 16), sb = rd64(act + 32), topic = rd64(act + 64) & 0xff, at;
    if (kind != 7 || !sb || (topic != 1 && topic != 10 && topic != 11)) return; /* NODE_WORK_GOSSIP; beacon_block, blob_sidecar, data_column_sidecar */
    shell_buf *d = shell_find(s, rd64(act + 48));
    if (!d || d->size < 24) return;
    const uint8_t *m = d->b + rd64(d->b + 8);
    uint64_t len = rd64(d->b + 16);
    if (topic == 1) at = len >= 4 ? (uint64_t)(m[0] | m[1] << 8 | m[2] << 16 | (uint32_t)m[3] << 24) : len; /* SignedBeaconBlock: the message's offset */
    else if (topic == 11) at = 20;                                    /* DataColumnSidecar: signed_block_header */
    else at = 8 + 131072 + 48 + 48;                                   /* BlobSidecar: signed_block_header */
    if (at + 48 > len) return;
    uint8_t key[40];
    memcpy(key, m + at + 16, 32); /* parent_root */
    memcpy(key + 32, m + at, 8);  /* slot */
    gshare_works++;
    for (int i = 0; i < ngshare; i++)
        if (gshare[i].s == s && !memcmp(gshare[i].key, key, 40)) {
            if (gshare[i].id != sb && shell_find(s, gshare[i].id)) *why = "a second proposer state copy for one parent root and slot of gossip";
            if (gshare[i].id != sb) gshare_states++;
            gshare[i].id = sb;
            return;
        }
    int i = ngshare < 256 ? ngshare++ : (int)(gshare_works % 256);
    gshare[i].s = s;
    memcpy(gshare[i].key, key, 40);
    gshare[i].id = sb;
    gshare_states++;
}

static void shell_keep(struct node_shell *s, uint64_t id, uint8_t *b, uint64_t size, const char **why) {
    if (!id || shell_find(s, id)) {
        *why = "an action gives an id in use";
        free(b);
        return;
    }
    s->bufs = realloc(s->bufs, (s->nbufs + 1) * sizeof *s->bufs);
    if (!s->bufs) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    s->bufs[s->nbufs].id = id;
    s->bufs[s->nbufs].size = size;
    s->bufs[s->nbufs].b = b;
    s->nbufs++;
}

/*
 * The light client store of the node, as BufferId 2 (node.md, lantern_node_init: Caller must): an LcStore of
 * lantern_lc_store_init of the anchor state and block, with capacities of 2, so that it grows through
 * lantern_lc_store_copy.
 */
static void shell_lc(struct node_shell *s, const uint8_t *state, const uint8_t *block, const char **why) {
    uint64_t room[7] = {2, 2, 2, 2, 2, 2, 2}, need = 0, st;
    if (CALL(lantern_lc_store_size, room, &need) != 0) {
        *why = "lantern_lc_store_size status";
        return;
    }
    uint8_t *lc = buffer(need);
    wr64(lc, need);
    if ((st = CALL(lantern_lc_store_init, room, s->ncfg, state, block, fresh_scratch(), lc)) != 0) {
        static char msg[64];
        snprintf(msg, sizeof msg, "lantern_lc_store_init: status %llu", (unsigned long long)st);
        *why = msg;
        free(lc);
        return;
    }
    if (!guard_ok(lc, need)) {
        *why = "lantern_lc_store_init wrote out of bounds";
        free(lc);
        return;
    }
    shell_keep(s, 2, lc, need, why);
}

/* The light client store c with twice the capacities of each part: lantern_lc_store_copy. */
static void shell_lc_grow(shell_buf *c, const char **why) {
    uint64_t room[7], need = 0;
    for (int k = 0; k < 7; k++) room[k] = 2 * rd64(c->b + 80 + 8 * k); /* LcStore room */
    if (CALL(lantern_lc_store_size, room, &need) != 0) {
        *why = "lantern_lc_store_size status";
        return;
    }
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(lantern_lc_store_copy, c->b, room, out) != 0) *why = "lantern_lc_store_copy status";
    else if (!guard_ok(out, need)) *why = "lantern_lc_store_copy wrote out of bounds";
    if (*why) {
        free(out);
        return;
    }
    free(c->b);
    c->b = out;
    c->size = need;
}

static void shell_drop(struct node_shell *s, uint64_t id, const char **why) {
    shell_buf *b = shell_find(s, id);
    if (!b) {
        *why = "a FREE action names no buffer";
        return;
    }
    free(b->b);
    *b = s->bufs[--s->nbufs];
}

/* Room for an event of size bytes at the end of the pending events. */
static uint8_t *shell_append(struct node_shell *s, uint64_t size) {
    if (s->pending_len + size > s->pending_cap) {
        s->pending_cap = 2 * (s->pending_len + size);
        s->pending = realloc(s->pending, (size_t)s->pending_cap);
        if (!s->pending) {
            fprintf(stderr, "out of memory\n");
            exit(2);
        }
    }
    uint8_t *e = s->pending + s->pending_len;
    s->pending_len += size;
    return e;
}

/* An event of kind with the u64 arg at 16 and, when bytes is not NULL, a ByteList of them at 24. */
static void shell_event(struct node_shell *s, uint64_t kind, uint64_t arg, const uint8_t *bytes, uint64_t len) {
    uint64_t size = bytes ? (48 + len + 7) & ~(uint64_t)7 : 24;
    uint8_t *e = shell_append(s, size);
    memset(e, 0, (size_t)size);
    wr64(e, size);
    wr64(e + 8, kind);
    wr64(e + 16, arg);
    if (bytes) {
        wr64(e + 24, size - 24);
        wr64(e + 32, 24);
        wr64(e + 40, len);
        memcpy(e + 48, bytes, (size_t)len);
    }
}

/* The index of the event stream of the connection, or -1. */
static int shell_ev_of(const struct node_shell *s, uint64_t conn) {
    for (int e = 0; e < s->nev; e++)
        if (s->ev[e].conn == conn) return e;
    return -1;
}

/* The node's entry of the block root, or NULL. */
static const uint8_t *shell_block(const struct node_shell *s, const uint8_t *root) {
    const uint8_t *b = s->node + rd64(s->node + NODE_BLOCKS);
    for (uint64_t i = 0, c = rd64(s->node + NODE_BLOCKS + 8); i < c; i++, b += NODE_BLOCK_BYTES)
        if (!memcmp(b, root, 32)) return b;
    return NULL;
}

/* The store node of the node's head root. */
static uint64_t shell_head(fc_node *n, const char **why) {
    for (uint64_t i = 0; i < node_count(n); i++)
        if (!memcmp(node_at(n, i), n->shell->node + NODE_HEAD_ROOT, 32)) return i;
    *why = "the node's head is not in the store";
    return 0;
}

/*
 * The first sync (node.md): the index of a peer entry that serves no slot of the chain, and that
 * sync_peer was set to, or UINT64_MAX. After each step sync_peer may not be that index + 1: the
 * node's BeaconBlocksByRange went to it. (A request to an entry with no connection fails within
 * the step, so the step leaves no stream of it.)
 */
static uint64_t idle_peer_index = UINT64_MAX;
static unsigned long idle_peer_checks;
static void idle_peer_check(const struct node_shell *s, const char **why) {
    if (idle_peer_index == UINT64_MAX) return;
    if (rd64(s->node + 728 + CONFIG_SIZE + 936 + 1848 + 8 * (4 + 64)) == idle_peer_index + 1) /* Node_sync_peer */
        *why = "a BeaconBlocksByRange to a peer that serves no slot of it";
    else idle_peer_checks++;
}

/* The request timeout (node.md): after a step, no request of the node with no NodeResponse is NODE_REQUEST_MS old. */
static unsigned long request_age_checks;
static void request_age_check(const struct node_shell *s, const char **why) {
    const uint8_t *e = s->node + rd64(s->node + 136); /* Node_streams */
    uint64_t now = rd64(s->node + NODE_TIME_MS);
    for (uint64_t i = 0, c = rd64(s->node + 136 + 8), sb = rd64(s->node + 168); i < c; i++, e += sb)
        if (rd64(e + 32) >= 5 && !rd64(e + 48) && rd64(e + 56) + 10000 <= now) { /* OPENING or RESPONSE, no response, opened_ms */
            *why = "a Status or GetMetaData request of the node outlives NODE_REQUEST_MS";
            return;
        }
    request_age_checks++;
}

static void head_due_check(fc_node *n, const char **why) {
    const uint8_t *node = n->shell->node;
    if (rd64(node + NODE_HEAD_DUE)) return;
    uint64_t now = rd64(n->store + STORE_TIME_MS), g = rd64(n->store + STORE_GENESIS_TIME_MS), d = rd64(n->store + STORE_CONFIG + 104);
    if ((now >= g && d ? (now - g) / d : 0) != rd64(node + NODE_HEAD_DUE + 8)) return; /* a new slot: the next step computes it */
    uint64_t head = 0;
    if (CALL(LF(get_head), n->store, fresh_scratch(), &head) != 0 || head >= node_count(n)) return;
    head_due_checks++;
    if (memcmp(node_at(n, head), node + NODE_HEAD_ROOT, 32)) *why = "head_due is 0 but the node's head is not get_head of the store";
}

/* The post-state the node keeps for the block root, or NULL. */
static const uint8_t *shell_state_of(fc_node *n, const uint8_t *root) {
    const uint8_t *e = shell_block(n->shell, root);
    if (!e || rd64(e + NB_STATUS) != NB_IMPORTED) return NULL;
    shell_buf *b = shell_find(n->shell, rd64(e + NB_STATE_ID));
    return b ? b->b : NULL;
}

/* The resize step for the node: copy it with twice the capacity of each part. */
/* The node in a new buffer with the NodeRoom field at byte offset field doubled. */
static void shell_grow_node(struct node_shell *s, uint64_t field, const char **why) {
    uint64_t room[NODE_ROOM_FIELDS], need = 0;
    if (field % 8 || field / 8 >= NODE_ROOM_FIELDS) {
        *why = "lantern_node_step: room is no NodeRoom field";
        return;
    }
    memcpy(room, s->room, sizeof room);
    room[field / 8] *= 2;
    if (CALL(lantern_node_size, room, &need) != 0) {
        *why = "lantern_node_size status";
        return;
    }
    if (need > (uint64_t)1 << 31) {
        static char msg[96];
        snprintf(msg, sizeof msg, "lantern_node_step asks for a node past 2 GiB: NodeRoom field %llu", (unsigned long long)field);
        *why = msg;
        return;
    }
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(lantern_node_copy, s->node, room, out) != 0) *why = "lantern_node_copy status";
    else if (!guard_ok(out, need)) *why = "lantern_node_copy wrote out of bounds";
    if (*why) {
        free(out);
        return;
    }
    free(s->node);
    s->node = out;
    s->node_size = need;
    memcpy(s->room, room, sizeof room);
}

/* The node's Seen with seen_room, or a copy of it with that room. */
static void shell_seen(struct node_shell *s, const char **why) {
    uint64_t need = 0;
    if (CALL(lantern_seen_size, s->seen_room, &need) != 0) {
        *why = "lantern_seen_size status";
        return;
    }
    uint8_t *b = buffer(need);
    wr64(b, need);
    if (!s->seen) {
        if (CALL(lantern_seen_init, s->seen_room, b) != 0) *why = "lantern_seen_init status";
    } else if (CALL(lantern_seen_copy, s->seen, s->seen_room, b) != 0) *why = "lantern_seen_copy status";
    free(s->seen);
    s->seen = b;
    s->seen_size = need;
}

/*
 * A WORK action: lantern_node_run with its buffers, again with more room while it asks for it,
 * then its WORK_DONE event for the next step.
 */
/*
 * regrow with the copy of the fork of the state's slot, with the node's config (the last fork whose
 * epoch is at most the slot's): the runner's fork, or the fork before.
 */
static uint8_t *regrow_slot(const struct node_shell *s, uint8_t *state, uint64_t *size, uint64_t growth, const char **why) {
#if FORK > FORK_PHASE0
    uint64_t f = FORK_FULU, per_epoch = strcmp(PRESET, "minimal") ? 32 : 8, slot = rd64(state + 48);
    while (f > 0 && slot / per_epoch < rd64(s->ncfg + 16 * f)) f--;
    if (f < FORK) return regrow_prev(state, size, growth, why);
#endif
    (void)s;
    return regrow(state, size, growth, why);
}

static void shell_work(fc_node *n, const uint8_t *work, const char **why) {
    struct node_shell *s = n->shell;
    uint64_t kind = rd64(work + 16), a_id = rd64(work + 24), b_id = rd64(work + 32), c_id = rd64(work + 40), d_id = rd64(work + 48);
    shell_buf *a = a_id ? shell_find(s, a_id) : NULL, *b = b_id && !(b_id & NODE_DB_REF) ? shell_find(s, b_id) : NULL;
    shell_buf *c = c_id ? shell_find(s, c_id) : NULL, *d = d_id && !(d_id & NODE_DB_REF) ? shell_find(s, d_id) : NULL;
    shell_buf view = {0, 0, NULL}, view_b = {0, 0, NULL};
    if (d_id & NODE_DB_REF) { /* the record of the node's Db, in place */
        if (kind != WORK_SERVE && kind != WORK_API_ENCODE && kind != WORK_API_CHUNK && kind != WORK_REPLAY && kind != WORK_ARCHIVE_LOAD) {
            *why = "a NODE_DB_REF in a WORK that does not serve, replay or load";
            return;
        }
        view.b = shell_db_view(s, d_id);
        node_db_serves++;
        view.size = 24;
        d = view.b ? &view : NULL;
    }
    if (b_id & NODE_DB_REF) { /* ARCHIVE_LOAD: the full state's record as state_b */
        if (kind != WORK_ARCHIVE_LOAD) {
            *why = "a NODE_DB_REF as state_b of a WORK other than ARCHIVE_LOAD";
            return;
        }
        view_b.b = shell_db_view(s, b_id);
        view_b.size = 24;
        b = view_b.b ? &view_b : NULL;
    }
    if ((a_id && !a) || (b_id && !b) || (c_id && !c) || (d_id && !d)) {
        *why = "a WORK action names no buffer";
        return;
    }
    const void *settings = NULL;
#if FORK >= FORK_DENEB
    settings = kzg_settings;
#endif
    /* API_SUBMIT: room for the records of its body, whose SSZ bytes are fewer than their JSON's */
    uint64_t ev_size = kind == WORK_API_CHUNK ? EV_API_BYTES + 24 + (s->api.room ? s->api.room : NODE_API_CHUNK)
                       : kind == WORK_API_SUBMIT && d ? (EV_WORK_DONE_SIZE + 2 * d->size + 256) & ~(uint64_t)7
                       : kind == WORK_PUBLISH_CHECK && d && rd64(work + 64) >> 8 & 1 ? (EV_WORK_DONE_SIZE + 4 * d->size + 4096 + 8192) & ~(uint64_t)7
                       : (kind == WORK_PUBLISH_DECODE || kind == WORK_PUBLISH_CHECK) && d ? (EV_WORK_DONE_SIZE + d->size + 256) & ~(uint64_t)7
                                                      : EV_WORK_DONE_SIZE;
    uint8_t *ev = buffer(ev_size);
    uint64_t st = 1, growth = 2;
    for (int t = 0; t < 32 && st == 1 && !*why; t++) {
        uint8_t *snode = copy_of(s->node, s->node_size), *sstore = copy_of(n->store, n->size);
        uint8_t *sa = a ? copy_of(a->b, a->size) : NULL;
        memset(ev, FILL, (size_t)ev_size);
        wr64(ev, ev_size);
        st = CALL(lantern_node_run, s->node, n->store, s->seen, work, a ? a->b : NULL, b ? b->b : NULL, c ? c->b : NULL,
                  d ? d->b : NULL, settings, kind == WORK_ARCHIVE_LOAD ? sized_scratch(16u << 20) : fresh_scratch(), ev);
        if (st != 0 && (memcmp(snode, s->node, (size_t)s->node_size) || memcmp(sstore, n->store, (size_t)n->size) ||
                        (a && memcmp(sa, a->b, (size_t)a->size)))) {
            static char msg[128];
            snprintf(msg, sizeof msg, "lantern_node_run: status %llu of work kind %llu changed %s", (unsigned long long)st,
                     (unsigned long long)kind, memcmp(snode, s->node, (size_t)s->node_size) ? "the node"
                     : memcmp(sstore, n->store, (size_t)n->size) ? "the store" : "state_a");
            *why = msg;
        }
        free(snode);
        free(sstore);
        free(sa);
        if (st != 1 || *why) break;
        if (ev_size > (uint64_t)1 << 28 || (a && a->size > (uint64_t)1 << 31)) {
            static char msg[96];
            snprintf(msg, sizeof msg, "lantern_node_run: work kind %llu asks for room past 256 MiB of event or 2 GiB of state",
                     (unsigned long long)kind);
            *why = msg;
            break;
        }
        /* BUFFER_TOO_SMALL: the event of a SERVE, the store for a node or for the justified balances, else the state's lists. */
        if (kind == WORK_API_SUBMIT) { /* the event, and the Seen its gossip validation adds to */
            free(ev);
            ev_size *= 4;
            ev = buffer(ev_size);
            for (int i = 0; i < 4; i++) s->seen_room[i] *= 2;
            shell_seen(s, why);
        } else if (kind == WORK_POOL_CHECK || kind == WORK_PRODUCE_CHECK || kind == WORK_PRODUCE_FOLD) {
            *why = "lantern_node_run: POOL_CHECK, PRODUCE_CHECK or PRODUCE_FOLD asks for room";
        } else if (kind == WORK_SERVE || kind == WORK_LC_SERVE || kind == WORK_LC_PUBLISH || kind == WORK_NEW_PAYLOAD || kind == WORK_FORKCHOICE || kind == WORK_API_ENCODE ||
            kind == WORK_API_EVENT || kind == WORK_PREPARE_PAYLOAD || kind == WORK_GET_PAYLOAD || kind == WORK_PRODUCE_BLOCK ||
            kind == WORK_PRODUCE_BID || kind == WORK_PUBLISH_DECODE || kind == WORK_PUBLISH_SIDECAR) {
            free(ev);
            ev_size *= 4;
            ev = buffer(ev_size);
        } else if (kind == WORK_PUBLISH_CHECK) {
            /* its event holds the block from the start: the Seen while it has fewer free keys than the block and
               NUMBER_OF_COLUMNS sidecars add (the check restores the Seen it asks room of), else the parent's state */
            uint64_t keys_room = (rd64(s->seen + 24) - rd64(s->seen + 8)) / 32 - rd64(s->seen + 16);
            if (keys_room < 1 + 128) {
                for (int i = 0; i < 4; i++) s->seen_room[i] *= 2;
                shell_seen(s, why);
            } else if (a) {
                a->b = regrow_slot(s, a->b, &a->size, growth, why);
                growth *= 2;
            } else
                *why = "lantern_node_run: PUBLISH_CHECK asks for room with no state";
        } else if (kind == WORK_PUBLISH_SIDECARS) {
            *why = "lantern_node_run: PUBLISH_SIDECARS asks for room";
        } else if (kind == WORK_GOSSIP) { /* the Seen, and the proposer state's lists */
            for (int i = 0; i < 4; i++) s->seen_room[i] *= 2;
            shell_seen(s, why);
            if (b) {
                b->b = regrow(b->b, &b->size, growth, why);
                growth *= 2;
            }
        } else if (kind == WORK_BLOB) {
            *why = "lantern_node_run: BLOB asks for room";
        } else if (kind == WORK_LC_BLOCK || kind == WORK_LC_HEAD) { /* the light client store */
            if (!c) *why = "lantern_node_run: a light client work asks for room with no store";
            else shell_lc_grow(c, why);
        } else if (kind == WORK_API_CHUNK) {
            *why = "lantern_node_run: API_CHUNK asks for room past NODE_API_FIRST_ROOM";
        } else if ((kind == WORK_IMPORT_BLOCK && node_count(n) < node_capacity(n->store)) || kind == WORK_TARGET_STATE ||
                   kind == WORK_SLOTS || kind == WORK_UPGRADE || kind == WORK_REPLAY || kind == WORK_ARCHIVE_LOAD) {
            shell_buf *g = kind == WORK_UPGRADE ? b : a; /* UPGRADE: the buffer the upgrade writes */
            if (!g) *why = "lantern_node_run: no room, and no state";
            else {
                g->b = regrow_slot(s, g->b, &g->size, growth, why);
                growth *= 2;
            }
        } else
            grow_store(n, why);
    }
    if (!*why && st != 0) {
        static char msg[112];
        snprintf(msg, sizeof msg, "lantern_node_run: work kind %llu, arg %llu, status %llu", (unsigned long long)kind,
                 (unsigned long long)rd64(work + 64), (unsigned long long)st);
        *why = msg;
    }
    if (!*why && kind == WORK_REPLAY) {
        node_replays++;
        if (rd64(ev + EV_RESULT) != 0) *why = "lantern_node_run: a REPLAY of a block the node imported is not valid";
    }
    if (!*why && kind == WORK_RECONSTRUCT) {
        if (rd64(ev + EV_RESULT) != 0) *why = "lantern_node_run: a RECONSTRUCT of valid column sidecars is not valid";
        else node_recons++;
    }
    if (!*why && kind == WORK_ARCHIVE_LOAD) {
        node_db_loads++;
        if (rd64(ev + EV_RESULT) != 0) *why = "lantern_node_run: an ARCHIVE_LOAD of a state record the node wrote is not valid";
    }
    if (!*why && (!guard_ok(ev, ev_size) || !guard_ok(s->node, s->node_size) || !guard_ok(n->store, n->size) ||
                  (a && !guard_ok(a->b, a->size))))
        *why = "lantern_node_run wrote out of bounds";
    uint64_t esize = *why ? 0 : rd64(ev);
    if (!*why && (esize < EV_WORK_DONE_SIZE || esize > ev_size || esize % 8 || rd64(ev + 8) != EV_WORK_DONE ||
                  memcmp(ev + 16, work + 16, 56) ||
                  (kind != WORK_SERVE && kind != WORK_LC_SERVE && kind != WORK_LC_PUBLISH && kind != WORK_NEW_PAYLOAD && kind != WORK_FORKCHOICE && kind != WORK_API_ENCODE &&
                   kind != WORK_API_CHUNK && kind != WORK_API_EVENT && kind != WORK_API_SUBMIT && kind != WORK_PREPARE_PAYLOAD &&
                   kind != WORK_GET_PAYLOAD && kind != WORK_PRODUCE_BLOCK && kind != WORK_PRODUCE_BID && kind != WORK_PUBLISH_DECODE && kind != WORK_PUBLISH_CHECK &&
                   kind != WORK_PUBLISH_SIDECAR && esize != EV_WORK_DONE_SIZE)))
        *why = "lantern_node_run: the event is not the WORK_DONE of the work";
    if (!*why) {
        uint64_t result = rd64(ev + EV_RESULT);
        int k = kind == WORK_ATTESTATION || kind == WORK_BLOCK_ATTESTATION || kind == WORK_GOSSIP_VOTE ? 0
                : kind == WORK_ATTESTER_SLASHING || kind == WORK_BLOCK_SLASHING ? 1 : -1;
        if (k >= 0 && !(k == 0 && result == LANTERN_NEED_TARGET_STATE)) {
            if (s->nresults[k] == SHELL_RESULTS) *why = "too many results";
            else s->results[k][s->nresults[k]++] = result;
        }
        memcpy(shell_append(s, esize), ev, (size_t)esize);
    }
    free(ev);
}

static void *p2p_state_of(struct p2p_net *net);
static void p2p_tick(struct p2p_net *net, int side, uint8_t *tick);
static void p2p_shell(struct p2p_net *net, int side, uint8_t *act, const char **why);

static void shell_engine(fc_node *n, const uint8_t *req, uint64_t len, const char **why);

/* The asm-discv5 events of a NODE_ACT_DISCV5: each SET_ENTRY's key and value kept, each LOOKUP counted. */
static void shell_discv5(struct node_shell *s, const uint8_t *ev, uint64_t len, const char **why) {
    for (uint64_t at = 0; at < len && !*why;) {
        uint64_t size = rd64(ev + at), kind = rd64(ev + at + 8);
        if (size < 16 || size % 8 || at + size > len) {
            *why = "NODE_ACT_DISCV5: an event breaks its size";
            return;
        }
        const uint8_t *e = ev + at;
        if (kind == 5 && size >= 48 && rd64(e + 16) >= 1 && rd64(e + 16) <= 16 && rd64(e + 40) <= 64 && 48 + rd64(e + 40) <= size) {
            char key[17] = {0};
            memcpy(key, e + 24, (size_t)rd64(e + 16));
            size_t k = 0;
            while (k < s->nentries && strcmp(s->entries[k].key, key)) k++;
            if (k == 8) *why = "NODE_ACT_DISCV5: too many keys";
            else {
                if (k == s->nentries) s->nentries++;
                strcpy(s->entries[k].key, key);
                s->entries[k].len = rd64(e + 40);
                memcpy(s->entries[k].value, e + 48, (size_t)rd64(e + 40));
            }
        } else if (kind == 3 && size >= 48) s->lookups++;
        else *why = "NODE_ACT_DISCV5: not a SET_ENTRY or LOOKUP";
        at += size;
    }
}

/* One lantern_node_step with the pending events, again with more room while it asks for it, then its actions in order. */
/* Each part of the node holds at most the entries of its NodeRoom capacity, as lantern_node_copy needs. */
static const struct {
    uint64_t ref; /* its PartRef in the Node */
    int room;     /* its NodeRoom field */
    const char *name;
} node_parts[] = {{64, 0, "blocks"}, {80, 1, "checkpoints"}, {96, 2, "pow_blocks"}, {120, 3, "peers"}, {136, 4, "streams"},
                  {224, 7, "messages"}, {256, 8, "blobs"}, {NODE_API_PART, 12, "api"}, {NODE_API_PART + 72, 13, "pool"},
                  {NODE_API_PART + 648, 14, "proposers"}, {NODE_API_PART + 2096, 15, "eth1_blocks"},
                  {NODE_API_PART + 2112, 16, "eth1_deposits"}, {NODE_API_PART + 2144, 16, "eth1_counts"},
                  {NODE_API_PART + 2352, 17, "responses"}};
static void shell_parts_check(const struct node_shell *s, const char **why) {
    for (size_t i = 0; i < sizeof node_parts / sizeof node_parts[0] && !*why; i++)
        if (rd64(s->node + node_parts[i].ref + 8) > s->room[node_parts[i].room]) {
            static char msg[96];
            snprintf(msg, sizeof msg, "lantern_node_step: the %s part holds more entries than its room", node_parts[i].name);
            *why = msg;
        }
}

static void shell_step(fc_node *n, const char **why) {
    struct node_shell *s = n->shell;
    uint64_t len = s->pending_len, esize = 24 + len, count[4] = {0, 0, 0, 0}, nevents = 0, st = 1;
    uint8_t *events = buffer(esize);
    wr64(events, esize);
    wr64(events + 8, 24);
    wr64(events + 16, len);
    memcpy(events + 24, s->pending, (size_t)len);
    s->pending_len = 0;
    for (uint64_t at = 0; at < len; at += rd64(events + 24 + at)) nevents++;
    uint64_t step_scratch = SCRATCH_BYTES;
    for (int t = 0; t < 128 && st == 1 && !*why; t++) {
        wr64(s->actions + 8, 24);
        wr64(s->actions + 16, 0);
        uint8_t *snode = copy_of(s->node, s->node_size), *sstore = copy_of(n->store, n->size), tick[56];
        void *p2p = s->net ? p2p_state_of(s->net) : NULL;
        uint64_t p2p_size = p2p ? rd64(p2p) : 0;
        uint8_t *sp2p = p2p ? copy_of(p2p, p2p_size) : NULL;
        if (s->net) p2p_tick(s->net, 0, tick);
        st = CALL(lantern_node_step, s->node, n->store, p2p, s->net ? tick : NULL, events, sized_scratch(step_scratch), s->actions,
                  count);
        if (st != 0 && (memcmp(snode, s->node, (size_t)s->node_size) || memcmp(sstore, n->store, (size_t)n->size) ||
                        (p2p && memcmp(sp2p, p2p, (size_t)p2p_size))))
            *why = "lantern_node_step: a non-zero status changed a state";
        free(snode);
        free(sstore);
        free(sp2p);
        if (st != 1 || *why) break;
        if (count[2] == 2) { /* BUFFER_TOO_SMALL: the buffer that short names, and of the node the field room names */
            shell_grow_node(s, count[3], why);
        } else if (count[2] == 1) {
            if (s->actions_size > (uint64_t)1 << 30) {
                *why = "lantern_node_step asks for actions past 1 GiB";
                break;
            }
            free(s->actions);
            s->actions_size *= 2;
            s->actions = buffer(s->actions_size);
            wr64(s->actions, s->actions_size);
        } else if (count[2] == 3 && step_scratch < (uint64_t)1 << 30) { /* scratch: twice the room, as the app grows it */
            step_scratch *= 2;
        } else {
            *why = count[2] == 3 ? "lantern_node_step asks for scratch past 1 GiB" : "lantern_node_step: short is no NODE_SHORT_*";
        }
    }
    if (!*why && st != 0) {
        static char msg[64];
        snprintf(msg, sizeof msg, "lantern_node_step: status %llu", (unsigned long long)st);
        *why = msg;
    }
    if (!*why && (!guard_ok(s->node, s->node_size) || !guard_ok(n->store, n->size) || !guard_ok(s->actions, s->actions_size)))
        *why = "lantern_node_step wrote out of bounds";
    if (!*why) shell_parts_check(n->shell, why);
    if (!*why) head_due_check(n, why);
    if (!*why) idle_peer_check(s, why);
    if (!*why) request_age_check(s, why);
    if (!*why && !s->net && (count[0] != nevents || count[1] != UINT64_MAX)) *why = "lantern_node_step: result is not the event count";
    if (!*why && count[0] > nevents) *why = "lantern_node_step: more events handled than given";
    if (!*why && count[0] < nevents) { /* the events not handled go again, before the new ones */
        uint64_t at = 0;
        for (uint64_t k = 0; k < count[0]; k++) at += rd64(events + 24 + at);
        memcpy(shell_append(s, len - at), events + 24 + at, (size_t)(len - at));
    }
    uint64_t used = *why ? 0 : rd64(s->actions + 16);
    if (!*why && (rd64(s->actions + 8) != 24 || 24 + used > s->actions_size)) *why = "lantern_node_step: actions out of bounds";
    for (uint64_t at = 0; at < used && !*why;) {
        uint8_t *act = s->actions + 24 + at;
        uint64_t size = rd64(act), kind = rd64(act + 8);
        if (size < 16 || size % 8 || at + size > used) {
            *why = "lantern_node_step: an action breaks its size";
            break;
        }
        if (kind == ACT_BYTES_PUT && size >= 48 && rd64(act + 24) == size - 24 && rd64(act + 32) == 24 &&
            rd64(act + 40) <= size - 48)
            shell_keep(s, rd64(act + 16), copy_of(act + 24, size - 24), size - 24, why);
        else if (kind == ACT_BYTES_NEW && size == 32 && rd64(act + 24) >= 24) { /* a ByteList of the size, its bytes zero */
            uint64_t n = rd64(act + 24);
            uint8_t *b = buffer(n);
            memset(b, 0, (size_t)n);
            wr64(b, n);
            wr64(b + 8, 24);
            wr64(b + 16, n - 24);
            shell_keep(s, rd64(act + 16), b, n, why);
        } else if (kind == ACT_STATE_BYTES && size == 32) {
            shell_buf *src = shell_find(s, rd64(act + 16));
            uint64_t need = 0, got = 0;
            uint8_t small[24] = {0};
            wr64(small, 24);
            if (!src) *why = "STATE_BYTES names no buffer";
            else if (CALL(LF(node_state_bytes), src->b, fresh_scratch(), small, &need) != 1 || need <= 24)
                *why = "lantern_node_state_bytes: a short buffer is not LANTERN_BUFFER_TOO_SMALL with the size";
            else {
                uint8_t *out = buffer(need);
                wr64(out, need);
                if (CALL(LF(node_state_bytes), src->b, fresh_scratch(), out, &got) != 0 || got != need) *why = "lantern_node_state_bytes: status";
                else {
                    shell_keep(s, rd64(act + 24), out, need, why);
                    if (s->api.nids < 16) s->api.ids[s->api.nids++] = rd64(act + 24);
                }
            }
        } else if (kind == ACT_STATE_COPY && size == 32) {
            shell_buf *src = shell_find(s, rd64(act + 16));
            if (!src) *why = "STATE_COPY names no buffer";
            else shell_keep(s, rd64(act + 24), copy_of(src->b, src->size), src->size, why);
        } else if ((kind == ACT_STATE_FREE || kind == ACT_BYTES_FREE) && size == 32)
            shell_drop(s, rd64(act + 16), why);
        else if (kind == ACT_WORK && size == 72) {
            gossip_share_check(s, act, why);
            if (!*why) shell_work(n, act, why);
        }
        else if (kind == ACT_DB_APPEND && size == 128)
            shell_db_append(s, act, why);
        else if (kind == ACT_DB_ARCHIVE && size == 120)
            shell_db_archive(s, act, why);
        else if (kind == ACT_BYTES_JOIN && size >= 32 && size == 32 + 8 * rd64(act + 24)) { /* the ByteLists of the ids, at multiples of 8 */
            uint64_t n = rd64(act + 24), total = 0;
            for (uint64_t i = 0; i < n && !*why; i++) {
                shell_buf *src = shell_find(s, rd64(act + 32 + 8 * i));
                if (!src) *why = "BYTES_JOIN names no buffer";
                else total += (24 + rd64(src->b + 16) + 7) & ~7ull;
            }
            if (!*why) {
                uint8_t *out = buffer(24 + total), *w = out + 24;
                memset(out, 0, (size_t)(24 + total));
                wr64(out, 24 + total);
                wr64(out + 8, 24);
                wr64(out + 16, total);
                for (uint64_t i = 0; i < n; i++) {
                    shell_buf *src = shell_find(s, rd64(act + 32 + 8 * i));
                    uint64_t len = rd64(src->b + 16);
                    wr64(w, 24 + len);
                    wr64(w + 8, 24);
                    wr64(w + 16, len);
                    memcpy(w + 24, src->b + rd64(src->b + 8), (size_t)len);
                    w += (24 + len + 7) & ~7ull;
                }
                shell_keep(s, rd64(act + 16), out, 24 + total, why);
            }
        }
        else if (kind == ACT_DB_DROP && size == 32) { /* the segment goes */
            uint64_t sidecars = rd64(act + 24), number = rd64(act + 16);
            size_t k = 0;
            while (k < s->nsegs && !(s->segs[k].sidecars == sidecars && s->segs[k].number == number)) k++;
            if (sidecars > 1) *why = "DB_DROP: not a block or a sidecar segment";
            else if (k < s->nsegs) {
                free(s->segs[k].b);
                s->segs[k] = s->segs[--s->nsegs];
            }
            if (s->ndrops < 16) s->drops[s->ndrops++] = sidecars << 63 | number;
        }
        else if (kind == ACT_DB_STATE && size == 56) {
            shell_buf *st = shell_find(s, rd64(act + 16)), *bl = shell_find(s, rd64(act + 24));
            if (!st || !bl) *why = "DB_STATE names no buffer";
            else if (rd64(st->b + 48) != rd64(act + 32)) *why = "DB_STATE: the state is not of the slot"; /* NODE_STATE_SLOT 48 */
            else {
                shell_db_anchor(st, bl, why);
                s->db_states++;
                node_db_states++;
            }
        }
        else if (kind == ACT_ENGINE && size >= 48 && rd64(act + 24) == size - 24 && rd64(act + 32) == 24 && rd64(act + 40) <= size - 48)
            shell_engine(n, act + 48, rd64(act + 40), why);
        else if (kind == ACT_BUILDER && size >= 48 && rd64(act + 16) < 4 && rd64(act + 24) == size - 24 && rd64(act + 32) == 24 &&
                 rd64(act + 40) <= size - 48) { /* the runner as the builder: it keeps the request and answers 200 */
            static const char ok[] = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
            uint64_t blen = rd64(act + 40);
            if (!(s->flags & NODE_FLAG_BUILDER)) *why = "a BUILDER action of a node with no builder";
            else {
                if (s->bld_len + blen > s->bld_cap) {
                    s->bld_cap = 2 * (s->bld_len + blen) + 4096;
                    s->bld = realloc(s->bld, (size_t)s->bld_cap);
                    if (!s->bld) {
                        fprintf(stderr, "out of memory\n");
                        exit(2);
                    }
                }
                memcpy(s->bld + s->bld_len, act + 48, (size_t)blen);
                s->bld_len += blen;
                s->bld_calls++;
                static const char hdr[] = "GET /eth/v1/builder/header/", sub[] = "POST /eth/v2/builder/blinded_blocks ";
                int is_hdr = blen >= sizeof hdr - 1 && !memcmp(act + 48, hdr, sizeof hdr - 1);
                int is_sub = blen >= sizeof sub - 1 && !memcmp(act + 48, sub, sizeof sub - 1);
                tv list = is_hdr ? s->bids : is_sub ? s->submits : NULL;
                uint64_t n = is_hdr ? s->nbids : is_sub ? s->nsubmits : 0, *calls = is_hdr ? &s->bid_calls : &s->submit_calls;
                if (list && n) {
                    /* getHeader, submitBlindedBlockV2: the case's k-th answer, its last past them; an empty one is no answer */
                    tv b = list + 9;
                    for (uint64_t k = 0; k < *calls && k + 1 < n; k++) b = tv_skip(b);
                    (*calls)++;
                    uint64_t alen;
                    const uint8_t *ans = tv_bytes(b, &alen);
                    if (alen) shell_event(s, EV_BUILDER, rd64(act + 16), ans, alen);
                }
                else shell_event(s, EV_BUILDER, rd64(act + 16), (const uint8_t *)ok, sizeof ok - 1);
            }
        }
        else if (kind == ACT_DISCV5 && size >= 48 && rd64(act + 24) == size - 24 && rd64(act + 32) == 24 && rd64(act + 40) <= size - 48)
            shell_discv5(s, act + 48, rd64(act + 40), why);
        else if (kind == ACT_API_SEND && size >= 56 && rd64(act + 24) <= 1 && rd64(act + 32) == size - 32 && rd64(act + 40) == 24 &&
                 rd64(act + 48) <= size - 56) {
            uint64_t n = rd64(act + 48);
            int e = shell_ev_of(s, rd64(act + 16));
            if (e >= 0) { /* an event stream */
                if (s->ev[e].closes || s->ev[e].gone || rd64(act + 24)) s->ev[e].late++;
                if (s->ev[e].len + n > s->ev[e].cap) {
                    s->ev[e].cap = 2 * (s->ev[e].len + n) + 4096;
                    s->ev[e].b = realloc(s->ev[e].b, (size_t)s->ev[e].cap);
                    if (!s->ev[e].b) {
                        fprintf(stderr, "out of memory\n");
                        exit(2);
                    }
                }
                memcpy(s->ev[e].b + s->ev[e].len, act + 56, (size_t)n);
                s->ev[e].len += n;
                s->ev[e].sends++;
                s->ev[e].lasts += rd64(act + 24);
                if (!s->ev[e].nosent && !s->ev[e].gone) shell_event(s, EV_API_SENT, s->ev[e].conn, NULL, 0);
            } else if (rd64(act + 16) != s->api.conn) *why = "API_SEND of another connection";
            else {
                if (s->api.closes || s->api.lasts) s->api.late++;
                if (s->api.len + n > s->api.cap) {
                    s->api.cap = 2 * (s->api.len + n) + 4096;
                    s->api.b = realloc(s->api.b, (size_t)s->api.cap);
                    if (!s->api.b) {
                        fprintf(stderr, "out of memory\n");
                        exit(2);
                    }
                }
                memcpy(s->api.b + s->api.len, act + 56, (size_t)n);
                s->api.len += n;
                s->api.sends++;
                s->api.lasts += rd64(act + 24);
                if (s->api.gone) s->api.late++;
                else if (rd64(act + 24) == 0 && s->api.cut) { /* the connection closes after the first chunk */
                    shell_event(s, EV_API_CLOSED, s->api.conn, NULL, 0);
                    s->api.gone = 1;
                } else if (rd64(act + 24) == 0)
                    shell_event(s, EV_API_SENT, s->api.conn, NULL, 0);
            }
        } else if (kind == ACT_API_CLOSE && size == 24) {
            int e = shell_ev_of(s, rd64(act + 16));
            if (e >= 0) {
                if (s->ev[e].closes || s->ev[e].gone) s->ev[e].late++;
                s->ev[e].closes++;
            } else if (rd64(act + 16) != s->api.conn) *why = "API_CLOSE of another connection";
            else {
                if (s->api.closes || !s->api.lasts || s->api.gone) s->api.late++;
                s->api.closes++;
            }
        }
        else if (kind == ACT_P2P_LIST && s->net && size >= 40 && rd64(act + 16) == size - 16 && rd64(act + 24) == 24 &&
                 rd64(act + 32) == size - 40) {
            /* the shell requests of libp2p, in order; the node took the application notices */
            for (uint64_t at2 = 0; at2 < rd64(act + 32) && !*why; at2 += rd64(act + 40 + at2))
                p2p_shell(s->net, 0, act + 40 + at2, why);
        } else
            *why = "lantern_node_step: an action of no kind";
        at += size;
    }
    free(events);
}

/* The first place of needle in the len bytes at hay, or NULL. */
static const char *find_bytes(const char *hay, uint64_t len, const char *needle) {
    size_t nl = strlen(needle);
    for (uint64_t i = 0; i + nl <= len; i++)
        if (!memcmp(hay + i, needle, nl)) return hay + i;
    return NULL;
}

/* The value of the hex digit c, or -1. */
static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/*
 * The 32 bytes of the hex string after the key in the len bytes at body, into out; 0 when there
 * is none. It reads only those len bytes: they end with no zero byte, so no C string function.
 */
static int find_hash(const char *body, uint64_t len, const char *key, uint8_t *out) {
    const char *p = find_bytes(body, len, key);
    if (!p || (uint64_t)(p - body) + strlen(key) + 64 > len) return 0;
    p += strlen(key);
    for (int i = 0; i < 32; i++) {
        int hi = hex_digit(p[2 * i]), lo = hex_digit(p[2 * i + 1]);
        if (hi < 0 || lo < 0) return 0;
        out[i] = (uint8_t)(hi << 4 | lo);
    }
    return 1;
}

/*
 * The execution engine of the node (docs/reference/node.md, Test vectors): one HTTP request of
 * engine_newPayload or engine_forkchoiceUpdated, with the JWT of the node's secret and time; the
 * answer is the payloadStatus of the case's last payload_status step of the payload's hash (the
 * head's for forkchoiceUpdated), else VALID, in two NODE_EV_ENGINE events.
 */
/* The u64 of the hex digits after "0x" at p, its end at *e; 2^64 - 1 for none. */
static uint64_t hex_u64(const char *p, const char *end, const char **e) {
    uint64_t v = 0;
    int k = 0;
    if (p + 2 > end || p[0] != '0' || p[1] != 'x') return UINT64_MAX;
    for (p += 2; p < end && k < 16; p++, k++) {
        int d = *p >= '0' && *p <= '9' ? *p - '0' : *p >= 'a' && *p <= 'f' ? *p - 'a' + 10 : -1;
        if (d < 0) break;
        v = v << 4 | (uint64_t)d;
    }
    if (e) *e = p;
    return k ? v : UINT64_MAX;
}

static int hex_out(char *o, const uint8_t *b, uint64_t n) {
    for (uint64_t i = 0; i < n; i++) sprintf(o + 2 * i, "%02x", b[i]);
    return (int)(2 * n);
}

/*
 * node-eth1: the runner as the execution engine of the eth1 follower: eth_getBlockByNumber of the
 * case's chain ("latest" its last block, a number past it null), eth_getLogs of the deposit
 * contract's DepositEvent logs of the case's deposits in the block range, each the contract's ABI
 * encoding. The request's address must be the case's contract.
 */
static void shell_eth1(fc_node *n, const char *body, uint64_t blen, const char **why) {
    struct node_shell *s = n->shell;
    const char *bend = body + blen, *idp = find_bytes(body, blen, "\"id\":");
    unsigned long long id = 0;
    for (const char *d = idp ? idp + 5 : bend; d < bend && *d >= '0' && *d <= '9'; d++) id = id * 10 + (unsigned long long)(*d - '0');
    if (!s->eth1_blocks || !s->eth1_nblocks) {
        *why = "engine: an eth_ call with no eth1 chain";
        return;
    }
    s->eth1_calls++;
    size_t cap = 4096 + (size_t)s->eth1_ndeposits * 1600, k;
    char *json = malloc(cap), *http = malloc(cap + 128);
    if (!json || !http) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    k = (size_t)snprintf(json, cap, "{\"jsonrpc\":\"2.0\",\"id\":%llu,\"result\":", id);
    if (find_bytes(body, blen, "\"method\":\"eth_getBlockByNumber\"")) {
        const char *pp = find_bytes(body, blen, "\"params\":[\"");
        uint64_t num = UINT64_MAX;
        if (!pp) {
            *why = "engine: eth_getBlockByNumber with no params";
        } else if (!strncmp(pp + 11, "latest\"", 7)) {
            num = rd64(s->eth1_blocks + 48 * (s->eth1_nblocks - 1));
        } else {
            num = hex_u64(pp + 11, bend, NULL);
            if (num == UINT64_MAX) *why = "engine: eth_getBlockByNumber of no number";
        }
        const uint8_t *b = NULL;
        for (uint64_t i = 0; i < s->eth1_nblocks; i++)
            if (rd64(s->eth1_blocks + 48 * i) == num) b = s->eth1_blocks + 48 * i;
        if (!b) k += (size_t)snprintf(json + k, cap - k, "null");
        else {
            k += (size_t)snprintf(json + k, cap - k, "{\"number\":\"0x%llx\",\"hash\":\"0x", (unsigned long long)rd64(b));
            k += (size_t)hex_out(json + k, b + 16, 32);
            k += (size_t)snprintf(json + k, cap - k, "\",\"timestamp\":\"0x%llx\",\"transactions\":[]}", (unsigned long long)rd64(b + 8));
        }
    } else {
        const char *ap = find_bytes(body, blen, "\"address\":\"0x"), *fp = find_bytes(body, blen, "\"fromBlock\":\""),
                   *tp = find_bytes(body, blen, "\"toBlock\":\"");
        uint8_t addr[20];
        int ok = ap && fp && tp;
        for (int i = 0; ok && i < 20; i++) {
            unsigned v;
            if (sscanf(ap + 13 + 2 * i, "%2x", &v) != 1) ok = 0;
            addr[i] = (uint8_t)v;
        }
        if (!ok) *why = "engine: eth_getLogs without an address and a block range";
        else if (!s->eth1_contract || memcmp(addr, s->eth1_contract, 20)) *why = "engine: eth_getLogs of another address than the deposit contract";
        else if (!find_bytes(body, blen, "\"topics\":[\"0x649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5\"]"))
            *why = "engine: eth_getLogs of another topic than DepositEvent";
        uint64_t from = ok ? hex_u64(fp + 13, bend, NULL) : 0, to = ok ? hex_u64(tp + 11, bend, NULL) : 0;
        json[k++] = '[';
        int first = 1;
        for (uint64_t i = 0; i < s->eth1_ndeposits && !*why; i++) {
            const uint8_t *d = s->eth1_deposits + 200 * i, *dd = d + 16;
            uint64_t bn = rd64(d);
            if (bn < from || bn > to) continue;
            uint8_t abi[576] = {0};
            abi[31] = 0xa0, abi[62] = 1, abi[94] = 1, abi[95] = 0x40, abi[126] = 1, abi[127] = 0x80, abi[158] = 2;
            abi[191] = 48, abi[287] = 32, abi[351] = 8, abi[415] = 96, abi[543] = 8;
            memcpy(abi + 192, dd, 48);
            memcpy(abi + 288, dd + 48, 32);
            memcpy(abi + 352, dd + 80, 8);
            memcpy(abi + 416, dd + 88, 96);
            memcpy(abi + 544, d + 8, 8);
            if (!first) json[k++] = ',';
            first = 0;
            k += (size_t)snprintf(json + k, cap - k, "{\"address\":\"0x");
            k += (size_t)hex_out(json + k, s->eth1_contract, 20);
            k += (size_t)snprintf(json + k, cap - k,
                                  "\",\"topics\":[\"0x649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5\"],\"data\":\"0x");
            k += (size_t)hex_out(json + k, abi, 576);
            k += (size_t)snprintf(json + k, cap - k, "\",\"blockNumber\":\"0x%llx\",\"logIndex\":\"0x0\",\"removed\":false}", (unsigned long long)bn);
        }
        json[k++] = ']';
    }
    json[k++] = '}';
    size_t hl = (size_t)snprintf(http, 128, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n", (int)k);
    memcpy(http + hl, json, k);
    hl += k;
    if (!*why) shell_event(s, EV_ENGINE, 0, (const uint8_t *)http, (uint64_t)hl);
    free(json);
    free(http);
}

static int engine_fcu_error;          /* set: each engine_forkchoiceUpdated with no payload attributes gets -38006, Too deep reorg */
static unsigned long engine_fcu_errors; /* those answers */
static void shell_engine(fc_node *n, const uint8_t *req, uint64_t len, const char **why) {
    static const char *const names[5] = {"VALID", "INVALID", "SYNCING", "ACCEPTED", "INVALID_BLOCK_HASH"};
    struct node_shell *s = n->shell;
    const char *r = (const char *)req, *end = find_bytes(r, len, "\r\n\r\n");
    uint8_t secret[32], token[24 + 256], hash[32];
    memset(secret, 0x42, 32);
    wr64(token, sizeof token);
    uint64_t iat = rd64(s->node + NODE_TIME_MS) / 1000;
    if (!end || len < 16 || memcmp(r, "POST / HTTP/1.1\r\n", 17)) {
        *why = "engine: not an HTTP POST";
        return;
    }
    if (CALL(lantern_jwt_token, secret, &iat, fresh_scratch(), token) != 0) *why = "engine: jwt_token status";
    else {
        char auth[300];
        snprintf(auth, sizeof auth, "\r\nAuthorization: Bearer %.*s\r\n", (int)rd64(token + 16), (const char *)token + 24);
        if (!find_bytes(r, (uint64_t)(end - r) + 2, auth)) *why = "engine: no JWT of the node's secret and time";
    }
    if (*why) return;
    const char *body = end + 4;
    uint64_t blen = len - (uint64_t)(body - r);
    if (find_bytes(body, blen, "\"method\":\"eth_getBlockByNumber\"") || find_bytes(body, blen, "\"method\":\"eth_getLogs\"")) {
        shell_eth1(n, body, blen, why);
        return;
    }
    int fcu = find_bytes(body, blen, "\"method\":\"engine_forkchoiceUpdatedV") != NULL;
    if (n->produce && find_bytes(body, blen, "\"method\":\"engine_getPayloadV")) { /* the case's result */
        const char *ip = find_bytes(body, blen, "\"id\":");
        unsigned long long gid = 0;
        for (const char *d = ip ? ip + 5 : body + blen; d < body + blen && *d >= '0' && *d <= '9'; d++) gid = gid * 10 + (unsigned long long)(*d - '0');
        size_t jl = (size_t)n->result_len + 64, hl;
        char *json = malloc(jl), *http = malloc(jl + 128);
        if (!json || !http) {
            fprintf(stderr, "out of memory\n");
            exit(2);
        }
        int k = snprintf(json, jl, "{\"jsonrpc\":\"2.0\",\"id\":%llu,\"result\":", gid);
        memcpy(json + k, n->result, (size_t)n->result_len);
        k += (int)n->result_len;
        json[k++] = '}';
        hl = (size_t)snprintf(http, 128, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n", k);
        memcpy(http + hl, json, (size_t)k);
        hl += (size_t)k;
        shell_event(n->shell, EV_ENGINE, 0, (const uint8_t *)http, (uint64_t)hl / 2); /* in two parts */
        shell_event(n->shell, EV_ENGINE, 0, (const uint8_t *)http + hl / 2, (uint64_t)(hl - hl / 2));
        free(json);
        free(http);
        return;
    }
    if (!fcu && !find_bytes(body, blen, "\"method\":\"engine_newPayloadV")) {
        *why = "engine: no engine_newPayload or engine_forkchoiceUpdated";
        return;
    }
    const char *idp = find_bytes(body, blen, "\"id\":");
    if (!idp || !find_hash(body, blen, fcu ? "\"headBlockHash\":\"0x" : "\"blockHash\":\"0x", hash)) {
        *why = "engine: no id or block hash";
        return;
    }
    if (n->watch) {
        const char *m = find_bytes(body, blen, ",\"method\":");
        n->engine_calls++;
        if (!n->tail_len) *why = "engine: a call the case does not make";
        else if (!m || (uint64_t)(body + blen - m) != n->tail_len || memcmp(m, n->tail, (size_t)n->tail_len)) {
            static char msg[1400];
            snprintf(msg, sizeof msg, "engine: the forkchoiceUpdated differs from the case's: got %.600s want %.600s",
                     m ? m : body, (const char *)n->tail);
            *why = msg;
        }
        if (*why) return;
    }
    unsigned long long id = 0; /* the digits after "id": within the body */
    for (const char *d = idp + 5; d < body + blen && *d >= '0' && *d <= '9'; d++) id = id * 10 + (unsigned long long)(*d - '0');
    if (fcu && engine_fcu_error && !find_bytes(body, blen, "\"timestamp\":")) { /* as Geth past its reorg limit */
        char ej[160], eh[320];
        int jl = snprintf(ej, sizeof ej, "{\"jsonrpc\":\"2.0\",\"id\":%llu,\"error\":{\"code\":-38006,\"message\":\"Too deep reorg\"}}", id);
        int el2 = snprintf(eh, sizeof eh, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s", jl, ej);
        shell_event(s, EV_ENGINE, 0, (const uint8_t *)eh, (uint64_t)el2);
        engine_fcu_errors++;
        return;
    }
    uint64_t el = 1, has_latest = 1;
    const uint8_t *latest = hash;
    for (size_t k = 0; k < n->npayloads; k++)
        if (!memcmp(n->payloads[k].block_hash, hash, 32)) {
            el = n->payloads[k].el;
            has_latest = n->payloads[k].has_latest;
            latest = n->payloads[k].latest_valid_hash;
        }
    char lvh[80] = "null", status[256], json[512], http[700];
    if (has_latest) {
        strcpy(lvh, "\"0x");
        for (int i = 0; i < 32; i++) snprintf(lvh + 3 + 2 * i, 3, "%02x", latest[i]);
        strcat(lvh, "\"");
    }
    snprintf(status, sizeof status, "{\"status\":\"%s\",\"latestValidHash\":%s,\"validationError\":null}", names[el - 1], lvh);
    char pid[24] = "null";
    if ((n->watch || n->produce) && n->pid_len == 8 && find_bytes(body, blen, "\"timestamp\":")) {
        strcpy(pid, "\"0x");
        for (int i = 0; i < 8; i++) snprintf(pid + 3 + 2 * i, 3, "%02x", n->pid[i]);
        strcat(pid, "\"");
    }
    if (fcu) snprintf(json, sizeof json, "{\"jsonrpc\":\"2.0\",\"id\":%llu,\"result\":{\"payloadStatus\":%s,\"payloadId\":%s}}", id, status, pid);
    else snprintf(json, sizeof json, "{\"jsonrpc\":\"2.0\",\"id\":%llu,\"result\":%s}", id, status);
    int hl = snprintf(http, sizeof http, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %zu\r\n\r\n%s",
                      strlen(json), json);
    shell_event(s, EV_ENGINE, 0, (const uint8_t *)http, (uint64_t)hl / 2); /* in two parts */
    shell_event(s, EV_ENGINE, 0, (const uint8_t *)http + hl / 2, (uint64_t)(hl - hl / 2));
}

/* Steps until the node gives no more work. */
/* Settles of node mode whose store has a finalized epoch above 0: the prune ran. */
static unsigned long node_settles_finalized;

static void shell_settle(fc_node *n, const char **why) {
    for (int k = 0; n->shell->pending_len && !*why; k++) {
        if (k == 4096) *why = "the node does not settle";
        else shell_step(n, why);
    }
    /* The node prunes at each new finalized epoch: the store's first node is then the finalized root. */
    if (!*why && (node_count(n) == 0 || memcmp(node_at(n, 0), n->store + STORE_FINALIZED + 8, 32)))
        *why = "the store's first node is not the finalized root after the node's prune";
    if (!*why && rd64(n->store + STORE_FINALIZED) > 0) node_settles_finalized++;
}

/* The SSZ bytes of value of the named type, from offset 24 of the returned buffer, their length in *len. */
static uint8_t *encoded(const char *type, const uint8_t *value, uint64_t *len, const char **why) {
    const uint8_t *desc = type_by_name(type);
    uint64_t scsize, need = 0;
    uint8_t *scr = scratch_for(desc, &scsize), *out = NULL;
    if (ssz_serialize_size(desc, value, scr, &need) != 0) *why = "serialize_size status";
    else {
        out = buffer(need);
        wr64(out, need);
        if (ssz_serialize(desc, value, scr, out) != 0) *why = "serialize status";
        *len = need - 24;
    }
    free(scr);
    return out;
}

/*
 * lantern_node_anchor of the case's anchor_state (node.md, Test vectors): the state and the block
 * must encode to the case's anchor_state and anchor_block; with another body_root in the state's
 * latest_block_header, the status must be LANTERN_INVALID_ANCHOR.
 */
static uint8_t *list_of(const uint8_t *b, uint64_t len, uint64_t junk, uint64_t room, uint64_t *size);
#define INVALID_ANCHOR 39
#define ANCHOR_BLOCK_BYTES 65536
static void anchor_check(tv parts, const char **why) {
    uint64_t slen, blen, need = 0, vsize = 0, lsize, elen;
    const uint8_t *enc = tv_bytes(tv_get(parts, "anchor_state"), &slen);
    const uint8_t *benc = tv_bytes(tv_get(parts, "anchor_block"), &blen);
    uint8_t *value = decode(type_by_name("BeaconState"), enc, slen, &vsize, why), cps[120];
    if (!value) return;
    if (CALL(LF(node_state_checkpoints), value, cps) != 0) *why = "lantern_node_state_checkpoints: status not 0";
    for (int k = 0; k < 3 && !*why; k++) /* previous_justified, current_justified, finalized: fields 18 to 20 */
        if (memcmp(cps + 40 * k, value + field_offset("BeaconState", 18 + (uint64_t)k), 40))
            *why = "lantern_node_state_checkpoints: a checkpoint is not the state's";
    uint64_t room[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}; /* StateRoom: docs/reference/state.md */
    CALL(LF(beacon_state_copy_size), value, room, &need);
    free(value);
    if (*why) return;
    uint8_t *data = list_of(enc, slen, 0, 0, &lsize), *state = buffer(need), *block = buffer(ANCHOR_BLOCK_BYTES);
    wr64(state, need);
    wr64(block, ANCHOR_BLOCK_BYTES);
    if (CALL(LF(node_anchor), data, room, fresh_scratch(), state, block) != 0) *why = "lantern_node_anchor: status not 0";
    else if (!guard_ok(state, need) || !guard_ok(block, ANCHOR_BLOCK_BYTES)) *why = "lantern_node_anchor wrote out of bounds";
    else {
        uint8_t *e = encoded("BeaconState", state, &elen, why);
        if (e && (elen != slen || memcmp(e + 24, enc, (size_t)slen))) *why = "lantern_node_anchor: the state is not the anchor state";
        free(e);
        if (!*why) {
            e = encoded("BeaconBlock", block, &elen, why);
            if (e && (elen != blen || memcmp(e + 24, benc, (size_t)blen))) *why = "lantern_node_anchor: the block is not the anchor block";
            free(e);
        }
    }
    if (!*why) { /* latest_block_header.body_root: SSZ bytes 144 to 176 of a BeaconState */
        data[24 + 144] ^= 1;
        wr64(state, need);
        wr64(block, ANCHOR_BLOCK_BYTES);
        if (CALL(LF(node_anchor), data, room, fresh_scratch(), state, block) != INVALID_ANCHOR)
            *why = "lantern_node_anchor: another body_root is not LANTERN_INVALID_ANCHOR";
    }
    free(data);
    free(state);
    free(block);
}

/*
 * lantern_node_block_header of a SignedBeaconBlock's SSZ bytes (node.md, Test vectors): the slot,
 * proposer_index, parent_root and state_root of the message at its offset, the signature at
 * bytes 4 to 100, and a header whose hash_tree_root is the block's root.
 */
#define SIGNED_HEADER_BYTES 208
static void header_check(const uint8_t *enc, uint64_t len, const char **why) {
    uint64_t lsize, vsize;
    uint8_t *data = list_of(enc, len, 0, 0, &lsize), *out = buffer(SIGNED_HEADER_BYTES), hroot[32], broot[32];
    uint64_t st = CALL(LF(node_block_header), data, fresh_scratch(), out);
    uint8_t *value = decode(type_by_name("SignedBeaconBlock"), enc, len, &vsize, why);
    uint64_t at = len >= 4 ? (enc[0] | (uint64_t)enc[1] << 8 | (uint64_t)enc[2] << 16 | (uint64_t)enc[3] << 24) : 0;
    if (!value) {
        *why = st == 56 ? NULL : "lantern_node_block_header: an invalid block is not LANTERN_INVALID_ENCODING";
    } else if (st != 0) *why = "lantern_node_block_header: status not 0";
    else if (!guard_ok(out, SIGNED_HEADER_BYTES)) *why = "lantern_node_block_header wrote out of bounds";
    else if (at + 80 > len || memcmp(out, enc + at, 80) || memcmp(out + 112, enc + 4, 96))
        *why = "lantern_node_block_header: a field is not the block's";
    else {
        root_of("BeaconBlockHeader", out, hroot, why);
        root_of("BeaconBlock", nested(value, field_offset("SignedBeaconBlock", 0)), broot, why);
        if (!*why && memcmp(hroot, broot, 32)) *why = "lantern_node_block_header: the header's root is not the block's";
    }
    free(value);
    free(data);
    free(out);
}

/* A block step through the node; a valid block's attestations and attester slashings go to fork choice by the node's own works. */
static void shell_block_step(fc_node *n, tv parts, tv step, const char **why) {
    struct node_shell *s = n->shell;
    char key[128];
    uint64_t blen, vsize;
    tv bname = tv_get(step, "block"), v = tv_get(step, "valid");
    int valid = !v || (*v == T_BOOL && v[1]);
    snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
    const uint8_t *bytes = tv_bytes(tv_get(parts, key), &blen);
    uint8_t *signed_block = decode(type_by_name("SignedBeaconBlock"), bytes, blen, &vsize, why), root[32];
    if (!signed_block) return;
    const uint8_t *block = nested(signed_block, field_offset("SignedBeaconBlock", 0));
    const uint8_t *body = nested(block, field_offset("BeaconBlock", 4));
    root_of("BeaconBlock", block, root, why);
    uint64_t available = step_data_available(parts, step, body, why);
    s->nresults[0] = s->nresults[1] = 0;
    if (!*why) {
        shell_event(s, EV_BLOCK, available, bytes, blen);
        shell_settle(n, why);
    }
    const uint8_t *e = *why ? NULL : shell_block(s, root);
    int imported = e && rd64(e + NB_STATUS) == NB_IMPORTED;
    if (!*why && valid && !imported) {
        static char msg[96];
        snprintf(msg, sizeof msg, "block: expected imported, node status %llu, result %llu",
                 e ? (unsigned long long)rd64(e + NB_STATUS) : 0ull, e ? (unsigned long long)rd64(e + 104) : 0ull);
        *why = msg;
    } else if (!*why && !valid && imported) *why = "block: expected not imported";
    if (!*why && valid) {
        uint64_t natt = rd64(body + field_offset("BeaconBlockBody", 5) + 8), nsl = rd64(body + field_offset("BeaconBlockBody", 4) + 8);
        if (!*why && (s->nresults[0] != natt || s->nresults[1] != nsl)) {
            static char msg[128];
            snprintf(msg, sizeof msg, "the block's votes: not one result each: %zu of %llu attestations, %zu of %llu slashings",
                     s->nresults[0], (unsigned long long)natt, s->nresults[1], (unsigned long long)nsl);
            *why = msg;
        }
        for (size_t i = 0; i < s->nresults[0] && !*why; i++)
            if (s->results[0][i] != 0) *why = "a block attestation is not valid";
        for (size_t i = 0; i < s->nresults[1] && !*why; i++)
            if (s->results[1][i] != 0) *why = "a block attester slashing is not valid";
    }
    free(signed_block);
}

/* Whether a case runs in node mode: one with no payload_status step. */
static int node_mode(tv parts) {
    tv steps = tv_get(parts, "steps");
    tv st = steps ? steps + 9 : NULL;
    for (uint64_t k = 0, c = steps ? rd64(steps + 1) : 0; k < c && FORK < FORK_BELLATRIX; k++, st = tv_skip(st))
        if (tv_get(st, "payload_status")) return 0; /* from bellatrix on, the node's execution engine gives them */
    return steps != NULL;
}

/*
 * The NodeID of the runner's peer, the secp256k1 key of p2p_config side 1: keccak256 of its
 * point, x then y, read as a big-endian number, in 32 little-endian bytes.
 */
static void peer_node_id(uint8_t *out, const char **why) {
    uint8_t key[32], pub[40], list[24 + 64], digest[32];
    for (int i = 0; i < 32; i++) key[i] = (uint8_t)(31 + i + 1);
    wr64(list, sizeof list);
    wr64(list + 8, 24);
    wr64(list + 16, 64);
    if (CALL(crypto_secp256k1_public_key, key, pub) != 0 || CALL(crypto_secp256k1_decompress, pub, list + 24) != 0 ||
        CALL(crypto_keccak256, list, digest) != 0) {
        *why = "the peer's node ID";
        return;
    }
    for (int i = 0; i < 32; i++) out[i] = digest[31 - i];
}

/* The node of a case's anchor, with the shell's buffers: the store, the node, the actions, the anchor state as id 1. */
static uint64_t shell_next_fork_epoch = UINT64_MAX; /* the epoch of the fork after the runner's in the node's config */
static int main_db = -1; /* the node of a fork_choice case in node mode: 1 with NODE_FLAG_DB, every second case; -1 others */
static struct node_shell *shell_open(fc_node *n, tv parts, uint8_t **anchor_block, const char **why) {
    memset(n, 0, sizeof *n);
    struct node_shell *s = calloc(1, sizeof *s);
    if (!s) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    gshare_forget(s);
    n->shell = s;
    *anchor_block = fc_setup(n, parts, why);
    if (*anchor_block) {
        /* Small capacities, so that the node grows through lantern_node_copy. */
        uint8_t anchor[NODE_ANCHOR_SIZE] = {0}; /* NodeAnchor: root, slot, genesis_validators_root, jwt_secret, engine_host_len, engine_host, node_id, history_slot, builder_host_len, builder_host, archive_slots */
        static unsigned long opened; /* every second node archives to a Db */
        int force_db = bf_state != NULL || drop_room; /* the backfill's and the drop check's nodes archive to a Db */
        /* every second node archives to a Db; every second pair keeps few post-states and rebuilds the others */
        int db = main_db >= 0 ? main_db || force_db : opened % 2 || force_db;
        uint64_t flags = (FORK >= FORK_BELLATRIX ? NODE_FLAG_ENGINE : 0) | NODE_FLAG_DISCV5 | (db ? NODE_FLAG_DB : 0) |
                         (opened / 2 % 2 ? NODE_FLAG_FEW_STATES : 0) | (force_supernode ? NODE_FLAG_SUPERNODE : 0), need = 0;
        opened++;
        for (int i = 0; i < NODE_ROOM_FIELDS; i++) s->room[i] = 2;
        s->room[2] = 1;
        s->room[9] = 4096; /* the execution engine's answers */
        s->room[13] = 16;  /* the pool: every operation of a case's pool requests */
        if (drop_room) { /* the drop check: a Db of three segments */
            s->room[10] = 3 * 8192;
            s->room[11] = 64;
        }
        memset(anchor + 72, 0x42, 32);
        wr64(anchor + 104, strlen(ENGINE_HOST));
        memcpy(anchor + 112, ENGINE_HOST, strlen(ENGINE_HOST));
        if (force_eth1) { /* the eth1 follower on the runner's chain, with the room of its window */
            flags |= NODE_FLAG_ENGINE | NODE_FLAG_ETH1;
            s->room[15] = 8192;
            s->room[16] = 2048;
        }
        if (flags & NODE_FLAG_DB) /* a state record each epoch of finality (node.md, the archive) */
            wr64(anchor + 288, strcmp(PRESET, "minimal") ? 32 : 8);
        if (force_builder) { /* the runner is the node's builder too */
            flags |= NODE_FLAG_BUILDER;
            wr64(anchor + 216, strlen(BUILDER_HOST));
            memcpy(anchor + 224, BUILDER_HOST, strlen(BUILDER_HOST));
        }
        s->seen_room[0] = s->seen_room[1] = s->seen_room[2] = 1;
        s->seen_room[3] = 64;
        shell_seen(s, why);
        root_of("BeaconBlock", *anchor_block, anchor, why);
        wr64(anchor + 32, rd64(*anchor_block + field_offset("BeaconBlock", 0)));
        memcpy(anchor + 40, n->anchor + field_offset("BeaconState", 1), 32);
        if (!*why) peer_node_id(anchor + 176, why); /* the node's columns hold the peer's custody columns */
        if (!*why && CALL(lantern_node_size, s->room, &need) != 0) *why = "lantern_node_size status";
        if (!*why) {
            s->node = buffer(need);
            s->node_size = need;
            wr64(s->node, need);
            /* The node picks the fork of a slot by the fork epochs: this runner's fork and the ones before at genesis. */
            uint8_t ncfg[CONFIG_SIZE];
            memcpy(ncfg, config, CONFIG_SIZE);
            for (uint64_t f = FORK_ALTAIR; f <= FORK_FULU; f++)
                wr64(ncfg + 16 * f, f <= FORK ? 0 : f == FORK + 1 ? shell_next_fork_epoch : UINT64_MAX);
            memcpy(s->anchor, anchor, sizeof s->anchor);
            memcpy(s->ncfg, ncfg, CONFIG_SIZE);
            s->flags = flags;
            if (CALL(lantern_node_init, s->room, ncfg, anchor, &flags, s->node) != 0) *why = "lantern_node_init status";
            else if (!guard_ok(s->node, need)) *why = "lantern_node_init wrote out of bounds";
            else if (memcmp(s->node + NODE_HEAD_ROOT, anchor, 32)) *why = "lantern_node_init: the head is not the anchor";
        }
        s->actions_size = 256;
        s->actions = buffer(s->actions_size);
        wr64(s->actions, s->actions_size);
        if (!*why) shell_keep(s, 1, copy_of(n->anchor, n->anchor_size), n->anchor_size, why);
        if (!*why) shell_lc(s, n->anchor, *anchor_block, why);
    }
    return s;
}

static void shell_close(fc_node *n, uint8_t *anchor_block) {
    struct node_shell *s = n->shell;
    free(s->api.b);
    free(s->bld);
    for (int e = 0; e < s->nev; e++) free(s->ev[e].b);
    free(s->seen);
    for (size_t k = 0; k < s->nbufs; k++) free(s->bufs[k].b);
    free(s->bufs);
    free(s->pending);
    free(s->node);
    free(s->actions);
    for (size_t k = 0; k < s->nsegs; k++) free(s->segs[k].b);
    free(s);
    free(n->store);
    free(n->anchor);
    free(anchor_block);
}

static void fc_serve_check(fc_node *n, tv parts, const char **why);
static void fc_reads_check(fc_node *n, const char **why);
static void fc_sync_check(tv parts, const char **why);
static void shell_api_head(fc_node *n, const char **why);
static void api_lookup_checks(fc_node *n, tv parts, const char **why);
static void drop_check(tv parts, const char **why);

static uint64_t http_request_call(const uint8_t *b, uint64_t len, const uint64_t *limits, uint64_t osize, uint8_t **out,
                                  uint64_t *http, const char **why);

#define HTTP_REQUEST_FIXED 144

/* The event streams of a node-events case (docs/reference/node.md, Test vectors): the request and head of each. */
static const char *const ev_requests[3] = {
    "GET /eth/v1/events?topics=head,head_v2,block,finalized_checkpoint HTTP/1.1\r\nHost: lantern\r\nAccept: text/event-stream\r\n\r\n",
    "GET /eth/v1/events?topics=block,chain_reorg HTTP/1.0\r\nHost: lantern\r\n\r\n",
    "GET /eth/v1/events?topics=finalized_checkpoint,head,block HTTP/1.1\r\nHost: lantern\r\n\r\n"};
static const char *const ev_heads[3] = {
    "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\n\r\n",
    "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n",
    "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\n\r\n"};

/* The three event streams opened: each must get its head, with last 0. */
static void ev_open(fc_node *n, const char **why) {
    static const uint64_t limits[2] = {16384, 1048576};
    struct node_shell *s = n->shell;
    for (int e = 0; e < 3 && !*why; e++) {
        uint64_t len = strlen(ev_requests[e]), http = 0, osize = (HTTP_REQUEST_FIXED + 2 * len + 64 + 7) & ~(uint64_t)7;
        uint8_t *out = NULL;
        memset(&s->ev[e], 0, sizeof s->ev[e]);
        s->ev[e].conn = (uint64_t)(0x100 + e) | (uint64_t)99 << 32;
        s->ev[e].nosent = e == 2;
        s->nev = e + 1;
        if (http_request_call((const uint8_t *)ev_requests[e], len, limits, osize, &out, &http, why) != 0 && !*why)
            *why = "an event stream: lantern_http_request";
        if (!*why) {
            shell_event(s, EV_API, s->ev[e].conn, out, rd64(out));
            shell_settle(n, why);
        }
        free(out);
        uint64_t hlen = strlen(ev_heads[e]);
        if (!*why && (s->ev[e].len != hlen || memcmp(s->ev[e].b, ev_heads[e], (size_t)hlen) || s->ev[e].lasts || s->ev[e].closes ||
                      s->ev[e].late))
            *why = "an event stream: not its head, with last 0";
        s->ev[e].seen = s->ev[e].total = s->ev[e].len;
    }
}

/* An event stream on ev[e] of the request bytes req: its head and the events after it collect there. */
static void ev_open_one(fc_node *n, int e, const uint8_t *req, uint64_t len, const char **why) {
    static const uint64_t limits[2] = {16384, 1048576};
    struct node_shell *s = n->shell;
    uint64_t http = 0, osize = (HTTP_REQUEST_FIXED + 2 * len + 64 + 7) & ~(uint64_t)7;
    uint8_t *out = NULL;
    memset(&s->ev[e], 0, sizeof s->ev[e]);
    s->ev[e].conn = (uint64_t)(0x100 + e) | (uint64_t)99 << 32;
    if (s->nev < e + 1) s->nev = e + 1;
    if (http_request_call(req, len, limits, osize, &out, &http, why) != 0 && !*why) *why = "an event stream: lantern_http_request";
    if (!*why) {
        shell_event(s, EV_API, s->ev[e].conn, out, rd64(out));
        shell_settle(n, why);
    }
    free(out);
}

/* The bytes of the open stream ev[e] must be want; then its client goes and the node settles. */
static void ev_stream_end(fc_node *n, int e, const uint8_t *want, uint64_t wlen, const char *what, const char **why) {
    struct node_shell *s = n->shell;
    if (s->ev[e].len != wlen || memcmp(s->ev[e].b, want, (size_t)wlen) || s->ev[e].lasts || s->ev[e].closes || s->ev[e].late) {
        static char msg[1024];
        uint64_t at = 0;
        while (at < s->ev[e].len && at < wlen && s->ev[e].b[at] == want[at]) at++;
        snprintf(msg, sizeof msg, "%s: the event stream differs at byte %llu of %llu (case %llu), lasts %llu, closes %llu: got %.*s",
                 what, (unsigned long long)at, (unsigned long long)s->ev[e].len, (unsigned long long)wlen,
                 (unsigned long long)s->ev[e].lasts, (unsigned long long)s->ev[e].closes,
                 (int)(s->ev[e].len - at < 400 ? s->ev[e].len - at : 400), s->ev[e].b ? (const char *)s->ev[e].b + at : "");
        *why = msg;
        return;
    }
    shell_event(s, EV_API_CLOSED, s->ev[e].conn, NULL, 0);
    s->ev[e].gone = 1;
    shell_settle(n, why);
}

/* The topic of the event text at t: its name after "event: ". */
static int ev_topic_is(const uint8_t *t, uint64_t len, const char *topic) {
    size_t k = strlen(topic);
    return len > 7 + k && !memcmp(t, "event: ", 7) && !memcmp(t + 7, topic, k) && t[7 + k] == '\n';
}

/* Each stream's bytes of a step: the step's texts of its topics, each in one chunk over HTTP/1.1; the third closes when its bytes would pass NODE_API_CHUNK. */
static void ev_step_check(struct node_shell *s, tv texts, const char **why) {
    uint64_t tlen;
    const uint8_t *t = tv_bytes(texts, &tlen);
    for (int e = 0; e < s->nev && !*why; e++) {
        uint8_t *want = buffer(tlen + 1), *got = buffer(s->ev[e].len - s->ev[e].seen + 1);
        uint64_t wlen = 0, glen = 0, close_now = 0;
        for (uint64_t at = 0; at < tlen && !s->ev[e].closed;) { /* the step's texts, each to its "\n\n" */
            uint64_t end = at;
            while (end + 1 < tlen && !(t[end] == '\n' && t[end + 1] == '\n')) end++;
            end += 2;
            const uint8_t *x = t + at;
            uint64_t xl = end - at;
            at = end;
            if (e == 1 && !ev_topic_is(x, xl, "block") && !ev_topic_is(x, xl, "chain_reorg")) continue;
            if (e != 1 && ev_topic_is(x, xl, "chain_reorg")) continue;
            if (e == 2 && ev_topic_is(x, xl, "head_v2")) continue; /* the third stream names head, not head_v2 */
            if (e == 2 && s->ev[e].total + xl + 8 > NODE_API_CHUNK) { /* falls behind: a close in place of it */
                close_now = 1;
                s->ev[e].closed = 1;
                break;
            }
            if (e == 2) s->ev[e].total += xl + 8;
            memcpy(want + wlen, x, (size_t)xl);
            wlen += xl;
        }
        const uint8_t *b = s->ev[e].b + s->ev[e].seen;
        uint64_t blen = s->ev[e].len - s->ev[e].seen;
        if (e == 1) { /* HTTP/1.0: the bytes as they are */
            memcpy(got, b, (size_t)blen);
            glen = blen;
        } else
            for (uint64_t at = 0; at < blen && !*why;) { /* a chunk: 4 lower case hex digits, CRLF, the bytes, CRLF */
                uint64_t size = 0;
                for (int d = 0; d < 4; d++) {
                    uint8_t c = at + (uint64_t)d < blen ? b[at + (uint64_t)d] : 0;
                    if (c >= '0' && c <= '9') size = size * 16 + (uint64_t)(c - '0');
                    else if (c >= 'a' && c <= 'f') size = size * 16 + (uint64_t)(c - 'a' + 10);
                    else *why = "an event stream: a chunk's size is not 4 lower case hex digits";
                }
                if (!*why && (at + 6 + size + 2 > blen || memcmp(b + at + 4, "\r\n", 2) || memcmp(b + at + 6 + size, "\r\n", 2) || !size))
                    *why = "an event stream: a broken chunk";
                if (!*why) {
                    memcpy(got + glen, b + at + 6, (size_t)size);
                    glen += size;
                }
                at += 6 + size + 2;
            }
        if (!*why && (glen != wlen || memcmp(got, want, (size_t)wlen))) {
            static char msg[1400];
            uint64_t k = 0;
            while (k < glen && k < wlen && got[k] == want[k]) k++;
            snprintf(msg, sizeof msg, "event stream %d: the step's events differ at byte %llu (got %llu, want %llu): got %.*s want %.*s", e,
                     (unsigned long long)k, (unsigned long long)glen, (unsigned long long)wlen, (int)(glen - k < 500 ? glen - k : 500),
                     (const char *)got + k, (int)(wlen - k < 500 ? wlen - k : 500), (const char *)want + k);
            *why = msg;
        }
        if (!*why && (s->ev[e].lasts || s->ev[e].late || s->ev[e].closes != (uint64_t)s->ev[e].closed))
            *why = close_now ? "event stream 2: no close where it falls behind" : "event stream: a last, a late action or a close";
        s->ev[e].seen = s->ev[e].len;
        free(want);
        free(got);
    }
}

/* After the case: each stream's client goes; the node must hold no NodeApi entry and send nothing more. */
static void ev_close(fc_node *n, const char **why) {
    struct node_shell *s = n->shell;
    for (int e = 0; e < s->nev; e++)
        if (!s->ev[e].closed) {
            shell_event(s, EV_API_CLOSED, s->ev[e].conn, NULL, 0);
            s->ev[e].gone = 1;
        }
    shell_settle(n, why);
    for (int e = 0; e < s->nev && !*why; e++)
        if (s->ev[e].len != s->ev[e].seen || s->ev[e].late) *why = "an event stream: an action after its end";
    if (!*why && rd64(s->node + NODE_API_PART + 8)) *why = "the node holds a NodeApi entry after its event streams end";
    s->nev = 0;
    for (int e = 0; e < 3; e++) {
        free(s->ev[e].b);
        memset(&s->ev[e], 0, sizeof s->ev[e]);
    }
}

/* One case through the node: the shell's buffers, then each step as events; with serve, then fc_serve_check. */
/*
 * A NODE_WORK_ATTESTER_SLASHING of the bytes with no state_a, as when the justified root has no
 * post-state (node.md): lantern_node_run must give LANTERN_OK, the result LANTERN_NEED_JUSTIFIED_STATE
 * and leave the store and the node unchanged.
 */
static void slashing_no_state_check(fc_node *n, const uint8_t *bytes, uint64_t len, const char **why) {
    struct node_shell *s = n->shell;
    uint8_t work[72] = {0};
    wr64(work, 72);
    wr64(work + 8, 5); /* NODE_ACT_WORK */
    wr64(work + 16, WORK_ATTESTER_SLASHING);
    uint8_t *data = serialized(bytes, len, &(uint64_t){0}), *ev = buffer(EV_WORK_DONE_SIZE);
    uint8_t *snode = copy_of(s->node, s->node_size), *sstore = copy_of(n->store, n->size);
    wr64(ev, EV_WORK_DONE_SIZE);
    const void *settings = NULL;
#if FORK >= FORK_DENEB
    settings = kzg_settings;
#endif
    uint64_t st = CALL(lantern_node_run, s->node, n->store, s->seen, work, NULL, NULL, NULL, data, settings, fresh_scratch(), ev);
    if (st != 0) *why = "an attester slashing work with no state: status not 0";
    else if (rd64(ev + EV_RESULT) != 41) *why = "an attester slashing work with no state: not LANTERN_NEED_JUSTIFIED_STATE";
    else if (memcmp(sstore, n->store, (size_t)n->size) || memcmp(snode, s->node, (size_t)s->node_size))
        *why = "an attester slashing work with no state: the store or the node changed";
    free(data);
    free(ev);
    free(snode);
    free(sstore);
}

static void fc_node_case(tv parts, int serve, const char **why) {
    fc_node n;
    uint8_t *anchor_block;
    static unsigned long main_opened;
    main_db = (int)(main_opened++ % 2);
    struct node_shell *s = shell_open(&n, parts, &anchor_block, why);
    main_db = -1;
    tv steps = tv_get(parts, "steps");
    tv st = steps ? steps + 9 : NULL;
    tv evs = NULL; /* the texts of each step, from the node-events case */
    if (case_events && !*why) {
        tv list = tv_get(case_events, "events");
        if (!list || rd64(list + 1) != (steps ? rd64(steps + 1) : 0)) *why = "the node-events case has not a text for each step";
        else {
            evs = list + 9;
            ev_open(&n, why);
        }
    }
    for (uint64_t k = 0, c = steps ? rd64(steps + 1) : 0; k < c && !*why; k++, st = tv_skip(st)) {
        tv v = tv_get(st, "valid");
        int valid = !v || (*v == T_BOOL && v[1]);
        if (tv_get(st, "tick")) {
            uint64_t secs = tv_u64(tv_get(st, "tick")), ms = secs > UINT64_MAX / 1000 ? UINT64_MAX : secs * 1000;
            shell_event(s, EV_TICK, ms, NULL, 0);
            shell_settle(&n, why);
        } else if (tv_get(st, "block")) {
            shell_block_step(&n, parts, st, why);
        } else if (tv_get(st, "attestation") || tv_get(st, "attester_slashing") || tv_get(st, "pow_block")) {
            int att = tv_get(st, "attestation") != NULL, pow = tv_get(st, "pow_block") != NULL;
            tv nm = tv_get(st, att ? "attestation" : pow ? "pow_block" : "attester_slashing");
            char key[128];
            uint64_t olen;
            snprintf(key, sizeof key, "%.*s", (int)rd64(nm + 1), (const char *)(nm + 9));
            const uint8_t *bytes = tv_bytes(tv_get(parts, key), &olen);
            if (!att && !pow) slashing_no_state_check(&n, bytes, olen, why);
            s->nresults[0] = s->nresults[1] = 0;
            shell_event(s, att ? EV_ATTESTATION : pow ? EV_POW_BLOCK : EV_ATTESTER_SLASHING, 0, bytes, olen);
            shell_settle(&n, why);
            if (!*why && !pow) {
                size_t r = att ? 0 : 1;
                if (s->nresults[r] != 1) *why = att ? "attestation: not one result" : "attester_slashing: not one result";
                else if ((s->results[r][0] == 0) != valid) *why = att ? "attestation: result" : "attester_slashing: result";
            }
        } else if (tv_get(st, "checks")) {
            fc_checks(&n, tv_get(st, "checks"), why);
        } else if (tv_get(st, "payload_status")) {
            fc_payload_step(&n, st, why); /* the runner's execution engine answers with it from now on */
        } else {
            *why = "unknown step";
        }
        if (!*why && !guard_ok(scratch_buf, SCRATCH_BYTES)) *why = "wrote past the scratch";
        if (evs && !*why) {
            ev_step_check(s, evs, why);
            evs = tv_skip(evs);
        }
        if (*why) {
            static char msg[1600];
            snprintf(msg, sizeof msg, "step %llu: %s", (unsigned long long)k, *why);
            *why = msg;
        }
    }
    if (s->nev && !*why) ev_close(&n, why);
    if (!*why) shell_db_rescan(n.shell, why);
    if (serve && !*why) shell_api_head(&n, why);
    if (serve && !*why) api_lookup_checks(&n, parts, why);
    if (serve && !*why) fc_reads_check(&n, why);
    if (serve && !*why) fc_serve_check(&n, parts, why);
    if (serve && !*why) fc_sync_check(parts, why);
    static int dropped; /* once in each process */
    if (serve && !*why && !dropped++) drop_check(parts, why);
    shell_close(&n, anchor_block);
}


#if FORK > FORK_PHASE0
/*
 * transition/core through the node (node.md, Test vectors): the node starts at lantern_node_anchor of
 * the fork before of pre, with the runner's fork at fork_epoch in its config; each block goes in a
 * BLOCK event after a TICK of its slot and must be imported; then the head must be the last block and
 * the post-state the node keeps for it the case's post. *ran is 0 when that node_anchor refuses pre.
 */
static unsigned long node_transitions;
static void transition_node_case(tv parts, uint64_t fork_epoch, int *ran, const char **why) {
    uint64_t plen, lsize, need = 0, vsize = 0, qlen, st;
    const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen), *post = tv_bytes(tv_get(parts, "post"), &qlen);
    const uint8_t *pstate = type_in(LP(types), "BeaconState"), *pblock = type_in(LP(types), "BeaconBlock");
    *ran = 0;
    uint8_t *value = decode(pstate, pre, plen, &vsize, why);
    if (!value) return;
    uint64_t room[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}; /* StateRoom: docs/reference/state.md */
    CALL(LP(beacon_state_copy_size), value, room, &need);
    free(value);
    need += 4096;
    uint8_t *data = list_of(pre, plen, 0, 0, &lsize), *state = buffer(need), *block = buffer(ANCHOR_BLOCK_BYTES);
    wr64(state, need);
    wr64(block, ANCHOR_BLOCK_BYTES);
    st = CALL(LP(node_anchor), data, room, fresh_scratch(), state, block);
    free(data);
    /* A pre past the slot of its latest block header is no anchor: get_forkchoice_store needs that block's post-state. */
    uint64_t hslot = rd64(state + field_offset("BeaconState", 4));
    if (st == INVALID_ANCHOR || (st == 0 && rd64(state + 48) != hslot)) {
        free(state);
        free(block);
        return;
    }
    *ran = 1;
    node_transitions++;
    /* The config: each fork before the runner's at epoch 0, the runner's at fork_epoch, the later ones never. */
    uint8_t ncfg[CONFIG_SIZE];
    memcpy(ncfg, config, CONFIG_SIZE);
    for (uint64_t f = FORK_ALTAIR; f <= FORK_FULU; f++) wr64(ncfg + 16 * f, f < FORK ? 0 : f == FORK ? fork_epoch : UINT64_MAX);
    fc_node n;
    memset(&n, 0, sizeof n);
    n.anchor = state;
    n.anchor_size = need;
    struct node_shell *s = calloc(1, sizeof *s);
    if (!s) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    gshare_forget(s);
    n.shell = s;
    if (st != 0) *why = "node_anchor of the fork before: status not 0";
    uint64_t sroom[2] = {2, 1}, sneed = 0; /* the store: get_forkchoice_store of the fork before */
    CALL(lantern_store_size, sroom, &sneed);
    n.store = buffer(sneed);
    n.size = sneed;
    wr64(n.store, sneed);
    while (!*why && (st = CALL(LP(get_forkchoice_store), state, block, ncfg, sroom, fresh_scratch(), n.store)) == 1 &&
           sroom[1] < (1u << 24)) {
        sroom[1] *= 2;
        CALL(lantern_store_size, sroom, &sneed);
        free(n.store);
        n.store = buffer(sneed);
        n.size = sneed;
        wr64(n.store, sneed);
    }
    if (!*why && st != 0) {
        static char smsg[80];
        snprintf(smsg, sizeof smsg, "get_forkchoice_store of the fork before: status %llu", (unsigned long long)st);
        *why = smsg;
    }
    uint8_t anchor[NODE_ANCHOR_SIZE] = {0}, *scr = NULL;
    uint64_t flags = NODE_FLAG_DISCV5, scsize;
    if (!*why) { /* the node: as shell_open's, with no execution engine and no Db */
        for (int i = 0; i < NODE_ROOM_FIELDS; i++) s->room[i] = 2;
        s->room[2] = 1;
        s->room[9] = 4096;
        s->room[13] = 16;
        memset(anchor + 72, 0x42, 32);
        s->seen_room[0] = s->seen_room[1] = s->seen_room[2] = 1;
        s->seen_room[3] = 64;
        shell_seen(s, why);
        scr = scratch_for(pblock, &scsize);
        if (ssz_hash_tree_root(pblock, block, scr, anchor) != 0) *why = "the anchor block's root: status";
        free(scr);
        wr64(anchor + 32, rd64(block + field_offset("BeaconBlock", 0)));
        memcpy(anchor + 40, state + field_offset("BeaconState", 1), 32);
        if (!*why) peer_node_id(anchor + 176, why);
        if (!*why && CALL(lantern_node_size, s->room, &sneed) != 0) *why = "lantern_node_size status";
    }
    if (!*why) {
        s->node = buffer(sneed);
        s->node_size = sneed;
        wr64(s->node, sneed);
        memcpy(s->anchor, anchor, sizeof s->anchor);
        memcpy(s->ncfg, ncfg, CONFIG_SIZE);
        s->flags = flags;
        if (CALL(lantern_node_init, s->room, ncfg, anchor, &flags, s->node) != 0) *why = "lantern_node_init status";
        s->actions_size = 256;
        s->actions = buffer(s->actions_size);
        wr64(s->actions, s->actions_size);
        if (!*why) shell_keep(s, 1, copy_of(state, need), need, why);
        if (!*why) shell_lc(s, state, block, why);
    }
    tv meta = tv_get(parts, "meta");
    uint64_t blocks = tv_u64(tv_get(meta, "blocks_count")), genesis = rd64(state + field_offset("BeaconState", 0));
    uint64_t slot_ms = rd64(ncfg + 104), per_epoch = strcmp(PRESET, "minimal") ? 32 : 8;
    uint8_t root[32] = {0};
#if FORK == FORK_BELLATRIX
    uint8_t pow_hash[32];
    int pow_sent = 0;
#endif
    for (uint64_t b = 0; b < blocks && !*why; b++) {
        char key[32];
        snprintf(key, sizeof key, "blocks_%llu", (unsigned long long)b);
        uint64_t blen;
        const uint8_t *enc = tv_bytes(tv_get(parts, key), &blen);
        uint64_t at = blen >= 4 ? (enc[0] | (uint64_t)enc[1] << 8 | (uint64_t)enc[2] << 16 | (uint64_t)enc[3] << 24) : blen;
        if (at + 8 > blen) {
            *why = "a block is too short";
            break;
        }
        uint64_t slot = 0;
        for (int k = 7; k >= 0; k--) slot = slot << 8 | enc[at + k];
        const uint8_t *desc = slot / per_epoch >= fork_epoch ? type_by_name("BeaconBlock") : pblock;
        uint8_t *msg = decode(desc, enc + at, blen - at, &vsize, why);
        if (!msg) break;
        scr = scratch_for(desc, &scsize);
        if (ssz_hash_tree_root(desc, msg, scr, root) != 0) *why = "a block's root: status";
        free(scr);
        free(msg);
        shell_event(s, EV_TICK, genesis * 1000 + slot * slot_ms, NULL, 0);
        shell_settle(&n, why);
#if FORK == FORK_BELLATRIX
        /*
         * The merge: each payload's parent_hash gets a terminal PoW block of that hash, of total difficulty
         * TERMINAL_TOTAL_DIFFICULTY, and its parent below it, as the fork_choice files' pow_block steps give
         * (validate_merge_block); the case gives none.
         */
        if (!*why && slot / per_epoch >= fork_epoch) {
            uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), enc, blen, &vsize, why);
            if (sb) {
                const uint8_t *m = nested(sb, field_offset("SignedBeaconBlock", 0));
                const uint8_t *body = nested(m, field_offset("BeaconBlock", 4));
                const uint8_t *payload = nested(body, field_offset("BeaconBlockBody", 9));
                const uint8_t *phash = payload + field_offset("ExecutionPayload", 0);
                if (!pow_sent || memcmp(phash, pow_hash, 32)) {
                    pow_sent = 1;
                    memcpy(pow_hash, phash, 32);
                    uint8_t pow[96], parent[96];
                    memcpy(pow, phash, 32);
                    memset(pow + 32, 0x5a, 32);
                    memcpy(pow + 64, config + 392 + 16 * 32 + 32, 32); /* TERMINAL_TOTAL_DIFFICULTY, little endian */
                    memcpy(parent, pow + 32, 32);
                    memset(parent + 32, 0, 32);
                    memcpy(parent + 64, pow + 64, 32);
                    for (int k = 0; k < 32 && !(parent[64 + k]--); k++) { /* minus 1, with the borrow */ }
                    shell_event(s, EV_POW_BLOCK, 0, pow, sizeof pow);
                    shell_event(s, EV_POW_BLOCK, 0, parent, sizeof parent);
                    shell_settle(&n, why);
                }
                free(sb);
            }
        }
#endif
        if (!*why) {
            shell_event(s, EV_BLOCK, 1, enc, blen);
            shell_settle(&n, why);
        }
        const uint8_t *e = *why ? NULL : shell_block(s, root);
        if (!*why && (!e || rd64(e + NB_STATUS) != NB_IMPORTED)) {
            static char msg2[96];
            snprintf(msg2, sizeof msg2, "block %llu: not imported, node status %llu, result %llu", (unsigned long long)b,
                     e ? (unsigned long long)rd64(e + NB_STATUS) : 0ull, e ? (unsigned long long)rd64(e + 104) : 0ull);
            *why = msg2;
        }
    }
    if (!*why && blocks && memcmp(s->node + NODE_HEAD_ROOT, root, 32)) *why = "the head is not the last block";
    if (!*why && blocks) {
        const uint8_t *e = shell_block(s, root);
        shell_buf *h = e ? shell_find(s, rd64(e + NB_STATE_ID)) : NULL;
        if (!h) *why = "the head has no post-state";
        else state_equals(h->b, post, qlen, why);
    }
    if (!*why) { /* node-reads: the rewards of the anchor and of the blocks (tests/generator/node.py) */
        if (!case_reads) *why = "no node-reads case of the case";
        else fc_reads_check(&n, why);
    }
    if (!*why && !guard_ok(scratch_buf, SCRATCH_BYTES)) *why = "wrote past the scratch";
    shell_close(&n, block);
}
#endif

/* ---------------------------------------------------------------- Node over libp2p */

/*
 * node-p2p: the node of a case and a bare asm-libp2p peer in memory, with the runner as the
 * network between them, as tests/runner of asm-libp2p does. The peer dials the node, then asks
 * for Status, Ping and MetaData and says Goodbye. The answers must be the case's.
 */

/* asm-libp2p at the pin of platform/deps.sh: the entry points, and the values of include/libp2p.inc used here. */
ABI uint64_t libp2p_state_size(const void *config, void *size);
ABI uint64_t libp2p_init(const void *config, void *state);
ABI uint64_t libp2p_step(void *state, const void *tick, const void *events, void *scratch, void *actions, void *result);
/* asm-discv5 at the pin of platform/deps.sh: the peer's node record. */
ABI uint64_t discv5_init(const void *config, void *state);
ABI uint64_t discv5_step(void *state, const void *tick, const void *events, void *scratch, void *actions);
ABI uint64_t discv5_local_record(const void *state, void *record);
#define DISCV5_STATE_SIZE 245392
#define DISCV5_SCRATCH_SIZE 65536
#define DISCV5_ACTIONS_ROOM (24 + 32768 + 2 * 16384) /* the ByteList header, then DISCV5_ACTIONS_BASE + 2 events */
#define P2P_CFG_FIXED 776
#define P2P_PROTO_SIZE 136
#define P2P_SCRATCH_SIZE 608928
#define P2P_ACTIONS_MIN 1056768
#define P2P_RECEIVE_MAX 65536
#define P2P_ST_PEER_ID_LEN 152 /* include/state.inc */
#define P2P_ST_PEER_ID 160
enum { P2P_EV_ACCEPTED = 1, P2P_EV_CONNECTED, P2P_EV_DIAL_FAILED, P2P_EV_RECEIVED, P2P_EV_SENT, P2P_EV_CLOSED, P2P_EV_DIAL,
       P2P_EV_DISCONNECT, P2P_EV_OPEN_STREAM, P2P_EV_STREAM_WRITE, P2P_EV_STREAM_CLOSE, P2P_EV_STREAM_RESET };
enum { P2P_ACT_DIAL = 1, P2P_ACT_ADOPT, P2P_ACT_REFUSE, P2P_ACT_SEND, P2P_ACT_CLOSE, P2P_ACT_WAKEUP, P2P_ACT_PEER_CONNECTED,
       P2P_ACT_PEER_DISCONNECTED, P2P_ACT_DIAL_FAILED, P2P_ACT_STREAM_INBOUND, P2P_ACT_STREAM_OPENED, P2P_ACT_STREAM_FAILED,
       P2P_ACT_STREAM_DATA, P2P_ACT_STREAM_EOF, P2P_ACT_STREAM_RESET, P2P_ACT_SEND_DATAGRAM = 23 };
#define NODE_PEERS 120          /* include/lantern.inc: Node_peers */
#define NODE_PEER_BYTES 240     /* NodePeer__mem */
#define NODE_PEER_STATUS_MS 232 /* NodePeer_status_ms */
#define P2P_STREAMS 8
#define P2P_PEER_ACTIONS (P2P_ACTIONS_MIN + (4u << 20))

/* The network: side 0 is the node's libp2p state, side 1 the peer's. */
/* SLOTS_PER_EPOCH of the preset (presets/<preset>/phase0.yaml). */
#define SLOTS_PER_EPOCH_RUNNER (strcmp(PRESET, "minimal") ? 32u : 8u)
#define MAX_REQUEST_LIGHT_CLIENT_UPDATES_RUNNER 128 /* MAX_REQUEST_LIGHT_CLIENT_UPDATES, of both presets */

/* A block of a case: its root, parent root, slot and SSZ bytes. */
typedef struct {
    uint8_t root[32], parent[32];
    uint64_t slot, len;
    const uint8_t *bytes;
    tv sidecars; /* deneb, electra: the list of its BlobSidecars of the case's node-blobs case, or NULL */
    tv columns;  /* fulu: the names of its DataColumnSidecar parts of the case, its step's columns, or NULL */
} case_block;

/* deneb, electra: the node-blobs case of the fork choice case that runs, or NULL. */
static tv case_blobs;

struct p2p_net {
    struct node_shell *shell;
    case_block **chain; /* with a chain, the peer serves BeaconBlocksByRange and BlobSidecarsByRange of it */
    size_t nchain;
    int no_blobs;          /* the peer answers BlobSidecarsByRange and DataColumnSidecarsByRange with no sidecar */
    int half_columns;      /* the peer answers DataColumnSidecarsByRange with the even columns only */
    int cut;               /* 1: its next BeaconBlocksByRange answer of 3 blocks or more leaves out the second; 2: the next of 2 or more holds the first only */
    uint64_t blobs_sent;   /* the sidecars it sent */
    tv parts;              /* fulu: the case, whose parts hold the column sidecars */
    uint64_t peer_cgc;     /* the custody_group_count of the peer's MetaData */
    uint8_t want_columns[16]; /* the columns each DataColumnSidecarsByRange of the node must ask for */
    uint64_t column_requests; /* the node's DataColumnSidecarsByRange requests */
    uint64_t column_floor;    /* fulu: a DataColumnSidecarsByRange may start at this slot or later: the peer's earliest_available_slot */
    uint64_t skip_column;     /* fulu: 1 + a column the peer leaves out of its answers, or 0 */
    uint8_t extra_columns[16]; /* fulu: columns the peer adds to its answers, asked or not */
    uint8_t retry_columns[16]; /* fulu: the columns a request may ask for instead of want_columns: a retry's */
    int drop_dials;           /* set: the node's dials reach no one; dials counts them */
    int silent;               /* set: the peer answers no BeaconBlocksByRange; held is set once it holds one */
    int silent_status;        /* set: the peer answers no Status request; held is set once it holds one */
    int held;
    uint64_t in_resets;       /* the node's request streams to the peer that the node reset */
    uint64_t dials, closes;   /* closes: the connections the node closed */
    uint8_t protos[64 * P2P_PROTO_SIZE]; /* the protocol list of both sides */
    uint64_t nprotos;
    uint8_t gvr[32];
    struct {
        uint64_t handle, proto;
        int eof;
        uint8_t *data;
        uint64_t len;
    } in[P2P_STREAMS]; /* the node's streams to the peer, and their protocol index */
    uint8_t *state[2], *scratch, *actions, *events; /* the peer's scratch, actions and events */
    uint64_t events_len, now, conn[2], dial_conn, token, node_handle;
    int connected, topics, untopics; /* the topics the node joined, and left */
    int dial_side;            /* the side whose DIAL is open */
    uint8_t status[96];       /* the Status the peer answers with */
    uint64_t status_len;
    struct {
        uint64_t tag, handle;
        int opened, eof, reset, failed;
        uint8_t *data;
        uint64_t len;
    } st[P2P_STREAMS];
    int nlc;                     /* the light client gossip messages the peer got: their topics and data */
    char lc_topic[4][96];
    uint8_t *lc_data[4];
    uint64_t lc_len[4];
};

static void *p2p_state_of(struct p2p_net *net) { return net->state[0]; }

/* The tick of a side: the time of the network, entropy that depends on it. */
static void p2p_tick(struct p2p_net *net, int side, uint8_t *tick) {
    wr64(tick, net->now);
    for (int k = 0; k < 32; k++) tick[8 + k] = (uint8_t)(k * 13 + net->now + (uint64_t)side * 7);
    wr64(tick + 40, net->now * 1000);
    wr64(tick + 48, 1794700800 + net->now / 1000);
}

/* Room for a libp2p event of kind for a side, zeroed, its size and kind set: a NODE_EV_P2P for the node. */
static uint8_t *p2p_event(struct p2p_net *net, int side, uint64_t kind, uint64_t size) {
    size = (size + 7) & ~(uint64_t)7;
    uint8_t *e;
    if (side == 0) {
        uint8_t *w = shell_append(net->shell, 16 + size);
        memset(w, 0, (size_t)(16 + size));
        wr64(w, 16 + size);
        wr64(w + 8, EV_P2P);
        e = w + 16;
    } else {
        net->events = realloc(net->events, (size_t)(24 + net->events_len + size));
        if (!net->events) {
            fprintf(stderr, "out of memory\n");
            exit(2);
        }
        e = net->events + 24 + net->events_len;
        memset(e, 0, (size_t)size);
        net->events_len += size;
    }
    wr64(e, size);
    wr64(e + 8, kind);
    return e;
}

/* A shell request of a side, as a socket layer: the dial of the peer reaches the node. */
static void p2p_shell(struct p2p_net *net, int side, uint8_t *act, const char **why) {
    uint64_t kind = rd64(act + 8);
    if (kind == P2P_ACT_DIAL && side == 0 && net->drop_dials) { /* a dial of the node to no one */
        net->dials++;
        return;
    }
    if (kind == P2P_ACT_DIAL) { /* the other side accepts it */
        net->dial_side = side;
        net->dial_conn = rd64(act + 16);
        uint8_t *e = p2p_event(net, 1 - side, P2P_EV_ACCEPTED, 56);
        wr64(e + 16, ++net->token);
        wr64(e + 24, 4);
        wr64(e + 32, 40001);
        e[40] = 10;
        e[43] = (uint8_t)(2 - side);
    } else if (kind == P2P_ACT_ADOPT || kind == P2P_ACT_REFUSE) {
        if (side != 1 - net->dial_side || rd64(act + 16) != net->token) {
            *why = "an ADOPT or REFUSE of no dial";
            return;
        }
        if (kind == P2P_ACT_REFUSE) {
            uint8_t *e = p2p_event(net, net->dial_side, P2P_EV_DIAL_FAILED, 32);
            wr64(e + 16, net->dial_conn);
            wr64(e + 24, 104);
            return;
        }
        net->conn[side] = rd64(act + 24);
        net->conn[net->dial_side] = net->dial_conn;
        uint8_t *e = p2p_event(net, net->dial_side, P2P_EV_CONNECTED, 24);
        wr64(e + 16, net->dial_conn);
    } else if (kind == P2P_ACT_SEND) {
        uint64_t conn = rd64(act + 16), count = rd64(act + 24);
        if (conn != net->conn[side]) return;
        for (uint64_t at = 0; at < count; at += P2P_RECEIVE_MAX) {
            uint64_t k = count - at > P2P_RECEIVE_MAX ? P2P_RECEIVE_MAX : count - at;
            uint8_t *e = p2p_event(net, 1 - side, P2P_EV_RECEIVED, 32 + k);
            wr64(e + 16, net->conn[1 - side]);
            wr64(e + 24, k);
            memcpy(e + 32, act + 32 + at, (size_t)k);
        }
        uint8_t *e = p2p_event(net, side, P2P_EV_SENT, 32);
        wr64(e + 16, conn);
        wr64(e + 24, count);
    } else if (kind == P2P_ACT_CLOSE) {
        uint64_t conn = rd64(act + 16);
        if (side == 0) net->closes++;
        uint8_t *e = p2p_event(net, side, P2P_EV_CLOSED, 32);
        wr64(e + 16, conn);
        if (conn == net->conn[side]) {
            e = p2p_event(net, 1 - side, P2P_EV_CLOSED, 32);
            wr64(e + 16, net->conn[1 - side]);
            net->conn[0] = net->conn[1] = 0;
        }
    }
}

/* An application notice of the peer. */
static void p2p_peer_app(struct p2p_net *net, uint8_t *act) {
    uint64_t kind = rd64(act + 8);
    if (kind == P2P_ACT_PEER_CONNECTED) {
        net->node_handle = rd64(act + 16);
        net->connected = 1;
        return;
    }
    if (kind == 16) { /* MESSAGE: a light client one is kept (its data is at data_off of the peer's state) */
        uint64_t tlen = rd64(act + 48), dlen = rd64(act + 40);
        if (tlen < 96 && net->nlc < 4) {
            memcpy(net->lc_topic[net->nlc], act + 56, (size_t)tlen);
            net->lc_topic[net->nlc][tlen] = 0;
            if (strstr(net->lc_topic[net->nlc], "/light_client_")) {
                net->lc_data[net->nlc] = copy_of(net->state[1] + rd64(act + 32), dlen);
                net->lc_len[net->nlc++] = dlen;
            }
        }
        return;
    }
    if (kind == 19) { /* PEER_TOPIC: the node joins or leaves a topic */
        if (rd64(act + 24)) net->topics++;
        else net->untopics++;
        return;
    }
    if (kind == P2P_ACT_STREAM_INBOUND) {
        for (int k = 0; k < P2P_STREAMS; k++)
            if (!net->in[k].handle) {
                net->in[k].handle = rd64(act + 16);
                net->in[k].proto = rd64(act + 32);
                net->in[k].eof = 0;
                net->in[k].len = 0;
                return;
            }
        return;
    }
    for (int k = 0; k < P2P_STREAMS; k++) {
        if (!net->in[k].handle || net->in[k].handle != rd64(act + 16)) continue;
        if (kind == P2P_ACT_STREAM_DATA) {
            uint64_t count = rd64(act + 24);
            net->in[k].data = realloc(net->in[k].data, (size_t)(net->in[k].len + count + 1));
            if (!net->in[k].data) {
                fprintf(stderr, "out of memory\n");
                exit(2);
            }
            memcpy(net->in[k].data + net->in[k].len, act + 32, (size_t)count);
            net->in[k].len += count;
        } else if (kind == P2P_ACT_STREAM_EOF) net->in[k].eof = 1;
        else if (kind == P2P_ACT_STREAM_RESET) {
            net->in[k].handle = 0;
            net->in_resets++;
        }
        return;
    }
    for (int k = 0; k < P2P_STREAMS; k++) {
        if (kind == P2P_ACT_STREAM_OPENED && net->st[k].tag == rd64(act + 24) && !net->st[k].opened) {
            net->st[k].handle = rd64(act + 16);
            net->st[k].opened = 1;
            return;
        }
        if (kind == P2P_ACT_STREAM_FAILED && net->st[k].tag == rd64(act + 16) && !net->st[k].opened) {
            net->st[k].failed = 1;
            return;
        }
        if (!net->st[k].opened || net->st[k].handle != rd64(act + 16)) continue;
        if (kind == P2P_ACT_STREAM_DATA) {
            uint64_t count = rd64(act + 24);
            net->st[k].data = realloc(net->st[k].data, (size_t)(net->st[k].len + count + 1));
            if (!net->st[k].data) {
                fprintf(stderr, "out of memory\n");
                exit(2);
            }
            memcpy(net->st[k].data + net->st[k].len, act + 32, (size_t)count);
            net->st[k].len += count;
        } else if (kind == P2P_ACT_STREAM_EOF) net->st[k].eof = 1;
        else if (kind == P2P_ACT_STREAM_RESET) net->st[k].reset = 1;
        return;
    }
}

static void node_config(uint8_t *ncfg);
static uint64_t node_attnets(const uint8_t *node_id, uint64_t epoch, const char **why);

/*
 * The peer writes a response chunk of result 0 and the SSZ bytes to stream k: with ctx 4, the
 * ForkDigest of the slot's epoch as context bytes.
 */
static void p2p_chunk(struct p2p_net *net, int k, uint64_t slot, const uint8_t *bytes, uint64_t blen, uint64_t ctx,
                      const char **why) {
    uint8_t ncfg[CONFIG_SIZE];
    node_config(ncfg);
    uint64_t h[6] = {1, ctx, 0, 0, 0, 0}, csize = 0, len = blen, epoch = slot / SLOTS_PER_EPOCH_RUNNER;
    if (ctx) CALL(LF(compute_fork_digest), net->gvr, &epoch, ncfg, fresh_scratch(), &h[3]);
    CALL(lantern_reqresp_chunk_size, &len, &csize);
    uint8_t *payload = serialized(bytes, blen, &(uint64_t){0}), *out = buffer(24 + csize);
    wr64(out, 24 + csize);
    wr64(out + 8, 24);
    wr64(out + 16, 0);
    if (CALL(lantern_reqresp_write_chunk, h, payload, fresh_scratch(), out) != 0) *why = "the peer: write_chunk status";
    else {
        uint64_t n = rd64(out + 16);
        uint8_t *w = p2p_event(net, 1, P2P_EV_STREAM_WRITE, 32 + n);
        wr64(w + 16, net->in[k].handle);
        wr64(w + 24, n);
        memcpy(w + 32, out + 24, (size_t)n);
    }
    free(payload);
    free(out);
}

/* Whether the protocol ID of the protocol index k contains name. */
static int p2p_proto_is(const struct p2p_net *net, uint64_t k, const char *name) {
    if (k >= net->nprotos) return 0;
    const uint8_t *e = net->protos + k * P2P_PROTO_SIZE;
    uint64_t len = rd64(e);
    return len <= P2P_PROTO_SIZE - 8 && find_bytes((const char *)e + 8, len, name) != NULL;
}

/*
 * The peer's answers to the node's complete requests: Status (84 or 92 bytes) with its own;
 * GetMetaData v3 with seq_number 0, no subnets and peer_cgc; BeaconBlocksByRange (24 bytes) of the
 * chain's blocks in the range; BlobSidecarsByRange (16 bytes) of their sidecars in (slot, index)
 * order; DataColumnSidecarsByRange of their column sidecars of the request's columns, which must
 * be want_columns in ascending order, in (slot, index) order. Each a chunk of result 0, with the
 * ForkDigest of its epoch for blocks and sidecars; then the close.
 */
static void p2p_serve(struct p2p_net *net, const char **why) {
    for (int k = 0; k < P2P_STREAMS && !*why; k++) {
        if (!net->in[k].handle || !net->in[k].eof) continue;
        if (p2p_proto_is(net, net->in[k].proto, "/metadata/3/")) {
            uint8_t md[25] = {0}; /* seq_number, attnets, syncnets, custody_group_count */
            wr64(md + 17, net->peer_cgc);
            if (net->in[k].len) *why = "the peer: the node's GetMetaData has request bytes";
            else p2p_chunk(net, k, 0, md, 25, 0, why);
            uint8_t *c = p2p_event(net, 1, P2P_EV_STREAM_CLOSE, 24);
            wr64(c + 16, net->in[k].handle);
            net->in[k].handle = 0;
            continue;
        }
        int columns = p2p_proto_is(net, net->in[k].proto, "/data_column_sidecars_by_range/");
        uint64_t header[6] = {0, 0, 0, 0, 0, 0}, consumed = 0, eof = 1, length = 0;
        uint8_t *input = serialized(net->in[k].data, net->in[k].len, &(uint64_t){0}), *req = buffer(24 + 2048);
        wr64(req, 24 + 2048);
        wr64(req + 8, 24);
        wr64(req + 16, 0);
        if (CALL(lantern_reqresp_read_header, input, header) != 0 ||
            (columns ? header[4] < 20 || (header[4] - 20) % 8 || header[4] > 20 + 8 * 128
                     : header[4] != 24 && header[4] != 16 && header[4] != 84 && header[4] != 92) ||
            (length = header[4],
             CALL(lantern_reqresp_read_payload, input, &header[5], &length, &eof, fresh_scratch(), req, &consumed) != 0))
            *why = "the peer: the node's request is not a Status, BeaconBlocksByRange, BlobSidecarsByRange or DataColumnSidecarsByRange request";
        uint64_t start = rd64(req + 24), count = rd64(req + 32);
        int blobs = !columns && header[4] == 16, status = !columns && (header[4] == 84 || header[4] == 92);
        uint8_t asked[16] = {0};
        if (!*why && columns) { /* the offset 20, then ascending columns: those the peer must be asked for */
            uint64_t n = (header[4] - 20) / 8;
            if ((rd64(req + 24 + 16) & 0xffffffff) != 20) *why = "the node's DataColumnSidecarsByRange: the offset is not 20";
            for (uint64_t i = 0; i < n && !*why; i++) {
                uint64_t c = rd64(req + 24 + 20 + 8 * i);
                if (c >= 128 || (i && c <= rd64(req + 24 + 12 + 8 * i))) *why = "the node's DataColumnSidecarsByRange: the columns are not ascending";
                else asked[c / 8] |= (uint8_t)(1u << (c % 8));
            }
            if (!*why && memcmp(asked, net->want_columns, 16) && memcmp(asked, net->retry_columns, 16))
                *why = "the node's DataColumnSidecarsByRange: not the columns expected";
            if (!*why && start < net->column_floor) *why = "the node's DataColumnSidecarsByRange: a slot below the peer's earliest_available_slot";
            net->column_requests++;
        }
        free(input);
        free(req);
        if (!*why && !status && !columns && !blobs && net->silent) { /* the node's request waits with no answer */
            net->held = 1;
            continue;
        }
        if (!*why && status && net->silent_status) { /* the node's Status waits with no answer */
            net->held = 1;
            continue;
        }
        if (!*why && !status && !net->chain) continue; /* blocks and sidecars once the chain is there */
        if (!*why && status) { /* Status: the peer's, of the same version */
            if (net->status_len != header[4]) *why = "the peer: a Status of another version";
            else p2p_chunk(net, k, 0, net->status, net->status_len, 0, why);
            count = 0;
        }
        uint64_t nth = 0; /* the blocks of the range */
        for (size_t b = 0; b < net->nchain && !*why; b++) {
            const case_block *cb = net->chain[b];
            if (cb->slot < start || cb->slot - start >= count) continue;
            nth++;
            if (columns) { /* the block's column sidecars of the columns asked, by index */
                for (uint64_t c = 0; c < 128 && cb->columns && !net->no_blobs && !*why; c++) {
                    if (!((asked[c / 8] | net->extra_columns[c / 8]) >> (c % 8) & 1) || net->skip_column == c + 1) continue;
                    tv e = cb->columns + 9;
                    for (uint64_t i = 0, nc = rd64(cb->columns + 1); i < nc && !*why; i++, e = tv_skip(e)) {
                        char key[128];
                        uint64_t slen;
                        snprintf(key, sizeof key, "%.*s", (int)rd64(e + 1), (const char *)(e + 9));
                        const uint8_t *sb = tv_bytes(tv_get(net->parts, key), &slen);
                        if (!sb || slen < 8 || rd64(sb) != c || (net->half_columns && c % 2)) continue;
                        p2p_chunk(net, k, cb->slot, sb, slen, 4, why);
                        net->blobs_sent++;
                    }
                }
                continue;
            }
            if (!blobs) {
                if ((net->cut == 1 && nth == 2) || (net->cut == 2 && nth >= 2)) continue; /* a gap; a short answer */
                p2p_chunk(net, k, cb->slot, cb->bytes, cb->len, 4, why);
                continue;
            }
            tv sc = cb->sidecars && !net->no_blobs ? cb->sidecars + 9 : NULL;
            for (uint64_t i = 0, c = sc ? rd64(cb->sidecars + 1) : 0; i < c && !*why; i++, sc = tv_skip(sc)) {
                uint64_t slen;
                const uint8_t *sb = tv_bytes(sc, &slen);
                p2p_chunk(net, k, cb->slot, sb, slen, 4, why);
                net->blobs_sent++;
            }
        }
        if (!columns && !blobs && !status && net->cut == 1 && nth >= 3) net->cut = 2;
        else if (!columns && !blobs && !status && net->cut == 2 && nth >= 2) net->cut = 0;
        uint8_t *c = p2p_event(net, 1, P2P_EV_STREAM_CLOSE, 24);
        wr64(c + 16, net->in[k].handle);
        net->in[k].handle = 0;
    }
}

/* One libp2p step of the peer with its events. */
static void p2p_peer_step(struct p2p_net *net, const char **why) {
    uint8_t tick[56];
    uint64_t result = 0;
    p2p_tick(net, 1, tick);
    wr64(net->events, 24 + net->events_len);
    wr64(net->events + 8, 24);
    wr64(net->events + 16, net->events_len);
    wr64(net->actions, P2P_PEER_ACTIONS);
    uint64_t st = CALL(libp2p_step, net->state[1], tick, net->events, net->scratch, net->actions, &result);
    if (st != 0) {
        *why = "libp2p_step of the peer: status not 0";
        return;
    }
    uint64_t at = 0;
    for (uint64_t k = 0; k < result; k++) at += rd64(net->events + 24 + at);
    memmove(net->events + 24, net->events + 24 + at, (size_t)(net->events_len - at));
    net->events_len -= at;
    uint64_t off = rd64(net->actions + 8), count = rd64(net->actions + 16);
    for (uint64_t a = 0; a < count && !*why; a += rd64(net->actions + off + a)) {
        uint8_t *act = net->actions + off + a;
        uint64_t kind = rd64(act + 8);
        if (kind <= P2P_ACT_CLOSE || kind == P2P_ACT_SEND_DATAGRAM) p2p_shell(net, 1, act, why);
        else p2p_peer_app(net, act);
    }
    if (!*why && (net->chain || net->status_len)) p2p_serve(net, why);
}

/* Steps of both sides, 10 ms apart, until done(net) or 400 rounds. */
static void p2p_run(fc_node *n, struct p2p_net *net, int (*done)(struct p2p_net *, int), int arg, const char **why) {
    for (int r = 0; r < 400 && !*why; r++) {
        if (done(net, arg)) return;
        shell_step(n, why);
        if (!*why) p2p_peer_step(net, why);
        net->now += 10;
    }
    if (!*why && !done(net, arg)) *why = "the network does not get there";
}

static uint64_t p2p_taken; /* set: p2p_open_record's node has 8 peer entries, this many taken by peers with no connection */
static int p2p_connected(struct p2p_net *net, int arg) {
    (void)arg;
    return net->connected && rd64(net->shell->node + NODE_PEERS + 8) == 1 + p2p_taken;
}

/*
 * A peer entry of the node at index i with no connection (a handle of no libp2p slot), inbound,
 * with NODE_PEER_METADATA and the 16 bytes of custody; its peer ID is empty. With head not
 * UINT64_MAX, NODE_PEER_STATUS too, that head_slot, and a status_ms the Status refresh never reaches.
 */
static void shell_fake_peer(struct node_shell *s, uint64_t i, const uint8_t *custody, uint64_t head) {
    uint8_t *p = s->node + rd64(s->node + NODE_PEERS) + i * NODE_PEER_BYTES;
    memset(p, 0, NODE_PEER_BYTES);
    wr64(p, ((uint64_t)0x77 << 32) | (0xff00 + i)); /* slot 0xff00 + i, generation 0x77 */
    wr64(p + 16, 4);                                   /* NODE_PEER_METADATA */
    if (head != UINT64_MAX) {
        wr64(p + 16, 1 | 4); /* NODE_PEER_STATUS */
        wr64(p + 104, head);
        wr64(p + NODE_PEER_STATUS_MS, (uint64_t)1 << 62);
    }
    memcpy(p + 176, custody, 16);
    if (rd64(s->node + NODE_PEERS + 8) < i + 1) wr64(s->node + NODE_PEERS + 8, i + 1);
}
static int p2p_opened(struct p2p_net *net, int k) { return net->st[k].opened || net->st[k].failed; }
static int p2p_ended(struct p2p_net *net, int k) { return net->st[k].eof || net->st[k].reset; }
static int p2p_held(struct p2p_net *net, int arg) {
    (void)arg;
    return net->held;
}
static int p2p_reset_seen(struct p2p_net *net, int arg) {
    (void)arg;
    return net->in_resets != 0;
}

/* A libp2p config of a side, with the protocol list protos of n entries. */
static uint8_t *p2p_config(int side, const uint8_t *protos, uint64_t n) {
    uint64_t size = P2P_CFG_FIXED + n * P2P_PROTO_SIZE;
    uint8_t *c = buffer(size);
    memset(c, 0, (size_t)size);
    static const uint64_t fields[][2] = {
        {8, 1},                                                        /* key_type: Ed25519; the peer's is secp256k1 */
        {80, 1000},   {88, 8},     {96, 64},     {104, 16},  {112, 64}, /* now, the slots: from fulu, a node's column topics too, and its attestation subnets */
        {120, 1 << 22}, {128, 1024}, {136, 256}, {144, 64},  {152, 3}, /* heap, caches, muxers */
        {160, 1 << 18}, {168, 1 << 20}, {176, 1 << 19}, {184, 10000}, {192, 5000}, {200, 1 << 20},
        {224, 8},     {232, 6},    {240, 12},    {248, 6},   {256, 4},  {264, 2}, /* D */
        {272, 700},   {280, 60000}, {288, 6},    {296, 3},   {304, 120000}, {312, 60000}, {320, 10000},
        {328, 10000}, {336, 1},    {352, 5000},  {360, 10},  {368, 3000}, {376, 3}, {384, 60}, {392, 2},
        {640, 1},     {648, 1024}, {656, 64},    {664, 3},   {672, 1000}, {680, 10}, /* gossipsub v1.2 */
    };
    for (size_t i = 0; i < sizeof fields / sizeof fields[0]; i++) wr64(c + fields[i][0], fields[i][1]);
    if (side == 1) wr64(c + 8, 2); /* the key of the peer's record (peer_record) */
    if (side == 1) { /* the peer queues a whole answer at once: a supernode's columns of a range are past 1 MiB */
        wr64(c + 120, 1 << 24);
        wr64(c + 200, 1 << 23);
    }
    wr64(c, size);
    for (int i = 0; i < 32; i++) {
        c[16 + i] = (uint8_t)(side * 31 + i + 1);
        c[48 + i] = (uint8_t)(side * 17 + i * 3);
    }
    double factor = 0.25;
    memcpy(c + 344, &factor, 8);
    wr64(c + 528, 7);
    memcpy(c + 536, "lantern", 7);
    wr64(c + 600, 10);
    memcpy(c + 608, "eth2/1.0.0", 10);
    wr64(c + 208, P2P_CFG_FIXED);
    wr64(c + 216, n);
    if (n) memcpy(c + P2P_CFG_FIXED, protos, (size_t)(n * P2P_PROTO_SIZE));
    return c;
}

/* A libp2p state of a config. */
static uint8_t *p2p_make(uint8_t *cfg, const char **why) {
    uint64_t size = 0;
    if (CALL(libp2p_state_size, cfg, &size) != 0) {
        *why = "libp2p_state_size status";
        return NULL;
    }
    uint8_t *st = buffer(size);
    wr64(st, size);
    if (CALL(libp2p_init, cfg, st) != 0) {
        *why = "libp2p_init status";
        free(st);
        return NULL;
    }
    return st;
}

/*
 * One request of the peer on a new stream of protocol name/version: the request's SSZ bytes as
 * one chunk, unless req is NULL, then the close of its side; then the stream's end. Returns the
 * stream's index.
 */
static int p2p_request(fc_node *n, struct p2p_net *net, int k, const char *name, uint64_t version, const uint8_t *req,
                       uint64_t len, const char **why) {
    char id[128];
    int idlen = snprintf(id, sizeof id, "/eth2/beacon_chain/req/%s/%llu/ssz_snappy", name, (unsigned long long)version);
    net->st[k].tag = 500 + (uint64_t)k;
    uint8_t *e = p2p_event(net, 1, P2P_EV_OPEN_STREAM, 40 + P2P_PROTO_SIZE);
    wr64(e + 16, net->node_handle);
    wr64(e + 24, net->st[k].tag);
    wr64(e + 32, 1);
    wr64(e + 40, (uint64_t)idlen);
    memcpy(e + 48, id, (size_t)idlen);
    p2p_run(n, net, p2p_opened, k, why);
    if (*why) return k;
    if (net->st[k].failed) {
        *why = "the node refuses the protocol";
        return k;
    }
    if (req) {
        uint64_t header[6] = {0, 0, 0, 0, 0, 0}, csize = 0;
        CALL(lantern_reqresp_chunk_size, &len, &csize);
        uint8_t *payload = serialized(req, len, &(uint64_t){0}), *out = buffer(24 + csize);
        wr64(out, 24 + csize);
        wr64(out + 8, 24);
        wr64(out + 16, 0);
        if (CALL(lantern_reqresp_write_chunk, header, payload, fresh_scratch(), out) != 0) *why = "write_chunk status";
        else {
            uint64_t count = rd64(out + 16);
            uint8_t *w = p2p_event(net, 1, P2P_EV_STREAM_WRITE, 32 + count);
            wr64(w + 16, net->st[k].handle);
            wr64(w + 24, count);
            memcpy(w + 32, out + 24, (size_t)count);
        }
        free(payload);
        free(out);
    }
    uint8_t *c = p2p_event(net, 1, P2P_EV_STREAM_CLOSE, 24);
    wr64(c + 16, net->st[k].handle);
    p2p_run(n, net, p2p_ended, k, why);
    if (!*why && net->st[k].reset) {
        static char rmsg[96];
        snprintf(rmsg, sizeof rmsg, "the node resets the stream of %s v%llu", name, (unsigned long long)version);
        *why = rmsg;
    }
    return k;
}

/* The response of one chunk of stream k: result 0 and the SSZ bytes want. */
static void p2p_check_response(struct p2p_net *net, int k, const uint8_t *want, uint64_t wlen, const char *what,
                               const char **why) {
    static char msg[96];
    uint64_t header[6] = {1, 0, 0, 0, 0, 0}, consumed = 0, eof = 1;
    uint8_t *input = serialized(net->st[k].data, net->st[k].len, &(uint64_t){0}), *out = buffer(24 + wlen + 8);
    wr64(out, 24 + wlen + 8);
    if (CALL(lantern_reqresp_read_header, input, header) != 0) snprintf(msg, sizeof msg, "%s: no response header", what);
    else if (header[2] != 0) snprintf(msg, sizeof msg, "%s: result %llu", what, (unsigned long long)header[2]);
    else if (header[4] != wlen) snprintf(msg, sizeof msg, "%s: length %llu", what, (unsigned long long)header[4]);
    else if (CALL(lantern_reqresp_read_payload, input, &header[5], &header[4], &eof, fresh_scratch(), out, &consumed) != 0)
        snprintf(msg, sizeof msg, "%s: payload status", what);
    else if (memcmp(out + 24, want, (size_t)wlen)) snprintf(msg, sizeof msg, "%s: bytes differ", what);
    else if (header[5] + consumed != net->st[k].len) snprintf(msg, sizeof msg, "%s: bytes after the chunk", what);
    else msg[0] = 0;
    if (msg[0]) *why = msg;
    free(input);
    free(out);
}

/* The node's config, as shell_open gives it: this runner's fork and the ones before at genesis. */
static void node_config(uint8_t *ncfg) {
    memcpy(ncfg, config, CONFIG_SIZE);
    for (uint64_t f = FORK_ALTAIR; f <= FORK_FULU; f++) wr64(ncfg + 16 * f, f <= FORK ? 0 : UINT64_MAX);
}

/* The node's attestation subnets at epoch: bit i for subnet i (lantern_compute_subscribed_subnets of its node ID). */
static uint64_t node_attnets(const uint8_t *node_id, uint64_t epoch, const char **why) {
    uint8_t ncfg[CONFIG_SIZE], list[24 + 8 * 64];
    uint64_t bits = 0;
    node_config(ncfg);
    wr64(list, sizeof list);
    wr64(list + 8, 24);
    wr64(list + 16, 0);
    if (CALL(LF(compute_subscribed_subnets), node_id, &epoch, ncfg, fresh_scratch(), list) != 0) *why = "compute_subscribed_subnets status";
    for (uint64_t i = 0; i < rd64(list + 16) && !*why; i++) bits |= 1ull << (rd64(list + 24 + 8 * i) % 64);
    return bits;
}


/*
 * The network of a node: its room for peers and streams, its libp2p state and a peer's, and the
 * peer's dial; then the node's entry of the peer.
 */
static void p2p_open_record(fc_node *n, struct p2p_net *net, const uint8_t *record, uint64_t rlen, const uint8_t *status,
                            uint64_t slen, const char **why);
static void p2p_open(fc_node *n, struct p2p_net *net, const char **why) { p2p_open_record(n, net, NULL, 0, NULL, 0, why); }
static void api_peers_check(fc_node *n, struct p2p_net *net, int outbound, const char **why);
static void api_subscribe_check(fc_node *n, struct p2p_net *net, const char **why);
#if FORK >= FORK_FULU
static void custody_check(fc_node *n, struct p2p_net *net, const uint8_t *status, uint64_t slen, const char **why);
#endif

/*
 * The network of a node, as p2p_open: with a record, the node gets it in a NODE_EV_ENR and must
 * dial the peer, and the peer answers the node's Status with status.
 */
static void p2p_open_record(fc_node *n, struct p2p_net *net, const uint8_t *record, uint64_t rlen, const uint8_t *status,
                            uint64_t slen, const char **why) {
    struct node_shell *s = n->shell;
    memset(net, 0, sizeof *net);
    if (slen) memcpy(net->status, status, (size_t)slen);
    net->status_len = slen;
    net->shell = s;
    net->now = 1000;
    s->net = net;
    s->room[3] = p2p_taken ? 8 : 4; /* peers */
    s->room[4] = 4;       /* streams */
    if (s->room[5] < 8192) s->room[5] = 8192;      /* request bytes */
    if (s->room[6] < (1u << 20)) s->room[6] = 1u << 20; /* queued libp2p events */
    if (s->room[7] < 16) s->room[7] = 16;               /* gossip messages */
    if (s->room[8] < 1024) s->room[8] = 1024;           /* blob sidecars: NODE_SYNC_BATCH * 9 free, and more */
    if (s->room[17] < 8) s->room[17] = 8;               /* NodeResponse entries: the node's requests but Status and GetMetaData */
    if (s->room[18] < (1u << 18)) s->room[18] = 1u << 18; /* response bytes: a block's chunk, past the request bytes */
    if (!*why) { /* the node with that room, then its libp2p state */
        uint8_t *old = s->node;
        uint64_t need = 0;
        CALL(lantern_node_size, s->room, &need);
        s->node = buffer(need);
        wr64(s->node, need);
        if (CALL(lantern_node_copy, old, s->room, s->node) != 0) *why = "lantern_node_copy status";
        s->node_size = need;
        free(old);
    }
    uint8_t protos[64 * P2P_PROTO_SIZE + 24];
    uint64_t nprotos = 0;
    wr64(protos, sizeof protos);
    if (!*why && CALL(lantern_node_protocols, protos, &nprotos) != 0) *why = "lantern_node_protocols status";
    if (!*why) {
        memcpy(net->protos, protos + 24, (size_t)(nprotos * P2P_PROTO_SIZE));
        net->nprotos = nprotos;
    }
    uint8_t *cfg0 = *why ? NULL : p2p_config(0, protos + 24, nprotos), *cfg1 = *why ? NULL : p2p_config(1, protos + 24, nprotos);
    if (!*why) net->state[0] = p2p_make(cfg0, why);
    if (!*why) net->state[1] = p2p_make(cfg1, why);
    free(cfg0);
    free(cfg1);
    net->scratch = buffer(P2P_SCRATCH_SIZE);
    wr64(net->scratch, P2P_SCRATCH_SIZE);
    net->actions = buffer(P2P_PEER_ACTIONS);
    if (s->actions_size < (8u << 20)) {
        s->actions_size = 8u << 20;
        free(s->actions);
        s->actions = buffer(s->actions_size);
        wr64(s->actions, s->actions_size);
    }
    net->events = xmalloc(24);
    static const uint8_t all[16] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
    for (uint64_t i = 0; i < p2p_taken && !*why; i++) shell_fake_peer(s, i, all, UINT64_MAX); /* they hold every column */
    if (!*why && p2p_taken >= 7) { /* the open room is full: the peer dials the node and gets no entry */
        uint8_t *e = p2p_event(net, 1, P2P_EV_DIAL, 128);
        wr64(e + 16, 7);
        wr64(e + 24, 4);
        wr64(e + 32, 9000);
        e[40] = 10;
        e[43] = 1;
        uint64_t idlen = rd64(net->state[0] + P2P_ST_PEER_ID_LEN);
        wr64(e + 56, idlen);
        memcpy(e + 64, net->state[0] + P2P_ST_PEER_ID, (size_t)idlen);
        for (int r = 0; r < 100 && !*why; r++) {
            shell_step(n, why);
            if (!*why) p2p_peer_step(net, why);
            net->now += 10;
        }
        return;
    }
    if (!*why && record) { /* the node dials the peer of the record */
        shell_event(s, EV_ENR, 0, record, rlen);
        p2p_run(n, net, p2p_connected, 0, why);
        if (*why && !strcmp(*why, "the network does not get there")) *why = "the node does not dial the peer of the record";
    } else if (!*why) { /* the peer dials the node */
        uint8_t *e = p2p_event(net, 1, P2P_EV_DIAL, 128);
        wr64(e + 16, 7);
        wr64(e + 24, 4);
        wr64(e + 32, 9000);
        e[40] = 10;
        e[43] = 1;
        uint64_t idlen = rd64(net->state[0] + P2P_ST_PEER_ID_LEN);
        wr64(e + 56, idlen);
        memcpy(e + 64, net->state[0] + P2P_ST_PEER_ID, (size_t)idlen);
        p2p_run(n, net, p2p_connected, 0, why);
    }
    if (!*why) { /* the node's entry of the peer */
        const uint8_t *peer = s->node + rd64(s->node + NODE_PEERS) + p2p_taken * NODE_PEER_BYTES;
        uint64_t idlen = rd64(net->state[1] + P2P_ST_PEER_ID_LEN);
        if (rd64(peer + 120) != idlen || memcmp(peer + 128, net->state[1] + P2P_ST_PEER_ID, (size_t)idlen))
            *why = "the node's peer entry: not the peer's ID";
    }
    if (!*why && !p2p_taken) api_peers_check(n, net, record != NULL, why);
}

static void p2p_close(struct p2p_net *net) {
    for (int k = 0; k < P2P_STREAMS; k++) {
        free(net->st[k].data);
        free(net->in[k].data);
    }
    for (int k = 0; k < net->nlc; k++) free(net->lc_data[k]);
    free(net->state[0]);
    free(net->state[1]);
    free(net->scratch);
    free(net->actions);
    free(net->events);
    net->shell->net = NULL;
}

/* Whether the node's last SET_ENTRY of key has the len bytes of want. */
static int shell_entry(const struct node_shell *s, const char *key, const uint8_t *want, uint64_t len) {
    for (size_t k = 0; k < s->nentries; k++)
        if (!strcmp(s->entries[k].key, key)) return s->entries[k].len == len && !memcmp(s->entries[k].value, want, (size_t)len);
    return 0;
}

static void p2p_op_events(fc_node *n, struct p2p_net *net, tv parts, const char **why);

static void p2p_settle(fc_node *n, struct p2p_net *net, const char **why);
static void record_of(const uint8_t *gvr, uint64_t epoch, int seed, int64_t cgc, uint8_t *out, const char **why);

/* Whether the node has a peer entry of the runner's peer's ID. */
static int shell_has_peer(const struct node_shell *s, const struct p2p_net *net) {
    const uint8_t *e = s->node + rd64(s->node + NODE_PEERS);
    uint64_t idlen = rd64(net->state[1] + P2P_ST_PEER_ID_LEN);
    for (uint64_t i = 0, c = rd64(s->node + NODE_PEERS + 8); i < c; i++, e += NODE_PEER_BYTES)
        if (rd64(e + 120) == idlen && !memcmp(e + 128, net->state[1] + P2P_ST_PEER_ID, (size_t)idlen)) return 1;
    return 0;
}

/*
 * The open room (node.md, the peer room): a new node of 8 peer entries, 7 taken by peers with no
 * connection: the peer dials it and gets no entry, the node closing the connection. With 6 taken,
 * the peer gets an entry.
 */
static unsigned long inbound_room_checked;
static void inbound_room_check(tv parts, const char **why) {
    for (uint64_t taken = 7; taken >= 6 && !*why; taken--) {
        fc_node m;
        uint8_t *anchor_block;
        struct p2p_net net;
        struct node_shell *s = shell_open(&m, parts, &anchor_block, why);
        if (*why) break;
        p2p_taken = taken;
        p2p_open(&m, &net, why);
        p2p_taken = 0;
        if (!*why && taken == 7 && (shell_has_peer(s, &net) || rd64(s->node + NODE_PEERS + 8) != 7 || !net.closes))
            *why = "the open room: an inbound peer past it is not refused";
        if (!*why && taken == 6 && (!shell_has_peer(s, &net) || rd64(s->node + NODE_PEERS + 8) != 7))
            *why = "the open room: an inbound peer within it gets no entry";
        p2p_close(&net);
        shell_close(&m, anchor_block);
    }
    if (!*why) inbound_room_checked++;
}

#if FORK >= FORK_FULU
/*
 * The column dials and the spare peer (node.md, the peer room), on the node of the network: 8 peer
 * entries; the runner's peer with no custody, peers with no connection holding every column but
 * the node's lowest, c0, and one holding c0 only, so c0 is short. With the open room full, a record
 * with cgc 0 gives no DIAL, and one with cgc NUMBER_OF_CUSTODY_GROUPS a DIAL. With the 8 entries
 * full, a lookup past NODE_LOOKUP_MS: with the runner's peer holding one of the node's columns, no
 * DISCONNECT; with no custody, its DISCONNECT, and its entry goes.
 */
static unsigned long column_room_checked;
static void column_room_check(fc_node *n, struct p2p_net *net, const char **why) {
    struct node_shell *s = n->shell;
    uint8_t *old = s->node;
    uint64_t need = 0, slot = 0;
    s->room[3] = 8; /* peers: spare room 1 */
    CALL(lantern_node_size, s->room, &need);
    s->node = buffer(need);
    wr64(s->node, need);
    if (CALL(lantern_node_copy, old, s->room, s->node) != 0) *why = "column dials: lantern_node_copy status";
    s->node_size = need;
    free(old);
    if (!*why && (rd64(s->node + NODE_PEERS + 8) != 1 || !shell_has_peer(s, net))) *why = "column dials: the runner's peer is not the one entry";
    if (!*why && CALL(LF(get_current_slot), n->store, &slot) != 0) *why = "column dials: get_current_slot status";
    if (*why) return;
    uint8_t cols[16], most[16], only[16] = {0}, one[16] = {0}, gvr[32], rec[24 + 300];
    uint64_t c0 = 128, c1 = 128, epoch = slot / SLOTS_PER_EPOCH_RUNNER;
    memcpy(cols, s->node + 440, 16); /* Node_columns */
    for (uint64_t c = 0; c < 128; c++)
        if (cols[c / 8] >> (c % 8) & 1) {
            if (c0 == 128) c0 = c;
            else if (c1 == 128) c1 = c;
        }
    if (c1 == 128) {
        *why = "column dials: the node samples fewer than 2 columns";
        return;
    }
    memset(most, 0xff, 16);
    most[c0 / 8] &= (uint8_t)~(1u << (c0 % 8));
    only[c0 / 8] = (uint8_t)(1u << (c0 % 8));
    one[c1 / 8] = (uint8_t)(1u << (c1 % 8));
    uint8_t *p0 = s->node + rd64(s->node + NODE_PEERS);
    wr64(p0 + 16, rd64(p0 + 16) | 4); /* the runner's peer: NODE_PEER_METADATA, no custody */
    memset(p0 + 176, 0, 16);
    for (uint64_t i = 1; i <= 5; i++) shell_fake_peer(s, i, most, slot);
    shell_fake_peer(s, 6, only, slot); /* 7 peers: the open room is full; c0 has one peer that serves the store's slot */
    wr64(s->node + 432, 0);      /* Node_dialing */
    net->drop_dials = 1;
    memcpy(gvr, n->anchor + field_offset("BeaconState", 1), 32);
    record_of(gvr, epoch, 100, 0, rec, why); /* cgc 0: no columns */
    if (!*why) {
        shell_event(s, EV_ENR, 0, rec + 24, rd64(rec + 16));
        shell_step(n, why);
    }
    if (!*why && (rd64(s->node + 432) || net->dials)) *why = "column dials: a record of no short column dials past the open room";
    if (!*why) record_of(gvr, epoch, 150, (int64_t)rd64(config + 280), rec, why); /* every custody group */
    if (!*why) {
        shell_event(s, EV_ENR, 0, rec + 24, rd64(rec + 16));
        shell_step(n, why);
    }
    if (!*why && rd64(s->node + 432) != 1) *why = "column dials: a record of a short column gets no DIAL";
    wr64(s->node + 432, 0); /* the dial ends */
    /* A second holder of c0, peer 1: behind (head_slot + SLOTS_PER_EPOCH below the slot), then with no data
     * at the slot (earliest_slot past it), c0 stays short; serving the slot, it is not short. */
    uint8_t *p1 = s->node + rd64(s->node + NODE_PEERS) + NODE_PEER_BYTES, both[16];
    memcpy(both, most, 16);
    both[c0 / 8] |= (uint8_t)(1u << (c0 % 8));
    if (!*why && slot <= SLOTS_PER_EPOCH_RUNNER) *why = "column dials: the store's slot leaves no room for a peer behind";
    for (int k = 0; k < 3 && !*why; k++) {
        memcpy(p1 + 176, both, 16);
        wr64(p1 + 104, k == 0 ? slot - SLOTS_PER_EPOCH_RUNNER - 1 : slot - SLOTS_PER_EPOCH_RUNNER);
        wr64(p1 + 112, k == 1 ? slot + 1 : 0); /* earliest_slot */
        record_of(gvr, epoch, (uint64_t)(151 + k), (int64_t)rd64(config + 280), rec, why);
        if (!*why) {
            shell_event(s, EV_ENR, 0, rec + 24, rd64(rec + 16));
            shell_step(n, why);
        }
        if (!*why && k < 2 && rd64(s->node + 432) != 1)
            *why = k ? "column dials: a holder with no data at the slot makes the column not short"
                     : "column dials: a holder behind makes the column not short";
        if (!*why && k == 2 && rd64(s->node + 432)) *why = "column dials: a column of two serving holders is short";
        wr64(s->node + 432, 0);
    }
    if (!*why) {
        memcpy(p1 + 176, most, 16);
        wr64(p1 + 104, slot);
        wr64(p1 + 112, 0);
    }
    if (!*why) shell_fake_peer(s, 7, most, slot); /* 8 peers: full */
    for (int spare = 0; spare < 2 && !*why; spare++) {
        static const uint8_t none[16] = {0};
        memcpy(p0 + 176, spare ? none : one, 16);
        uint64_t t = rd64(s->node + 16), due = rd64(s->node + 424) + 10000 + 1, lookups = s->lookups; /* time_ms; lookup_ms + NODE_LOOKUP_MS */
        shell_event(s, EV_TICK, t > due ? t + 1 : due, NULL, 0);
        p2p_settle(n, net, why);
        if (!*why && s->lookups == lookups) *why = "column dials: no lookup with a short column and the peers full";
        if (!*why && !spare && !shell_has_peer(s, net)) *why = "column dials: a peer of a sampled column is dropped";
        if (!*why && spare && shell_has_peer(s, net)) *why = "column dials: the spare peer is not dropped";
        p0 = s->node + rd64(s->node + NODE_PEERS);
    }
    net->drop_dials = 0;
    if (!*why) column_room_checked++;
}
#endif

/*
 * The Status refresh (node.md): a peer entry with no connection, NODE_PEER_STATUS and status_ms the
 * node's time T; the runner's peer at T + NODE_STATUS_REFRESH, so the other is the one due. A tick at T + NODE_STATUS_REFRESH - 1 leaves its status_ms; a tick at T +
 * NODE_STATUS_REFRESH makes it that time, the refresh's Status request to it. The entry goes after.
 */
static unsigned long status_refresh_checked;
static void status_refresh_check(fc_node *n, struct p2p_net *net, const char **why) {
    struct node_shell *s = n->shell;
    static const uint8_t none[16] = {0};
    uint64_t k = rd64(s->node + NODE_PEERS + 8), t = rd64(s->node + NODE_TIME_MS);
    uint64_t period = SLOTS_PER_EPOCH_RUNNER / 2 * rd64(config + 104), at;
    if (k != 1) {
        *why = "status refresh: the runner's peer is not the one entry";
        return;
    }
    shell_fake_peer(s, k, none, 0);
    wr64(s->node + rd64(s->node + NODE_PEERS) + k * NODE_PEER_BYTES + NODE_PEER_STATUS_MS, t);
    wr64(s->node + rd64(s->node + NODE_PEERS) + NODE_PEER_STATUS_MS, t + period); /* the runner's peer: not due before it */
    shell_event(s, EV_TICK, t + period - 1, NULL, 0);
    p2p_settle(n, net, why);
    at = rd64(s->node + rd64(s->node + NODE_PEERS) + k * NODE_PEER_BYTES + NODE_PEER_STATUS_MS);
    if (!*why && at != t) *why = "status refresh: a Status asked before half an epoch";
    if (!*why) {
        shell_event(s, EV_TICK, t + period, NULL, 0);
        p2p_settle(n, net, why);
    }
    at = rd64(s->node + rd64(s->node + NODE_PEERS) + k * NODE_PEER_BYTES + NODE_PEER_STATUS_MS);
    if (!*why && at < t + period) *why = "status refresh: no Status asked after half an epoch";
    wr64(s->node + NODE_PEERS + 8, k); /* the entry goes */
    if (!*why) p2p_settle(n, net, why);
    if (!*why) { /* a Status the peer never answers: NODE_REQUEST_MS after it, the node resets the stream */
        uint64_t now = rd64(s->node + NODE_TIME_MS) + 10000; /* NODE_REQUEST_MS: the requests open now go, and free their room */
        shell_event(s, EV_TICK, now, NULL, 0);
        p2p_settle(n, net, why);
        net->silent_status = 1;
        net->held = 0;
        net->in_resets = 0;
        wr64(s->node + rd64(s->node + NODE_PEERS) + NODE_PEER_STATUS_MS, now - period);
        if (!*why) shell_event(s, EV_TICK, now, NULL, 0);
        if (!*why) p2p_settle(n, net, why);
        int asked = 0; /* the refresh's: its status_ms that time, and a Status request of the node to it opened then */
        const uint8_t *e = s->node + rd64(s->node + 136);
        for (uint64_t q = 0, c = rd64(s->node + 144), sb = rd64(s->node + 168); q < c; q++, e += sb)
            asked |= rd64(e + 16) == 1 && rd64(e + 32) >= 5 && rd64(e + 56) == now; /* REQRESP_STATUS, OPENING or RESPONSE, opened_ms */
        if (!*why && (!asked || rd64(s->node + rd64(s->node + NODE_PEERS) + NODE_PEER_STATUS_MS) != now))
            *why = "status refresh: no Status asked of the peer once due";
        if (!*why) shell_event(s, EV_TICK, now + 10000, NULL, 0); /* NODE_REQUEST_MS */
        if (!*why) p2p_run(n, net, p2p_reset_seen, 0, why);
        if (*why && !strcmp(*why, "the network does not get there")) *why = "status refresh: a Status with no answer is not reset after NODE_REQUEST_MS";
        net->silent_status = 0;
        if (!*why) p2p_settle(n, net, why);
    }
    if (!*why) status_refresh_checked++;
}

static void run_node_p2p(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, slen, mlen;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        fc_node n;
        uint8_t *anchor_block;
        struct node_shell *s = shell_open(&n, parts, &anchor_block, &why);
        struct p2p_net net;
        p2p_open(&n, &net, &why);
        const uint8_t *status = tv_bytes(tv_get(parts, "status"), &slen), *metadata = tv_bytes(tv_get(parts, "metadata"), &mlen);
        if (!why) { /* Status: the node's answer, and the node keeps the peer's */
            int k = p2p_request(&n, &net, 0, "status", tv_u64(tv_get(parts, "status_version")), status, slen, &why);
            if (!why) p2p_check_response(&net, k, status, slen, "status", &why);
            const uint8_t *peer = s->node + rd64(s->node + NODE_PEERS);
            if (!why && (!(rd64(peer + 16) & 1) || memcmp(peer + 24, status, 4) || memcmp(peer + 32, status + 4, 80)))
                why = "the node's peer entry: not the peer's Status";
        }
        if (!why) { /* Ping: the node's seq_number */
            static const uint8_t seq[8] = {5};
            uint8_t ours[8];
            wr64(ours, rd64(s->node + 176)); /* Node_metadata_seq */
            int k = p2p_request(&n, &net, 1, "ping", 1, seq, 8, &why);
            if (!why) p2p_check_response(&net, k, ours, 8, "ping", &why);
        }
        if (!why) { /* MetaData: no request bytes */
            int k = p2p_request(&n, &net, 2, "metadata", tv_u64(tv_get(parts, "metadata_version")), NULL, 0, &why);
            /* the case's, with the bits of the node's subnets as attnets and the node's seq_number, above 0 with them */
            uint8_t md[64] = {0};
            uint64_t bits = node_attnets(s->anchor + 176, rd64(s->node + 216) / SLOTS_PER_EPOCH_RUNNER, &why), seq = rd64(s->node + 176);
            if (mlen > sizeof md || mlen < 16) why = "the case's MetaData";
            else memcpy(md, metadata, (size_t)mlen);
            wr64(md, seq);
            wr64(md + 8, bits);
            if (!why && bits && !seq) why = "MetaData: subnets with seq_number 0";
            if (!why) p2p_check_response(&net, k, md, mlen, "metadata", &why);
        }
        if (!why) { /* Goodbye: the node closes the stream with no answer */
            static const uint8_t reason[8] = {1};
            int k = p2p_request(&n, &net, 3, "goodbye", 1, reason, 8, &why);
            if (!why && net.st[k].len) why = "goodbye: an answer";
        }
        if (!why) { /* NODE_FLAG_DISCV5: the record entries of the anchor's epoch, and a lookup */
            uint8_t gvr[32], ncfg[CONFIG_SIZE], want[16], zero[8] = {0};
            uint64_t epoch = rd64(s->node + 216) / SLOTS_PER_EPOCH_RUNNER; /* Node_earliest_slot: the anchor's */
            memcpy(gvr, n.anchor + field_offset("BeaconState", 1), 32);
            node_config(ncfg);
            CALL(LF(compute_enr_fork_id), gvr, &epoch, ncfg, fresh_scratch(), want);
            if (!shell_entry(s, "eth2", want, 16)) why = "the record's eth2";
            uint8_t att[8];
            wr64(att, node_attnets(s->anchor + 176, epoch, &why));
            if (!why && !shell_entry(s, "attnets", att, 8)) why = "the record's attnets";
            else if (FORK >= FORK_ALTAIR && !shell_entry(s, "syncnets", zero, 1)) why = "the record's syncnets";
            else if (!s->lookups) why = "no lookup";
#if FORK >= FORK_FULU
            uint8_t cgc[8];
            uint64_t v = rd64(config + 288), nb = 0; /* CUSTODY_REQUIREMENT, big-endian with no leading zero byte */
            for (uint64_t t = v; t; t >>= 8) nb++;
            for (uint64_t b = 0; b < nb; b++) cgc[b] = (uint8_t)(v >> (8 * (nb - 1 - b)));
            if (!why && !shell_entry(s, "cgc", cgc, nb)) why = "the record's cgc";
            CALL(LF(compute_next_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), want);
            if (!why && !shell_entry(s, "nfd", want, 4)) why = "the record's nfd";
#endif
        }
        if (!why) api_subscribe_check(&n, &net, &why);
#if FORK >= FORK_FULU
        if (!why) custody_check(&n, &net, status, slen, &why);
#endif
        if (!why) p2p_op_events(&n, &net, parts, &why);
        if (!why) status_refresh_check(&n, &net, &why);
#if FORK >= FORK_FULU
        if (!why) column_room_check(&n, &net, &why);
#endif
        if (!why && rd64(s->node + rd64(s->node + 152) + 16)) why = "the node keeps libp2p events at the end"; /* Node_p2p_out: a ByteList */
        p2p_close(&net);
        shell_close(&n, anchor_block);
        if (!why) inbound_room_check(parts, &why);
        report(file, name, len, why == NULL, why);
    }
}

/*
 * The chunks of stream k: one for each block of want, in order, each with result 0, the
 * ForkDigest of the block's epoch as context, and the block's SSZ bytes; then no more bytes.
 */
static void p2p_check_blocks(struct p2p_net *net, int k, case_block **want, size_t nwant, const uint8_t *gvr, const char *what,
                             const char **why) {
    static char msg[128];
    uint8_t ncfg[CONFIG_SIZE];
    node_config(ncfg);
    uint64_t at = 0, total = net->st[k].len;
    msg[0] = 0;
    for (size_t b = 0; b < nwant && !msg[0]; b++) {
        uint64_t header[6] = {1, 4, 0, 0, 0, 0}, consumed = 0, eof = 1, epoch = want[b]->slot / SLOTS_PER_EPOCH_RUNNER;
        uint8_t digest[8] = {0};
        uint8_t *input = serialized(net->st[k].data + at, total - at, &(uint64_t){0}), *out = buffer(24 + want[b]->len + 8);
        wr64(out, 24 + want[b]->len + 8);
        CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), digest);
        if (at >= total) snprintf(msg, sizeof msg, "%s: %zu chunks, %zu wanted", what, b, nwant);
        else if (CALL(lantern_reqresp_read_header, input, header) != 0) snprintf(msg, sizeof msg, "%s: chunk %zu: no header", what, b);
        else if (header[2] != 0) snprintf(msg, sizeof msg, "%s: chunk %zu: result %llu", what, b, (unsigned long long)header[2]);
        else if (memcmp(&header[3], digest, 4)) snprintf(msg, sizeof msg, "%s: chunk %zu: context bytes", what, b);
        else if (header[4] != want[b]->len) snprintf(msg, sizeof msg, "%s: chunk %zu: length", what, b);
        else if (CALL(lantern_reqresp_read_payload, input, &header[5], &header[4], &eof, fresh_scratch(), out, &consumed) != 0)
            snprintf(msg, sizeof msg, "%s: chunk %zu: payload status", what, b);
        else if (memcmp(out + 24, want[b]->bytes, (size_t)want[b]->len)) snprintf(msg, sizeof msg, "%s: chunk %zu: bytes", what, b);
        at += header[5] + consumed;
        free(input);
        free(out);
    }
    if (!msg[0] && at != total) snprintf(msg, sizeof msg, "%s: bytes after the last chunk", what);
    if (msg[0]) *why = msg;
}

/* The chain of the last head a case's checks name, from its valid blocks, in slot order. */
static size_t case_chain(tv parts, case_block **blocks_out, case_block ***chain_out, const char **why) {
    tv steps = tv_get(parts, "steps"), st = steps ? steps + 9 : NULL, head = NULL;
    uint64_t count = steps ? rd64(steps + 1) : 0, nblocks = 0;
    case_block *blocks = xmalloc(sizeof *blocks * (count ? count : 1));
    for (uint64_t k = 0; k < count && !*why; k++, st = tv_skip(st)) {
        tv c = tv_get(st, "checks"), v = tv_get(st, "valid");
        if (c && tv_get(c, "head")) head = tv_get(c, "head");
        if (!tv_get(st, "block") || (v && !(*v == T_BOOL && v[1]))) continue;
        tv bname = tv_get(st, "block");
        char key[128];
        uint64_t vsize;
        snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
        case_block *b = &blocks[nblocks];
        b->bytes = tv_bytes(tv_get(parts, key), &b->len);
        b->sidecars = case_blobs ? tv_get(case_blobs, key) : NULL;
        b->columns = FORK >= FORK_FULU ? tv_get(st, "columns") : NULL;
        uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), b->bytes, b->len, &vsize, why);
        if (!sb) break;
        const uint8_t *block = nested(sb, field_offset("SignedBeaconBlock", 0));
        root_of("BeaconBlock", block, b->root, why);
        b->slot = rd64(block + field_offset("BeaconBlock", 0));
        memcpy(b->parent, block + field_offset("BeaconBlock", 2), 32);
        free(sb);
        nblocks++;
    }
    uint64_t hlen = 0;
    const uint8_t *hroot = head ? tv_bytes(tv_get(head, "root"), &hlen) : NULL;
    case_block **chain = xmalloc(sizeof *chain * (nblocks ? nblocks : 1));
    size_t nchain = 0;
    for (const uint8_t *cur = hroot; cur && hlen == 32 && !*why;) { /* from the head down, then in slot order */
        case_block *b = NULL;
        for (uint64_t k = 0; k < nblocks && !b; k++)
            if (!memcmp(blocks[k].root, cur, 32)) b = &blocks[k];
        if (!b || nchain == nblocks) break;
        chain[nchain++] = b;
        cur = b->parent;
    }
    for (size_t a = 0, z = nchain ? nchain - 1 : 0; a < z; a++, z--) {
        case_block *t = chain[a];
        chain[a] = chain[z];
        chain[z] = t;
    }
    *blocks_out = blocks;
    *chain_out = chain;
    return nchain;
}

#if FORK >= FORK_ALTAIR
static void p2p_lc_serve_check(fc_node *n, struct p2p_net *net, const uint8_t *const *roots, size_t nroots, const uint8_t *gvr,
                               const char **why);
#endif

/*
 * Node mode, after the steps of a case whose checks name a head: the node serves the chain of that
 * head, from the case's valid blocks, with BlocksByRange and BlocksByRoot; and its light client data.
 */
static void fc_serve_check(fc_node *n, tv parts, const char **why) {
    case_block *blocks, **chain;
    size_t nchain = case_chain(parts, &blocks, &chain, why);
    if (!*why && nchain) {
        struct p2p_net net;
        uint8_t gvr[32];
        memcpy(gvr, n->anchor + field_offset("BeaconState", 1), 32);
        uint64_t anchor_slot = rd64(n->shell->node + 216); /* Node_earliest_slot */
        p2p_open(n, &net, why);
        if (!*why) { /* the whole chain by range */
            uint8_t req[24];
            wr64(req, anchor_slot);
            wr64(req + 8, chain[nchain - 1]->slot - anchor_slot + 1);
            wr64(req + 16, 1);
            int k = p2p_request(n, &net, 0, "beacon_blocks_by_range", 2, req, 24, why);
            if (!*why) p2p_check_blocks(&net, k, chain, nchain, gvr, "blocks_by_range", why);
        }
        if (!*why) { /* the head, a root the node does not know, and the first block, by root */
            uint8_t req[96];
            memcpy(req, chain[nchain - 1]->root, 32);
            memset(req + 32, 0xEE, 32);
            memcpy(req + 64, chain[0]->root, 32);
            case_block *want[2] = {chain[nchain - 1], chain[0]};
            int k = p2p_request(n, &net, 1, "beacon_blocks_by_root", 2, req, 96, why);
            if (!*why) p2p_check_blocks(&net, k, want, 2, gvr, "blocks_by_root", why);
        }
#if FORK >= FORK_FULU
        if (!*why) { /* the head's ancestry by head, in descending slot order, with a count past the chain */
            uint8_t req[40];
            memcpy(req, chain[nchain - 1]->root, 32);
            wr64(req + 32, nchain + 5);
            case_block **want = calloc(nchain, sizeof *want);
            for (size_t i = 0; i < nchain; i++) want[i] = chain[nchain - 1 - i];
            int k = p2p_request(n, &net, 2, "beacon_blocks_by_head", 1, req, 40, why);
            if (!*why) p2p_check_blocks(&net, k, want, nchain, gvr, "blocks_by_head", why);
            free(want);
        }
#endif
#if FORK >= FORK_ALTAIR
        if (!*why) { /* the light client data: bootstraps of the anchor's root, the chain's first block and its head */
            const uint8_t *roots[3] = {chain[0]->parent, chain[0]->root, chain[nchain - 1]->root};
            p2p_lc_serve_check(n, &net, roots, 3, gvr, why);
        }
#endif
        if (!*why && rd64(n->shell->node + 136 + 8)) *why = "the node keeps a stream at the end"; /* Node_streams */
        p2p_close(&net);
    }
    free(chain);
    free(blocks);
}

static void p2p_settle(fc_node *n, struct p2p_net *net, const char **why);
static case_block **sync_chain; /* the chain p2p_synced waits for */
static size_t sync_nchain;
/* Whether the node imported the block of the root: an imported entry, or a block of its Db, which holds only those. */
static int shell_imported(const struct node_shell *s, const uint8_t *root) {
    const uint8_t *e = shell_block(s, root);
    return (e && rd64(e + NB_STATUS) == NB_IMPORTED) || shell_db_slot(s, root) != UINT64_MAX;
}

#define NODE_STREAMS 136 /* Node_streams: NodeStream entries of Node_stream_bytes (at 168) each */
static int sync_bare; /* set: a request of the node but Status and GetMetaData read its response with no NodeResponse */
static void sync_responses(const struct node_shell *s) {
    const uint8_t *e = s->node + rd64(s->node + NODE_STREAMS);
    for (uint64_t i = 0, c = rd64(s->node + NODE_STREAMS + 8), w = rd64(s->node + 168); i < c; i++, e += w)
        if (rd64(e + 32) == 6 && rd64(e + 16) != 1 && rd64(e + 16) != 6 && !rd64(e + 48)) sync_bare = 1; /* NODE_STREAM_RESPONSE, not REQRESP_STATUS or REQRESP_METADATA, no response */
}

static int p2p_synced(struct p2p_net *net, int arg) {
    (void)arg;
    sync_responses(net->shell);
    for (size_t b = 0; b < sync_nchain; b++)
        if (!shell_imported(net->shell, sync_chain[b]->root)) return 0;
    return 1;
}

/* Whether the node holds a NODE_BLOB_VALID entry of the block root and index, or the sidecar in its Db. */
static int shell_has_blob(const struct node_shell *s, const uint8_t *root, uint64_t index) {
    const uint8_t *e = s->node + rd64(s->node + NODE_BLOBS);
    for (uint64_t i = 0, c = rd64(s->node + NODE_BLOBS + 8); i < c; i++, e += NODE_BLOB_BYTES)
        if (!memcmp(e, root, 32) && rd64(e + 32) == index && rd64(e + 56) == NBLOB_VALID) return 1;
    uint64_t slot = shell_db_slot(s, root);
    if (slot == UINT64_MAX || index >= 128) return 0;
    const uint8_t *db = s->node + rd64(s->node + NODE_DB);
    const uint8_t *d = db + rd64(db + 24) + DB_SLOT_BYTES * (slot - rd64(db + 8)); /* DbSlot: indices at 72 */
    return d[72 + index / 8] >> (index % 8) & 1;
}

/* Whether a block of a case has blob or column sidecars. */
static int block_has_sidecars(const case_block *b) {
    return (b->sidecars && rd64(b->sidecars + 1)) || (b->columns && rd64(b->columns + 1));
}

/* The first block of the chain with sidecars: the one that waits for its blobs or columns when the peer sends none. */
static size_t sync_first_blobs(void) {
    for (size_t b = 0; b < sync_nchain; b++)
        if (block_has_sidecars(sync_chain[b])) return b;
    return sync_nchain;
}

#if FORK >= FORK_FULU
/* The columns of the groups of get_custody_groups(node_id, count), as bits in 16 bytes. */
static void custody_columns(const uint8_t *node_id, uint64_t count, uint8_t *out, const char **why) {
    uint8_t list[24 + 8 * 128];
    memset(out, 0, 16);
    wr64(list, sizeof list);
    if (CALL(LF(get_custody_groups), node_id, &count, config, list) != 0) {
        *why = "get_custody_groups status";
        return;
    }
    uint64_t groups = rd64(config + 280); /* NUMBER_OF_CUSTODY_GROUPS */
    for (uint64_t i = 0, n = rd64(list + 16); i < n; i++)
        for (uint64_t j = 0, g = rd64(list + 24 + 8 * i); j < 128 / groups; j++)
            out[(groups * j + g) / 8] |= (uint8_t)(1u << ((groups * j + g) % 8));
}

/* The node's columns: of max(SAMPLES_PER_SLOT, CUSTODY_REQUIREMENT) groups of its node ID, the peer's. */
static void node_columns(uint8_t *out, const char **why) {
    uint8_t nid[32];
    uint64_t samples = rd64(config + 272), custody = rd64(config + 288);
    peer_node_id(nid, why);
    if (!*why) custody_columns(nid, samples > custody ? samples : custody, out, why);
}

/* The DataColumnSidecar bytes of column c among the names of a block's columns, or NULL. */
static const uint8_t *case_column(tv parts, tv names, uint64_t c, uint64_t *len) {
    tv e = names ? names + 9 : NULL;
    for (uint64_t i = 0, n = names ? rd64(names + 1) : 0; i < n; i++, e = tv_skip(e)) {
        char key[128];
        snprintf(key, sizeof key, "%.*s", (int)rd64(e + 1), (const char *)(e + 9));
        const uint8_t *sb = tv_bytes(tv_get(parts, key), len);
        if (sb && *len >= 8 && rd64(sb) == c) return sb;
    }
    return NULL;
}

/*
 * After a sync with column sidecars, the node serves them: DataColumnSidecarsByRange of every
 * column from the anchor's slot to the head's gives each sidecar of its columns in (slot, index)
 * order, and DataColumnSidecarsByRoot of the chain's blocks from the last to the first, each with
 * its columns and one it does not sample, then a root of no block, gives those sidecars in that
 * order. Each chunk is checked as a block's is.
 */
static void sync_serve_columns(fc_node *m, struct p2p_net *net, tv parts, case_block **chain, size_t nchain,
                               const uint8_t *cols, const char **why) {
    size_t ns = 0, ncols = 0;
    uint64_t other = 128;
    for (uint64_t c = 0; c < 128; c++) {
        if (cols[c / 8] >> (c % 8) & 1) ncols++;
        else if (other == 128) other = c;
    }
    for (size_t b = 0; b < nchain; b++)
        for (uint64_t c = 0, len; c < 128; c++)
            if ((cols[c / 8] >> (c % 8) & 1) && case_column(parts, chain[b]->columns, c, &len)) ns++;
    if (!ns) return;
    case_block *one = xmalloc(sizeof *one * ns), **want = xmalloc(sizeof *want * ns);
    size_t k = 0;
    for (size_t b = 0; b < nchain; b++) /* by range: (slot, index) order */
        for (uint64_t c = 0, len; c < 128; c++) {
            const uint8_t *sb = (cols[c / 8] >> (c % 8) & 1) ? case_column(parts, chain[b]->columns, c, &len) : NULL;
            if (!sb) continue;
            memset(&one[k], 0, sizeof one[k]);
            one[k].slot = chain[b]->slot;
            one[k].bytes = sb;
            one[k].len = len;
            want[k] = &one[k];
            k++;
        }
    uint8_t req[20 + 8 * 128];
    uint64_t anchor_slot = rd64(m->shell->node + 216); /* Node_earliest_slot */
    wr64(req, anchor_slot);
    wr64(req + 8, chain[nchain - 1]->slot - anchor_slot + 1);
    memset(req + 16, 0, 4);
    req[16] = 20;
    for (uint64_t c = 0; c < 128; c++) wr64(req + 20 + 8 * c, c);
    int st = p2p_request(m, net, 1, "data_column_sidecars_by_range", 1, req, sizeof req, why);
    if (!*why) p2p_check_blocks(net, st, want, ns, net->gvr, "data_column_sidecars_by_range", why);
    size_t nid = nchain + 1, w = 0, isize = 36 + 8 * (ncols + 1), size = 4 * nid + isize * nchain + 36 + 8;
    uint8_t *ids = xmalloc(size), *at = ids + 4 * nid; /* by root: the offsets, then each identifier */
    for (size_t b = nchain, i = 0; b-- > 0; i++) {
        uint64_t off = (uint64_t)(at - ids);
        for (int j = 0; j < 4; j++) ids[4 * i + (size_t)j] = (uint8_t)(off >> (8 * j));
        memcpy(at, chain[b]->root, 32);
        memset(at + 32, 0, 4);
        at[32] = 36;
        uint64_t n = 0;
        for (uint64_t c = 0; c < 128; c++)
            if (cols[c / 8] >> (c % 8) & 1) {
                wr64(at + 36 + 8 * n++, c);
                if (!*why && w < ns) {
                    for (size_t q = 0; q < ns; q++) /* its sidecar, when the chain has it */
                        if (one[q].slot == chain[b]->slot && rd64(one[q].bytes) == c) want[w++] = &one[q];
                }
            }
        wr64(at + 36 + 8 * n++, other);
        at += 36 + 8 * n;
    }
    uint64_t off = (uint64_t)(at - ids);
    for (int j = 0; j < 4; j++) ids[4 * nchain + (size_t)j] = (uint8_t)(off >> (8 * j));
    memset(at, 0xEE, 32);
    memset(at + 32, 0, 4);
    at[32] = 36;
    wr64(at + 36, 0);
    at += 44;
    if (!*why) st = p2p_request(m, net, 2, "data_column_sidecars_by_root", 1, ids, (uint64_t)(at - ids), why);
    if (!*why) p2p_check_blocks(net, st, want, w, net->gvr, "data_column_sidecars_by_root", why);
    free(ids);
    free(want);
    free(one);
}
#endif
static int p2p_blobs_wait(struct p2p_net *net, int arg) {
    (void)arg;
    sync_responses(net->shell);
    size_t f = sync_first_blobs();
    for (size_t b = 0; b < f; b++)
        if (!shell_imported(net->shell, sync_chain[b]->root)) return 0;
    const uint8_t *e = shell_block(net->shell, sync_chain[f]->root);
    return e && rd64(e + NB_STATUS) == NB_BLOBS;
}

static void api_sidecar_checks(fc_node *n, tv parts, case_block **chain, size_t nchain, const uint8_t *cols, const char **why);
static void api_blob_checks(fc_node *n, tv parts, case_block **chain, size_t nchain, int supernode, const char **why);
#if FORK >= FORK_FULU
static void api_supernode_identity(fc_node *n, const char **why);
#endif

/*
 * After a sync with sidecars, the node serves them: BlobSidecarsByRange of the anchor's slot to the
 * head's gives every sidecar of the chain in (slot, index) order, and BlobSidecarsByRoot of the
 * chain's sidecars from the last block to the first, with an identifier of no sidecar after the
 * first, gives those sidecars in that order. Each chunk is checked as a block's is: result 0, the
 * ForkDigest of its slot's epoch, its SSZ bytes.
 */
static void sync_serve_blobs(fc_node *m, struct p2p_net *net, case_block **chain, size_t nchain, const char **why) {
    size_t ns = 0;
    for (size_t b = 0; b < nchain; b++) ns += chain[b]->sidecars ? (size_t)rd64(chain[b]->sidecars + 1) : 0;
    if (!ns) return;
    case_block *one = xmalloc(sizeof *one * ns), **want = xmalloc(sizeof *want * ns);
    uint8_t *ids = xmalloc(40 * (ns + 1));
    size_t k = 0;
    for (size_t b = 0; b < nchain; b++) { /* by range: (slot, index) order */
        tv sc = chain[b]->sidecars ? chain[b]->sidecars + 9 : NULL;
        for (uint64_t i = 0, c = sc ? rd64(chain[b]->sidecars + 1) : 0; i < c; i++, sc = tv_skip(sc), k++) {
            memset(&one[k], 0, sizeof one[k]);
            one[k].slot = chain[b]->slot;
            one[k].bytes = tv_bytes(sc, &one[k].len);
            want[k] = &one[k];
        }
    }
    uint8_t req[16];
    uint64_t anchor_slot = rd64(m->shell->node + 216); /* Node_earliest_slot */
    wr64(req, anchor_slot);
    wr64(req + 8, chain[nchain - 1]->slot - anchor_slot + 1);
    int st = p2p_request(m, net, 1, "blob_sidecars_by_range", 1, req, 16, why);
    if (!*why) p2p_check_blocks(net, st, want, ns, net->gvr, "blob_sidecars_by_range", why);
    size_t nid = 0, w = 0; /* by root: from the last block to the first, an unknown identifier after the first */
    for (size_t b = nchain, at = ns; b-- > 0;) {
        uint64_t c = chain[b]->sidecars ? rd64(chain[b]->sidecars + 1) : 0;
        at -= (size_t)c;
        for (uint64_t i = 0; i < c; i++) {
            memcpy(ids + 40 * nid, chain[b]->root, 32);
            wr64(ids + 40 * nid + 32, i);
            nid++;
            want[w++] = &one[at + i];
            if (nid == 1) {
                memset(ids + 40 * nid, 0xEE, 32);
                wr64(ids + 40 * nid + 32, 0);
                nid++;
            }
        }
    }
    if (!*why) st = p2p_request(m, net, 2, "blob_sidecars_by_root", 1, ids, 40 * nid, why);
    if (!*why) p2p_check_blocks(net, st, want, w, net->gvr, "blob_sidecars_by_root", why);
    free(ids);
    free(want);
    free(one);
}

/*
 * A node record made with asm-discv5 from the secp256k1 key of bytes seed + 1 to seed + 32: ip
 * 10.0.0.2, udp and tcp 9000, eth2 of lantern_compute_enr_fork_id at the epoch, and with cgc at 0
 * or above, a cgc of it (big-endian, no leading zero byte). out: a ByteList of 24 + 300 bytes.
 */
static void record_of(const uint8_t *gvr, uint64_t epoch, int seed, int64_t cgc, uint8_t *out, const char **why) {
    uint8_t cfg[152] = {0}, tick[40] = {0}, ncfg[CONFIG_SIZE], ev[24 + 56 + 64 + 56] = {0};
    for (int i = 0; i < 32; i++) cfg[i] = (uint8_t)(seed + i + 1);
    wr64(cfg + 32, 1);         /* seq */
    memset(cfg + 40, 7, 32);   /* entropy */
    wr64(cfg + 72, 1000);      /* now */
    wr64(cfg + 80, 9000);      /* the udp port */
    wr64(cfg + 88, 4);
    cfg[96] = 10;
    cfg[99] = 2;
    wr64(ev, sizeof ev);       /* SET_ENTRY tcp 9000, SET_ENTRY eth2 */
    wr64(ev + 8, 24);
    wr64(ev + 16, 56 + 64);
    wr64(ev + 24, 56);
    wr64(ev + 32, 5);
    wr64(ev + 40, 3);
    memcpy(ev + 48, "tcp", 3);
    wr64(ev + 64, 2);
    ev[72] = 9000 >> 8;
    ev[73] = 9000 & 255;
    wr64(ev + 80, 64);
    wr64(ev + 88, 5);
    wr64(ev + 96, 4);
    memcpy(ev + 104, "eth2", 4);
    wr64(ev + 120, 16);
    if (cgc >= 0) { /* SET_ENTRY cgc */
        uint64_t nb = 0;
        for (uint64_t t = (uint64_t)cgc; t; t >>= 8) nb++;
        wr64(ev + 16, 56 + 64 + 56);
        wr64(ev + 144, 56);
        wr64(ev + 152, 5);
        wr64(ev + 160, 3);
        memcpy(ev + 168, "cgc", 3);
        wr64(ev + 184, nb);
        for (uint64_t b = 0; b < nb; b++) ev[192 + b] = (uint8_t)((uint64_t)cgc >> (8 * (nb - 1 - b)));
    }
    node_config(ncfg);
    if (CALL(LF(compute_enr_fork_id), gvr, &epoch, ncfg, fresh_scratch(), ev + 128) != 0) {
        *why = "compute_enr_fork_id status";
        return;
    }
    uint8_t *st = buffer(DISCV5_STATE_SIZE), *scr = buffer(DISCV5_SCRATCH_SIZE), *acts = buffer(DISCV5_ACTIONS_ROOM + 16384);
    wr64(scr, DISCV5_SCRATCH_SIZE);
    wr64(acts, DISCV5_ACTIONS_ROOM + 16384); /* a third SET_ENTRY event: cgc */
    wr64(tick, 1001);
    memset(tick + 8, 9, 32);
    wr64(out, 24 + 300);
    if (CALL(discv5_init, cfg, st) != 0) *why = "discv5_init status";
    else {
        uint64_t st5 = CALL(discv5_step, st, tick, ev, scr, acts);
        static char msg[48];
        snprintf(msg, sizeof msg, "discv5_step status %llu", (unsigned long long)st5);
        if (st5 != 0) *why = msg;
    }
    if (!*why && CALL(discv5_local_record, st, out) != 0) *why = "discv5_local_record status";
    free(st);
    free(scr);
    free(acts);
}

/* The node record of the runner's peer, from the peer's secp256k1 key (p2p_config of side 1), with no cgc. */
static void peer_record(const uint8_t *gvr, uint64_t epoch, uint8_t *out, const char **why) { record_of(gvr, epoch, 31, -1, out, why); }

/*
 * One sync of the chain: a new node at the case's anchor, at last_ms, gets the Status of a peer
 * whose head is the chain's last block, and syncs from it. With no_blobs the peer sends no
 * sidecar: the first block with sidecars must wait for them, and neither it nor a later block
 * may be imported. Else the node must import the chain, take its last block as head, and hold
 * each sidecar the peer sent.
 */
static int sync_supernode; /* set: the sync's node has NODE_FLAG_SUPERNODE */
static int sync_half; /* set: the peer serves the even columns only, so the supernode rebuilds the others */
static int sync_dead; /* set: a peer with no connection goes first in the node's peers part (node.md, sync_peer) */
static int sync_retry; /* set: the peer serves sidecars only after the first block with them waits (the sidecar retry) */
static int sync_partial; /* fulu, with sync_retry: the peer leaves out the node's lowest column until then (node.md, the retry's columns) */
static void sync_once(tv parts, case_block **chain, size_t nchain, uint64_t last_ms, int no_blobs, uint8_t **head_state,
                      uint64_t *head_size, const char **why) {
    fc_node m;
    uint8_t *anchor_block;
    force_supernode = sync_supernode;
    struct node_shell *s = shell_open(&m, parts, &anchor_block, why);
    force_supernode = 0;
    uint64_t genesis_ms = *why ? 0 : rd64(m.store + STORE_GENESIS_TIME_MS);
    if (!*why) { /* with half the columns, a slot later: the node waits a third of a block's slot before it rebuilds */
        shell_event(s, EV_TICK, last_ms + (sync_half ? rd64(config + 104) : 0), NULL, 0);
        shell_settle(&m, why);
    }
    struct p2p_net net;
    uint8_t gvr[32], ncfg[CONFIG_SIZE], status[96] = {0}, digest[8] = {0}, record[24 + 300];
    memcpy(gvr, m.anchor + field_offset("BeaconState", 1), 32);
    node_config(ncfg);
    uint64_t epoch = last_ms < genesis_ms ? 0 : (last_ms - genesis_ms) / rd64(config + 104) / SLOTS_PER_EPOCH_RUNNER;
    CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), digest);
    memcpy(status, digest, 4); /* fork_digest, finalized (0, 0), head_root, head_slot, earliest_available_slot */
    memcpy(status + 44, chain[nchain - 1]->root, 32);
    wr64(status + 76, chain[nchain - 1]->slot);
    if (!*why) wr64(status + 84, rd64(s->node + 216)); /* Node_earliest_slot */
    if (!*why) peer_record(gvr, epoch, record, why);
    /* The node dials the peer of the record and sends its Status; the peer answers with this one. */
    if (!*why) p2p_open_record(&m, &net, record + 24, rd64(record + 16), status, FORK >= FORK_FULU ? 92 : 84, why);
    if (!*why) {
        net.chain = chain;
        net.nchain = nchain;
        net.no_blobs = no_blobs;
        net.half_columns = sync_half;
        net.cut = sync_dead; /* with the dead peer: a gap, then a short answer */
        net.parts = parts;
        memcpy(net.gvr, gvr, 32);
#if FORK >= FORK_FULU
        uint8_t nid[32], cols[16];
        node_columns(cols, why); /* with no sidecars, a peer of CUSTODY_REQUIREMENT groups: the node asks for those */
        if (sync_supernode) memset(cols, 0xFF, 16); /* a supernode: every column */
        net.peer_cgc = no_blobs && !sync_retry ? rd64(config + 288) : rd64(config + 280);
        if (!*why) peer_node_id(nid, why);
        if (!*why && no_blobs && !sync_retry) custody_columns(nid, net.peer_cgc, net.want_columns, why);
        else if (!*why) memcpy(net.want_columns, cols, 16);
        if (sync_partial) { /* every column but the lowest; a retry asks for that one alone */
            net.no_blobs = 0;
            for (uint64_t c = 0; c < 128 && !net.skip_column; c++)
                if (cols[c / 8] >> (c % 8) & 1) net.skip_column = c + 1;
            if (net.skip_column) net.retry_columns[(net.skip_column - 1) / 8] = (uint8_t)(1u << ((net.skip_column - 1) % 8));
        }
        if (sync_half) /* the even columns only: a retry asks for the odd ones */
            for (uint64_t c = 1; c < 128; c += 2)
                if (cols[c / 8] >> (c % 8) & 1) net.retry_columns[c / 8] |= (uint8_t)(1u << (c % 8));
#endif
        sync_chain = chain;
        sync_nchain = nchain;
        if (!*why && sync_dead) { /* before the peer, one whose handle works no more: each request to it fails */
            uint8_t *peers = s->node + rd64(s->node + NODE_PEERS);
            uint64_t np = rd64(s->node + NODE_PEERS + 8);
            memmove(peers + NODE_PEER_BYTES, peers, (size_t)(np * NODE_PEER_BYTES));
            memset(peers, 0, NODE_PEER_BYTES);
            wr64(peers, rd64(peers + NODE_PEER_BYTES) + ((uint64_t)0x100 << 32)); /* the peer's slot, a later generation */
            wr64(peers + 16, 1 | 4);                   /* NODE_PEER_STATUS, NODE_PEER_METADATA, no custody */
            memcpy(peers + 24, digest, 4);             /* fork_digest */
            wr64(peers + 104, chain[nchain - 1]->slot); /* head_slot */
            wr64(s->node + NODE_PEERS + 8, np + 1);
            /* before both, one whose earliest_slot is past the chain: it serves none of it, and no range request may go to it */
            np++;
            memmove(peers + NODE_PEER_BYTES, peers, (size_t)(np * NODE_PEER_BYTES));
            memset(peers, 0, NODE_PEER_BYTES);
            wr64(peers, rd64(peers + NODE_PEER_BYTES) + ((uint64_t)0x100 << 32)); /* the dead peer's slot, a later generation */
            wr64(peers + 16, 1 | 4);
            memcpy(peers + 24, digest, 4);
            wr64(peers + 104, chain[nchain - 1]->slot);
            wr64(peers + 112, chain[nchain - 1]->slot + 1); /* earliest_slot */
            memset(peers + 176, 0xff, 16);
            wr64(peers + NODE_PEER_STATUS_MS, (uint64_t)1 << 62);
            wr64(s->node + NODE_PEERS + 8, np + 1);
            idle_peer_index = 0;
            wr64(s->node + 728 + CONFIG_SIZE + 936 + 1848 + 8 * (4 + 64), 0); /* Node_sync_peer: the next request looks from it on */
        }
        engine_fcu_error = sync_dead && FORK >= FORK_BELLATRIX; /* each forkchoiceUpdated fails: the imports go on */
        if (!*why && sync_dead) { /* the peer holds the first BeaconBlocksByRange: NODE_REQUEST_MS later the node resets it */
            net.silent = 1;
            p2p_run(&m, &net, p2p_held, 0, why);
            if (*why && !strcmp(*why, "the network does not get there")) *why = "sync with a silent peer: the node sends no BeaconBlocksByRange";
            if (!*why) shell_event(s, EV_TICK, last_ms + 10000, NULL, 0); /* NODE_REQUEST_MS */
            if (!*why) p2p_run(&m, &net, p2p_reset_seen, 0, why);
            if (*why && !strcmp(*why, "the network does not get there")) *why = "sync with a silent peer: the node does not reset its request";
            net.silent = 0;
        }
        if (!*why) p2p_run(&m, &net, no_blobs ? p2p_blobs_wait : p2p_synced, 0, why);
        engine_fcu_error = 0;
        if (*why && !strcmp(*why, "the network does not get there"))
            *why = no_blobs ? "sync with no sidecars: the first block with blobs does not wait for them"
                 : sync_dead ? "sync with a peer that fails first: the node does not import the chain"
                             : "sync: the node does not import the peer's chain";
        if (!*why && sync_bare) *why = "sync: a request of the node reads its response with no NodeResponse";
        sync_bare = 0;
        if (!*why && sync_retry) { /* the peer has the sidecars now: from a slot later the node must ask again */
            shell_settle(&m, why);
            if (!*why) p2p_settle(&m, &net, why);
            net.no_blobs = no_blobs = 0;
#if FORK >= FORK_FULU
            if (sync_partial) { /* the retry asks for the lowest column only; the answers hold the others too */
                uint64_t c0 = net.skip_column - 1;
                memset(net.want_columns, 0, 16);
                net.want_columns[c0 / 8] = (uint8_t)(1u << (c0 % 8));
                memset(net.retry_columns, 0, 16);
                memcpy(net.extra_columns, cols, 16);
                net.extra_columns[c0 / 8] &= (uint8_t)~(1u << (c0 % 8));
                net.skip_column = 0;
            }
#endif
            uint64_t later = rd64(config + 104) > 4000 ? rd64(config + 104) : 4000; /* NODE_SIDECAR_RETRY_MS */
            if (!*why) shell_event(s, EV_TICK, last_ms + later, NULL, 0);
            if (!*why) p2p_run(&m, &net, p2p_synced, 0, why);
            if (*why && !strcmp(*why, "the network does not get there"))
                *why = sync_partial ? "sync with a column left out: the node does not ask for it again"
                                    : "sync with sidecars a slot later: the node does not ask for them again";
            if (!*why && sync_partial) { /* the copies leave no entry: each is valid, one of a root and index, or free */
                shell_settle(&m, why);
                const uint8_t *e = s->node + rd64(s->node + NODE_BLOBS), *f;
                uint64_t c = rd64(s->node + NODE_BLOBS + 8);
                for (uint64_t i = 0; i < c && !*why; i++, e += NODE_BLOB_BYTES) {
                    if (rd64(e + 56) != NBLOB_VALID && rd64(e + 56) != 4) *why = "sync with a column left out: a NodeBlob neither valid nor free";
                    f = e + NODE_BLOB_BYTES;
                    for (uint64_t j = i + 1; j < c && !*why && rd64(e + 56) == NBLOB_VALID; j++, f += NODE_BLOB_BYTES)
                        if (rd64(f + 56) == NBLOB_VALID && rd64(f + 32) == rd64(e + 32) && !memcmp(f, e, 32))
                            *why = "sync with a column left out: two valid entries of a root and index";
                }
            }
        }
        if (!*why) shell_settle(&m, why);
        if (!*why && no_blobs) {
            p2p_settle(&m, &net, why);
            for (size_t b = sync_first_blobs(); b < nchain && !*why; b++) {
                if (shell_imported(s, chain[b]->root)) *why = "sync with no sidecars: a block from the first with blobs is imported";
            }
        } else if (!*why) {
            if (memcmp(s->node + NODE_HEAD_ROOT, chain[nchain - 1]->root, 32)) *why = "sync: the head is not the chain's last block";
            for (size_t b = 0; b < nchain && !*why; b++)
                for (uint64_t i = 0, c = chain[b]->sidecars ? rd64(chain[b]->sidecars + 1) : 0; i < c; i++)
                    if (!shell_has_blob(s, chain[b]->root, i)) *why = "sync: a sidecar the peer sent is not a valid NodeBlob";
            if (!*why) sync_serve_blobs(&m, &net, chain, nchain, why);
#if FORK < FORK_FULU
            if (!*why) api_sidecar_checks(&m, parts, chain, nchain, NULL, why);
            if (!*why) api_blob_checks(&m, parts, chain, nchain, 0, why);
#endif
#if FORK >= FORK_FULU
            for (size_t b = 0; b < nchain && !*why; b++) /* each column sidecar of its columns the peer sent */
                for (uint64_t c = 0, len; c < 128 && !*why; c++)
                    if ((cols[c / 8] >> (c % 8) & 1) && case_column(parts, chain[b]->columns, c, &len) &&
                        !shell_has_blob(s, chain[b]->root, c))
                        *why = "sync: a column sidecar the peer sent is not a valid NodeBlob";
            if (sync_supernode) { /* a supernode: its custody group count, and the blobs of its columns */
                for (size_t b = 0; b < nchain && sync_half && !*why; b++) /* its rebuilt columns: the case's sidecars */
                    for (uint64_t c = 1, len; c < 128 && !*why; c += 2) {
                        const uint8_t *want = case_column(parts, chain[b]->columns, c, &len);
                        if (!want) continue;
                        const uint8_t *e = s->node + rd64(s->node + NODE_BLOBS), *got = NULL;
                        uint64_t glen = 0;
                        for (uint64_t i = 0, n = rd64(s->node + NODE_BLOBS + 8); i < n && !got; i++, e += NODE_BLOB_BYTES)
                            if (!memcmp(e, chain[b]->root, 32) && rd64(e + 32) == c && rd64(e + 56) == NBLOB_VALID) {
                                shell_buf *bb = shell_find(s, rd64(e + 48));
                                if (bb) {
                                    got = bb->b + rd64(bb->b + 8);
                                    glen = rd64(bb->b + 16);
                                }
                            }
                        if (!got || glen != len || memcmp(got, want, (size_t)len))
                            *why = "sync with half the columns: a rebuilt column sidecar is not the case's";
                    }
                if (!*why) api_supernode_identity(&m, why);
                if (!*why) api_blob_checks(&m, parts, chain, nchain, 1, why);
            } else {
                if (!*why) sync_serve_columns(&m, &net, parts, chain, nchain, cols, why);
                if (!*why) api_sidecar_checks(&m, parts, chain, nchain, cols, why);
                if (!*why) api_blob_checks(&m, parts, chain, nchain, 0, why);
            }
#endif
        }
#if FORK >= FORK_FULU
        if (!*why && !net.column_requests) *why = "sync: the node sends no DataColumnSidecarsByRange";
#endif
        p2p_close(&net);
    }
    if (!*why && head_state) { /* the post-state of the chain's last block */
        const uint8_t *e = shell_block(s, chain[nchain - 1]->root);
        shell_buf *h = e ? shell_find(s, rd64(e + NB_STATE_ID)) : NULL;
        if (!h) *why = "sync: the head has no post-state";
        else {
            *head_state = copy_of(h->b, h->size);
            *head_size = h->size;
        }
    }
    idle_peer_index = UINT64_MAX;
    shell_close(&m, anchor_block);
}

/*
 * Node mode, after fc_serve_check: a new node at the case's anchor, at the case's last tick, gets
 * the Status of a peer whose head is the chain's last block; it must sync the chain from the
 * peer with BeaconBlocksByRange and BlobSidecarsByRange, and take its last block as head. A chain
 * with sidecars syncs again with none sent.
 */
/* Whether the node keeps no peer. */
static int p2p_dropped(struct p2p_net *net, int arg) {
    (void)arg;
    return rd64(net->shell->node + NODE_PEERS + 8) == 0;
}

/*
 * The Status rules (node.md): a new node at the case's anchor, at its last tick, dials a peer whose
 * Status has another fork_digest; it must disconnect it.
 */
static void status_check(tv parts, uint64_t last_ms, const char **why) {
    fc_node m;
    uint8_t *anchor_block;
    struct node_shell *s = shell_open(&m, parts, &anchor_block, why);
    uint64_t genesis_ms = *why ? 0 : rd64(m.store + STORE_GENESIS_TIME_MS);
    if (!*why) {
        shell_event(s, EV_TICK, last_ms, NULL, 0);
        shell_settle(&m, why);
    }
    struct p2p_net net;
    uint8_t gvr[32], ncfg[CONFIG_SIZE], status[96] = {0}, record[24 + 300];
    memcpy(gvr, m.anchor + field_offset("BeaconState", 1), 32);
    node_config(ncfg);
    uint64_t epoch = last_ms < genesis_ms ? 0 : (last_ms - genesis_ms) / rd64(config + 104) / SLOTS_PER_EPOCH_RUNNER;
    CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), status);
    status[0] ^= 0xFF; /* another fork_digest; finalized (0, 0) */
    if (!*why) peer_record(gvr, epoch, record, why);
    if (!*why) {
        p2p_open_record(&m, &net, record + 24, rd64(record + 16), status, FORK >= FORK_FULU ? 92 : 84, why);
        if (!*why) p2p_run(&m, &net, p2p_dropped, 0, why);
        if (*why && !strcmp(*why, "the network does not get there")) *why = "status: the node keeps a peer of another fork_digest";
        p2p_close(&net);
    }
    shell_close(&m, anchor_block);
}

#define NODE_BACKFILL_HANDLE 560 /* include/lantern.inc: Node_backfill_handle */
#define NODE_BACKFILL_SLOT 568
#define NB_BF_CHECKING 10
#define NB_BACKFILL 11
static case_block **bf_chain;
static size_t bf_nchain, bf_above; /* the blocks from bf_above up must reach the Db */

/* Whether the blocks of the chain from bf_above up are in the Db, and the backfill has no request or block open. */
static int p2p_backfilled(struct p2p_net *net, int arg) {
    (void)arg;
    const struct node_shell *s = net->shell;
    for (size_t b = bf_above; b < bf_nchain; b++)
        if (shell_db_slot(s, bf_chain[b]->root) == UINT64_MAX) return 0;
    if (rd64(s->node + NODE_BACKFILL_HANDLE)) return 0;
    const uint8_t *e = s->node + rd64(s->node + NODE_BLOCKS);
    for (uint64_t i = 0, c = rd64(s->node + NODE_BLOCKS + 8); i < c; i++, e += NODE_BLOCK_BYTES)
        if (rd64(e + NB_STATUS) == NB_BF_CHECKING || rd64(e + NB_STATUS) == NB_BACKFILL) return 0;
    return 1;
}

#if FORK >= FORK_FULU
/* The node's backfill request is open; then answered and weighed, with no block in NODE_BLOCK_BF_CHECKING. */
static int p2p_backfill_open(struct p2p_net *net, int arg) {
    (void)arg;
    return rd64(net->shell->node + NODE_BACKFILL_HANDLE) != 0;
}
static int p2p_backfill_weighed(struct p2p_net *net, int arg) {
    (void)arg;
    const uint8_t *node = net->shell->node, *e = node + rd64(node + NODE_BLOCKS);
    if (rd64(node + NODE_BACKFILL_HANDLE) || rd64(node + 648) != UINT64_MAX) return 0; /* Node_backfill_start */
    for (uint64_t i = 0, c = rd64(node + NODE_BLOCKS + 8); i < c; i++, e += NODE_BLOCK_BYTES)
        if (rd64(e + NB_STATUS) == NB_BF_CHECKING) return 0;
    return 1;
}
/* The node's entry of the peer holds an earliest_slot of 0. */
static int p2p_peer_earliest_zero(struct p2p_net *net, int arg) {
    (void)arg;
    const uint8_t *node = net->shell->node;
    return rd64(node + NODE_PEERS + 8) == 1 && rd64(node + rd64(node + NODE_PEERS) + 112) == 0;
}
#endif

/*
 * The backfill (node.md): a node with NODE_FLAG_DB from the post-state and the block of the chain's
 * last block, at the case's last tick, gets a peer whose Status head is that block. The peer
 * answers BeaconBlocksByRange with the chain's blocks; each must reach the Db, and backfill_slot is
 * the first's. With bad, the block at bad has another signature: it and those below stay out.
 */
static void api_headers_db_checks(fc_node *n, case_block **chain, size_t nchain, const char **why);
static void backfill_once(tv parts, case_block **chain, size_t nchain, uint64_t last_ms, size_t bad, int late,
                          const char **why) {
    uint64_t vsize = 0;
    uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), chain[nchain - 1]->bytes, chain[nchain - 1]->len, &vsize, why);
    if (!sb) return;
    bf_block = nested(sb, field_offset("SignedBeaconBlock", 0));
    fc_node m;
    uint8_t *anchor_block;
    struct node_shell *s = shell_open(&m, parts, &anchor_block, why);
    bf_block = NULL;
    free(sb);
    if (!*why) {
        shell_event(s, EV_TICK, last_ms, NULL, 0);
        shell_settle(&m, why);
    }
    case_block *served[1024], badblock;
    uint8_t *badbytes = NULL;
    if (nchain > 1024) *why = "backfill: a chain of more than 1024 blocks";
    for (size_t b = 0; b < nchain && !*why; b++) served[b] = chain[b];
    if (!*why && bad < nchain) {
        badblock = *chain[bad];
        badbytes = (uint8_t *)copy_of(chain[bad]->bytes, chain[bad]->len);
        badbytes[4 + 40] ^= 0x01; /* a bit of the signature's x coordinate */
        badblock.bytes = badbytes;
        served[bad] = &badblock;
    }
    struct p2p_net net;
    uint64_t genesis_ms = *why ? 0 : rd64(m.store + STORE_GENESIS_TIME_MS);
    uint8_t gvr[32], ncfg[CONFIG_SIZE], status[96] = {0}, record[24 + 300];
    if (!*why) {
        memcpy(gvr, m.anchor + field_offset("BeaconState", 1), 32);
        node_config(ncfg);
        uint64_t epoch = last_ms < genesis_ms ? 0 : (last_ms - genesis_ms) / rd64(config + 104) / SLOTS_PER_EPOCH_RUNNER;
        CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), status);
        memcpy(status + 44, chain[nchain - 1]->root, 32); /* finalized (0, 0), head the chain's last block */
        wr64(status + 76, chain[nchain - 1]->slot);
        if (late) wr64(status + 84, chain[nchain - 1]->slot); /* earliest_available_slot: its sidecars' first */
        peer_record(gvr, epoch, record, why);
    }
    if (!*why) {
        p2p_open_record(&m, &net, record + 24, rd64(record + 16), status, FORK >= FORK_FULU ? 92 : 84, why);
        if (!*why) {
            net.chain = served;
            net.nchain = nchain;
            net.no_blobs = 0; /* the peer serves the chain's sidecars too */
            net.parts = parts;
            memcpy(net.gvr, gvr, 32);
#if FORK >= FORK_FULU
            uint8_t cols[16];
            node_columns(cols, why);
            net.peer_cgc = rd64(config + 280);
            memcpy(net.want_columns, cols, 16);
#endif
            bf_chain = chain;
            bf_nchain = nchain;
            bf_above = bad < nchain ? bad + 1 : 0;
#if FORK >= FORK_FULU
            if (late) { /* the peer serves no sidecar below its earliest slot: none is asked of it, and no block joins the Db */
                net.column_floor = chain[nchain - 1]->slot;
                p2p_run(&m, &net, p2p_backfill_open, 0, why);
                if (*why && !strcmp(*why, "the network does not get there")) *why = "backfill with a late peer: no request";
                if (!*why) p2p_run(&m, &net, p2p_backfill_weighed, 0, why);
                if (*why && !strcmp(*why, "the network does not get there")) *why = "backfill with a late peer: the request is not weighed";
                for (size_t b = 0; b + 1 < nchain && !*why; b++) /* a block with columns waits for them */
                    if (chain[b]->columns && shell_db_slot(s, chain[b]->root) != UINT64_MAX)
                        *why = "backfill with a late peer: a block with columns joins the Db with no sidecars asked";
                /* the peer backfills: its next Status, at the Status refresh, gives earliest_available_slot 0 */
                wr64(net.status + 84, 0);
                net.column_floor = 0;
                uint64_t now = rd64(s->node + NODE_TIME_MS);
                if (!*why) shell_event(s, EV_TICK, now + SLOTS_PER_EPOCH_RUNNER / 2 * rd64(config + 104), NULL, 0);
                if (!*why) p2p_run(&m, &net, p2p_peer_earliest_zero, 0, why);
                if (*why && !strcmp(*why, "the network does not get there")) *why = "backfill with a late peer: no Status asked after half an epoch";
                if (!*why) p2p_run(&m, &net, p2p_backfill_weighed, 0, why); /* a request of that tick, before the new Status, ends */
                if (*why && !strcmp(*why, "the network does not get there")) *why = "backfill with a late peer: a request is not weighed";
                now = rd64(s->node + NODE_TIME_MS);
                if (!*why) shell_event(s, EV_TICK, now + 12000, NULL, 0); /* NODE_STATUS_MS: the backfill asks again */
            }
#endif
            if (!*why) p2p_run(&m, &net, p2p_backfilled, 0, why);
            if (*why && !strcmp(*why, "the network does not get there")) {
                static char msg[256];
                size_t in = 0;
                for (size_t b = 0; b < nchain; b++) in += shell_db_slot(s, chain[b]->root) != UINT64_MAX;
                snprintf(msg, sizeof msg, "%s: %zu of %zu blocks (slots %llu to %llu); backfill_slot %llu, next %llu, start %llu, got %llu, handle %llu",
                         bad < nchain ? "backfill: the blocks above one of another signature do not reach the Db"
                                      : "backfill: the chain does not reach the Db",
                         in, nchain, (unsigned long long)chain[0]->slot, (unsigned long long)chain[nchain - 1]->slot,
                         (unsigned long long)rd64(s->node + NODE_BACKFILL_SLOT), (unsigned long long)rd64(s->node + 624),
                         (unsigned long long)rd64(s->node + 648), (unsigned long long)rd64(s->node + 656),
                         (unsigned long long)rd64(s->node + NODE_BACKFILL_HANDLE));
                *why = msg;
            }
            for (size_t b = 0; b < nchain && !*why; b++) {
                int in = shell_db_slot(s, chain[b]->root) != UINT64_MAX;
                if (bad < nchain && b <= bad && in) *why = "backfill: a block of another signature, or one below it, is in the Db";
            }
            if (!*why && bad >= nchain && rd64(s->node + NODE_BACKFILL_SLOT) != chain[0]->slot)
                *why = "backfill: backfill_slot is not the slot of the chain's first block";
            if (!*why && bad >= nchain && rd64(s->node + 216) != chain[0]->slot) /* Node_earliest_slot */
                *why = "backfill: earliest_slot is not the slot of the chain's first block";
            for (size_t b = 0; b < nchain && !*why && bad >= nchain; b++) { /* each sidecar of the chain, in the Db */
                for (uint64_t i = 0, c = chain[b]->sidecars ? rd64(chain[b]->sidecars + 1) : 0; i < c; i++)
                    if (!shell_has_blob(s, chain[b]->root, i)) *why = "backfill: a blob sidecar of the chain is not in the Db";
#if FORK >= FORK_FULU
                for (uint64_t c = 0, len; c < 128 && !*why; c++)
                    if ((cols[c / 8] >> (c % 8) & 1) && case_column(parts, chain[b]->columns, c, &len) &&
                        !shell_has_blob(s, chain[b]->root, c))
                        *why = "backfill: a column sidecar of the chain is not in the Db";
#endif
            }
            p2p_close(&net);
            if (!*why && bad >= nchain && !late) api_headers_db_checks(&m, chain, nchain, why);
        }
    }
    free(badbytes);
    shell_close(&m, anchor_block);
}

static void backfill_check(tv parts, case_block **chain, size_t nchain, uint64_t last_ms, uint8_t *head_state,
                           uint64_t head_size, const char **why) {
    bf_state = head_state;
    bf_state_size = head_size;
    backfill_once(parts, chain, nchain, last_ms, SIZE_MAX, 0, why);
    if (!*why) backfill_once(parts, chain, nchain, last_ms, nchain / 2, 0, why);
#if FORK >= FORK_FULU
    if (!*why) backfill_once(parts, chain, nchain, last_ms, SIZE_MAX, 1, why); /* a peer of a later earliest slot */
#endif
    bf_state = NULL;
}

/*
 * The sidecar drop (node.md): a node with NODE_FLAG_DB whose Db holds a block and a sidecar at slot
 * 1 and a block in the third segment, with windows of 0 epochs, at a slot past them, must drop
 * sidecar segments 0 and 1 and no other, take sidecar_floor the third segment's first slot, and keep
 * every block of its index.
 */
#define NODE_SIDECAR_FLOOR 720 /* include/lantern.inc: Node_sidecar_floor */
#define NODE_CONFIG 728        /* Node_config */
static void drop_check(tv parts, const char **why) {
    fc_node m;
    uint8_t *anchor_block;
    drop_room = 1;
    struct node_shell *s = shell_open(&m, parts, &anchor_block, why);
    drop_room = 0;
    uint8_t *db = *why ? NULL : s->node + rd64(s->node + NODE_DB);
    uint64_t far = 2 * 8192 + 5;
    if (db && rd64(db + 8) != 0) *why = "drop: the Db does not start at slot 0";
    for (int r = 0; r < 3 && !*why; r++) { /* a block at 1, its sidecar, a block at far */
        uint8_t rec[80] = {0};
        uint64_t off = 0, slot = r == 2 ? far : 1;
        wr64(rec, r == 1 ? 2 : 1); /* DB_BLOB_SIDECAR, DB_BLOCK */
        wr64(rec + 8, slot);
        memset(rec + 24, 0x30 + r, 32);
        wr64(rec + 56, 24 + 8);
        wr64(rec + 64, 24);
        wr64(rec + 72, 8);
        if (CALL(lantern_db_add, db, rec, &off) != 0) *why = "drop: lantern_db_add status";
    }
    uint8_t *before = *why ? NULL : copy_of(db, rd64(db));
    if (!*why) { /* windows of 0 epochs, at a slot past the last block */
        wr64(s->node + NODE_CONFIG + 376, 0);
        wr64(s->node + NODE_CONFIG + 312, 0);
        shell_event(s, EV_TICK, rd64(m.store + STORE_GENESIS_TIME_MS) + (3 * 8192) * rd64(config + 104), NULL, 0);
        shell_settle(&m, why);
    }
    if (!*why && (s->ndrops != 2 || s->drops[0] != (1ull << 63 | 0) || s->drops[1] != (1ull << 63 | 1)))
        *why = "drop: not a DB_DROP of sidecar segments 0 and 1 alone";
    if (!*why && rd64(s->node + NODE_SIDECAR_FLOOR) != 2 * 8192) *why = "drop: sidecar_floor is not the third segment's first slot";
    if (!*why) {
        db = s->node + rd64(s->node + NODE_DB);
        static const uint8_t zero[48];
        const uint8_t *a = before + rd64(before + 24), *b = db + rd64(db + 24);
        for (uint64_t sl = 0; sl < rd64(db + 16) && !*why; sl++, a += DB_SLOT_BYTES, b += DB_SLOT_BYTES) {
            if (memcmp(a, b, 40) || memcmp(a + 88, b + 88, 8)) *why = "drop: a block or a state of the index changed";
            else if (memcmp(b + 40, zero, 48)) *why = "drop: a sidecar below sidecar_floor stays";
        }
    }
    free(before);
    if (!*why) drop_ran = 1;
    shell_close(&m, anchor_block);
}

static void fc_sync_check(tv parts, const char **why) {
    case_block *blocks, **chain;
    size_t nchain = case_chain(parts, &blocks, &chain, why);
    tv steps = tv_get(parts, "steps"), st = steps ? steps + 9 : NULL;
    uint64_t last_ms = 0;
    for (uint64_t k = 0, c = steps ? rd64(steps + 1) : 0; k < c; k++, st = tv_skip(st))
        if (tv_get(st, "tick")) {
            uint64_t secs = tv_u64(tv_get(st, "tick"));
            last_ms = secs > UINT64_MAX / 1000 ? UINT64_MAX : secs * 1000;
        }
    if (!*why && nchain) {
        uint8_t *head_state = NULL;
        uint64_t head_size = 0;
        sync_dead = 1; /* a peer that fails first: the node must ask the next one, and the slots again */
        sync_once(parts, chain, nchain, last_ms, 0, nchain >= 2 ? &head_state : NULL, &head_size, why);
        sync_dead = 0;
        sync_chain = chain;
        sync_nchain = nchain;
        if (!*why && sync_first_blobs() < nchain) sync_once(parts, chain, nchain, last_ms, 1, NULL, NULL, why);
        sync_retry = 1; /* sidecars only later: the sidecar retry must get them */
        if (!*why && sync_first_blobs() < nchain) sync_once(parts, chain, nchain, last_ms, 1, NULL, NULL, why);
        sync_retry = 0;
#if FORK >= FORK_FULU
        int columns = 0; /* a chain with column sidecars syncs again with a supernode */
        for (size_t b = 0; b < nchain; b++) columns |= chain[b]->columns != NULL;
        if (!*why && columns) {
            sync_retry = sync_partial = 1; /* a column left out: the retry asks for it alone */
            sync_once(parts, chain, nchain, last_ms, 1, NULL, NULL, why);
            sync_retry = sync_partial = 0;
            sync_supernode = 1;
            if (!*why) sync_once(parts, chain, nchain, last_ms, 0, NULL, NULL, why);
            sync_half = 1; /* and with the even columns only: it rebuilds the others */
            if (!*why) sync_once(parts, chain, nchain, last_ms, 0, NULL, NULL, why);
            sync_half = 0;
            sync_supernode = 0;
        }
#endif
        if (!*why) status_check(parts, last_ms, why);
        if (!*why && head_state) backfill_check(parts, chain, nchain, last_ms, head_state, head_size, why);
        free(head_state);
    }
    free(chain);
    free(blocks);
}

/* asm-snappy at the pin of platform/deps.sh, for the peer's messages. */
ABI uint64_t snappy_compress_size(const void *input, void *size);
ABI uint64_t snappy_compress(const void *input, void *scratch, void *compressed);
#define SNAPPY_SCRATCH_COMPRESS 32776
enum { GOSSIP_BEACON_BLOCK_TOPIC = 1, GOSSIP_BEACON_AGGREGATE_AND_PROOF_TOPIC = 2, GOSSIP_ATTESTER_SLASHING_TOPIC = 6, GOSSIP_BLOB_SIDECAR_TOPIC = 10, GOSSIP_DATA_COLUMN_SIDECAR_TOPIC = 11 }; /* include/lantern.inc GOSSIP_* */

/* The peer publishes the SSZ bytes ssz as a message of the topic string topic: Snappy, its message-id, a PUBLISH. */
static void p2p_publish(struct p2p_net *net, const uint8_t *topic, uint64_t tlen, const uint8_t *ssz, uint64_t len,
                        const char **why) {
    uint64_t csize = 0;
    uint8_t ncfg[CONFIG_SIZE], id[32] = {0};
    node_config(ncfg);
    uint8_t *in = serialized(ssz, len, &(uint64_t){0});
    CALL(snappy_compress_size, in, &csize);
    uint8_t *out = buffer(csize), *scr = buffer(SNAPPY_SCRATCH_COMPRESS + 64);
    wr64(out, csize);
    wr64(scr, SNAPPY_SCRATCH_COMPRESS + 64);
    uint8_t *tl = serialized(topic, tlen, &(uint64_t){0});
    if (CALL(snappy_compress, in, scr, out) != 0) *why = "snappy_compress status";
    else if (CALL(LF(compute_message_id), tl, out, ncfg, fresh_scratch(), id) != 0) *why = "compute_message_id status";
    else {
        uint64_t dlen = rd64(out + 16), toff = 72 + ((tlen + 7) & ~(uint64_t)7);
        uint8_t *e = p2p_event(net, 1, 15 /* PUBLISH */, toff + dlen);
        wr64(e + 16, 20);
        memcpy(e + 24, id, 20);
        wr64(e + 56, tlen);
        wr64(e + 64, dlen);
        memcpy(e + 72, topic, (size_t)tlen);
        memcpy(e + toff, out + 24, (size_t)dlen);
    }
    free(in);
    free(out);
    free(scr);
    free(tl);
}

/*
 * The operation events over gossip (node.md, node-p2p): an event stream of proposer_slashing and
 * attester_slashing, then the case's slashings from the peer, each on its topic of the anchor's
 * epoch; the stream's bytes must be the case's.
 */
static void p2p_op_events(fc_node *n, struct p2p_net *net, tv parts, const char **why) {
    static const char req[] = "GET /eth/v1/events?topics=proposer_slashing,attester_slashing HTTP/1.1\r\nHost: lantern\r\n\r\n";
    struct node_shell *s = n->shell;
    uint64_t lens[2], wlen;
    const uint8_t *msgs[2] = {tv_bytes(tv_get(parts, "proposer_slashing"), &lens[0]), tv_bytes(tv_get(parts, "attester_slashing"), &lens[1])};
    const uint8_t *want = tv_bytes(tv_get(parts, "op_events"), &wlen);
    static const uint64_t ids[2] = {5, GOSSIP_ATTESTER_SLASHING_TOPIC}; /* GOSSIP_PROPOSER_SLASHING, GOSSIP_ATTESTER_SLASHING */
    uint8_t gvr[32], ncfg[CONFIG_SIZE];
    memcpy(gvr, n->anchor + field_offset("BeaconState", 1), 32);
    node_config(ncfg);
    uint64_t epoch = rd64(s->node + 216) / SLOTS_PER_EPOCH_RUNNER; /* Node_earliest_slot: the anchor's */
    ev_open_one(n, 0, (const uint8_t *)req, sizeof req - 1, why);
    if (!*why) p2p_settle(n, net, why);
    for (int k = 0; k < 2 && !*why; k++) {
        uint8_t topic[24] = {0}, list[24 + 128];
        wr64(list, sizeof list);
        CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), topic);
        wr64(topic + 8, ids[k]);
        if (CALL(lantern_gossip_topic, topic, list) != 0) *why = "gossip_topic status";
        if (!*why) p2p_publish(net, list + 24, rd64(list + 16), msgs[k], lens[k], why);
        if (!*why) p2p_settle(n, net, why);
    }
    if (!*why && (s->ev[0].len != wlen || memcmp(s->ev[0].b, want, (size_t)wlen) || s->ev[0].lasts || s->ev[0].closes ||
                  s->ev[0].late)) {
        static char msg[512];
        snprintf(msg, sizeof msg, "the operation events over gossip: %llu bytes, the case's %llu: %.*s",
                 (unsigned long long)s->ev[0].len, (unsigned long long)wlen, (int)(s->ev[0].len < 300 ? s->ev[0].len : 300),
                 s->ev[0].b ? (const char *)s->ev[0].b : "");
        *why = msg;
    }
    if (!*why) {
        shell_event(s, EV_API_CLOSED, s->ev[0].conn, NULL, 0);
        s->ev[0].gone = 1;
        p2p_settle(n, net, why);
    }
}

static const uint8_t *gossip_root; /* the block p2p_imported waits for */
static int p2p_imported(struct p2p_net *net, int arg) {
    (void)arg;
    const uint8_t *e = shell_block(net->shell, gossip_root);
    return (e && rd64(e + NB_STATUS) == NB_INVALID) || shell_imported(net->shell, gossip_root);
}
static int p2p_subscribed(struct p2p_net *net, int arg) { return net->topics >= arg; }

#if FORK < FORK_FULU
static int p2p_unsubscribed(struct p2p_net *net, int arg) { return net->untopics >= arg; }

/* The gossip topics of a fork before fulu (node.md): five, sync_committee_contribution_and_proof and the two light client topics, bls_to_execution_change, blob subnets. */
/* The topics of a fork the node joins: from phase0 those of its SUBNETS_PER_NODE attestation subnets too. */
static int fork_topics(uint64_t fork) {
    int t = 5 + (int)rd64(config + 336) + 3 * (fork >= FORK_ALTAIR) + (fork >= FORK_CAPELLA);
    if (fork == FORK_DENEB) t += (int)rd64(config + 392 + 16 * 32 + 112);   /* BLOB_SIDECAR_SUBNET_COUNT */
    if (fork == FORK_ELECTRA) t += (int)rd64(config + 392 + 16 * 32 + 120); /* BLOB_SIDECAR_SUBNET_COUNT_ELECTRA */
    return t;
}

/*
 * The topics of a node whose config has the next fork at epoch 3 (node.md; altair p2p-interface.md,
 * Transitioning the gossip): at epoch 0 the peer sees the node join the runner's fork's topics and
 * no more; at epoch 1 those of the next fork too, two epochs ahead; at epoch 5, two epochs after
 * the fork, it leaves the first ones.
 */
static void fc_subscribe_check(tv parts, const char **why) {
    fc_node n;
    uint8_t *anchor_block;
    shell_next_fork_epoch = 3;
    struct node_shell *s = shell_open(&n, parts, &anchor_block, why);
    shell_next_fork_epoch = UINT64_MAX;
    uint64_t genesis_ms = *why ? 0 : rd64(n.store + STORE_GENESIS_TIME_MS);
    uint64_t epoch_ms = rd64(config + 104) * SLOTS_PER_EPOCH_RUNNER;
    struct p2p_net net;
    int now = fork_topics(FORK), next = 0;
#if FORK + 1 < FORK_FULU
    next = fork_topics(FORK + 1);
#else
    uint8_t subnets[16] = {0}; /* fulu: the subnets of the columns the node samples, Node_columns at 440 */
    const uint8_t *cols = s->node + 440;
    for (uint64_t c = 0, sc = rd64(config + 296); c < 128 && sc && !*why; c++) /* DATA_COLUMN_SIDECAR_SUBNET_COUNT */
        if (cols[c / 8] >> (c % 8) & 1) subnets[(c % sc) / 8] |= (uint8_t)(1u << ((c % sc) % 8));
    next = 9 + (int)rd64(config + 336); /* SUBNETS_PER_NODE; five, the contribution, the light client and bls_to_execution_change topics */
    for (int c = 0; c < 128; c++) next += subnets[c / 8] >> (c % 8) & 1;
#endif
    if (!*why) p2p_open(&n, &net, why);
    if (!*why) p2p_run(&n, &net, p2p_subscribed, now, why);
    if (!*why) p2p_settle(&n, &net, why);
    if (!*why && net.topics != now) *why = "subscribe: at epoch 0 the node joins other topics than its fork's";
    if (!*why) {
        shell_event(s, EV_TICK, genesis_ms + epoch_ms, NULL, 0);
        p2p_run(&n, &net, p2p_subscribed, now + next, why);
        if (!*why) p2p_settle(&n, &net, why);
        if (!*why && (net.topics != now + next || net.untopics)) *why = "subscribe: at epoch 1 the node does not join the next fork's topics alone";
    }
    if (!*why) {
        shell_event(s, EV_TICK, genesis_ms + 3 * epoch_ms, NULL, 0);
        p2p_settle(&n, &net, why);
        if (!*why && (net.topics != now + next || net.untopics)) *why = "subscribe: at the fork the node joins or leaves topics";
    }
    if (!*why) {
        shell_event(s, EV_TICK, genesis_ms + 5 * epoch_ms, NULL, 0);
        p2p_run(&n, &net, p2p_unsubscribed, now, why);
        if (!*why) p2p_settle(&n, &net, why);
        if (!*why && (net.untopics != now || net.topics != now + next)) *why = "subscribe: at epoch 5 the node does not leave its old topics alone";
    }
    if (!*why) p2p_close(&net);
    shell_close(&n, anchor_block);
}
#endif
static int p2p_never(struct p2p_net *net, int arg) {
    (void)net;
    (void)arg;
    return 0;
}

/* Rounds of the network that the node may use to handle its events. */
static void p2p_settle(fc_node *n, struct p2p_net *net, const char **why) {
    for (int k = 0; k < 6 && !*why; k++) {
        shell_step(n, why);
        if (!*why) p2p_peer_step(net, why);
        net->now += 10;
    }
    (void)p2p_never;
}

/*
 * Whether a case's valid blocks can all come over gossip: each in its own slot, after a tick to
 * that slot, and no payload_status step.
 */
static int gossip_case(tv parts, uint64_t genesis_ms) {
    tv steps = tv_get(parts, "steps"), st = steps ? steps + 9 : NULL;
    uint64_t now = 0, slots[256], nslots = 0, slot_ms = rd64(config + 104);
    for (uint64_t k = 0, c = steps ? rd64(steps + 1) : 0; k < c; k++, st = tv_skip(st)) {
        tv v = tv_get(st, "valid");
        if (tv_get(st, "payload_status")) return 0;
        if (tv_get(st, "tick")) now = tv_u64(tv_get(st, "tick")) * 1000;
        if (!tv_get(st, "block") || (v && !(*v == T_BOOL && v[1]))) continue;
        tv bname = tv_get(st, "block");
        char key[128];
        uint64_t blen, vsize;
        const char *why = NULL;
        snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
        uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), tv_bytes(tv_get(parts, key), &blen), blen, &vsize, &why);
        if (!sb) return 0;
        uint64_t slot = rd64(nested(sb, field_offset("SignedBeaconBlock", 0)) + field_offset("BeaconBlock", 0));
        free(sb);
        if (nslots == 256 || now < genesis_ms + slot * slot_ms) return 0;
        for (uint64_t i = 0; i < nslots; i++)
            if (slots[i] == slot) return 0;
        slots[nslots++] = slot;
    }
    return nslots > 0;
}

/* The signing root of the 32-byte root under the domain: sha256(root || domain), as SigningData's. */
static void signing_root(const uint8_t *root, const uint8_t *domain, uint8_t *out) {
    uint8_t bl[24 + 64];
    wr64(bl, sizeof bl);
    wr64(bl + 8, 24);
    wr64(bl + 16, 64);
    memcpy(bl + 24, root, 32);
    memcpy(bl + 56, domain, 32);
    CALL(crypto_sha256, bl, out);
}

/* bls.Sign of the 32-byte message by the pyspec test key of validator v: the secret key v + 1. */
static void test_sign(uint64_t v, const uint8_t *msg, uint8_t *sig, const char **why) {
    uint8_t sk[32] = {0}, bl[24 + 32];
    for (int i = 0; i < 8; i++) sk[31 - i] = (uint8_t)((v + 1) >> (8 * i));
    wr64(bl, sizeof bl);
    wr64(bl + 8, 24);
    wr64(bl + 16, 32);
    memcpy(bl + 24, msg, 32);
    uint64_t ssize = 8192 + 64;
    uint8_t *scratch = buffer(ssize);
    wr64(scratch, ssize);
    if (CALL(crypto_bls_sign, sk, bl, scratch, sig) != 0) *why = "crypto_bls_sign status";
    free(scratch);
}

/*
 * A SignedAggregateAndProof of the Attestation bytes att by its first attester, signed with the
 * pyspec test keys and the domains of state, in *olen bytes; NULL when the attestation has no
 * attester, or from electra more than one committee.
 */
static uint8_t *test_aggregate(const uint8_t *state, const uint8_t *att, uint64_t alen, uint64_t *olen, const char **why) {
    uint64_t vsize = 0, nval = rd64(state + field_offset("BeaconState", 11) + 8);
    if (alen < 4 + 128 + 96) return NULL;
#if FORK >= FORK_ELECTRA
    uint64_t fixed = (uint64_t)att[0] | (uint64_t)att[1] << 8 | (uint64_t)att[2] << 16 | (uint64_t)att[3] << 24, bits = 0;
    for (uint64_t i = 228; i < fixed && i < alen; i++) bits += (uint64_t)__builtin_popcount(att[i]);
    if (bits != 1) return NULL;
#endif
    uint8_t *a = decode(type_by_name("Attestation"), att, alen, &vsize, why), *out = NULL, *list = NULL;
    if (!a) return NULL;
    uint64_t lsize = 24 + 8 * nval;
    list = buffer(lsize);
    wr64(list, lsize);
    wr64(list + 8, 24);
    wr64(list + 16, 0);
    if (CALL(LF(get_attesting_indices), state, a, committee_cache, fresh_scratch(), list) == 0 && rd64(list + 16)) {
        uint64_t aggr = rd64(list + 24), slot = rd64(att + 4), epoch = slot / SLOTS_PER_EPOCH_RUNNER, mlen = 108 + alen;
        uint8_t dt[4] = {5, 0, 0, 0}, domain[32], chunk[32] = {0}, root[32], sel[96];
        wr64(chunk, slot); /* selection proof: the slot under DOMAIN_SELECTION_PROOF */
        if (CALL(LF(get_domain), state, dt, &epoch, fresh_scratch(), domain) != 0) *why = "get_domain status";
        signing_root(chunk, domain, root);
        if (!*why) test_sign(aggr, root, sel, why);
        *olen = 100 + mlen;
        out = buffer(*olen);
        memset(out, 0, (size_t)*olen);
        out[0] = 100;               /* SignedAggregateAndProof: the message's offset, the signature */
        uint8_t *m = out + 100;     /* AggregateAndProof: aggregator_index, the aggregate's offset, selection_proof, the aggregate */
        wr64(m, aggr);
        m[8] = 108;
        memcpy(m + 12, sel, 96);
        memcpy(m + 108, att, (size_t)alen);
        uint8_t *mv = *why ? NULL : decode(type_by_name("AggregateAndProof"), m, mlen, &vsize, why);
        if (mv) {
            dt[0] = 6; /* DOMAIN_AGGREGATE_AND_PROOF */
            root_of("AggregateAndProof", mv, chunk, why);
            if (!*why && CALL(LF(get_domain), state, dt, &epoch, fresh_scratch(), domain) != 0) *why = "get_domain status";
            signing_root(chunk, domain, root);
            if (!*why) test_sign(aggr, root, out + 4, why);
            free(mv);
        }
        if (*why) {
            free(out);
            out = NULL;
        }
    }
    free(list);
    free(a);
    return out;
}

static unsigned long gossip_votes, gossip_votes_applied; /* valid attestation steps sent as aggregates, and applied by the node */

/*
 * A case through a node that gets its blocks over gossip: the peer publishes each valid block on
 * beacon_block after the case's ticks, and the node must import it; the other steps are events
 * as in fc_node_case, and the checks must hold.
 */
/* "0x" and the lower case hex of n bytes at b, at o; o has 2n + 3 bytes. */
static void hex_text(char *o, const uint8_t *b, size_t n) {
    static const char d[] = "0123456789abcdef";
    o[0] = '0';
    o[1] = 'x';
    for (size_t i = 0; i < n; i++) {
        o[2 + 2 * i] = d[b[i] >> 4];
        o[3 + 2 * i] = d[b[i] & 15];
    }
    o[2 + 2 * n] = 0;
}

/* The text t as one chunk of an event stream over HTTP/1.1 at the end of the growing buffer *b. */
static void ev_want_chunk(uint8_t **b, uint64_t *len, uint64_t *cap, const char *t) {
    size_t tl = strlen(t);
    if (*len + tl + 16 > *cap) {
        *cap = 2 * (*len + tl + 16) + 4096;
        *b = realloc(*b, (size_t)*cap);
        if (!*b) {
            fprintf(stderr, "out of memory\n");
            exit(2);
        }
    }
    *len += (uint64_t)snprintf((char *)*b + *len, 16, "%04llx\r\n", (unsigned long long)tl);
    memcpy(*b + *len, t, tl);
    memcpy(*b + *len + tl, "\r\n", 2);
    *len += tl + 2;
}

#if FORK >= FORK_DENEB
/* The text of the event of a blob or column sidecar sc (beacon-api.md) of the block root, into a new buffer. */
static char *ev_sidecar_text(const uint8_t *sc, uint64_t n, const uint8_t root[32], int column) {
    char rh[67], h[99];
    uint64_t cap = 512 + 100 * (n / 48 + 1);
    char *t = xmalloc((size_t)cap);
    hex_text(rh, root, 32);
    if (!column) { /* a BlobSidecar: index, blob, commitment, proof, the header */
        const uint64_t blob = 4096 * 32; /* FIELD_ELEMENTS_PER_BLOB * BYTES_PER_FIELD_ELEMENT */
        uint8_t bl[24 + 48], vh[32];
        wr64(bl, sizeof bl);
        wr64(bl + 8, 24);
        wr64(bl + 16, 48);
        memcpy(bl + 24, sc + 8 + blob, 48);
        CALL(crypto_sha256, bl, vh);
        vh[0] = 1; /* VERSIONED_HASH_VERSION_KZG */
        char ch[99], vhh[67];
        hex_text(ch, sc + 8 + blob, 48);
        hex_text(vhh, vh, 32);
        snprintf(t, (size_t)cap, "event: blob_sidecar\ndata: {\"block_root\":\"%s\",\"index\":\"%llu\",\"slot\":\"%llu\","
                 "\"kzg_commitment\":\"%s\",\"versioned_hash\":\"%s\"}\n\n", rh, (unsigned long long)rd64(sc),
                 (unsigned long long)rd64(sc + 8 + blob + 96), ch, vhh);
        return t;
    }
    uint64_t a = sc[12] | (uint64_t)sc[13] << 8 | (uint64_t)sc[14] << 16 | (uint64_t)sc[15] << 24;
    uint64_t z = sc[16] | (uint64_t)sc[17] << 8 | (uint64_t)sc[18] << 16 | (uint64_t)sc[19] << 24;
    int at = snprintf(t, (size_t)cap, "event: data_column_sidecar\ndata: {\"block_root\":\"%s\",\"index\":\"%llu\",\"slot\":\"%llu\","
                      "\"kzg_commitments\":[", rh, (unsigned long long)rd64(sc), (unsigned long long)rd64(sc + 20));
    for (uint64_t c = a; c + 48 <= z && z <= n; c += 48) {
        hex_text(h, sc + c, 48);
        at += snprintf(t + at, (size_t)cap - (size_t)at, "%s\"%s\"", c == a ? "" : ",", h);
    }
    snprintf(t + at, (size_t)cap - (size_t)at, "]}\n\n");
    return t;
}
#endif

static void fc_gossip_case(tv parts, int *ran, const char **why) {
    fc_node n;
    uint8_t *anchor_block;
    *ran = 0;
    struct node_shell *s = shell_open(&n, parts, &anchor_block, why);
    uint64_t genesis_ms = *why ? 0 : rd64(n.store + STORE_GENESIS_TIME_MS);
    if (*why || !gossip_case(parts, genesis_ms)) {
        shell_close(&n, anchor_block);
        return;
    }
    *ran = 1;
    struct p2p_net net;
    uint8_t gvr[32], ncfg[CONFIG_SIZE];
    memcpy(gvr, n.anchor + field_offset("BeaconState", 1), 32);
    node_config(ncfg);
    p2p_open(&n, &net, why);
    int topics = 5 + (int)rd64(config + 336); /* the node's topics reach the peer, its attestation subnets': from fulu, those of its column subnets too */
#if FORK >= FORK_FULU
    uint8_t cols[16], subnets[16] = {0};
    node_columns(cols, why);
    for (uint64_t c = 0, sc = rd64(config + 296); c < 128 && sc && !*why; c++) /* DATA_COLUMN_SIDECAR_SUBNET_COUNT */
        if (cols[c / 8] >> (c % 8) & 1) subnets[(c % sc) / 8] |= (uint8_t)(1u << ((c % sc) % 8));
    topics = 9 + (int)rd64(config + 336);
    for (int c = 0; c < 128; c++) topics += subnets[c / 8] >> (c % 8) & 1;
#endif
    if (!*why) p2p_run(&n, &net, p2p_subscribed, topics, why);
    /* the events of the blocks and sidecars over gossip (node.md): a stream open over the case */
    static const char ereq[] = "GET /eth/v1/events?topics=block_gossip,blob_sidecar,data_column_sidecar HTTP/1.1\r\nHost: lantern\r\n\r\n";
    static const char ehead[] = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\n\r\n";
    uint64_t ewlen = sizeof ehead - 1, ewcap = 65536;
    uint8_t *ewant = xmalloc((size_t)ewcap);
    memcpy(ewant, ehead, (size_t)ewlen);
    if (!*why) ev_open_one(&n, 0, (const uint8_t *)ereq, sizeof ereq - 1, why);
    if (!*why) p2p_settle(&n, &net, why);
    tv steps = tv_get(parts, "steps");
    tv st = steps ? steps + 9 : NULL;
    uint64_t now_ms = 0, slashings = 0, slashings_applied = 0;
    for (uint64_t k = 0, c = steps ? rd64(steps + 1) : 0; k < c && !*why; k++, st = tv_skip(st)) {
        tv v = tv_get(st, "valid");
        int valid = !v || (*v == T_BOOL && v[1]);
        if (tv_get(st, "attester_slashing") && valid) { /* over gossip, on the topic of the tick's epoch; else as an event */
            char key[128];
            uint64_t olen, before = s->nresults[1];
            tv nm = tv_get(st, "attester_slashing");
            snprintf(key, sizeof key, "%.*s", (int)rd64(nm + 1), (const char *)(nm + 9));
            const uint8_t *bytes = tv_bytes(tv_get(parts, key), &olen);
            uint64_t epoch = now_ms < genesis_ms ? 0 : (now_ms - genesis_ms) / rd64(config + 104) / SLOTS_PER_EPOCH_RUNNER;
            uint8_t topic[24] = {0}, list[24 + 128];
            wr64(list, sizeof list);
            CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), topic);
            wr64(topic + 8, GOSSIP_ATTESTER_SLASHING_TOPIC);
            if (CALL(lantern_gossip_topic, topic, list) != 0) *why = "gossip_topic status";
            if (!*why) p2p_publish(&net, list + 24, rd64(list + 16), bytes, olen, why);
            if (!*why) p2p_settle(&n, &net, why);
            slashings++;
            if (!*why && s->nresults[1] > before) slashings_applied++;
            else if (!*why) {
                shell_event(s, EV_ATTESTER_SLASHING, 0, bytes, olen);
                p2p_settle(&n, &net, why);
            }
        } else if (tv_get(st, "tick")) {
            uint64_t secs = tv_u64(tv_get(st, "tick")), ms = secs > UINT64_MAX / 1000 ? UINT64_MAX : secs * 1000;
            now_ms = ms;
            shell_event(s, EV_TICK, ms, NULL, 0);
            p2p_settle(&n, &net, why);
        } else if (tv_get(st, "block")) {
            if (!valid) continue;
            char key[128];
            uint64_t blen, vsize;
            tv bname = tv_get(st, "block");
            snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
            const uint8_t *bytes = tv_bytes(tv_get(parts, key), &blen);
            uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), bytes, blen, &vsize, why), root[32];
            if (!sb) break;
            const uint8_t *block = nested(sb, field_offset("SignedBeaconBlock", 0));
            root_of("BeaconBlock", block, root, why);
            uint64_t epoch = rd64(block + field_offset("BeaconBlock", 0)) / SLOTS_PER_EPOCH_RUNNER;
            uint8_t topic[24] = {0}, list[24 + 128];
            wr64(list, sizeof list);
            CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), topic);
            wr64(topic + 8, GOSSIP_BEACON_BLOCK_TOPIC);
            if (!*why && CALL(lantern_gossip_topic, topic, list) != 0) *why = "gossip_topic status";
            if (!*why) p2p_publish(&net, list + 24, rd64(list + 16), bytes, blen, why);
            { /* its block_gossip event */
                char rh[67], t[160];
                hex_text(rh, root, 32);
                snprintf(t, sizeof t, "event: block_gossip\ndata: {\"slot\":\"%llu\",\"block\":\"%s\"}\n\n",
                         (unsigned long long)rd64(block + field_offset("BeaconBlock", 0)), rh);
                ev_want_chunk(&ewant, &ewlen, &ewcap, t);
            }
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
            tv sc = case_blobs ? tv_get(case_blobs, key) : NULL; /* then its sidecars, each on the topic of its subnet */
            tv se = sc ? sc + 9 : NULL;
            for (uint64_t i = 0, c = sc ? rd64(sc + 1) : 0; i < c && !*why; i++, se = tv_skip(se)) {
                uint64_t slen;
                const uint8_t *sb = tv_bytes(se, &slen);
                uint64_t index = slen >= 8 ? rd64(sb) : 0;
                wr64(topic + 8, GOSSIP_BLOB_SIDECAR_TOPIC);
                if (CALL(LF(compute_subnet_for_blob_sidecar), &index, config, topic + 16) != 0) *why = "compute_subnet_for_blob_sidecar status";
                wr64(list, sizeof list);
                if (!*why && CALL(lantern_gossip_topic, topic, list) != 0) *why = "gossip_topic status";
                if (!*why) p2p_publish(&net, list + 24, rd64(list + 16), sb, slen, why);
                char *t = ev_sidecar_text(sb, slen, root, 0);
                ev_want_chunk(&ewant, &ewlen, &ewcap, t);
                free(t);
            }
#endif
#if FORK >= FORK_FULU
            for (uint64_t c = 0, len; c < 128 && !*why; c++) { /* then its column sidecars of the node's columns, each on its subnet */
                const uint8_t *cb = (cols[c / 8] >> (c % 8) & 1) ? case_column(parts, tv_get(st, "columns"), c, &len) : NULL;
                if (!cb) continue;
                wr64(topic + 8, GOSSIP_DATA_COLUMN_SIDECAR_TOPIC);
                wr64(topic + 16, c % rd64(config + 296));
                wr64(list, sizeof list);
                if (CALL(lantern_gossip_topic, topic, list) != 0) *why = "gossip_topic status";
                if (!*why) p2p_publish(&net, list + 24, rd64(list + 16), cb, len, why);
                char *t = ev_sidecar_text(cb, len, root, 1);
                ev_want_chunk(&ewant, &ewlen, &ewcap, t);
                free(t);
            }
#endif
            gossip_root = root;
            if (!*why) p2p_run(&n, &net, p2p_imported, 0, why);
            if (*why && !strcmp(*why, "the network does not get there")) *why = "a valid block is not imported over gossip";
            if (!*why) p2p_settle(&n, &net, why); /* the block's votes: the node's own works */
            if (!*why && (s->ev[0].len != ewlen || memcmp(s->ev[0].b, ewant, (size_t)ewlen) || s->ev[0].closes || s->ev[0].late)) {
                static char emsg[640];
                uint64_t at = 0;
                while (at < s->ev[0].len && at < ewlen && s->ev[0].b[at] == ewant[at]) at++;
                snprintf(emsg, sizeof emsg, "the events of a block over gossip differ at byte %llu of %llu (want %llu): got %.*s",
                         (unsigned long long)at, (unsigned long long)s->ev[0].len, (unsigned long long)ewlen,
                         (int)(s->ev[0].len - at < 300 ? s->ev[0].len - at : 300), s->ev[0].b ? (const char *)s->ev[0].b + at : "");
                *why = emsg;
            }
            free(sb);
        } else if (tv_get(st, "attestation") || tv_get(st, "attester_slashing") || tv_get(st, "pow_block")) {
            int att = tv_get(st, "attestation") != NULL, pow = tv_get(st, "pow_block") != NULL;
            tv nm = tv_get(st, att ? "attestation" : pow ? "pow_block" : "attester_slashing");
            char key[128];
            uint64_t olen;
            snprintf(key, sizeof key, "%.*s", (int)rd64(nm + 1), (const char *)(nm + 9));
            const uint8_t *bytes = tv_bytes(tv_get(parts, key), &olen);
            int applied = 0;
            if (att && valid) { /* a valid attestation: over gossip first, as an aggregate of its first attester */
                const uint8_t *e = shell_block(s, s->node + NODE_HEAD_ROOT);
                shell_buf *h = e ? shell_find(s, rd64(e + NB_STATE_ID)) : NULL;
                uint64_t glen = 0, before = s->nresults[0];
                uint8_t *agg = h ? test_aggregate(h->b, bytes, olen, &glen, why) : NULL;
                if (agg && !*why) {
                    uint64_t epoch = now_ms < genesis_ms ? 0 : (now_ms - genesis_ms) / rd64(config + 104) / SLOTS_PER_EPOCH_RUNNER;
                    uint8_t topic[24] = {0}, list[24 + 128];
                    wr64(list, sizeof list);
                    CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), topic);
                    wr64(topic + 8, GOSSIP_BEACON_AGGREGATE_AND_PROOF_TOPIC);
                    if (CALL(lantern_gossip_topic, topic, list) != 0) *why = "gossip_topic status";
                    if (!*why) p2p_publish(&net, list + 24, rd64(list + 16), agg, glen, why);
                    if (!*why) p2p_settle(&n, &net, why);
                    gossip_votes++;
                    if (!*why && s->nresults[0] > before) {
                        applied = 1;
                        gossip_votes_applied++;
                        if (s->results[0][s->nresults[0] - 1] != 0) *why = "a valid attestation's vote over gossip is not valid";
                    }
                }
                free(agg);
            }
            if (!applied && !*why) {
                shell_event(s, att ? EV_ATTESTATION : pow ? EV_POW_BLOCK : EV_ATTESTER_SLASHING, 0, bytes, olen);
                p2p_settle(&n, &net, why);
            }
        } else if (tv_get(st, "checks")) {
            fc_checks(&n, tv_get(st, "checks"), why);
        }
        if (*why) {
            static char msg[192];
            snprintf(msg, sizeof msg, "step %llu: %s", (unsigned long long)k, *why);
            *why = msg;
        }
    }
    if (!*why && slashings && !slashings_applied) *why = "no valid attester slashing is applied over gossip";
    if (!*why) ev_stream_end(&n, 0, ewant, ewlen, "gossip", why);
    free(ewant);
    p2p_close(&net);
    shell_close(&n, anchor_block);
}

/* compliance: the rules of the spec's fork choice compliance runner (tests/generators/compliance_runners). */
static void run_fork_choice(const char *file, const char *dir, case_file *f, int compliance) {
    /* Node mode also serves the chain of these files' cases over libp2p. */
    int serve = strstr(file, "fork_choice-get_head") || strstr(file, "fork_choice-on_block");
#if FORK >= FORK_DENEB
    load_kzg_settings(dir);
#else
    (void)dir;
#endif
    case_file blobs = {0};
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    if (serve && !read_file(dir, PRESET "-" STR(FORK_NAME) "-node-blobs.bin", &blobs)) {
        fprintf(stderr, "%s/%s-%s-node-blobs.bin: missing\n", dir, PRESET, STR(FORK_NAME));
        exit(2);
    }
#endif
    case_file reads = {0}; /* the node-reads cases, named as the node-events cases */
    if (serve && !read_file(dir, PRESET "-" STR(FORK_NAME) "-node-reads.bin", &reads)) {
        fprintf(stderr, "%s/%s-%s-node-reads.bin: missing\n", dir, PRESET, STR(FORK_NAME));
        exit(2);
    }
    case_file events = {0}; /* the node-events cases: "get_head/" or "on_block/" and the case's name */
    const char *handler = strstr(file, "fork_choice-get_head") ? "get_head/" : "on_block/";
#if FORK > FORK_PHASE0
    if (serve && !read_file(dir, PRESET "-" STR(FORK_NAME) "-node-events.bin", &events)) {
        fprintf(stderr, "%s/%s-%s-node-events.bin: missing\n", dir, PRESET, STR(FORK_NAME));
        exit(2);
    }
#endif
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, vsize;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        case_events = NULL;
        events.at = 16;
        for (uint64_t b = 0; b < events.count && !case_events; b++) {
            const char *ename;
            uint64_t elen, hl = strlen(handler);
            tv eparts = next_case(&events, &ename, &elen);
            if (elen == hl + len && !memcmp(ename, handler, (size_t)hl) && !memcmp(ename + hl, name, (size_t)len)) case_events = eparts;
        }
        case_reads = NULL;
        reads.at = 16;
        for (uint64_t b = 0; b < reads.count && !case_reads; b++) {
            const char *rname;
            uint64_t rlen, hl = strlen(handler);
            tv rparts = next_case(&reads, &rname, &rlen);
            if (rlen == hl + len && !memcmp(rname, handler, (size_t)hl) && !memcmp(rname + hl, name, (size_t)len)) case_reads = rparts;
        }
        case_blobs = NULL; /* the node-blobs case of the same name */
        blobs.at = 16;
        for (uint64_t b = 0; b < blobs.count && !case_blobs; b++) {
            const char *bname;
            uint64_t blen;
            tv bparts = next_case(&blobs, &bname, &blen);
            if (blen == len && !memcmp(bname, name, (size_t)len)) case_blobs = bparts;
        }
        fc_node n;
        memset(&n, 0, sizeof n);
        n.compliance = compliance;
        uint8_t *anchor_block = fc_setup(&n, parts, &why);
        if (anchor_block) keep(&n.blocks, &n.nblocks, node_at(&n, 0), 0, copy_of(n.anchor, n.anchor_size), n.anchor_size);
        if (anchor_block && !why && !compliance) anchor_check(parts, &why);
        tv steps = tv_get(parts, "steps");
        tv s = steps ? steps + 9 : NULL;
        for (uint64_t k = 0, c = steps ? rd64(steps + 1) : 0; k < c && !why; k++, s = tv_skip(s)) {
            tv v = tv_get(s, "valid");
            int valid = !v || (*v == T_BOOL && v[1]);
            if (tv_get(s, "tick")) {
                uint64_t secs = tv_u64(tv_get(s, "tick")), ms = secs > UINT64_MAX / 1000 ? UINT64_MAX : secs * 1000;
                uint64_t result = 0xA5A5A5A5A5A5A5A5u;
                if (CALL(LF(on_tick), n.store, &ms, &result) != 0) why = "on_tick: status not 0";
                else if ((result == 0) != valid) why = "on_tick: result";
            } else if (tv_get(s, "block")) {
                fc_block(&n, parts, s, &why);
            } else if (tv_get(s, "attestation") || tv_get(s, "attester_slashing")) {
                int att = tv_get(s, "attestation") != NULL;
                tv nm = tv_get(s, att ? "attestation" : "attester_slashing");
                char key[128];
                uint64_t olen;
                snprintf(key, sizeof key, "%.*s", (int)rd64(nm + 1), (const char *)(nm + 9));
                uint8_t *op = decode(type_by_name(att ? "Attestation" : "AttesterSlashing"), tv_bytes(tv_get(parts, key), &olen),
                                     olen, &vsize, &why);
                if (op) {
                    uint64_t result = att ? fc_attestation(&n, op, 0, &why) : fc_attester_slashing(&n, op, &why);
                    if (!why && (result == 0) != valid) why = att ? "on_attestation: result" : "on_attester_slashing: result";
                    free(op);
                }
            } else if (tv_get(s, "checks")) {
                fc_checks(&n, tv_get(s, "checks"), &why);
            } else if (tv_get(s, "pow_block")) {
#if FORK >= FORK_BELLATRIX
                tv nm = tv_get(s, "pow_block");
                char key[128];
                uint64_t plen;
                snprintf(key, sizeof key, "%.*s", (int)rd64(nm + 1), (const char *)(nm + 9));
                uint8_t *pb = decode(type_by_name("PowBlock"), tv_bytes(tv_get(parts, key), &plen), plen, &vsize, &why);
                if (pb && n.npow == 16) why = "too many pow_block steps";
                else if (pb) n.pow[n.npow++] = pb;
#else
                why = "a pow_block step before bellatrix";
#endif
            } else if (tv_get(s, "payload_status")) {
                fc_payload_step(&n, s, &why);
            } else {
                why = "unknown step";
            }
            if (!why && n.store && !guard_ok(n.store, n.size)) why = "wrote past the store";
            if (!why && !guard_ok(scratch_buf, SCRATCH_BYTES)) why = "wrote past the scratch";
            if (why) {
                static char msg[160];
                snprintf(msg, sizeof msg, "step %llu: %s", (unsigned long long)k, why);
                why = msg;
            }
        }
        for (size_t k = 0; k < n.nblocks; k++) free(n.blocks[k].state);
        for (size_t k = 0; k < n.ncheckpoints; k++) free(n.checkpoints[k].state);
        for (size_t k = 0; k < n.npow; k++) free(n.pow[k]);
        free(n.blocks);
        free(n.checkpoints);
        free(n.store);
        free(n.anchor);
        free(anchor_block);
        report(file, name, len, why == NULL, why);
        if (!compliance && node_mode(parts)) {
            char nname[256];
            int nlen = snprintf(nname, sizeof nname, "%.*s (node)", (int)len, name);
            const char *nwhy = NULL;
            if (serve && FORK > FORK_PHASE0 && !case_events) nwhy = "no node-events case of the case";
            else if (serve && !case_reads) nwhy = "no node-reads case of the case";
            else fc_node_case(parts, serve, &nwhy);
            case_events = NULL;
            case_reads = NULL;
            report(file, nname, (uint64_t)nlen, nwhy == NULL, nwhy);
            int ran = 0;
            const char *gwhy = NULL;
#if FORK < FORK_FULU
            static int subscribe_checked;
            if (!subscribe_checked && strstr(file, "fork_choice-get_head")) {
                subscribe_checked = 1;
                nlen = snprintf(nname, sizeof nname, "%.*s (subscribe)", (int)len, name);
                fc_subscribe_check(parts, &gwhy);
                report(file, nname, (uint64_t)nlen, gwhy == NULL, gwhy);
                gwhy = NULL;
            }
#endif
            if (serve) fc_gossip_case(parts, &ran, &gwhy);
            if (ran) {
                nlen = snprintf(nname, sizeof nname, "%.*s (gossip)", (int)len, name);
                report(file, nname, (uint64_t)nlen, gwhy == NULL, gwhy);
            }
        }
    }
    case_blobs = NULL;
    case_events = NULL;
    case_reads = NULL;
    free(blobs.data);
    free(events.data);
    free(reads.data);
}

/* ---------------------------------------------------------------- Merkle proofs */

#if FORK == FORK_FULU
/*
 * merkle_proof-single_merkle_proof, BeaconBlockBody: the proof of blob_kzg_commitments. A partial column header
 * made of the body's commitments, the case's branch and a block header with the body's root must pass
 * lantern_fulu_verify_partial_data_column_header_inclusion_proof, and fail with one branch byte changed.
 */
static void run_merkle_proof(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, blen, vsize;
        tv parts = next_case(f, &name, &len);
        if (strncmp(name, "BeaconBlockBody/", 16)) {
            report(file, name, len, 0, "not a BeaconBlockBody case");
            continue;
        }
        tv proof = tv_get(parts, "proof"), branch = tv_get(proof, "branch");
        uint8_t *body = decode(type_by_name("BeaconBlockBody"), tv_bytes(tv_get(parts, "object"), &blen), blen, &vsize, &why);
        if (!body) {
            report(file, name, len, 0, why);
            continue;
        }
        if (tv_u64(tv_get(proof, "leaf_index")) != 27 || rd64(branch + 1) != 4) why = "not the proof of blob_kzg_commitments";
        uint64_t ref = field_offset("BeaconBlockBody", 11), count = rd64(body + ref + 8);
        /* The SSZ bytes of PartialDataColumnHeader: offset, SignedBeaconBlockHeader, the branch, the commitments. */
        uint64_t size = 4 + 208 + 128 + 48 * count;
        uint8_t *ssz = buffer(size);
        memset(ssz, 0, (size_t)size);
        ssz[0] = (4 + 208 + 128) & 0xff; /* the offset of the commitments, 4 bytes little endian */
        ssz[1] = (4 + 208 + 128) >> 8;
        uint8_t body_root[32];
        root_of("BeaconBlockBody", body, body_root, &why);
        memcpy(ssz + 4 + 80, body_root, 32); /* the header's body_root: after slot, proposer_index, parent_root, state_root */
        tv e = branch + 9;
        for (int k = 0; k < 4; k++, e = tv_skip(e)) memcpy(ssz + 4 + 208 + 32 * k, tv_bytes(e, &blen), 32);
        memcpy(ssz + 4 + 208 + 128, body + rd64(body + ref), (size_t)(48 * count));
        for (int flip = 0; flip < 2 && !why; flip++) {
            if (flip) ssz[4 + 208] ^= 1;
            uint8_t *hdr = decode(type_by_name("PartialDataColumnHeader"), ssz, size, &vsize, &why);
            uint64_t out = 7;
            if (hdr && CALL(LF(verify_partial_data_column_header_inclusion_proof), hdr, fresh_scratch(), &out) != 0) why = "status";
            else if (hdr && out != (uint64_t)!flip) why = flip ? "a changed branch passes" : "the proof fails";
            free(hdr);
        }
        free(ssz);
        free(body);
        report(file, name, len, why == NULL, why);
    }
}

#endif

#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
/*
 * merkle_proof-single_merkle_proof, BeaconBlockBody: the proof of blob_kzg_commitments[i]. A blob sidecar of that
 * commitment, the case's branch and a block header with the body's root must pass
 * lantern_verify_blob_sidecar_inclusion_proof, and fail with one branch byte changed.
 */
static void run_merkle_proof(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, blen, vsize;
        tv parts = next_case(f, &name, &len);
        if (strncmp(name, "BeaconBlockBody/", 16)) {
            report(file, name, len, 0, "not a BeaconBlockBody case");
            continue;
        }
        tv proof = tv_get(parts, "proof"), branch = tv_get(proof, "branch");
        uint8_t *body = decode(type_by_name("BeaconBlockBody"), tv_bytes(tv_get(parts, "object"), &blen), blen, &vsize, &why);
        if (!body) {
            report(file, name, len, 0, why);
            continue;
        }
        /* The generalized index: field 11 of a body of 16 leaves, the list's data root, then the element. */
        uint64_t depth = rd64(branch + 1), leaves = depth > 5 && depth < 40 ? 1ull << (depth - 5) : 0;
        uint64_t base = 27 * 2 * leaves, gindex = tv_u64(tv_get(proof, "leaf_index"));
        uint64_t ref = field_offset("BeaconBlockBody", 11), count = rd64(body + ref + 8), index = gindex - base;
        uint64_t size = ssz_size(type_by_name("BlobSidecar"));
        uint64_t blob = size - 8 - 48 - 48 - 208 - 32 * depth; /* the SSZ size of the blob */
        if (!leaves || gindex < base || index >= count || size < 8 + 48 + 48 + 208 + 32 * depth)
            why = "not the proof of a blob commitment";
        uint8_t *ssz = buffer(size), body_root[32];
        memset(ssz, 0, (size_t)size);
        if (!why) {
            wr64(ssz, index);
            memcpy(ssz + 8 + blob, body + rd64(body + ref) + 48 * index, 48);
            root_of("BeaconBlockBody", body, body_root, &why);
            memcpy(ssz + 8 + blob + 96 + 80, body_root, 32); /* the header's body_root */
            tv e = branch + 9;
            for (uint64_t k = 0; k < depth; k++, e = tv_skip(e)) memcpy(ssz + size - 32 * depth + 32 * k, tv_bytes(e, &blen), 32);
        }
        for (int flip = 0; flip < 2 && !why; flip++) {
            if (flip) ssz[size - 32 * depth] ^= 1;
            uint8_t *sc = decode(type_by_name("BlobSidecar"), ssz, size, &vsize, &why);
            uint64_t out = 7;
            if (sc && CALL(LF(verify_blob_sidecar_inclusion_proof), sc, &out) != 0) why = "status";
            else if (sc && out != (uint64_t)!flip) why = flip ? "a changed branch passes" : "the proof fails";
            free(sc);
        }
        free(ssz);
        free(body);
        report(file, name, len, why == NULL, why);
    }
}
#endif


/* ---------------------------------------------------------------- Light client data */

/*
 * lc-header (light-client.md): lantern_block_to_light_client_header of each case's block, and
 * lantern_upgrade_lc_header of each case's header, must give the case's bytes; with an out one
 * byte short, LANTERN_BUFFER_TOO_SMALL.
 */
static void run_lc_header(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, blen, wlen, lsize;
        tv parts = next_case(f, &name, &len);
        int upgrade = !strncmp(name, "upgrade/", 8);
        const uint8_t *in = tv_bytes(tv_get(parts, upgrade ? "header" : "block"), &blen);
        const uint8_t *want = tv_bytes(tv_get(parts, upgrade ? "out" : "header"), &wlen);
        uint8_t *list = in ? list_of(in, blen, 0, 0, &lsize) : NULL;
        if (!list || !want) why = "the case lacks its bytes";
        uint64_t scratch_size = SCRATCH_BYTES; /* a block past what SCRATCH_BYTES decodes: twice the room, as a shell grows it */
        for (int shy = 0; shy < 2 && !why; shy++) {
            uint64_t room = 24 + wlen - (uint64_t)shy, st;
            uint8_t *out = buffer(room);
            wr64(out, room);
            for (;;) {
                st = upgrade ? CALL(LF(upgrade_lc_header), list, (const void *)(uintptr_t)tv_u64(tv_get(parts, "from")), out)
                             : CALL(LF(block_to_light_client_header), list, sized_scratch(scratch_size), out);
                if (upgrade || shy || st != 1 || scratch_size >= (uint64_t)1 << 28) break;
                scratch_size *= 2;
            }
            static char msg[96];
            if (shy && st != 1) why = "an out a byte short is not BUFFER_TOO_SMALL";
            else if (!shy && st != 0) {
                snprintf(msg, sizeof msg, "status %llu", (unsigned long long)st);
                why = msg;
            } else if (!shy && (rd64(out + 8) != 24 || rd64(out + 16) != wlen || memcmp(out + 24, want, (size_t)wlen))) {
                uint64_t at = 0;
                while (at < wlen && at < rd64(out + 16) && out[24 + at] == want[at]) at++;
                snprintf(msg, sizeof msg, "not the header (%llu bytes, not %llu; first at byte %llu)", (unsigned long long)rd64(out + 16),
                         (unsigned long long)wlen, (unsigned long long)at);
                why = msg;
            } else if (!guard_ok(out, room)) why = "wrote past out";
            free(out);
        }
        free(list);
        report(file, name, len, why == NULL, why);
    }
}

#if FORK >= FORK_ALTAIR
/*
 * light_client-single_merkle_proof (light-client.md): BeaconState, lantern_state_branch of the case's field with
 * and without the StateCache must be branch, and leaf with it must rebuild the state's root at leaf_index;
 * BeaconBlockBody, lantern_execution_branch must be branch.
 */
static void run_lc_merkle_proof(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, olen, vsize, blen;
        tv parts = next_case(f, &name, &len);
        tv proof = tv_get(parts, "proof"), branch = tv_get(proof, "branch");
        const uint8_t *obj = tv_bytes(tv_get(parts, "object"), &olen);
        uint64_t depth = branch ? rd64(branch + 1) : 0, gindex = tv_u64(tv_get(proof, "leaf_index"));
        uint8_t want[32 * 8], got[32 * 8], guard[8];
        tv e = branch ? branch + 9 : NULL;
        for (uint64_t k = 0; k < depth && k < 8; k++, e = tv_skip(e)) memcpy(want + 32 * k, tv_bytes(e, &blen), 32);
        if (depth < 1 || depth > 8) why = "a branch of no depth lantern knows";
        if (!why && !strncmp(name, "BeaconState/", 12)) {
            uint64_t field = strstr(name, "current_sync_committee") ? 0 : strstr(name, "next_sync_committee") ? 1 :
                             strstr(name, "finality_root") ? 2 : 9;
            uint8_t *state = decode(type_by_name("BeaconState"), obj, olen, &vsize, &why);
            for (int cached = 0; cached < 2 && state && !why; cached++) {
                memset(got, 0xA5, sizeof got);
                memset(guard, 0xA5, sizeof guard);
                if (CALL(LF(state_branch), state, (const void *)(uintptr_t)field, cached ? state_cache : NULL, fresh_scratch(), got) != 0) why = "lantern_state_branch: status";
                else if (memcmp(got, want, (size_t)(32 * depth))) why = cached ? "lantern_state_branch with the StateCache: not the branch" : "lantern_state_branch: not the branch";
                else if (depth < 8 && got[32 * depth] != 0xA5) why = "lantern_state_branch: wrote past the branch";
            }
            if (!why && state) { /* is_valid_merkle_branch: leaf, the branch and leaf_index give the state's root */
                uint8_t node[32], root[32], bl[24 + 64];
                memcpy(node, tv_bytes(tv_get(proof, "leaf"), &blen), 32);
                wr64(bl, sizeof bl);
                wr64(bl + 8, 24);
                wr64(bl + 16, 64);
                for (uint64_t k = 0, g = gindex; k < depth; k++, g >>= 1) {
                    memcpy(bl + 24 + (g & 1 ? 0 : 32), want + 32 * k, 32); /* a right child's sibling is on the left */
                    memcpy(bl + 24 + (g & 1 ? 32 : 0), node, 32);
                    CALL(crypto_sha256, bl, node);
                }
                if (CALL(LF(state_root), state, NULL, fresh_scratch(), root) != 0) why = "lantern_state_root status";
                else if (memcmp(root, node, 32) || gindex >> depth != 1) why = "leaf and branch do not give the state's root";
            }
            free(state);
        } else if (!why && !strncmp(name, "BeaconBlockBody/", 16)) {
            uint64_t lsize;
            uint8_t *list = list_of(obj, olen, 0, 0, &lsize);
            memset(got, 0xA5, sizeof got);
            if (CALL(LF(execution_branch), list, fresh_scratch(), got) != 0) why = "lantern_execution_branch: status";
            else if (depth != 4 || memcmp(got, want, 128)) why = "lantern_execution_branch: not the branch";
            else if (got[128] != 0xA5) why = "lantern_execution_branch: wrote past the branch";
            free(list);
        } else if (!why) {
            why = "a suite lantern does not know";
        }
        report(file, name, len, why == NULL, why);
    }
}

/* light_client-update_ranking (light-client.md): lantern_is_better_update of each ordered pair must be the spec's. */
static void run_lc_update_ranking(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len;
        tv parts = next_case(f, &name, &len), better = tv_get(parts, "better");
        uint64_t n = tv_u64(tv_get(tv_get(parts, "meta"), "updates_count"));
        uint8_t **lists = calloc((size_t)n + 1, sizeof *lists);
        for (uint64_t k = 0; k < n; k++) {
            char key[32];
            uint64_t ulen, lsize;
            snprintf(key, sizeof key, "updates_%llu", (unsigned long long)k);
            const uint8_t *u = tv_bytes(tv_get(parts, key), &ulen);
            lists[k] = u ? list_of(u, ulen, 0, 0, &lsize) : NULL;
            if (!u) why = "an update is missing";
        }
        if (!better || rd64(better + 1) != n * n) why = "the case has not an answer for each pair";
        tv b = better ? better + 9 : NULL;
        for (uint64_t x = 0; x < n && !why; x++)
            for (uint64_t y = 0; y < n && !why; y++, b = tv_skip(b)) {
                uint64_t out = 7;
                static char msg[96];
                if (CALL(LF(is_better_update), lists[x], lists[y], &out) != 0) why = "lantern_is_better_update: status";
                else if (out != tv_u64(b)) {
                    snprintf(msg, sizeof msg, "lantern_is_better_update(updates_%llu, updates_%llu) is %llu",
                             (unsigned long long)x, (unsigned long long)y, (unsigned long long)out);
                    why = msg;
                }
            }
        for (uint64_t k = 0; k < n; k++) free(lists[k]);
        free(lists);
        report(file, name, len, why == NULL, why);
    }
}
#endif

#if FORK >= FORK_ALTAIR
/* ---------------------------------------------------------------- Light client data collection */

static void case_config(tv parts);
static void root_of(const char *type, const uint8_t *value, uint8_t root[32], const char **why);

/* The functions of each fork from altair that a case of several forks calls (light-client.md, Test vectors). */
#define LCF_DECL(f)                                                                                                  \
    extern const uint8_t lantern_##f##_types[];                                                                      \
    ABI uint64_t lantern_##f##_process_slots(void *, const void *, const void *, void *, void *);                    \
    ABI uint64_t lantern_##f##_state_transition(void *, const void *, const void *, const void *, void *, void *);   \
    ABI uint64_t lantern_##f##_beacon_state_copy_size(const void *, const void *, void *);                           \
    ABI uint64_t lantern_##f##_beacon_state_copy(const void *, const void *, void *);                                \
    ABI uint64_t lantern_##f##_upgrade_size(const void *, const void *, void *);                                     \
    ABI uint64_t lantern_##f##_node_upgrade(const void *, const void *, const void *, void *, void *);               \
    ABI uint64_t lantern_##f##_compute_fork_digest(const void *, const void *, const void *, void *, void *);
LCF_DECL(altair)
LCF_DECL(bellatrix)
LCF_DECL(capella)
LCF_DECL(deneb)
LCF_DECL(electra)
LCF_DECL(fulu)
#define LCF_ENTRY(f)                                                                                                 \
    {lantern_##f##_types, (const void *)lantern_##f##_process_slots, (const void *)lantern_##f##_state_transition,  \
     (const void *)lantern_##f##_beacon_state_copy_size, (const void *)lantern_##f##_beacon_state_copy,             \
     (const void *)lantern_##f##_upgrade_size, (const void *)lantern_##f##_node_upgrade,                            \
     (const void *)lantern_##f##_compute_fork_digest}
static const struct {
    const uint8_t *types;
    const void *slots, *transition, *copy_size, *copy, *upgrade_size, *upgrade, *digest;
} lcf[7] = {{0}, LCF_ENTRY(altair), LCF_ENTRY(bellatrix), LCF_ENTRY(capella), LCF_ENTRY(deneb), LCF_ENTRY(electra), LCF_ENTRY(fulu)};

#define LC_KINDS 4

/* The fork of a slot with the case's config: the last fork whose epoch is at most the slot's. */
static uint64_t lc_fork_at(uint64_t slot) {
    uint64_t epoch = slot / slots_per_epoch();
    for (uint64_t f = 6; f >= 1; f--)
        if (epoch >= rd64(config + 16 * f)) return f;
    return 0;
}

/* The offset of field i of the container name of the fork's types. */
static uint64_t lc_field(uint64_t fork, const char *name, uint64_t i) {
    const uint8_t *d = type_in(lcf[fork].types, name);
    return rd64(field_of(d, rd64(root_node(d) + 16) + i) + 8);
}

/* A copy of the state s of the fork with each list's room times growth, or NULL. */
static uint8_t *lc_copy(const uint8_t *s, uint64_t fork, uint64_t growth, uint64_t *size) {
    uint64_t room[8] = {64 * growth, 2048 * growth, 4 * growth,  9000 * growth,
                        64 * growth, 64 * growth,   4 * growth, 4096 * growth}, need = 0;
    if (CALL(lcf[fork].copy_size, s, room, &need) != 0) return NULL;
    uint8_t *out = buffer(need + 4096);
    wr64(out, need + 4096);
    if (CALL(lcf[fork].copy, s, room, out) != 0 || !guard_ok(out, need + 4096)) {
        free(out);
        return NULL;
    }
    *size = need + 4096;
    return out;
}

typedef struct {
    uint8_t root[32];
    uint64_t fork, size;
    uint8_t *state;
} lc_kept;

typedef struct {
    uint8_t *b;
    uint64_t room[7];
    lc_kept *states;
    uint64_t nstates;
    uint8_t gvr[32];
} lc_run;

/* The store with twice the capacities of each part: lantern_lc_store_copy, which must keep its data. */
static void lc_grow(lc_run *r, const char **why) {
    uint64_t room[7], need = 0;
    for (int k = 0; k < 7; k++) room[k] = 2 * r->room[k];
    if (CALL(lantern_lc_store_size, room, &need) != 0) {
        *why = "lantern_lc_store_size: status";
        return;
    }
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(lantern_lc_store_copy, r->b, room, out) != 0) *why = "lantern_lc_store_copy: status";
    else if (!guard_ok(out, need)) *why = "lantern_lc_store_copy wrote out of bounds";
    else if (memcmp(out + 8, r->b + 8, 72) || memcmp(out + 136, r->b + 136, 32)) *why = "lantern_lc_store_copy: other data";
    if (*why) {
        free(out);
        return;
    }
    free(r->b);
    r->b = out;
    memcpy(r->room, room, sizeof room);
}

/* The kept post-state of a root, or NULL. */
static lc_kept *lc_state_of(lc_run *r, const uint8_t *root) {
    for (uint64_t k = 0; k < r->nstates; k++)
        if (!memcmp(r->states[k].root, root, 32)) return &r->states[k];
    return NULL;
}

/* The text of a string value in buf, or "" when it is none. */
static const char *lc_text(tv v, char *buf, size_t n) {
    buf[0] = 0;
    if (v && *v == T_STRING && rd64(v + 1) < n) {
        memcpy(buf, v + 9, (size_t)rd64(v + 1));
        buf[rd64(v + 1)] = 0;
    }
    return buf;
}

/* The fork digest of an epoch with the functions of the fork. */
static void lc_digest(lc_run *r, uint64_t fork, uint64_t epoch, uint8_t out[4]) {
    uint8_t d[8] = {0};
    CALL(lcf[fork].digest, r->gvr, &epoch, config, fresh_scratch(), d);
    memcpy(out, d, 4);
}

/* An object of the light client store lc: lantern_lc_read of the kind and key into a new buffer, its fork in *fork; NULL with none. */
static uint8_t *lc_object(const uint8_t *lc, uint64_t kind, uint64_t key, uint64_t *fork, const char **why) {
    uint64_t room = 24 + 65536;
    uint8_t *out = buffer(room);
    wr64(out, room);
    uint64_t st = CALL(lantern_lc_read, lc, (const void *)(uintptr_t)kind, (const void *)(uintptr_t)key, out, fork);
    if (st == 0) return out;
    if (st != LC_NO_ANSWER) *why = "lantern_lc_read status";
    free(out);
    return NULL;
}

/*
 * The chunks of light client stream k: one for each object of want (ByteLists of lantern_lc_read,
 * forks[b] the fork of each), with result 0, the ForkDigest of the epoch of the object's first header's
 * beacon slot as context (compute_fork_digest of that fork), and its SSZ bytes; with none and single, one chunk of result 3 and no
 * payload; then no more bytes.
 */
static void p2p_check_lc(struct p2p_net *net, int k, uint8_t **want, const uint64_t *forks, size_t nwant, int single,
                         const uint8_t *gvr, const char *what, const char **why) {
    static char msg[128];
    uint8_t ncfg[CONFIG_SIZE];
    node_config(ncfg);
    uint64_t at = 0, total = net->st[k].len;
    size_t chunks = nwant ? nwant : (size_t)single;
    msg[0] = 0;
    for (size_t b = 0; b < chunks && !msg[0]; b++) {
        const uint8_t *w = nwant ? want[b] + rd64(want[b] + 8) : NULL;
        uint64_t wlen = nwant ? rd64(want[b] + 16) : 0, header[6] = {1, 4, 0, 0, 0, 0}, consumed = 0, eof = 1;
        uint8_t digest[8] = {0};
        if (w) {
            uint64_t off = forks[b] >= FORK_CAPELLA ? (uint64_t)(w[0] | w[1] << 8 | w[2] << 16 | (uint64_t)w[3] << 24) : 0;
            uint64_t epoch = rd64(w + off) / SLOTS_PER_EPOCH_RUNNER;
            if (forks[b] >= 1 && forks[b] <= 6) CALL(lcf[forks[b]].digest, gvr, &epoch, ncfg, fresh_scratch(), digest);
            else CALL(LF(compute_fork_digest), gvr, &epoch, ncfg, fresh_scratch(), digest);
        }
        uint8_t *input = serialized(net->st[k].data + at, total - at, &(uint64_t){0}), *out = buffer(24 + wlen + 8);
        wr64(out, 24 + wlen + 8);
        if (at >= total) snprintf(msg, sizeof msg, "%s: %zu chunks, %zu wanted", what, b, chunks);
        else if (CALL(lantern_reqresp_read_header, input, header) != 0) snprintf(msg, sizeof msg, "%s: chunk %zu: no header", what, b);
        else if (header[2] != (w ? 0u : 3u)) snprintf(msg, sizeof msg, "%s: chunk %zu: result %llu", what, b, (unsigned long long)header[2]);
        else if (w && memcmp(&header[3], digest, 4)) snprintf(msg, sizeof msg, "%s: chunk %zu: context bytes", what, b);
        else if (header[4] != wlen) snprintf(msg, sizeof msg, "%s: chunk %zu: length %llu", what, b, (unsigned long long)header[4]);
        else if (CALL(lantern_reqresp_read_payload, input, &header[5], &header[4], &eof, fresh_scratch(), out, &consumed) != 0)
            snprintf(msg, sizeof msg, "%s: chunk %zu: payload status", what, b);
        else if (wlen && memcmp(out + 24, w, (size_t)wlen)) snprintf(msg, sizeof msg, "%s: chunk %zu: bytes", what, b);
        at += header[5] + consumed;
        free(input);
        free(out);
    }
    if (!msg[0] && at != total) snprintf(msg, sizeof msg, "%s: bytes after the last chunk", what);
    if (msg[0]) *why = msg;
}

/* Stream k of the peer, emptied for a new request. */
static void p2p_reuse(struct p2p_net *net, int k) {
    free(net->st[k].data);
    memset(&net->st[k], 0, sizeof net->st[k]);
}

/*
 * The light client methods of the peer (node.md, NODE_WORK_LC_SERVE): each answer must be that of the
 * node's light client store (BufferId 2), as lantern_lc_read gives its objects. Bootstraps of the
 * roots, and of a root the node does not know; the finality and optimistic updates; the updates of
 * the periods from 0, with a count past the limit; none for a count of 0.
 */
static void p2p_lc_serve_check(fc_node *n, struct p2p_net *net, const uint8_t *const *roots, size_t nroots, const uint8_t *gvr,
                               const char **why) {
#define LC_STORE (shell_find(n->shell, 2)->b) /* again before each read: the table of buffers moves as the node adds one */
    if (!shell_find(n->shell, 2)) {
        *why = "no light client store";
        return;
    }
    static const struct {
        const char *name;
        uint64_t kind;
    } latest[2] = {{"light_client_finality_update", 2}, {"light_client_optimistic_update", 3}};
    for (int i = 0; i < 2 && !*why; i++) {
        uint64_t fork = 0;
        uint8_t *o = lc_object(LC_STORE, latest[i].kind, 0, &fork, why);
        p2p_reuse(net, 3);
        if (!*why) p2p_request(n, net, 3, latest[i].name, 1, NULL, 0, why);
        if (!*why) p2p_check_lc(net, 3, &o, &fork, o ? 1 : 0, 1, gvr, latest[i].name, why);
        free(o);
    }
    uint8_t unknown[32];
    memset(unknown, 0xEE, 32);
    for (size_t i = 0; i <= nroots && !*why; i++) {
        const uint8_t *root = i < nroots ? roots[i] : unknown;
        uint64_t fork = 0;
        uint8_t *o = lc_object(LC_STORE, 0, (uint64_t)(uintptr_t)root, &fork, why);
        p2p_reuse(net, 3);
        if (!*why) p2p_request(n, net, 3, "light_client_bootstrap", 1, root, 32, why);
        if (!*why) p2p_check_lc(net, 3, &o, &fork, o ? 1 : 0, 1, gvr, "light_client_bootstrap", why);
        free(o);
    }
    static const uint64_t ranges[2][2] = {{0, 200}, {0, 0}};
    for (int i = 0; i < 2 && !*why; i++) {
        uint8_t *want[MAX_REQUEST_LIGHT_CLIENT_UPDATES_RUNNER];
        uint64_t forks[MAX_REQUEST_LIGHT_CLIENT_UPDATES_RUNNER], count = ranges[i][1];
        size_t nwant = 0;
        if (count > MAX_REQUEST_LIGHT_CLIENT_UPDATES_RUNNER) count = MAX_REQUEST_LIGHT_CLIENT_UPDATES_RUNNER;
        for (uint64_t p = ranges[i][0]; p < ranges[i][0] + count && !*why; p++) { /* from the first update held to the first period of none */
            uint8_t *o = lc_object(LC_STORE, 1, p, &forks[nwant], why);
            if (o) want[nwant++] = o;
            else if (nwant) break;
        }
        uint8_t req[16];
        wr64(req, ranges[i][0]);
        wr64(req + 8, ranges[i][1]);
        p2p_reuse(net, 3);
        if (!*why) p2p_request(n, net, 3, "light_client_updates_by_range", 1, req, 16, why);
        if (!*why) p2p_check_lc(net, 3, want, forks, nwant, 0, gvr, "light_client_updates_by_range", why);
        for (size_t b = 0; b < nwant; b++) free(want[b]);
    }
#undef LC_STORE
}

#define NODE_LC_FIELDS (NODE_API_PART + 728) /* Node_lc_finality_slot, then lc_finality_super, lc_optimistic_slot, lc_pending, lc_due */
#define NODE_FORK_DIGEST 240                  /* Node_fork_digest */
static int p2p_lc_got(struct p2p_net *net, int arg) { return net->nlc >= arg; }

/*
 * The slots of a light client finality (kind 2) or optimistic (kind 3) update's SSZ bytes of the
 * fork: out[0] attested_header.beacon.slot, out[1] finalized_header.beacon.slot (0 for an
 * optimistic update), out[2] signature_slot, out[3] 1 for a supermajority of its sync aggregate.
 */
static void lc_update_slots(const uint8_t *b, uint64_t kind, uint64_t fork, uint64_t out[4]) {
    uint64_t committee = strcmp(PRESET, "minimal") ? 512 : 32, agg = committee / 8 + 96, branch = 32 * (fork >= FORK_ELECTRA ? 7 : 6);
    uint64_t fixed = fork >= FORK_CAPELLA, at = 0, sig;
    if (kind == 2) {
        out[0] = rd64(b + (fixed ? (uint64_t)(b[0] | b[1] << 8 | b[2] << 16 | (uint64_t)b[3] << 24) : 0));
        out[1] = rd64(b + (fixed ? (uint64_t)(b[4] | b[5] << 8 | b[6] << 16 | (uint64_t)b[7] << 24) : 112));
        at = (fixed ? 8 : 224) + branch;
    } else {
        out[0] = rd64(b + (fixed ? (uint64_t)(b[0] | b[1] << 8 | b[2] << 16 | (uint64_t)b[3] << 24) : 0));
        out[1] = 0;
        at = fixed ? 4 : 112;
    }
    uint64_t bits = 0;
    for (uint64_t i = 0; i < committee / 8; i++)
        for (int j = 0; j < 8; j++) bits += b[at + i] >> j & 1;
    sig = rd64(b + at + agg);
    out[2] = sig;
    out[3] = bits * 3 >= committee * 2;
}

/* The light client gossip of a node, as the runner sees it: the topics at its ForkDigest, the store's updates, their slots, and whether each goes. */
typedef struct {
    char topics[2][96];
    uint64_t tlens[2], forks[2], slots[2][4];
    uint8_t *want[2];
    int goes[2], ngo;
} lc_gossip;

/*
 * The node's light client gossip once it subscribes: the peer joins both topics; for each topic the
 * store's update (lantern_lc_read), its slots, and whether it goes: its ForkDigest (of its fork, at
 * the epoch of its attested slot) is the node's, and it is new for fields at 0 (node.md, The light
 * client gossip).
 */
static void lc_gossip_open(fc_node *n, struct p2p_net *net, const uint8_t *gvr, lc_gossip *g, const char **why) {
    struct node_shell *s = n->shell;
    static const char *names[2] = {"light_client_finality_update", "light_client_optimistic_update"};
    uint8_t ncfg[CONFIG_SIZE];
    node_config(ncfg);
    memset(g, 0, sizeof *g);
    for (int k = 0; k < 40 && !*why && !(rd64(s->node + NODE_FLAGS) & 4); k++) p2p_settle(n, net, why); /* NODE_FLAG_SUBSCRIBED */
    if (!*why && !(rd64(s->node + NODE_FLAGS) & 4)) *why = "lc gossip: the node does not subscribe";
    const uint8_t *d = s->node + NODE_FORK_DIGEST;
    for (int i = 0; i < 2 && !*why; i++) {
        g->tlens[i] = (uint64_t)snprintf(g->topics[i], sizeof g->topics[i], "/eth2/%02x%02x%02x%02x/%s/ssz_snappy", d[0], d[1], d[2], d[3], names[i]);
        uint8_t *e = p2p_event(net, 1, 13 /* SUBSCRIBE */, 24 + ((g->tlens[i] + 7) & ~(uint64_t)7));
        wr64(e + 16, g->tlens[i]);
        memcpy(e + 24, g->topics[i], (size_t)g->tlens[i]);
        g->want[i] = lc_object(shell_find(s, 2)->b, 2 + (uint64_t)i, 0, &g->forks[i], why);
        if (!g->want[i]) continue;
        lc_update_slots(g->want[i] + rd64(g->want[i] + 8), 2 + (uint64_t)i, g->forks[i], g->slots[i]);
        uint64_t epoch = g->slots[i][0] / SLOTS_PER_EPOCH_RUNNER;
        uint8_t digest[8] = {0};
        CALL(lcf[g->forks[i]].digest, gvr, &epoch, ncfg, fresh_scratch(), digest);
        int fresh = i == 0 ? g->slots[0][1] > 0 || g->slots[0][3] : g->slots[1][0] > 0;
        g->goes[i] = !memcmp(digest, d, 4) && fresh;
        g->ngo += g->goes[i];
    }
    if (!*why) p2p_settle(n, net, why);
}

static void lc_gossip_close(lc_gossip *g) {
    free(g->want[0]);
    free(g->want[1]);
}

/*
 * The node's publish (node.md, The light client gossip): with the fields at 0, lc_pending 3 and
 * lc_due 0, the node must publish on each topic the store's update that goes, Snappy compressed,
 * take its slots in the topic's fields, and leave lc_pending 0.
 */
static void p2p_lc_publish_check(fc_node *n, struct p2p_net *net, const uint8_t *gvr, const char **why) {
    static char msg[160];
    struct node_shell *s = n->shell;
    lc_gossip g;
    lc_gossip_open(n, net, gvr, &g, why);
    net->nlc = 0;
    memset(s->node + NODE_LC_FIELDS, 0, 24);
    wr64(s->node + NODE_LC_FIELDS + 24, 3);
    wr64(s->node + NODE_LC_FIELDS + 32, 0);
    if (!*why) p2p_run(n, net, p2p_lc_got, g.ngo, why);
    if (!*why) p2p_settle(n, net, why);
    if (!*why && net->nlc != g.ngo) {
        snprintf(msg, sizeof msg, "lc publish: the peer got %d messages, not %d", net->nlc, g.ngo);
        *why = msg;
    }
    if (!*why && rd64(s->node + NODE_LC_FIELDS + 24)) *why = "lc publish: lc_pending is not 0";
    for (int i = 0, m = 0; i < 2 && !*why; i++) {
        if (!g.goes[i]) continue;
        uint64_t csize = 0, len = rd64(g.want[i] + 16);
        uint8_t *in = serialized(g.want[i] + rd64(g.want[i] + 8), len, &(uint64_t){0});
        CALL(snappy_compress_size, in, &csize);
        uint8_t *out = buffer(csize), *scr = buffer(SNAPPY_SCRATCH_COMPRESS + 64);
        wr64(out, csize);
        wr64(scr, SNAPPY_SCRATCH_COMPRESS + 64);
        if (CALL(snappy_compress, in, scr, out) != 0) *why = "lc publish: snappy_compress status";
        else if (strcmp(net->lc_topic[m], g.topics[i])) *why = "lc publish: a message on another topic";
        else if (net->lc_len[m] != rd64(out + 16) || memcmp(net->lc_data[m], out + 24, (size_t)net->lc_len[m]))
            *why = "lc publish: a message's data is not the store's update";
        else if (i == 0 && (rd64(s->node + NODE_LC_FIELDS) != g.slots[0][1] || rd64(s->node + NODE_LC_FIELDS + 8) != g.slots[0][3]))
            *why = "lc publish: the finality fields are not the update's";
        else if (i == 1 && rd64(s->node + NODE_LC_FIELDS + 16) != g.slots[1][0]) *why = "lc publish: lc_optimistic_slot is not the update's";
        m++;
        free(in);
        free(out);
        free(scr);
    }
    lc_gossip_close(&g);
}

/* The topic's field of the node that an accepted update sets, and the update's value for it: finality lc_finality_slot, optimistic lc_optimistic_slot. */
static uint64_t lc_field_of(const struct node_shell *s, int i) { return rd64(s->node + NODE_LC_FIELDS + (i ? 16 : 0)); }
static uint64_t lc_value_of(const lc_gossip *g, int i) { return i ? g->slots[1][0] : g->slots[0][1]; }

/*
 * The node's validation of the peer's updates (node.md, The light client gossip), with the fields
 * at 0: on the topic early, the update with its last byte changed, then the update itself before its
 * due time less MAXIMUM_GOSSIP_CLOCK_DISPARITY, must leave them at 0; on the other topic, the update
 * at its due time must set the topic's field to its slot (finality: also lc_finality_super).
 */
static void p2p_lc_validate_check(fc_node *n, struct p2p_net *net, const uint8_t *gvr, int early, const char **why) {
    static char msg[160];
    struct node_shell *s = n->shell;
    lc_gossip g;
    lc_gossip_open(n, net, gvr, &g, why);
    memset(s->node + NODE_LC_FIELDS, 0, 24);
    uint64_t genesis_ms = rd64(n->store + STORE_GENESIS_TIME_MS), slot_ms = rd64(config + 104);
    uint64_t due_ms = rd64(config + 256) * slot_ms / 10000, disparity = rd64(config + 328); /* SYNC_MESSAGE_DUE_BPS, MAXIMUM_GOSSIP_CLOCK_DISPARITY */
    int late = 1 - early;
    if (!*why && g.goes[early]) {
        uint64_t due = genesis_ms + g.slots[early][2] * slot_ms + due_ms, len = rd64(g.want[early] + 16);
        const uint8_t *b = g.want[early] + rd64(g.want[early] + 8);
        uint8_t *changed = copy_of(b, len);
        changed[len - 1] ^= 1;
        if (rd64(s->node + NODE_TIME_MS) < due - disparity) {
            shell_event(s, EV_TICK, due - disparity - 1, NULL, 0);
            p2p_publish(net, (const uint8_t *)g.topics[early], g.tlens[early], changed, len, why);
            if (!*why) p2p_settle(n, net, why);
            if (!*why && (lc_field_of(s, 0) || lc_field_of(s, 1))) *why = "lc validate: a changed update sets the fields";
            if (!*why) p2p_publish(net, (const uint8_t *)g.topics[early], g.tlens[early], b, len, why);
            if (!*why) p2p_settle(n, net, why);
            if (!*why && (lc_field_of(s, 0) || lc_field_of(s, 1))) *why = "lc validate: an update before its due time sets the fields";
        }
        free(changed);
    }
    if (!*why && g.goes[late]) {
        uint64_t due = genesis_ms + g.slots[late][2] * slot_ms + due_ms;
        if (rd64(s->node + NODE_TIME_MS) < due) shell_event(s, EV_TICK, due, NULL, 0);
        p2p_publish(net, (const uint8_t *)g.topics[late], g.tlens[late], g.want[late] + rd64(g.want[late] + 8), rd64(g.want[late] + 16), why);
        for (int k = 0; k < 4 && !*why && lc_field_of(s, late) != lc_value_of(&g, late); k++) p2p_settle(n, net, why);
        if (!*why && (lc_field_of(s, late) != lc_value_of(&g, late) || (late == 0 && rd64(s->node + NODE_LC_FIELDS + 8) != g.slots[0][3]))) {
            snprintf(msg, sizeof msg, "lc validate: the peer's %s update does not set its fields", late ? "optimistic" : "finality");
            *why = msg;
        }
    }
    lc_gossip_close(&g);
}

/* The post-state of the block at enc on its parent's, kept by the block's root; the root in root. */
static void lc_new_block(lc_run *r, const uint8_t *enc, uint64_t elen, uint8_t root[32], const char **why) {
    if (elen < 100 + 80) {
        *why = "a block is too short";
        return;
    }
    const uint8_t *msg = enc + (enc[0] | enc[1] << 8 | enc[2] << 16 | (uint64_t)enc[3] << 24);
    uint64_t slot = rd64(msg), bfork = lc_fork_at(slot), vsize, size = 0;
    lc_kept *parent = lc_state_of(r, msg + 16);
    if (!parent) {
        *why = "a block's parent state is unknown";
        return;
    }
    if (bfork < parent->fork) {
        *why = "a block of a fork before its parent's";
        return;
    }
    uint8_t *state = lc_copy(parent->state, parent->fork, 1, &size);
    uint64_t f = parent->fork, result = 0, st = 0;
    while (state && !*why && f < bfork) { /* each fork boundary: process_slots to its first slot, then the upgrade */
        uint64_t first = rd64(config + 16 * (f + 1)) * slots_per_epoch();
        if (rd64(state + 48) < first) {
            for (uint64_t growth = 2;; growth *= 2) {
                st = CALL(lcf[f].slots, state, &first, config, fresh_scratch(), &result);
                if (st != 1 || growth > 1024) break;
                uint8_t *g = lc_copy(state, f, growth, &size);
                if (!g) break;
                free(state);
                state = g;
            }
            if (st != 0 || result != 0) {
                *why = "process_slots to a fork failed";
                break;
            }
        }
        uint64_t sroom[8] = {64, 2048, 4, 9000, 64, 64, 4, 4096}, need = 0;
        CALL(lcf[f + 1].upgrade_size, state, sroom, &need);
        uint8_t *out = buffer(need + 4096);
        wr64(out, need + 4096);
        if (CALL(lcf[f + 1].upgrade, state, sroom, config, fresh_scratch(), out) != 0) {
            *why = "lantern_node_upgrade: status";
            free(out);
            break;
        }
        free(state);
        state = out;
        size = need + 4096;
        f++;
    }
    uint8_t *block = state && !*why ? decode(type_in(lcf[bfork].types, "SignedBeaconBlock"), enc, elen, &vsize, why) : NULL;
    if (block) {
        uint64_t options[3] = {1, 1, rd64(state + 48) == slot}; /* TransitionOptions: slots_done after an upgrade at the slot */
        for (uint64_t growth = 2;; growth *= 2) {
            st = CALL(lcf[bfork].transition, state, block, options, config, fresh_scratch(), &result);
            if (st != 1 || growth > 1024) break;
            uint8_t *g = lc_copy(state, bfork, growth, &size);
            if (!g) break;
            free(state);
            state = g;
        }
        if (st != 0 || result != 0) {
            static char msg2[96];
            snprintf(msg2, sizeof msg2, "the state transition of the block of slot %llu: status %llu, result %llu",
                     (unsigned long long)slot, (unsigned long long)st, (unsigned long long)result);
            *why = msg2;
        } else {
            const uint8_t *m = nested(block, lc_field(bfork, "SignedBeaconBlock", 0));
            if (CALL(ssz_hash_tree_root, type_in(lcf[bfork].types, "BeaconBlock"), m, fresh_scratch(), root) != 0)
                *why = "the block's root";
        }
        free(block);
    }
    if (*why) {
        free(state);
        return;
    }
    r->states = realloc(r->states, (size_t)(r->nstates + 1) * sizeof *r->states);
    lc_kept *k = &r->states[r->nstates++];
    memcpy(k->root, root, 32);
    k->fork = bfork;
    k->size = size;
    k->state = state;
}

/* st = a store function's status, after growing the store as often as it asks for room. */
#define LC_GROWING(r, why, st, call)                                                                                  \
    do {                                                                                                             \
        for (int tries_ = 0; tries_ < 24 && !*(why); tries_++) {                                                    \
            (st) = (call);                                                                                           \
            if ((st) != 1) break;                                                                                    \
            lc_grow((r), (why));                                                                                     \
        }                                                                                                            \
    } while (0)

/* The check of one object of a new_head step: lantern_lc_read must give the case's bytes, or none. */
static void lc_check_object(lc_run *r, tv parts, uint64_t kind, uint64_t key, tv obj, const char *what, const char **why) {
    static char msg[160];
    uint64_t room = 24 + 65536, fork = 99;
    uint8_t *out = buffer(room);
    wr64(out, room);
    uint64_t st = CALL(lantern_lc_read, r->b, (const void *)(uintptr_t)kind, (const void *)(uintptr_t)key, out, &fork);
    if (!obj) {
        if (st != LC_NO_ANSWER) {
            snprintf(msg, sizeof msg, "%s: status %llu where the case has none", what, (unsigned long long)st);
            *why = msg;
        }
        free(out);
        return;
    }
    char name[200];
    uint64_t wlen = 0, dlen = 0;
    lc_text(tv_get(obj, "data"), name, sizeof name);
    tv file = tv_get(parts, name);
    const uint8_t *want = file ? tv_bytes(file, &wlen) : NULL, *digest = tv_bytes(tv_get(obj, "fork_digest"), &dlen);
    if (!want) snprintf(msg, sizeof msg, "%s: the case lacks %s", what, name);
    else if (st != 0) snprintf(msg, sizeof msg, "%s: status %llu", what, (unsigned long long)st);
    else if (!guard_ok(out, room)) snprintf(msg, sizeof msg, "%s: wrote past out", what);
    else if (rd64(out + 16) != wlen || memcmp(out + rd64(out + 8), want, (size_t)wlen)) {
        uint64_t at = 0;
        while (at < wlen && at < rd64(out + 16) && out[rd64(out + 8) + at] == want[at]) at++;
        snprintf(msg, sizeof msg, "%s: not %s (%llu bytes, not %llu; first at byte %llu)", what, name,
                 (unsigned long long)rd64(out + 16), (unsigned long long)wlen, (unsigned long long)at);
    } else {
        const uint8_t *b = out + rd64(out + 8);
        uint64_t at = fork >= 3 ? (uint64_t)(b[0] | b[1] << 8 | b[2] << 16 | (uint64_t)b[3] << 24) : 0, slot = rd64(b + at);
        uint8_t d[4];
        if (fork != lc_fork_at(slot)) snprintf(msg, sizeof msg, "%s: fork %llu, not that of its slot", what, (unsigned long long)fork);
        else {
            lc_digest(r, fork, slot / slots_per_epoch(), d);
            if (dlen != 4 || memcmp(d, digest, 4)) snprintf(msg, sizeof msg, "%s: not the case's fork_digest", what);
            else msg[0] = 0;
        }
    }
    if (!want || st != 0 || msg[0]) *why = msg;
    free(out);
}

/*
 * The case's store at its end, on two nodes of the case's anchor state and block whose light client
 * store (BufferId 2) is a copy of it (node.md, NODE_WORK_LC_SERVE, The light client gossip): the
 * requests of p2p_lc_serve_check, with bootstraps of the anchor's root and of up to 7 blocks of
 * the case, and p2p_lc_publish_check on the first; p2p_lc_validate_check on the second with the
 * finality topic early and on the third with the optimistic topic early.
 */
static void lc_serve_store(lc_run *r, const uint8_t *block, const char **why) {
    for (int pass = 0; pass < 3 && !*why; pass++) { /* one node serves and publishes; two validate the peer's updates */
        fc_node m;
        uint8_t *anchor_block = NULL;
        bf_state = r->states[0].state;
        bf_state_size = r->states[0].size;
        bf_block = block;
        struct node_shell *s = shell_open(&m, NULL, &anchor_block, why);
        bf_state = NULL;
        bf_block = NULL;
        shell_buf *c = *why ? NULL : shell_find(s, 2);
        if (!*why && !c) *why = "lc serve: no light client store";
        if (!*why) {
            free(c->b);
            c->size = rd64(r->b);
            c->b = copy_of(r->b, c->size);
            const uint8_t *roots[8];
            size_t nroots = 0;
            for (uint64_t k = 0; k < r->nstates && nroots < 8; k += r->nstates / 8 + 1) roots[nroots++] = r->states[k].root;
            struct p2p_net net;
            p2p_open(&m, &net, why);
            if (!*why && pass == 0) p2p_lc_serve_check(&m, &net, roots, nroots, r->gvr, why);
            if (!*why && pass == 0) p2p_lc_publish_check(&m, &net, r->gvr, why);
            if (!*why && pass) p2p_lc_validate_check(&m, &net, r->gvr, pass - 1, why);
            if (!*why && rd64(s->node + 136 + 8)) *why = "lc serve: the node keeps a stream at the end"; /* Node_streams */
            p2p_close(&net);
        }
        if (s) shell_close(&m, anchor_block);
    }
}

/*
 * light_client-data_collection (light-client.md, Test vectors): the steps of the case through the
 * LcStore functions, with the post-states of the runner; then its store served by a node.
 */
static void run_lc_data_collection(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, slen, size = 0, step_no = 0;
        tv parts = next_case(f, &name, &len);
        case_config(parts);
        lc_run r;
        memset(&r, 0, sizeof r);
        for (int k = 0; k < 7; k++) r.room[k] = 2;
        const uint8_t *enc = tv_bytes(tv_get(parts, "initial_state"), &slen);
        uint8_t *anchor = load_state(enc, slen, &size, &why), *block = NULL;
        if (anchor) memcpy(r.gvr, anchor + 16, 32);
        if (anchor) { /* the anchor block: lantern_node_anchor's value, the model's genesis block */
            uint64_t sroom[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}, need = 0, lsize;
            CALL(LF(beacon_state_copy_size), anchor, sroom, &need);
            uint8_t *data = list_of(enc, slen, 0, 0, &lsize), *st2 = buffer(need);
            block = buffer(ANCHOR_BLOCK_BYTES);
            wr64(st2, need);
            wr64(block, ANCHOR_BLOCK_BYTES);
            if (CALL(LF(node_anchor), data, sroom, fresh_scratch(), st2, block) != 0) why = "lantern_node_anchor: status";
            else {
                r.states = calloc(1, sizeof *r.states);
                r.nstates = 1;
                r.states[0].fork = FORK;
                r.states[0].state = anchor;
                r.states[0].size = size;
                anchor = NULL;
                root_of("BeaconBlock", block, r.states[0].root, &why);
            }
            free(data);
            free(st2);
        }
        if (!why) {
            uint64_t need = 0;
            CALL(lantern_lc_store_size, r.room, &need);
            r.b = buffer(need);
            wr64(r.b, need);
            uint64_t st = CALL(lantern_lc_store_init, r.room, config, r.states[0].state, block, fresh_scratch(), r.b);
            if (!why && st != 0) why = "lantern_lc_store_init: status";
        }
        free(anchor);
        tv steps = tv_get(tv_get(parts, "steps"), "steps") ? tv_get(tv_get(parts, "steps"), "steps") : tv_get(parts, "steps");
        tv s = steps && *steps == T_LIST ? steps + 9 : NULL;
        uint64_t nsteps = s ? rd64(steps + 1) : 0;
        if (!s && !why) why = "the case has no steps";
        static char where[256];
        for (uint64_t k = 0; k < nsteps && !why; k++, s = tv_skip(s), step_no++) {
            tv nb = tv_get(s, "new_block"), nh = tv_get(s, "new_head");
            if (nb) {
                char bname[200];
                uint64_t blen, lsize, dlen;
                tv bfile = tv_get(parts, lc_text(tv_get(nb, "data"), bname, sizeof bname));
                if (!bfile) {
                    why = "a new_block file is missing";
                    break;
                }
                const uint8_t *benc = tv_bytes(bfile, &blen), *digest = tv_bytes(tv_get(nb, "fork_digest"), &dlen);
                uint8_t root[32], d[4];
                lc_new_block(&r, benc, blen, root, &why);
                if (why) break;
                lc_kept *kept = lc_state_of(&r, root);
                lc_digest(&r, kept->fork, rd64(kept->state + 48) / slots_per_epoch(), d);
                if (dlen != 4 || memcmp(d, digest, 4)) {
                    why = "new_block: not the case's fork_digest";
                    break;
                }
                uint8_t *list = list_of(benc, blen, 0, 0, &lsize);
                uint64_t st = 1;
                LC_GROWING(&r, &why, st, CALL(lantern_lc_on_block, r.b, config, kept->state, list, NULL, fresh_scratch()));
                free(list);
                if (!why && st != 0) {
                    snprintf(where, sizeof where, "step %llu, lantern_lc_on_block: status %llu", (unsigned long long)k, (unsigned long long)st);
                    why = where;
                }
            } else if (nh) {
                uint64_t hlen, dlen;
                const uint8_t *head = tv_bytes(tv_get(nh, "head_block_root"), &hlen);
                lc_kept *kept = lc_state_of(&r, head);
                if (!kept) {
                    why = "new_head: the head's state is unknown";
                    break;
                }
                uint8_t cp[40]; /* the finalized_checkpoint of the head's post-state: field 20 */
                memcpy(cp, kept->state + lc_field(kept->fork, "BeaconState", 20), 40);
                uint64_t st = 1;
                LC_GROWING(&r, &why, st, CALL(lantern_lc_on_head, r.b, config, head, cp, fresh_scratch()));
                if (!why && st != 0) {
                    snprintf(where, sizeof where, "step %llu, lantern_lc_on_head: status %llu", (unsigned long long)k, (unsigned long long)st);
                    why = where;
                    break;
                }
                tv checks = tv_get(nh, "checks"), fin = tv_get(checks, "latest_finalized_checkpoint");
                const uint8_t *froot = tv_bytes(tv_get(fin, "root"), &dlen);
                const char *w = NULL;
                if (rd64(r.b + 24) != tv_u64(tv_get(fin, "epoch")) || dlen != 32 || memcmp(r.b + 40, froot, 32))
                    w = "latest_finalized_checkpoint differs";
                tv list = tv_get(checks, "bootstraps"), e = list && *list == T_LIST ? list + 9 : NULL;
                for (uint64_t n = 0, c = e ? rd64(list + 1) : 0; n < c && !w; n++, e = tv_skip(e)) {
                    uint64_t rl;
                    const uint8_t *br = tv_bytes(tv_get(e, "block_root"), &rl);
                    lc_check_object(&r, parts, 0, (uint64_t)(uintptr_t)br, tv_get(e, "bootstrap"), "bootstrap", &w);
                }
                list = tv_get(checks, "best_updates");
                e = list && *list == T_LIST ? list + 9 : NULL;
                for (uint64_t n = 0, c = e ? rd64(list + 1) : 0; n < c && !w; n++, e = tv_skip(e))
                    lc_check_object(&r, parts, 1, tv_u64(tv_get(e, "period")), tv_get(e, "update"), "best update", &w);
                if (!w) lc_check_object(&r, parts, 2, 0, tv_get(checks, "latest_finality_update"), "finality update", &w);
                if (!w) lc_check_object(&r, parts, 3, 0, tv_get(checks, "latest_optimistic_update"), "optimistic update", &w);
                if (w) {
                    snprintf(where, sizeof where, "step %llu (head): %s", (unsigned long long)k, w);
                    why = where;
                }
            } else why = "a step lantern does not know";
        }
        if (!why) lc_serve_store(&r, block, &why);
        for (uint64_t k = 0; k < r.nstates; k++) free(r.states[k].state);
        free(r.states);
        free(r.b);
        free(block);
        report(file, name, len, why == NULL, why);
    }
}
#endif

/* ---------------------------------------------------------------- Gossip */

/* The config of one case: the preset's, with the values of the case's config.yaml when it has one. */
static void case_config(tv parts) {
    memcpy(config, base_config, CONFIG_SIZE);
    tv c = tv_get(parts, "config");
    if (c) config_from_map(c, 1);
}

#define SEEN_KEYS 8
#define SEEN_HEADERS 56
#define SEEN_HEADER_BYTES 72
#define GOSSIP_IGNORE 44
#define GOSSIP_REJECT 45

typedef struct {
    uint8_t *b;
    uint64_t size, room[4]; /* keys, bits, blocks, header_bytes */
} seen_buf;

/* A Seen with the capacities of s->room. */
static void seen_make(seen_buf *s, const char **why) {
    uint64_t need = 0;
    if (CALL(lantern_seen_size, s->room, &need) != 0) {
        *why = "lantern_seen_size status";
        return;
    }
    uint8_t *b = buffer(need);
    wr64(b, need);
    if (!s->b) {
        if (CALL(lantern_seen_init, s->room, b) != 0) *why = "lantern_seen_init status";
    } else if (CALL(lantern_seen_copy, s->b, s->room, b) != 0) *why = "lantern_seen_copy status";
    else if (!guard_ok(b, need)) *why = "lantern_seen_copy wrote out of bounds";
    free(s->b);
    s->b = b;
    s->size = need;
}

/* The resize step for seen: twice each capacity. */
static void seen_grow(seen_buf *s, const char **why) {
    for (int i = 0; i < 4; i++) s->room[i] *= 2;
    seen_make(s, why);
}

/* The kept state of a root, or NULL. */
static kept_state *kept_of(fc_node *n, const uint8_t *root) { return find_kept(n->blocks, n->nblocks, root, 0, 0); }

/* hash_tree_root of value of the named type. */
static void root_of(const char *type, const uint8_t *value, uint8_t root[32], const char **why) {
    if (CALL(ssz_hash_tree_root, type_by_name(type), value, fresh_scratch(), root) != 0) *why = "hash_tree_root status";
}

/* A copy of the state of parent_root after process_slots to slot, or NULL when lantern reads none. */
static uint8_t *gossip_proposer_state(fc_node *n, const uint8_t *parent_root, uint64_t slot, uint64_t *size,
                                      const char **why) {
    kept_state *k = kept_of(n, parent_root);
    if (!k || slot <= rd64(k->state + field_offset("BeaconState", 2))) return NULL;
    *size = k->size;
    uint8_t *state = copy_of(k->state, k->size);
    uint64_t result = 0, st, growth = 2;
    while ((st = CALL(LF(process_slots), state, &slot, config, fresh_scratch(), &result)) == 1 && !*why)
        state = regrow(state, size, growth *= 2, why);
    if (st != 0 || result != 0) {
        free(state);
        return NULL;
    }
    return state;
}

static void run_gossip(const char *file, const char *dir, const char *handler, case_file *f) {
    static const struct {
        const char *topic, *type;
    } topics[] = {
#define GOSSIP_ENTRY(name, type) {#name, STR(type)},
        GOSSIP_TOPICS(GOSSIP_ENTRY)};
    int t = -1;
    for (int k = 0; k < (int)(sizeof topics / sizeof topics[0]); k++)
        if (!strcmp(handler, topics[k].topic)) t = k;
    if (t < 0) {
        printf("SKIP %s: lantern has no handler %s\n", file, handler);
        return;
    }
#if FORK >= FORK_DENEB
    load_kzg_settings(dir);
#else
    (void)dir;
#endif
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, slen, blen, vsize;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        case_config(parts);
        tv meta = tv_get(parts, "meta");
        fc_node n;
        memset(&n, 0, sizeof n);
        seen_buf seen = {NULL, 0, {1, 1, 1, 64}};
        seen_make(&seen, &why);
        n.anchor = load_state(tv_bytes(tv_get(parts, "state"), &slen), slen, &n.anchor_size, &why);
        tv blocks = tv_get(meta, "blocks"), b = blocks + 9;
        for (uint64_t k = 0, c = rd64(blocks + 1); k < c && !why; k++, b = tv_skip(b)) {
            char key[160];
            tv bn = tv_get(b, "block");
            snprintf(key, sizeof key, "%.*s", (int)rd64(bn + 1), (const char *)(bn + 9));
            uint8_t *signed_block = decode(type_by_name("SignedBeaconBlock"), tv_bytes(tv_get(parts, key), &blen), blen, &vsize, &why);
            if (!signed_block) break;
            const uint8_t *block = nested(signed_block, field_offset("SignedBeaconBlock", 0));
            uint8_t root[32];
            root_of("BeaconBlock", block, root, &why);
            tv ps = tv_get(b, "payload_status"), fl = tv_get(b, "failed"), pe = tv_get(b, "pending");
            uint64_t status = PAYLOAD_VALID;
            if (ps) {
                const char *text = (const char *)(ps + 9);
                status = !strncmp(text, "VALID", 5) ? PAYLOAD_VALID : !strncmp(text, "INVALIDATED", 11) ? PAYLOAD_INVALIDATED : PAYLOAD_NOT_VALIDATED;
            }
            if (k == 0) { /* the anchor */
                uint64_t room[2] = {4, 1}, need = 0, st;
                CALL(lantern_store_size, room, &need);
                n.store = buffer(need);
                n.size = need;
                wr64(n.store, need);
                while ((st = CALL(LF(get_forkchoice_store), n.anchor, block, config, room, fresh_scratch(), n.store)) == 1 &&
                       room[1] < (1u << 24)) {
                    room[1] *= 2;
                    CALL(lantern_store_size, room, &need);
                    free(n.store);
                    n.store = buffer(need);
                    n.size = need;
                    wr64(n.store, need);
                }
                if (st != 0) why = "get_forkchoice_store status";
                else keep(&n.blocks, &n.nblocks, node_at(&n, 0), 0, copy_of(n.anchor, n.anchor_size), n.anchor_size);
            } else if ((fl && fl[1]) || (pe && pe[1])) { /* seen, with no post-state */
                if (!ps) status = PAYLOAD_NOT_VALIDATED;
                uint64_t st;
                while ((st = CALL(lantern_seen_add_block, seen.b, root, &status)) == 1 && !why) seen_grow(&seen, &why);
                if (st != 0) why = "seen_add_block status";
            } else { /* imported: on_tick to its slot, then on_block */
                uint64_t slot = rd64(block + field_offset("BeaconBlock", 0)), result = 0;
                uint64_t ms = rd64(n.store + STORE_GENESIS_TIME_MS) + slot * rd64(config + 104);
                if (rd64(n.store + STORE_TIME_MS) < ms && CALL(LF(on_tick), n.store, &ms, &result) != 0) why = "on_tick status";
                kept_state *parent = kept_of(&n, block + field_offset("BeaconBlock", 2));
                if (!parent) why = "a block's parent is not imported";
                else {
                    uint64_t options[5] = {status == PAYLOAD_VALID ? PAYLOAD_VALID : PAYLOAD_NOT_VALIDATED, 1, 0, 0, 0};
                    uint64_t size = parent->size, growth = 2;
                    uint8_t *state = copy_of(parent->state, size);
                    uint64_t st = FC_RETRY(&n, &why, CALL(LF(on_block), n.store, signed_block, state, options, fresh_scratch(), &result),
                                           if (node_count(&n) == node_capacity(n.store)) grow_store(&n, &why);
                                           else { state = regrow(state, &size, growth, &why); growth *= 2; }, state, size);
                    if (!why && (st != 0 || result != 0)) why = "on_block of a meta block";
                    if (!why) {
                        uint64_t node = node_count(&n) - 1;
                        keep(&n.blocks, &n.nblocks, node_at(&n, node), 0, state, size);
                        state = NULL;
                        if (status == PAYLOAD_INVALIDATED &&
                            (CALL(lantern_store_payload_status, n.store, &node, &status, &result) != 0 || result != 0))
                            why = "store_payload_status";
                    }
                    free(state);
                }
            }
            free(signed_block);
        }
        tv fin = tv_get(meta, "finalized_checkpoint");
        if (fin && !why) { /* the case's finalized checkpoint */
            wr64(n.store + STORE_FINALIZED, tv_u64(tv_get(fin, "epoch")));
            tv r = tv_get(fin, "root"), fb = tv_get(fin, "block");
            if (r) memcpy(n.store + STORE_FINALIZED + 8, tv_bytes(r, &blen), 32);
            else {
                char key[160];
                snprintf(key, sizeof key, "%.*s", (int)rd64(fb + 1), (const char *)(fb + 9));
                uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), tv_bytes(tv_get(parts, key), &blen), blen, &vsize, &why);
                if (sb) root_of("BeaconBlock", nested(sb, field_offset("SignedBeaconBlock", 0)), n.store + STORE_FINALIZED + 8, &why);
                free(sb);
            }
        }
#if FORK == FORK_FULU
        tv hdrs = tv_get(meta, "seen_partial_data_column_headers");
        b = hdrs ? hdrs + 9 : NULL;
        for (uint64_t k = 0, c = hdrs ? rd64(hdrs + 1) : 0; k < c && !why; k++, b = tv_skip(b)) {
            char key[160];
            tv hn = tv_get(b, "header");
            snprintf(key, sizeof key, "%.*s", (int)rd64(hn + 1), (const char *)(hn + 9));
            uint8_t *hdr = decode(type_by_name("PartialDataColumnHeader"), tv_bytes(tv_get(parts, key), &blen), blen, &vsize, &why);
            if (!hdr) break;
            uint64_t entry = 64 + rd64(hdr);
            while (rd64(seen.b + SEEN_HEADER_BYTES) + entry > seen.room[3] && !why) seen_grow(&seen, &why);
            uint8_t *at = seen.b + rd64(seen.b + SEEN_HEADERS) + rd64(seen.b + SEEN_HEADER_BYTES);
            memcpy(at, tv_bytes(tv_get(b, "block_root"), &blen), 32);
            root_of("PartialDataColumnHeader", hdr, at + 32, &why);
            memcpy(at + 64, hdr, (size_t)rd64(hdr));
            wr64(seen.b + SEEN_HEADERS + 8, rd64(seen.b + SEEN_HEADERS + 8) + 1);
            wr64(seen.b + SEEN_HEADER_BYTES, rd64(seen.b + SEEN_HEADER_BYTES) + entry);
            free(hdr);
        }
#endif
        tv msgs = tv_get(meta, "messages"), m = msgs + 9;
        for (uint64_t k = 0, c = rd64(msgs + 1); k < c && !why; k++, m = tv_skip(m)) {
            char key[160];
            tv mn = tv_get(m, "message");
            snprintf(key, sizeof key, "%.*s", (int)rd64(mn + 1), (const char *)(mn + 9));
            uint8_t *msg = decode(type_by_name(topics[t].type), tv_bytes(tv_get(parts, key), &blen), blen, &vsize, &why);
            if (!msg) break;
            uint64_t head = fc_head(&n, &why);
            kept_state *hk = why ? NULL : kept_of(&n, node_at(&n, head));
            if (!why && !hk) why = "no state for the head";
            tv tm = tv_get(m, "current_time_ms"), sn = tv_get(m, "subnet_id"), ci = tv_get(m, "column_index"), gi = tv_get(m, "group_id");
            uint64_t now = tm ? tv_u64(tm) : 0, subnet = sn ? tv_u64(sn) : 0, column = ci ? tv_u64(ci) : 0;
            uint8_t *group = NULL;
#if FORK == FORK_FULU
            if (gi) {
                snprintf(key, sizeof key, "%.*s", (int)rd64(gi + 1), (const char *)(gi + 9));
                group = decode(type_by_name("PartialDataColumnGroupID"), tv_bytes(tv_get(parts, key), &blen), blen, &vsize, &why);
            }
#else
            (void)gi;
            (void)column;
#endif
            /* The parent and slot of a message with a block or block header. */
            const uint8_t *slotp = NULL, *parentp = NULL;
            if (!strcmp(handler, "beacon_block")) {
                const uint8_t *blk = nested(msg, field_offset("SignedBeaconBlock", 0));
                slotp = blk + field_offset("BeaconBlock", 0);
                parentp = blk + field_offset("BeaconBlock", 2);
            } else {
                const uint8_t *h = NULL; /* a SignedBeaconBlockHeader: its message first, of fixed size */
                if (!strcmp(handler, "blob_sidecar")) h = msg + field_offset("BlobSidecar", 4);
                else if (!strcmp(handler, "data_column_sidecar")) h = msg + field_offset("DataColumnSidecar", 4);
                else if (!strcmp(handler, "partial_data_column_sidecar")) {
                    uint64_t ref = field_offset("PartialDataColumnSidecar", 3);
                    if (rd64(msg + ref + 8) == 1) h = msg + rd64(msg + ref) + field_offset("PartialDataColumnHeader", 1);
                }
                if (h) {
                    slotp = h + field_offset("BeaconBlockHeader", 0);
                    parentp = h + field_offset("BeaconBlockHeader", 2);
                }
            }
            uint64_t psize = 0;
            uint8_t *proposer = slotp && !why ? gossip_proposer_state(&n, parentp, rd64(slotp), &psize, &why) : NULL;
            const uint8_t *head_state = hk ? hk->state : NULL, *pstate = proposer ? proposer : head_state;
            uint64_t result = 0xA5A5A5A5A5A5A5A5u, st = 0;
            for (int tries = 0; tries < 24 && !why; tries++) {
                uint8_t *snap = copy_of(seen.b, seen.size);
                const char *nm = topics[t].topic;
                void *sb = seen.b, *store = n.store;
                if (!strcmp(nm, "beacon_block")) {
#if FORK == FORK_BELLATRIX
                    kept_state *jk = kept_of(&n, n.store + STORE_JUSTIFIED + 8);
                    st = CALL(LF(validate_beacon_block_gossip), sb, store, msg, &now, head_state, pstate, jk ? jk->state : head_state,
                              fresh_scratch(), &result);
#else
                    st = CALL(LF(validate_beacon_block_gossip), sb, store, msg, &now, head_state, pstate, fresh_scratch(), &result);
#endif
                }
                else if (!strcmp(nm, "beacon_aggregate_and_proof"))
                    st = CALL(LF(validate_beacon_aggregate_and_proof_gossip), sb, store, msg, &now, head_state, fresh_scratch(), &result);
                else if (!strcmp(nm, "beacon_attestation"))
                    st = CALL(LF(validate_beacon_attestation_gossip), sb, store, msg, &now, &subnet, head_state, fresh_scratch(), &result);
                else if (!strcmp(nm, "voluntary_exit"))
                    st = CALL(LF(validate_voluntary_exit_gossip), sb, store, msg, &now, head_state, fresh_scratch(), &result);
                else if (!strcmp(nm, "proposer_slashing"))
                    st = CALL(LF(validate_proposer_slashing_gossip), sb, store, msg, head_state, fresh_scratch(), &result);
                else if (!strcmp(nm, "attester_slashing"))
                    st = CALL(LF(validate_attester_slashing_gossip), sb, store, msg, head_state, fresh_scratch(), &result);
#if FORK >= FORK_ALTAIR
                else if (!strcmp(nm, "sync_committee_contribution_and_proof"))
                    st = CALL(LF(validate_sync_committee_contribution_and_proof_gossip), sb, store, msg, &now, head_state, fresh_scratch(), &result);
                else if (!strcmp(nm, "sync_committee_message"))
                    st = CALL(LF(validate_sync_committee_message_gossip), sb, store, msg, &now, &subnet, head_state, fresh_scratch(), &result);
#endif
#if FORK >= FORK_CAPELLA
                else if (!strcmp(nm, "bls_to_execution_change"))
                    st = CALL(LF(validate_bls_to_execution_change_gossip), sb, store, msg, &now, head_state, fresh_scratch(), &result);
#endif
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
                else if (!strcmp(nm, "blob_sidecar"))
                    st = CALL(LF(validate_blob_sidecar_gossip), sb, store, msg, &now, &subnet, head_state, pstate, kzg_settings,
                              fresh_scratch(), &result);
#endif
#if FORK >= FORK_FULU
                else if (!strcmp(nm, "data_column_sidecar"))
                    st = CALL(LF(validate_data_column_sidecar_gossip), sb, store, msg, &now, &subnet, head_state, pstate, kzg_settings,
                              fresh_scratch(), &result);
                else
                    st = CALL(LF(validate_partial_data_column_sidecar_gossip), sb, store, msg, &now, group, &column, head_state, pstate,
                              kzg_settings, fresh_scratch(), &result);
#else
                else
                    why = "a topic with no call";
#endif
                if (st != 0 && memcmp(snap, seen.b, (size_t)seen.size)) why = "a non-zero status changed seen";
                /* A failed check leaves seen as it was, except that a partial column keeps the header it
                   recorded before its cell checks, as the spec does. */
                else if (st == 0 && result != 0 && strcmp(nm, "partial_data_column_sidecar") &&
                         memcmp(snap, seen.b, (size_t)seen.size))
                    why = "a failed check changed seen";
                free(snap);
                if (st != 1) break;
                seen_grow(&seen, &why);
            }
            if (!why && !guard_ok(seen.b, seen.size)) why = "wrote past seen";
            if (!why && st != 0) {
                static char msg2[64];
                snprintf(msg2, sizeof msg2, "status %llu", (unsigned long long)st);
                why = msg2;
            }
            if (!why) {
                tv ex = tv_get(m, "expected");
                const char *want = (const char *)(ex + 9), *got = result == 0 ? "valid" : result == GOSSIP_IGNORE ? "ignore"
                                                                       : result == GOSSIP_REJECT ? "reject" : "other";
                if (strncmp(want, got, (size_t)rd64(ex + 1)) || strlen(got) != rd64(ex + 1)) {
                    static char msg2[160];
                    snprintf(msg2, sizeof msg2, "message %llu: expected %.*s, got %s (%llu)", (unsigned long long)k, (int)rd64(ex + 1), want,
                             got, (unsigned long long)result);
                    why = msg2;
                }
            }
            free(proposer);
            free(group);
            free(msg);
        }
        for (size_t k = 0; k < n.nblocks; k++) free(n.blocks[k].state);
        for (size_t k = 0; k < n.ncheckpoints; k++) free(n.checkpoints[k].state);
        free(n.blocks);
        free(n.checkpoints);
        free(n.store);
        free(n.anchor);
        free(seen.b);
        memcpy(config, base_config, CONFIG_SIZE);
        report(file, name, len, why == NULL, why);
    }
}


/* ---------------------------------------------------------------- P2p helpers */

#define INVALID_TOPIC 48

/* A ByteList of the bytes of v, with room for exactly them. */
static uint8_t *byte_list(tv v, uint64_t *size) {
    uint64_t len;
    const uint8_t *b = tv_bytes(v, &len);
    *size = 24 + len;
    uint8_t *l = buffer(*size);
    wr64(l, *size);
    wr64(l + 8, 24);
    wr64(l + 16, len);
    memcpy(l + 24, b, (size_t)len);
    return l;
}

/*
 * p2p-<function>: lantern's cases of the p2p helpers (tests/generator/p2p.py). A case's config part
 * replaces values of the preset's config; a null output is where the spec raises.
 */
static void run_p2p(const char *file, const char *handler, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, blen, st = 0, n = 0, size = 0;
        tv parts = next_case(f, &name, &len);
        case_config(parts);
        tv in = tv_get(parts, "input"), want = tv_get(parts, "output");
        int null = want && *want == T_NULL;
        uint64_t error = 4; /* LANTERN_INVALID_OVERFLOW */
        uint8_t root[32] = {0}, node_id[32], *out = NULL;
        uint64_t epoch = 0;
        if (tv_get(in, "genesis_validators_root")) memcpy(root, tv_bytes(tv_get(in, "genesis_validators_root"), &blen), 32);
        if (tv_get(in, "epoch")) epoch = tv_u64(tv_get(in, "epoch"));
        if (tv_get(in, "current_epoch")) epoch = tv_u64(tv_get(in, "current_epoch"));
        if (tv_get(in, "node_id")) tv_uint256(tv_get(in, "node_id"), node_id);
        /* Fixed size outputs: n bytes in out, then guard bytes. */
        if (!strcmp(handler, "compute_fork_version")) {
            out = buffer(n = 4);
            st = CALL(LF(compute_fork_version), &epoch, config, out);
        } else if (!strcmp(handler, "compute_fork_digest")) {
            out = buffer(n = 4);
            st = CALL(LF(compute_fork_digest), root, &epoch, config, fresh_scratch(), out);
        } else if (!strcmp(handler, "compute_enr_fork_id")) {
            out = buffer(n = 16);
            st = CALL(LF(compute_enr_fork_id), root, &epoch, config, fresh_scratch(), out);
#if FORK >= FORK_FULU
        } else if (!strcmp(handler, "compute_next_fork_digest")) {
            out = buffer(n = 4);
            st = CALL(LF(compute_next_fork_digest), root, &epoch, config, fresh_scratch(), out);
        } else if (!strcmp(handler, "compute_max_request_data_column_sidecars")) {
            out = buffer(n = 8);
            st = CALL(LF(compute_max_request_data_column_sidecars), config, out);
#endif
#if FORK == FORK_DENEB || FORK == FORK_ELECTRA
        } else if (!strcmp(handler, "compute_max_request_blob_sidecars")) {
            out = buffer(n = 8);
            st = CALL(LF(compute_max_request_blob_sidecars), config, out);
#endif
        } else if (!strcmp(handler, "compute_attestation_subnet_prefix_bits")) {
            out = buffer(n = 8);
            st = CALL(LF(compute_attestation_subnet_prefix_bits), config, out);
        } else if (!strcmp(handler, "compute_min_epochs_for_block_requests")) {
            out = buffer(n = 8);
            st = CALL(LF(compute_min_epochs_for_block_requests), config, out);
        } else if (!strcmp(handler, "max_compressed_len")) {
            uint64_t v = tv_u64(tv_get(in, "n"));
            out = buffer(n = 8);
            st = CALL(LF(max_compressed_len), &v, out);
        } else if (!strcmp(handler, "max_message_size")) {
            out = buffer(n = 8);
            st = CALL(LF(max_message_size), config, out);
        } else if (!strcmp(handler, "compute_subscribed_subnet")) {
            uint64_t index = tv_u64(tv_get(in, "index"));
            out = buffer(n = 8);
            st = CALL(LF(compute_subscribed_subnet), node_id, &epoch, &index, config, fresh_scratch(), out);
        } else if (!strcmp(handler, "compute_message_id")) {
            uint64_t ts, ds;
            uint8_t *topic = byte_list(tv_get(in, "topic"), &ts), *data = byte_list(tv_get(in, "data"), &ds);
            out = buffer(n = 20);
            st = CALL(LF(compute_message_id), topic, data, config, fresh_scratch(), out);
            if (!guard_ok(topic, ts) || !guard_ok(data, ds)) why = "wrote past an input";
            free(topic);
            free(data);
        } else if (!strcmp(handler, "gossip_topic_parse")) {
            uint8_t *string = byte_list(tv_get(in, "string"), &size);
            error = INVALID_TOPIC;
            out = buffer(n = 24);
            st = CALL(lantern_gossip_topic_parse, string, out);
            if (null && out[0] != FILL) why = "wrote out for a bad string";
            if (!null && !st) {
                uint8_t topic[24] = {0};
                tv d = tv_get(want, "fork_digest");
                memcpy(topic, tv_bytes(d, &blen), 4);
                wr64(topic + 8, tv_u64(tv_get(want, "name")));
                wr64(topic + 16, tv_u64(tv_get(want, "subnet_id")));
                if (memcmp(out, topic, 24)) why = "topic differs";
            }
            free(string);
        }
        /* Variable size outputs. */
        if (!strcmp(handler, "compute_subscribed_subnets")) {
            uint64_t count = rd64(config + CONFIG_SUBNETS_PER_NODE);
            size = 24 + 8 * count;
            out = buffer(size);
            wr64(out, size);
            st = CALL(LF(compute_subscribed_subnets), node_id, &epoch, config, fresh_scratch(), out);
            if (!st && !list_equals(out, want)) why = "subnets differ";
            if (!st && count) { /* one entry less room: BUFFER_TOO_SMALL */
                uint8_t *small = buffer(size - 8);
                wr64(small, size - 8);
                if (CALL(LF(compute_subscribed_subnets), node_id, &epoch, config, fresh_scratch(), small) != 1) why = "short out accepted";
                free(small);
            }
            n = size;
        } else if (!strcmp(handler, "gossip_topic")) {
            uint8_t topic[24] = {0};
            tv d = tv_get(in, "fork_digest");
            memcpy(topic, tv_bytes(d, &blen), 4);
            wr64(topic + 8, tv_u64(tv_get(in, "name")));
            wr64(topic + 16, tv_u64(tv_get(in, "subnet_id")));
            uint64_t sl = 0;
            const uint8_t *string = null ? NULL : tv_bytes(want, &sl);
            error = INVALID_TOPIC;
            size = 24 + (null ? 64 : sl);
            out = buffer(size);
            wr64(out, size);
            st = CALL(lantern_gossip_topic, topic, out);
            if (!st && (rd64(out + 8) != 24 || rd64(out + 16) != sl || memcmp(out + 24, string, (size_t)sl))) why = "string differs";
            if (!st && sl) { /* one byte less room: BUFFER_TOO_SMALL */
                uint8_t *small = buffer(size - 1);
                wr64(small, size - 1);
                if (CALL(lantern_gossip_topic, topic, small) != 1) why = "short out accepted";
                free(small);
            }
            n = size;
        }
        if (!out) why = "no such handler";
        else if (null) {
            if (st != error) why = "status";
        } else if (st) why = "status";
        else if (!why && *want == T_BYTES && strcmp(handler, "gossip_topic")) {
            const uint8_t *b = tv_bytes(want, &blen);
            if (blen != n || memcmp(out, b, (size_t)n)) why = "output differs";
        } else if (!why && *want == T_INT) {
            if (rd64(out) != tv_u64(want)) why = "output differs";
        }
        if (out && !why && !guard_ok(out, n)) why = "wrote past out";
        free(out);
        report(file, name, len, why == NULL, why);
    }
    memcpy(config, base_config, CONFIG_SIZE);
}

/* ---------------------------------------------------------------- Req/resp encoding */

#define INVALID_PROTOCOL 49
#define INVALID_CHUNK 50
#define REQRESP_MORE 51

/* A ByteList of junk bytes, then len bytes of b, with room for room more bytes. */
static uint8_t *list_of(const uint8_t *b, uint64_t len, uint64_t junk, uint64_t room, uint64_t *size) {
    *size = 24 + junk + len + room;
    uint8_t *l = buffer(*size);
    wr64(l, *size);
    wr64(l + 8, 24);
    wr64(l + 16, junk + len);
    for (uint64_t k = 0; k < junk; k++) l[24 + k] = (uint8_t)(0xC0 + k);
    if (len) memcpy(l + 24 + junk, b, (size_t)len);
    return l;
}

/* Whether want is the string text. */
static int is_text(tv want, const char *text) {
    return want && *want == T_STRING && rd64(want + 1) == strlen(text) && !memcmp(want + 9, text, strlen(text));
}

/* Reads one chunk of the bytes of list l from byte at: its header (kind, context length) and payload. */
static const char *read_back(const uint8_t *l, uint64_t at, uint64_t kind, uint64_t context_length, uint64_t *header,
                             uint8_t **payload, uint64_t *consumed) {
    header[0] = kind;
    header[1] = context_length;
    uint64_t size, eof = 1;
    uint8_t *view = list_of(l + 24 + at, rd64(l + 16) - at, 0, 0, &size);
    const char *why = NULL;
    if (CALL(lantern_reqresp_read_header, view, header) != 0) why = "the written header does not read back";
    else {
        uint64_t length = header[4], start = header[5], osize = 24 + length;
        *payload = buffer(osize);
        wr64(*payload, osize);
        if (CALL(lantern_reqresp_read_payload, view, &start, &length, &eof, fresh_scratch(), *payload, consumed) != 0)
            why = "the written payload does not read back";
    }
    free(view);
    return why;
}

/* reqresp-<function>: lantern's cases of the req/resp encoding (tests/generator/reqresp.py). */
static void run_reqresp(const char *file, const char *handler, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, blen, size, st;
        tv parts = next_case(f, &name, &len);
        tv in = tv_get(parts, "input"), want = tv_get(parts, "output");
        int null = want && *want == T_NULL;
        if (!strcmp(handler, "ssz_size_bounds")) {
            char tname[128];
            tv tn = tv_get(in, "type"); /* a string */
            snprintf(tname, sizeof tname, "%.*s", (int)rd64(tn + 1), (const char *)(tn + 9));
            const uint8_t *desc = type_by_name(tname);
            if (!desc) continue; /* a type lantern does not have */
            uint8_t *out = buffer(16);
            st = CALL(lantern_ssz_size_bounds, desc, out);
            if (st) why = "status";
            else if (rd64(out) != tv_u64(tv_get(want, "min")) || rd64(out + 8) != tv_u64(tv_get(want, "max"))) why = "bounds differ";
            else if (!guard_ok(out, 16)) why = "wrote past out";
            free(out);
        } else if (!strcmp(handler, "protocol_parse")) {
            uint8_t *id = byte_list(tv_get(in, "id"), &size), *out = buffer(16);
            st = CALL(lantern_reqresp_protocol_parse, id, out);
            if (null) {
                if (st != INVALID_PROTOCOL) why = "status";
                else if (out[0] != FILL) why = "wrote out for a bad ID";
            } else if (st) why = "status";
            else if (rd64(out) != tv_u64(tv_get(want, "method")) || rd64(out + 8) != tv_u64(tv_get(want, "version"))) why = "protocol differs";
            if (!why && !guard_ok(out, 16)) why = "wrote past out";
            free(id);
            free(out);
        } else if (!strcmp(handler, "protocol_id")) {
            uint64_t protocol[2] = {tv_u64(tv_get(in, "method")), tv_u64(tv_get(in, "version"))}, sl = 0;
            const uint8_t *string = null ? NULL : tv_bytes(want, &sl);
            size = 24 + (null ? 64 : sl);
            uint8_t *out = buffer(size);
            wr64(out, size);
            st = CALL(lantern_reqresp_protocol_id, protocol, out);
            if (null) {
                if (st != INVALID_PROTOCOL) why = "status";
            } else if (st) why = "status";
            else if (rd64(out + 8) != 24 || rd64(out + 16) != sl || memcmp(out + 24, string, (size_t)sl)) why = "ID differs";
            else {
                uint8_t *small = buffer(size - 1);
                wr64(small, size - 1);
                if (CALL(lantern_reqresp_protocol_id, protocol, small) != 1) why = "short out accepted";
                free(small);
            }
            if (!why && !guard_ok(out, size)) why = "wrote past out";
            free(out);
        } else if (!strcmp(handler, "chunk_size")) {
            uint64_t n = tv_u64(tv_get(in, "n"));
            uint8_t *out = buffer(8);
            st = CALL(lantern_reqresp_chunk_size, &n, out);
            if (null) {
                if (st != 4) why = "status";
            } else if (st) why = "status";
            else if (rd64(out) != tv_u64(want)) why = "size differs";
            if (!why && !guard_ok(out, 8)) why = "wrote past out";
            free(out);
        } else if (!strcmp(handler, "read_header")) {
            const uint8_t *b = tv_bytes(tv_get(in, "bytes"), &blen);
            uint8_t *input = list_of(b, blen, 0, 0, &size);
            uint64_t header[6] = {tv_u64(tv_get(in, "kind")), tv_u64(tv_get(in, "context_length")), 7, 7, 7, 7};
            st = CALL(lantern_reqresp_read_header, input, header);
            if (is_text(want, "more")) {
                if (st != REQRESP_MORE) why = "status";
                else if (header[2] != 7 || header[5] != 7) why = "wrote the header";
            } else if (is_text(want, "invalid")) {
                if (st != INVALID_CHUNK) why = "status";
            } else if (st) why = "status";
            else {
                uint8_t ctx[8] = {0};
                memcpy(ctx, tv_bytes(tv_get(want, "context"), &blen), 4);
                if (header[2] != tv_u64(tv_get(want, "result")) || header[3] != rd64(ctx) || header[4] != tv_u64(tv_get(want, "length")) ||
                    header[5] != tv_u64(tv_get(want, "header_bytes")))
                    why = "header differs";
            }
            if (!why && !guard_ok(input, size)) why = "wrote past input";
            free(input);
        } else if (!strcmp(handler, "read_payload")) {
            const uint8_t *b = tv_bytes(tv_get(in, "bytes"), &blen);
            uint64_t start = 3, length = tv_u64(tv_get(in, "length")), eof = tv_u64(tv_get(in, "eof")), consumed = 7;
            uint8_t *input = list_of(b, blen, start, 0, &size);
            uint64_t osize = 24 + length;
            uint8_t *out = buffer(osize);
            wr64(out, osize);
            st = CALL(lantern_reqresp_read_payload, input, &start, &length, &eof, fresh_scratch(), out, &consumed);
            if (is_text(want, "more")) {
                if (st != REQRESP_MORE) why = "status";
            } else if (is_text(want, "invalid")) {
                if (st != INVALID_CHUNK) why = "status";
            } else if (st) why = "status";
            else {
                const uint8_t *p = tv_bytes(tv_get(want, "payload"), &blen);
                if (rd64(out + 8) != 24 || rd64(out + 16) != blen || memcmp(out + 24, p, (size_t)blen)) why = "payload differs";
                else if (consumed != tv_u64(tv_get(want, "consumed"))) why = "consumed differs";
                else if (length) {
                    uint8_t *small = buffer(osize - 1);
                    wr64(small, osize - 1);
                    if (CALL(lantern_reqresp_read_payload, input, &start, &length, &eof, fresh_scratch(), small, &consumed) != 1)
                        why = "short out accepted";
                    free(small);
                }
            }
            if (!why && !guard_ok(out, osize)) why = "wrote past out";
            free(input);
            free(out);
        } else if (!strcmp(handler, "write_chunk")) {
            uint64_t kind = tv_u64(tv_get(in, "kind")), clen = tv_u64(tv_get(in, "context_length")), result = tv_u64(tv_get(in, "result"));
            uint64_t header[6] = {kind, clen, result, 0, 99, 99}, psize, osize, csize = 0;
            memcpy(&header[3], tv_bytes(tv_get(in, "context"), &blen), 4);
            uint8_t *payload = byte_list(tv_get(in, "payload"), &psize);
            uint64_t plen = rd64(payload + 16);
            if (CALL(lantern_reqresp_chunk_size, &plen, &csize) != 0) why = "chunk size status";
            uint8_t *out = list_of(NULL, 0, 7, csize, &osize), *before = copy_of(out, osize + GUARD);
            /* One byte less room than the bound: BUFFER_TOO_SMALL, out unchanged. */
            wr64(out, osize - 1);
            if (!why && CALL(lantern_reqresp_write_chunk, header, payload, fresh_scratch(), out) != 1) why = "short out accepted";
            wr64(out, osize);
            if (!why && memcmp(out + 8, before + 8, (size_t)(osize - 8))) why = "a refused write changed out";
            if (!why && (st = CALL(lantern_reqresp_write_chunk, header, payload, fresh_scratch(), out)) != 0) why = "status";
            if (!why && (memcmp(out + 24, before + 24, 7) || rd64(out + 8) != 24)) why = "changed the bytes before the chunk";
            if (!why && !guard_ok(out, osize)) why = "wrote past out";
            if (!why) {
                uint64_t back[6], consumed = 0;
                uint8_t *p = NULL;
                why = read_back(out, 7, kind, clen, back, &p, &consumed);
                if (!why) {
                    uint64_t ctx = kind == 1 && result == 0 && clen ? header[3] : 0;
                    if (back[2] != (kind ? result : 0) || back[3] != ctx) why = "result or context differs";
                    else if (back[4] != plen || memcmp(p + 24, payload + 24, (size_t)plen)) why = "payload differs";
                    else if (7 + back[5] + consumed != rd64(out + 16)) why = "the chunk has more bytes than it reads";
                }
                free(p);
            }
            free(before);
            free(payload);
            free(out);
        } else why = "no such handler";
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Network config */

#define INVALID_CONFIG 60

/*
 * config-parse: lantern_config_parse over each case's file bytes (tests/generator/config.py), from a
 * config of a pattern; the result must be that pattern with the case's values, or for a fault
 * the pattern unchanged and the case's line.
 */
static void run_config_parse(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, tlen;
        tv parts = next_case(f, &name, &len);
        const uint8_t *text = tv_bytes(tv_get(parts, "text"), &tlen);
        tv want = tv_get(parts, "config"), wline = tv_get(parts, "line");
        /* The bytes at offset 40 of the list, with digits before and after them that a read past them takes in. */
        uint64_t size = 40 + tlen + 16;
        uint8_t *l = buffer(size);
        wr64(l, size);
        wr64(l + 8, 40);
        wr64(l + 16, tlen);
        memset(l + 24, '7', 16);
        if (tlen) memcpy(l + 40, text, (size_t)tlen);
        memset(l + 40 + tlen, '9', 16);
        uint8_t *cfg = buffer(CONFIG_SIZE), start[CONFIG_SIZE], expected[CONFIG_SIZE], kept[CONFIG_SIZE];
        for (int b = 0; b < CONFIG_SIZE; b++) start[b] = (uint8_t)(0x5A ^ b);
        memcpy(cfg, start, CONFIG_SIZE);
        if (want) { /* the pattern with the case's values, as the runner reads a config map */
            memcpy(kept, config, CONFIG_SIZE);
            memcpy(config, start, CONFIG_SIZE);
            config_from_map(want, 1);
            memcpy(expected, config, CONFIG_SIZE);
            memcpy(config, kept, CONFIG_SIZE);
        }
        uint64_t line = 0xFFFF, st = CALL(lantern_config_parse, l, cfg, &line);
        if (!guard_ok(cfg, CONFIG_SIZE) || !guard_ok(l, size)) why = "lantern_config_parse wrote out of bounds";
        else if (want) {
            if (st != 0) why = "status is not LANTERN_OK";
            else if (line != 0) why = "line is not 0";
            else if (memcmp(cfg, expected, CONFIG_SIZE)) why = "the config is not the case's";
        } else if (st != INVALID_CONFIG) why = "status is not LANTERN_INVALID_CONFIG";
        else if (line != tv_u64(wline)) why = "line is not the case's";
        else if (memcmp(cfg, start, CONFIG_SIZE)) why = "a faulty file changed the config";
        report(file, name, len, !why, why);
        free(l);
        free(cfg);
    }
}

/* ---------------------------------------------------------------- Database */

#define DB_FIRST_SLOT 8 /* include/lantern.inc: Db_first_slot, Db_end_slot, Db_slots, Db_blocks */
#define DB_END_SLOT 16
#define DB_SLOTS 24
#define DB_BLOCKS 56

/* A Db of a room [slots, roots], from lantern_db_size and lantern_db_init at a first slot; its size in *size. */
static uint8_t *db_new(const uint64_t *room, uint64_t first, uint64_t *size, const char **why) {
    *size = 0;
    if (CALL(lantern_db_size, room, size) != 0) {
        *why = "lantern_db_size status";
        return NULL;
    }
    uint8_t *db = buffer(*size);
    wr64(db, *size);
    if (CALL(lantern_db_init, room, &first, db) != 0) *why = "lantern_db_init status";
    else if (!guard_ok(db, *size)) *why = "lantern_db_init wrote out of bounds";
    return db;
}

/* Whether a Db holds the case's first slot, end slot, blocks and entries, and finds each root as the case says. */
static const char *db_check(const uint8_t *db, uint64_t first, uint64_t end, uint64_t blocks, tv entries, tv find) {
    uint64_t elen;
    const uint8_t *e = tv_bytes(entries, &elen);
    if (rd64(db + DB_FIRST_SLOT) != first) return "first_slot is not the case's";
    if (rd64(db + DB_END_SLOT) != end) return "end_slot is not the case's";
    if (blocks != UINT64_MAX && rd64(db + DB_BLOCKS) != blocks) return "blocks is not the case's";
    if (elen != (end - first) * DB_SLOT_BYTES || memcmp(db + rd64(db + DB_SLOTS), e, (size_t)elen)) return "the entries are not the case's";
    tv p = find + 9;
    for (uint64_t i = 0, n = rd64(find + 1); i < n; i++, p = tv_skip(p)) {
        uint64_t rlen, slot = 0;
        const uint8_t *root = tv_bytes(p + 9, &rlen);
        if (CALL(lantern_db_find_root, db, root, &slot) != 0) return "lantern_db_find_root status";
        if (slot != tv_u64(tv_skip(p + 9))) return "lantern_db_find_root: not the case's slot";
    }
    return NULL;
}

/*
 * eth1-<kind>: lantern's cases of the eth1 follower functions (tests/generator/eth1.py,
 * docs/reference/eth1.md). requests: the request of eth_getBlockByNumber or eth_getLogs, and
 * LANTERN_BUFFER_TOO_SMALL one byte short of the room. block: lantern_eth1_block of the text. logs:
 * lantern_eth1_deposit_logs of the text, its entries. tree: each push and its root, then each proof.
 */
static uint8_t *eth1_list(const uint8_t *bytes, uint64_t len) {
    uint8_t *l = buffer(24 + len);
    wr64(l, 24 + len);
    wr64(l + 8, 24);
    wr64(l + 16, len);
    if (len) memcpy(l + 24, bytes, (size_t)len);
    return l;
}
static void run_eth1(const char *file, const char *kind, case_file *f) {
    static const uint64_t status_of[3] = {0, 54, 69}; /* LANTERN_OK, LANTERN_INVALID_JSON, LANTERN_INVALID_DEPOSIT_LOG */
    for (uint64_t c = 0; c < f->count; c++) {
        const char *name, *why = NULL;
        uint64_t len;
        tv parts = next_case(f, &name, &len);
        if (!strcmp(kind, "eth1-requests")) {
            uint64_t tlen, k = tv_u64(tv_get(parts, "kind")), id = tv_u64(tv_get(parts, "id"));
            const uint8_t *text = tv_bytes(tv_get(parts, "text"), &tlen);
            for (int small = 0; small < 2 && !why; small++) {
                uint64_t room = small ? (k ? 383 : 127) : 24 + 1024;
                uint8_t *out = buffer(24 + room);
                wr64(out, 24 + room);
                uint64_t st;
                if (k == 0) {
                    uint64_t number = tv_u64(tv_get(parts, "number"));
                    st = CALL(lantern_eth_get_block_by_number, &number, &id, out);
                } else {
                    uint64_t alen, from = tv_u64(tv_get(parts, "from")), to = tv_u64(tv_get(parts, "to"));
                    const uint8_t *address = tv_bytes(tv_get(parts, "address"), &alen);
                    st = CALL(lantern_eth_get_deposit_logs, address, &from, &to, &id, out);
                }
                if (!guard_ok(out, 24 + room)) why = "the request wrote out of bounds";
                else if (small && st != 1) why = "a room one byte short: not LANTERN_BUFFER_TOO_SMALL";
                else if (!small && st != 0) why = "the request: not LANTERN_OK";
                else if (!small && (rd64(out + 8) != 24 || rd64(out + 16) != tlen || memcmp(out + 24, text, (size_t)tlen))) why = "the request differs";
                free(out);
            }
        } else if (!strcmp(kind, "eth1-block")) {
            uint64_t tlen, hlen;
            const uint8_t *text = tv_bytes(tv_get(parts, "text"), &tlen), *hash = tv_bytes(tv_get(parts, "hash"), &hlen);
            uint8_t *json = eth1_list(text, tlen), *out = buffer(88);
            memset(out, 0x5A, 88);
            uint64_t st = CALL(lantern_eth1_block, json, out), want = status_of[tv_u64(tv_get(parts, "status"))];
            if (!guard_ok(out, 88)) why = "lantern_eth1_block wrote out of bounds";
            else if (st != want) why = "lantern_eth1_block: another status";
            else if (st == 0 && (rd64(out) != tv_u64(tv_get(parts, "number")) || rd64(out + 8) != tv_u64(tv_get(parts, "timestamp")) ||
                                 memcmp(out + 24, hash, 32)))
                why = "lantern_eth1_block: another number, timestamp or hash";
            free(json);
            free(out);
        } else if (!strcmp(kind, "eth1-logs")) {
            uint64_t tlen, elen;
            const uint8_t *text = tv_bytes(tv_get(parts, "text"), &tlen), *ents = tv_bytes(tv_get(parts, "entries"), &elen);
            uint8_t *json = eth1_list(text, tlen);
            uint64_t want = status_of[tv_u64(tv_get(parts, "status"))];
            for (int small = 0; small < 2 && !why; small++) {
                if (small && (want != 0 || elen == 0)) break;
                uint64_t room = small ? elen - 1 : elen + 4096;
                uint8_t *out = buffer(24 + room);
                wr64(out, 24 + room);
                uint64_t st = CALL(lantern_eth1_deposit_logs, json, out);
                if (!guard_ok(out, 24 + room)) why = "lantern_eth1_deposit_logs wrote out of bounds";
                else if (small && st != 1) why = "a room one entry short: not LANTERN_BUFFER_TOO_SMALL";
                else if (!small && st != want) why = "lantern_eth1_deposit_logs: another status";
                else if (!small && st == 0 && (rd64(out + 8) != 24 || rd64(out + 16) != elen || memcmp(out + 24, ents, (size_t)elen)))
                    why = "lantern_eth1_deposit_logs: other entries";
                free(out);
            }
            free(json);
        } else {
            uint64_t llen, rlen;
            const uint8_t *leaves = tv_bytes(tv_get(parts, "leaves"), &llen), *roots = tv_bytes(tv_get(parts, "roots"), &rlen);
            uint64_t tsize = 8 + 32 * 32, dlen;
            uint8_t *tree = buffer(tsize), root[32];
            memset(tree, 0, (size_t)tsize);
            const uint8_t *datas = tv_bytes(tv_get(parts, "datas"), &dlen);
            for (uint64_t k = 0; k < dlen / 184 && !why; k++) {
                uint8_t *d = buffer(184), *leaf = buffer(32);
                memcpy(d, datas + 184 * k, 184);
                if (CALL(lantern_deposit_leaf, d, leaf) != 0) why = "lantern_deposit_leaf status";
                else if (!guard_ok(leaf, 32)) why = "lantern_deposit_leaf wrote out of bounds";
                else if (memcmp(leaf, leaves + 32 * k, 32)) why = "lantern_deposit_leaf: another root";
                free(d);
                free(leaf);
            }
            for (uint64_t k = 0; k < llen / 32 && !why; k++) {
                if (CALL(lantern_deposit_tree_push, tree, leaves + 32 * k) != 0) why = "lantern_deposit_tree_push status";
                else if (CALL(lantern_deposit_tree_root, tree, root) != 0) why = "lantern_deposit_tree_root status";
                else if (!guard_ok(tree, tsize)) why = "the tree was written out of bounds";
                else if (rd64(tree) != k + 1 || memcmp(root, roots + 32 * k, 32)) why = "the root after a push differs";
            }
            uint8_t *lst = eth1_list(leaves, llen);
            tv proofs = tv_get(parts, "proofs");
            tv p = proofs + 9;
            for (uint64_t i = 0, n = rd64(proofs + 1); i < n && !why; i++, p = tv_skip(p)) {
                tv it = p + 9;
                uint64_t count = tv_u64(it), index = tv_u64(tv_skip(it)), plen;
                const uint8_t *want = tv_bytes(tv_skip(tv_skip(it)), &plen);
                uint64_t ssize = 8 + 16 * count + 32;
                uint8_t *scr = buffer(ssize), *out = buffer(33 * 32);
                wr64(scr, ssize);
                if (CALL(lantern_deposit_proof, lst, &count, &index, scr, out) != 0) why = "lantern_deposit_proof status";
                else if (!guard_ok(out, 33 * 32) || !guard_ok(scr, ssize)) why = "lantern_deposit_proof wrote out of bounds";
                else if (memcmp(out, want, 33 * 32)) why = "lantern_deposit_proof: another proof";
                uint64_t past = count;
                if (!why && CALL(lantern_deposit_proof, lst, &count, &past, scr, out) != 70) why = "an index at the count: not LANTERN_INVALID_INDEX";
                free(scr);
                free(out);
            }
            free(lst);
            free(tree);
        }
        report(file, name, len, !why, why);
    }
}

/*
 * db-index: lantern's cases of the database index (tests/generator/db.py): lantern_db_scan of each
 * segment in order, then the Db, lantern_db_find_root, lantern_db_copy to a larger room, and
 * lantern_db_prune.
 */
static void run_db_index(const char *file, case_file *f) {
    for (uint64_t c = 0; c < f->count; c++) {
        const char *name, *why = NULL;
        uint64_t len, size = 0;
        tv parts = next_case(f, &name, &len);
        tv room_tv = tv_get(parts, "room"), segs = tv_get(parts, "segments");
        uint64_t room[2] = {tv_u64(room_tv + 9), tv_u64(tv_skip(room_tv + 9))}, first = tv_u64(tv_get(parts, "first_slot"));
        uint8_t *db = db_new(room, first, &size, &why);
        tv sg = segs + 9;
        for (uint64_t i = 0, n = rd64(segs + 1); i < n && !why; i++, sg = tv_skip(sg)) {
            uint64_t blen, number = tv_u64(tv_get(sg, "number")), kind = tv_u64(tv_get(sg, "kind")), valid = 77;
            const uint8_t *bytes = tv_bytes(tv_get(sg, "bytes"), &blen);
            uint8_t *list = buffer(24 + blen + 64); /* bytes after the segment's, that a read past it would take */
            wr64(list, 24 + blen + 64);
            wr64(list + 8, 24);
            wr64(list + 16, blen);
            if (blen) memcpy(list + 24, bytes, (size_t)blen);
            memset(list + 24 + blen, 0x5C, 64);
            uint64_t st = CALL(lantern_db_scan, db, &number, &kind, list, &valid);
            static char msg[96];
            if (!guard_ok(db, size)) why = "lantern_db_scan wrote out of bounds";
            else if (st != tv_u64(tv_get(sg, "status"))) {
                snprintf(msg, sizeof msg, "segment %llu: status %llu", (unsigned long long)i, (unsigned long long)st);
                why = msg;
            } else if (valid != tv_u64(tv_get(sg, "valid"))) {
                snprintf(msg, sizeof msg, "segment %llu: valid %llu", (unsigned long long)i, (unsigned long long)valid);
                why = msg;
            }
            free(list);
        }
        uint64_t end = tv_u64(tv_get(parts, "end_slot")), blocks = tv_u64(tv_get(parts, "blocks"));
        tv entries = tv_get(parts, "entries"), find = tv_get(parts, "find"), copy_room = tv_get(parts, "copy_room");
        if (!why) why = db_check(db, first, end, blocks, entries, find);
        if (!why && copy_room) { /* a larger room: the same index */
            uint64_t room2[2] = {tv_u64(copy_room + 9), tv_u64(tv_skip(copy_room + 9))}, size2 = 0;
            CALL(lantern_db_size, room2, &size2);
            uint8_t *db2 = buffer(size2);
            wr64(db2, size2);
            if (CALL(lantern_db_copy, db, room2, db2) != 0) why = "lantern_db_copy status";
            else if (!guard_ok(db2, size2)) why = "lantern_db_copy wrote out of bounds";
            else why = db_check(db2, first, end, blocks, entries, find);
            if (!why) { /* and a room below the entries in use */
                uint64_t room3[2] = {end - first ? end - first - 1 : 0, room2[1]}, size3 = 0;
                CALL(lantern_db_size, room3, &size3);
                uint8_t *db3 = buffer(size3 + 8);
                wr64(db3, size3 + 8);
                if (end > first && CALL(lantern_db_copy, db, room3, db3) != 1) why = "lantern_db_copy to too few slots: not LANTERN_BUFFER_TOO_SMALL";
                free(db3);
            }
            free(db2);
        }
        if (!why) { /* the sidecars below the second segment leave; every block and every later sidecar stays */
            uint8_t *d2 = copy_of(db, size);
            uint64_t cut = (first / 8192 + 1) * 8192, f0 = rd64(db + 8), e0 = rd64(db + 16);
            if (CALL(lantern_db_drop_sidecars, d2, &cut) != 0) why = "lantern_db_drop_sidecars status";
            else if (!guard_ok(d2, size)) why = "lantern_db_drop_sidecars wrote out of bounds";
            const uint8_t *a = db + rd64(db + 24), *b = d2 + rd64(d2 + 24);
            static const uint8_t zero[48];
            for (uint64_t sl = f0; sl < e0 && !why; sl++, a += DB_SLOT_BYTES, b += DB_SLOT_BYTES) {
                if (memcmp(a, b, 40) || memcmp(a + 88, b + 88, 8)) why = "lantern_db_drop_sidecars: a block or a state changed";
                else if (sl < cut && memcmp(b + 40, zero, 48)) why = "lantern_db_drop_sidecars: a sidecar below the slot stays";
                else if (sl >= cut && memcmp(a + 40, b + 40, 48)) why = "lantern_db_drop_sidecars: a later sidecar changed";
            }
            free(d2);
        }
        tv prune = tv_get(parts, "prune");
        if (!why && prune) {
            uint64_t slot = tv_u64(prune);
            if (CALL(lantern_db_prune, db, &slot) != 0) why = "lantern_db_prune status";
            else if (!guard_ok(db, size)) why = "lantern_db_prune wrote out of bounds";
            else why = db_check(db, tv_u64(tv_get(parts, "pruned_first")), end, UINT64_MAX, tv_get(parts, "pruned_entries"),
                                tv_get(parts, "pruned_find"));
        }
        report(file, name, len, !why, why);
        free(db);
    }
}

/* A ByteList of a copy of n bytes, with 64 bytes of 0x5C after them that a read past the bytes would take. */
static uint8_t *db_list(const uint8_t *bytes, uint64_t n) {
    uint8_t *l = buffer(24 + n + 64);
    wr64(l, 24 + n + 64);
    wr64(l + 8, 24);
    wr64(l + 16, n);
    if (n) memcpy(l + 24, bytes, (size_t)n);
    memset(l + 24 + n, 0x5C, 64);
    return l;
}

/*
 * db-state_diff: lantern's cases of the state diffs (tests/generator/db.py, docs/reference/db.md):
 * lantern_db_state_diff of base and state must give diff, and lantern_db_state_patch of base and
 * diff the state; each with LANTERN_BUFFER_TOO_SMALL and the same size one byte short. A bad diff
 * must give LANTERN_INVALID_ENCODING.
 */
static void run_db_state_diff(const char *file, case_file *f) {
    for (uint64_t c = 0; c < f->count; c++) {
        const char *name, *why = NULL;
        uint64_t len, blen, slen, dlen;
        tv parts = next_case(f, &name, &len);
        const uint8_t *b = tv_bytes(tv_get(parts, "base"), &blen);
        uint8_t *base = db_list(b, blen);
        tv bad = tv_get(parts, "bad");
        if (bad) {
            const uint8_t *d = tv_bytes(bad, &dlen);
            uint8_t *diff = db_list(d, dlen), *out = buffer(24 + 4096);
            uint64_t size = 0;
            wr64(out, 24 + 4096);
            if (CALL(lantern_db_state_patch, base, diff, out, &size) != 56) why = "lantern_db_state_patch: not LANTERN_INVALID_ENCODING";
            else if (!guard_ok(out, 24 + 4096)) why = "lantern_db_state_patch wrote out of bounds";
            free(diff);
            free(out);
        } else {
            const uint8_t *st = tv_bytes(tv_get(parts, "state"), &slen), *want = tv_bytes(tv_get(parts, "diff"), &dlen);
            uint8_t *state = db_list(st, slen), *diff = db_list(want, dlen);
            for (int pass = 0; pass < 2 && !why; pass++) { /* 0 the diff, 1 the patch */
                uint64_t need = 24 + (pass ? slen : dlen), size = 0, st2;
                const uint8_t *expect = pass ? st : want;
                uint8_t *out = buffer(need), *small = buffer(need - 1);
                wr64(out, need);
                wr64(small, need - 1);
                st2 = pass ? CALL(lantern_db_state_patch, base, diff, out, &size) : CALL(lantern_db_state_diff, base, state, out, &size);
                if (st2 != 0) why = pass ? "lantern_db_state_patch status" : "lantern_db_state_diff status";
                else if (!guard_ok(out, need)) why = "wrote out of bounds";
                else if (size != need) why = pass ? "lantern_db_state_patch: size" : "lantern_db_state_diff: size";
                else if (rd64(out + 8) != 24 || rd64(out + 16) != need - 24 || memcmp(out + 24, expect, (size_t)(need - 24)))
                    why = pass ? "lantern_db_state_patch: another state" : "lantern_db_state_diff: another diff";
                if (!why) {
                    size = 0;
                    st2 = pass ? CALL(lantern_db_state_patch, base, diff, small, &size) : CALL(lantern_db_state_diff, base, state, small, &size);
                    if (st2 != 1 || size != need) why = "one byte short: not LANTERN_BUFFER_TOO_SMALL with the size";
                    else if (!guard_ok(small, need - 1)) why = "one byte short: wrote out of bounds";
                }
                free(out);
                free(small);
            }
            free(state);
            free(diff);
        }
        free(base);
        report(file, name, len, !why, why);
    }
}

/* ---------------------------------------------------------------- Application */

#define INVALID_OPTION 61
#define APP_OPTIONS_SIZE 200

/*
 * app-options: lantern_app_options over each case's command line (tests/generator/app.py), as an
 * ArgList with a '#' after the bytes of each argument. A text field must be an Arg inside the
 * bytes of one argument and hold the case's text. A fault must give the case's index.
 */
static void run_app_options(const char *file, case_file *f) {
    static const char *texts[] = {"network_dir", "execution", "jwt_secret", "boot_nodes", "data_dir", "checkpoint_state",
                                  "checkpoint_block", "builder"};
    static const uint64_t text_at[] = {0, 16, 32, 48, 96, 112, 128, 176};
    static const char *numbers[] = {"port", "enr_address", "http_port", "target_peers", "log_level", "http_address",
                                    "http_max_connections", "supernode", "archive"};
    static const uint64_t number_at[] = {64, 72, 80, 88, 144, 152, 160, 168, 192};
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, total = 0, alen;
        tv parts = next_case(f, &name, &len);
        tv args = tv_get(parts, "args"), want = tv_get(parts, "options"), wfault = tv_get(parts, "fault");
        uint64_t count = rd64(args + 1);
        tv a = args + 9;
        for (uint64_t k = 0; k < count; k++, a = tv_skip(a)) {
            tv_bytes(a, &alen);
            total += alen + 1;
        }
        /* ArgList: size, args (40, count), bytes (40 + 16 count, total), the entries, the bytes */
        uint64_t at = 40 + 16 * count, size = (at + total + 7) & ~(uint64_t)7;
        uint8_t *list = buffer(size), *opts = buffer(APP_OPTIONS_SIZE);
        wr64(list, size);
        wr64(list + 8, 40);
        wr64(list + 16, count);
        wr64(list + 24, at);
        wr64(list + 32, total);
        a = args + 9;
        for (uint64_t k = 0, b = at; k < count; k++, a = tv_skip(a)) {
            const uint8_t *bytes = tv_bytes(a, &alen);
            wr64(list + 40 + 16 * k, b);
            wr64(list + 48 + 16 * k, alen);
            memcpy(list + b, bytes, (size_t)alen);
            list[b + alen] = '#';
            b += alen + 1;
        }
        uint64_t fault = 0xFFFF, st = CALL(lantern_app_options, list, opts, &fault);
        if (!guard_ok(opts, APP_OPTIONS_SIZE) || !guard_ok(list, size)) why = "lantern_app_options wrote out of bounds";
        else if (want) {
            if (st != 0) why = "status is not LANTERN_OK";
            for (int t = 0; t < 8 && !why; t++) {
                uint64_t at = text_at[t], wl, start = rd64(opts + at), got = rd64(opts + at + 8);
                const uint8_t *w = tv_bytes(tv_get(want, texts[t]), &wl);
                int inside = got == 0;
                for (uint64_t k = 0; k < count && !inside; k++)
                    inside = start >= rd64(list + 40 + 16 * k) && start + got <= rd64(list + 40 + 16 * k) + rd64(list + 48 + 16 * k);
                if (got != wl || !inside || (wl && memcmp(list + start, w, (size_t)wl))) why = texts[t];
            }
            for (int t = 0; t < 9 && !why; t++)
                if (rd64(opts + number_at[t]) != tv_u64(tv_get(want, numbers[t]))) why = numbers[t];
        } else if (st != INVALID_OPTION) why = "status is not LANTERN_INVALID_OPTION";
        else if (fault != tv_u64(wfault)) why = "fault is not the case's index";
        report(file, name, len, !why, why);
        free(list);
        free(opts);
    }
}

/* ---------------------------------------------------------------- Beacon API */

#define HTTP_MORE_STATUS 53

#define HTTP_INVALID_STATUS 52
#define HTTP_REQUEST_FIXED 144

/* The status of lantern_http_request on the first len bytes of b, with out of osize bytes; the HTTP status in *http. */
static uint64_t http_request_call(const uint8_t *b, uint64_t len, const uint64_t *limits, uint64_t osize, uint8_t **out,
                                  uint64_t *http, const char **why) {
    uint64_t size;
    uint8_t *l = list_of(b, len, 0, 8, &size), *lim = buffer(16);
    wr64(lim, limits[0]);
    wr64(lim + 8, limits[1]);
    *out = buffer(osize);
    wr64(*out, osize);
    uint64_t st = CALL(lantern_http_request, l, lim, *out);
    if (!guard_ok(*out, osize) || !guard_ok(l, size) || !guard_ok(lim, 16)) *why = "lantern_http_request wrote out of bounds";
    *http = rd64(*out + 8);
    free(l);
    free(lim);
    return st;
}

#define JSON_MORE_STATUS 65
#define JSON_CURSOR_SIZE 600

/*
 * json-encode: lantern_json_encode of each case's value (tests/generator/json_codec.py), read with
 * the type of this fork's type table of the case's name, when lantern has it: the JSON in one call
 * must be the case's, and in calls of 1, 7 and 64 bytes of room the bytes of all calls in order;
 * one byte short of the whole gives LANTERN_JSON_MORE, and no room LANTERN_BUFFER_TOO_SMALL. The
 * same again with lantern_json_encode_ssz of the case's SSZ bytes.
 */
static unsigned long json_types_skipped;
static void run_json_encode(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, tlen, slen, jlen, vsize = 0;
        tv parts = next_case(f, &name, &len);
        const uint8_t *tn = tv_bytes(tv_get(parts, "type"), &tlen), *enc = tv_bytes(tv_get(parts, "ssz"), &slen);
        const uint8_t *want = tv_bytes(tv_get(parts, "json"), &jlen);
        char tname[128];
        snprintf(tname, sizeof tname, "%.*s", (int)(tlen < 120 ? tlen : 120), (const char *)tn);
        const uint8_t *desc = type_by_name(tname);
        if (!desc) {
            json_types_skipped++;
            continue;
        }
        uint8_t *value = decode(desc, enc, slen, &vsize, &why);
        uint64_t esize;
        uint8_t *encl = list_of(enc, slen, 0, 8, &esize);
        static const uint64_t rooms[4] = {0, 1, 7, 64}; /* 0: all of it at once */
        for (int r = 0; r < 8 && !why; r++) {
            int ssz_in = r >= 4; /* the second four: from the SSZ bytes */
            const uint8_t *input = ssz_in ? encl : value;
            uint64_t room = rooms[r % 4] ? rooms[r % 4] : jlen + 8, got = 0, calls = 0, st = JSON_MORE_STATUS;
            uint8_t *cursor = buffer(JSON_CURSOR_SIZE), *out = buffer(24 + room), *all = buffer(jlen + 64);
            memset(cursor, 0, JSON_CURSOR_SIZE);
            while (st == JSON_MORE_STATUS && !why) {
                wr64(out, 24 + room);
                wr64(out + 8, 24);
                wr64(out + 16, 0);
                st = ssz_in ? CALL(lantern_json_encode_ssz, desc, input, cursor, out) : CALL(lantern_json_encode, desc, input, cursor, out);
                if (!guard_ok(out, 24 + room) || !guard_ok(cursor, JSON_CURSOR_SIZE) || !guard_ok(value, vsize) || !guard_ok(encl, esize))
                    why = "lantern_json_encode wrote out of bounds";
                else if (st != 0 && st != JSON_MORE_STATUS) why = "status is neither LANTERN_OK nor LANTERN_JSON_MORE";
                else if (rd64(out + 16) > room || (st == JSON_MORE_STATUS && rd64(out + 16) != room))
                    why = "a call did not fill its room";
                else if (got + rd64(out + 16) > jlen) why = "more bytes than the case's JSON";
                else {
                    memcpy(all + got, out + 24, (size_t)rd64(out + 16));
                    got += rd64(out + 16);
                }
                if (++calls > jlen + 2) why = "the calls do not end";
            }
            if (!why && (got != jlen || memcmp(all, want, (size_t)jlen))) {
                static char msg[700];
                uint64_t k = 0;
                while (k < got && k < jlen && all[k] == want[k]) k++;
                snprintf(msg, sizeof msg, "%s, room %llu: the JSON differs at byte %llu of %llu (case %llu): %.*s",
                         ssz_in ? "from SSZ" : "from the value", (unsigned long long)room, (unsigned long long)k, (unsigned long long)got, (unsigned long long)jlen,
                         (int)(got - k < 200 ? got - k : 200), (const char *)all + k);
                why = msg;
            }
            free(cursor);
            free(out);
            free(all);
        }
        if (!why && jlen > 1) { /* one byte short, then no room */
            uint8_t *cursor = buffer(JSON_CURSOR_SIZE), *out = buffer(24 + jlen - 1);
            memset(cursor, 0, JSON_CURSOR_SIZE);
            wr64(out, 24 + jlen - 1);
            wr64(out + 8, 24);
            wr64(out + 16, 0);
            if (CALL(lantern_json_encode, desc, value, cursor, out) != JSON_MORE_STATUS) why = "one byte short is not LANTERN_JSON_MORE";
            wr64(out, 24);
            wr64(out + 16, 0);
            if (!why && CALL(lantern_json_encode, desc, value, cursor, out) != 1) why = "no room is not LANTERN_BUFFER_TOO_SMALL";
            free(cursor);
            free(out);
        }
        free(value);
        free(encl);
        report(file, name, len, !why, why);
    }
}

#define JSON_INVALID_STATUS 54
#define JSON_FAULT_BYTES 128
#define JSON_DECODE_SCRATCH 6208

/*
 * json-decode: lantern_json_decode of each case's text (tests/generator/json_codec.py), with the
 * type of this fork's type table of the case's name, when lantern has it: the SSZ bytes of a valid
 * text, else LANTERN_INVALID_JSON and the case's JsonFault (kind, offset, path); a valid text with
 * one byte less of room gives LANTERN_BUFFER_TOO_SMALL and its size, and so does a scratch one
 * byte short. json-engine_decode: the same with lantern_engine_json_decode (the Engine API's JSON).
 */
static void run_json_decode(const char *file, case_file *f, int engine) {
    ABI uint64_t (*decode_fn)(const void *, const void *, void *, void *, void *) = engine ? lantern_engine_json_decode : lantern_json_decode;
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, tlen, jlen, slen = 0, lsize;
        tv parts = next_case(f, &name, &len);
        const uint8_t *tn = tv_bytes(tv_get(parts, "type"), &tlen), *json = tv_bytes(tv_get(parts, "json"), &jlen);
        tv want = tv_get(parts, "ssz");
        const uint8_t *ssz = want ? tv_bytes(want, &slen) : NULL;
        char tname[128];
        snprintf(tname, sizeof tname, "%.*s", (int)(tlen < 120 ? tlen : 120), (const char *)tn);
        const uint8_t *desc = type_by_name(tname);
        if (!desc) {
            json_types_skipped++;
            continue;
        }
        uint8_t *l = list_of(json, jlen, 0, 8, &lsize), *scratch = buffer(JSON_DECODE_SCRATCH), *fault = buffer(JSON_FAULT_BYTES);
        uint64_t osize = 24 + slen + 64;
        uint8_t *out = buffer(osize);
        wr64(scratch, JSON_DECODE_SCRATCH);
        wr64(out, osize);
        uint64_t st = CALL(decode_fn, desc, l, scratch, out, fault);
        if (!guard_ok(out, osize) || !guard_ok(fault, JSON_FAULT_BYTES) || !guard_ok(scratch, JSON_DECODE_SCRATCH) || !guard_ok(l, lsize))
            why = "lantern_json_decode wrote out of bounds";
        else if (ssz) {
            if (st != 0) {
                static char msg[200];
                snprintf(msg, sizeof msg, "status %llu, fault %llu at %llu depth %llu", (unsigned long long)st,
                         (unsigned long long)rd64(fault), (unsigned long long)rd64(fault + 8), (unsigned long long)rd64(fault + 24));
                why = msg;
            } else if (rd64(out + 8) != 24 || rd64(out + 16) != slen || memcmp(out + 24, ssz, (size_t)slen)) {
                static char msg[200];
                uint64_t k = 0;
                while (k < slen && k < rd64(out + 16) && out[24 + k] == ssz[k]) k++;
                snprintf(msg, sizeof msg, "the encoding differs at byte %llu of %llu (case %llu)", (unsigned long long)k,
                         (unsigned long long)rd64(out + 16), (unsigned long long)slen);
                why = msg;
            }
            if (!why && slen) { /* one byte less of room */
                wr64(out, 24 + slen - 1);
                wr64(scratch, JSON_DECODE_SCRATCH);
                if (CALL(decode_fn, desc, l, scratch, out, fault) != 1 || rd64(fault + 16) != slen)
                    why = "one byte less of room is not LANTERN_BUFFER_TOO_SMALL with the encoding's size";
            }
            if (!why) { /* a scratch one byte short */
                wr64(out, osize);
                wr64(scratch, JSON_DECODE_SCRATCH - 1);
                if (CALL(decode_fn, desc, l, scratch, out, fault) != 1) why = "a short scratch is not LANTERN_BUFFER_TOO_SMALL";
            }
        } else {
            tv path = tv_get(parts, "fault_path");
            uint64_t depth = rd64(path + 1), ok = st == JSON_INVALID_STATUS && rd64(fault) == tv_u64(tv_get(parts, "fault_kind")) &&
                                                  rd64(fault + 8) == tv_u64(tv_get(parts, "fault_offset")) && rd64(fault + 24) == depth;
            tv p = path + 9;
            for (uint64_t k = 0; k < depth && ok && k < 12; k++, p = tv_skip(p))
                if (rd64(fault + 32 + 8 * k) != tv_u64(p)) ok = 0;
            if (!ok) {
                static char msg[300];
                snprintf(msg, sizeof msg, "status %llu, fault %llu at %llu depth %llu; the case's %llu at %llu depth %llu",
                         (unsigned long long)st, (unsigned long long)rd64(fault), (unsigned long long)rd64(fault + 8),
                         (unsigned long long)rd64(fault + 24), (unsigned long long)tv_u64(tv_get(parts, "fault_kind")),
                         (unsigned long long)tv_u64(tv_get(parts, "fault_offset")), (unsigned long long)depth);
                why = msg;
            }
        }
        free(l);
        free(scratch);
        free(fault);
        free(out);
        report(file, name, len, !why, why);
    }
}

/*
 * One request to the node on the connection conn (docs/reference/node.md, Test vectors): its
 * HttpRequest of lantern_http_request (head_max 16384, body_max 1048576) in a NODE_EV_API, then
 * the node settles; the connection's sends and closes are in s->api.
 */
static void shell_api_ask(fc_node *n, const uint8_t *req, uint64_t len, uint64_t conn, const char **why) {
    static const uint64_t limits[2] = {16384, 1048576};
    struct node_shell *s = n->shell;
    uint8_t *out = NULL;
    uint64_t http = 0, osize = (HTTP_REQUEST_FIXED + 2 * len + 64 + 7) & ~(uint64_t)7;
    uint64_t st = http_request_call(req, len, limits, osize, &out, &http, why);
    if (!*why && st != 0 && st != HTTP_INVALID_STATUS) *why = "lantern_http_request: status is not LANTERN_OK or LANTERN_INVALID_HTTP";
    s->api.conn = conn;
    s->api.len = s->api.sends = s->api.lasts = s->api.closes = s->api.late = 0;
    s->api.gone = 0;
    s->api.nids = 0;
    if (!*why) {
        if (st != 0) wr64(out, HTTP_REQUEST_FIXED); /* LANTERN_INVALID_HTTP: the fixed part, with its status */
        shell_event(s, EV_API, conn, out, rd64(out));
        shell_settle(n, why);
    }
    free(out);
}

/*
 * shell_api_ask, with a NODE_EV_API_CLOSED of the connection after steps steps of the node (or once
 * it settled); after the step that takes the close, the node must send nothing more to it.
 */
/* Returns the steps the node took before the close: below steps when it had no event left. */
static uint64_t shell_api_ask_closing(fc_node *n, const uint8_t *req, uint64_t len, uint64_t conn, uint64_t steps, const char **why) {
    static const uint64_t limits[2] = {16384, 1048576};
    struct node_shell *s = n->shell;
    uint8_t *out = NULL;
    uint64_t http = 0, osize = (HTTP_REQUEST_FIXED + 2 * len + 64 + 7) & ~(uint64_t)7;
    uint64_t st = http_request_call(req, len, limits, osize, &out, &http, why);
    if (!*why && st != 0) *why = "lantern_http_request: status is not LANTERN_OK";
    s->api.conn = conn;
    s->api.len = s->api.sends = s->api.lasts = s->api.closes = s->api.late = 0;
    s->api.gone = 0;
    s->api.nids = 0;
    uint64_t k = 0;
    if (!*why) {
        shell_event(s, EV_API, conn, out, rd64(out));
        for (; k < steps && s->pending_len && !*why; k++) shell_step(n, why);
    }
    if (!*why) {
        shell_event(s, EV_API_CLOSED, conn, NULL, 0);
        shell_step(n, why);
        s->api.gone = 1;
        s->api.late = 0;
    }
    if (!*why) shell_settle(n, why);
    if (!*why && s->api.late) *why = "an answer goes on after its connection closed";
    free(out);
    return k;
}

/*
 * The connection's bytes in the form with Content-Length (docs/reference/node.md, Test vectors): a
 * chunked body, each chunk's size in 4 lower case hex digits, decoded, with Content-Length in place
 * of Transfer-Encoding; a body with neither field, after Eth-Consensus-Version, with Content-Length
 * after that line, when the connection closes. Returns a new buffer of *len bytes, or NULL with why.
 */
static uint8_t *api_normalize(const struct node_shell *s, uint64_t *len, const char **why) {
    const char *b = (const char *)s->api.b, *end = s->api.b ? find_bytes(b, s->api.len, "\r\n\r\n") : NULL;
    uint8_t *out = buffer(s->api.len + 64);
    if (!end) {
        memcpy(out, b ? b : "", (size_t)s->api.len);
        *len = s->api.len;
        return out;
    }
    uint64_t head = (uint64_t)(end - b) + 4, k = 0;
    const char *te = find_bytes(b, head, "\r\nTransfer-Encoding: chunked\r\n");
    const char *ecv = find_bytes(b, head, "\r\nEth-Consensus-Version: ");
    if (te) { /* the chunks: size, CRLF, bytes, CRLF; then 0 CRLF CRLF */
        uint64_t at = head, body = 0, pre = (uint64_t)(te - b) + 2;
        uint8_t *data = buffer(s->api.len);
        for (;;) {
            if (at + 5 == s->api.len && !memcmp(b + at, "0\r\n\r\n", 5)) break;
            if (at + 6 > s->api.len) {
                *why = "a chunked body ends early";
                break;
            }
            uint64_t n = 0;
            for (int d = 0; d < 4; d++) {
                char c = b[at + d];
                int v = (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
                if (v < 0) n = UINT64_MAX;
                else if (n != UINT64_MAX) n = n * 16 + (uint64_t)v;
            }
            if (n == UINT64_MAX || n == 0 || b[at + 4] != '\r' || b[at + 5] != '\n' || at + 6 + n + 2 > s->api.len ||
                b[at + 6 + n] != '\r' || b[at + 7 + n] != '\n') {
                *why = "a chunk breaks RFC 9112 section 7.1 or its 4 hex digits";
                break;
            }
            memcpy(data + body, b + at + 6, (size_t)n);
            body += n;
            at += 6 + n + 2;
        }
        memcpy(out, b, (size_t)pre);
        k = pre + (uint64_t)sprintf((char *)out + pre, "Content-Length: %llu\r\n", (unsigned long long)body);
        memcpy(out + k, b + pre + 28, (size_t)(head - pre - 28));
        k += head - pre - 28;
        out = realloc(out, (size_t)(k + body + 1));
        memcpy(out + k, data, (size_t)body);
        free(data);
        *len = k + body;
        return out;
    }
    const char *ct = ecv ? ecv : find_bytes(b, head, "\r\nContent-Type: ");
    if (ct && !find_bytes(b, head, "\r\nContent-Length: ")) { /* HTTP/1.0: the body ends with the connection */
        const char *eol = find_bytes(ct + 2, head - (uint64_t)(ct + 2 - b), "\r\n");
        uint64_t pre = (uint64_t)(eol - b) + 2, body = s->api.len - head;
        if (!s->api.closes) *why = "a body with no length, and the connection stays open";
        memcpy(out, b, (size_t)pre);
        k = pre + (uint64_t)sprintf((char *)out + pre, "Content-Length: %llu\r\n", (unsigned long long)body);
        out = realloc(out, (size_t)(k + s->api.len - pre + 1));
        memcpy(out + k, b + pre, (size_t)(s->api.len - pre));
        *len = k + s->api.len - pre;
        return out;
    }
    memcpy(out, b, (size_t)s->api.len);
    *len = s->api.len;
    return out;
}

/*
 * node-reads (docs/reference/node.md, Test vectors): after the steps of a fork choice case in node
 * mode, each request of its node-reads case on its own connection; the sends, in the form with
 * Content-Length, must be the case's answer, and the node must hold no entry or bytes of it after.
 */
static const char *api_clean(struct node_shell *s);
static const char *api_mismatch(const struct node_shell *s, const char *name, const uint8_t *want, uint64_t wlen);
static unsigned long reads_asked; /* the node-reads requests checked */
static void fc_reads_check(fc_node *n, const char **why) {
    struct node_shell *s = n->shell;
    tv reqs = tv_get(case_reads, "requests"), wants = tv_get(case_reads, "responses");
    if (!reqs || !wants || rd64(reqs + 1) != rd64(wants + 1)) {
        *why = "the node-reads case has not an answer for each request";
        return;
    }
    tv rq = reqs + 9, w = wants + 9;
    for (uint64_t k = 0, c = rd64(reqs + 1); k < c && !*why; k++, rq = tv_skip(rq), w = tv_skip(w)) {
        uint64_t rlen, wlen, glen = 0;
        const uint8_t *req = tv_bytes(rq, &rlen), *want = tv_bytes(w, &wlen);
        s->api.room = 0;
        shell_api_ask(n, req, rlen, 40, why);
        uint8_t *g = *why ? NULL : api_normalize(s, &glen, why);
        if (!*why && (glen != wlen || memcmp(g, want, (size_t)wlen))) {
            static char msg[1200];
            const char *eol = memchr(req, '\r', (size_t)rlen);
            snprintf(msg, sizeof msg, "node-reads %.*s: %s", (int)(eol ? eol - (const char *)req : 0), (const char *)req,
                     api_mismatch(s, "the answer", want, wlen));
            *why = msg;
        }
        if (!*why && s->api.lasts != 1) *why = "node-reads: not one send with last 1";
        if (!*why) {
            const char *c = api_clean(s);
            if (c) *why = c;
        }
        free(g);
        reads_asked++;
    }
}

/* 0 when the node holds no NodeApi entry and each id of a NODE_ACT_STATE_BYTES is free, else why. */
static const char *api_clean(struct node_shell *s) {
    uint64_t open = 0; /* the entries of the event streams still open may stay */
    for (int e = 0; e < s->nev; e++) open += !s->ev[e].gone && !s->ev[e].closed && !s->ev[e].closes;
    if (rd64(s->node + NODE_API_PART + 8) > open) return "the node holds a NodeApi entry after the answer";
    for (size_t k = 0; k < s->api.nids; k++)
        if (shell_find(s, s->api.ids[k])) return "the state's bytes of an answer are not freed";
    return NULL;
}

/* The answer's response bytes, then a line of its sends and closes, for a failure message. */
static const char *api_mismatch(const struct node_shell *s, const char *name, const uint8_t *want, uint64_t wlen) {
    static char msg[1024];
    uint64_t k = 0;
    while (k < s->api.len && k < wlen && s->api.b[k] == want[k]) k++;
    snprintf(msg, sizeof msg, "%s: the response differs at byte %llu of %llu (case %llu), sends %llu, lasts %llu, closes %llu: got %.*s",
             name, (unsigned long long)k, (unsigned long long)s->api.len, (unsigned long long)wlen, (unsigned long long)s->api.sends,
             (unsigned long long)s->api.lasts, (unsigned long long)s->api.closes, (int)(s->api.len < 600 ? s->api.len : 600),
             s->api.b ? (const char *)s->api.b : "");
    return msg;
}

/*
 * node-api: each case's requests to a node at its anchor (tests/generator/node.py), each on its own
 * connection, after a NODE_EV_TICK of the case's time and a NODE_EV_API_IDENTITY; from the index
 * offline on, after a NODE_EV_ENGINE with arg 1. The sends must be the case's response, the last
 * with last 1 and no other, and one NODE_ACT_API_CLOSE after them when the case closes.
 */
/*
 * node-publish: the NodeBlob entries of the case's root in NODE_BLOB_VALID must be the case's
 * sidecars at their indices: each of them before fulu, the columns of Node_columns in fulu.
 */
static const char *publish_sidecars_held(struct node_shell *s, tv parts, tv sc) {
    uint64_t rlen, nsc = rd64(sc + 1), held = 0, want = nsc;
    const uint8_t *root = tv_bytes(tv_get(parts, "root"), &rlen);
    static char msg[160];
#if FORK >= FORK_FULU
    if (nsc) {
        want = 0;
        for (int i = 0; i < 128; i++) want += (s->node[440 + i / 8] >> (i % 8)) & 1; /* Node_columns */
    }
#endif
    uint64_t off = rd64(s->node + NODE_BLOBS), count = rd64(s->node + NODE_BLOBS + 8);
    for (uint64_t i = 0; i < count; i++) {
        const uint8_t *e = s->node + off + NODE_BLOB_BYTES * i;
        if (rlen != 32 || memcmp(e, root, 32) || rd64(e + 56) != NBLOB_VALID) continue;
        uint64_t index = rd64(e + 32), glen;
        shell_buf *b = shell_find(s, rd64(e + 48));
        tv item = sc + 9;
        for (uint64_t k = 0; k < index && k < nsc; k++) item = tv_skip(item);
        if (index >= nsc) {
            snprintf(msg, sizeof msg, "a NodeBlob of index %llu, past the case's sidecars", (unsigned long long)index);
            return msg;
        }
        const uint8_t *g = tv_bytes(item, &glen);
        if (!b || rd64(b->b + 16) != glen || memcmp(b->b + rd64(b->b + 8), g, (size_t)glen)) {
            snprintf(msg, sizeof msg, "the NodeBlob of index %llu is not the spec's sidecar", (unsigned long long)index);
            return msg;
        }
        held++;
    }
    if (held != want) {
        snprintf(msg, sizeof msg, "the node holds %llu sidecars of the block, not %llu", (unsigned long long)held,
                 (unsigned long long)want);
        return msg;
    }
    return NULL;
}

/*
 * The closes of a node-produce case: the request, its connection closed after each number of the
 * node's steps below closes; after each the node must hold no entry and no buffer of it.
 */
static void produce_closes(fc_node *n, const uint8_t *req, uint64_t rlen, uint64_t closes, const char **why) {
    struct node_shell *s = n->shell;
    for (uint64_t c = 0; c < closes && !*why; c++) {
        size_t nbufs = s->nbufs;
        uint64_t held = node_held_ids(s->node);
        uint64_t took = shell_api_ask_closing(n, req, rlen, 1000 + c, c, why);
        if (!*why && c + 1 == closes && took == c) *why = "the case's closes end before the node settles";
        if (!*why) *why = api_clean(s);
        if (!*why && s->nbufs - nbufs != node_held_ids(s->node) - held) *why = "a request whose connection closed leaves buffers";
        if (*why) {
            static char msg[256];
            snprintf(msg, sizeof msg, "the connection closed after %llu steps: %s", (unsigned long long)c, *why);
            *why = msg;
        }
    }
}

/*
 * node-produce and node-publish: lantern's cases of produceBlockV3 and publishBlockV2 (node.md, Test
 * vectors). Each request after its tick; the runner's buffers grow only by those the node holds.
 */
static void run_node_produce(const char *file, const char *dir, case_file *f) {
#if FORK >= FORK_DENEB
    load_kzg_settings(dir); /* the sidecars' gossip checks */
#else
    (void)dir;
#endif
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        fc_node n;
        uint8_t *anchor_block;
        tv bflag = tv_get(parts, "builder");
        int builder = bflag && tv_u64(bflag);
        force_builder = builder; /* the builder cases: the runner is the node's builder, its bids the case's */
        tv eflag = tv_get(parts, "eth1");
        force_eth1 = eflag && tv_u64(eflag); /* the eth1 cases: the runner is the node's eth1 chain too */
        struct node_shell *s = shell_open(&n, parts, &anchor_block, &why);
        force_builder = 0;
        if (force_eth1 && s) {
            uint64_t bl, dl, cl;
            s->eth1_blocks = tv_bytes(tv_get(parts, "eth1_blocks"), &bl);
            s->eth1_deposits = tv_bytes(tv_get(parts, "eth1_deposits"), &dl);
            s->eth1_contract = tv_bytes(tv_get(parts, "eth1_contract"), &cl);
            s->eth1_nblocks = bl / 48;
            s->eth1_ndeposits = dl / 200;
            s->eth1_calls = 0;
            if (cl != 20) why = "the eth1 case's contract is not 20 bytes";
        }
        force_eth1 = 0;
        if (builder) {
            s->bids = tv_get(parts, "bids");
            s->nbids = s->bids ? rd64(s->bids + 1) : 0;
            s->submits = tv_get(parts, "submits");
            s->nsubmits = s->submits ? rd64(s->submits + 1) : 0;
            s->bid_calls = s->submit_calls = s->bld_len = s->bld_calls = 0;
        }
        tv reqs = tv_get(parts, "requests"), resps = tv_get(parts, "responses");
        n.produce = 1;
        n.pid = tv_bytes(tv_get(parts, "payload_id"), &plen);
        n.pid_len = plen;
        n.result = tv_bytes(tv_get(parts, "result"), &n.result_len);
        if (!why) {
            for (uint64_t fk = FORK_ALTAIR; fk <= FORK_FULU; fk++)
                wr64(n.store + STORE_CONFIG + 16 * fk, rd64(s->ncfg + 16 * fk));
            shell_event(s, EV_TICK, tv_u64(tv_get(parts, "time_ms")), NULL, 0);
            shell_settle(&n, &why);
        }
        uint64_t elen = 0;
        tv evp = tv_get(parts, "events");
        const uint8_t *events = evp ? tv_bytes(evp, &elen) : NULL;
        if (!why && elen) { /* node-publish: the events of the publishes, a stream open over the case */
            static const char ereq[] = "GET /eth/v1/events?topics=block_gossip,blob_sidecar,data_column_sidecar HTTP/1.1\r\nHost: lantern\r\n\r\n";
            ev_open_one(&n, 0, (const uint8_t *)ereq, sizeof ereq - 1, &why);
        }
        tv rq = reqs + 9, rs = resps + 9, tk = tv_get(parts, "ticks") + 9, afterp = tv_get(parts, "after");
        tv af = afterp ? afterp + 9 : NULL;
        uint64_t nreq = rd64(reqs + 1), closes = tv_u64(tv_get(parts, "closes"));
        if (rd64(tv_get(parts, "ticks") + 1) != nreq) why = "the case's ticks are not one for each request";
        if (afterp && rd64(afterp + 1) != nreq) why = "the case's after ticks are not one for each request";
        for (uint64_t k = 0; k < nreq && !why; k++, rq = tv_skip(rq), rs = tv_skip(rs), tk = tv_skip(tk), af = af ? tv_skip(af) : NULL) {
            uint64_t rlen, wlen, glen = 0, at = tv_u64(tk), later = af ? tv_u64(af) : 0;
            const uint8_t *req = tv_bytes(rq, &rlen), *want = tv_bytes(rs, &wlen);
            if (at) { /* a tick before the request */
                shell_event(s, EV_TICK, at, NULL, 0);
                shell_settle(&n, &why);
                if (why) break;
            }
            if (closes && k + 1 == nreq) /* the last request: its connection closed after each number of steps up to closes */
                produce_closes(&n, req, rlen, closes, &why);
            if (why) break;
            size_t nbufs = s->nbufs;
            uint64_t held = node_held_ids(s->node);
            shell_api_ask(&n, req, rlen, (k + 1) | (uint64_t)7 << 32, &why);
            if (!why && later) { /* a tick after the request: no answer before it */
                if (s->api.len) why = "an answer before the tick after the request";
                if (!why) {
                    shell_event(s, EV_TICK, later, NULL, 0);
                    shell_settle(&n, &why);
                }
            }
            if (!why && s->nbufs - nbufs != node_held_ids(s->node) - held) why = "a request leaves buffers the node does not hold";
            uint8_t *got = why ? NULL : api_normalize(s, &glen, &why);
            if (!why && (glen != wlen || memcmp(got, want, (size_t)wlen))) {
                free(s->api.b);
                s->api.b = got;
                s->api.len = s->api.cap = glen;
                got = NULL;
                static char label[32];
                snprintf(label, sizeof label, "request %llu", (unsigned long long)k);
                why = api_mismatch(s, label, want, wlen);
            }
            free(got);
            if (!why) why = api_clean(s);
        }
        tv bwant = tv_get(parts, "builders");
        if (!why && builder && bwant) { /* the requests of the node's builder calls, in their order */
            uint64_t bwlen;
            const uint8_t *bw = tv_bytes(bwant, &bwlen);
            if (s->bld_len != bwlen || (bwlen && memcmp(s->bld, bw, (size_t)bwlen))) {
                static char msg[384];
                uint64_t at = 0;
                while (at < s->bld_len && at < bwlen && s->bld[at] == bw[at]) at++;
                snprintf(msg, sizeof msg, "the builder calls differ at byte %llu (%llu bytes, %llu calls; the case's %llu): %.*s",
                         (unsigned long long)at, (unsigned long long)s->bld_len, (unsigned long long)s->bld_calls,
                         (unsigned long long)bwlen, (int)(s->bld_len - at < 200 ? s->bld_len - at : 200), (const char *)s->bld + at);
                why = msg;
            }
        }
        if (!why && elen) ev_stream_end(&n, 0, events, elen, "the publish events", &why);
        if (!why && elen) why = api_clean(s);
        tv sc = tv_get(parts, "sidecars");
        if (!why && sc) why = publish_sidecars_held(s, parts, sc);
        n.produce = 0;
        shell_close(&n, anchor_block);
        report(file, name, len, why == NULL, why);
    }
}

/* node-payload: lantern's cases of payload preparation (node.md, Test vectors). */
#define NODE_PAYLOAD_SLOT (NODE_API_PART + 664) /* Node_payload_slot: past the proposers PartRef */
/* lantern_node_liveness (node.md, node-liveness): a Seen of the case's keys, its ids, the byte of each. */
static void run_node_liveness(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, slen, klen, ilen, wlen, size = 0;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        uint8_t *state = load_state(tv_bytes(tv_get(parts, "state"), &slen), slen, &size, &why);
        const uint8_t *keys = tv_bytes(tv_get(parts, "keys"), &klen), *ids = tv_bytes(tv_get(parts, "ids"), &ilen);
        const uint8_t *want = tv_bytes(tv_get(parts, "out"), &wlen);
        uint64_t epoch = tv_u64(tv_get(parts, "epoch")), count = ilen / 8;
        seen_buf seen = {NULL, 0, {klen / 32 + 1, 1, 1, 64}};
        if (!why) seen_make(&seen, &why);
        if (!why) { /* the keys, in order, after those of lantern_seen_init */
            uint64_t off = rd64(seen.b + 8), n = rd64(seen.b + 16);
            memcpy(seen.b + off + 32 * n, keys, (size_t)klen);
            wr64(seen.b + 16, n + klen / 32);
        }
        uint8_t *list = buffer(24 + 64 * count), *out = buffer(count + 8);
        wr64(list, 24 + 64 * count);
        wr64(list + 8, 24);
        wr64(list + 16, 64 * count);
        memset(list + 24, 0, (size_t)(64 * count));
        for (uint64_t k = 0; k < count; k++) {
            wr64(list + 24 + 64 * k, 1); /* API_VALIDATOR_INDEX */
            wr64(list + 24 + 64 * k + 8, rd64(ids + 8 * k));
        }
        memset(out, FILL, (size_t)(count + 8 + GUARD));
        uint8_t *state0 = state ? copy_of(state, size) : NULL, *seen0 = seen.b ? copy_of(seen.b, seen.size) : NULL;
        if (!why) {
            uint64_t st = CALL(LF(node_liveness), state, config, seen.b, list, (const void *)(uintptr_t)epoch, fresh_scratch(), out);
            if (st != 0) why = "status";
            else if (wlen != count || memcmp(out, want, (size_t)count)) why = "out differs";
            else if (!guard_ok(out, count)) why = "wrote past out";
            else if (memcmp(state, state0, (size_t)size)) why = "changed the state";
            else if (memcmp(seen.b, seen0, (size_t)seen.size)) why = "changed the seen";
        }
        free(state0);
        free(seen0);
        free(list);
        free(out);
        free(state);
        free(seen.b);
        report(file, name, len, why == NULL, why);
    }
}

/* SYNC_COMMITTEE_SIZE of the preset (presets/<preset>/altair.yaml). */
#define SYNC_SIZE_RUNNER (strcmp(PRESET, "minimal") ? 512u : 32u)

/* A ByteList of the bytes (len of them), in a new buffer. */
static uint8_t *byte_list_of(const uint8_t *bytes, uint64_t len) {
    uint8_t *list = buffer(24 + len);
    wr64(list, 24 + len);
    wr64(list + 8, 24);
    wr64(list + 16, len);
    memcpy(list + 24, bytes, (size_t)len);
    return list;
}

/*
 * lantern_node_block_rewards and lantern_node_sync_rewards (node.md, node-rewards): the case's status,
 * the 48 bytes of the block's rewards and the sync items; the inputs keep their bytes, and an out one
 * byte short of room gives LANTERN_BUFFER_TOO_SMALL.
 */
static void run_node_rewards(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, blen, elen, llen, wlen, slen = 0, psize = 0, esize = 0, lsize = 0;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        const uint8_t *penc = tv_bytes(tv_get(parts, "pre"), &plen), *benc = tv_bytes(tv_get(parts, "block"), &blen);
        const uint8_t *eenc = tv_bytes(tv_get(parts, "early"), &elen), *lenc = tv_bytes(tv_get(parts, "late"), &llen);
        const uint8_t *want = tv_bytes(tv_get(parts, "rewards"), &wlen);
        uint64_t status = tv_u64(tv_get(parts, "status"));
        uint8_t *pre = load_state(penc, plen, &psize, &why);
        uint8_t *early = elen && !why ? load_state(eenc, elen, &esize, &why) : NULL;
        uint8_t *late = llen && !why ? load_state(lenc, llen, &lsize, &why) : NULL;
        uint8_t *block = byte_list_of(benc, blen), *out = buffer(48);
        uint8_t *pre0 = pre ? copy_of(pre, psize) : NULL, *block0 = copy_of(block, 24 + blen);
        uint8_t *early0 = early ? copy_of(early, esize) : NULL, *late0 = late ? copy_of(late, lsize) : NULL;
        memset(out, FILL, 48 + GUARD);
        if (!why) {
            uint64_t st = CALL(LF(node_block_rewards), pre, block, early, late, config, fresh_scratch(), out);
            if (st != status) why = "lantern_node_block_rewards: status";
            else if (st == 0 && (wlen != 48 || memcmp(out, want, 48))) why = "lantern_node_block_rewards: out differs";
            else if (!guard_ok(out, 48)) why = "lantern_node_block_rewards: wrote past out";
        }
#if FORK == FORK_PHASE0
        (void)slen;
        if (!why) { /* phase0 has no sync committee */
            uint8_t small[24 + GUARD];
            wr64(small, 24);
            if (CALL(LF(node_sync_rewards), pre, block, fresh_scratch(), small) != 66) why = "lantern_node_sync_rewards: not LANTERN_NO_STATE_ANSWER in phase0";
        }
#else
        const uint8_t *items = tv_bytes(tv_get(parts, "sync"), &slen);
        uint64_t room = 24 + 16 * (uint64_t)SYNC_SIZE_RUNNER;
        uint8_t *list = buffer(room);
        for (int r = 0; r < 2 && !why; r++) {
            memset(list, FILL, (size_t)(room + GUARD));
            wr64(list, room - (uint64_t)r);
            uint64_t st = CALL(LF(node_sync_rewards), pre, block, fresh_scratch(), list), sw = r ? 1 : status;
            if (st != sw) why = r ? "lantern_node_sync_rewards: an out a byte short is not BUFFER_TOO_SMALL" : "lantern_node_sync_rewards: status";
            else if (!r && st == 0 && (rd64(list + 8) != 24 || rd64(list + 16) != slen || memcmp(list + 24, items, (size_t)slen)))
                why = "lantern_node_sync_rewards: out differs";
            else if (!guard_ok(list, room - (uint64_t)r)) why = "lantern_node_sync_rewards: wrote past out";
        }
        free(list);
#endif
        if (!why && memcmp(pre, pre0, (size_t)psize)) why = "changed pre";
        if (!why && memcmp(block, block0, (size_t)(24 + blen))) why = "changed the block";
        if (!why && early && memcmp(early, early0, (size_t)esize)) why = "changed early";
        if (!why && late && memcmp(late, late0, (size_t)lsize)) why = "changed late";
        free(pre); free(pre0); free(early); free(early0); free(late); free(late0); free(block); free(block0); free(out);
        report(file, name, len, why == NULL, why);
    }
}

/*
 * node-attrewards (node.md): in modes 0 and 1, lantern_node_attestation_rewards of every validator
 * of the case's state, in windows of 5 and in one, and lantern_node_ideal_reward of every effective
 * balance step, must give the case's items; the state keeps its bytes.
 */
static void run_node_attrewards(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size = 0;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        uint8_t *state = load_state(tv_bytes(tv_get(parts, "pre"), &plen), plen, &size, &why);
        uint8_t *state0 = state ? copy_of(state, size) : NULL;
        for (uint64_t mode = 0; mode < 2 && !why; mode++) {
            char key[16];
            uint64_t ilen, dlen;
            snprintf(key, sizeof key, "items_%llu", (unsigned long long)mode);
            const uint8_t *want = tv_bytes(tv_get(parts, key), &ilen);
            snprintf(key, sizeof key, "ideal_%llu", (unsigned long long)mode);
            const uint8_t *ideal = tv_bytes(tv_get(parts, key), &dlen);
            for (uint64_t window = 5; window && !why; window = window == 5 ? 1u << 20 : 0) {
                uint8_t totals[96 + GUARD];
                uint8_t *items = attestation_rewards_of(state, mode, window, totals, &why);
                if (items && memcmp(items, want, (size_t)ilen)) {
                    uint64_t k = 0;
                    while (k < ilen && items[k] == want[k]) k++;
                    static char msg[160];
                    snprintf(msg, sizeof msg, "mode %llu, windows of %llu: validator %llu, item byte %llu", (unsigned long long)mode,
                             (unsigned long long)window, (unsigned long long)(k / 48), (unsigned long long)(k % 48));
                    why = msg;
                }
                for (uint64_t s = 0; items && !why && s < dlen / 48; s++) {
                    uint8_t out[48 + GUARD];
                    memset(out, FILL, sizeof out);
                    uint64_t eb = rd64(ideal + 48 * s + 40);
                    if (CALL(LF(node_ideal_reward), totals, (const void *)(uintptr_t)eb, out) != 0) why = "lantern_node_ideal_reward: status";
                    else if (memcmp(out, ideal + 48 * s, 48)) {
                        static char msg[96];
                        snprintf(msg, sizeof msg, "mode %llu: lantern_node_ideal_reward of step %llu", (unsigned long long)mode,
                                 (unsigned long long)s + 1);
                        why = msg;
                    } else if (!guard_ok(out, 48)) why = "lantern_node_ideal_reward: wrote past out";
                }
                if (items && !why && rd64(totals + 72) / 1000000000u != dlen / 48) why = "the totals' largest effective balance";
                free(items);
            }
        }
        if (!why && memcmp(state, state0, (size_t)size)) why = "changed the state";
        free(state);
        free(state0);
        report(file, name, len, why == NULL, why);
    }
}

static void run_node_payload(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, rlen, wlen, plen, hlen;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        fc_node n;
        uint8_t *anchor_block;
        struct node_shell *s = shell_open(&n, parts, &anchor_block, &why);
        const uint8_t *req = tv_bytes(tv_get(parts, "request"), &rlen), *want = tv_bytes(tv_get(parts, "response"), &wlen);
        const uint8_t *root = tv_bytes(tv_get(parts, "payload_root"), &hlen);
        n.tail = tv_bytes(tv_get(parts, "tail"), &n.tail_len);
        n.pid = tv_bytes(tv_get(parts, "payload_id"), &plen);
        n.pid_len = plen;
        if (!why) {
            for (uint64_t fk = FORK_ALTAIR; fk <= FORK_FULU; fk++)
                wr64(n.store + STORE_CONFIG + 16 * fk, rd64(s->ncfg + 16 * fk));
            shell_event(s, EV_TICK, tv_u64(tv_get(parts, "time0")), NULL, 0); /* the anchor's forkchoiceUpdated, answered */
            shell_settle(&n, &why);
        }
        uint64_t elen = 0;
        const uint8_t *events = tv_bytes(tv_get(parts, "events"), &elen);
        if (!why) { /* the payload_attributes events: a stream open over the case */
            static const char ereq[] = "GET /eth/v1/events?topics=payload_attributes HTTP/1.1\r\nHost: lantern\r\n\r\n";
            ev_open_one(&n, 0, (const uint8_t *)ereq, sizeof ereq - 1, &why);
        }
        if (!why) { /* the prepareBeaconProposer, then the tick: each engine call counts from here */
            n.watch = 1;
            n.engine_calls = 0;
            shell_api_ask(&n, req, rlen, 1 | (uint64_t)7 << 32, &why);
            uint64_t glen = 0;
            uint8_t *got = why ? NULL : api_normalize(s, &glen, &why);
            if (!why && (glen != wlen || memcmp(got, want, (size_t)wlen))) why = "prepareBeaconProposer: the response differs";
            free(got);
            if (!why) why = api_clean(s);
        }
        if (!why) {
            shell_event(s, EV_TICK, tv_u64(tv_get(parts, "time1")), NULL, 0);
            shell_settle(&n, &why);
        }
        if (!why && n.engine_calls != (n.tail_len ? 1u : 0u)) why = n.tail_len ? "no forkchoiceUpdated with the attributes" : "an engine call";
        if (!why) ev_stream_end(&n, 0, events, elen, "the payload_attributes events", &why);
        if (!why) {
            const uint8_t *nd = s->node + NODE_PAYLOAD_SLOT;
            uint64_t status = rd64(nd + 48);
            if (rd64(nd) != tv_u64(tv_get(parts, "payload_slot"))) why = "payload_slot differs";
            else if (hlen != 32 || memcmp(nd + 8, root, 32)) why = "payload_root differs";
            else if (status != tv_u64(tv_get(parts, "payload_status"))) why = "payload_status differs";
            else if (status == 3 && (plen != 8 || memcmp(nd + 40, n.pid, 8))) why = "payload_id differs";
            else if (rd64(nd + 56) != tv_u64(tv_get(parts, "payload_proposer"))) why = "payload_proposer differs";
        }
        n.watch = 0;
        shell_close(&n, anchor_block);
        report(file, name, len, why == NULL, why);
    }
}

static void run_node_api(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, ilen, clen;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        fc_node n;
        uint8_t *anchor_block;
        force_builder = 1; /* the runner is the node's builder: each request's calls must be the case's */
        struct node_shell *s = shell_open(&n, parts, &anchor_block, &why);
        force_builder = 0;
        uint64_t slen, stlen;
        const uint8_t *identity = tv_bytes(tv_get(parts, "identity"), &ilen), *closes = tv_bytes(tv_get(parts, "closes"), &clen);
        tv builders = tv_get(parts, "builders"), bd = builders ? builders + 9 : NULL;
        if (builders && rd64(builders + 1) != rd64(tv_get(parts, "requests") + 1)) why = "the case's builders differ in length";
        const uint8_t *syncing = tv_bytes(tv_get(parts, "syncing"), &slen), *streams = tv_bytes(tv_get(parts, "streams"), &stlen);
        tv names = tv_get(parts, "names"), reqs = tv_get(parts, "requests"), resps = tv_get(parts, "responses");
        uint64_t count = rd64(reqs + 1), offline = tv_u64(tv_get(parts, "offline"));
        if (!why && (rd64(names + 1) != count || rd64(resps + 1) != count || clen != count || slen != count || stlen != count))
            why = "the case's lists differ in length";
        if (!why) {
            /* the store's fork epochs: the node's, as the generator's spec has them (the pools' gossip checks read them) */
            for (uint64_t fk = FORK_ALTAIR; fk <= FORK_FULU; fk++)
                wr64(n.store + STORE_CONFIG + 16 * fk, rd64(s->ncfg + 16 * fk));
            shell_event(s, EV_TICK, tv_u64(tv_get(parts, "time_ms")), NULL, 0);
            shell_event(s, EV_API_IDENTITY, 0, identity, ilen);
            shell_settle(&n, &why);
        }
        tv nm = names + 9, rq = reqs + 9, rs = resps + 9;
        const uint8_t *open_want = NULL; /* streams 2: an event stream open to the case's end, and its bytes then */
        uint64_t open_wlen = 0;
        for (uint64_t k = 0; k < count && !why; k++, nm = tv_skip(nm), rq = tv_skip(rq), rs = tv_skip(rs), bd = bd ? tv_skip(bd) : NULL) {
            uint64_t rlen, wlen, nlen, bwlen = 0;
            const uint8_t *req = tv_bytes(rq, &rlen), *want = tv_bytes(rs, &wlen), *nb = tv_bytes(nm, &nlen);
            const uint8_t *bwant = bd ? tv_bytes(bd, &bwlen) : NULL;
            char rname[96];
            snprintf(rname, sizeof rname, "%.*s", (int)(nlen < 90 ? nlen : 90), (const char *)nb);
            if (k == offline) {
                shell_event(s, EV_ENGINE, 1, NULL, 0);
                shell_settle(&n, &why);
            }
            if (streams[k] == 2) { /* once, on its own connection; its bytes are checked at the end */
                if (open_want) why = "a second open event stream";
                if (!why) ev_open_one(&n, 0, req, rlen, &why);
                open_want = want;
                open_wlen = wlen;
                continue;
            }
            /* NODE_API_CHUNK, then many small chunks: 2048 bytes, or a 512th of the response, so that a
               mainnet state goes in some hundreds of chunks */
            uint64_t rooms[2] = {0, wlen / 512 > 2048 ? (wlen / 512) & ~(uint64_t)7 : 2048};
            for (int r = 0; r < 2 && !why; r++) {
                s->api.room = rooms[r];
                size_t nbufs = s->nbufs;
                uint64_t held = node_pool_held(s->node);
                /* syncing bit 0: NODE_FLAG_SYNCING; bit 1: every node of the store NOT_VALIDATED, restored after */
                uint64_t statuses[64], nodes = node_count(&n) < 64 ? node_count(&n) : 64;
                if (syncing[k] & 1) wr64(s->node + NODE_FLAGS, rd64(s->node + NODE_FLAGS) | NODE_FLAG_SYNCING);
                for (uint64_t i = 0; (syncing[k] & 2) && i < nodes; i++) {
                    statuses[i] = rd64(node_at(&n, i) + NODE_PAYLOAD_STATUS);
                    wr64((uint8_t *)node_at(&n, i) + NODE_PAYLOAD_STATUS, PAYLOAD_NOT_VALIDATED);
                }
                s->bld_len = s->bld_calls = 0;
                shell_api_ask(&n, req, rlen, (k + 1) | (uint64_t)(7 + r) << 32, &why);
                if (!why && (s->bld_len != bwlen || (bwlen && memcmp(s->bld, bwant, (size_t)bwlen)) || s->bld_calls > 1)) {
                    static char msg[600];
                    uint64_t at = 0;
                    while (at < s->bld_len && at < bwlen && s->bld[at] == bwant[at]) at++;
                    snprintf(msg, sizeof msg, "%s: the builder calls differ at byte %llu (%llu bytes, %llu calls; the case's %llu): %.*s", rname,
                             (unsigned long long)at, (unsigned long long)s->bld_len, (unsigned long long)s->bld_calls,
                             (unsigned long long)bwlen, (int)(s->bld_len - at < 200 ? s->bld_len - at : 200), (const char *)s->bld + at);
                    why = msg;
                }
                if (syncing[k] & 1) wr64(s->node + NODE_FLAGS, rd64(s->node + NODE_FLAGS) & ~(uint64_t)NODE_FLAG_SYNCING);
                for (uint64_t i = 0; (syncing[k] & 2) && i < nodes; i++)
                    wr64((uint8_t *)node_at(&n, i) + NODE_PAYLOAD_STATUS, statuses[i]);
                /* the bytes of the operations the pool took stay */
                if (!why && s->nbufs != nbufs + (node_pool_held(s->node) - held))
                    why = "the runner holds other buffers after the answer";
                if (!why && streams[k]) { /* an event stream: its head with last 0, no close; then the client goes */
                    if (s->api.len != wlen || memcmp(s->api.b, want, (size_t)wlen) || s->api.lasts || s->api.closes || s->api.late)
                        why = api_mismatch(s, rname, want, wlen);
                    else {
                        shell_event(s, EV_API_CLOSED, s->api.conn, NULL, 0);
                        s->api.gone = 1;
                        shell_settle(&n, &why);
                    }
                    if (!why && (s->api.len != wlen || s->api.closes)) why = "an event stream: an action after its connection closed";
                    if (!why) why = api_clean(s);
                    continue;
                }
                uint64_t glen = 0;
                uint8_t *got = why ? NULL : api_normalize(s, &glen, &why);
                if (why && got) { /* a broken framing: the bytes as they came */
                    static char msg[1024];
                    snprintf(msg, sizeof msg, "%s, room %llu, sends %llu, lasts %llu, closes %llu, %llu bytes: %.*s", why,
                             (unsigned long long)rooms[r], (unsigned long long)s->api.sends, (unsigned long long)s->api.lasts,
                             (unsigned long long)s->api.closes, (unsigned long long)s->api.len, (int)(s->api.len < 500 ? s->api.len : 500),
                             (const char *)s->api.b);
                    why = msg;
                }
                if (!why && (glen != wlen || memcmp(got, want, (size_t)wlen))) {
                    free(s->api.b);
                    s->api.b = got;
                    s->api.len = s->api.cap = glen;
                    got = NULL;
                    why = api_mismatch(s, rname, want, wlen);
                } else if (!why && (s->api.lasts != 1 || s->api.late || s->api.closes != closes[k]))
                    why = api_mismatch(s, rname, want, wlen);
                if (!why) why = api_clean(s);
                free(got);
            }
            s->api.room = 0;
            if (why && strncmp(why, rname, strlen(rname))) {
                static char msg[256];
                snprintf(msg, sizeof msg, "%s: %s", rname, why);
                why = msg;
            }
        }
        if (!why && open_want) { /* the open stream: its head and the events of the requests after it */
            if (s->ev[0].len != open_wlen || memcmp(s->ev[0].b, open_want, (size_t)open_wlen) || s->ev[0].lasts ||
                s->ev[0].closes || s->ev[0].late) {
                static char msg[1024];
                uint64_t at = 0;
                while (at < s->ev[0].len && at < open_wlen && s->ev[0].b[at] == open_want[at]) at++;
                snprintf(msg, sizeof msg, "the open event stream differs at byte %llu of %llu (case %llu), lasts %llu, closes %llu: got %.*s",
                         (unsigned long long)at, (unsigned long long)s->ev[0].len, (unsigned long long)open_wlen,
                         (unsigned long long)s->ev[0].lasts, (unsigned long long)s->ev[0].closes,
                         (int)(s->ev[0].len - at < 400 ? s->ev[0].len - at : 400), (const char *)s->ev[0].b + at);
                why = msg;
            } else {
                shell_event(s, EV_API_CLOSED, s->ev[0].conn, NULL, 0);
                s->ev[0].gone = 1;
                shell_settle(&n, &why);
                if (!why) why = api_clean(s);
            }
        }
        if (!why) { /* getStateV2 of head as SSZ in small chunks, the connection closed after the first */
            static const char sreq[] = "GET /eth/v2/debug/beacon/states/head HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n";
            s->api.room = 2048;
            s->api.cut = 1;
            shell_api_ask(&n, (const uint8_t *)sreq, sizeof sreq - 1, 9 | (uint64_t)9 << 32, &why);
            if (!why && (s->api.sends != 1 || s->api.lasts || s->api.closes || s->api.late)) why = "cut: actions after the connection closed";
            if (!why) why = api_clean(s);
            s->api.room = 0;
            s->api.cut = 0;
        }
        shell_close(&n, anchor_block);
        report(file, name, len, why == NULL, why);
    }
}

/* The bytes of the attestations of a SignedBeaconBlock's body: its message at the offset at byte 0,
 * the body at the offset at byte 80 of it, the list from the offset at byte 208 of the body to the
 * offset at 212. 0 for offsets that break those rules. */
static int body_attestations(const uint8_t *b, uint64_t n, uint64_t *at, uint64_t *len) {
    if (n < 4) return 0;
    uint64_t m = (uint64_t)b[0] | (uint64_t)b[1] << 8 | (uint64_t)b[2] << 16 | (uint64_t)b[3] << 24;
    if (m + 84 > n) return 0;
    const uint8_t *p = b + m + 80;
    uint64_t body = m + ((uint64_t)p[0] | (uint64_t)p[1] << 8 | (uint64_t)p[2] << 16 | (uint64_t)p[3] << 24);
    if (body + 216 > n) return 0;
    p = b + body + 208;
    uint64_t a = (uint64_t)p[0] | (uint64_t)p[1] << 8 | (uint64_t)p[2] << 16 | (uint64_t)p[3] << 24;
    uint64_t d = (uint64_t)p[4] | (uint64_t)p[5] << 8 | (uint64_t)p[6] << 16 | (uint64_t)p[7] << 24;
    if (a > d || body + d > n) return 0;
    *at = body + a;
    *len = d - a;
    return 1;
}

/*
 * Node mode, after the steps (docs/reference/node.md, Test vectors): getBlockV2 of head as SSZ, the
 * bytes of a block whose root is the head's, and as JSON, a data that lantern_json_decode gives as
 * those bytes; getStateV2 of head as SSZ, lantern_node_state_bytes of the head's post-state st, and
 * as JSON the same way; getBlockAttestationsV2 of head, a data that lantern_json_decode of the
 * fork's Attestations gives as the bytes of the block body's attestations; getBlindedBlock of head
 * as SSZ, a SignedBlindedBeaconBlock (a SignedBeaconBlock before bellatrix) whose message has the
 * head's root and whose signature is the block's, and as JSON a data that lantern_json_decode
 * gives as those bytes; each in NODE_API_CHUNK and in chunks of 2048 bytes. A head that is the
 * anchor has no block bytes: 404.
 */
#if FORK >= FORK_BELLATRIX
#define BLINDED_TYPE "SignedBlindedBeaconBlock"
#define BLINDED_MESSAGE "BlindedBeaconBlock"
#else
#define BLINDED_TYPE "SignedBeaconBlock"
#define BLINDED_MESSAGE "BeaconBlock"
#endif
static unsigned long api_heads_streamed; /* the heads whose block and state went as streams */
static unsigned long api_fork_choice_200, api_fork_choice_500; /* getDebugForkChoice answers checked, of each status */
static void api_streams_head(fc_node *n, const uint8_t *st, const char **why) {
    static const char *const reqs[7] = {
        "GET /eth/v2/beacon/blocks/head HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n",
        "GET /eth/v2/beacon/blocks/head HTTP/1.1\r\nHost: lantern\r\n\r\n",
        "GET /eth/v2/debug/beacon/states/head HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n",
        "GET /eth/v2/debug/beacon/states/head HTTP/1.1\r\nHost: lantern\r\n\r\n",
        "GET /eth/v2/beacon/blocks/head/attestations HTTP/1.1\r\nHost: lantern\r\n\r\n",
        "GET /eth/v1/beacon/blinded_blocks/head HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n",
        "GET /eth/v1/beacon/blinded_blocks/head HTTP/1.1\r\nHost: lantern\r\n\r\n"};
    static const char *const types[7] = {"SignedBeaconBlock", "SignedBeaconBlock", "BeaconState", "BeaconState", "Attestations",
                                          BLINDED_TYPE, BLINDED_TYPE};
    struct node_shell *s = n->shell;
    const uint8_t *head = s->node + NODE_HEAD_ROOT;
    int anchor = !memcmp(head, s->anchor, 32);
    uint64_t need = 0, got = 0, blen = 0;
    uint8_t small[24] = {0}, *sb = NULL, *block = NULL, *blinded = NULL;
    uint64_t bnlen = 0;
    wr64(small, 24);
    if (CALL(LF(node_state_bytes), st, fresh_scratch(), small, &need) != 1 || need <= 24) {
        *why = "lantern_node_state_bytes: no size";
        return;
    }
    sb = buffer(need);
    wr64(sb, need);
    if (CALL(LF(node_state_bytes), st, fresh_scratch(), sb, &got) != 0) *why = "lantern_node_state_bytes: status";
    char version[64];
    snprintf(version, sizeof version, "\r\nEth-Consensus-Version: %s\r\n", STR(FORK_NAME));
    for (int q = 0; q < 7 && !*why; q++)
        for (int r = 0; r < 2 && !*why; r++) {
            static char msg[160];
            uint64_t small = (need - 24) / 128 > 2048 ? ((need - 24) / 128) & ~(uint64_t)7 : 2048; /* some hundreds of chunks */
            s->api.room = r ? small : 0;
            shell_api_ask(n, (const uint8_t *)reqs[q], strlen(reqs[q]), (uint64_t)(3 + 2 * q + r), why);
            uint64_t glen = 0;
            uint8_t *g = *why ? NULL : api_normalize(s, &glen, why);
            const char *gb = (const char *)g, *end = g ? find_bytes(gb, glen, "\r\n\r\n") : NULL;
            if (*why) break;
            if ((q < 2 || q >= 4) && anchor) {
                if (glen < 13 || memcmp(g, "HTTP/1.1 404 ", 13)) *why = "API getBlockV2 of an anchor head is not 404";
            } else if (!end || glen < 17 || memcmp(g, "HTTP/1.1 200 OK\r\n", 17) || !find_bytes(gb, (uint64_t)(end - gb) + 2, version) ||
                       s->api.lasts != 1 || s->api.late) {
                snprintf(msg, sizeof msg, "API %s of head: not a 200 answer with Eth-Consensus-Version %s",
                         q < 2 ? "getBlockV2" : q < 4 ? "getStateV2" : q == 4 ? "getBlockAttestationsV2" : "getBlindedBlock", STR(FORK_NAME));
                *why = msg;
            } else {
                const uint8_t *body = (const uint8_t *)end + 4;
                uint64_t len = glen - (uint64_t)(body - g);
                if (q == 0) { /* the block's bytes: their message's root is the head */
                    uint64_t vsize = 0;
                    uint8_t root[32];
                    uint8_t *v = len > 100 ? decode(type_by_name("BeaconBlock"), body + 100, len - 100, &vsize, why) : NULL;
                    if (!v) *why = "API getBlockV2 of head as SSZ: not a block";
                    else root_of("BeaconBlock", v, root, why);
                    if (!*why && memcmp(root, head, 32)) *why = "API getBlockV2 of head as SSZ: a block of another root";
                    free(v);
                    if (!*why && r == 0) {
                        block = copy_of(body, len);
                        blen = len;
                    }
                } else if (q == 2) {
                    if (len != need - 24 || memcmp(body, sb + 24, (size_t)len)) *why = "API getStateV2 of head as SSZ: not the state's bytes";
                } else if (q == 5) { /* the blinded block's bytes: their message's root is the head, their signature the block's */
                    uint64_t vsize = 0;
                    uint8_t root[32];
                    uint8_t *v = len > 100 ? decode(type_by_name(BLINDED_MESSAGE), body + 100, len - 100, &vsize, why) : NULL;
                    if (!v) *why = "API getBlindedBlock of head as SSZ: not a blinded block";
                    else root_of(BLINDED_MESSAGE, v, root, why);
                    if (!*why && memcmp(root, head, 32)) *why = "API getBlindedBlock of head as SSZ: another root than the head's";
                    if (!*why && (!block || blen < 100 || memcmp(body + 4, block + 4, 96)))
                        *why = "API getBlindedBlock of head as SSZ: another signature than the block's";
                    free(v);
                    if (!*why && r == 0) {
                        blinded = copy_of(body, len);
                        bnlen = len;
                    }
                } else { /* JSON: the data decodes as the SSZ answer */
                    char pre[64];
                    int pl = snprintf(pre, sizeof pre, "{\"version\":\"%s\",\"execution_optimistic\":", STR(FORK_NAME));
                    const char *d = len > (uint64_t)pl ? find_bytes((const char *)body, len, ",\"data\":") : NULL;
                    const uint8_t *ssz = q == 1 ? block : q == 6 ? blinded : sb + 24;
                    uint64_t slen = q == 1 ? blen : q == 6 ? bnlen : need - 24, aat = 0;
                    if (q == 4 && (!block || !body_attestations(block, blen, &aat, &slen))) ssz = NULL; /* the body's attestations */
                    else if (q == 4) ssz = block + aat;
                    if (!d || memcmp(body, pre, (size_t)pl) || body[len - 1] != '}' || !ssz) {
                        *why = "API JSON of head: not {version, execution_optimistic, finalized, data}";
                    } else {
                        uint64_t at = (uint64_t)(d - (const char *)body) + 8, lsize, osize = 24 + slen + 64;
                        uint8_t *l = list_of(body + at, len - at - 1, 0, 8, &lsize), *scr = buffer(JSON_DECODE_SCRATCH);
                        uint8_t *out = buffer(osize), *fault = buffer(JSON_FAULT_BYTES);
                        wr64(scr, JSON_DECODE_SCRATCH);
                        wr64(out, osize);
                        uint64_t js = CALL(lantern_json_decode, type_by_name(types[q]), l, scr, out, fault);
                        if (js != 0 || rd64(out + 16) != slen || memcmp(out + 24, ssz, (size_t)slen)) {
                            snprintf(msg, sizeof msg, "API JSON of head %s: lantern_json_decode status %llu, fault at %llu", types[q],
                                     (unsigned long long)js, (unsigned long long)rd64(fault + 8));
                            *why = msg;
                        }
                        free(l);
                        free(scr);
                        free(out);
                        free(fault);
                    }
                }
            }
            if (!*why) *why = api_clean(s);
            free(g);
        }
    s->api.room = 0;
    if (!*why) api_heads_streamed++;
    free(sb);
    free(block);
    free(blinded);
}

/*
 * Node mode, after the steps: getDebugChainHeadsV2 must answer the leaves of the node's store (beacon-api.md):
 * each BlockNode, in order, that no node not out has as parent, where a node is out when its payload_status is
 * PAYLOAD_STATUS_INVALIDATED (1) or its parent is out.
 */
static void api_heads_check(fc_node *n, const char **why) {
    struct node_shell *s = n->shell;
    static const char req[] = "GET /eth/v2/debug/beacon/heads HTTP/1.1\r\nHost: lantern\r\n\r\n";
    const uint8_t *st = n->store;
    uint64_t off = rd64(st + STORE_BLOCKS), cnt = rd64(st + STORE_BLOCKS + 8), k = 0, cap = 64 + 128 * cnt;
    uint8_t *out = calloc(cnt + 1, 1), *child = calloc(cnt + 1, 1);
    char *want = malloc(cap);
    for (uint64_t i = 0; i < cnt; i++) {
        const uint8_t *b = st + off + i * NODE_BYTES;
        uint64_t p = rd64(b + 80);
        out[i] = rd64(b + 208) == 1 || (p < cnt && out[p]);
        if (!out[i] && p < cnt) child[p] = 1;
    }
    k += (uint64_t)snprintf(want + k, cap - k, "{\"data\":[");
    for (uint64_t i = 0, first = 1; i < cnt; i++) {
        const uint8_t *b = st + off + i * NODE_BYTES;
        if (out[i] || child[i]) continue;
        k += (uint64_t)snprintf(want + k, cap - k, "%s{\"root\":\"0x", first ? "" : ",");
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", b[j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\",\"slot\":\"%llu\",\"execution_optimistic\":%s}", (unsigned long long)rd64(b + 64),
                                rd64(b + 208) == 2 ? "true" : "false");
        first = 0;
    }
    k += (uint64_t)snprintf(want + k, cap - k, "]}");
    shell_api_ask(n, (const uint8_t *)req, sizeof req - 1, 13, why);
    if (!*why && (s->api.len < 17 + k || memcmp(s->api.b, "HTTP/1.1 200 OK\r\n", 17) ||
                  memcmp(s->api.b + s->api.len - k, want, (size_t)k)))
        *why = api_mismatch(s, "API getDebugChainHeadsV2", (const uint8_t *)want, k);
    free(out);
    free(child);
    free(want);
}

/*
 * Node mode, after the steps: getDebugForkChoice must answer the store's justified and finalized checkpoints and
 * each BlockNode in order (beacon-api.md), each weight lantern_get_weight of its node; the error 500 when
 * lantern_get_weight of a node fails.
 */
static void api_fork_choice_check(fc_node *n, const char **why) {
    struct node_shell *s = n->shell;
    static const char req[] = "GET /eth/v1/debug/fork_choice HTTP/1.1\r\nHost: lantern\r\n\r\n";
    static const char *const validity[3] = {"valid", "invalid", "optimistic"}; /* of PAYLOAD_STATUS_* */
    const uint8_t *st = n->store;
    uint64_t off = rd64(st + STORE_BLOCKS), cnt = rd64(st + STORE_BLOCKS + 8), k = 0, cap = 256 + 640 * cnt, fail = 0;
    char *want = malloc(cap);
    for (int c = 0; c < 2; c++) {
        const uint8_t *cp = st + (c ? STORE_FINALIZED : STORE_JUSTIFIED);
        k += (uint64_t)snprintf(want + k, cap - k, "%s\"%s_checkpoint\":{\"epoch\":\"%llu\",\"root\":\"0x", c ? "," : "{",
                                c ? "finalized" : "justified", (unsigned long long)rd64(cp));
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", cp[8 + j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\"}");
    }
    k += (uint64_t)snprintf(want + k, cap - k, ",\"fork_choice_nodes\":[");
    for (uint64_t i = 0; i < cnt; i++) {
        const uint8_t *b = st + off + i * NODE_BYTES;
        uint64_t node = i, weight = 0, ps = rd64(b + NODE_PAYLOAD_STATUS);
        if (CALL(LF(get_weight), st, &node, &weight) != 0) fail = 1;
        k += (uint64_t)snprintf(want + k, cap - k, "%s{\"slot\":\"%llu\",\"block_root\":\"0x", i ? "," : "",
                                (unsigned long long)rd64(b + NODE_SLOT));
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", b[j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\",\"parent_root\":\"0x");
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", b[32 + j]);
        k += (uint64_t)snprintf(want + k, cap - k,
                                "\",\"justified_epoch\":\"%llu\",\"finalized_epoch\":\"%llu\",\"weight\":\"%llu\",\"validity\":\"%s\","
                                "\"execution_block_hash\":\"0x",
                                (unsigned long long)rd64(b + 88), (unsigned long long)rd64(b + NODE_FINALIZED_EPOCH),
                                (unsigned long long)weight, ps < 3 ? validity[ps] : "?");
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", b[NODE_BLOCK_HASH + j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\"}");
    }
    k += (uint64_t)snprintf(want + k, cap - k, "]}");
    shell_api_ask(n, (const uint8_t *)req, sizeof req - 1, 31, why);
    if (!*why && fail && (s->api.len < 13 || memcmp(s->api.b, "HTTP/1.1 500 ", 13)))
        *why = "API getDebugForkChoice: not the error 500 when lantern_get_weight fails";
    else if (!*why && !fail && (s->api.len < 17 + k || memcmp(s->api.b, "HTTP/1.1 200 OK\r\n", 17) ||
                                memcmp(s->api.b + s->api.len - k, want, (size_t)k)))
        *why = api_mismatch(s, "API getDebugForkChoice", (const uint8_t *)want, k);
    if (!*why) {
        if (fail) api_fork_choice_500++;
        else api_fork_choice_200++;
    }
    free(want);
}

/*
 * Node mode, after the steps: getBlockHeader of head must give 200 with the node's head_root as
 * root and its block's slot; getStateFinalityCheckpoints of head the checkpoints of the head's
 * post-state (docs/reference/node.md, Test vectors).
 */
static void shell_api_head(fc_node *n, const char **why) {
    struct node_shell *s = n->shell;
    static const char hreq[] = "GET /eth/v1/beacon/headers/head HTTP/1.1\r\nHost: lantern\r\n\r\n";
    static const char freq[] = "GET /eth/v1/beacon/states/head/finality_checkpoints HTTP/1.1\r\nHost: lantern\r\n\r\n";
    const uint8_t *head = s->node + NODE_HEAD_ROOT, *e = shell_block(s, head), *st = shell_state_of(n, head);
    char want[512];
    int k = 0;
    if (!e || !st) {
        *why = "API: the head has no block or no post-state";
        return;
    }
    k = snprintf(want, sizeof want, "\"data\":{\"root\":\"0x");
    for (int b = 0; b < 32; b++) k += snprintf(want + k, sizeof want - (size_t)k, "%02x", head[b]);
    snprintf(want + k, sizeof want - (size_t)k, "\",\"canonical\":true,\"header\":{\"message\":{\"slot\":\"%llu\"",
             (unsigned long long)rd64(e + 64)); /* NodeBlock_slot */
    shell_api_ask(n, (const uint8_t *)hreq, sizeof hreq - 1, 1, why);
    if (!*why && (s->api.len < 17 || memcmp(s->api.b, "HTTP/1.1 200 OK\r\n", 17) || !find_bytes((const char *)s->api.b, s->api.len, want)))
        *why = api_mismatch(s, "API getBlockHeader of head", (const uint8_t *)want, strlen(want));
    if (*why) return;
    uint8_t cps[120];
    if (CALL(LF(node_state_checkpoints), st, cps) != 0) {
        *why = "lantern_node_state_checkpoints: status not 0";
        return;
    }
    static const char *names[3] = {"previous_justified", "current_justified", "finalized"};
    k = snprintf(want, sizeof want, "\"data\":{");
    for (int c = 0; c < 3; c++) {
        k += snprintf(want + k, sizeof want - (size_t)k, "%s\"%s\":{\"epoch\":\"%llu\",\"root\":\"0x", c ? "," : "", names[c],
                      (unsigned long long)rd64(cps + 40 * c));
        for (int b = 0; b < 32; b++) k += snprintf(want + k, sizeof want - (size_t)k, "%02x", cps[40 * c + 8 + b]);
        k += snprintf(want + k, sizeof want - (size_t)k, "\"}");
    }
    shell_api_ask(n, (const uint8_t *)freq, sizeof freq - 1, 2, why);
    if (!*why && (s->api.len < 17 || memcmp(s->api.b, "HTTP/1.1 200 OK\r\n", 17) || !find_bytes((const char *)s->api.b, s->api.len, want)))
        *why = api_mismatch(s, "API getStateFinalityCheckpoints of head", (const uint8_t *)want, strlen(want));
    if (!*why) api_heads_check(n, why);
    if (!*why) api_fork_choice_check(n, why);
    if (!*why) api_streams_head(n, st, why);
}

/* The root of a JSON answer's "root":"0x…" into out; 0 when it has none. */
static int api_root_of(const struct node_shell *s, uint8_t *out) {
    return s->api.len > 17 && !memcmp(s->api.b, "HTTP/1.1 200 OK\r\n", 17) &&
           find_hash((const char *)s->api.b, s->api.len, "\"root\":\"0x", out);
}

/* A block of a case for getBlockHeaders: its roots, slot and bytes, the node's NodeBlock of it or NULL, and 1 on the chain. */
typedef struct {
    uint8_t root[32], parent[32], body_root[32];
    uint64_t slot, len;
    const uint8_t *bytes, *entry;
    int on;
} hd_block;
static unsigned long api_headers_asked, api_headers_db; /* the getBlockHeaders answers checked; of them, with a Db block */

/*
 * One getBlockHeaders request of the query (has_slot, slot, proot), its answer from the case's blocks: first the
 * chain's block of the query the node no longer holds (with NODE_FLAG_DB, in its Db), then each block of the query
 * the node holds imported, in the order of its NodeBlock entries; each item's header from the block's bytes.
 */
static void api_headers_query(fc_node *n, const hd_block *hb, size_t nh, const char *req, int has_slot, uint64_t slot,
                              const uint8_t *proot, uint64_t f_slot, uint64_t conn, const char **why) {
    struct node_shell *s = n->shell;
    static char msg[512];
    int db = (rd64(s->node + NODE_FLAGS) & NODE_FLAG_DB) != 0, opt = 0, fin;
    const hd_block *items[128];
    size_t ni = 0, held;
    for (size_t k = 0; k < nh; k++)
        if (db && hb[k].on && !hb[k].entry && (!has_slot || hb[k].slot == slot) && (!proot || !memcmp(hb[k].parent, proot, 32)) &&
            ni < 128)
            items[ni++] = &hb[k];
    held = ni;
    for (size_t k = 0; k < nh; k++)
        if (hb[k].entry && rd64(hb[k].entry + NB_STATUS) == NB_IMPORTED && (!has_slot || hb[k].slot == slot) &&
            (!proot || !memcmp(hb[k].parent, proot, 32)) && ni < 128)
            items[ni++] = &hb[k];
    for (size_t a = held + 1; a < ni; a++) /* in the order of the node's entries */
        for (size_t b = a; b > held && items[b - 1]->entry > items[b]->entry; b--) {
            const hd_block *t = items[b];
            items[b] = items[b - 1];
            items[b - 1] = t;
        }
    fin = ni > 0;
    for (size_t k = 0; k < ni; k++) {
        if (items[k]->entry && rd64(items[k]->entry + 120) == PAYLOAD_NOT_VALIDATED) opt = 1; /* NodeBlock_payload_status */
        if (!items[k]->on || items[k]->slot > f_slot) fin = 0;
    }
    uint64_t cap = 256 + 800 * ni, k = 0;
    char *want = malloc(cap);
    k += (uint64_t)snprintf(want + k, cap - k, "{\"execution_optimistic\":%s,\"finalized\":%s,\"data\":[", opt ? "true" : "false",
                            fin ? "true" : "false");
    for (size_t i = 0; i < ni; i++) {
        const uint8_t *b = items[i]->bytes, *m = b + ((uint64_t)b[0] | (uint64_t)b[1] << 8 | (uint64_t)b[2] << 16 | (uint64_t)b[3] << 24);
        k += (uint64_t)snprintf(want + k, cap - k, "%s{\"root\":\"0x", i ? "," : "");
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", items[i]->root[j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\",\"canonical\":%s,\"header\":{\"message\":{\"slot\":\"%llu\",\"proposer_index\":\"%llu\",\"parent_root\":\"0x",
                                items[i]->on ? "true" : "false", (unsigned long long)rd64(m), (unsigned long long)rd64(m + 8));
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", m[16 + j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\",\"state_root\":\"0x");
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", m[48 + j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\",\"body_root\":\"0x");
        for (int j = 0; j < 32; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", items[i]->body_root[j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\"},\"signature\":\"0x");
        for (int j = 0; j < 96; j++) k += (uint64_t)snprintf(want + k, cap - k, "%02x", b[4 + j]);
        k += (uint64_t)snprintf(want + k, cap - k, "\"}}");
    }
    k += (uint64_t)snprintf(want + k, cap - k, "]}");
    shell_api_ask(n, (const uint8_t *)req, strlen(req), conn, why);
    uint64_t glen = 0;
    uint8_t *g = *why ? NULL : api_normalize(s, &glen, why);
    const char *gb = (const char *)g, *end = g ? find_bytes(gb, glen, "\r\n\r\n") : NULL;
    if (!*why && (!end || glen < 17 || memcmp(g, "HTTP/1.1 200 OK\r\n", 17) || glen - (uint64_t)(end + 4 - gb) != k ||
                  memcmp(end + 4, want, (size_t)k) || s->api.lasts != 1 || s->api.late)) {
        uint64_t at = 0, blen = end ? glen - (uint64_t)(end + 4 - gb) : 0;
        while (at < blen && at < k && end[4 + at] == want[at]) at++;
        snprintf(msg, sizeof msg, "API getBlockHeaders %.60s: the body differs at byte %llu of %llu (case %llu): %.200s", req + 4,
                 (unsigned long long)at, (unsigned long long)blen, (unsigned long long)k, end ? end + 4 + (at > 40 ? at - 40 : 0) : gb);
        *why = msg;
    }
    if (!*why) *why = api_clean(s);
    if (!*why) {
        api_headers_asked++;
        if (held) api_headers_db++;
    }
    free(g);
    free(want);
}

/* The base58btc text of the n bytes at in, into out with a 0 after it; returns its length. */
static size_t base58_text(const uint8_t *in, size_t n, char *out) {
    static const char digits[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    uint8_t d[128] = {0}; /* the digits, least significant first */
    size_t len = 0, zeros = 0, k = 0;
    while (zeros < n && in[zeros] == 0) zeros++;
    for (size_t i = zeros; i < n; i++) {
        unsigned carry = in[i];
        for (size_t j = 0; j < len; j++) {
            carry += (unsigned)d[j] << 8;
            d[j] = (uint8_t)(carry % 58);
            carry /= 58;
        }
        while (carry) {
            d[len++] = (uint8_t)(carry % 58);
            carry /= 58;
        }
    }
    for (size_t i = 0; i < zeros; i++) out[k++] = '1';
    for (size_t i = len; i > 0; i--) out[k++] = digits[d[i - 1]];
    out[k] = 0;
    return k;
}

/*
 * getPeers and getPeer after a connection of the runner's network (beacon-api.md): the peer, connected, with its
 * ID in base58btc, its connection's address (outbound: the record's 10.0.0.2 and TCP 9000; inbound: the peer's
 * 10.0.0.1 and 40001) and its direction, under each filter; getPeer of its ID text, and of another (404).
 */
static unsigned long api_peers_checked[2]; /* the peers checks of inbound and outbound connections */
static void api_peers_check(fc_node *n, struct p2p_net *net, int outbound, const char **why) {
    static const struct { const char *query; int match; } qs[6] = {
        {"", 1}, {"?state=connected", 1}, {"?state=disconnected,connecting", 0}, {"?direction=inbound", 2}, {"?direction=outbound", 3},
        {"?state=connected&direction=inbound,outbound", 1}};
    struct node_shell *s = n->shell;
    char id[128], item[512], want[768], req[256];
    size_t idn = base58_text(net->state[1] + P2P_ST_PEER_ID, (size_t)rd64(net->state[1] + P2P_ST_PEER_ID_LEN), id);
    snprintf(item, sizeof item,
             "{\"peer_id\":\"%s\",\"enr\":null,\"last_seen_p2p_address\":\"/ip4/%s/tcp/%s/p2p/%s\",\"state\":\"connected\",\"direction\":\"%s\"}",
             id, outbound ? "10.0.0.2" : "10.0.0.1", outbound ? "9000" : "40001", id, outbound ? "outbound" : "inbound");
    for (size_t q = 0; q < 7 && !*why; q++) {
        int match = q == 6 || qs[q].match == 1 || (qs[q].match == 2 && !outbound) || (qs[q].match == 3 && outbound);
        if (q < 6) {
            snprintf(want, sizeof want, "{\"data\":[%s],\"meta\":{\"count\":%d}}", match ? item : "", match);
            snprintf(req, sizeof req, "GET /eth/v1/node/peers%s HTTP/1.1\r\nHost: lantern\r\n\r\n", qs[q].query);
        } else {
            snprintf(want, sizeof want, "{\"data\":%s}", item);
            snprintf(req, sizeof req, "GET /eth/v1/node/peers/%s HTTP/1.1\r\nHost: lantern\r\n\r\n", id);
        }
        shell_api_ask(n, (const uint8_t *)req, strlen(req), 300 + q, why);
        size_t k = strlen(want);
        if (!*why && (s->api.len < 17 + k || memcmp(s->api.b, "HTTP/1.1 200 OK\r\n", 17) || memcmp(s->api.b + s->api.len - k, want, k)))
            *why = api_mismatch(s, q < 6 ? "API getPeers" : "API getPeer", (const uint8_t *)want, k);
    }
    if (!*why && idn > 2) { /* another ID: its last digit changed */
        id[idn - 1] = id[idn - 1] == 'z' ? 'y' : 'z';
        snprintf(req, sizeof req, "GET /eth/v1/node/peers/%s HTTP/1.1\r\nHost: lantern\r\n\r\n", id);
        shell_api_ask(n, (const uint8_t *)req, strlen(req), 307, why);
        if (!*why && (s->api.len < 13 || memcmp(s->api.b, "HTTP/1.1 404 ", 13))) *why = "API getPeer of another peer ID: not 404";
    }
    if (!*why) *why = api_clean(s);
    if (!*why) api_peers_checked[outbound]++;
}

static int p2p_topic(struct p2p_net *net, int arg) { return net->topics >= arg; }
static int p2p_untopic(struct p2p_net *net, int arg) { return net->untopics >= arg; }

/* The subscription POST body to path, the node's answer to be 200 with no body. */
static void api_subscribe(fc_node *n, const char *path, const char *body, uint64_t conn, const char **why) {
    struct node_shell *s = n->shell;
    static const char ok[] = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n";
    char req[2048];
    snprintf(req, sizeof req, "POST %s HTTP/1.1\r\nHost: lantern\r\nContent-Type: application/json\r\nContent-Length: %zu\r\n\r\n%s",
             path, strlen(body), body);
    shell_api_ask(n, (const uint8_t *)req, strlen(req), conn, why);
    if (!*why && (s->api.len != sizeof ok - 1 || memcmp(s->api.b, ok, sizeof ok - 1)))
        *why = api_mismatch(s, path, (const uint8_t *)ok, sizeof ok - 1);
    if (!*why) *why = api_clean(s);
}

/*
 * The subscriptions (beacon-api.md, prepareBeaconCommitteeSubnet and prepareSyncCommitteeSubnets;
 * node.md, the subscriptions), with a peer: an aggregator's subscription for the next slot on a
 * subnet outside attnets makes the node join beacon_attestation of that subnet, one topic, and
 * leave it once the store's slot is past that slot. From altair, a sync subscription of index 0 to
 * the next epoch makes it join sync_committee_0, one topic, with seq_number one more, bit 0 of
 * syncnets in its MetaData and its record; at that epoch it leaves it, with seq_number one more.
 */
static void api_subscribe_check(fc_node *n, struct p2p_net *net, const char **why) {
    struct node_shell *s = n->shell;
    uint64_t slot = 0, genesis_ms = rd64(n->store + STORE_GENESIS_TIME_MS), slot_ms = rd64(config + 104);
    uint64_t attnets = rd64(s->node + 712), max = strcmp(PRESET, "minimal") ? 64u : 4u, c, at = 0; /* MAX_COMMITTEES_PER_SLOT */
    char body[256];
    if (CALL(LF(get_current_slot), n->store, &slot) != 0) {
        *why = "subscribe: get_current_slot status";
        return;
    }
    for (c = 0; c < max; c++) { /* compute_subnet_for_attestation of the next slot: one outside attnets */
        at = (max * ((slot + 1) % SLOTS_PER_EPOCH_RUNNER) + c) % 64;
        if (!(attnets >> at & 1)) break;
    }
    if (c == max) {
        *why = "subscribe: no subnet outside attnets";
        return;
    }
    snprintf(body, sizeof body,
             "[{\"validator_index\":\"0\",\"committee_index\":\"%llu\",\"committees_at_slot\":\"%llu\",\"slot\":\"%llu\",\"is_aggregator\":true}]",
             (unsigned long long)c, (unsigned long long)max, (unsigned long long)(slot + 1));
    int topics = net->topics, untopics = net->untopics;
    api_subscribe(n, "/eth/v1/validator/beacon_committee_subscriptions", body, 400, why);
    if (!*why) p2p_run(n, net, p2p_topic, topics + 1, why);
    if (!*why) p2p_settle(n, net, why);
    if (!*why && (net->topics != topics + 1 || net->untopics != untopics))
        *why = "subscribe: an aggregator's subscription: not one topic joined";
    if (!*why) {
        shell_event(s, EV_TICK, genesis_ms + (slot + 2) * slot_ms, NULL, 0);
        p2p_run(n, net, p2p_untopic, untopics + 1, why);
    }
    if (!*why) p2p_settle(n, net, why);
    if (!*why && (net->untopics != untopics + 1 || net->topics != topics + 1))
        *why = "subscribe: past the aggregator's slot: not one topic left";
#if FORK >= FORK_ALTAIR
    uint64_t epoch = (slot + 2) / SLOTS_PER_EPOCH_RUNNER, seq = rd64(s->node + 176); /* Node_metadata_seq */
    snprintf(body, sizeof body, "[{\"validator_index\":\"0\",\"sync_committee_indices\":[\"0\"],\"until_epoch\":\"%llu\"}]",
             (unsigned long long)(epoch + 1));
    topics = net->topics;
    untopics = net->untopics;
    if (!*why) api_subscribe(n, "/eth/v1/validator/sync_committee_subscriptions", body, 401, why);
    if (!*why) p2p_run(n, net, p2p_topic, topics + 1, why);
    if (!*why) p2p_settle(n, net, why);
    if (!*why && (net->topics != topics + 1 || net->untopics != untopics))
        *why = "subscribe: a sync subscription: not one topic joined";
    if (!*why && rd64(s->node + 176) != seq + 1) *why = "subscribe: a sync subscription: seq_number not one more";
    static const uint8_t one[1] = {1}, none[1] = {0};
    if (!*why && !shell_entry(s, "syncnets", one, 1)) *why = "subscribe: a sync subscription: the record's syncnets";
    if (!*why) { /* MetaData v2: seq_number, attnets, syncnets with bit 0 */
        uint8_t md[17] = {0};
        wr64(md, seq + 1);
        wr64(md + 8, rd64(s->node + 712));
        md[16] = 1;
        int k = p2p_request(n, net, 4, "metadata", 2, NULL, 0, why);
        if (!*why) p2p_check_response(net, k, md, sizeof md, "metadata of a sync subscription", why);
    }
    if (!*why) {
        shell_event(s, EV_TICK, genesis_ms + (epoch + 1) * SLOTS_PER_EPOCH_RUNNER * slot_ms, NULL, 0);
        p2p_run(n, net, p2p_untopic, untopics + 1, why);
    }
    if (!*why) p2p_settle(n, net, why);
    if (!*why && (net->untopics != untopics + 1 || net->topics != topics + 1))
        *why = "subscribe: at the sync subscription's epoch: not one topic left";
    if (!*why && rd64(s->node + 176) != seq + 2) *why = "subscribe: at the sync subscription's epoch: seq_number not one more";
    if (!*why && !shell_entry(s, "syncnets", none, 1)) *why = "subscribe: at the sync subscription's epoch: the record's syncnets";
#endif
}

/*
 * Validator custody (fulu validator.md; node.md, validator custody), with a peer: prepareBeaconProposer of
 * the validators 0 to 9 of the anchor state (the store's finalized state), then the next epoch: custody_count
 * get_validators_custody_requirement of their effective balances, columns those of max(SAMPLES_PER_SLOT, it)
 * groups of get_custody_groups of the node ID, one SUBSCRIBE of each new subnet, seq_number one more,
 * MetaData v3 and the record's cgc of it, and Status v2 the case's with earliest_available_slot the slot of
 * the preparation (the node checks at once). Three epochs on, with the preparations ended, custody_count stays.
 */
#if FORK >= FORK_FULU
static unsigned long custody_raises; /* the raises the custody checks saw */
static void custody_check(fc_node *n, struct p2p_net *net, const uint8_t *status, uint64_t slen, const char **why) {
    struct node_shell *s = n->shell;
    uint64_t genesis_ms = rd64(n->store + STORE_GENESIS_TIME_MS), slot_ms = rd64(config + 104), slot = 0;
    if (CALL(LF(get_current_slot), n->store, &slot) != 0) {
        *why = "custody: get_current_slot status";
        return;
    }
    uint64_t epoch = slot / SLOTS_PER_EPOCH_RUNNER, ref = field_offset("BeaconState", 11);
    const uint8_t *st = n->anchor, *vals = st + rd64(st + ref);
    uint64_t nvals = rd64(st + ref + 8), total = 0, groups_n = rd64(config + 280), samples = rd64(config + 272);
    for (uint64_t i = 0; i < 10 && i < nvals; i++) total += rd64(vals + 128 * i + 80); /* Validator effective_balance */
    uint64_t need = rd64(config + 368) ? total / rd64(config + 368) : groups_n;
    if (need < rd64(config + 360)) need = rd64(config + 360); /* VALIDATOR_CUSTODY_REQUIREMENT */
    if (need > groups_n) need = groups_n;
    uint64_t cur = rd64(s->node + NODE_ARCHIVE + 56), want = need > cur ? need : cur, count = want > samples ? want : samples;
    uint8_t before[16], cols[16] = {0}, *gout = buffer(24 + 8 * count);
    memcpy(before, s->node + 440, 16); /* Node_columns */
    wr64(gout, 24 + 8 * count);
    if (CALL(LF(get_custody_groups), s->node + 680, &count, config, gout) != 0) *why = "custody: get_custody_groups status"; /* Node_node_id */
    for (uint64_t g = 0; g < count && !*why; g++) {
        uint8_t *cout = buffer(24 + 8 * 128);
        wr64(cout, 24 + 8 * 128);
        if (CALL(LF(compute_columns_for_custody_group), gout + 24 + 8 * g, config, cout) != 0) *why = "custody: compute_columns_for_custody_group status";
        for (uint64_t c = 0; c < rd64(cout + 16) && !*why; c++) {
            uint64_t col = rd64(cout + rd64(cout + 8) + 8 * c);
            if (col < 128) cols[col / 8] |= (uint8_t)(1u << (col % 8));
        }
        free(cout);
    }
    free(gout);
    uint64_t subnets = rd64(config + 296), k = 0;
    for (uint64_t sn = 0; sn < subnets && sn < 128 && !*why; sn++) { /* the subnets of the new columns that the old had not */
        int had = 0, has = 0;
        for (uint64_t c = sn; c < 128; c += subnets) {
            had |= before[c / 8] >> (c % 8) & 1;
            has |= cols[c / 8] >> (c % 8) & 1;
        }
        k += has && !had;
    }
    char body[1024];
    int w = snprintf(body, sizeof body, "[");
    for (int i = 0; i < 10; i++)
        w += snprintf(body + w, sizeof body - (size_t)w, "%s{\"validator_index\":\"%d\",\"fee_recipient\":\"0x%040d\"}", i ? "," : "", i, i);
    snprintf(body + w, sizeof body - (size_t)w, "]");
    uint64_t seq = rd64(s->node + 176), topics = (uint64_t)net->topics, untopics = (uint64_t)net->untopics;
    if (!*why) api_subscribe(n, "/eth/v1/validator/prepare_beacon_proposer", body, 402, why);
    if (!*why) {
        shell_event(s, EV_TICK, genesis_ms + (epoch + 1) * SLOTS_PER_EPOCH_RUNNER * slot_ms, NULL, 0);
        if (k) p2p_run(n, net, p2p_topic, (int)(topics + k), why);
    }
    if (!*why) p2p_settle(n, net, why);
    static char msg[160];
    if (!*why && rd64(s->node + NODE_ARCHIVE + 56) != want) {
        snprintf(msg, sizeof msg, "custody: custody_count %llu, not %llu", (unsigned long long)rd64(s->node + NODE_ARCHIVE + 56), (unsigned long long)want);
        *why = msg;
    }
    if (!*why && memcmp(s->node + 440, cols, 16)) *why = "custody: the node's columns are not those of get_custody_groups";
    if (!*why && ((uint64_t)net->topics != topics + k || (uint64_t)net->untopics != untopics)) {
        snprintf(msg, sizeof msg, "custody: %d topics joined, not %llu", net->topics - (int)topics, (unsigned long long)k);
        *why = msg;
    }
    if (!*why && want > cur) {
        custody_raises++;
        uint8_t cgc[8], md[25] = {0}, *sv = copy_of(status, slen);
        uint64_t nb = 0;
        for (uint64_t t = want; t; t >>= 8) nb++;
        for (uint64_t b = 0; b < nb; b++) cgc[b] = (uint8_t)(want >> (8 * (nb - 1 - b)));
        if (rd64(s->node + 176) != seq + 1) *why = "custody: seq_number not one more";
        else if (!shell_entry(s, "cgc", cgc, nb)) *why = "custody: the record's cgc";
        if (!*why) { /* MetaData v3: seq_number, attnets, syncnets, custody_group_count */
            wr64(md, seq + 1);
            wr64(md + 8, rd64(s->node + 712));
            wr64(md + 17, want);
            if (!net->status_len && slen <= sizeof net->status) { /* the peer answers the node's own requests first */
                memcpy(net->status, status, (size_t)slen);
                net->status_len = slen;
            }
            p2p_serve(net, why);
            if (!*why) p2p_settle(n, net, why);
            net->st[4].len = 0; /* a fresh stream in the slot */
            net->st[4].opened = net->st[4].eof = net->st[4].reset = net->st[4].failed = 0;
            int q = p2p_request(n, net, 4, "metadata", 3, NULL, 0, why);
            if (!*why) p2p_check_response(net, q, md, sizeof md, "custody: metadata", why);
        }
        if (!*why && slen >= 92) { /* Status v2: earliest_available_slot the raise's slot */
            wr64(sv + slen - 8, slot); /* the store's slot of the preparation: the node checks at once */
            net->st[0].len = 0;
            net->st[0].opened = net->st[0].eof = net->st[0].reset = net->st[0].failed = 0;
            int q = p2p_request(n, net, 0, "status", 2, status, slen, why);
            if (!*why) p2p_check_response(net, q, sv, slen, "custody: status", why);
        }
        free(sv);
    }
    if (!*why) { /* the preparations end: no change */
        shell_event(s, EV_TICK, genesis_ms + (epoch + 4) * SLOTS_PER_EPOCH_RUNNER * slot_ms, NULL, 0);
        p2p_settle(n, net, why);
    }
    if (!*why && rd64(s->node + NODE_ARCHIVE + 56) != want) *why = "custody: custody_count fell after the preparations ended";
}
#endif

/*
 * After a sync, the node's sidecars through the Beacon API (beacon-api.md): getBlobSidecars (deneb, electra) or
 * getDebugDataColumnSidecars (fulu, the node's columns cols) of the root of each block of the chain with sidecars:
 * as SSZ the block's sidecars the node holds, by index, one after another; as JSON items that lantern_json_decode
 * of BlobSidecar or DataColumnSidecar gives as those sidecars' bytes; with indices of the first and last of them,
 * as SSZ, those two.
 */
static unsigned long api_sidecars_checked; /* the blocks whose sidecars were checked */
static void api_sidecar_checks(fc_node *n, tv parts, case_block **chain, size_t nchain, const uint8_t *cols, const char **why) {
#if FORK >= FORK_DENEB
    struct node_shell *s = n->shell;
    static char msg[256];
    static uint64_t conn = 400;
    const char *path = FORK >= FORK_FULU ? "/eth/v1/debug/beacon/data_column_sidecars/0x" : "/eth/v1/beacon/blob_sidecars/0x";
    const char *type = FORK >= FORK_FULU ? "DataColumnSidecar" : "BlobSidecar";
    (void)cols;
    (void)parts;
    for (size_t b = 0; b < nchain && !*why; b++) {
        const uint8_t *sc[128];
        uint64_t sclen[128], total = 0, nsc = 0;
#if FORK >= FORK_FULU
        for (uint64_t c = 0, len; c < 128; c++) {
            const uint8_t *col = (cols[c / 8] >> (c % 8) & 1) ? case_column(parts, chain[b]->columns, c, &len) : NULL;
            if (col) {
                sc[nsc] = col;
                sclen[nsc++] = len;
            }
        }
#else
        tv e = chain[b]->sidecars ? chain[b]->sidecars + 9 : NULL;
        for (uint64_t i = 0, c = chain[b]->sidecars ? rd64(chain[b]->sidecars + 1) : 0; i < c && nsc < 128; i++, e = tv_skip(e)) {
            sc[nsc] = tv_bytes(e, &sclen[nsc]);
            nsc++;
        }
#endif
        if (!nsc) continue;
        for (uint64_t i = 0; i < nsc; i++) total += sclen[i];
        char hex[65];
        for (int k = 0; k < 32; k++) snprintf(hex + 2 * k, 3, "%02x", chain[b]->root[k]);
        for (int form = 0; form < 3 && !*why; form++) { /* SSZ, JSON, SSZ of the first and last indices */
            char req[384];
            if (form == 2)
                snprintf(req, sizeof req, "GET %s%s?indices=%llu,%llu HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n", path,
                         hex, (unsigned long long)rd64(sc[0]), (unsigned long long)rd64(sc[nsc - 1]));
            else
                snprintf(req, sizeof req, "GET %s%s HTTP/1.1\r\nHost: lantern\r\n%s\r\n", path, hex,
                         form == 0 ? "Accept: application/octet-stream\r\n" : "");
            shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
            uint64_t glen = 0;
            uint8_t *g = *why ? NULL : api_normalize(s, &glen, why);
            const char *gb = (const char *)g, *end = g ? find_bytes(gb, glen, "\r\n\r\n") : NULL;
            if (*why) break;
            const uint8_t *body = end ? (const uint8_t *)end + 4 : NULL;
            uint64_t blen = body ? glen - (uint64_t)(body - g) : 0;
            if (!end || glen < 17 || memcmp(g, "HTTP/1.1 200 OK\r\n", 17) || s->api.lasts != 1 || s->api.late) {
                snprintf(msg, sizeof msg, "API sidecars of a block (form %d): not a 200 answer", form);
                *why = msg;
            } else if (form == 0) {
                uint64_t k = 0;
                int ok = blen == total;
                for (uint64_t i = 0; ok && i < nsc; k += sclen[i], i++) ok = !memcmp(body + k, sc[i], (size_t)sclen[i]);
                if (!ok) {
                    snprintf(msg, sizeof msg, "API sidecars as SSZ: not the block's %llu sidecars, one after another (%llu bytes, not %llu)",
                             (unsigned long long)nsc, (unsigned long long)blen, (unsigned long long)total);
                    *why = msg;
                }
            } else if (form == 2) {
                int ok = nsc == 1 ? blen == sclen[0] && !memcmp(body, sc[0], (size_t)sclen[0])
                                  : blen == sclen[0] + sclen[nsc - 1] && !memcmp(body, sc[0], (size_t)sclen[0]) &&
                                        !memcmp(body + sclen[0], sc[nsc - 1], (size_t)sclen[nsc - 1]);
                if (!ok) *why = "API sidecars with indices: not those sidecars";
            } else { /* JSON: each item decodes as its sidecar */
                char pre[64];
                int pl = snprintf(pre, sizeof pre, "{\"version\":\"%s\",\"execution_optimistic\":", STR(FORK_NAME));
                const char *d = blen > (uint64_t)pl ? find_bytes((const char *)body, blen, ",\"data\":[") : NULL;
                if (!d || memcmp(body, pre, (size_t)pl) || blen < 2 || memcmp(body + blen - 2, "]}", 2)) {
                    *why = "API sidecars as JSON: not {version, execution_optimistic, finalized, data}";
                } else {
                    uint64_t i = 0, p = (uint64_t)(d - (const char *)body) + 9, stop = blen - 2;
                    while (!*why && p < stop) {
                        uint64_t q = p;
                        int depth = 0, in = 0;
                        for (; q < stop; q++) { /* the item's end: its closing } at depth 0 */
                            char c = (char)body[q];
                            if (in) {
                                if (c == '"') in = 0;
                            } else if (c == '"') in = 1;
                            else if (c == '{' || c == '[') depth++;
                            else if ((c == '}' || c == ']') && --depth == 0) {
                                q++;
                                break;
                            }
                        }
                        uint64_t lsize, osize = 24 + (i < nsc ? sclen[i] : 0) + 64;
                        uint8_t *l = list_of(body + p, q - p, 0, 8, &lsize), *scr = buffer(JSON_DECODE_SCRATCH);
                        uint8_t *out = buffer(osize), *fault = buffer(JSON_FAULT_BYTES);
                        wr64(scr, JSON_DECODE_SCRATCH);
                        wr64(out, osize);
                        if (i >= nsc || CALL(lantern_json_decode, type_by_name(type), l, scr, out, fault) != 0 || rd64(out + 16) != sclen[i] ||
                            memcmp(out + 24, sc[i], (size_t)sclen[i]))
                            *why = "API sidecars as JSON: an item that is not the block's sidecar";
                        free(l);
                        free(scr);
                        free(out);
                        free(fault);
                        i++;
                        p = q < stop && body[q] == ',' ? q + 1 : q;
                    }
                    if (!*why && i != nsc) *why = "API sidecars as JSON: not one item for each sidecar";
                }
            }
            if (!*why) *why = api_clean(s);
            free(g);
        }
        if (!*why) api_sidecars_checked++;
    }
#else
    (void)n;
    (void)parts;
    (void)chain;
    (void)nchain;
    (void)cols;
    (void)why;
#endif
}

#if FORK >= FORK_FULU
/* The little endian u32 at p. */
static uint64_t le32(const uint8_t *p) {
    return p[0] | (uint64_t)p[1] << 8 | (uint64_t)p[2] << 16 | (uint64_t)p[3] << 24;
}
#endif

#if FORK >= FORK_DENEB
/* The value of the lower case hex digit c, or 16. */
static unsigned lower_hex_digit(char c) {
    return c >= '0' && c <= '9' ? (unsigned)(c - '0') : c >= 'a' && c <= 'f' ? (unsigned)(c - 'a' + 10) : 16u;
}
#endif

/*
 * After a sync, getBlobs (beacon-api.md) of the root of each block of the chain with sidecars or columns (node.md).
 * Deneb and electra: the blob of each of its sidecars. Fulu, with supernode: blob i is cell i of each of the
 * columns 0 to 63 of the case, and crypto_kzg_blob_to_kzg_commitment of it must give commitment i; without: 404.
 * As SSZ the blobs one after another; as JSON data items whose hex gives them; with versioned_hashes of the first
 * and last commitments, as SSZ, those two blobs.
 */
static unsigned long api_blobs_checked; /* the blocks whose blobs were checked */
static void api_blob_checks(fc_node *n, tv parts, case_block **chain, size_t nchain, int supernode, const char **why) {
#if FORK >= FORK_DENEB
    struct node_shell *s = n->shell;
    static char msg[256];
    static uint64_t conn = 600;
    const uint64_t blob = 4096 * 32; /* FIELD_ELEMENTS_PER_BLOB * BYTES_PER_FIELD_ELEMENT */
    (void)parts;
    (void)supernode;
    for (size_t b = 0; b < nchain && !*why; b++) {
        uint8_t *blobs = NULL;
        const uint8_t *cm[128];
        uint64_t nb = 0;
        int want404 = 0;
#if FORK >= FORK_FULU
        const uint64_t cell = 2048; /* BYTES_PER_CELL */
        uint64_t len0, len;
        const uint8_t *c0 = case_column(parts, chain[b]->columns, 0, &len0);
        if (!c0) continue;
        uint64_t ocom = le32(c0 + 12), opr = le32(c0 + 16);
        nb = (opr - ocom) / 48;
        if (!nb || nb > 128) continue;
        for (uint64_t i = 0; i < nb; i++) cm[i] = c0 + ocom + 48 * i;
        if (!supernode) want404 = 1;
        else {
            blobs = xmalloc((size_t)(nb * blob));
            for (uint64_t c = 0; c < 64 && !*why; c++) {
                const uint8_t *col = case_column(parts, chain[b]->columns, c, &len);
                if (!col) *why = "getBlobs: the case lacks a column of the first half";
                else
                    for (uint64_t i = 0; i < nb; i++) memcpy(blobs + i * blob + c * cell, col + le32(col + 8) + i * cell, (size_t)cell);
            }
            for (uint64_t i = 0; i < nb && !*why; i++) {
                uint8_t got[48];
                if (CALL(crypto_kzg_blob_to_kzg_commitment, kzg_settings, blobs + i * blob, fresh_scratch(), got) != 0 || memcmp(got, cm[i], 48))
                    *why = "getBlobs: cells 0 to 63 of the case's columns are not a blob of its commitment";
            }
        }
#else
        tv e = chain[b]->sidecars ? chain[b]->sidecars + 9 : NULL;
        uint64_t c = chain[b]->sidecars ? rd64(chain[b]->sidecars + 1) : 0;
        if (!c || c > 128) continue;
        blobs = xmalloc((size_t)(c * blob));
        for (uint64_t i = 0; i < c; i++, e = tv_skip(e)) {
            uint64_t sl;
            const uint8_t *sc = tv_bytes(e, &sl);
            memcpy(blobs + nb * blob, sc + 8, (size_t)blob);
            cm[nb++] = sc + 8 + blob;
        }
#endif
        char hex[65], vh[2][67];
        for (int k = 0; k < 32; k++) snprintf(hex + 2 * k, 3, "%02x", chain[b]->root[k]);
        for (int k = 0; k < 2; k++) { /* kzg_commitment_to_versioned_hash of the first and last commitments */
            uint8_t bl[24 + 48], h[32];
            wr64(bl, sizeof bl);
            wr64(bl + 8, 24);
            wr64(bl + 16, 48);
            memcpy(bl + 24, cm[k ? nb - 1 : 0], 48);
            CALL(crypto_sha256, bl, h);
            h[0] = 1; /* VERSIONED_HASH_VERSION_KZG */
            hex_text(vh[k], h, 32);
        }
        for (int form = 0; form < 3 && !*why; form++) { /* SSZ, JSON, SSZ of the first and last versioned hashes */
            char req[512];
            if (form == 2)
                snprintf(req, sizeof req, "GET /eth/v1/beacon/blobs/0x%s?versioned_hashes=%s,%s HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n",
                         hex, vh[0], vh[1]);
            else
                snprintf(req, sizeof req, "GET /eth/v1/beacon/blobs/0x%s HTTP/1.1\r\nHost: lantern\r\n%s\r\n", hex,
                         form == 0 ? "Accept: application/octet-stream\r\n" : "");
            shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
            uint64_t glen = 0;
            uint8_t *g = *why ? NULL : api_normalize(s, &glen, why);
            const char *end = g ? find_bytes((const char *)g, glen, "\r\n\r\n") : NULL;
            if (*why) break;
            const uint8_t *body = end ? (const uint8_t *)end + 4 : NULL;
            uint64_t blen = body ? glen - (uint64_t)(body - g) : 0;
            if (want404) {
                if (!end || glen < 24 || memcmp(g, "HTTP/1.1 404 Not Found\r\n", 24)) *why = "getBlobs of a node with under half the columns: not 404";
                if (!*why) *why = api_clean(s);
                free(g);
                break;
            }
            if (!end || glen < 17 || memcmp(g, "HTTP/1.1 200 OK\r\n", 17) || s->api.lasts != 1 || s->api.late) {
                snprintf(msg, sizeof msg, "getBlobs of a block (form %d): not a 200 answer", form);
                *why = msg;
            } else if (form == 0) {
                if (blen != nb * blob || memcmp(body, blobs, (size_t)(nb * blob))) {
                    snprintf(msg, sizeof msg, "getBlobs as SSZ: not the block's %llu blobs, one after another (%llu bytes)",
                             (unsigned long long)nb, (unsigned long long)blen);
                    *why = msg;
                }
            } else if (form == 2) {
                int ok = nb == 1 ? blen == blob && !memcmp(body, blobs, (size_t)blob)
                                 : blen == 2 * blob && !memcmp(body, blobs, (size_t)blob) &&
                                       !memcmp(body + blob, blobs + (nb - 1) * blob, (size_t)blob);
                if (!ok) *why = "getBlobs with versioned_hashes: not those blobs";
            } else { /* JSON: {"execution_optimistic":…,"finalized":…,"data":["0x…",…]} */
                const char *pre = "{\"execution_optimistic\":";
                const char *d = blen > 24 ? find_bytes((const char *)body, blen, ",\"data\":[") : NULL;
                if (!d || memcmp(body, pre, strlen(pre)) || blen < 2 || memcmp(body + blen - 2, "]}", 2)) {
                    *why = "getBlobs as JSON: not {execution_optimistic, finalized, data}";
                } else {
                    uint64_t i = 0, p = (uint64_t)(d - (const char *)body) + 9, stop = blen - 2;
                    while (!*why && p < stop) {
                        if (i >= nb || stop - p < 2 * blob + 4 || memcmp(body + p, "\"0x", 3) || body[p + 3 + 2 * blob] != '"') {
                            *why = "getBlobs as JSON: an item that is not \"0x and a blob's hex";
                            break;
                        }
                        for (uint64_t k = 0; k < blob && !*why; k++) {
                            unsigned hi = lower_hex_digit((char)body[p + 3 + 2 * k]), lo = lower_hex_digit((char)body[p + 4 + 2 * k]);
                            if (hi > 15 || lo > 15 || (uint8_t)(hi << 4 | lo) != blobs[i * blob + k]) *why = "getBlobs as JSON: an item that is not the block's blob";
                        }
                        p += 2 * blob + 4;
                        if (p < stop && body[p] == ',') p++;
                        i++;
                    }
                    if (!*why && i != nb) *why = "getBlobs as JSON: not one item for each blob";
                }
            }
            if (!*why) *why = api_clean(s);
            free(g);
        }
        free(blobs);
        if (!*why) api_blobs_checked++;
    }
#else
    (void)n;
    (void)parts;
    (void)chain;
    (void)nchain;
    (void)supernode;
    (void)why;
#endif
}

/*
 * The custody group count of a supernode through the Beacon API: getNetworkIdentity's metadata must give
 * custody_group_count NUMBER_OF_CUSTODY_GROUPS (beacon-api.md).
 */
#if FORK >= FORK_FULU
static void api_supernode_identity(fc_node *n, const char **why) {
    static uint64_t conn = 900;
    const char *req = "GET /eth/v1/node/identity HTTP/1.1\r\nHost: lantern\r\n\r\n";
    shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
    uint64_t glen = 0;
    uint8_t *g = *why ? NULL : api_normalize(n->shell, &glen, why);
    char want[64];
    snprintf(want, sizeof want, "\"custody_group_count\":\"%llu\"", (unsigned long long)rd64(config + 280));
    if (!*why && (glen < 17 || memcmp(g, "HTTP/1.1 200 OK\r\n", 17) || !find_bytes((const char *)g, glen, want)))
        *why = "a supernode's getNetworkIdentity: custody_group_count is not NUMBER_OF_CUSTODY_GROUPS";
    if (!*why) *why = api_clean(n->shell);
    free(g);
}
#endif

/*
 * getBlockHeaders of the Db's blocks (beacon-api.md), in a node whose Db holds the chain below its anchor, the
 * chain's last block: of each slot of a block below the anchor, and of the root of each block below the anchor's
 * parent as parent_root; each answer the Db's block alone.
 */
static void api_headers_db_checks(fc_node *n, case_block **chain, size_t nchain, const char **why) {
    size_t nh = nchain ? nchain - 1 : 0;
    hd_block *hb = xmalloc(sizeof *hb * (nh ? nh : 1));
    uint64_t conn = 200, f_slot = nchain ? chain[nchain - 1]->slot : 0;
    char req[256];
    for (size_t b = 0; b < nh && !*why; b++) {
        hd_block *h = &hb[b];
        uint64_t vsize;
        uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), chain[b]->bytes, chain[b]->len, &vsize, why);
        if (!sb) break;
        root_of("BeaconBlockBody", nested(nested(sb, field_offset("SignedBeaconBlock", 0)), field_offset("BeaconBlock", 4)),
                h->body_root, why);
        free(sb);
        memcpy(h->root, chain[b]->root, 32);
        memcpy(h->parent, chain[b]->parent, 32);
        h->slot = chain[b]->slot;
        h->len = chain[b]->len;
        h->bytes = chain[b]->bytes;
        h->entry = NULL;
        h->on = 1;
    }
    for (size_t b = 0; b < nh && !*why; b++) {
        snprintf(req, sizeof req, "GET /eth/v1/beacon/headers?slot=%llu HTTP/1.1\r\nHost: lantern\r\n\r\n", (unsigned long long)hb[b].slot);
        api_headers_query(n, hb, nh, req, 1, hb[b].slot, NULL, f_slot, conn++, why);
        if (*why || b + 1 >= nh) continue;
        int k = snprintf(req, sizeof req, "GET /eth/v1/beacon/headers?parent_root=0x");
        for (int j = 0; j < 32; j++) k += snprintf(req + k, sizeof req - (size_t)k, "%02x", hb[b].root[j]);
        snprintf(req + k, sizeof req - (size_t)k, " HTTP/1.1\r\nHost: lantern\r\n\r\n");
        api_headers_query(n, hb, nh, req, 0, 0, hb[b].root, f_slot, conn++, why);
    }
    free(hb);
}

/*
 * getBlockHeaders in node mode (beacon-api.md): of each slot of a valid block of the case and of the slot after the
 * head's, of the root of the anchor and of each such block as parent_root, of a block's slot
 * with its parent root and with another root, and with no query (the head's slot).
 */
static void api_headers_checks(fc_node *n, tv parts, case_block **chain, size_t nchain, uint64_t anchor_slot, uint64_t head_slot,
                               uint64_t *conn, const char **why) {
    struct node_shell *s = n->shell;
    tv steps = tv_get(parts, "steps");
    uint64_t count = steps ? rd64(steps + 1) : 0, f_slot = 0;
    hd_block *hb = xmalloc(sizeof *hb * (count ? count : 1));
    size_t nh = 0;
    const uint8_t *anchor_root = s->anchor, *ae = shell_block(s, anchor_root);
    uint64_t at = 0;
    for (tv stp = steps ? steps + 9 : NULL; stp && at < count && !*why; stp = tv_skip(stp), at++) {
        tv v = tv_get(stp, "valid"), bname = tv_get(stp, "block");
        if (!bname || (v && !(*v == T_BOOL && v[1]))) goto next;
        char key[128];
        uint64_t vsize;
        snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
        hd_block *h = &hb[nh];
        h->bytes = tv_bytes(tv_get(parts, key), &h->len);
        uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), h->bytes, h->len, &vsize, why);
        if (!sb) break;
        const uint8_t *block = nested(sb, field_offset("SignedBeaconBlock", 0));
        root_of("BeaconBlock", block, h->root, why);
        root_of("BeaconBlockBody", nested(block, field_offset("BeaconBlock", 4)), h->body_root, why);
        h->slot = rd64(block + field_offset("BeaconBlock", 0));
        memcpy(h->parent, block + field_offset("BeaconBlock", 2), 32);
        free(sb);
        int dup = 0;
        for (size_t j = 0; j < nh; j++)
            if (!memcmp(hb[j].root, h->root, 32)) dup = 1;
        if (dup) goto next;
        h->entry = shell_block(s, h->root);
        h->on = 0;
        for (size_t c = 0; c < nchain; c++)
            if (!memcmp(chain[c]->root, h->root, 32)) h->on = 1;
        nh++;
    next:;
    }
    const uint8_t *fr = n->store + STORE_FINALIZED + 8;
    if (!memcmp(fr, anchor_root, 32)) f_slot = anchor_slot;
    for (size_t j = 0; j < nh; j++)
        if (!memcmp(hb[j].root, fr, 32)) f_slot = hb[j].slot;
    char req[256];
    const char *tail = " HTTP/1.1\r\nHost: lantern\r\n\r\n";
    static const uint8_t other[32] = {7, 7, 7};
    if (!*why && ae && head_slot > anchor_slot) { /* no query: the head's slot */
        snprintf(req, sizeof req, "GET /eth/v1/beacon/headers%s", tail);
        api_headers_query(n, hb, nh, req, 1, head_slot, NULL, f_slot, (*conn)++, why);
    }
    if (!*why && ae && head_slot >= anchor_slot) { /* the slot after the head's: none */
        snprintf(req, sizeof req, "GET /eth/v1/beacon/headers?slot=%llu%s", (unsigned long long)(head_slot + 1), tail);
        api_headers_query(n, hb, nh, req, 1, head_slot + 1, NULL, f_slot, (*conn)++, why);
    }
    for (size_t j = 0; ae && j <= nh && !*why; j++) {
        const uint8_t *root = j < nh ? hb[j].root : anchor_root;
        int k = snprintf(req, sizeof req, "GET /eth/v1/beacon/headers?parent_root=0x");
        for (int b = 0; b < 32; b++) k += snprintf(req + k, sizeof req - (size_t)k, "%02x", root[b]);
        snprintf(req + k, sizeof req - (size_t)k, "%s", tail);
        api_headers_query(n, hb, nh, req, 0, 0, root, f_slot, (*conn)++, why);
        if (*why || j == nh || hb[j].slot == anchor_slot || !memcmp(hb[j].parent, ae + 32, 32)) continue; /* NodeBlock_parent_root */
        int seen = 0;
        for (size_t i = 0; i < j; i++)
            if (hb[i].slot == hb[j].slot) seen = 1;
        if (!seen) {
            snprintf(req, sizeof req, "GET /eth/v1/beacon/headers?slot=%llu%s", (unsigned long long)hb[j].slot, tail);
            api_headers_query(n, hb, nh, req, 1, hb[j].slot, NULL, f_slot, (*conn)++, why);
        }
        for (int o = 0; o < 2 && !*why; o++) {
            const uint8_t *pr = o ? other : hb[j].parent;
            k = snprintf(req, sizeof req, "GET /eth/v1/beacon/headers?slot=%llu&parent_root=0x", (unsigned long long)hb[j].slot);
            for (int b = 0; b < 32; b++) k += snprintf(req + k, sizeof req - (size_t)k, "%02x", pr[b]);
            snprintf(req + k, sizeof req - (size_t)k, "%s", tail);
            api_headers_query(n, hb, nh, req, 1, hb[j].slot, pr, f_slot, (*conn)++, why);
        }
    }
    free(hb);
}

/*
 * Node mode, after the steps (docs/reference/node.md, Test vectors): the chain is the case's valid
 * blocks from the node's head_root by parent_root. getBlockRoot of each slot after the anchor's to
 * the head's: the chain's block of that slot, else 404. getStateRoot of each slot from the head's to
 * the store's, at most an epoch and a slot past the head's: the hash_tree_root of the head's
 * post-state processed to the slot. getBlockHeader of the root of each valid block the node holds:
 * 200, canonical when it is on the chain. Then getBlockHeaders (api_headers_checks).
 */
static unsigned long api_lookups;
static unsigned long api_archive_states; /* old states the archive checks asked */
static unsigned long api_duty_epochs;    /* duties the lookup checks asked */
static void api_lookup_checks(fc_node *n, tv parts, const char **why) {
    struct node_shell *s = n->shell;
    case_block *blocks = NULL, **chain = NULL;
    size_t nchain = case_chain(parts, &blocks, &chain, why), nblocks = 0;
    const uint8_t *head = s->node + NODE_HEAD_ROOT, *e = shell_block(s, head), *st = shell_state_of(n, head);
    uint64_t anchor_slot = rd64(s->anchor + 32), head_slot = e ? rd64(e + 64) : 0, conn = 100; /* NodeBlock_slot */
    char req[192], msg[192];
    uint8_t got[32];
    if (*why || !e || !st || (nchain && memcmp(chain[nchain - 1]->root, head, 32))) goto done; /* the chain must end at the head */
    for (uint64_t slot = anchor_slot + 1; slot <= head_slot && !*why; slot++) {
        const uint8_t *want = NULL;
        for (size_t k = 0; k < nchain; k++)
            if (chain[k]->slot == slot) want = chain[k]->root;
        snprintf(req, sizeof req, "GET /eth/v1/beacon/blocks/%llu/root HTTP/1.1\r\nHost: lantern\r\n\r\n", (unsigned long long)slot);
        shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
        if (*why) break;
        int ok = want ? api_root_of(s, got) && !memcmp(got, want, 32) : s->api.len > 13 && !memcmp(s->api.b, "HTTP/1.1 404 ", 13);
        if (!ok) {
            snprintf(msg, sizeof msg, "API getBlockRoot of slot %llu: not %s", (unsigned long long)slot, want ? "the chain's block" : "404");
            *why = msg;
        }
        api_lookups++;
    }
    uint64_t store_slot = (rd64(n->store + STORE_TIME_MS) - rd64(n->store + STORE_GENESIS_TIME_MS)) / rd64(config + 104);
    uint64_t last = store_slot < head_slot + SLOTS_PER_EPOCH_RUNNER + 1 ? store_slot : head_slot + SLOTS_PER_EPOCH_RUNNER + 1;
    uint64_t size = 0;
    for (size_t b = 0; b < s->nbufs; b++)
        if (s->bufs[b].b == st) size = s->bufs[b].size;
    uint8_t *copy = size ? copy_of(st, size) : NULL;
    for (uint64_t slot = head_slot; copy && slot <= last && !*why; slot++) {
        uint64_t result = 0, status, growth = 2;
        uint8_t root[32];
        if (slot > head_slot)
            while ((status = CALL(LF(process_slots), copy, &slot, config, fresh_scratch(), &result)) == 1 && !*why)
                copy = regrow(copy, &size, growth *= 2, why);
        else
            status = 0;
        if (*why || status != 0 || result != 0) break; /* a slot lantern does not reach alone: the rest is skipped */
        root_of("BeaconState", copy, root, why);
        snprintf(req, sizeof req, "GET /eth/v1/beacon/states/%llu/root HTTP/1.1\r\nHost: lantern\r\n\r\n", (unsigned long long)slot);
        if (!*why) shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
        if (!*why && !(api_root_of(s, got) && !memcmp(got, root, 32))) {
            snprintf(msg, sizeof msg, "API getStateRoot of slot %llu: not the head's post-state at that slot", (unsigned long long)slot);
            *why = msg;
        }
        if (!*why) *why = api_clean(s);
        api_lookups++;
    }
    free(copy);
    /* getStateRoot of each slot from the anchor's to the head's, then of its state root: that root (below F's slot by the replay) */
    uint64_t roots_n = strcmp(PRESET, "minimal") ? 8192 : 64, first = head_slot > roots_n ? head_slot - roots_n : 0;
    uint8_t head_root[32];
    if (!*why) root_of("BeaconState", st, head_root, why);
    for (uint64_t slot = anchor_slot > first ? anchor_slot : first; slot <= head_slot && !*why; slot++) {
        const uint8_t *r = slot == head_slot ? head_root : st + field_offset("BeaconState", 6) + 32 * (slot % roots_n);
        snprintf(req, sizeof req, "GET /eth/v1/beacon/states/%llu/root HTTP/1.1\r\nHost: lantern\r\n\r\n", (unsigned long long)slot);
        shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
        if (*why) break;
        if (!(api_root_of(s, got) && !memcmp(got, r, 32))) {
            snprintf(msg, sizeof msg, "API getStateRoot of slot %llu: not its state root", (unsigned long long)slot);
            *why = msg;
        }
        if (!*why) *why = api_clean(s);
        api_lookups++;
        if (*why) break;
        int k = snprintf(req, sizeof req, "GET /eth/v1/beacon/states/0x");
        for (int b = 0; b < 32; b++) k += snprintf(req + k, sizeof req - (size_t)k, "%02x", r[b]);
        snprintf(req + k, sizeof req - (size_t)k, "/root HTTP/1.1\r\nHost: lantern\r\n\r\n");
        shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
        if (*why) break;
        if (!(api_root_of(s, got) && !memcmp(got, r, 32))) {
            snprintf(msg, sizeof msg, "API getStateRoot of the state root of slot %llu: not that root", (unsigned long long)slot);
            *why = msg;
        }
        if (!*why) *why = api_clean(s);
        api_lookups++;
    }
    /* with state records (node.md, the archive): getStateV2 as SSZ of the slot after each, below the head: the
       state of that slot's state root, from a replay whose base is a state record, full or a diff */
    if (!*why && (s->flags & NODE_FLAG_DB) && rd64(s->node + NODE_ARCHIVE + 16) != UINT64_MAX) {
        const uint8_t *db = s->node + rd64(s->node + NODE_DB);
        for (uint64_t sl = rd64(db + 8); sl < rd64(db + 16) && !*why; sl++) {
            uint64_t q = sl + 1, glen = 0, vsize = 0;
            if (!rd64(db + rd64(db + 24) + DB_SLOT_BYTES * (sl - rd64(db + 8)) + 88) || q <= anchor_slot || q >= head_slot ||
                head_slot - q >= roots_n)
                continue;
            const uint8_t *r = st + field_offset("BeaconState", 6) + 32 * (q % roots_n);
            snprintf(req, sizeof req, "GET /eth/v2/debug/beacon/states/%llu HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n",
                     (unsigned long long)q);
            s->api.room = 0;
            shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
            uint8_t *g = *why ? NULL : api_normalize(s, &glen, why);
            const char *end = g ? find_bytes((const char *)g, glen, "\r\n\r\n") : NULL;
            if (*why) break;
            if (!end || glen < 17 || memcmp(g, "HTTP/1.1 200 OK\r\n", 17)) {
                snprintf(msg, sizeof msg, "API getStateV2 of slot %llu after a state record: not 200", (unsigned long long)q);
                *why = msg;
            } else {
                const uint8_t *body = (const uint8_t *)end + 4;
                uint8_t *v = decode(type_by_name("BeaconState"), body, glen - (uint64_t)(body - g), &vsize, why);
                uint8_t root[32];
                if (!v) *why = "API getStateV2 after a state record: not a state";
                else root_of("BeaconState", v, root, why);
                if (!*why && memcmp(root, r, 32)) {
                    snprintf(msg, sizeof msg, "API getStateV2 of slot %llu after a state record: another state", (unsigned long long)q);
                    *why = msg;
                }
                free(v);
                api_archive_states++;
            }
            free(g);
            if (!*why) *why = api_clean(s);
        }
    }
    /* getProposerDuties and getAttesterDuties of validator 0 for each epoch from the anchor's to the head's: 200, an
       item for each slot of the epoch above 0 and one item (below F's slot by the replay); 503 while the node syncs */
    for (uint64_t ep = (anchor_slot + SLOTS_PER_EPOCH_RUNNER - 1) / SLOTS_PER_EPOCH_RUNNER; ep <= head_slot / SLOTS_PER_EPOCH_RUNNER && !*why; ep++) {
        for (int kind = 0; kind < 2 && !*why; kind++) {
            uint64_t glen = 0, items = 0;
            if (kind == 0)
                snprintf(req, sizeof req, "GET /eth/v1/validator/duties/proposer/%llu HTTP/1.1\r\nHost: lantern\r\n\r\n", (unsigned long long)ep);
            else
                snprintf(req, sizeof req, "POST /eth/v1/validator/duties/attester/%llu HTTP/1.1\r\nHost: lantern\r\nContent-Type: application/json\r\n"
                         "Content-Length: 5\r\n\r\n[\"0\"]", (unsigned long long)ep);
            s->api.room = 0;
            shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
            uint8_t *g = *why ? NULL : api_normalize(s, &glen, why);
            const char *end = g ? find_bytes((const char *)g, glen, "\r\n\r\n") : NULL;
            if (*why) break;
            if (end && glen >= 13 && !memcmp(g, "HTTP/1.1 503 ", 13)) {
                free(g);
                *why = api_clean(s);
                continue;
            }
            for (const char *at = end; at && (at = find_bytes(at + 1, glen - (uint64_t)(at + 1 - (const char *)g), "\"slot\":\"")); ) items++;
            if (!end || glen < 17 || memcmp(g, "HTTP/1.1 200 OK\r\n", 17) || items != (kind ? 1 : ep ? SLOTS_PER_EPOCH_RUNNER : SLOTS_PER_EPOCH_RUNNER - 1)) {
                snprintf(msg, sizeof msg, "API %s of epoch %llu: not 200 with %u items", kind ? "getAttesterDuties" : "getProposerDuties",
                         (unsigned long long)ep, kind ? 1u : ep ? (unsigned)SLOTS_PER_EPOCH_RUNNER : (unsigned)SLOTS_PER_EPOCH_RUNNER - 1);
                *why = msg;
            }
            free(g);
            if (!*why) *why = api_clean(s);
            api_duty_epochs++;
        }
    }
    tv steps = tv_get(parts, "steps");
    for (tv stp = steps ? steps + 9 : NULL; stp && nblocks < rd64(steps + 1) && !*why; stp = tv_skip(stp), nblocks++) {
        tv v = tv_get(stp, "valid"), bname = tv_get(stp, "block");
        if (!bname || (v && !(*v == T_BOOL && v[1]))) continue;
        char key[128];
        uint64_t len, vsize;
        uint8_t root[32];
        snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
        const uint8_t *bytes = tv_bytes(tv_get(parts, key), &len);
        uint8_t *sb = decode(type_by_name("SignedBeaconBlock"), bytes, len, &vsize, why);
        if (!sb) break;
        root_of("BeaconBlock", nested(sb, field_offset("SignedBeaconBlock", 0)), root, why);
        free(sb);
        const uint8_t *be = shell_block(s, root);
        if (*why || !be || rd64(be + NB_STATUS) != NB_IMPORTED) continue;
        int on = 0;
        for (size_t k = 0; k < nchain; k++)
            if (!memcmp(chain[k]->root, root, 32)) on = 1;
        int k = snprintf(req, sizeof req, "GET /eth/v1/beacon/headers/0x");
        for (int b = 0; b < 32; b++) k += snprintf(req + k, sizeof req - (size_t)k, "%02x", root[b]);
        snprintf(req + k, sizeof req - (size_t)k, " HTTP/1.1\r\nHost: lantern\r\n\r\n");
        shell_api_ask(n, (const uint8_t *)req, strlen(req), conn++, why);
        if (!*why && !(api_root_of(s, got) && !memcmp(got, root, 32) &&
                       find_bytes((const char *)s->api.b, s->api.len, on ? "\"canonical\":true" : "\"canonical\":false"))) {
            snprintf(msg, sizeof msg, "API getBlockHeader of a block %s the chain: not 200 with canonical %s", on ? "on" : "off",
                     on ? "true" : "false");
            *why = msg;
        }
        api_lookups++;
    }
    if (!*why) api_headers_checks(n, parts, chain, nchain, anchor_slot, head_slot, &conn, why);
done:
    free(chain);
    free(blocks);
}

/*
 * http-request: lantern_http_request of each case's bytes (tests/generator/http_request.py): the
 * status, the HTTP status of a fault, and for a request read its fields and its six parts, each at
 * a multiple of 8 and in order; with one byte less of room than out_size, LANTERN_BUFFER_TOO_SMALL;
 * and the status of every shorter prefix of the bytes.
 */
static void run_http_request(const char *file, case_file *f) {
    static const char *const parts_names[6] = {"path", "query", "accept", "content_type", "consensus_version", "body"};
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, blen, plen, http = 0;
        tv parts = next_case(f, &name, &len);
        const uint8_t *b = tv_bytes(tv_get(parts, "bytes"), &blen), *prefix = tv_bytes(tv_get(parts, "prefix"), &plen);
        uint64_t limits[2] = {tv_u64(tv_get(parts, "head_max")), tv_u64(tv_get(parts, "body_max"))};
        uint64_t want = tv_u64(tv_get(parts, "status")), want_http = tv_u64(tv_get(parts, "http_status"));
        tv osz = tv_get(parts, "out_size");
        uint64_t osize = osz ? tv_u64(osz) : HTTP_REQUEST_FIXED + 64;
        uint8_t *out = NULL;
        uint64_t st = http_request_call(b, blen, limits, osize, &out, &http, &why);
        static char msg[256];
        if (why) {
        } else if (st != want) {
            snprintf(msg, sizeof msg, "status %llu, not %llu", (unsigned long long)st, (unsigned long long)want);
            why = msg;
        } else if (st == HTTP_INVALID_STATUS && http != want_http) {
            snprintf(msg, sizeof msg, "HTTP status %llu, not %llu", (unsigned long long)http, (unsigned long long)want_http);
            why = msg;
        } else if (st == 0) {
            static const char *const fields[5] = {"used", "method", "version", "close", NULL};
            static const uint64_t offsets[4] = {16, 24, 32, 40};
            for (int k = 0; k < 4 && !why; k++)
                if (rd64(out + offsets[k]) != tv_u64(tv_get(parts, fields[k]))) {
                    snprintf(msg, sizeof msg, "%s is %llu", fields[k], (unsigned long long)rd64(out + offsets[k]));
                    why = msg;
                }
            uint64_t at = HTTP_REQUEST_FIXED;
            for (int k = 0; k < 6 && !why; k++) {
                uint64_t wl, off = rd64(out + 48 + 16 * k), cnt = rd64(out + 56 + 16 * k);
                const uint8_t *w = tv_bytes(tv_get(parts, parts_names[k]), &wl);
                if (off != at || cnt != wl || (wl && memcmp(out + off, w, (size_t)wl))) {
                    snprintf(msg, sizeof msg, "part %s: offset %llu, count %llu", parts_names[k], (unsigned long long)off,
                             (unsigned long long)cnt);
                    why = msg;
                }
                at += (wl + 7) / 8 * 8;
            }
            uint8_t *small = NULL;
            if (!why && http_request_call(b, blen, limits, osize - 1, &small, &http, &why) != 1 && !why)
                why = "one byte less of room is not LANTERN_BUFFER_TOO_SMALL";
            free(small);
        }
        free(out);
        for (uint64_t k = 0; k < blen && !why && plen == 3 * blen; k++) {
            uint64_t ws = prefix[3 * k], wh = prefix[3 * k + 1] | (uint64_t)prefix[3 * k + 2] << 8;
            uint8_t *o = NULL;
            uint64_t s = http_request_call(b, k, limits, HTTP_REQUEST_FIXED + 2048, &o, &http, &why);
            if (!why && (s != ws || (s == HTTP_INVALID_STATUS && http != wh))) {
                snprintf(msg, sizeof msg, "the first %llu bytes: status %llu (HTTP %llu), not %llu (HTTP %llu)",
                         (unsigned long long)k, (unsigned long long)s, (unsigned long long)http, (unsigned long long)ws,
                         (unsigned long long)wh);
                why = msg;
            }
            free(o);
        }
        if (!why && plen != 3 * blen) why = "the case's prefix list is not 3 bytes per length";
        report(file, name, len, !why, why);
    }
}

#define ROUTE_INVALID_STATUS 64
#define API_ROUTE_FIXED 488

/* An HttpRequest of the case's method and parts path, query, accept, content_type, consensus_version and body (none when the case has no body part). */
static uint8_t *route_request(tv parts, uint64_t *size) {
    static const char *const names[5] = {"path", "query", "accept", "content_type", "consensus_version"};
    const uint8_t *b[5];
    uint64_t lens[5], n = HTTP_REQUEST_FIXED, blen = 0;
    for (int k = 0; k < 5; k++) {
        b[k] = tv_bytes(tv_get(parts, names[k]), &lens[k]);
        n += (lens[k] + 7) / 8 * 8;
    }
    tv bv = tv_get(parts, "body");
    const uint8_t *bb = bv ? tv_bytes(bv, &blen) : NULL;
    n += (blen + 7) / 8 * 8;
    uint8_t *r = buffer(n);
    wr64(r, n);
    wr64(r + 8, 0);
    wr64(r + 16, 0);
    wr64(r + 24, tv_u64(tv_get(parts, "method")));
    wr64(r + 32, 11);
    wr64(r + 40, 0);
    uint64_t at = HTTP_REQUEST_FIXED;
    for (int k = 0; k < 5; k++) {
        wr64(r + 48 + 16 * k, at);
        wr64(r + 56 + 16 * k, lens[k]);
        if (lens[k]) memcpy(r + at, b[k], (size_t)lens[k]);
        at += (lens[k] + 7) / 8 * 8;
    }
    wr64(r + 128, at);
    wr64(r + 136, blen);
    if (blen) memcpy(r + at, bb, (size_t)blen);
    *size = n;
    return r;
}

/*
 * api-route: lantern_api_route of each case's request (tests/generator/api_route.py): the status;
 * with LANTERN_OK every byte of the ApiRoute, then one byte less of room; with
 * LANTERN_INVALID_ROUTE its HTTP status, fault, allow and op.
 */
static void run_api_route(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, size, wl = 0;
        tv parts = next_case(f, &name, &len);
        uint8_t *r = route_request(parts, &size);
        uint64_t want = tv_u64(tv_get(parts, "status"));
        tv wo = tv_get(parts, "out");
        const uint8_t *w = wo ? tv_bytes(wo, &wl) : NULL;
        uint64_t osize = w ? wl : API_ROUTE_FIXED + 4096;
        uint8_t *out = buffer(osize);
        wr64(out, osize);
        uint64_t st = CALL(lantern_api_route, r, out);
        static char msg[256];
        if (!guard_ok(out, osize) || !guard_ok(r, size)) {
            why = "lantern_api_route wrote out of bounds";
        } else if (st != want) {
            snprintf(msg, sizeof msg, "status %llu, not %llu", (unsigned long long)st, (unsigned long long)want);
            why = msg;
        } else if (st == 0) {
            for (uint64_t k = 0; k < wl && !why; k++)
                if (out[k] != w[k]) {
                    snprintf(msg, sizeof msg, "byte %llu is %u, not %u", (unsigned long long)k, out[k], w[k]);
                    why = msg;
                }
            if (!why) {
                uint8_t *small = buffer(osize - 1);
                wr64(small, osize - 1);
                if (CALL(lantern_api_route, r, small) != 1) why = "one byte less of room is not LANTERN_BUFFER_TOO_SMALL";
                else if (!guard_ok(small, osize - 1)) why = "lantern_api_route wrote past a short out";
                free(small);
            }
        } else if (st == ROUTE_INVALID_STATUS) {
            static const char *const fields[4] = {"http_status", "fault", "allow", "op"};
            static const uint64_t offsets[4] = {8, 32, 24, 16};
            for (int k = 0; k < 4 && !why; k++)
                if (rd64(out + offsets[k]) != tv_u64(tv_get(parts, fields[k]))) {
                    snprintf(msg, sizeof msg, "%s is %llu", fields[k], (unsigned long long)rd64(out + offsets[k]));
                    why = msg;
                }
        }
        report(file, name, len, !why, why);
        free(r);
        free(out);
    }
}

/* ---------------------------------------------------------------- Engine API client */

#define INVALID_HTTP 52
#define HTTP_MORE 53

/* Whether ByteList l holds exactly the bytes of want. */
static int list_holds(const uint8_t *l, tv want) {
    uint64_t wl;
    const uint8_t *w = tv_bytes(want, &wl);
    return rd64(l + 8) == 24 && rd64(l + 16) == wl && !memcmp(l + 24, w, (size_t)wl);
}

/* engine-<function>: lantern's cases of the Engine API client (tests/generator/engine.py). */
static void run_engine(const char *file, const char *handler, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, blen, size, st;
        tv parts = next_case(f, &name, &len);
        tv in = tv_get(parts, "input"), want = tv_get(parts, "output");
        if (!strcmp(handler, "exchange_capabilities") || !strcmp(handler, "forkchoice_updated") || !strcmp(handler, "new_payload") ||
            !strcmp(handler, "get_execution_requests_list") || !strcmp(handler, "get_payload")) {
            uint64_t wl, need = 24 + 512, id = tv_get(in, "id") ? tv_u64(tv_get(in, "id")) : 0, alen = 0;
            const uint8_t *w = tv_bytes(want, &wl), *attributes = NULL;
            uint8_t *value = NULL;
            const char *dwhy = NULL;
            (void)w;
            if (!strcmp(handler, "forkchoice_updated")) {
                attributes = tv_bytes(tv_get(in, "attributes"), &alen);
                if (alen) need = 24 + 1024 + 192 * rd64(attributes + 96);
                else attributes = NULL;
            } else if (!strcmp(handler, "get_payload")) need = 24 + 256;
            if (!strcmp(handler, "new_payload") || !strcmp(handler, "get_execution_requests_list")) {
                int np = !strcmp(handler, "new_payload");
                const uint8_t *enc = tv_bytes(tv_get(in, np ? "block" : "execution_requests"), &blen);
                uint64_t vsize;
                value = decode(type_by_name(np ? "BeaconBlock" : "ExecutionRequests"), enc, blen, &vsize, &dwhy);
                if (!value) {
                    report(file, name, len, 0, dwhy);
                    continue;
                }
                need = 24 + wl;
#if FORK >= FORK_BELLATRIX
                if (np) {
                    uint64_t bound = 0;
                    if (CALL(LF(engine_new_payload_size), value, &bound) != 0) why = "size status";
                    else if (bound < wl) why = "the size is below the request";
                    need = 24 + bound;
                }
#endif
            }
            uint8_t *out = buffer(need), *small = buffer(need - 1);
            wr64(out, need);
            wr64(small, need - 1);
            uint64_t st2 = 1;
            if (!why) {
                if (!strcmp(handler, "exchange_capabilities")) {
                    st = CALL(lantern_engine_exchange_capabilities, &id, out);
                    st2 = CALL(lantern_engine_exchange_capabilities, &id, small);
                }
#if FORK >= FORK_BELLATRIX
                else if (!strcmp(handler, "forkchoice_updated")) {
                    const uint8_t *state = tv_bytes(tv_get(in, "state"), &blen);
                    st = CALL(LF(engine_forkchoice_updated), state, attributes, &id, out);
                    st2 = CALL(LF(engine_forkchoice_updated), state, attributes, &id, small);
                } else if (!strcmp(handler, "get_payload")) {
                    const uint8_t *pid = tv_bytes(tv_get(in, "payload_id"), &blen);
                    st = CALL(LF(engine_get_payload), pid, &id, out);
                    st2 = CALL(LF(engine_get_payload), pid, &id, small);
                } else if (!strcmp(handler, "new_payload")) {
                    st = CALL(LF(engine_new_payload), value, &id, fresh_scratch(), out);
                    st2 = CALL(LF(engine_new_payload), value, &id, fresh_scratch(), small);
                }
#endif
#if FORK >= FORK_ELECTRA
                else if (!strcmp(handler, "get_execution_requests_list")) {
                    st = CALL(LF(get_execution_requests_list), value, out);
                    st2 = wl ? CALL(LF(get_execution_requests_list), value, small) : 1;
                }
#endif
                else st = 99;
                if (st) why = "status";
                else if (!list_holds(out, want)) why = "output differs";
                else if (!guard_ok(out, need)) why = "wrote past out";
                else if (st2 != 1) why = "short out accepted";
            }
            free(value);
            free(out);
            free(small);
        } else if (!strcmp(handler, "payload_attributes")) {
#if FORK >= FORK_BELLATRIX
            uint64_t flen, vsize, wl = 0;
            const uint8_t *enc = tv_bytes(tv_get(in, "state"), &blen), *fee = tv_bytes(tv_get(in, "fee_recipient"), &flen);
            const char *dwhy = NULL;
            uint8_t *state = decode(type_by_name("BeaconState"), enc, blen, &vsize, &dwhy);
            if (!state) {
                report(file, name, len, 0, dwhy);
                continue;
            }
            const uint8_t *w = is_text(want, "invalid") ? NULL : tv_bytes(want, &wl);
            size = w ? wl : 104 + 44 * 16; /* the attributes' bytes: 104 and 44 a withdrawal */
            uint8_t *out = buffer(size);
            st = CALL(LF(get_payload_attributes), state, fee, config, fresh_scratch(), out);
            if (!w) {
                if (st < 2) why = "status";
            } else if (st) why = "status";
            else if (memcmp(out, w, (size_t)wl)) why = "attributes differ";
            else if (!guard_ok(out, size)) why = "wrote past out";
            free(state);
            free(out);
#else
            why = "no such handler";
#endif
        } else if (!strcmp(handler, "get_execution_requests")) {
#if FORK >= FORK_ELECTRA
            uint64_t lsize, wl = 0;
            uint8_t *list = byte_list(tv_get(in, "list"), &lsize);
            if (!is_text(want, "invalid")) tv_bytes(want, &wl);
            size = 24 + (wl ? wl : 12 + lsize);
            uint8_t *out = buffer(size), *small = buffer(size - 1);
            wr64(out, size);
            wr64(small, size - 1);
            st = CALL(LF(get_execution_requests), list, out);
            if (is_text(want, "invalid")) {
                if (st != 56) why = "status";
            } else if (st) why = "status";
            else if (!list_holds(out, want)) why = "requests differ";
            else if (!guard_ok(out, size)) why = "wrote past out";
            else if (CALL(LF(get_execution_requests), list, small) != 1) why = "short out accepted";
            if (!why && !guard_ok(list, lsize)) why = "wrote past list";
            free(list);
            free(out);
            free(small);
#else
            why = "no such handler";
#endif
        } else if (!strcmp(handler, "parse_response")) {
            uint64_t method = tv_u64(tv_get(in, "method")), bsize;
            uint8_t *body = byte_list(tv_get(in, "body"), &bsize), *out = buffer(112);
            st = CALL(lantern_engine_parse_response, body, &method, out);
            if (is_text(want, "invalid")) {
                if (st != 54) why = "status";
            } else if (st) why = "status";
            else {
                tv lv = tv_get(want, "latest_valid_hash"), pv = tv_get(want, "payload_id"), ec = tv_get(want, "error_code");
                int64_t code = *ec == T_NEG_INT ? (int64_t)rd64(ec + 1) : (int64_t)tv_u64(ec);
                if (rd64(out) != tv_u64(tv_get(want, "id"))) why = "id differs";
                else if (rd64(out + 8) != tv_u64(tv_get(want, "error"))) why = "error differs";
                else if (rd64(out + 8) && (int64_t)rd64(out + 16) != code) why = "error code differs";
                else if (!rd64(out + 8) && rd64(out + 24) != tv_u64(tv_get(want, "status"))) why = "status differs";
                else if (!rd64(out + 8) && method != 3 && rd64(out + 32) != (uint64_t)(*lv == T_BYTES)) why = "latest valid hash presence differs";
                else if (!rd64(out + 8) && *lv == T_BYTES && memcmp(out + 40, tv_bytes(lv, &blen), 32)) why = "latest valid hash differs";
                else if (!rd64(out + 8) && method == 2 && rd64(out + 72) != (uint64_t)(*pv == T_BYTES)) why = "payload id presence differs";
                else if (!rd64(out + 8) && *pv == T_BYTES && memcmp(out + 80, tv_bytes(pv, &blen), 8)) why = "payload id differs";
                else if (!rd64(out + 8) && method == 3 && rd64(out + 88) != tv_u64(tv_get(want, "capabilities"))) why = "capabilities differ";
                else if (!rd64(out + 8) && method == 4 && (rd64(out + 96) != tv_u64(tv_get(want, "result_offset")) ||
                                                          rd64(out + 104) != tv_u64(tv_get(want, "result_length")))) why = "result place differs";
            }
            if (!why && !guard_ok(out, 112)) why = "wrote past out";
            if (!why && !guard_ok(body, bsize)) why = "wrote past body";
            free(body);
            free(out);
        } else if (!strcmp(handler, "jwt_token")) {
            uint64_t iat = tv_u64(tv_get(in, "iat"));
            const uint8_t *secret = tv_bytes(tv_get(in, "secret"), &blen);
            size = 24 + 128;
            uint8_t *out = buffer(size), small[24 + 127];
            wr64(out, size);
            st = CALL(lantern_jwt_token, secret, &iat, fresh_scratch(), out);
            if (st) why = "status";
            else if (!list_holds(out, want)) why = "token differs";
            else if (!guard_ok(out, size)) why = "wrote past out";
            wr64(small, sizeof small);
            if (!why && CALL(lantern_jwt_token, secret, &iat, fresh_scratch(), small) != 1) why = "short out accepted";
            free(out);
        } else if (!strcmp(handler, "http_post")) {
            uint64_t hs, ts, bs, wl;
            uint8_t *host = byte_list(tv_get(in, "host"), &hs), *token = byte_list(tv_get(in, "token"), &ts);
            uint8_t *body = byte_list(tv_get(in, "body"), &bs);
            tv_bytes(want, &wl);
            size = 24 + wl;
            uint8_t *out = buffer(size), *small = buffer(size - 1);
            wr64(out, size);
            wr64(small, size - 1);
            st = CALL(lantern_http_post, host, token, body, out);
            if (st) why = "status";
            else if (!list_holds(out, want)) why = "request differs";
            else if (!guard_ok(out, size)) why = "wrote past out";
            else if (CALL(lantern_http_post, host, token, body, small) != 1) why = "short out accepted";
            free(host);
            free(token);
            free(body);
            free(out);
            free(small);
        } else if (!strcmp(handler, "http_parse_response")) {
            const uint8_t *b = tv_bytes(tv_get(in, "bytes"), &blen);
            uint64_t eof = tv_u64(tv_get(in, "eof")), isize, out[2] = {7, 7}, wl = 0;
            uint8_t *input = list_of(b, blen, 0, 0, &isize);
            if (*want == T_MAP) tv_bytes(tv_get(want, "body"), &wl);
            size = 24 + wl;
            uint8_t *body = buffer(size);
            wr64(body, size);
            st = CALL(lantern_http_parse_response, input, &eof, body, out);
            if (is_text(want, "more")) {
                if (st != HTTP_MORE) why = "status";
                else if (out[0] != 7) why = "wrote out";
            } else if (is_text(want, "invalid")) {
                if (st != INVALID_HTTP) why = "status";
            } else if (st) why = "status";
            else if (out[0] != tv_u64(tv_get(want, "status")) || out[1] != tv_u64(tv_get(want, "consumed"))) why = "status or consumed differs";
            else if (!list_holds(body, tv_get(want, "body"))) why = "body differs";
            else if (wl) {
                uint8_t *small = buffer(size - 1);
                wr64(small, size - 1);
                if (CALL(lantern_http_parse_response, input, &eof, small, out) != 1) why = "short body accepted";
                free(small);
            }
            if (!why && !guard_ok(body, size)) why = "wrote past body";
            free(input);
            free(body);
        } else why = "no such handler";
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Fuzzing */

#ifdef _WIN32
#include <windows.h>
#else
#include <signal.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

/*
 * LANTERN_FUZZ=N: after the cases of an http-request, json-decode or json-engine_decode file, N
 * inputs made from each case's input by 1 to 8 edits (xorshift64 from LANTERN_FUZZ_SEED, default
 * 1): a bit flipped, a byte set to a JSON or HTTP token byte or to any byte, bytes cut, bytes
 * repeated, a token byte put in, the input cut short. Each input ends at the end of a page with
 * no access after it, so a read past its length traps. The status must be one the function
 * documents, every guard byte must hold, and the parts of a valid answer must lie inside it. A
 * trap prints the input in hex and exits 3. First each case's own input in that layout: the
 * case's status.
 */
static uint64_t fuzz_rounds(void) {
    const char *n = getenv("LANTERN_FUZZ");
    return n ? strtoull(n, NULL, 10) : 0;
}

static uint64_t fuzz_state = 1;
static uint64_t fuzz_next(void) {
    fuzz_state ^= fuzz_state << 13;
    fuzz_state ^= fuzz_state >> 7;
    fuzz_state ^= fuzz_state << 17;
    return fuzz_state;
}

/* The input that runs now, for the trap report. */
static const uint8_t *fuzz_input;
static uint64_t fuzz_input_len;

#ifndef _WIN32
static void fuzz_trap(int sig) {
    static const char hex[] = "0123456789abcdef";
    char line[80];
    int n = snprintf(line, sizeof line, "CRASH signal %d on a fuzz input of %llu bytes:\n", sig, (unsigned long long)fuzz_input_len);
    if (write(2, line, (size_t)n) < 0) _exit(3);
    for (uint64_t k = 0; fuzz_input && k < fuzz_input_len; k++) {
        char two[2] = {hex[fuzz_input[k] >> 4], hex[fuzz_input[k] & 15]};
        if (write(2, two, 2) < 0) break;
    }
    if (write(2, "\n", 1) < 0) _exit(3);
    printf("CRASH: see the standard error\n");
    fflush(stdout);
    _exit(3);
}
#endif

/* A page of no access after a ByteList of len bytes, its last byte the last of the page before. */
typedef struct {
    uint8_t *base, *list;
    size_t total;
} fuzz_map;

static size_t fuzz_page(void) {
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwPageSize;
#else
    return (size_t)sysconf(_SC_PAGESIZE);
#endif
}

static uint8_t *fuzz_list(fuzz_map *m, const uint8_t *b, uint64_t len) {
    size_t page = fuzz_page(), need = 24 + (size_t)len;
    m->total = (need + page - 1) / page * page + page;
#ifdef _WIN32
    m->base = VirtualAlloc(NULL, m->total, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    DWORD old;
    if (!m->base || !VirtualProtect(m->base + m->total - page, page, PAGE_NOACCESS, &old)) {
        fprintf(stderr, "fuzz: no memory\n");
        exit(2);
    }
#else
    m->base = mmap(NULL, m->total, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m->base == MAP_FAILED || mprotect(m->base + m->total - page, page, PROT_NONE)) {
        fprintf(stderr, "fuzz: no memory\n");
        exit(2);
    }
#endif
    uint8_t *bytes = m->base + m->total - page - len;
    m->list = m->base;
    wr64(m->list, (uint64_t)(bytes - m->base) + len);
    wr64(m->list + 8, (uint64_t)(bytes - m->base));
    wr64(m->list + 16, len);
    if (len) memcpy(bytes, b, (size_t)len);
    fuzz_input = bytes;
    fuzz_input_len = len;
    return m->list;
}

static void fuzz_free(fuzz_map *m) {
#ifdef _WIN32
    VirtualFree(m->base, 0, MEM_RELEASE);
#else
    munmap(m->base, m->total);
#endif
    fuzz_input = NULL;
}

/* An input made from len bytes at in by 1 to 8 edits, in out of cap bytes: its length. */
static uint64_t fuzz_mutate(const uint8_t *in, uint64_t len, uint8_t *out, uint64_t cap) {
    static const char tokens[] = "{}[]\":,-.0123456789abcdefxX \r\n\t\\uE+/?&=;%";
    uint64_t n = len < cap ? len : cap;
    memcpy(out, in, (size_t)n);
    int edits = 1 + (int)(fuzz_next() % 8);
    for (int e = 0; e < edits; e++) {
        uint64_t r = fuzz_next(), at = n ? r % n : 0, k;
        switch ((r >> 32) % 8) {
        case 0:
            if (n) out[at] ^= (uint8_t)(1u << ((r >> 40) % 8));
            break;
        case 1:
        case 2:
            if (n) out[at] = (uint8_t)tokens[(r >> 40) % (sizeof tokens - 1)];
            break;
        case 3:
            if (n) out[at] = (uint8_t)(r >> 48);
            break;
        case 4:
            k = 1 + (r >> 40) % 16;
            if (at + k > n) k = n - at;
            memmove(out + at, out + at + k, (size_t)(n - at - k));
            n -= k;
            break;
        case 5:
            k = 1 + (r >> 40) % 64;
            if (at + k > n) k = n - at;
            if (n + k <= cap) {
                memmove(out + at + k, out + at, (size_t)(n - at));
                n += k;
            }
            break;
        case 6:
            if (n < cap) {
                memmove(out + at + 1, out + at, (size_t)(n - at));
                out[at] = (uint8_t)tokens[(r >> 40) % (sizeof tokens - 1)];
                n++;
            }
            break;
        default:
            if (n && (r >> 40) % 4 == 0) n = (r >> 44) % n;
            break;
        }
    }
    return n;
}

static void fuzz_start(void) {
    const char *seed = getenv("LANTERN_FUZZ_SEED");
    fuzz_state = seed ? strtoull(seed, NULL, 10) : 1;
    if (!fuzz_state) fuzz_state = 1;
#ifndef _WIN32
    signal(SIGSEGV, fuzz_trap);
    signal(SIGBUS, fuzz_trap);
#endif
}

static void fuzz_end(void) {
#ifndef _WIN32
    signal(SIGSEGV, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
#endif
}

/* The fuzz inputs of the http-request cases (lantern_http_request). */
static void fuzz_http(const char *file, case_file *f) {
    uint64_t rounds = fuzz_rounds(), runs = 0;
    if (!rounds) return;
    fuzz_start();
    static char msg[256];
    const char *why = NULL;
    f->at = 16;
    for (uint64_t i = 0; i < f->count && !why; i++) {
        const char *name;
        uint64_t len, blen;
        tv parts = next_case(f, &name, &len);
        const uint8_t *b = tv_bytes(tv_get(parts, "bytes"), &blen);
        uint64_t cap = blen + 1024, limits[2] = {tv_u64(tv_get(parts, "head_max")), tv_u64(tv_get(parts, "body_max"))};
        uint8_t *in = xmalloc((size_t)cap);
        {
            tv osz = tv_get(parts, "out_size");
            uint64_t osize = osz ? tv_u64(osz) : HTTP_REQUEST_FIXED + 64;
            fuzz_map m;
            uint8_t *l = fuzz_list(&m, b, blen), *lim = buffer(16), *out = buffer(osize);
            wr64(lim, limits[0]);
            wr64(lim + 8, limits[1]);
            wr64(out, osize);
            if (CALL(lantern_http_request, l, lim, out) != tv_u64(tv_get(parts, "status"))) why = "a case's own input at the end of a page: not the case's status";
            fuzz_free(&m);
            free(lim);
            free(out);
        }
        for (uint64_t r = 0; r < rounds && !why; r++, runs++) {
            uint64_t n = fuzz_mutate(b, blen, in, cap), osize = HTTP_REQUEST_FIXED + 64 + (fuzz_next() % 2 ? n + 64 : 0);
            fuzz_map m;
            uint8_t *l = fuzz_list(&m, in, n), *lim = buffer(16), *out = buffer(osize);
            wr64(lim, limits[0]);
            wr64(lim + 8, limits[1]);
            wr64(out, osize);
            uint64_t st = CALL(lantern_http_request, l, lim, out);
            if (!guard_ok(out, osize) || !guard_ok(lim, 16)) why = "lantern_http_request wrote out of bounds";
            else if (st != 0 && st != 1 && st != HTTP_INVALID_STATUS && st != HTTP_MORE_STATUS) {
                snprintf(msg, sizeof msg, "status %llu", (unsigned long long)st);
                why = msg;
            } else if (st == 0) {
                if (rd64(out + 16) > n) why = "used is past the input";
                for (int k = 0; k < 6 && !why; k++) {
                    uint64_t off = rd64(out + 48 + 16 * k), cnt = rd64(out + 56 + 16 * k);
                    if (cnt && (off < HTTP_REQUEST_FIXED || off > osize || cnt > osize - off)) why = "a part lies outside out";
                }
            }
            if (why) {
                fprintf(stderr, "fuzz input of %s round %llu (%llu bytes):", file, (unsigned long long)r, (unsigned long long)n);
                for (uint64_t k = 0; k < n; k++) fprintf(stderr, "%02x", in[k]);
                fprintf(stderr, "\n");
            }
            fuzz_free(&m);
            free(lim);
            free(out);
        }
        free(in);
    }
    fuzz_end();
    report(file, "fuzz", 4, !why, why);
    if (!why) printf("NOTE: %llu fuzz inputs of %s\n", (unsigned long long)runs, file);
}

/* The fuzz inputs of the json-decode or json-engine_decode cases (lantern_json_decode). */
static void fuzz_json(const char *file, case_file *f, int engine) {
    ABI uint64_t (*decode_fn)(const void *, const void *, void *, void *, void *) = engine ? lantern_engine_json_decode : lantern_json_decode;
    uint64_t rounds = fuzz_rounds(), runs = 0;
    if (!rounds) return;
    fuzz_start();
    static char msg[256];
    const char *why = NULL;
    f->at = 16;
    for (uint64_t i = 0; i < f->count && !why; i++) {
        const char *name;
        uint64_t len, tlen, jlen;
        tv parts = next_case(f, &name, &len);
        const uint8_t *tn = tv_bytes(tv_get(parts, "type"), &tlen), *json = tv_bytes(tv_get(parts, "json"), &jlen);
        char tname[128];
        snprintf(tname, sizeof tname, "%.*s", (int)(tlen < 120 ? tlen : 120), (const char *)tn);
        const uint8_t *desc = type_by_name(tname);
        if (!desc) continue;
        uint64_t cap = jlen + 1024, slen = 0;
        uint8_t *in = xmalloc((size_t)cap);
        tv want = tv_get(parts, "ssz");
        if (want) tv_bytes(want, &slen);
        {
            uint64_t osize = 24 + slen + 64;
            fuzz_map m;
            uint8_t *l = fuzz_list(&m, json, jlen), *scratch = buffer(JSON_DECODE_SCRATCH), *fault = buffer(JSON_FAULT_BYTES), *out = buffer(osize);
            wr64(scratch, JSON_DECODE_SCRATCH);
            wr64(out, osize);
            if (CALL(decode_fn, desc, l, scratch, out, fault) != (want ? 0 : JSON_INVALID_STATUS))
                why = "a case's own input at the end of a page: not the case's status";
            fuzz_free(&m);
            free(scratch);
            free(fault);
            free(out);
        }
        for (uint64_t r = 0; r < rounds && !why; r++, runs++) {
            uint64_t n = fuzz_mutate(json, jlen, in, cap), osize = 24 + 2 * n + 256;
            fuzz_map m;
            uint8_t *l = fuzz_list(&m, in, n), *scratch = buffer(JSON_DECODE_SCRATCH), *fault = buffer(JSON_FAULT_BYTES), *out = buffer(osize);
            wr64(scratch, JSON_DECODE_SCRATCH);
            wr64(out, osize);
            uint64_t st = CALL(decode_fn, desc, l, scratch, out, fault);
            if (!guard_ok(out, osize) || !guard_ok(fault, JSON_FAULT_BYTES) || !guard_ok(scratch, JSON_DECODE_SCRATCH))
                why = "lantern_json_decode wrote out of bounds";
            else if (st != 0 && st != 1 && st != JSON_INVALID_STATUS) {
                snprintf(msg, sizeof msg, "status %llu", (unsigned long long)st);
                why = msg;
            } else if (st == 0 && (rd64(out + 8) != 24 || rd64(out + 16) > osize - 24)) why = "the SSZ bytes lie outside out";
            else if (st == JSON_INVALID_STATUS && rd64(fault + 8) > n) why = "the fault's offset is past the input";
            if (why) {
                fprintf(stderr, "fuzz input of %s, type %s, round %llu (%llu bytes): %.*s\n", file, tname, (unsigned long long)r,
                        (unsigned long long)n, (int)n, (const char *)in);
            }
            fuzz_free(&m);
            free(scratch);
            free(fault);
            free(out);
        }
        free(in);
    }
    fuzz_end();
    report(file, "fuzz", 4, !why, why);
    if (!why) printf("NOTE: %llu fuzz inputs of %s\n", (unsigned long long)runs, file);
}

/* ---------------------------------------------------------------- Main */

#ifdef _WIN32
#include <windows.h>
/*
 * A crash on Windows: the exception, its address as an offset into the runner's image (to read
 * with llvm-nm of the build), the link register or the return address, the data address, and
 * the file and case that ran.
 */
static LONG WINAPI crash_report(EXCEPTION_POINTERS *e) {
    uintptr_t base = (uintptr_t)GetModuleHandleW(NULL), at = (uintptr_t)e->ExceptionRecord->ExceptionAddress;
    uintptr_t data = e->ExceptionRecord->NumberParameters > 1 ? (uintptr_t)e->ExceptionRecord->ExceptionInformation[1] : 0;
#if defined(__aarch64__) || defined(_M_ARM64)
    uintptr_t back = (uintptr_t)e->ContextRecord->Lr, sp = (uintptr_t)e->ContextRecord->Sp;
#else
    uintptr_t sp = (uintptr_t)e->ContextRecord->Rsp, back = *(uintptr_t *)sp;
#endif
    fprintf(stderr, "CRASH code 0x%lx at image + 0x%llx (link image + 0x%llx), data 0x%llx, sp 0x%llx, file %s, case %.*s\n",
            (unsigned long)e->ExceptionRecord->ExceptionCode, (unsigned long long)(at - base),
            (unsigned long long)(back - base), (unsigned long long)data, (unsigned long long)sp, current_file,
            (int)current_case_len, current_case);
    if (fuzz_input) { /* a fuzz input: in hex */
        fprintf(stderr, "on a fuzz input of %llu bytes:\n", (unsigned long long)fuzz_input_len);
        for (uint64_t k = 0; k < fuzz_input_len; k++) fprintf(stderr, "%02x", fuzz_input[k]);
        fprintf(stderr, "\n");
    }
    printf("CRASH: see the standard error\n");
    fflush(stderr);
    fflush(stdout);
    return EXCEPTION_EXECUTE_HANDLER;
}
#endif

#ifdef LANTERN_SHA_VARIANT
/* The CPU features of asm-crypto's sha variant (README, Target profile). */
#if defined(__x86_64__)
#include <cpuid.h>
static int sha_variant_supported(void) {
    unsigned a, b, c, d;
    if (!__get_cpuid(1, &a, &b, &c, &d) || !(c & bit_SSSE3)) return 0;
    if (!__get_cpuid_count(7, 0, &a, &b, &c, &d)) return 0;
    return (b & bit_SHA) != 0;
}
#elif defined(_WIN32)
static int sha_variant_supported(void) { return IsProcessorFeaturePresent(PF_ARM_V8_CRYPTO_INSTRUCTIONS_AVAILABLE) != 0; }
#elif defined(__APPLE__)
#include <sys/sysctl.h>
static int sha_variant_supported(void) {
    int v = 0;
    size_t n = sizeof v;
    return sysctlbyname("hw.optional.arm.FEAT_SHA256", &v, &n, NULL, 0) == 0 && v == 1;
}
#else
#include <sys/auxv.h>
static int sha_variant_supported(void) { return (getauxval(AT_HWCAP) & (1UL << 6)) != 0; }   /* HWCAP_SHA2 */
#endif
#endif

int main(int argc, char **argv) {
#ifdef _WIN32
    SetUnhandledExceptionFilter(crash_report);
#endif
    if (argc < 3) {
        fprintf(stderr, "usage: %s VECTOR_DIR FILE ...\n", argv[0]);
        return 2;
    }
#ifdef LANTERN_SHA_VARIANT
    if (!sha_variant_supported()) {
        printf("SKIP the sha variant: this CPU lacks its features\n");
        printf("PASS: 0 passed, 0 failed\n");
        return 0;
    }
#endif
    load_config(argv[1]);
    const char *prefix = PRESET "-" STR(FORK_NAME) "-";
    size_t plen = strlen(prefix);
    for (int a = 2; a < argc; a++) {
        const char *file = argv[a];
        if (strncmp(file, prefix, plen)) continue;
        NOTE_FILE(file);
        char kind[256];
        snprintf(kind, sizeof kind, "%s", file + plen);
        char *dot = strstr(kind, ".bin");
        if (dot) *dot = 0;
        case_file f;
        if (!read_file(argv[1], file, &f)) {
            printf("FAIL %s: cannot read\n", file);
            failures++;
            continue;
        }
        int before = failures, ran = passes, skips = skipped;
        /* The signatures-off runner runs only the handlers whose cases can have bls_setting 2. */
        if (!bls_off && !strcmp(kind, "descriptors")) run_descriptors(file, &f);
        else if (!bls_off && !strncmp(kind, "ssz_static-", 11)) run_ssz_static(file, kind + 11, &f);
        else if (!bls_off && !strncmp(kind, "epoch_processing-", 17)) run_epoch(file, kind + 17, &f);
        else if (!bls_off && !strcmp(kind, "shuffling-core")) run_shuffling(file, &f);
        else if (!strncmp(kind, "operations-", 11)) run_operations(file, kind + 11, &f);
        else if (!bls_off && !strcmp(kind, "sanity-slots")) run_slots(file, &f);
        else if (!strcmp(kind, "sanity-blocks") || !strcmp(kind, "finality-finality") || !strcmp(kind, "random-random"))
            run_blocks(file, &f);
        else if (!bls_off && !strncmp(kind, "rewards-", 8)) run_rewards(file, &f);
#if FORK > FORK_PHASE0
        else if (!bls_off && !strcmp(kind, "fork-fork")) run_fork(file, &f);
        else if (!strcmp(kind, "transition-core")) run_transition(file, argv[1], &f);
#else
        else if (!bls_off && !strcmp(kind, "genesis-initialization")) run_genesis_init(file, &f);
        else if (!bls_off && !strcmp(kind, "genesis-validity")) run_genesis_validity(file, &f);
#endif
        else if (!strncmp(kind, "fork_choice-", 12)) run_fork_choice(file, argv[1], &f, 0);
        else if (!strncmp(kind, "fork_choice_compliance-", 23)) run_fork_choice(file, argv[1], &f, 1);
        else if (!bls_off && !strcmp(kind, "sync-optimistic")) run_fork_choice(file, argv[1], &f, 0);
        else if (!bls_off && !strncmp(kind, "networking-gossip_", 18)) run_gossip(file, argv[1], kind + 18, &f);
        else if (!bls_off && !strncmp(kind, "p2p-", 4)) run_p2p(file, kind + 4, &f);
        else if (!bls_off && !strncmp(kind, "reqresp-", 8)) run_reqresp(file, kind + 8, &f);
        else if (!bls_off && !strncmp(kind, "engine-", 7)) run_engine(file, kind + 7, &f);
        else if (!bls_off && !strcmp(kind, "node-p2p")) run_node_p2p(file, &f);
        else if (!bls_off && !strcmp(kind, "config-parse")) run_config_parse(file, &f);
        else if (!bls_off && !strcmp(kind, "app-options")) run_app_options(file, &f);
        else if (!bls_off && !strcmp(kind, "node-api")) run_node_api(file, &f);
        else if (!bls_off && !strcmp(kind, "node-payload")) run_node_payload(file, &f);
        else if (!bls_off && !strcmp(kind, "node-liveness")) run_node_liveness(file, &f);
        else if (!bls_off && !strcmp(kind, "node-rewards")) run_node_rewards(file, &f);
        else if (!bls_off && !strcmp(kind, "node-attrewards")) run_node_attrewards(file, &f);
        else if (!bls_off && (!strcmp(kind, "node-produce") || !strcmp(kind, "node-publish"))) run_node_produce(file, argv[1], &f);
        else if (!bls_off && !strcmp(kind, "json-encode")) run_json_encode(file, &f);
        else if (!bls_off && !strcmp(kind, "json-decode")) {
            run_json_decode(file, &f, 0);
            fuzz_json(file, &f, 0);
        } else if (!bls_off && !strcmp(kind, "json-engine_decode")) {
            run_json_decode(file, &f, 1);
            fuzz_json(file, &f, 1);
        } else if (!bls_off && !strcmp(kind, "http-request")) {
            run_http_request(file, &f);
            fuzz_http(file, &f);
        }
        else if (!bls_off && !strcmp(kind, "api-route")) run_api_route(file, &f);
        else if (!bls_off && !strcmp(kind, "db-index")) run_db_index(file, &f);
        else if (!bls_off && !strcmp(kind, "db-state_diff")) run_db_state_diff(file, &f);
        else if (!bls_off && !strncmp(kind, "eth1-", 5)) run_eth1(file, kind, &f);
#if FORK == FORK_FULU
        else if (!bls_off && (!strcmp(kind, "networking-get_custody_groups") ||
                              !strcmp(kind, "networking-compute_columns_for_custody_group")))
            run_custody(file, kind + 11, &f);
#endif
#if FORK >= FORK_DENEB
        else if (!bls_off && !strcmp(kind, "merkle_proof-single_merkle_proof")) run_merkle_proof(file, &f);
#endif
#if FORK >= FORK_ALTAIR
        else if (!bls_off && !strcmp(kind, "light_client-single_merkle_proof")) run_lc_merkle_proof(file, &f);
        else if (!bls_off && !strcmp(kind, "light_client-update_ranking")) run_lc_update_ranking(file, &f);
        else if (!bls_off && !strcmp(kind, "light_client-data_collection")) run_lc_data_collection(file, &f);
#endif
        else if (!bls_off && !strcmp(kind, "lc-header")) run_lc_header(file, &f);
        else {
            if (!bls_off) printf("SKIP %s: the runner has no handler for it\n", file);
            free(f.data);
            continue;
        }
        if (bls_off && passes == ran && failures == before) { /* every case skipped */
            free(f.data);
            continue;
        }
        printf("%s %s: %d passed, %d failed", failures == before ? "PASS" : "FAIL", file, passes - ran,
               failures - before);
        if (skipped > skips) printf(", %d skipped (bls_setting)", skipped - skips);
        printf("\n");
        free(f.data);
    }
    for (int i = 0; i < stats_count; i++) {
        int bad = stats[i].fault || stats[i].peak > STACK_CAP;
        printf("STACK %s %llu bytes%s\n", stats[i].name, (unsigned long long)stats[i].peak, bad ? " ABI FAULT" : "");
        if (bad) failures++;
    }
    if (node_settles_finalized) printf("NOTE: %lu node settles past a finalized epoch\n", node_settles_finalized);
    if (api_heads_streamed) printf("NOTE: %lu heads served as getBlockV2 and getStateV2 streams\n", api_heads_streamed);
    if (reads_asked) printf("NOTE: %lu node-reads requests answered\n", reads_asked);
    if (engine_fcu_errors) printf("NOTE: %lu engine_forkchoiceUpdated answered Too deep reorg on syncs\n", engine_fcu_errors);
    if (inbound_room_checked) printf("NOTE: the open room checked on %lu cases\n", inbound_room_checked);
    if (request_age_checks) printf("NOTE: %lu node steps with no request older than NODE_REQUEST_MS\n", request_age_checks);
    if (idle_peer_checks) printf("NOTE: %lu node steps with no BeaconBlocksByRange to a peer that serves none of it\n", idle_peer_checks);
    if (status_refresh_checked) printf("NOTE: the Status refresh checked on %lu cases\n", status_refresh_checked);
#if FORK >= FORK_FULU
    if (column_room_checked) printf("NOTE: the column dials and the spare peer checked on %lu cases\n", column_room_checked);
#endif
    if (api_peers_checked[0] || api_peers_checked[1])
        printf("NOTE: getPeers and getPeer checked after %lu inbound and %lu outbound connections\n", api_peers_checked[0],
               api_peers_checked[1]);
    if (api_sidecars_checked) printf("NOTE: the sidecars of %lu blocks checked through the Beacon API\n", api_sidecars_checked);
    if (api_blobs_checked) printf("NOTE: the blobs of %lu blocks checked through getBlobs\n", api_blobs_checked);
    if (api_headers_asked) printf("NOTE: %lu getBlockHeaders answers checked, %lu with a Db block\n", api_headers_asked, api_headers_db);
    if (api_fork_choice_200 || api_fork_choice_500)
        printf("NOTE: getDebugForkChoice answered 200 %lu times, 500 %lu times\n", api_fork_choice_200, api_fork_choice_500);
    if (api_lookups) printf("NOTE: %lu lookups of a block or a state by slot or root\n", api_lookups);
    if (node_replays) printf("NOTE: %lu post-states the nodes rebuilt by replay\n", node_replays);
    if (gshare_works) printf("NOTE: %lu gossip blocks and sidecars checked with %lu proposer states\n", gshare_works, gshare_states);
    if (head_due_checks) printf("NOTE: %lu node steps whose head was not due matched get_head\n", head_due_checks);
    if (gossip_votes) printf("NOTE: %lu of %lu valid attestations went to fork choice as gossip aggregates\n", gossip_votes_applied, gossip_votes);
    if (drop_ran) printf("NOTE: the sidecar drop check passed\n");
    if (json_types_skipped) printf("NOTE: %lu JSON cases of types lantern does not define\n", json_types_skipped);
    if (cached_roots) printf("NOTE: %lu post states hashed alike with and without the state cache\n", cached_roots);
#if FORK > FORK_PHASE0
    if (node_transitions) printf("NOTE: %lu transition cases through the node\n", node_transitions);
#endif
    if (node_db_records) printf("NOTE: %lu Db records archived, %lu served from the Db, %lu anchors saved and read back\n", node_db_records, node_db_serves, node_db_states);
#if FORK >= FORK_FULU
    if (custody_raises) printf("NOTE: %lu custody raises checked\n", custody_raises);
#endif
    if (node_recons) printf("NOTE: %lu blocks of columns rebuilt from half of them\n", node_recons);
    if (api_duty_epochs) printf("NOTE: %lu duties of epochs from the anchor's to the head's asked\n", api_duty_epochs);
    if (node_db_archives) printf("NOTE: %lu state records archived, %lu states loaded from them, %lu old states asked after them\n", node_db_archives, node_db_loads, api_archive_states);
    printf("%s: %d passed, %d failed\n", failures ? "FAIL" : "PASS", passes, failures);
    return failures ? 1 : 0;
}
