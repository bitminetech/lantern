/*
 * The SSZ types of one fork, from consensus-specs v1.7.0-beta.4 (aa16bb4):
 * each type of the fork TYPES_FORK (include/forks.inc) at its latest
 * definition in phase0 to that fork, under the names that SSZ_NAMES sets
 * (include/ssz_types.inc). Types come before the types that hold them. Needs
 * ssz.inc, ssz_types.inc, preset.inc, lantern.inc and forks.inc first. The
 * layout of each value is asm-ssz's Value; the field offsets that this file
 * sets, T_field, are offsets in such a value.
 *
 * Aliases of one layout share one name here: Slot, Epoch, Gwei,
 * ValidatorIndex, CommitteeIndex, WithdrawalIndex, BlobIndex, ColumnIndex,
 * RowIndex and SubnetID are Uint64; Root, Hash32, Domain and Bytes32 are
 * Bytes32; Version, DomainType and ForkDigest are Bytes4; ExecutionAddress
 * is Bytes20; BLSPubkey, KZGCommitment and KZGProof are Bytes48;
 * BLSSignature is Bytes96; ParticipationFlags is Uint8.
 */

/* ------------------------------------------------------------ Basic types */

SSZ_UINT Uint8, 1
SSZ_UINT Uint64, 8
SSZ_UINT Uint256, 32
SSZ_BOOLEAN Boolean
SSZ_BYTE_VECTOR Bytes4, 4
SSZ_BYTE_VECTOR Bytes20, 20
SSZ_BYTE_VECTOR Bytes32, 32
SSZ_BYTE_VECTOR Bytes48, 48
SSZ_BYTE_VECTOR Bytes96, 96

/* ------------------------------------------------------------ Byte and bit strings */

SSZ_BIT_VECTOR JustificationBits, JUSTIFICATION_BITS_LENGTH
SSZ_BIT_VECTOR Attnets, ATTESTATION_SUBNET_COUNT
.if TYPES_FORK >= FORK_ELECTRA
SSZ_BIT_LIST AggregationBits, MAX_VALIDATORS_PER_COMMITTEE * MAX_COMMITTEES_PER_SLOT
SSZ_BIT_VECTOR CommitteeBits, MAX_COMMITTEES_PER_SLOT
.else
SSZ_BIT_LIST AggregationBits, MAX_VALIDATORS_PER_COMMITTEE
.endif
.if TYPES_FORK >= FORK_ALTAIR
SSZ_BIT_VECTOR SyncCommitteeBits, SYNC_COMMITTEE_SIZE
SSZ_BIT_VECTOR SyncSubcommitteeBits, SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
SSZ_BIT_VECTOR Syncnets, SYNC_COMMITTEE_SUBNET_COUNT
.endif
.if TYPES_FORK >= FORK_BELLATRIX
SSZ_BYTE_VECTOR LogsBloom, BYTES_PER_LOGS_BLOOM
SSZ_BYTE_LIST ExtraData, MAX_EXTRA_DATA_BYTES
SSZ_BYTE_LIST Transaction, MAX_BYTES_PER_TRANSACTION
.endif
.if TYPES_FORK == FORK_DENEB || TYPES_FORK == FORK_ELECTRA
SSZ_BYTE_VECTOR Blob, BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_BLOB
.endif
.if TYPES_FORK >= FORK_FULU
SSZ_BYTE_VECTOR Cell, BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_CELL
SSZ_BIT_LIST CellsBitList, MAX_BLOB_COMMITMENTS_PER_BLOCK
.endif

/* ------------------------------------------------------------ Vectors and lists of basic and byte types */

SSZ_VECTOR BlockRoots, Bytes32, SLOTS_PER_HISTORICAL_ROOT          /* also StateRoots */
SSZ_LIST HistoricalRoots, Bytes32, HISTORICAL_ROOTS_LIMIT
SSZ_VECTOR RandaoMixes, Bytes32, EPOCHS_PER_HISTORICAL_VECTOR
SSZ_VECTOR Slashings, Uint64, EPOCHS_PER_SLASHINGS_VECTOR
SSZ_LIST Balances, Uint64, VALIDATOR_REGISTRY_LIMIT              /* also InactivityScores */
SSZ_VECTOR DepositProof, Bytes32, DEPOSIT_CONTRACT_TREE_DEPTH + 1
.if TYPES_FORK >= FORK_ELECTRA
SSZ_LIST AttestingIndices, Uint64, MAX_VALIDATORS_PER_COMMITTEE * MAX_COMMITTEES_PER_SLOT
.else
SSZ_LIST AttestingIndices, Uint64, MAX_VALIDATORS_PER_COMMITTEE
.endif
.if TYPES_FORK >= FORK_ALTAIR
SSZ_LIST EpochParticipation, Uint8, VALIDATOR_REGISTRY_LIMIT
SSZ_VECTOR SyncCommitteePubkeys, Bytes48, SYNC_COMMITTEE_SIZE
.endif
.if TYPES_FORK >= FORK_BELLATRIX
SSZ_LIST Transactions, Transaction, MAX_TRANSACTIONS_PER_PAYLOAD
.endif
.if TYPES_FORK >= FORK_DENEB
SSZ_LIST BlobKZGCommitments, Bytes48, MAX_BLOB_COMMITMENTS_PER_BLOCK  /* also KZGProofs */
.endif
.if TYPES_FORK == FORK_DENEB || TYPES_FORK == FORK_ELECTRA
SSZ_VECTOR KZGCommitmentInclusionProof, Bytes32, KZG_COMMITMENT_INCLUSION_PROOF_DEPTH
.endif
.if TYPES_FORK >= FORK_FULU
SSZ_VECTOR ProposerLookahead, Uint64, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH
SSZ_LIST DataColumn, Cell, MAX_BLOB_COMMITMENTS_PER_BLOCK
SSZ_VECTOR KZGCommitmentsInclusionProof, Bytes32, KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH
SSZ_LIST DataColumnIndices, Uint64, NUMBER_OF_COLUMNS
.endif

