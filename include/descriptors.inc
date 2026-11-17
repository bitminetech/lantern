/*
 * The asm-ssz type descriptors of the types of one fork in include/types.inc.
 *
 * Every type has one TypeNode in one shared node table, and every container
 * field one TypeField in one shared field table. Each root type that lantern
 * passes to asm-ssz has its own 48-byte TypeDescriptor header, labelled
 * lantern_type_T. The headers come first, then the node table, then the
 * field table, so each header's nodes.offset and fields.offset point forward
 * to the shared tables and its root names its own node. A type has a lower
 * node index than every type inside it, as asm-ssz requires.
 *
 * The core includes this file once, in its read only data. The node and root
 * lists and the field records are written by hand; the emitting macros check
 * every index against its plan.
 */

/* ------------------------------------------------------------ Lists */

/*
 * Every type, in node order: its name, then its element node for a vector or
 * list, or its first field record for a container.
 */
.macro SSZ_NODES m
    \m SignedBeaconBlock, F_SignedBeaconBlock
    \m BeaconBlock, F_BeaconBlock
    \m BeaconBlockBody, F_BeaconBlockBody
    \m BeaconState, F_BeaconState
    .if FORK == FORK_PHASE0
    \m PendingAttestations, N_PendingAttestation
    \m PendingAttestation, F_PendingAttestation
    .endif
    .if FORK <= FORK_BELLATRIX
    \m HistoricalBatch, F_HistoricalBatch
    .endif
    \m SignedAggregateAndProof, F_SignedAggregateAndProof
    \m AggregateAndProof, F_AggregateAndProof
    \m Attestations, N_Attestation
    \m Attestation, F_Attestation
    \m AttesterSlashings, N_AttesterSlashing
    \m AttesterSlashing, F_AttesterSlashing
    \m IndexedAttestation, F_IndexedAttestation
    .if FORK >= FORK_ELECTRA
    \m SingleAttestation, F_SingleAttestation
    .endif
    \m AttestationData, F_AttestationData
    \m Checkpoint, F_Checkpoint
    \m ProposerSlashings, N_ProposerSlashing
    \m ProposerSlashing, F_ProposerSlashing
    .if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    \m BlobSidecar, F_BlobSidecar
    \m BlobIdentifier, F_BlobIdentifier
    .endif
    .if FORK >= FORK_FULU
    \m DataColumnSidecar, F_DataColumnSidecar
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnSidecar, F_PartialDataColumnSidecar
    .endif
    .if FORK >= FORK_FULU
    \m OptionalPartialDataColumnHeader, N_PartialDataColumnHeader
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnHeader, F_PartialDataColumnHeader
    .endif
    \m SignedBeaconBlockHeader, F_SignedBeaconBlockHeader
    \m BeaconBlockHeader, F_BeaconBlockHeader
    \m Deposits, N_Deposit
    \m Deposit, F_Deposit
    \m DepositData, F_DepositData
    \m VoluntaryExits, N_SignedVoluntaryExit
    \m SignedVoluntaryExit, F_SignedVoluntaryExit
    \m VoluntaryExit, F_VoluntaryExit
    .if FORK >= FORK_ALTAIR
    \m SyncAggregate, F_SyncAggregate
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayload, F_ExecutionPayload
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayloadHeader, F_ExecutionPayloadHeader
    .endif
    .if FORK >= FORK_BELLATRIX
    \m Transactions, N_Transaction
    .endif
    .if FORK >= FORK_BELLATRIX
    \m Transaction
    .endif
    .if FORK >= FORK_CAPELLA
    \m Withdrawals, N_Withdrawal
    .endif
    .if FORK >= FORK_CAPELLA
    \m Withdrawal, F_Withdrawal
    .endif
    .if FORK >= FORK_CAPELLA
    \m BLSToExecutionChanges, N_SignedBLSToExecutionChange
    .endif
    .if FORK >= FORK_CAPELLA
    \m SignedBLSToExecutionChange, F_SignedBLSToExecutionChange
    .endif
    .if FORK >= FORK_CAPELLA
    \m BLSToExecutionChange, F_BLSToExecutionChange
    .endif
    .if FORK >= FORK_ELECTRA
    \m ExecutionRequests, F_ExecutionRequests
    .endif
    .if FORK >= FORK_ELECTRA
    \m DepositRequests, N_DepositRequest
    .endif
    .if FORK >= FORK_ELECTRA
    \m DepositRequest, F_DepositRequest
    .endif
    .if FORK >= FORK_ELECTRA
    \m WithdrawalRequests, N_WithdrawalRequest
    .endif
    .if FORK >= FORK_ELECTRA
    \m WithdrawalRequest, F_WithdrawalRequest
    .endif
    .if FORK >= FORK_ELECTRA
    \m ConsolidationRequests, N_ConsolidationRequest
    .endif
    .if FORK >= FORK_ELECTRA
    \m ConsolidationRequest, F_ConsolidationRequest
    .endif
    \m Eth1DataVotes, N_Eth1Data
    \m Eth1Data, F_Eth1Data
    \m Fork, F_Fork
    \m Validators, N_Validator
    \m Validator, F_Validator
    .if FORK >= FORK_ALTAIR
    \m SyncCommittee, F_SyncCommittee
    .endif
    .if FORK >= FORK_CAPELLA
    \m HistoricalSummaries, N_HistoricalSummary
    .endif
    .if FORK >= FORK_CAPELLA
    \m HistoricalSummary, F_HistoricalSummary
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingDeposits, N_PendingDeposit
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingDeposit, F_PendingDeposit
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingPartialWithdrawals, N_PendingPartialWithdrawal
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingPartialWithdrawal, F_PendingPartialWithdrawal
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingConsolidations, N_PendingConsolidation
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingConsolidation, F_PendingConsolidation
    .endif
    .if FORK >= FORK_ALTAIR
    \m SignedContributionAndProof, F_SignedContributionAndProof
    .endif
    .if FORK >= FORK_ALTAIR
    \m ContributionAndProof, F_ContributionAndProof
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeContribution, F_SyncCommitteeContribution
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeMessage, F_SyncCommitteeMessage
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncAggregatorSelectionData, F_SyncAggregatorSelectionData
    .endif
    .if FORK >= FORK_FULU
    \m DataColumnsByRootIdentifier, F_DataColumnsByRootIdentifier
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnPartsMetadata, F_PartialDataColumnPartsMetadata
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnGroupID, F_PartialDataColumnGroupID
    .endif
    .if FORK >= FORK_FULU
    \m MatrixEntry, F_MatrixEntry
    .endif
    \m SigningData, F_SigningData
    \m ForkData, F_ForkData
    \m DepositMessage, F_DepositMessage
    \m BlockRoots, N_Bytes32
    \m HistoricalRoots, N_Bytes32
    \m RandaoMixes, N_Bytes32
    \m Slashings, N_Uint64
    \m Balances, N_Uint64
    .if FORK >= FORK_ALTAIR
    \m EpochParticipation, N_Uint8
    .endif
    .if FORK >= FORK_FULU
    \m ProposerLookahead, N_Uint64
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteePubkeys, N_Bytes48
    .endif
    \m DepositProof, N_Bytes32
    \m AttestingIndices, N_Uint64
    .if FORK >= FORK_DENEB
    \m BlobKZGCommitments, N_Bytes48
    .endif
    .if FORK >= FORK_FULU
    \m DataColumn, N_Cell
    .endif
    .if FORK >= FORK_FULU
    \m KZGCommitmentsInclusionProof, N_Bytes32
    .endif
    .if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    \m KZGCommitmentInclusionProof, N_Bytes32
    .endif
    .if FORK >= FORK_FULU
    \m DataColumnIndices, N_Uint64
    .endif
    .if FORK >= FORK_BELLATRIX
    \m LogsBloom
    .endif
    .if FORK >= FORK_FULU
    \m Cell
    .endif
    .if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    \m Blob
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExtraData
    .endif
    \m JustificationBits
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeBits
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncSubcommitteeBits
    .endif
    .if FORK >= FORK_ELECTRA
    \m CommitteeBits
    .endif
    \m AggregationBits
    .if FORK >= FORK_FULU
    \m CellsBitList
    .endif
    \m Bytes4
    \m Bytes20
    \m Bytes32
    \m Bytes48
    \m Bytes96
    \m Uint8
    \m Uint64
    .if FORK >= FORK_BELLATRIX
    \m Uint256
    .endif
    \m Boolean
