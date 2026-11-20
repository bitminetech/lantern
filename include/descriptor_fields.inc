/*
 * The field records of include/descriptors.inc, in field order: SSZ_FIELDS T at the first field of
 * container T, then one SSZ_DFIELD for each field. descriptors.inc includes it twice: once for the
 * TypeField records, once for the name of each field.
 */
.if FORK >= FORK_DENEB
SSZ_FIELDS BlockContents
SSZ_DFIELD N_BeaconBlock, BlockContents, block
SSZ_DFIELD N_BundleProofs, BlockContents, kzg_proofs
SSZ_DFIELD N_BundleBlobs, BlockContents, blobs
.endif

SSZ_FIELDS ProduceDraft
SSZ_DFIELD N_ProposerSlashings, ProduceDraft, proposer_slashings
SSZ_DFIELD N_AttesterSlashings, ProduceDraft, attester_slashings
SSZ_DFIELD N_DraftAttestations, ProduceDraft, attestations
SSZ_DFIELD N_VoluntaryExits, ProduceDraft, voluntary_exits
.if FORK >= FORK_ALTAIR
SSZ_DFIELD N_SyncAggregate, ProduceDraft, sync_aggregate
.endif
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_BLSToExecutionChanges, ProduceDraft, bls_to_execution_changes
.endif

SSZ_FIELDS SignedBeaconBlock
SSZ_DFIELD N_BeaconBlock, SignedBeaconBlock, message
SSZ_DFIELD N_Bytes96, SignedBeaconBlock, signature

SSZ_FIELDS BeaconBlock
SSZ_DFIELD N_Uint64, BeaconBlock, slot
SSZ_DFIELD N_Uint64, BeaconBlock, proposer_index
SSZ_DFIELD N_Bytes32, BeaconBlock, parent_root
SSZ_DFIELD N_Bytes32, BeaconBlock, state_root
SSZ_DFIELD N_BeaconBlockBody, BeaconBlock, body

SSZ_FIELDS BeaconBlockBody
SSZ_DFIELD N_Bytes96, BeaconBlockBody, randao_reveal
SSZ_DFIELD N_Eth1Data, BeaconBlockBody, eth1_data
SSZ_DFIELD N_Bytes32, BeaconBlockBody, graffiti
SSZ_DFIELD N_ProposerSlashings, BeaconBlockBody, proposer_slashings
SSZ_DFIELD N_AttesterSlashings, BeaconBlockBody, attester_slashings
SSZ_DFIELD N_Attestations, BeaconBlockBody, attestations
SSZ_DFIELD N_Deposits, BeaconBlockBody, deposits
SSZ_DFIELD N_VoluntaryExits, BeaconBlockBody, voluntary_exits
.if FORK >= FORK_ALTAIR
SSZ_DFIELD N_SyncAggregate, BeaconBlockBody, sync_aggregate
.endif
.if FORK >= FORK_BELLATRIX
SSZ_DFIELD N_ExecutionPayload, BeaconBlockBody, execution_payload
.endif
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_BLSToExecutionChanges, BeaconBlockBody, bls_to_execution_changes
.endif
.if FORK >= FORK_DENEB
SSZ_DFIELD N_BlobKZGCommitments, BeaconBlockBody, blob_kzg_commitments
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_ExecutionRequests, BeaconBlockBody, execution_requests
.endif

.if FORK >= FORK_BELLATRIX
SSZ_FIELDS SignedBlindedBeaconBlock
SSZ_DFIELD N_BlindedBeaconBlock, SignedBlindedBeaconBlock, message
SSZ_DFIELD N_Bytes96, SignedBlindedBeaconBlock, signature

SSZ_FIELDS BlindedBeaconBlock
SSZ_DFIELD N_Uint64, BlindedBeaconBlock, slot
SSZ_DFIELD N_Uint64, BlindedBeaconBlock, proposer_index
SSZ_DFIELD N_Bytes32, BlindedBeaconBlock, parent_root
SSZ_DFIELD N_Bytes32, BlindedBeaconBlock, state_root
SSZ_DFIELD N_BlindedBeaconBlockBody, BlindedBeaconBlock, body