/* ------------------------------------------------------------ Containers of fixed size */

SSZ_CONTAINER Fork, 0
SSZ_FIELD Fork, previous_version, Bytes4
SSZ_FIELD Fork, current_version, Bytes4
SSZ_FIELD Fork, epoch, Uint64
SSZ_END Fork

SSZ_CONTAINER ForkData, 0
SSZ_FIELD ForkData, current_version, Bytes4
SSZ_FIELD ForkData, genesis_validators_root, Bytes32
SSZ_END ForkData

SSZ_CONTAINER Checkpoint, 0
SSZ_FIELD Checkpoint, epoch, Uint64
SSZ_FIELD Checkpoint, root, Bytes32
SSZ_END Checkpoint

SSZ_CONTAINER Validator, 0
SSZ_FIELD Validator, pubkey, Bytes48
SSZ_FIELD Validator, withdrawal_credentials, Bytes32
SSZ_FIELD Validator, effective_balance, Uint64
SSZ_FIELD Validator, slashed, Boolean
SSZ_FIELD Validator, activation_eligibility_epoch, Uint64
SSZ_FIELD Validator, activation_epoch, Uint64
SSZ_FIELD Validator, exit_epoch, Uint64
SSZ_FIELD Validator, withdrawable_epoch, Uint64
SSZ_END Validator

SSZ_CONTAINER AttestationData, 0
SSZ_FIELD AttestationData, slot, Uint64
SSZ_FIELD AttestationData, index, Uint64
SSZ_FIELD AttestationData, beacon_block_root, Bytes32
SSZ_FIELD AttestationData, source, Checkpoint
SSZ_FIELD AttestationData, target, Checkpoint
SSZ_END AttestationData

SSZ_CONTAINER Eth1Data, 0
SSZ_FIELD Eth1Data, deposit_root, Bytes32
SSZ_FIELD Eth1Data, deposit_count, Uint64
SSZ_FIELD Eth1Data, block_hash, Bytes32
SSZ_END Eth1Data

SSZ_CONTAINER DepositMessage, 0
SSZ_FIELD DepositMessage, pubkey, Bytes48
SSZ_FIELD DepositMessage, withdrawal_credentials, Bytes32
SSZ_FIELD DepositMessage, amount, Uint64
SSZ_END DepositMessage

SSZ_CONTAINER DepositData, 0
SSZ_FIELD DepositData, pubkey, Bytes48
SSZ_FIELD DepositData, withdrawal_credentials, Bytes32
SSZ_FIELD DepositData, amount, Uint64
SSZ_FIELD DepositData, signature, Bytes96
SSZ_END DepositData

SSZ_CONTAINER BeaconBlockHeader, 0
SSZ_FIELD BeaconBlockHeader, slot, Uint64
SSZ_FIELD BeaconBlockHeader, proposer_index, Uint64
SSZ_FIELD BeaconBlockHeader, parent_root, Bytes32
SSZ_FIELD BeaconBlockHeader, state_root, Bytes32
SSZ_FIELD BeaconBlockHeader, body_root, Bytes32
SSZ_END BeaconBlockHeader

SSZ_CONTAINER SignedBeaconBlockHeader, 0
SSZ_FIELD SignedBeaconBlockHeader, message, BeaconBlockHeader
SSZ_FIELD SignedBeaconBlockHeader, signature, Bytes96
SSZ_END SignedBeaconBlockHeader

SSZ_CONTAINER SigningData, 0
SSZ_FIELD SigningData, object_root, Bytes32
SSZ_FIELD SigningData, domain, Bytes32
SSZ_END SigningData

SSZ_CONTAINER ProposerSlashing, 0
SSZ_FIELD ProposerSlashing, signed_header_1, SignedBeaconBlockHeader
SSZ_FIELD ProposerSlashing, signed_header_2, SignedBeaconBlockHeader
SSZ_END ProposerSlashing

SSZ_CONTAINER Deposit, 0
SSZ_FIELD Deposit, proof, DepositProof
SSZ_FIELD Deposit, data, DepositData
SSZ_END Deposit

SSZ_CONTAINER VoluntaryExit, 0
SSZ_FIELD VoluntaryExit, epoch, Uint64
SSZ_FIELD VoluntaryExit, validator_index, Uint64
SSZ_END VoluntaryExit

SSZ_CONTAINER SignedVoluntaryExit, 0
SSZ_FIELD SignedVoluntaryExit, message, VoluntaryExit
SSZ_FIELD SignedVoluntaryExit, signature, Bytes96
SSZ_END SignedVoluntaryExit

.if TYPES_FORK <= FORK_BELLATRIX
SSZ_CONTAINER HistoricalBatch, 0
SSZ_FIELD HistoricalBatch, block_roots, BlockRoots
SSZ_FIELD HistoricalBatch, state_roots, BlockRoots
SSZ_END HistoricalBatch
.endif