.endm

/* The root types, each with its own header, in header order. */
.macro SSZ_ROOTS m
    \m SignedBeaconBlock
    \m BeaconBlock
    \m BeaconBlockBody
    \m BeaconState
    .if FORK == FORK_PHASE0
    \m PendingAttestation
    .endif
    .if FORK <= FORK_BELLATRIX
    \m HistoricalBatch
    .endif
    \m SignedAggregateAndProof
    \m AggregateAndProof
    \m Attestation
    \m AttesterSlashing
    \m IndexedAttestation
    .if FORK >= FORK_ELECTRA
    \m SingleAttestation
    .endif
    \m AttestationData
    \m Checkpoint
    \m ProposerSlashing
    .if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    \m BlobSidecar
    \m BlobIdentifier
    .endif
    .if FORK >= FORK_FULU
    \m DataColumnSidecar
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnSidecar
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnHeader
    .endif
    \m SignedBeaconBlockHeader
    \m BeaconBlockHeader
    \m Deposit
    \m DepositData
    \m SignedVoluntaryExit
    \m VoluntaryExit
    .if FORK >= FORK_ALTAIR
    \m SyncAggregate
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayload
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayloadHeader
    .endif
    .if FORK >= FORK_BELLATRIX
    \m Transactions
    .endif
    .if FORK >= FORK_CAPELLA
    \m Withdrawals
    .endif
    .if FORK >= FORK_CAPELLA
    \m Withdrawal
    .endif
    .if FORK >= FORK_CAPELLA
    \m SignedBLSToExecutionChange
    .endif
    .if FORK >= FORK_CAPELLA
    \m BLSToExecutionChange
    .endif
    .if FORK >= FORK_ELECTRA
    \m ExecutionRequests
    .endif
    .if FORK >= FORK_ELECTRA
    \m DepositRequests
    .endif
    .if FORK >= FORK_ELECTRA
    \m DepositRequest
    .endif
    .if FORK >= FORK_ELECTRA
    \m WithdrawalRequests
    .endif
    .if FORK >= FORK_ELECTRA
    \m WithdrawalRequest
    .endif
    .if FORK >= FORK_ELECTRA
    \m ConsolidationRequests
    .endif
    .if FORK >= FORK_ELECTRA
    \m ConsolidationRequest
    .endif
    \m Eth1Data
    \m Fork
    \m Validator
    .if FORK >= FORK_ALTAIR
    \m SyncCommittee
    .endif
    .if FORK >= FORK_CAPELLA
    \m HistoricalSummary
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingDeposit
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingPartialWithdrawal
    .endif
    .if FORK >= FORK_ELECTRA
    \m PendingConsolidation
    .endif
    .if FORK >= FORK_ALTAIR
    \m SignedContributionAndProof
    .endif
    .if FORK >= FORK_ALTAIR
    \m ContributionAndProof
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeContribution
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeMessage
    .endif
    .if FORK >= FORK_ALTAIR
    \m SyncAggregatorSelectionData
    .endif
    .if FORK >= FORK_FULU
    \m DataColumnsByRootIdentifier
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnPartsMetadata
    .endif
    .if FORK >= FORK_FULU
    \m PartialDataColumnGroupID
    .endif
    .if FORK >= FORK_FULU
    \m MatrixEntry
    .endif
    \m SigningData
    \m ForkData
    \m DepositMessage
    \m BlockRoots
    \m Bytes32
    \m Uint64
    .if FORK >= FORK_DENEB
    \m BlobKZGCommitments
    .endif