SSZ_FIELDS BlindedBeaconBlockBody
SSZ_DFIELD N_Bytes96, BlindedBeaconBlockBody, randao_reveal
SSZ_DFIELD N_Eth1Data, BlindedBeaconBlockBody, eth1_data
SSZ_DFIELD N_Bytes32, BlindedBeaconBlockBody, graffiti
SSZ_DFIELD N_ProposerSlashings, BlindedBeaconBlockBody, proposer_slashings
SSZ_DFIELD N_AttesterSlashings, BlindedBeaconBlockBody, attester_slashings
SSZ_DFIELD N_Attestations, BlindedBeaconBlockBody, attestations
SSZ_DFIELD N_Deposits, BlindedBeaconBlockBody, deposits
SSZ_DFIELD N_VoluntaryExits, BlindedBeaconBlockBody, voluntary_exits
SSZ_DFIELD N_SyncAggregate, BlindedBeaconBlockBody, sync_aggregate
SSZ_DFIELD N_ExecutionPayloadHeader, BlindedBeaconBlockBody, execution_payload_header
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_BLSToExecutionChanges, BlindedBeaconBlockBody, bls_to_execution_changes
.endif
.if FORK >= FORK_DENEB
SSZ_DFIELD N_BlobKZGCommitments, BlindedBeaconBlockBody, blob_kzg_commitments
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_ExecutionRequests, BlindedBeaconBlockBody, execution_requests
.endif
.endif

SSZ_FIELDS BeaconState
SSZ_DFIELD N_Uint64, BeaconState, genesis_time
SSZ_DFIELD N_Bytes32, BeaconState, genesis_validators_root
SSZ_DFIELD N_Uint64, BeaconState, slot
SSZ_DFIELD N_Fork, BeaconState, fork
SSZ_DFIELD N_BeaconBlockHeader, BeaconState, latest_block_header
SSZ_DFIELD N_BlockRoots, BeaconState, block_roots
SSZ_DFIELD N_BlockRoots, BeaconState, state_roots
SSZ_DFIELD N_HistoricalRoots, BeaconState, historical_roots
SSZ_DFIELD N_Eth1Data, BeaconState, eth1_data
SSZ_DFIELD N_Eth1DataVotes, BeaconState, eth1_data_votes
SSZ_DFIELD N_Uint64, BeaconState, eth1_deposit_index
SSZ_DFIELD N_Validators, BeaconState, validators
SSZ_DFIELD N_Balances, BeaconState, balances
SSZ_DFIELD N_RandaoMixes, BeaconState, randao_mixes
SSZ_DFIELD N_Slashings, BeaconState, slashings
.if FORK == FORK_PHASE0
SSZ_DFIELD N_PendingAttestations, BeaconState, previous_epoch_attestations
SSZ_DFIELD N_PendingAttestations, BeaconState, current_epoch_attestations
.else
SSZ_DFIELD N_EpochParticipation, BeaconState, previous_epoch_participation
SSZ_DFIELD N_EpochParticipation, BeaconState, current_epoch_participation
.endif
SSZ_DFIELD N_JustificationBits, BeaconState, justification_bits
SSZ_DFIELD N_Checkpoint, BeaconState, previous_justified_checkpoint
SSZ_DFIELD N_Checkpoint, BeaconState, current_justified_checkpoint
SSZ_DFIELD N_Checkpoint, BeaconState, finalized_checkpoint
.if FORK >= FORK_ALTAIR
SSZ_DFIELD N_Balances, BeaconState, inactivity_scores
.endif
.if FORK >= FORK_ALTAIR
SSZ_DFIELD N_SyncCommittee, BeaconState, current_sync_committee
.endif
.if FORK >= FORK_ALTAIR
SSZ_DFIELD N_SyncCommittee, BeaconState, next_sync_committee
.endif
.if FORK >= FORK_BELLATRIX
SSZ_DFIELD N_ExecutionPayloadHeader, BeaconState, latest_execution_payload_header
.endif
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_Uint64, BeaconState, next_withdrawal_index
.endif
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_Uint64, BeaconState, next_withdrawal_validator_index
.endif
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_HistoricalSummaries, BeaconState, historical_summaries
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_Uint64, BeaconState, deposit_requests_start_index
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_Uint64, BeaconState, deposit_balance_to_consume
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_Uint64, BeaconState, exit_balance_to_consume
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_Uint64, BeaconState, earliest_exit_epoch
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_Uint64, BeaconState, consolidation_balance_to_consume
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_Uint64, BeaconState, earliest_consolidation_epoch
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_PendingDeposits, BeaconState, pending_deposits
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_PendingPartialWithdrawals, BeaconState, pending_partial_withdrawals
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_PendingConsolidations, BeaconState, pending_consolidations
.endif
.if FORK >= FORK_FULU
SSZ_DFIELD N_ProposerLookahead, BeaconState, proposer_lookahead
.endif

