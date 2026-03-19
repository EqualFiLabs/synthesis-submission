# Requirements Document

## Introduction

Phase 1 of the Equalis Agentic Financing protocol implements the minimum viable smart contract layer for a hackathon demo. The scope covers one complete end-to-end flow for Solo Compute financing: proposal creation → lender approval → agreement activation → encrypted credential handoff → off-chain usage metering → repayment with waterfall and fee-index distribution.

The mailbox-relayer (off-chain Fastify service) and mailbox-sdk (TypeScript ECIES library) are existing companion repositories in this workspace. This spec defines the on-chain contracts they integrate with.

Execution profile for this phase is demo-first and provider-agnostic at the core contract layer. Phase 1 defers broad invariant/differential/stress/security coverage to Phase 5.

### Explicitly Out of Scope

- Pooled financing and governance voting
- ERC-8004 trust modes (reputation, validation gating)
- ERC-8004 borrower resolution (Phase 1 sets borrower = proposal creator; full identity resolution lands in Phase 4)
- ERC-8183 ACP job lifecycle
- Collateral management (post/release/seize)
- Net draw coverage covenants
- Delinquency, default, and write-off state transitions
- Multiple on-chain provider adapters (Lambda, RunPod)
- Module encumbrance mirroring

## Glossary

- **Diamond**: EIP-2535 Diamond proxy architecture used by Equalis for upgradeable facet-based contracts
- **Facet**: A contract module within the Diamond that implements a specific set of functions
- **AgenticStorage**: The canonical Diamond storage struct at namespace `keccak256("equalis.agentic.financing.storage.v1")`
- **Proposal**: A financing request submitted by a borrower agent, following the `FinancingProposal` struct from the canonical spec
- **Agreement**: An active financing arrangement created when a proposal is activated, following the `FinancingAgreement` struct
- **Borrower**: In Phase 1, the proposal creator (`proposal.creator`). ERC-8004-based borrower resolution is deferred to Phase 4.
- **Lender**: The counterparty providing financing capital, identified by position NFT ownership
- **Relayer**: The off-chain Compute Orchestration Node (mailbox-relayer) that bridges contracts to provider APIs
- **Settlement_Asset**: The ERC-20 token (e.g. USDC) used for monetary accounting and repayment
- **Encumbrance**: Capital reserved against a lender position for an active agreement, tracked on EqualFi native rails via `LibEncumbrance.position(positionKey, poolId).directLent`
- **Encumbrance_Namespace**: `keccak256("equalis.agentic.encumbrance.v1")` — logical identifier for Agentic financing (events/reason tagging), not a function parameter in the current `LibEncumbrance` API
- **Compute_Unit_Config**: A mapping of `(settlementAsset, unitType)` (e.g. `(USDC, VENICE_TEXT_TOKEN_IN)`) to `unitPrice`
- **Compute_Policy**: Provider selection and routing metadata handled by relayer/policy layers rather than canonical proposal/agreement primitives in Phase 1
- **Envelope**: A UTF-8 encoded JSON string containing ECIES cipher fields (`iv`, `ephemPublicKey`, `ciphertext`, `mac`), compatible with `@equalfi/mailbox-sdk`
- **Waterfall**: The repayment application order: fees first, then interest, then principal
- **Fee_Split**: The 70/30 division of repayment revenue (`toFees + toInterest`) between lender rail (70%) and protocol rail (30%); principal is not fee-split
- **LibEncumbrance**: Existing Equalis library for native encumbrance tracking per position key
- **LibFeeRouter**: Existing Equalis library for routing protocol fee share to treasury/ACI/FI splits
- **LibPositionNFT**: Existing Equalis library for position NFT ownership validation
- **Relayer_Role**: An access-control role granting permission to call usage registration and provider payload publication functions

## Requirements

### Requirement 1: Diamond Storage Initialization