.if TYPES_FORK >= FORK_ALTAIR
SSZ_CONTAINER SyncAggregate, 0
SSZ_FIELD SyncAggregate, sync_committee_bits, SyncCommitteeBits
SSZ_FIELD SyncAggregate, sync_committee_signature, Bytes96
SSZ_END SyncAggregate

SSZ_CONTAINER SyncCommittee, 0
SSZ_FIELD SyncCommittee, pubkeys, SyncCommitteePubkeys
SSZ_FIELD SyncCommittee, aggregate_pubkey, Bytes48
SSZ_END SyncCommittee

SSZ_CONTAINER SyncCommitteeMessage, 0
SSZ_FIELD SyncCommitteeMessage, slot, Uint64
SSZ_FIELD SyncCommitteeMessage, beacon_block_root, Bytes32
SSZ_FIELD SyncCommitteeMessage, validator_index, Uint64
SSZ_FIELD SyncCommitteeMessage, signature, Bytes96
SSZ_END SyncCommitteeMessage

SSZ_CONTAINER SyncCommitteeContribution, 0
SSZ_FIELD SyncCommitteeContribution, slot, Uint64
SSZ_FIELD SyncCommitteeContribution, beacon_block_root, Bytes32
SSZ_FIELD SyncCommitteeContribution, subcommittee_index, Uint64
SSZ_FIELD SyncCommitteeContribution, aggregation_bits, SyncSubcommitteeBits
SSZ_FIELD SyncCommitteeContribution, signature, Bytes96
SSZ_END SyncCommitteeContribution

SSZ_CONTAINER ContributionAndProof, 0
SSZ_FIELD ContributionAndProof, aggregator_index, Uint64
SSZ_FIELD ContributionAndProof, contribution, SyncCommitteeContribution
SSZ_FIELD ContributionAndProof, selection_proof, Bytes96
SSZ_END ContributionAndProof

SSZ_CONTAINER SignedContributionAndProof, 0
SSZ_FIELD SignedContributionAndProof, message, ContributionAndProof
SSZ_FIELD SignedContributionAndProof, signature, Bytes96
SSZ_END SignedContributionAndProof

SSZ_CONTAINER SyncAggregatorSelectionData, 0
SSZ_FIELD SyncAggregatorSelectionData, slot, Uint64
SSZ_FIELD SyncAggregatorSelectionData, subcommittee_index, Uint64
SSZ_END SyncAggregatorSelectionData
.endif

.if TYPES_FORK >= FORK_CAPELLA
SSZ_CONTAINER Withdrawal, 0
SSZ_FIELD Withdrawal, index, Uint64
SSZ_FIELD Withdrawal, validator_index, Uint64
SSZ_FIELD Withdrawal, address, Bytes20
SSZ_FIELD Withdrawal, amount, Uint64
SSZ_END Withdrawal

SSZ_CONTAINER BLSToExecutionChange, 0
SSZ_FIELD BLSToExecutionChange, validator_index, Uint64
SSZ_FIELD BLSToExecutionChange, from_bls_pubkey, Bytes48
SSZ_FIELD BLSToExecutionChange, to_execution_address, Bytes20
SSZ_END BLSToExecutionChange

SSZ_CONTAINER SignedBLSToExecutionChange, 0
SSZ_FIELD SignedBLSToExecutionChange, message, BLSToExecutionChange
SSZ_FIELD SignedBLSToExecutionChange, signature, Bytes96
SSZ_END SignedBLSToExecutionChange

SSZ_CONTAINER HistoricalSummary, 0
SSZ_FIELD HistoricalSummary, block_summary_root, Bytes32
SSZ_FIELD HistoricalSummary, state_summary_root, Bytes32
SSZ_END HistoricalSummary
.endif

.if TYPES_FORK == FORK_DENEB || TYPES_FORK == FORK_ELECTRA
SSZ_CONTAINER BlobSidecar, 0
SSZ_FIELD BlobSidecar, index, Uint64
SSZ_FIELD BlobSidecar, blob, Blob
SSZ_FIELD BlobSidecar, kzg_commitment, Bytes48
SSZ_FIELD BlobSidecar, kzg_proof, Bytes48
SSZ_FIELD BlobSidecar, signed_block_header, SignedBeaconBlockHeader
SSZ_FIELD BlobSidecar, kzg_commitment_inclusion_proof, KZGCommitmentInclusionProof
SSZ_END BlobSidecar

SSZ_CONTAINER BlobIdentifier, 0
SSZ_FIELD BlobIdentifier, block_root, Bytes32
SSZ_FIELD BlobIdentifier, index, Uint64
SSZ_END BlobIdentifier
.endif

.if TYPES_FORK >= FORK_ELECTRA
SSZ_CONTAINER PendingDeposit, 0
SSZ_FIELD PendingDeposit, pubkey, Bytes48
SSZ_FIELD PendingDeposit, withdrawal_credentials, Bytes32
SSZ_FIELD PendingDeposit, amount, Uint64
SSZ_FIELD PendingDeposit, signature, Bytes96
SSZ_FIELD PendingDeposit, slot, Uint64
SSZ_END PendingDeposit