.if FORK == FORK_PHASE0
SSZ_FIELDS PendingAttestation
SSZ_DFIELD N_AggregationBits, PendingAttestation, aggregation_bits
SSZ_DFIELD N_AttestationData, PendingAttestation, data
SSZ_DFIELD N_Uint64, PendingAttestation, inclusion_delay
SSZ_DFIELD N_Uint64, PendingAttestation, proposer_index
.endif

.if FORK <= FORK_BELLATRIX
SSZ_FIELDS HistoricalBatch
SSZ_DFIELD N_BlockRoots, HistoricalBatch, block_roots
SSZ_DFIELD N_BlockRoots, HistoricalBatch, state_roots
.endif

SSZ_FIELDS SignedAggregateAndProof
SSZ_DFIELD N_AggregateAndProof, SignedAggregateAndProof, message
SSZ_DFIELD N_Bytes96, SignedAggregateAndProof, signature

SSZ_FIELDS AggregateAndProof
SSZ_DFIELD N_Uint64, AggregateAndProof, aggregator_index
SSZ_DFIELD N_Attestation, AggregateAndProof, aggregate
SSZ_DFIELD N_Bytes96, AggregateAndProof, selection_proof

SSZ_FIELDS Attestation
SSZ_DFIELD N_AggregationBits, Attestation, aggregation_bits
SSZ_DFIELD N_AttestationData, Attestation, data
SSZ_DFIELD N_Bytes96, Attestation, signature
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_CommitteeBits, Attestation, committee_bits
.endif

SSZ_FIELDS AttesterSlashing
SSZ_DFIELD N_IndexedAttestation, AttesterSlashing, attestation_1
SSZ_DFIELD N_IndexedAttestation, AttesterSlashing, attestation_2

SSZ_FIELDS IndexedAttestation
SSZ_DFIELD N_AttestingIndices, IndexedAttestation, attesting_indices
SSZ_DFIELD N_AttestationData, IndexedAttestation, data
SSZ_DFIELD N_Bytes96, IndexedAttestation, signature

.if FORK >= FORK_ELECTRA
SSZ_FIELDS SingleAttestation
SSZ_DFIELD N_Uint64, SingleAttestation, committee_index
SSZ_DFIELD N_Uint64, SingleAttestation, attester_index
SSZ_DFIELD N_AttestationData, SingleAttestation, data
SSZ_DFIELD N_Bytes96, SingleAttestation, signature
.endif

SSZ_FIELDS AttestationData
SSZ_DFIELD N_Uint64, AttestationData, slot
SSZ_DFIELD N_Uint64, AttestationData, index
SSZ_DFIELD N_Bytes32, AttestationData, beacon_block_root
SSZ_DFIELD N_Checkpoint, AttestationData, source
SSZ_DFIELD N_Checkpoint, AttestationData, target

SSZ_FIELDS Checkpoint
SSZ_DFIELD N_Uint64, Checkpoint, epoch
SSZ_DFIELD N_Bytes32, Checkpoint, root

SSZ_FIELDS ProposerSlashing
SSZ_DFIELD N_SignedBeaconBlockHeader, ProposerSlashing, signed_header_1
SSZ_DFIELD N_SignedBeaconBlockHeader, ProposerSlashing, signed_header_2

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
SSZ_FIELDS BlobSidecar
SSZ_DFIELD N_Uint64, BlobSidecar, index
SSZ_DFIELD N_Blob, BlobSidecar, blob
SSZ_DFIELD N_Bytes48, BlobSidecar, kzg_commitment
SSZ_DFIELD N_Bytes48, BlobSidecar, kzg_proof
SSZ_DFIELD N_SignedBeaconBlockHeader, BlobSidecar, signed_block_header
SSZ_DFIELD N_KZGCommitmentInclusionProof, BlobSidecar, kzg_commitment_inclusion_proof