**User Story:** As a protocol deployer, I want the agentic financing storage to be initialized within the Diamond namespace, so that all facets share consistent state without storage collisions.

#### Acceptance Criteria

1. THE AgenticStorage SHALL use storage position `keccak256("equalis.agentic.financing.storage.v1")`
2. THE AgenticStorage SHALL initialize `nextProposalId` to 1
3. THE AgenticStorage SHALL initialize `nextAgreementId` to 1
4. WHEN a Facet reads AgenticStorage, THE Facet SHALL resolve the storage pointer using the canonical namespace hash

### Requirement 2: Create Proposal

**User Story:** As a borrower agent, I want to submit a SoloCompute financing proposal, so that I can request compute credit from a lender.

#### Acceptance Criteria

1. WHEN a Borrower submits a SoloCompute proposal with valid parameters (`agentId`, `lenderPositionId`, `settlementAsset`, `requestedAmount`, `requestedUnits`, `expiresAt`, `counterparty`, `termsHash`), THE AgenticProposalFacet SHALL create a FinancingProposal with status `Pending` and assign a unique sequential `proposalId`
2. WHEN a Borrower submits a proposal, THE AgenticProposalFacet SHALL validate that `expiresAt` is greater than `block.timestamp`
3. WHEN a Borrower submits a proposal, THE AgenticProposalFacet SHALL validate that `requestedAmount` is greater than zero
4. WHEN a Borrower submits a proposal, THE AgenticProposalFacet SHALL validate that `requestedUnits` is greater than zero
5. WHEN a Borrower submits a proposal, THE AgenticProposalFacet SHALL validate that `settlementAsset` is not the zero address
6. WHEN a Borrower submits a proposal, THE AgenticProposalFacet SHALL validate that `counterparty` is not the zero address
7. WHEN a proposal is created, THE AgenticProposalFacet SHALL emit `ProposalCreated(proposalId, ProposalType.SoloCompute, agentId)`
8. WHEN a proposal is created, THE AgenticProposalFacet SHALL append the `proposalId` to the `agentToProposals[agentId]` array and the `lenderToProposals[counterparty]` array
9. WHEN a Borrower submits a proposal, THE AgenticProposalFacet SHALL keep provider selection out of canonical proposal storage; routing is handled by adapter policy layers
10. IF any validation fails, THEN THE AgenticProposalFacet SHALL revert with a descriptive error message

### Requirement 3: Cancel Proposal

**User Story:** As a borrower agent, I want to cancel my pending proposal, so that I can withdraw a request I no longer need.

#### Acceptance Criteria

1. WHEN the original Borrower cancels a proposal with status `Pending`, THE AgenticProposalFacet SHALL transition the proposal status to `Cancelled`
2. IF a non-creator address attempts to cancel a proposal, THEN THE AgenticProposalFacet SHALL revert
3. IF a proposal has status other than `Pending`, THEN THE AgenticProposalFacet SHALL revert when cancellation is attempted

### Requirement 4: Approve Proposal

**User Story:** As a lender, I want to approve a borrower's proposal, so that the financing arrangement can proceed to activation.

#### Acceptance Criteria

1. WHEN the designated Lender approves a proposal with status `Pending` before `expiresAt`, THE AgenticApprovalFacet SHALL transition the proposal status to `Approved`
2. WHEN a proposal is approved, THE AgenticApprovalFacet SHALL emit `ProposalApproved(proposalId, approver)`
3. IF a non-counterparty address attempts to approve a proposal, THEN THE AgenticApprovalFacet SHALL revert
4. IF the proposal status is not `Pending`, THEN THE AgenticApprovalFacet SHALL revert
5. IF `block.timestamp` is greater than or equal to `expiresAt`, THEN THE AgenticApprovalFacet SHALL revert

### Requirement 5: Reject Proposal

**User Story:** As a lender, I want to reject a borrower's proposal, so that I can decline financing requests.

#### Acceptance Criteria