SSZ_CONTAINER PendingPartialWithdrawal, 0
SSZ_FIELD PendingPartialWithdrawal, validator_index, Uint64
SSZ_FIELD PendingPartialWithdrawal, amount, Uint64
SSZ_FIELD PendingPartialWithdrawal, withdrawable_epoch, Uint64
SSZ_END PendingPartialWithdrawal

SSZ_CONTAINER PendingConsolidation, 0
SSZ_FIELD PendingConsolidation, source_index, Uint64
SSZ_FIELD PendingConsolidation, target_index, Uint64
SSZ_END PendingConsolidation

SSZ_CONTAINER DepositRequest, 0
SSZ_FIELD DepositRequest, pubkey, Bytes48
SSZ_FIELD DepositRequest, withdrawal_credentials, Bytes32
SSZ_FIELD DepositRequest, amount, Uint64
SSZ_FIELD DepositRequest, signature, Bytes96
SSZ_FIELD DepositRequest, index, Uint64
SSZ_END DepositRequest

SSZ_CONTAINER WithdrawalRequest, 0
SSZ_FIELD WithdrawalRequest, source_address, Bytes20
SSZ_FIELD WithdrawalRequest, validator_pubkey, Bytes48
SSZ_FIELD WithdrawalRequest, amount, Uint64
SSZ_END WithdrawalRequest

SSZ_CONTAINER ConsolidationRequest, 0
SSZ_FIELD ConsolidationRequest, source_address, Bytes20
SSZ_FIELD ConsolidationRequest, source_pubkey, Bytes48
SSZ_FIELD ConsolidationRequest, target_pubkey, Bytes48
SSZ_END ConsolidationRequest

SSZ_CONTAINER SingleAttestation, 0
SSZ_FIELD SingleAttestation, committee_index, Uint64
SSZ_FIELD SingleAttestation, attester_index, Uint64
SSZ_FIELD SingleAttestation, data, AttestationData
SSZ_FIELD SingleAttestation, signature, Bytes96
SSZ_END SingleAttestation
.endif

.if TYPES_FORK >= FORK_FULU
SSZ_CONTAINER MatrixEntry, 0
SSZ_FIELD MatrixEntry, cell, Cell
SSZ_FIELD MatrixEntry, kzg_proof, Bytes48
SSZ_FIELD MatrixEntry, column_index, Uint64
SSZ_FIELD MatrixEntry, row_index, Uint64
SSZ_END MatrixEntry

SSZ_CONTAINER PartialDataColumnGroupID, 0
SSZ_FIELD PartialDataColumnGroupID, beacon_block_root, Bytes32
SSZ_END PartialDataColumnGroupID
.endif

/* ------------------------------------------------------------ Lists of containers */

SSZ_LIST Eth1DataVotes, Eth1Data, EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH
SSZ_LIST Validators, Validator, VALIDATOR_REGISTRY_LIMIT
SSZ_LIST ProposerSlashings, ProposerSlashing, MAX_PROPOSER_SLASHINGS
SSZ_LIST Deposits, Deposit, MAX_DEPOSITS
SSZ_LIST VoluntaryExits, SignedVoluntaryExit, MAX_VOLUNTARY_EXITS
.if TYPES_FORK >= FORK_CAPELLA
SSZ_LIST HistoricalSummaries, HistoricalSummary, HISTORICAL_ROOTS_LIMIT
SSZ_LIST BLSToExecutionChanges, SignedBLSToExecutionChange, MAX_BLS_TO_EXECUTION_CHANGES
SSZ_LIST Withdrawals, Withdrawal, MAX_WITHDRAWALS_PER_PAYLOAD
.endif
.if TYPES_FORK >= FORK_ELECTRA
SSZ_LIST PendingDeposits, PendingDeposit, PENDING_DEPOSITS_LIMIT
SSZ_LIST PendingPartialWithdrawals, PendingPartialWithdrawal, PENDING_PARTIAL_WITHDRAWALS_LIMIT
SSZ_LIST PendingConsolidations, PendingConsolidation, PENDING_CONSOLIDATIONS_LIMIT
SSZ_LIST DepositRequests, DepositRequest, MAX_DEPOSIT_REQUESTS_PER_PAYLOAD
SSZ_LIST WithdrawalRequests, WithdrawalRequest, MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD
SSZ_LIST ConsolidationRequests, ConsolidationRequest, MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD
.endif

/* ------------------------------------------------------------ Containers of variable size */

SSZ_CONTAINER IndexedAttestation, 1
SSZ_FIELD IndexedAttestation, attesting_indices, AttestingIndices
SSZ_FIELD IndexedAttestation, data, AttestationData
SSZ_FIELD IndexedAttestation, signature, Bytes96
SSZ_END IndexedAttestation

SSZ_CONTAINER AttesterSlashing, 1
SSZ_FIELD AttesterSlashing, attestation_1, IndexedAttestation
SSZ_FIELD AttesterSlashing, attestation_2, IndexedAttestation
SSZ_END AttesterSlashing

SSZ_CONTAINER Attestation, 1
SSZ_FIELD Attestation, aggregation_bits, AggregationBits
SSZ_FIELD Attestation, data, AttestationData
SSZ_FIELD Attestation, signature, Bytes96
.if TYPES_FORK >= FORK_ELECTRA
SSZ_FIELD Attestation, committee_bits, CommitteeBits
.endif
SSZ_END Attestation