.endm

/* ------------------------------------------------------------ Plan: node, field and header indices */

/* N_T: the node of T. F_T: the first field record of container T. Field records follow node order. */
.set SSZ_NC, 0
.set SSZ_FC, 0
.macro SSZ_PLAN T, element=0
    .set N_\T, SSZ_NC
    .set SSZ_NC, SSZ_NC + 1
    .if \T\()__kind == SSZ_KIND_CONTAINER
    .set F_\T, SSZ_FC
    .set SSZ_FC, SSZ_FC + \T\()__len
    .endif
.endm
SSZ_NODES SSZ_PLAN

/* H_T: the header of root type T. */
.set SSZ_HC, 0
.macro SSZ_HEADER_INDEX T
    .set H_\T, SSZ_HC
    .set SSZ_HC, SSZ_HC + 1
.endm
SSZ_ROOTS SSZ_HEADER_INDEX

/* ------------------------------------------------------------ Emitting macros */

/* The header of root type T, which must be the next header. */
.macro SSZ_HEADER T
    .if (. - lantern_types_headers) != H_\T * SSZ_DESC_FIXED
    .error "SSZ_HEADER: out of order"
    .endif
lantern_type_\T:
    .quad SSZ_DESC_FIXED * (SSZ_HC - H_\T) + SSZ_NC * SSZ_NODE_STRIDE + SSZ_FC * SSZ_FIELD_STRIDE
    .quad SSZ_DESC_FIXED * (SSZ_HC - H_\T)
    .quad SSZ_NC
    .quad SSZ_DESC_FIXED * (SSZ_HC - H_\T) + SSZ_NC * SSZ_NODE_STRIDE
    .quad SSZ_FC
    .quad N_\T