1. WHEN the designated Lender rejects a proposal with status `Pending`, THE AgenticApprovalFacet SHALL transition the proposal status to `Rejected`
2. WHEN a proposal is rejected, THE AgenticApprovalFacet SHALL emit `ProposalRejected(proposalId, rejector)`
3. IF a non-counterparty address attempts to reject a proposal, THEN THE AgenticApprovalFacet SHALL revert

### Requirement 6: Activate Agreement

**User Story:** As a borrower agent, I want to activate an approved proposal into a live agreement, so that I can begin drawing compute resources.

#### Acceptance Criteria

1. WHEN a Borrower activates a proposal with status `Approved`, THE AgenticAgreementFacet SHALL create a FinancingAgreement with status `Active`, mode `MeteredUsage`, and assign a unique sequential `agreementId`
2. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL set `borrower = proposal.creator` for Phase 1
3. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL set `creditLimit` from `proposal.requestedAmount` and `unitLimit` from `proposal.requestedUnits`
4. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL derive `lenderPositionKey` via `LibPositionNFT.getPositionKey(positionNFTContract, lenderPositionId)` where `positionNFTContract` is loaded from `LibPositionNFT` storage
5. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL encumber the lender position on native rails by increasing `LibEncumbrance.position(lenderPositionKey, lenderPoolId).directLent` by the full `creditLimit`; module/index encumbrance wrappers SHALL NOT be used for Agentic financing
6. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL transition the proposal status to `Activated`
7. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL emit `AgreementActivated(agreementId, proposalId, AgreementMode.MeteredUsage)`
8. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL emit `NativeEncumbranceUpdated` with the lender position key, encumbered principal equal to `creditLimit`, and reason `keccak256("ACTIVATION")`
9. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL append the `agreementId` to `agentToAgreements[agentId]` and `lenderToAgreements[lender]`
10. IF the proposal status is not `Approved`, THEN THE AgenticAgreementFacet SHALL revert

### Requirement 7: Register Encryption Public Key

**User Story:** As a borrower agent, I want to register my secp256k1 encryption public key on-chain, so that the relayer can encrypt provider credentials for me.

#### Acceptance Criteria

1. WHEN a Borrower registers a compressed secp256k1 public key (33 bytes starting with `0x02` or `0x03`), THE AgentEncPubRegistryFacet SHALL store the key mapped to `msg.sender`
2. WHEN a public key is registered, THE AgentEncPubRegistryFacet SHALL emit `AgentEncPubRegistered(msg.sender, pubkey)`
3. WHEN a Borrower registers a new key, THE AgentEncPubRegistryFacet SHALL overwrite any previously registered key for that address
4. IF the provided key length is not 33 bytes, THEN THE AgentEncPubRegistryFacet SHALL revert
5. IF the first byte is not `0x02` or `0x03`, THEN THE AgentEncPubRegistryFacet SHALL revert
6. THE AgentEncPubRegistryFacet SHALL provide a view function to read the registered public key for any address

### Requirement 8: Publish Borrower Payload

**User Story:** As a borrower agent, I want to publish an encrypted payload for my active agreement, so that the relayer can read my provisioning request.

#### Acceptance Criteria

1. WHEN the Borrower of an active agreement publishes an Envelope as bytes, THE AgenticMailboxFacet SHALL store the payload mapped to the `agreementId`
2. WHEN a borrower payload is published, THE AgenticMailboxFacet SHALL emit `BorrowerPayloadPublished(agreementId, msg.sender, envelope)`
3. IF the caller is not the Borrower of the agreement, THEN THE AgenticMailboxFacet SHALL revert
4. IF the agreement status is not `Active`, THEN THE AgenticMailboxFacet SHALL revert
5. IF the envelope bytes are empty, THEN THE AgenticMailboxFacet SHALL revert
6. WHEN borrower payload is published multiple times for the same `agreementId`, THE AgenticMailboxFacet SHALL overwrite prior payload bytes and the latest payload SHALL be authoritative