SSZ_CONTAINER AggregateAndProof, 1
SSZ_FIELD AggregateAndProof, aggregator_index, Uint64
SSZ_FIELD AggregateAndProof, aggregate, Attestation
SSZ_FIELD AggregateAndProof, selection_proof, Bytes96
SSZ_END AggregateAndProof

SSZ_CONTAINER SignedAggregateAndProof, 1
SSZ_FIELD SignedAggregateAndProof, message, AggregateAndProof
SSZ_FIELD SignedAggregateAndProof, signature, Bytes96
SSZ_END SignedAggregateAndProof

.if TYPES_FORK == FORK_PHASE0
SSZ_CONTAINER PendingAttestation, 1
SSZ_FIELD PendingAttestation, aggregation_bits, AggregationBits
SSZ_FIELD PendingAttestation, data, AttestationData
SSZ_FIELD PendingAttestation, inclusion_delay, Uint64
SSZ_FIELD PendingAttestation, proposer_index, Uint64
SSZ_END PendingAttestation

SSZ_LIST PendingAttestations, PendingAttestation, MAX_ATTESTATIONS * SLOTS_PER_EPOCH
.endif

.if TYPES_FORK >= FORK_BELLATRIX
SSZ_CONTAINER ExecutionPayloadHeader, 1
SSZ_FIELD ExecutionPayloadHeader, parent_hash, Bytes32
SSZ_FIELD ExecutionPayloadHeader, fee_recipient, Bytes20
SSZ_FIELD ExecutionPayloadHeader, state_root, Bytes32
SSZ_FIELD ExecutionPayloadHeader, receipts_root, Bytes32
SSZ_FIELD ExecutionPayloadHeader, logs_bloom, LogsBloom
SSZ_FIELD ExecutionPayloadHeader, prev_randao, Bytes32
SSZ_FIELD ExecutionPayloadHeader, block_number, Uint64
SSZ_FIELD ExecutionPayloadHeader, gas_limit, Uint64
SSZ_FIELD ExecutionPayloadHeader, gas_used, Uint64
SSZ_FIELD ExecutionPayloadHeader, timestamp, Uint64
SSZ_FIELD ExecutionPayloadHeader, extra_data, ExtraData
SSZ_FIELD ExecutionPayloadHeader, base_fee_per_gas, Uint256
SSZ_FIELD ExecutionPayloadHeader, block_hash, Bytes32
SSZ_FIELD ExecutionPayloadHeader, transactions_root, Bytes32
.if TYPES_FORK >= FORK_CAPELLA
SSZ_FIELD ExecutionPayloadHeader, withdrawals_root, Bytes32
.endif
.if TYPES_FORK >= FORK_DENEB
SSZ_FIELD ExecutionPayloadHeader, blob_gas_used, Uint64
SSZ_FIELD ExecutionPayloadHeader, excess_blob_gas, Uint64
.endif
SSZ_END ExecutionPayloadHeader
.if TYPES_FORK >= FORK_BELLATRIX
SSZ_CONTAINER PowBlock, 0
SSZ_FIELD PowBlock, block_hash, Bytes32
SSZ_FIELD PowBlock, parent_hash, Bytes32
SSZ_FIELD PowBlock, total_difficulty, Uint256
SSZ_END PowBlock
.endif

SSZ_CONTAINER ExecutionPayload, 1
SSZ_FIELD ExecutionPayload, parent_hash, Bytes32
SSZ_FIELD ExecutionPayload, fee_recipient, Bytes20
SSZ_FIELD ExecutionPayload, state_root, Bytes32
SSZ_FIELD ExecutionPayload, receipts_root, Bytes32
SSZ_FIELD ExecutionPayload, logs_bloom, LogsBloom
SSZ_FIELD ExecutionPayload, prev_randao, Bytes32
SSZ_FIELD ExecutionPayload, block_number, Uint64
SSZ_FIELD ExecutionPayload, gas_limit, Uint64
SSZ_FIELD ExecutionPayload, gas_used, Uint64
SSZ_FIELD ExecutionPayload, timestamp, Uint64
SSZ_FIELD ExecutionPayload, extra_data, ExtraData
SSZ_FIELD ExecutionPayload, base_fee_per_gas, Uint256
SSZ_FIELD ExecutionPayload, block_hash, Bytes32
SSZ_FIELD ExecutionPayload, transactions, Transactions
.if TYPES_FORK >= FORK_CAPELLA
SSZ_FIELD ExecutionPayload, withdrawals, Withdrawals
.endif
.if TYPES_FORK >= FORK_DENEB
SSZ_FIELD ExecutionPayload, blob_gas_used, Uint64
SSZ_FIELD ExecutionPayload, excess_blob_gas, Uint64
.endif
SSZ_END ExecutionPayload
.endif

.if TYPES_FORK >= FORK_ELECTRA
SSZ_CONTAINER ExecutionRequests, 1
SSZ_FIELD ExecutionRequests, deposits, DepositRequests
SSZ_FIELD ExecutionRequests, withdrawals, WithdrawalRequests
SSZ_FIELD ExecutionRequests, consolidations, ConsolidationRequests
SSZ_END ExecutionRequests

SSZ_LIST AttesterSlashings, AttesterSlashing, MAX_ATTESTER_SLASHINGS_ELECTRA
SSZ_LIST Attestations, Attestation, MAX_ATTESTATIONS_ELECTRA
.else
SSZ_LIST AttesterSlashings, AttesterSlashing, MAX_ATTESTER_SLASHINGS
SSZ_LIST Attestations, Attestation, MAX_ATTESTATIONS
.endif

