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
    .if FORK >= FORK_ALTAIR
    \m LightClientBootstrap, F_LightClientBootstrap
    \m LightClientUpdate, F_LightClientUpdate
    \m LightClientFinalityUpdate, F_LightClientFinalityUpdate
    \m LightClientOptimisticUpdate, F_LightClientOptimisticUpdate
    \m LightClientHeader, F_LightClientHeader
    \m SyncCommitteeBranch, N_Bytes32
    \m FinalityBranch, N_Bytes32
    .endif
    .if FORK >= FORK_CAPELLA
    \m ExecutionBranch, N_Bytes32
    .endif
    .if FORK >= FORK_DENEB
    \m BlockContents, F_BlockContents
    \m SignedBlockContents, F_SignedBlockContents
    .endif
    \m SignedBeaconBlock, F_SignedBeaconBlock
    \m BeaconBlock, F_BeaconBlock
    \m BeaconBlockBody, F_BeaconBlockBody
    .if FORK >= FORK_BELLATRIX
    \m SignedBlindedBeaconBlock, F_SignedBlindedBeaconBlock
    \m BlindedBeaconBlock, F_BlindedBeaconBlock
    \m BlindedBeaconBlockBody, F_BlindedBeaconBlockBody
    .endif
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
    \m BlobSidecarsByRangeRequest, F_BlobSidecarsByRangeRequest
    \m BlobIdentifiers, N_BlobIdentifier
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
    .if FORK >= FORK_CAPELLA
    \m GetPayloadResult, F_GetPayloadResult
    .endif
    .if FORK >= FORK_DENEB
    \m BlobsBundle, F_BlobsBundle
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayload, F_ExecutionPayload
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayloadHeader, F_ExecutionPayloadHeader
    .endif
    .if FORK >= FORK_BELLATRIX
    \m PowBlock, F_PowBlock
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
    \m DataColumnSidecarsByRangeRequest, F_DataColumnSidecarsByRangeRequest
    .endif
    .if FORK >= FORK_FULU
    \m DataColumnsByRootIdentifiers, N_DataColumnsByRootIdentifier
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
    \m Status, F_Status
    .if FORK >= FORK_FULU
    \m StatusV2, F_StatusV2
    .endif
    \m MetaData, F_MetaData
    .if FORK >= FORK_ALTAIR
    \m MetaDataV2, F_MetaDataV2
    .endif
    .if FORK >= FORK_FULU
    \m MetaDataV3, F_MetaDataV3
    .endif
    \m BeaconBlocksByRangeRequest, F_BeaconBlocksByRangeRequest
    .if FORK >= FORK_FULU
    \m BeaconBlocksByHeadRequest, F_BeaconBlocksByHeadRequest
    .endif
    \m ENRForkID, F_ENRForkID
    \m SigningData, F_SigningData
    \m ForkData, F_ForkData
    \m DepositMessage, F_DepositMessage
    \m BeaconCommitteeSubscription, F_BeaconCommitteeSubscription
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeSubscription, F_SyncCommitteeSubscription
    .endif
    \m ProposerPreparation, F_ProposerPreparation
    \m BlockRoots, N_Bytes32
    \m BeaconBlockRoots, N_Bytes32
    \m ErrorMessage, N_Uint8
    \m HistoricalRoots, N_Bytes32
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeIndices, N_Uint64
    .endif
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
    \m BundleProofs, N_Bytes48
    \m BundleBlobs, N_Blob
    .endif
    .if FORK >= FORK_ELECTRA
    \m ExecutionRequestsList, N_RequestBytes
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
    .if FORK >= FORK_DENEB
    \m Blob
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExtraData
    .endif
    .if FORK >= FORK_ELECTRA
    \m RequestBytes
    .endif
    \m JustificationBits
    \m Attnets
    .if FORK >= FORK_ALTAIR
    \m Syncnets
    .endif
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
    .if FORK >= FORK_ALTAIR
    \m LightClientBootstrap
    \m LightClientUpdate
    \m LightClientFinalityUpdate
    \m LightClientOptimisticUpdate
    \m LightClientHeader
    .endif
    \m SignedBeaconBlock
    \m BeaconBlock
    \m BeaconBlockBody
    .if FORK >= FORK_BELLATRIX
    \m SignedBlindedBeaconBlock
    \m BlindedBeaconBlock
    .endif
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
    \m Attestations
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
    .if FORK >= FORK_CAPELLA
    \m GetPayloadResult
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayload
    .endif
    .if FORK >= FORK_BELLATRIX
    \m ExecutionPayloadHeader
    .endif
    .if FORK >= FORK_BELLATRIX
    \m PowBlock
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
    \m ErrorMessage
    \m Status
    .if FORK >= FORK_FULU
    \m StatusV2
    .endif
    \m MetaData
    .if FORK >= FORK_ALTAIR
    \m MetaDataV2
    .endif
    .if FORK >= FORK_FULU
    \m MetaDataV3
    .endif
    \m BeaconBlocksByRangeRequest
    \m BeaconBlockRoots
    .if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    \m BlobSidecarsByRangeRequest
    \m BlobIdentifiers
    .endif
    .if FORK >= FORK_FULU
    \m DataColumnSidecarsByRangeRequest
    \m DataColumnsByRootIdentifiers
    \m BeaconBlocksByHeadRequest
    .endif
    \m ENRForkID
    \m SigningData
    \m ForkData
    \m DepositMessage
    \m BeaconCommitteeSubscription
    .if FORK >= FORK_ALTAIR
    \m SyncCommitteeSubscription
    .endif
    \m ProposerPreparation
    \m BlockRoots
    \m Bytes32
    \m Uint64
    .if FORK >= FORK_DENEB
    \m BlobKZGCommitments
    \m BlockContents
    \m SignedBlockContents
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
.include "descriptor_fields.inc"

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

/* ------------------------------------------------------------ Field names */

/*
 * The name of each field, right after the field records: 32 bytes at the index of its record,
 * the name and then zero bytes, or a name of 32 bytes alone (docs/reference/beacon-api.md,
 * lantern_json_encode).
 */
.purgem SSZ_FIELDS
.purgem SSZ_DFIELD
.macro SSZ_FIELDS T
.endm
.macro SSZ_DFIELD node, T, name
77: .ascii "\name"
    .if (. - 77b) > 32
    .error "descriptors: a field name of more than 32 bytes"
    .endif
    .space 32 - (. - 77b)
.endm
lantern_types_names:
.include "descriptor_fields.inc"
.purgem SSZ_FIELDS
.purgem SSZ_DFIELD
.macro SSZ_DFIELD node, T, name
    .quad \node, \T\()_\name, \T\()_\name\()__ssz, \T\()_\name\()__var
.endm

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