SSZ_FIELDS BlobSidecarsByRangeRequest
SSZ_DFIELD N_Uint64, BlobSidecarsByRangeRequest, start_slot
SSZ_DFIELD N_Uint64, BlobSidecarsByRangeRequest, count

SSZ_FIELDS BlobIdentifier
SSZ_DFIELD N_Bytes32, BlobIdentifier, block_root
SSZ_DFIELD N_Uint64, BlobIdentifier, index
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS DataColumnSidecar
SSZ_DFIELD N_Uint64, DataColumnSidecar, index
SSZ_DFIELD N_DataColumn, DataColumnSidecar, column
SSZ_DFIELD N_BlobKZGCommitments, DataColumnSidecar, kzg_commitments
SSZ_DFIELD N_BlobKZGCommitments, DataColumnSidecar, kzg_proofs
SSZ_DFIELD N_SignedBeaconBlockHeader, DataColumnSidecar, signed_block_header
SSZ_DFIELD N_KZGCommitmentsInclusionProof, DataColumnSidecar, kzg_commitments_inclusion_proof
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS PartialDataColumnSidecar
SSZ_DFIELD N_CellsBitList, PartialDataColumnSidecar, cells_present_bitmap
SSZ_DFIELD N_DataColumn, PartialDataColumnSidecar, partial_column
SSZ_DFIELD N_BlobKZGCommitments, PartialDataColumnSidecar, kzg_proofs
SSZ_DFIELD N_OptionalPartialDataColumnHeader, PartialDataColumnSidecar, header
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS PartialDataColumnHeader
SSZ_DFIELD N_BlobKZGCommitments, PartialDataColumnHeader, kzg_commitments
SSZ_DFIELD N_SignedBeaconBlockHeader, PartialDataColumnHeader, signed_block_header
SSZ_DFIELD N_KZGCommitmentsInclusionProof, PartialDataColumnHeader, kzg_commitments_inclusion_proof
.endif

SSZ_FIELDS SignedBeaconBlockHeader
SSZ_DFIELD N_BeaconBlockHeader, SignedBeaconBlockHeader, message
SSZ_DFIELD N_Bytes96, SignedBeaconBlockHeader, signature

SSZ_FIELDS BeaconBlockHeader
SSZ_DFIELD N_Uint64, BeaconBlockHeader, slot
SSZ_DFIELD N_Uint64, BeaconBlockHeader, proposer_index
SSZ_DFIELD N_Bytes32, BeaconBlockHeader, parent_root
SSZ_DFIELD N_Bytes32, BeaconBlockHeader, state_root
SSZ_DFIELD N_Bytes32, BeaconBlockHeader, body_root

SSZ_FIELDS Deposit
SSZ_DFIELD N_DepositProof, Deposit, proof
SSZ_DFIELD N_DepositData, Deposit, data

SSZ_FIELDS DepositData
SSZ_DFIELD N_Bytes48, DepositData, pubkey
SSZ_DFIELD N_Bytes32, DepositData, withdrawal_credentials
SSZ_DFIELD N_Uint64, DepositData, amount
SSZ_DFIELD N_Bytes96, DepositData, signature

SSZ_FIELDS SignedVoluntaryExit
SSZ_DFIELD N_VoluntaryExit, SignedVoluntaryExit, message
SSZ_DFIELD N_Bytes96, SignedVoluntaryExit, signature

SSZ_FIELDS VoluntaryExit
SSZ_DFIELD N_Uint64, VoluntaryExit, epoch
SSZ_DFIELD N_Uint64, VoluntaryExit, validator_index

.if FORK >= FORK_ALTAIR
SSZ_FIELDS SyncAggregate
SSZ_DFIELD N_SyncCommitteeBits, SyncAggregate, sync_committee_bits
SSZ_DFIELD N_Bytes96, SyncAggregate, sync_committee_signature
.endif

.if FORK >= FORK_CAPELLA
SSZ_FIELDS GetPayloadResult
SSZ_DFIELD N_ExecutionPayload, GetPayloadResult, execution_payload
SSZ_DFIELD N_Uint256, GetPayloadResult, block_value
.if FORK >= FORK_DENEB
SSZ_DFIELD N_BlobsBundle, GetPayloadResult, blobs_bundle
SSZ_DFIELD N_Boolean, GetPayloadResult, should_override_builder
.endif
.if FORK >= FORK_ELECTRA
SSZ_DFIELD N_ExecutionRequestsList, GetPayloadResult, execution_requests
.endif
.endif