### Requirement 9: Publish Provider Payload

**User Story:** As the relayer, I want to publish encrypted provider credentials for an active agreement, so that the borrower can access compute resources.

#### Acceptance Criteria

1. WHEN an address with Relayer_Role publishes an Envelope as bytes for an active agreement, THE AgenticMailboxFacet SHALL store the payload mapped to the `agreementId`
2. WHEN a provider payload is published, THE AgenticMailboxFacet SHALL emit `ProviderPayloadPublished(agreementId, msg.sender, envelope)`
3. IF the caller does not have Relayer_Role, THEN THE AgenticMailboxFacet SHALL revert
4. IF the agreement status is not `Active`, THEN THE AgenticMailboxFacet SHALL revert
5. IF the envelope bytes are empty, THEN THE AgenticMailboxFacet SHALL revert
6. WHEN provider payload is published multiple times for the same `agreementId`, THE AgenticMailboxFacet SHALL overwrite prior payload bytes and the latest payload SHALL be authoritative

### Requirement 10: Read Mailbox Payloads

**User Story:** As any participant, I want to read the encrypted payloads for an agreement, so that I can decrypt and consume the credential data.

#### Acceptance Criteria

1. THE AgenticMailboxFacet SHALL provide a view function that returns the borrower payload bytes for a given `agreementId`
2. THE AgenticMailboxFacet SHALL provide a view function that returns the provider payload bytes for a given `agreementId`
3. WHEN no payload has been published for an agreement, THE AgenticMailboxFacet SHALL return empty bytes

### Requirement 11: Configure Compute Unit Pricing

**User Story:** As a protocol administrator, I want to configure unit type pricing, so that off-chain usage can be converted to on-chain monetary debt.

#### Acceptance Criteria

1. WHEN an authorized administrator sets a Compute_Unit_Config with `settlementAsset`, `unitType`, `unitPrice`, and `active` flag, THE ComputeUsageFacet SHALL store the configuration keyed by `(settlementAsset, unitType)`
2. THE ComputeUsageFacet SHALL validate that `unitPrice` is greater than zero for active unit types
3. THE ComputeUsageFacet SHALL provide a view function to read the Compute_Unit_Config for any `(settlementAsset, unitType)` pair
4. WHEN an administrator deactivates a unit type by setting `active` to false, THE ComputeUsageFacet SHALL prevent new usage registration against that `(settlementAsset, unitType)` pair

### Requirement 12: Register Usage

**User Story:** As the relayer, I want to submit metered usage for an active agreement, so that off-chain compute consumption is converted to on-chain debt.

#### Acceptance Criteria

1. WHEN an address with Relayer_Role submits usage with `agreementId`, `unitType`, and `amount` (uint256 representing scaled units), THE ComputeUsageFacet SHALL load `unitPrice` from the agreement's `settlementAsset` and compute `debtDelta = amount * unitPrice / UNIT_SCALE`, then add `debtDelta` to `agreement.principalDrawn`
2. WHEN usage is registered, THE ComputeUsageFacet SHALL add `amount` to `agreementUnitUsage[agreementId][unitType]` and to `agreementTotalUnitsUsed[agreementId]`
3. WHEN usage is registered, THE ComputeUsageFacet SHALL validate that `agreement.principalDrawn + debtDelta` does not exceed `agreement.creditLimit`
4. WHEN usage is registered, THE ComputeUsageFacet SHALL validate that total units used does not exceed `agreement.unitLimit`
5. WHEN usage is registered, THE ComputeUsageFacet SHALL emit `DrawExecuted(agreementId, debtDelta, amount, address(0))` where `recipient` is `address(0)` to indicate compute draw rather than monetary transfer
6. WHEN usage is registered, THE ComputeUsageFacet SHALL update native encumbrance via `NativeEncumbranceUpdated` with reason `keccak256("USAGE")`
7. IF the caller does not have Relayer_Role, THEN THE ComputeUsageFacet SHALL revert
8. IF the agreement status is not `Active`, THEN THE ComputeUsageFacet SHALL revert
9. IF the `(settlementAsset, unitType)` config is not active in Compute_Unit_Config, THEN THE ComputeUsageFacet SHALL revert
10. IF `amount` is zero, THEN THE ComputeUsageFacet SHALL revert