SSZ_CONTAINER BeaconBlockBody, 1
SSZ_FIELD BeaconBlockBody, randao_reveal, Bytes96
SSZ_FIELD BeaconBlockBody, eth1_data, Eth1Data
SSZ_FIELD BeaconBlockBody, graffiti, Bytes32
SSZ_FIELD BeaconBlockBody, proposer_slashings, ProposerSlashings
SSZ_FIELD BeaconBlockBody, attester_slashings, AttesterSlashings
SSZ_FIELD BeaconBlockBody, attestations, Attestations
SSZ_FIELD BeaconBlockBody, deposits, Deposits
SSZ_FIELD BeaconBlockBody, voluntary_exits, VoluntaryExits
.if TYPES_FORK >= FORK_ALTAIR
SSZ_FIELD BeaconBlockBody, sync_aggregate, SyncAggregate
.endif
.if TYPES_FORK >= FORK_BELLATRIX
SSZ_FIELD BeaconBlockBody, execution_payload, ExecutionPayload
.endif
.if TYPES_FORK >= FORK_CAPELLA
SSZ_FIELD BeaconBlockBody, bls_to_execution_changes, BLSToExecutionChanges
.endif
.if TYPES_FORK >= FORK_DENEB
SSZ_FIELD BeaconBlockBody, blob_kzg_commitments, BlobKZGCommitments
.endif
.if TYPES_FORK >= FORK_ELECTRA
SSZ_FIELD BeaconBlockBody, execution_requests, ExecutionRequests
.endif
SSZ_END BeaconBlockBody

SSZ_CONTAINER BeaconBlock, 1
SSZ_FIELD BeaconBlock, slot, Uint64
SSZ_FIELD BeaconBlock, proposer_index, Uint64
SSZ_FIELD BeaconBlock, parent_root, Bytes32
SSZ_FIELD BeaconBlock, state_root, Bytes32
SSZ_FIELD BeaconBlock, body, BeaconBlockBody
SSZ_END BeaconBlock

SSZ_CONTAINER SignedBeaconBlock, 1
SSZ_FIELD SignedBeaconBlock, message, BeaconBlock
SSZ_FIELD SignedBeaconBlock, signature, Bytes96
SSZ_END SignedBeaconBlock

/*
 * The blinded blocks of beacon-APIs v4.0.0 (Bellatrix to Electra BlindedBeaconBlockBody,
 * BlindedBeaconBlock, SignedBlindedBeaconBlock): BeaconBlockBody's fields in their order, with
 * execution_payload_header in the place of execution_payload, so that a block and its blinded
 * block have one hash_tree_root.
 */
.if TYPES_FORK >= FORK_BELLATRIX
SSZ_CONTAINER BlindedBeaconBlockBody, 1
SSZ_FIELD BlindedBeaconBlockBody, randao_reveal, Bytes96
SSZ_FIELD BlindedBeaconBlockBody, eth1_data, Eth1Data
SSZ_FIELD BlindedBeaconBlockBody, graffiti, Bytes32
SSZ_FIELD BlindedBeaconBlockBody, proposer_slashings, ProposerSlashings
SSZ_FIELD BlindedBeaconBlockBody, attester_slashings, AttesterSlashings
SSZ_FIELD BlindedBeaconBlockBody, attestations, Attestations
SSZ_FIELD BlindedBeaconBlockBody, deposits, Deposits
SSZ_FIELD BlindedBeaconBlockBody, voluntary_exits, VoluntaryExits
SSZ_FIELD BlindedBeaconBlockBody, sync_aggregate, SyncAggregate
SSZ_FIELD BlindedBeaconBlockBody, execution_payload_header, ExecutionPayloadHeader
.if TYPES_FORK >= FORK_CAPELLA
SSZ_FIELD BlindedBeaconBlockBody, bls_to_execution_changes, BLSToExecutionChanges
.endif
.if TYPES_FORK >= FORK_DENEB
SSZ_FIELD BlindedBeaconBlockBody, blob_kzg_commitments, BlobKZGCommitments
.endif
.if TYPES_FORK >= FORK_ELECTRA
SSZ_FIELD BlindedBeaconBlockBody, execution_requests, ExecutionRequests
.endif
SSZ_END BlindedBeaconBlockBody

SSZ_CONTAINER BlindedBeaconBlock, 1
SSZ_FIELD BlindedBeaconBlock, slot, Uint64
SSZ_FIELD BlindedBeaconBlock, proposer_index, Uint64
SSZ_FIELD BlindedBeaconBlock, parent_root, Bytes32
SSZ_FIELD BlindedBeaconBlock, state_root, Bytes32
SSZ_FIELD BlindedBeaconBlock, body, BlindedBeaconBlockBody
SSZ_END BlindedBeaconBlock

SSZ_CONTAINER SignedBlindedBeaconBlock, 1
SSZ_FIELD SignedBlindedBeaconBlock, message, BlindedBeaconBlock
SSZ_FIELD SignedBlindedBeaconBlock, signature, Bytes96
SSZ_END SignedBlindedBeaconBlock
.endif