.if FORK >= FORK_DENEB
SSZ_FIELDS BlobsBundle
SSZ_DFIELD N_BlobKZGCommitments, BlobsBundle, commitments
SSZ_DFIELD N_BundleProofs, BlobsBundle, proofs
SSZ_DFIELD N_BundleBlobs, BlobsBundle, blobs
.endif

.if FORK >= FORK_BELLATRIX
SSZ_FIELDS ExecutionPayload
SSZ_DFIELD N_Bytes32, ExecutionPayload, parent_hash
SSZ_DFIELD N_Bytes20, ExecutionPayload, fee_recipient
SSZ_DFIELD N_Bytes32, ExecutionPayload, state_root
SSZ_DFIELD N_Bytes32, ExecutionPayload, receipts_root
SSZ_DFIELD N_LogsBloom, ExecutionPayload, logs_bloom
SSZ_DFIELD N_Bytes32, ExecutionPayload, prev_randao
SSZ_DFIELD N_Uint64, ExecutionPayload, block_number
SSZ_DFIELD N_Uint64, ExecutionPayload, gas_limit
SSZ_DFIELD N_Uint64, ExecutionPayload, gas_used
SSZ_DFIELD N_Uint64, ExecutionPayload, timestamp
SSZ_DFIELD N_ExtraData, ExecutionPayload, extra_data
SSZ_DFIELD N_Uint256, ExecutionPayload, base_fee_per_gas
SSZ_DFIELD N_Bytes32, ExecutionPayload, block_hash
SSZ_DFIELD N_Transactions, ExecutionPayload, transactions
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_Withdrawals, ExecutionPayload, withdrawals
.endif
.if FORK >= FORK_DENEB
SSZ_DFIELD N_Uint64, ExecutionPayload, blob_gas_used
.endif
.if FORK >= FORK_DENEB
SSZ_DFIELD N_Uint64, ExecutionPayload, excess_blob_gas
.endif
.endif

.if FORK >= FORK_BELLATRIX
SSZ_FIELDS ExecutionPayloadHeader
SSZ_DFIELD N_Bytes32, ExecutionPayloadHeader, parent_hash
SSZ_DFIELD N_Bytes20, ExecutionPayloadHeader, fee_recipient
SSZ_DFIELD N_Bytes32, ExecutionPayloadHeader, state_root
SSZ_DFIELD N_Bytes32, ExecutionPayloadHeader, receipts_root
SSZ_DFIELD N_LogsBloom, ExecutionPayloadHeader, logs_bloom
SSZ_DFIELD N_Bytes32, ExecutionPayloadHeader, prev_randao
SSZ_DFIELD N_Uint64, ExecutionPayloadHeader, block_number
SSZ_DFIELD N_Uint64, ExecutionPayloadHeader, gas_limit
SSZ_DFIELD N_Uint64, ExecutionPayloadHeader, gas_used
SSZ_DFIELD N_Uint64, ExecutionPayloadHeader, timestamp
SSZ_DFIELD N_ExtraData, ExecutionPayloadHeader, extra_data
SSZ_DFIELD N_Uint256, ExecutionPayloadHeader, base_fee_per_gas
SSZ_DFIELD N_Bytes32, ExecutionPayloadHeader, block_hash
SSZ_DFIELD N_Bytes32, ExecutionPayloadHeader, transactions_root
.if FORK >= FORK_CAPELLA
SSZ_DFIELD N_Bytes32, ExecutionPayloadHeader, withdrawals_root
.endif
.if FORK >= FORK_DENEB
SSZ_DFIELD N_Uint64, ExecutionPayloadHeader, blob_gas_used
.endif
.if FORK >= FORK_DENEB
SSZ_DFIELD N_Uint64, ExecutionPayloadHeader, excess_blob_gas
.endif
.endif

.if FORK >= FORK_BELLATRIX
SSZ_FIELDS PowBlock
SSZ_DFIELD N_Bytes32, PowBlock, block_hash
SSZ_DFIELD N_Bytes32, PowBlock, parent_hash
SSZ_DFIELD N_Uint256, PowBlock, total_difficulty
.endif