### Requirement 13: Batch Register Usage

**User Story:** As the relayer, I want to submit multiple usage entries in a single transaction, so that gas costs are reduced for periodic metering.

#### Acceptance Criteria

1. WHEN an address with Relayer_Role submits a batch of usage entries (array of `agreementId`, `unitType`, `amount` tuples), THE ComputeUsageFacet SHALL process each entry sequentially applying the same validation and accounting as single usage registration
2. IF any entry in the batch fails validation, THEN THE ComputeUsageFacet SHALL revert the entire batch

### Requirement 14: Apply Repayment

**User Story:** As a borrower agent, I want to repay my debt in the settlement asset, so that my outstanding balance decreases and lender encumbrance is released.

#### Acceptance Criteria

1. WHEN a Borrower submits a repayment of `amount` in Settlement_Asset for an active agreement, THE AgenticAgreementFacet SHALL apply the Waterfall: allocate to `feesAccrued` first, then `interestAccrued`, then `principalDrawn`
2. WHEN a repayment is applied, THE AgenticAgreementFacet SHALL compute `revenueBase = toFees + toInterest`, `lenderShare = revenueBase * 7000 / 10000`, and `protocolShare = revenueBase - lenderShare`
3. WHEN a repayment is applied, THE AgenticAgreementFacet SHALL route `protocolShare` through LibFeeRouter and route `lenderShare` through the lender fee index for pro-rata lender distribution by deposit size
4. WHEN a repayment is applied, THE AgenticAgreementFacet SHALL transfer `amount` of Settlement_Asset from the Borrower to the contract using `transferFrom`
5. WHEN principal is repaid, THE AgenticAgreementFacet SHALL increase `principalRepaid` by the principal portion and proportionally release native encumbrance by decreasing the same lender `directLent` reservation
6. WHEN a repayment is applied, THE AgenticAgreementFacet SHALL emit `RepaymentApplied(agreementId, amount, toFees, toInterest, toPrincipal)`
7. WHEN a repayment is applied, THE AgenticAgreementFacet SHALL emit `NativeEncumbranceUpdated` with updated encumbered amounts and reason `keccak256("REPAYMENT")`
8. IF `amount` is zero, THEN THE AgenticAgreementFacet SHALL revert
9. IF the agreement status is not `Active`, THEN THE AgenticAgreementFacet SHALL revert
10. IF the Borrower has insufficient Settlement_Asset allowance or balance, THEN THE AgenticAgreementFacet SHALL revert
11. IF `amount` exceeds total outstanding debt (`feesAccrued + interestAccrued + (principalDrawn - principalRepaid)`), THEN THE AgenticAgreementFacet SHALL revert

### Requirement 15: Close Agreement

**User Story:** As a borrower agent, I want to close my agreement when all debt is repaid, so that the financing arrangement is formally concluded.

#### Acceptance Criteria

1. WHEN a Borrower requests closure of an agreement where `principalDrawn` equals `principalRepaid` and `feesAccrued` and `interestAccrued` are zero, THE AgenticAgreementFacet SHALL transition the agreement status to `Closed`
2. WHEN an agreement is closed, THE AgenticAgreementFacet SHALL release all remaining native encumbrance by reducing the agreement's remaining lender `directLent` reservation to zero
3. WHEN an agreement is closed, THE AgenticAgreementFacet SHALL emit `AgreementClosed(agreementId)`
4. IF outstanding debt remains (`principalDrawn > principalRepaid` or fees/interest are non-zero), THEN THE AgenticAgreementFacet SHALL revert