SSZ_CONTAINER BeaconState, 1
SSZ_FIELD BeaconState, genesis_time, Uint64
SSZ_FIELD BeaconState, genesis_validators_root, Bytes32
SSZ_FIELD BeaconState, slot, Uint64
SSZ_FIELD BeaconState, fork, Fork
SSZ_FIELD BeaconState, latest_block_header, BeaconBlockHeader
SSZ_FIELD BeaconState, block_roots, BlockRoots
SSZ_FIELD BeaconState, state_roots, BlockRoots
SSZ_FIELD BeaconState, historical_roots, HistoricalRoots
SSZ_FIELD BeaconState, eth1_data, Eth1Data
SSZ_FIELD BeaconState, eth1_data_votes, Eth1DataVotes
SSZ_FIELD BeaconState, eth1_deposit_index, Uint64
SSZ_FIELD BeaconState, validators, Validators
SSZ_FIELD BeaconState, balances, Balances
SSZ_FIELD BeaconState, randao_mixes, RandaoMixes
SSZ_FIELD BeaconState, slashings, Slashings
.if TYPES_FORK == FORK_PHASE0
SSZ_FIELD BeaconState, previous_epoch_attestations, PendingAttestations
SSZ_FIELD BeaconState, current_epoch_attestations, PendingAttestations
.else
SSZ_FIELD BeaconState, previous_epoch_participation, EpochParticipation
SSZ_FIELD BeaconState, current_epoch_participation, EpochParticipation
.endif
SSZ_FIELD BeaconState, justification_bits, JustificationBits
SSZ_FIELD BeaconState, previous_justified_checkpoint, Checkpoint
SSZ_FIELD BeaconState, current_justified_checkpoint, Checkpoint
SSZ_FIELD BeaconState, finalized_checkpoint, Checkpoint
.if TYPES_FORK >= FORK_ALTAIR
SSZ_FIELD BeaconState, inactivity_scores, Balances
SSZ_FIELD BeaconState, current_sync_committee, SyncCommittee
SSZ_FIELD BeaconState, next_sync_committee, SyncCommittee
.endif
.if TYPES_FORK >= FORK_BELLATRIX
SSZ_FIELD BeaconState, latest_execution_payload_header, ExecutionPayloadHeader
.endif
.if TYPES_FORK >= FORK_CAPELLA
SSZ_FIELD BeaconState, next_withdrawal_index, Uint64
SSZ_FIELD BeaconState, next_withdrawal_validator_index, Uint64
SSZ_FIELD BeaconState, historical_summaries, HistoricalSummaries
.endif
.if TYPES_FORK >= FORK_ELECTRA
SSZ_FIELD BeaconState, deposit_requests_start_index, Uint64
SSZ_FIELD BeaconState, deposit_balance_to_consume, Uint64
SSZ_FIELD BeaconState, exit_balance_to_consume, Uint64
SSZ_FIELD BeaconState, earliest_exit_epoch, Uint64
SSZ_FIELD BeaconState, consolidation_balance_to_consume, Uint64
SSZ_FIELD BeaconState, earliest_consolidation_epoch, Uint64
SSZ_FIELD BeaconState, pending_deposits, PendingDeposits
SSZ_FIELD BeaconState, pending_partial_withdrawals, PendingPartialWithdrawals
SSZ_FIELD BeaconState, pending_consolidations, PendingConsolidations
.endif
.if TYPES_FORK >= FORK_FULU
SSZ_FIELD BeaconState, proposer_lookahead, ProposerLookahead
.endif
SSZ_END BeaconState

.if TYPES_FORK >= FORK_FULU
SSZ_CONTAINER DataColumnSidecar, 1
SSZ_FIELD DataColumnSidecar, index, Uint64
SSZ_FIELD DataColumnSidecar, column, DataColumn
SSZ_FIELD DataColumnSidecar, kzg_commitments, BlobKZGCommitments
SSZ_FIELD DataColumnSidecar, kzg_proofs, BlobKZGCommitments
SSZ_FIELD DataColumnSidecar, signed_block_header, SignedBeaconBlockHeader
SSZ_FIELD DataColumnSidecar, kzg_commitments_inclusion_proof, KZGCommitmentsInclusionProof
SSZ_END DataColumnSidecar

SSZ_CONTAINER DataColumnsByRootIdentifier, 1
SSZ_FIELD DataColumnsByRootIdentifier, block_root, Bytes32
SSZ_FIELD DataColumnsByRootIdentifier, columns, DataColumnIndices
SSZ_END DataColumnsByRootIdentifier

SSZ_CONTAINER PartialDataColumnHeader, 1
SSZ_FIELD PartialDataColumnHeader, kzg_commitments, BlobKZGCommitments
SSZ_FIELD PartialDataColumnHeader, signed_block_header, SignedBeaconBlockHeader
SSZ_FIELD PartialDataColumnHeader, kzg_commitments_inclusion_proof, KZGCommitmentsInclusionProof
SSZ_END PartialDataColumnHeader

SSZ_LIST OptionalPartialDataColumnHeader, PartialDataColumnHeader, 1

SSZ_CONTAINER PartialDataColumnSidecar, 1
SSZ_FIELD PartialDataColumnSidecar, cells_present_bitmap, CellsBitList
SSZ_FIELD PartialDataColumnSidecar, partial_column, DataColumn
SSZ_FIELD PartialDataColumnSidecar, kzg_proofs, BlobKZGCommitments
SSZ_FIELD PartialDataColumnSidecar, header, OptionalPartialDataColumnHeader
SSZ_END PartialDataColumnSidecar