.if FORK >= FORK_CAPELLA
SSZ_FIELDS Withdrawal
SSZ_DFIELD N_Uint64, Withdrawal, index
SSZ_DFIELD N_Uint64, Withdrawal, validator_index
SSZ_DFIELD N_Bytes20, Withdrawal, address
SSZ_DFIELD N_Uint64, Withdrawal, amount
.endif

.if FORK >= FORK_CAPELLA
SSZ_FIELDS SignedBLSToExecutionChange
SSZ_DFIELD N_BLSToExecutionChange, SignedBLSToExecutionChange, message
SSZ_DFIELD N_Bytes96, SignedBLSToExecutionChange, signature
.endif

.if FORK >= FORK_CAPELLA
SSZ_FIELDS BLSToExecutionChange
SSZ_DFIELD N_Uint64, BLSToExecutionChange, validator_index
SSZ_DFIELD N_Bytes48, BLSToExecutionChange, from_bls_pubkey
SSZ_DFIELD N_Bytes20, BLSToExecutionChange, to_execution_address
.endif

.if FORK >= FORK_ELECTRA
SSZ_FIELDS ExecutionRequests
SSZ_DFIELD N_DepositRequests, ExecutionRequests, deposits
SSZ_DFIELD N_WithdrawalRequests, ExecutionRequests, withdrawals
SSZ_DFIELD N_ConsolidationRequests, ExecutionRequests, consolidations
.endif

.if FORK >= FORK_ELECTRA
SSZ_FIELDS DepositRequest
SSZ_DFIELD N_Bytes48, DepositRequest, pubkey
SSZ_DFIELD N_Bytes32, DepositRequest, withdrawal_credentials
SSZ_DFIELD N_Uint64, DepositRequest, amount
SSZ_DFIELD N_Bytes96, DepositRequest, signature
SSZ_DFIELD N_Uint64, DepositRequest, index
.endif

.if FORK >= FORK_ELECTRA
SSZ_FIELDS WithdrawalRequest
SSZ_DFIELD N_Bytes20, WithdrawalRequest, source_address
SSZ_DFIELD N_Bytes48, WithdrawalRequest, validator_pubkey
SSZ_DFIELD N_Uint64, WithdrawalRequest, amount
.endif

.if FORK >= FORK_ELECTRA
SSZ_FIELDS ConsolidationRequest
SSZ_DFIELD N_Bytes20, ConsolidationRequest, source_address
SSZ_DFIELD N_Bytes48, ConsolidationRequest, source_pubkey
SSZ_DFIELD N_Bytes48, ConsolidationRequest, target_pubkey
.endif

SSZ_FIELDS Eth1Data
SSZ_DFIELD N_Bytes32, Eth1Data, deposit_root
SSZ_DFIELD N_Uint64, Eth1Data, deposit_count
SSZ_DFIELD N_Bytes32, Eth1Data, block_hash

SSZ_FIELDS Fork
SSZ_DFIELD N_Bytes4, Fork, previous_version
SSZ_DFIELD N_Bytes4, Fork, current_version
SSZ_DFIELD N_Uint64, Fork, epoch

SSZ_FIELDS Validator
SSZ_DFIELD N_Bytes48, Validator, pubkey
SSZ_DFIELD N_Bytes32, Validator, withdrawal_credentials
SSZ_DFIELD N_Uint64, Validator, effective_balance
SSZ_DFIELD N_Boolean, Validator, slashed
SSZ_DFIELD N_Uint64, Validator, activation_eligibility_epoch
SSZ_DFIELD N_Uint64, Validator, activation_epoch
SSZ_DFIELD N_Uint64, Validator, exit_epoch
SSZ_DFIELD N_Uint64, Validator, withdrawable_epoch

.if FORK >= FORK_ALTAIR
SSZ_FIELDS SyncCommittee
SSZ_DFIELD N_SyncCommitteePubkeys, SyncCommittee, pubkeys
SSZ_DFIELD N_Bytes48, SyncCommittee, aggregate_pubkey
.endif

.if FORK >= FORK_CAPELLA
SSZ_FIELDS HistoricalSummary
SSZ_DFIELD N_Bytes32, HistoricalSummary, block_summary_root
SSZ_DFIELD N_Bytes32, HistoricalSummary, state_summary_root
.endif