### Requirement 16: Relayer Authorization

**User Story:** As a protocol administrator, I want to whitelist the relayer address for usage submission and provider payload publication, so that only the trusted orchestration node can submit metering data and credentials.

#### Acceptance Criteria

1. THE AgenticAgreementFacet SHALL maintain a role-based access control mapping for Relayer_Role
2. WHEN an authorized administrator grants Relayer_Role to an address, THE AgenticAgreementFacet SHALL allow that address to call `registerUsage`, `batchRegisterUsage`, and `publishProviderPayload`
3. WHEN an authorized administrator revokes Relayer_Role from an address, THE AgenticAgreementFacet SHALL prevent that address from calling relayer-restricted functions
4. THE AgenticAgreementFacet SHALL support multiple addresses holding Relayer_Role simultaneously

### Requirement 17: Query Agreement State

**User Story:** As any participant, I want to read agreement details and balances, so that I can monitor the financing arrangement.

#### Acceptance Criteria

1. THE AgenticAgreementFacet SHALL provide a view function returning the full FinancingAgreement struct for a given `agreementId`
2. THE AgenticAgreementFacet SHALL provide a view function returning all `agreementId` values for a given `agentId`
3. THE AgenticAgreementFacet SHALL provide a view function returning all `proposalId` values for a given `agentId`
4. THE AgenticAgreementFacet SHALL provide a view function returning the encumbered principal and units for a given `agreementId`

### Requirement 18: Query Proposal State

**User Story:** As any participant, I want to read proposal details, so that I can review pending and historical financing requests.

#### Acceptance Criteria

1. THE AgenticProposalFacet SHALL provide a view function returning the full FinancingProposal struct for a given `proposalId`
2. THE AgenticProposalFacet SHALL provide a view function returning all `proposalId` values for a given lender address

### Requirement 19: Event Schema Compatibility

**User Story:** As the relayer operator, I want on-chain events to match the expected schema, so that the ingestion engine can parse and process them without modification.

#### Acceptance Criteria

1. THE Diamond SHALL emit `AgreementActivated(uint256 indexed agreementId, uint256 indexed proposalId, AgreementMode mode)` with the canonical v1.11 signature expected by the relayer ingestion engine
2. THE Diamond SHALL emit `BorrowerPayloadPublished(uint256 indexed agreementId, address indexed borrower, bytes envelope)` with envelope bytes decodable as UTF-8 string matching the `@equalfi/mailbox-sdk` Envelope format
3. THE Diamond SHALL emit `ProviderPayloadPublished(uint256 indexed agreementId, address indexed provider, bytes envelope)` with the same envelope encoding
4. THE Diamond SHALL emit `DrawExecuted(uint256 indexed agreementId, uint256 amount, uint256 units, address recipient)` for each usage registration
5. THE Diamond SHALL emit `RepaymentApplied(uint256 indexed agreementId, uint256 amount, uint256 toFees, uint256 toInterest, uint256 toPrincipal)` for each repayment
6. THE Diamond SHALL emit `NativeEncumbranceUpdated(uint256 indexed agreementId, bytes32 indexed positionKey, uint256 principalEncumbered, uint256 unitsEncumbered, bytes32 reason)` for each encumbrance mutation
7. THE Diamond SHALL emit `ProposalCreated(uint256 indexed proposalId, ProposalType proposalType, uint256 indexed agentId)` for each new proposal
8. THE Diamond SHALL emit `ProposalApproved(uint256 indexed proposalId, address indexed approver)` for each approval
9. THE Diamond SHALL emit `AgreementClosed(uint256 indexed agreementId)` when an agreement transitions to `Closed`

### Requirement 20: Reentrancy Protection

**User Story:** As a protocol security auditor, I want all state-changing functions to be protected against reentrancy, so that the contract cannot be exploited through callback attacks.