.endm

/* The TypeNode of T, which must be the next node. */
.macro SSZ_NODE_AT T, element=0
    .if (. - lantern_types_nodes) != N_\T * SSZ_NODE_STRIDE
    .error "SSZ_NODE_AT: out of order"
    .endif
    SSZ_NODE \T, \element
.endm

/* The TypeFields of container T start here. */
.macro SSZ_FIELDS T
    .if (. - lantern_types_fields) != F_\T * SSZ_FIELD_STRIDE
    .error "SSZ_FIELDS: out of order or a field is missing"
    .endif
.endm

/* ------------------------------------------------------------ Headers and nodes */

    .p2align 3
lantern_types_headers:
SSZ_ROOTS SSZ_HEADER
lantern_types_nodes:
SSZ_NODES SSZ_NODE_AT

/* ------------------------------------------------------------ Fields */

lantern_types_fields:
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

lantern_types_end:
    .if (lantern_types_nodes - lantern_types_headers) != SSZ_HC * SSZ_DESC_FIXED
    .error "descriptors: a header is missing"
    .endif
    .if (lantern_types_fields - lantern_types_nodes) != SSZ_NC * SSZ_NODE_STRIDE
    .error "descriptors: a node is missing"
    .endif
    .if (lantern_types_end - lantern_types_fields) != SSZ_FC * SSZ_FIELD_STRIDE
    .error "descriptors: a field is missing"
    .endif

/* ------------------------------------------------------------ Type table for the tests */

/*
 * lantern_<fork>_types (FORK_DATA, include/forks.inc): u64 count, then for each root type
 * the distance back from the table to its header and to its name (a zero ended string).
 */
.macro SSZ_NAME T
lantern_type_name_\T:
    .asciz "\T"
.endm

.macro SSZ_TABLE_ENTRY T
    .quad lantern_types_table - lantern_type_\T
    .quad lantern_types_table - lantern_type_name_\T
.endm

SSZ_ROOTS SSZ_NAME
    .p2align 3
FORK_DATA types
lantern_types_table:
    .quad SSZ_HC
SSZ_ROOTS SSZ_TABLE_ENTRY