.if FORK >= FORK_ELECTRA
SSZ_FIELDS PendingDeposit
SSZ_DFIELD N_Bytes48, PendingDeposit, pubkey
SSZ_DFIELD N_Bytes32, PendingDeposit, withdrawal_credentials
SSZ_DFIELD N_Uint64, PendingDeposit, amount
SSZ_DFIELD N_Bytes96, PendingDeposit, signature
SSZ_DFIELD N_Uint64, PendingDeposit, slot
.endif

.if FORK >= FORK_ELECTRA
SSZ_FIELDS PendingPartialWithdrawal
SSZ_DFIELD N_Uint64, PendingPartialWithdrawal, validator_index
SSZ_DFIELD N_Uint64, PendingPartialWithdrawal, amount
SSZ_DFIELD N_Uint64, PendingPartialWithdrawal, withdrawable_epoch
.endif

.if FORK >= FORK_ELECTRA
SSZ_FIELDS PendingConsolidation
SSZ_DFIELD N_Uint64, PendingConsolidation, source_index
SSZ_DFIELD N_Uint64, PendingConsolidation, target_index
.endif

.if FORK >= FORK_ALTAIR
SSZ_FIELDS SignedContributionAndProof
SSZ_DFIELD N_ContributionAndProof, SignedContributionAndProof, message
SSZ_DFIELD N_Bytes96, SignedContributionAndProof, signature
.endif

.if FORK >= FORK_ALTAIR
SSZ_FIELDS ContributionAndProof
SSZ_DFIELD N_Uint64, ContributionAndProof, aggregator_index
SSZ_DFIELD N_SyncCommitteeContribution, ContributionAndProof, contribution
SSZ_DFIELD N_Bytes96, ContributionAndProof, selection_proof
.endif

.if FORK >= FORK_ALTAIR
SSZ_FIELDS SyncCommitteeContribution
SSZ_DFIELD N_Uint64, SyncCommitteeContribution, slot
SSZ_DFIELD N_Bytes32, SyncCommitteeContribution, beacon_block_root
SSZ_DFIELD N_Uint64, SyncCommitteeContribution, subcommittee_index
SSZ_DFIELD N_SyncSubcommitteeBits, SyncCommitteeContribution, aggregation_bits
SSZ_DFIELD N_Bytes96, SyncCommitteeContribution, signature
.endif

.if FORK >= FORK_ALTAIR
SSZ_FIELDS SyncCommitteeMessage
SSZ_DFIELD N_Uint64, SyncCommitteeMessage, slot
SSZ_DFIELD N_Bytes32, SyncCommitteeMessage, beacon_block_root
SSZ_DFIELD N_Uint64, SyncCommitteeMessage, validator_index
SSZ_DFIELD N_Bytes96, SyncCommitteeMessage, signature
.endif

.if FORK >= FORK_ALTAIR
SSZ_FIELDS SyncAggregatorSelectionData
SSZ_DFIELD N_Uint64, SyncAggregatorSelectionData, slot
SSZ_DFIELD N_Uint64, SyncAggregatorSelectionData, subcommittee_index
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS DataColumnSidecarsByRangeRequest
SSZ_DFIELD N_Uint64, DataColumnSidecarsByRangeRequest, start_slot
SSZ_DFIELD N_Uint64, DataColumnSidecarsByRangeRequest, count
SSZ_DFIELD N_DataColumnIndices, DataColumnSidecarsByRangeRequest, columns

SSZ_FIELDS DataColumnsByRootIdentifier
SSZ_DFIELD N_Bytes32, DataColumnsByRootIdentifier, block_root
SSZ_DFIELD N_DataColumnIndices, DataColumnsByRootIdentifier, columns
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS PartialDataColumnPartsMetadata
SSZ_DFIELD N_CellsBitList, PartialDataColumnPartsMetadata, available
SSZ_DFIELD N_CellsBitList, PartialDataColumnPartsMetadata, requests
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS PartialDataColumnGroupID
SSZ_DFIELD N_Bytes32, PartialDataColumnGroupID, beacon_block_root
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS MatrixEntry
SSZ_DFIELD N_Cell, MatrixEntry, cell
SSZ_DFIELD N_Bytes48, MatrixEntry, kzg_proof
SSZ_DFIELD N_Uint64, MatrixEntry, column_index
SSZ_DFIELD N_Uint64, MatrixEntry, row_index
.endif