#### Acceptance Criteria

1. THE AgenticAgreementFacet SHALL follow the checks-effects-interactions (CEI) pattern for all functions that transfer Settlement_Asset
2. THE AgenticAgreementFacet SHALL use a reentrancy guard on `applyRepayment` and `activateAgreement`
3. THE ComputeUsageFacet SHALL follow the CEI pattern for `registerUsage` and `batchRegisterUsage`

### Requirement 21: Input Validation

**User Story:** As a protocol security auditor, I want all external inputs to be validated, so that invalid data cannot corrupt contract state.

#### Acceptance Criteria

1. WHEN any function receives an address parameter, THE Facet SHALL validate the address is not the zero address where a zero address is semantically invalid
2. WHEN any function receives a uint256 amount parameter representing a transfer or usage quantity, THE Facet SHALL validate the amount is greater than zero
3. WHEN any function receives a `proposalId` or `agreementId`, THE Facet SHALL validate the ID references an existing record
4. WHEN any function receives a timestamp parameter, THE Facet SHALL validate the timestamp is in the expected range relative to `block.timestamp`

### Requirement 22: Repayment Accounting Invariant

**User Story:** As a protocol auditor, I want repayment accounting to be provably correct, so that funds are never lost or double-counted.

#### Acceptance Criteria

1. FOR ALL repayments, THE AgenticAgreementFacet SHALL ensure `toFees + toInterest + toPrincipal` equals the submitted `amount`
2. FOR ALL agreements, THE AgenticAgreementFacet SHALL ensure `principalRepaid` never exceeds `principalDrawn`
3. FOR ALL repayments, THE AgenticAgreementFacet SHALL ensure `lenderShare + protocolShare` equals `revenueBase` (no rounding loss beyond 1 wei)
4. FOR ALL agreements, THE AgenticAgreementFacet SHALL ensure `principalDrawn` never exceeds `creditLimit`
5. FOR ALL repayments, THE AgenticAgreementFacet SHALL ensure `amount <= totalOutstandingDebt`

### Requirement 23: Encumbrance Conservation Invariant

**User Story:** As a protocol auditor, I want encumbrance to be conserved across all state transitions, so that lender capital is always properly tracked.

#### Acceptance Criteria

1. WHEN an agreement is activated, THE AgenticAgreementFacet SHALL set `principalEncumbered` equal to `creditLimit`
2. WHEN a repayment reduces principal, THE AgenticAgreementFacet SHALL reduce `principalEncumbered` by the same principal portion
3. WHEN an agreement is closed, THE AgenticAgreementFacet SHALL set `principalEncumbered` to zero
4. FOR ALL active agreements, THE AgenticAgreementFacet SHALL ensure `principalEncumbered` equals `creditLimit - principalRepaid`
5. FOR ALL agentic agreements, native reservation mutations SHALL occur on `LibEncumbrance.position(positionKey, poolId).directLent`; `LibModuleEncumbrance` and `LibIndexEncumbrance` SHALL NOT be used

### Requirement 24: Mailbox Envelope Round-Trip Compatibility

**User Story:** As a protocol integrator, I want the on-chain mailbox to preserve envelope bytes exactly, so that the mailbox-sdk can encrypt and decrypt payloads through the contract without data corruption.

#### Acceptance Criteria

1. FOR ALL valid Envelope bytes published via `publishBorrowerPayload`, THE AgenticMailboxFacet SHALL return identical bytes when read via the corresponding view function (round-trip property)
2. FOR ALL valid Envelope bytes published via `publishProviderPayload`, THE AgenticMailboxFacet SHALL return identical bytes when read via the corresponding view function (round-trip property)
3. THE AgenticMailboxFacet SHALL store envelope bytes without modification, truncation, or padding
4. FOR repeated publishes on the same `agreementId`, THE most recent payload SHALL overwrite prior payload and SHALL be the authoritative payload