SSZ_CONTAINER PartialDataColumnPartsMetadata, 1
SSZ_FIELD PartialDataColumnPartsMetadata, available, CellsBitList
SSZ_FIELD PartialDataColumnPartsMetadata, requests, CellsBitList
SSZ_END PartialDataColumnPartsMetadata
.endif

/* ------------------------------------------------------------ Req/resp messages */

/*
 * The messages of the req/resp methods (docs/reference/req-resp.md): the containers that
 * p2p-interface.md states in its text, and its list types. A list limit that is a config
 * value takes the value of the mainnet and minimal configs (REQUEST_*_LIMIT of
 * include/lantern.inc); the request handlers check counts against the config.
 */
SSZ_LIST ErrorMessage, Uint8, 256

SSZ_CONTAINER Status, 0
SSZ_FIELD Status, fork_digest, Bytes4
SSZ_FIELD Status, finalized_root, Bytes32
SSZ_FIELD Status, finalized_epoch, Uint64
SSZ_FIELD Status, head_root, Bytes32
SSZ_FIELD Status, head_slot, Uint64
SSZ_END Status

.if TYPES_FORK >= FORK_FULU
SSZ_CONTAINER StatusV2, 0
SSZ_FIELD StatusV2, fork_digest, Bytes4
SSZ_FIELD StatusV2, finalized_root, Bytes32
SSZ_FIELD StatusV2, finalized_epoch, Uint64
SSZ_FIELD StatusV2, head_root, Bytes32
SSZ_FIELD StatusV2, head_slot, Uint64
SSZ_FIELD StatusV2, earliest_available_slot, Uint64
SSZ_END StatusV2
.endif

SSZ_CONTAINER MetaData, 0
SSZ_FIELD MetaData, seq_number, Uint64
SSZ_FIELD MetaData, attnets, Attnets
SSZ_END MetaData

.if TYPES_FORK >= FORK_ALTAIR
SSZ_CONTAINER MetaDataV2, 0
SSZ_FIELD MetaDataV2, seq_number, Uint64
SSZ_FIELD MetaDataV2, attnets, Attnets
SSZ_FIELD MetaDataV2, syncnets, Syncnets
SSZ_END MetaDataV2
.endif

.if TYPES_FORK >= FORK_FULU
SSZ_CONTAINER MetaDataV3, 0
SSZ_FIELD MetaDataV3, seq_number, Uint64
SSZ_FIELD MetaDataV3, attnets, Attnets
SSZ_FIELD MetaDataV3, syncnets, Syncnets
SSZ_FIELD MetaDataV3, custody_group_count, Uint64
SSZ_END MetaDataV3
.endif

SSZ_CONTAINER BeaconBlocksByRangeRequest, 0
SSZ_FIELD BeaconBlocksByRangeRequest, start_slot, Uint64
SSZ_FIELD BeaconBlocksByRangeRequest, count, Uint64
SSZ_FIELD BeaconBlocksByRangeRequest, step, Uint64
SSZ_END BeaconBlocksByRangeRequest

.if TYPES_FORK >= FORK_DENEB
SSZ_LIST BeaconBlockRoots, Bytes32, REQUEST_BLOCKS_LIMIT_DENEB
.else
SSZ_LIST BeaconBlockRoots, Bytes32, REQUEST_BLOCKS_LIMIT
.endif

.if TYPES_FORK == FORK_DENEB || TYPES_FORK == FORK_ELECTRA
SSZ_CONTAINER BlobSidecarsByRangeRequest, 0
SSZ_FIELD BlobSidecarsByRangeRequest, start_slot, Uint64
SSZ_FIELD BlobSidecarsByRangeRequest, count, Uint64
SSZ_END BlobSidecarsByRangeRequest
.if TYPES_FORK == FORK_ELECTRA
SSZ_LIST BlobIdentifiers, BlobIdentifier, REQUEST_BLOB_SIDECARS_LIMIT_ELECTRA
.else
SSZ_LIST BlobIdentifiers, BlobIdentifier, REQUEST_BLOB_SIDECARS_LIMIT
.endif
.endif

.if TYPES_FORK >= FORK_FULU
SSZ_CONTAINER DataColumnSidecarsByRangeRequest, 1
SSZ_FIELD DataColumnSidecarsByRangeRequest, start_slot, Uint64
SSZ_FIELD DataColumnSidecarsByRangeRequest, count, Uint64
SSZ_FIELD DataColumnSidecarsByRangeRequest, columns, DataColumnIndices
SSZ_END DataColumnSidecarsByRangeRequest

SSZ_LIST DataColumnsByRootIdentifiers, DataColumnsByRootIdentifier, REQUEST_BLOCKS_LIMIT_DENEB

SSZ_CONTAINER BeaconBlocksByHeadRequest, 0
SSZ_FIELD BeaconBlocksByHeadRequest, beacon_root, Bytes32
SSZ_FIELD BeaconBlocksByHeadRequest, count, Uint64
SSZ_END BeaconBlocksByHeadRequest
.endif

SSZ_CONTAINER ENRForkID, 0
SSZ_FIELD ENRForkID, fork_digest, Bytes4
SSZ_FIELD ENRForkID, next_fork_version, Bytes4
SSZ_FIELD ENRForkID, next_fork_epoch, Uint64
SSZ_END ENRForkID