SSZ_FIELDS Status
SSZ_DFIELD N_Bytes4, Status, fork_digest
SSZ_DFIELD N_Bytes32, Status, finalized_root
SSZ_DFIELD N_Uint64, Status, finalized_epoch
SSZ_DFIELD N_Bytes32, Status, head_root
SSZ_DFIELD N_Uint64, Status, head_slot

.if FORK >= FORK_FULU
SSZ_FIELDS StatusV2
SSZ_DFIELD N_Bytes4, StatusV2, fork_digest
SSZ_DFIELD N_Bytes32, StatusV2, finalized_root
SSZ_DFIELD N_Uint64, StatusV2, finalized_epoch
SSZ_DFIELD N_Bytes32, StatusV2, head_root
SSZ_DFIELD N_Uint64, StatusV2, head_slot
SSZ_DFIELD N_Uint64, StatusV2, earliest_available_slot
.endif

SSZ_FIELDS MetaData
SSZ_DFIELD N_Uint64, MetaData, seq_number
SSZ_DFIELD N_Attnets, MetaData, attnets

.if FORK >= FORK_ALTAIR
SSZ_FIELDS MetaDataV2
SSZ_DFIELD N_Uint64, MetaDataV2, seq_number
SSZ_DFIELD N_Attnets, MetaDataV2, attnets
SSZ_DFIELD N_Syncnets, MetaDataV2, syncnets
.endif

.if FORK >= FORK_FULU
SSZ_FIELDS MetaDataV3
SSZ_DFIELD N_Uint64, MetaDataV3, seq_number
SSZ_DFIELD N_Attnets, MetaDataV3, attnets
SSZ_DFIELD N_Syncnets, MetaDataV3, syncnets
SSZ_DFIELD N_Uint64, MetaDataV3, custody_group_count
.endif

SSZ_FIELDS BeaconBlocksByRangeRequest
SSZ_DFIELD N_Uint64, BeaconBlocksByRangeRequest, start_slot
SSZ_DFIELD N_Uint64, BeaconBlocksByRangeRequest, count
SSZ_DFIELD N_Uint64, BeaconBlocksByRangeRequest, step

.if FORK >= FORK_FULU
SSZ_FIELDS BeaconBlocksByHeadRequest
SSZ_DFIELD N_Bytes32, BeaconBlocksByHeadRequest, beacon_root
SSZ_DFIELD N_Uint64, BeaconBlocksByHeadRequest, count
.endif

SSZ_FIELDS ENRForkID
SSZ_DFIELD N_Bytes4, ENRForkID, fork_digest
SSZ_DFIELD N_Bytes4, ENRForkID, next_fork_version
SSZ_DFIELD N_Uint64, ENRForkID, next_fork_epoch

SSZ_FIELDS SigningData
SSZ_DFIELD N_Bytes32, SigningData, object_root
SSZ_DFIELD N_Bytes32, SigningData, domain

SSZ_FIELDS ForkData
SSZ_DFIELD N_Bytes4, ForkData, current_version
SSZ_DFIELD N_Bytes32, ForkData, genesis_validators_root

SSZ_FIELDS DepositMessage
SSZ_DFIELD N_Bytes48, DepositMessage, pubkey
SSZ_DFIELD N_Bytes32, DepositMessage, withdrawal_credentials
SSZ_DFIELD N_Uint64, DepositMessage, amount

SSZ_FIELDS BeaconCommitteeSubscription
SSZ_DFIELD N_Uint64, BeaconCommitteeSubscription, validator_index
SSZ_DFIELD N_Uint64, BeaconCommitteeSubscription, committee_index
SSZ_DFIELD N_Uint64, BeaconCommitteeSubscription, committees_at_slot
SSZ_DFIELD N_Uint64, BeaconCommitteeSubscription, slot
SSZ_DFIELD N_Boolean, BeaconCommitteeSubscription, is_aggregator

.if FORK >= FORK_ALTAIR
SSZ_FIELDS SyncCommitteeSubscription
SSZ_DFIELD N_Uint64, SyncCommitteeSubscription, validator_index
SSZ_DFIELD N_SyncCommitteeIndices, SyncCommitteeSubscription, sync_committee_indices
SSZ_DFIELD N_Uint64, SyncCommitteeSubscription, until_epoch
.endif

SSZ_FIELDS ProposerPreparation
SSZ_DFIELD N_Uint64, ProposerPreparation, validator_index
SSZ_DFIELD N_Bytes20, ProposerPreparation, fee_recipient
