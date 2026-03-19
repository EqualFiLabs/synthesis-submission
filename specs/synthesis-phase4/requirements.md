# Requirements Document

## Introduction

Phase 4 of the Equalis Agentic Financing protocol implements the advanced on-chain features that complete the canonical specification. Building on Phase 1's core proposal/agreement/accounting facets, Phase 2's event infrastructure, and Phase 3's compute provider adapters, Phase 4 adds seven new subsystems:

1. **ERC-8004 Integration** — Identity resolution, reputation feedback, and validation gating via the ERC-8004 standard
2. **ERC-8183 Integration** — ACP job lifecycle management with venue-agnostic adapter routing
3. **Adapter Registry** — venueKey → adapter routing for hot-swappable ACP execution venues
4. **Collateral Management** — Optional collateral deposits, releases, and seizure with toggle semantics
5. **Net Draw Coverage Covenants** — Periodic payment-vs-net-draw enforcement with breach detection, draw freeze, cure, and termination
6. **Pooled Financing and Governance** — Multi-lender capital pooling with on-chain governance voting
7. **Interest Accrual and Fee Schedules** — Linear interest computation and fee waterfall management

Phase 4 depends on Phase 1 Diamond facets and storage layout (already deployed). All new facets are additive — no breaking modifications to existing Phase 1 storage layout/behavior, Phase 2 event infrastructure, or Phase 3 compute adapters. Additive storage fields and mappings required for Phase 4 are in scope.

### Cross-Chain Note (Hackathon Context)

ERC-8004 resolution performed by on-chain facets can only read contracts on the same chain as the Diamond. If the ERC-8004 registry of record lives on a different chain (e.g. registry on Base, Diamond on Arbitrum), then **on-chain ERC-8004 gating is not possible without an oracle/bridge design**.

For Phase 4 deployments:
- Same-chain mode (Diamond + ERC-8004 registry/adapters on same chain): on-chain ERC-8004 gating applies.
- Cross-chain hackathon mode: ERC-8004 gating SHOULD be handled via the **Phase 2 offchain resolver** (verification at relayer level) until a dedicated on-chain oracle/bridge/resolver is introduced.

### Explicitly Out of Scope

- Breaking modifications to Phase 1 Diamond facet behavior or existing storage layout (already deployed)
- Modifications to Phase 2 EventListener or TransactionSubmitter
- Modifications to Phase 3 compute provider adapters (Lambda, RunPod, Venice, Bankr)
- Delinquency/default/write-off status transitions (owned by Phase 5 AgenticRiskFacet)
- Frontend or UI components
- Production mainnet deployment or HSM/KMS key management
- Token economics beyond the fee/interest model defined in canonical spec
- Module mirror bridge from native encumbrance state (optional, non-canonical)

## Glossary

- **ERC-8004**: An identity standard providing agent wallet resolution, reputation feedback, and validation gating via registry contracts
- **ERC-8183**: An agentic commerce protocol standard defining job lifecycle (create, fund, submit, complete, reject, claimRefund) for execution venues
- **ACP**: Agentic Commerce Protocol — the job lifecycle defined by ERC-8183
- **ACP_Job**: A unit of work linked to a financing agreement, routed through an ERC-8183 adapter, with states: Open, Funded, Submitted, Completed, Rejected, Expired
- **Venue_Key**: A `bytes32` identifier (e.g., `keccak256("ERC8183_REFERENCE")`) used to select an ACP adapter from the registry
- **IACP8183Adapter**: The canonical Solidity interface that all ACP venue adapters implement: createJob, setProviderJob, setBudgetJob, fundJob, submitJob, completeJob, rejectJob, claimRefund
- **Reference8183Adapter**: A concrete IACP8183Adapter implementation routing jobs through a neutral ERC-8183 reference venue implementation (local reference venue may be used for test/dev)
- **MockGeneric8183Adapter**: A test/reference IACP8183Adapter implementation used for portability verification and differential testing
- **Adapter_Registry**: The on-chain registry mapping venueKey → adapter address with enable/disable controls
- **Trust_Mode**: One of four identity trust levels per agreement: DiscoveryOnly, ReputationOnly, ValidationRequired, Hybrid
- **Collateral**: Optional first-loss capital posted by a borrower against an agreement, tracked separately from encumbrance
- **Collateral_Toggle**: The `collateralEnabled` boolean on an agreement that determines whether collateral rules apply
- **Net_Draw**: `max(0, grossDraw_p - refunds_p)` for covenant period `p`
- **Required_Payment**: `feesDue_p + interestDue_p + (netDraw_p * minNetDrawCoverageBps / 10000) + principalFloorPerPeriod`
- **Cure_Period**: The time window (default: 7 days) after a covenant breach during which the borrower can cure before termination
- **Draw_Freeze**: A state where new draws are blocked due to covenant breach or collateral shortfall
- **Draw_Termination**: Permanent revocation of draw rights after an unresolved breach past the cure period
- **Pool_Share**: A record of a lender's contribution to a pooled financing agreement, used for pro-rata distribution
- **Quorum_Bps**: The minimum percentage of pool shares that must vote for a governance proposal to be valid (default: 2000 = 20%)
- **Pass_Threshold_Bps**: The minimum percentage of votes in favor for a governance proposal to pass (default: 5500 = 55%)
- **Interest_Accrual**: The computation of interest owed on an agreement's outstanding principal over time
- **Fee_Schedule**: The set of fees applicable to an agreement: origination fee, service fee, late fee
- **Repayment_Waterfall**: The order in which repayments are applied: fees first, then interest, then principal
- **Governance_Role**: An access-control role for addresses authorized to execute governance actions on pooled agreements
- **Admin_Role**: An access-control role for protocol administrators who can configure global settings

## Requirements

### Requirement 1: ERC-8004 Registry Configuration

**User Story:** As a protocol administrator, I want to configure the ERC-8004 identity registry address, so that the protocol can resolve agent identities and interact with reputation and validation services.

#### Acceptance Criteria

1. WHEN an Admin_Role address calls `setERC8004Registry(address)`, THE ERC8004Facet SHALL store the registry address in AgenticStorage
2. IF the caller does not have Admin_Role, THEN THE ERC8004Facet SHALL revert
3. IF the registry address is the zero address, THEN THE ERC8004Facet SHALL revert
4. THE ERC8004Facet SHALL provide a view function returning the current ERC-8004 registry address

### Requirement 2: ERC-8004 Identity Resolution

**User Story:** As a protocol participant, I want to validate an agent's identity through ERC-8004, so that only agents with resolvable on-chain identities can participate in financing.

#### Acceptance Criteria

1. WHEN `validateIdentity(agentRegistry, agentId)` is called, THE ERC8004Facet SHALL query the configured IERC8004IdentityAdapter to resolve the agent wallet for that `(agentRegistry, agentId)` tuple
2. WHEN the IERC8004IdentityAdapter returns a non-zero wallet address for `(agentRegistry, agentId)`, THE ERC8004Facet SHALL return `valid = true`
3. WHEN the IERC8004IdentityAdapter returns a zero address for `resolveAgentWallet`, THE ERC8004Facet SHALL fall back to `resolveOwner` and return `valid = true` if the owner address is non-zero
4. IF both `resolveAgentWallet` and `resolveOwner` return the zero address, THEN THE ERC8004Facet SHALL return `valid = false`
5. THE ERC8004Facet SHALL provide a `requireIdentity(agentRegistry, agentId)` function that reverts with `IdentityNotResolved` if `validateIdentity` returns false

### Requirement 3: ERC-8004 Trust Mode Gating

**User Story:** As a lender, I want to configure trust requirements on agreements, so that proposal creation and agreement activation are gated by identity, reputation, or validation checks.

#### Acceptance Criteria

1. WHEN an agreement has `trustMode = DiscoveryOnly`, THE ERC8004Facet SHALL allow proposal creation and activation without reputation or validation checks
2. WHEN an agreement has `trustMode = ReputationOnly`, THE ERC8004Facet SHALL require that the borrower's reputation summary value from IERC8004ReputationAdapter meets or exceeds `minReputationValue` before activation
3. WHEN an agreement has `trustMode = ValidationRequired`, THE ERC8004Facet SHALL require that the borrower has a validation response from IERC8004ValidationAdapter with `response >= minValidationResponse` (default: 80) before activation
4. WHEN an agreement has `trustMode = Hybrid`, THE ERC8004Facet SHALL require both the reputation threshold and the validation response threshold to be satisfied before activation
5. IF the trust mode requirements are not met, THEN THE ERC8004Facet SHALL revert with a descriptive error indicating which trust check failed
6. THE ERC8004Facet SHALL emit `TrustProfileSet(agreementId, trustMode, minReputationValue, minReputationValueDecimals, requiredValidator, minValidationResponse)` when trust parameters are configured

### Requirement 4: ERC-8004 Reputation Feedback

**User Story:** As a protocol participant, I want to submit reputation feedback after agreement completion, so that agent behavior is recorded on-chain for future trust decisions.

#### Acceptance Criteria

1. WHEN a lender or Governance_Role address calls `submitReputationFeedback(agreementId, counterparty, score, comment)` for a Closed or Defaulted agreement, THE ERC8004Facet SHALL call `giveFeedback` on the configured IERC8004ReputationAdapter with the agreement's `agentRegistry`, `agentId`, and the provided score
2. THE ERC8004Facet SHALL use `tag1`/`tag2` taxonomy derived from the agreement outcome: `"repayment_quality"` for healthy closures, `"delinquency"` for delinquent agreements, `"default"` for defaulted agreements
3. WHEN feedback is submitted, THE ERC8004Facet SHALL emit `ReputationFeedbackPosted(agreementId, agentRegistry, agentId, value, valueDecimals, tag1, tag2)`
4. IF the agreement status is not Closed or Defaulted, THEN THE ERC8004Facet SHALL revert
5. IF the caller is not the lender of the agreement or a Governance_Role address, THEN THE ERC8004Facet SHALL revert

### Requirement 5: ERC-8004 Validation Request and Recording

**User Story:** As a protocol participant, I want to request and record ERC-8004 validation for high-trust agreements, so that external validators can gate agreement transitions.

#### Acceptance Criteria

1. WHEN a validation request is needed for a ValidationRequired or Hybrid agreement, THE ERC8004Facet SHALL call `validationRequest` on the configured IERC8004ValidationAdapter with the agreement's `agentRegistry`, `requiredValidator`, `agentId`, and a request URI
2. WHEN a validation request is submitted, THE ERC8004Facet SHALL emit `ValidationRequested(agreementId, requestHash, validator)`
3. WHEN the ERC8004Facet checks validation status via `getValidationStatus`, THE ERC8004Facet SHALL record the response in `agreementLastValidationResponse` and `agreementLastValidationAt`
4. WHEN a validation response is recorded, THE ERC8004Facet SHALL emit `ValidationRecorded(agreementId, requestHash, response, tag)`
5. IF the validation response is below `minValidationResponse`, THEN THE ERC8004Facet SHALL prevent the gated transition and revert with `ValidationBelowThreshold`

### Requirement 6: ACP Adapter Registry — Venue Registration

**User Story:** As a protocol administrator, I want to register ACP venue adapters by venueKey, so that the protocol can route ACP jobs to different execution venues without hardcoding adapter addresses.

#### Acceptance Criteria

1. WHEN an Admin_Role address calls `registerVenueAdapter(venueKey, adapter)`, THE AdapterRegistryFacet SHALL store the adapter address mapped to the venueKey and mark it as enabled
2. WHEN a venue adapter is registered, THE AdapterRegistryFacet SHALL emit `ACPVenueAdapterSet(venueKey, adapter, true)`
3. IF the caller does not have Admin_Role, THEN THE AdapterRegistryFacet SHALL revert
4. IF the adapter address is the zero address, THEN THE AdapterRegistryFacet SHALL revert
5. THE AdapterRegistryFacet SHALL allow updating an existing venueKey to point to a new adapter address
6. THE AdapterRegistryFacet SHALL provide a view function `getVenueAdapter(venueKey)` returning the adapter address and enabled status

### Requirement 7: ACP Adapter Registry — Venue Enable/Disable

**User Story:** As a protocol administrator, I want to enable or disable venue adapters without unregistering them, so that I can perform operational circuit-breaking on specific venues.

#### Acceptance Criteria

1. WHEN an Admin_Role address calls `setVenueEnabled(venueKey, enabled)`, THE AdapterRegistryFacet SHALL update the enabled status for the venueKey
2. WHEN a venue is disabled, THE AdapterRegistryFacet SHALL emit `ACPVenueAdapterSet(venueKey, adapter, false)`
3. IF a disabled venueKey is used to create an ACP job, THEN THE ERC8183Facet SHALL revert with `VenueDisabled`
4. THE AdapterRegistryFacet SHALL allow re-enabling a previously disabled venue without re-registration

### Requirement 8: ACP Adapter Registry — Agreement Venue Assignment

**User Story:** As a protocol participant, I want to assign a specific ACP venue to an agreement, so that the agreement's ACP jobs are routed through the selected adapter.

#### Acceptance Criteria

1. WHEN `setAgreementVenue(agreementId, venueKey)` is called by the lender or Admin_Role before agreement activation, THE AdapterRegistryFacet SHALL store the venueKey for the agreement
2. WHEN an agreement venue is assigned, THE AdapterRegistryFacet SHALL emit `ACPAgreementVenueSet(agreementId, venueKey, adapter)`
3. THE AdapterRegistryFacet SHALL provide a view function `getAgreementVenue(agreementId)` returning the venueKey and resolved adapter address
4. IF the venueKey is not registered, THEN THE AdapterRegistryFacet SHALL revert with `VenueNotRegistered`
5. IF the venueKey is registered but disabled, THEN THE AdapterRegistryFacet SHALL revert with `VenueDisabled`

### Requirement 9: ERC-8183 ACP Job Creation

**User Story:** As a borrower agent, I want to create ACP jobs linked to my financing agreement, so that execution tasks are tracked and funded through the protocol.

#### Acceptance Criteria

1. WHEN `createAcpJob(agreementId, venueKey, provider, evaluator, expiredAt, description, hook)` is called by the borrower of an active agreement, THE ERC8183Facet SHALL resolve the adapter from the AdapterRegistryFacet using the venueKey and call `createJob` on the adapter
2. WHEN an ACP job is created, THE ERC8183Facet SHALL store the job linkage in `agreementToAcpJobs[agreementId]` and `acpJobToAgreement[acpJobId]`
3. WHEN an ACP job is created, THE ERC8183Facet SHALL emit `ACPJobLinked(agreementId, acpJobId, adapter)`
4. THE ERC8183Facet SHALL assign the job status `Open` and record `createdAt` timestamp
5. IF the agreement does not have `acpEnabled = true`, THEN THE ERC8183Facet SHALL revert with `ACPNotEnabled`
6. IF the agreement has `drawFrozen = true`, THEN THE ERC8183Facet SHALL revert with `DrawFrozen`
7. IF the caller is not the borrower of the agreement, THEN THE ERC8183Facet SHALL revert

### Requirement 10: ERC-8183 ACP Job Configuration

**User Story:** As ACP participants, we want to configure provider and budget while the job is still open, so that funding and execution follow the ERC-8183 reference lifecycle.

#### Acceptance Criteria

1. WHEN `setAcpProvider(jobId, provider)` is called by the borrower (ACP client) while the job status is `Open` and provider is currently unset, THE ERC8183Facet SHALL call `setProviderJob` on the adapter and persist the provider
2. WHEN `setAcpBudget(jobId, budget, optParams)` is called by the designated provider while the job status is `Open`, THE ERC8183Facet SHALL call `setBudgetJob` on the adapter and persist the configured budget
3. IF `setAcpProvider` or `setAcpBudget` is called when job status is not `Open`, THEN THE ERC8183Facet SHALL revert with `InvalidJobTransition`
4. IF the caller is not authorized for the corresponding action (borrower for provider set, provider for budget set), THEN THE ERC8183Facet SHALL revert
5. IF `setAcpProvider` is called after provider is already set, THEN THE ERC8183Facet SHALL revert

### Requirement 11: ERC-8183 ACP Job Submission

**User Story:** As a service provider, I want to submit the result of an ACP job, so that the evaluator can review and complete or reject the work.

#### Acceptance Criteria

1. WHEN `submitAcpJob(jobId, deliverable, optParams)` is called by the provider, THE ERC8183Facet SHALL call `submitJob` on the adapter and transition the job status to `Submitted`
2. WHEN a job is submitted from a `Funded` state, THE ERC8183Facet SHALL record `submittedAt` and emit `ACPJobSubmitted(agreementId, acpJobId, deliverable)`
3. WHEN a job has `budget == 0`, THE ERC8183Facet SHALL also allow submit transition directly from `Open` to `Submitted` per ERC-8183 reference semantics
4. IF the job status is neither `Funded` nor `Open` with zero budget, THEN THE ERC8183Facet SHALL revert with `InvalidJobTransition`
5. IF the caller is not the designated provider, THEN THE ERC8183Facet SHALL revert

### Requirement 12: ERC-8183 ACP Job Completion

**User Story:** As an evaluator, I want to complete an ACP job after reviewing the deliverable, so that the financed amount remains as utilized debt under the agreement repayment schedule.

#### Acceptance Criteria

1. WHEN `completeAcpJob(jobId, reason, optParams)` is called by the evaluator, THE ERC8183Facet SHALL call `completeJob` on the adapter and transition the job status from `Submitted` to `Completed`
2. WHEN a job is completed, THE ERC8183Facet SHALL record `acpJobTerminalState[jobId] = 1` (Completed) and emit `ACPJobResolved(agreementId, acpJobId, 1, reason)`
3. WHEN a job reaches Completed terminal state, THE ERC8183Facet SHALL leave the financed amount as utilized debt — no refund is applied
4. IF the job status is not `Submitted`, THEN THE ERC8183Facet SHALL revert with `InvalidJobTransition`

### Requirement 13: ERC-8183 ACP Job Rejection

**User Story:** As an ACP participant, I want to reject an ACP job under the canonical authorization rules, so that rejected work triggers a refund that reduces outstanding principal.

#### Acceptance Criteria

1. WHEN `rejectAcpJob(jobId, reason, optParams)` is called for a job in status `Open`, THE ERC8183Facet SHALL require borrower authorization and call `rejectJob` on the adapter
2. WHEN `rejectAcpJob(jobId, reason, optParams)` is called for a job in status `Funded` or `Submitted`, THE ERC8183Facet SHALL require evaluator authorization and call `rejectJob` on the adapter
3. WHEN a job is rejected, THE ERC8183Facet SHALL record `acpJobTerminalState[jobId] = 2` (Rejected) and emit `ACPJobResolved(agreementId, acpJobId, 2, reason)`
4. WHEN a refund is applied from a rejected `Funded` or `Submitted` job, THE ERC8183Facet SHALL reduce `principalDrawn` and `principalEncumbered` proportionally (including mirror encumbrance mappings) and emit `NativeEncumbranceUpdated`
5. IF the job status is not `Open`, `Funded`, or `Submitted`, THEN THE ERC8183Facet SHALL revert with `InvalidJobTransition`

### Requirement 14: ERC-8183 ACP Job Refund (Expired)

**User Story:** As a protocol participant, I want to claim a refund for an expired ACP job, so that escrowed funds are returned and the agreement's utilization is reduced.

#### Acceptance Criteria

1. WHEN `claimAcpRefund(jobId)` is called for a job in status `Funded` or `Submitted` that has passed its `expiredAt` timestamp, THE ERC8183Facet SHALL call `claimRefund` on the adapter
2. WHEN a refund is claimed, THE ERC8183Facet SHALL record `acpJobTerminalState[jobId] = 3` (Expired) and emit `ACPJobResolved(agreementId, acpJobId, 3, reason)`
3. WHEN a refund is applied from an expired job, THE ERC8183Facet SHALL reduce `principalDrawn` and `principalEncumbered` on the linked agreement by the refunded amount and emit `NativeEncumbranceUpdated`
4. THE `claimAcpRefund` function SHALL remain callable regardless of circuit breaker pause state — refund liveness is non-pausable
5. IF the job has already reached a terminal state, THEN THE ERC8183Facet SHALL revert with `JobAlreadyTerminal`

### Requirement 15: ERC-8183 ACP Job Funding

**User Story:** As a borrower agent, I want to fund an ACP job from my agreement's credit line, so that the execution venue receives the budget for the job.

#### Acceptance Criteria

1. WHEN `fundAcpJob(jobId, optParams)` is called by the borrower for a job in status `Open`, THE ERC8183Facet SHALL call `fundJob` on the adapter
2. WHEN a job is funded, THE ERC8183Facet SHALL transition status to `Funded` and increase `principalDrawn` on the linked agreement by the configured budget amount
3. WHEN a job is funded, THE ERC8183Facet SHALL emit `ACPJobFunded(agreementId, acpJobId, budget)`
4. IF funding the job would cause `principalDrawn` to exceed `creditLimit`, THEN THE ERC8183Facet SHALL revert with `CreditLimitExceeded`
5. IF the agreement has `drawFrozen = true`, THEN THE ERC8183Facet SHALL revert with `DrawFrozen`
6. IF the provider is not set for the job, THEN THE ERC8183Facet SHALL revert with `ProviderNotSet`

### Requirement 16: ERC-8183 Terminal State Finality

**User Story:** As a protocol auditor, I want ACP job terminal states to be irreversible, so that accounting adjustments from job resolution cannot be replayed or reversed.

#### Acceptance Criteria

1. WHEN an ACP job reaches a terminal state (Completed, Rejected, or Expired), THE ERC8183Facet SHALL prevent any further state transitions on that job
2. IF any function attempts to transition a job that has a non-zero `acpJobTerminalState`, THEN THE ERC8183Facet SHALL revert with `JobAlreadyTerminal`
3. THE ERC8183Facet SHALL ensure that accounting adjustments (refund reductions to `principalDrawn` and `principalEncumbered`) are applied exactly once per terminal transition

### Requirement 17: Reference8183Adapter Implementation

**User Story:** As a protocol operator, I want a neutral ERC-8183 reference adapter, so that agreements can route execution through a standard reference venue without coupling the protocol to a specific commercial platform.

#### Acceptance Criteria

1. THE Reference8183Adapter SHALL implement the full IACP8183Adapter interface: createJob, setProviderJob, setBudgetJob, fundJob, submitJob, completeJob, rejectJob, claimRefund
2. THE Reference8183Adapter SHALL isolate venue-specific integration logic within the adapter contract — no venue-specific schemas in core storage
3. THE Reference8183Adapter SHALL use CEI pattern and reentrancy guards on all state-mutating entry points
4. THE Reference8183Adapter SHALL enforce strict authorization: only approved core facets can call mutating functions
5. THE Reference8183Adapter SHALL implement idempotent sync: repeated state-sync calls produce no additional accounting effects
6. THE Reference8183Adapter SHALL preserve ERC-8183 reference semantics for authorization and status transitions (`Open/Funded/Submitted/Completed/Rejected/Expired`)
7. THE Reference8183Adapter SHALL enforce terminal finality: once a canonical terminal state is recorded, no backward transitions are permitted
8. THE Reference8183Adapter SHALL persist canonical `reason` hash from terminal transitions for auditability

### Requirement 18: MockGeneric8183Adapter Implementation

**User Story:** As a protocol developer, I want a mock/generic ERC-8183 adapter, so that portability can be verified through differential testing against the Reference8183Adapter.

#### Acceptance Criteria

1. THE MockGeneric8183Adapter SHALL implement the full IACP8183Adapter interface with in-memory or simple storage-based job tracking
2. THE MockGeneric8183Adapter SHALL produce identical accounting outcomes as the Reference8183Adapter for the same job lifecycle sequences
3. THE MockGeneric8183Adapter SHALL support all terminal state transitions (Completed, Rejected, Expired) with the same refund semantics
4. THE MockGeneric8183Adapter SHALL be usable in integration tests as a drop-in replacement for Reference8183Adapter via the adapter registry

### Requirement 19: Collateral Posting

**User Story:** As a borrower, I want to post collateral against my financing agreement, so that I can satisfy lender collateral requirements and reduce my risk profile.

#### Acceptance Criteria

1. WHEN the borrower calls `postCollateral(agreementId, token, amount)` for an agreement with `collateralEnabled = true`, THE CollateralManagerFacet SHALL transfer `amount` of the specified ERC-20 token from the borrower to the contract and increase `collateralPosted` on the agreement
2. WHEN collateral is posted with `token = address(0)`, THE CollateralManagerFacet SHALL accept native ETH via `msg.value` and increase `collateralPosted`
3. WHEN collateral is posted, THE CollateralManagerFacet SHALL emit `CollateralPosted(agreementId, token, amount, sourcePositionKey)`
4. IF the agreement does not have `collateralEnabled = true`, THEN THE CollateralManagerFacet SHALL revert with `CollateralNotEnabled`
5. IF the caller is not the borrower of the agreement, THEN THE CollateralManagerFacet SHALL revert
6. IF `amount` is zero, THEN THE CollateralManagerFacet SHALL revert

### Requirement 20: Collateral Release

**User Story:** As a lender or governance participant, I want to release collateral back to the borrower, so that excess collateral can be returned when risk conditions allow.

#### Acceptance Criteria

1. WHEN a lender or Governance_Role address calls `releaseCollateral(agreementId, amount)`, THE CollateralManagerFacet SHALL transfer `amount` of the collateral asset back to the borrower and decrease `collateralPosted`
2. WHEN collateral is released, THE CollateralManagerFacet SHALL emit `CollateralReleased(agreementId, token, amount, targetPositionKey)`
3. IF releasing the collateral would cause the collateral ratio to fall below `maintenanceCollateralRatioBps`, THEN THE CollateralManagerFacet SHALL revert with `CollateralBelowMaintenance`
4. IF the caller is not the lender of the agreement or a Governance_Role address, THEN THE CollateralManagerFacet SHALL revert
5. IF `amount` exceeds `collateralPosted`, THEN THE CollateralManagerFacet SHALL revert

### Requirement 21: Collateral Seizure

**User Story:** As a lender or governance participant, I want to seize collateral from a defaulted agreement, so that losses can be partially recovered from the first-loss buffer.

#### Acceptance Criteria

1. WHEN a lender or Governance_Role address calls `seizeCollateral(agreementId, amount, recipient)` for an agreement with status `Defaulted` (set by Phase 5 AgenticRiskFacet), THE CollateralManagerFacet SHALL transfer `amount` of the collateral asset to the `recipient` and increase `collateralSeized`
2. WHEN collateral is seized, THE CollateralManagerFacet SHALL emit `CollateralSeized(agreementId, token, amount, reason)`
3. IF the agreement status is not `Defaulted`, THEN THE CollateralManagerFacet SHALL revert with `AgreementNotDefaulted`
4. IF the caller is not the lender or a Governance_Role address, THEN THE CollateralManagerFacet SHALL revert
5. IF `amount` exceeds `collateralPosted - collateralSeized`, THEN THE CollateralManagerFacet SHALL revert with `InsufficientCollateral`

### Requirement 22: Collateral Toggle Configuration

**User Story:** As a lender, I want to toggle collateral requirements on an agreement before activation, so that I can choose whether to require borrower collateral for risk protection.

#### Acceptance Criteria

1. WHEN the lender calls `setCollateralRequired(agreementId, required)` before agreement activation, THE CollateralManagerFacet SHALL update `collateralEnabled` on the agreement
2. WHEN collateral is enabled, THE CollateralManagerFacet SHALL emit `CollateralProfileSet(agreementId, true, collateralAsset, minCollateralRatioBps, maintenanceCollateralRatioBps)`
3. IF the agreement has already been activated, THEN THE CollateralManagerFacet SHALL revert with `AgreementAlreadyActive`
4. IF the caller is not the lender of the agreement, THEN THE CollateralManagerFacet SHALL revert
5. WHEN `collateralEnabled` is set to true, THE CollateralManagerFacet SHALL apply default `minCollateralRatioBps` of 11000 and `maintenanceCollateralRatioBps` of 10500 unless explicitly overridden

### Requirement 23: Collateral View

**User Story:** As any participant, I want to view collateral details for an agreement, so that I can monitor the collateral position.

#### Acceptance Criteria

1. THE CollateralManagerFacet SHALL provide a view function `getCollateral(agreementId)` returning: `collateralEnabled`, `collateralAsset`, `collateralPosted`, `collateralSeized`, `minCollateralRatioBps`, `maintenanceCollateralRatioBps`, and the current collateral ratio in basis points
2. WHEN `collateralEnabled` is false, THE view function SHALL return zero values for all collateral fields except `collateralEnabled`

### Requirement 24: Covenant Parameter Configuration

**User Story:** As a lender, I want to set net draw coverage covenant parameters before agreement activation, so that periodic payment requirements are enforced to protect my capital.

#### Acceptance Criteria

1. WHEN the lender calls `setCovenantParams(agreementId, minNetDrawCoverageBps, principalFloorPerPeriod, covenantCurePeriod)` before agreement activation, THE CovenantFacet SHALL store the parameters on the agreement
2. THE CovenantFacet SHALL validate that `minNetDrawCoverageBps` is at least 10000 (100% minimum coverage)
3. THE CovenantFacet SHALL validate that `covenantCurePeriod` is between 3 days and 30 days
4. IF the agreement has already been activated, THEN THE CovenantFacet SHALL revert with `AgreementAlreadyActive`
5. IF the caller is not the lender of the agreement, THEN THE CovenantFacet SHALL revert
6. WHEN covenant parameters are not explicitly set, THE CovenantFacet SHALL apply defaults: `minNetDrawCoverageBps = 10500`, non-zero governance `principalFloorPerPeriod`, `covenantCurePeriod = 7 days`

### Requirement 25: Covenant Compliance Check

**User Story:** As any participant, I want to check the current covenant compliance status of an agreement, so that I can monitor whether the borrower is meeting coverage requirements.

#### Acceptance Criteria

1. WHEN `checkCovenant(agreementId, periodId)` is called, THE CovenantFacet SHALL compute period values `grossDraw_p`, `refunds_p`, `netDraw_p = max(0, grossDraw_p - refunds_p)`, and `actualPayment_p`
2. THE CovenantFacet SHALL compute `requiredPayment_p = feesDue_p + interestDue_p + (netDraw_p * minNetDrawCoverageBps / 10000) + principalFloorPerPeriod`
3. WHEN `actualPayment_p < requiredPayment_p`, THE CovenantFacet SHALL return `breached = true` with `requiredPayment`, `actualPayment`, and `netDraw`
4. WHEN `actualPayment_p >= requiredPayment_p`, THE CovenantFacet SHALL return `breached = false` with the same computed metrics
5. THE CovenantFacet SHALL use deterministic period accounting data from canonical storage mappings (`periodGrossDraw`, `periodRefunds`, `periodPayments`)

### Requirement 26: Covenant Breach Detection

**User Story:** As a protocol participant, I want to trigger breach detection on an agreement, so that draw freezes are enforced when the borrower fails to meet coverage requirements.

#### Acceptance Criteria

1. WHEN `detectBreach(agreementId)` is called and `checkCovenant` returns `breached = true`, THE CovenantFacet SHALL set `drawFrozen = true` on the agreement and record `breachDetectedAt = block.timestamp`
2. WHEN a breach is detected, THE CovenantFacet SHALL emit `CoverageCovenantBreached(agreementId, periodId, requiredPayment, actualPayment, netDraw)`
3. WHEN a breach is detected, THE CovenantFacet SHALL increment `agreementCovenantStrikes` for the agreement
4. IF `checkCovenant` returns `breached = false`, THEN THE CovenantFacet SHALL not modify agreement state
5. IF the agreement already has `drawFrozen = true` from a prior unresolved breach, THEN THE CovenantFacet SHALL not emit a duplicate breach event

### Requirement 27: Covenant Breach Cure

**User Story:** As a borrower, I want to cure a covenant breach by posting additional collateral or making repayments, so that my draw rights are restored.

#### Acceptance Criteria

1. WHEN `cureBreach(agreementId)` is called and `checkCovenant` returns `breached = false` (period payment shortfall resolved), THE CovenantFacet SHALL set `drawFrozen = false` and clear the breach state
2. WHEN a breach is cured, THE CovenantFacet SHALL emit `CoverageCovenantCured(agreementId, periodId, curePayment)`
3. IF `checkCovenant` still returns `breached = true`, THEN THE CovenantFacet SHALL revert with `BreachNotCured`
4. IF the agreement does not have an active breach, THEN THE CovenantFacet SHALL revert with `NoActiveBreach`

### Requirement 28: Covenant Breach Termination

**User Story:** As a lender or governance participant, I want to terminate draw rights after an unresolved breach, so that continued borrowing is permanently stopped when the cure period expires.

#### Acceptance Criteria

1. WHEN `terminateForBreach(agreementId)` is called and `block.timestamp - breachDetectedAt >= covenantCurePeriod`, THE CovenantFacet SHALL set `drawTerminated = true` on the agreement
2. WHEN draw rights are terminated, THE CovenantFacet SHALL emit `DrawRightsTerminated(agreementId, reason)` with reason `keccak256("COVENANT_BREACH")`
3. WHEN draw rights are terminated, THE CovenantFacet SHALL hand off to the Phase 5 default workflow for status transition (`Delinquent -> Defaulted`) if unresolved
4. IF `block.timestamp - breachDetectedAt` is less than `covenantCurePeriod`, THEN THE CovenantFacet SHALL revert with `CurePeriodNotExpired`
5. IF the agreement does not have an active breach, THEN THE CovenantFacet SHALL revert with `NoActiveBreach`
6. WHEN draw rights are terminated, repayments and refunds SHALL remain callable on the agreement

### Requirement 29: Draw Freeze Enforcement

**User Story:** As a protocol auditor, I want draw operations to be blocked when an agreement has a frozen draw state, so that no new capital is deployed during a covenant breach.

#### Acceptance Criteria

1. WHILE an agreement has `drawFrozen = true`, THE ComputeUsageFacet SHALL revert `registerUsage` calls with `DrawFrozen`
2. WHILE an agreement has `drawFrozen = true`, THE ERC8183Facet SHALL revert `createAcpJob` and `fundAcpJob` calls with `DrawFrozen`
3. WHILE an agreement has `drawFrozen = true`, THE AgenticAgreementFacet SHALL continue to accept repayment calls
4. WHILE an agreement has `drawTerminated = true`, THE same draw-blocking behavior SHALL apply permanently

### Requirement 30: Interest Parameter Configuration

**User Story:** As a lender, I want to set interest rate parameters on an agreement before activation, so that the borrower accrues interest on drawn principal.

#### Acceptance Criteria

1. WHEN the lender calls `setInterestParams(agreementId, annualRateBps)` before agreement activation, THE InterestFacet SHALL store the linear interest parameters on the agreement
2. THE InterestFacet SHALL validate that `annualRateBps` is within a reasonable range (0 to 10000 bps, i.e., 0% to 100%)
3. THE InterestFacet SHALL configure linear accrual as the canonical v1.11 baseline behavior
4. IF the agreement has already been activated, THEN THE InterestFacet SHALL revert with `AgreementAlreadyActive`
5. IF the caller is not the lender of the agreement, THEN THE InterestFacet SHALL revert

### Requirement 31: Interest Accrual — Linear

**User Story:** As a protocol operator, I want to accrue linear interest on agreements, so that borrowers owe interest proportional to their outstanding principal and elapsed time.

#### Acceptance Criteria

1. WHEN `accrueInterest(agreementId)` is called, THE InterestFacet SHALL compute interest as `principalDrawn * annualRateBps * elapsedSeconds / (10000 * SECONDS_PER_YEAR)`
2. WHEN interest is accrued, THE InterestFacet SHALL add the computed amount to `interestAccrued` on the agreement
3. WHEN interest is accrued, THE InterestFacet SHALL update `lastAccrualAt` to `block.timestamp`
4. IF `principalDrawn` is zero, THEN THE InterestFacet SHALL accrue zero interest
5. IF `block.timestamp` equals `lastAccrualAt`, THEN THE InterestFacet SHALL accrue zero interest (no double-accrual)

### Requirement 32: Interest Model Guard (v1.11 Baseline)

**User Story:** As a protocol auditor, I want the baseline interest model to stay aligned with canonical v1.11 linear accrual, so that accounting remains deterministic and spec-compliant.

#### Acceptance Criteria

1. THE Phase 4 baseline SHALL NOT require compound-interest state or computation paths for v1.11 completion
2. IF a compound-interest extension is added later, THEN it SHALL be explicitly flagged as post-v1.11 scope and SHALL NOT alter baseline linear accrual tests
3. THE repayment waterfall ordering SHALL remain unchanged: fees -> interest -> principal

### Requirement 33: Pending Interest Query

**User Story:** As any participant, I want to query the pending (unaccrued) interest on an agreement, so that I can see the total interest owed including time elapsed since the last accrual.

#### Acceptance Criteria

1. THE InterestFacet SHALL provide a view function `pendingInterest(agreementId)` that computes interest from `lastAccrualAt` to `block.timestamp` without modifying state
2. THE `pendingInterest` function SHALL return the sum of already-accrued interest plus the newly computed pending amount
3. THE `pendingInterest` function SHALL use the same linear computation logic as `accrueInterest`

### Requirement 34: Fee Schedule Configuration

**User Story:** As a lender, I want to configure fee schedules on agreements, so that origination fees, service fees, and late fees are applied according to the agreement terms.

#### Acceptance Criteria

1. WHEN the lender configures a fee schedule before activation, THE InterestFacet SHALL store origination fee (basis points of credit limit), service fee (basis points per period), and late fee (basis points of past-due amount) parameters
2. WHEN an agreement is activated with a non-zero origination fee, THE InterestFacet SHALL add the origination fee to `feesAccrued` at activation time
3. WHEN a service fee is configured, THE InterestFacet SHALL accrue the service fee proportionally with each interest accrual call
4. WHEN an agreement has an unresolved risk shortfall (`drawFrozen = true`) with a late fee configured, THE InterestFacet SHALL accrue the late fee on the past-due amount

### Requirement 35: Interest Accrual Scheduler (Off-Chain)

**User Story:** As a relayer operator, I want an off-chain scheduler that periodically calls `accrueInterest` for active agreements, so that interest is kept up to date without manual intervention.

#### Acceptance Criteria

1. THE Interest_Accrual_Scheduler SHALL periodically query active agreements and call `accrueInterest` for each agreement where `block.timestamp - lastAccrualAt` exceeds a configurable threshold
2. THE Interest_Accrual_Scheduler SHALL be configurable with an accrual interval (default: 1 hour)
3. IF the `accrueInterest` transaction fails, THE scheduler SHALL log the error and retry on the next cycle
4. THE Interest_Accrual_Scheduler SHALL skip agreements where `principalDrawn` is zero (no interest to accrue)

### Requirement 36: Covenant Monitor (Off-Chain)

**User Story:** As a relayer operator, I want an off-chain monitor that periodically checks covenant compliance for active agreements, so that breaches are detected and enforced promptly.

#### Acceptance Criteria

1. THE Covenant_Monitor SHALL periodically call `checkCovenant` for all active agreements with covenant parameters configured
2. WHEN the Covenant_Monitor detects a breach, THE monitor SHALL call `detectBreach` on-chain to trigger the draw freeze
3. WHEN the Covenant_Monitor detects that a breached agreement's cure period has expired, THE monitor SHALL call `terminateForBreach` on-chain
4. THE Covenant_Monitor SHALL be configurable with a check interval (default: 15 minutes)
5. IF an on-chain transaction fails, THE monitor SHALL log the error and retry on the next cycle

### Requirement 37: Enable Pooled Financing

**User Story:** As a borrower agent, I want to enable pooled financing on a proposal, so that multiple lenders can contribute capital to fund my agreement.

#### Acceptance Criteria

1. WHEN `enablePooledFinancing(proposalId)` is called for a proposal with type `PooledAgentic` or `PooledCompute`, THE PooledFinancingFacet SHALL mark the proposal as pooled and set `counterparty = address(0)` and `lenderPositionId = 0`
2. IF the proposal type is `SoloAgentic` or `SoloCompute`, THEN THE PooledFinancingFacet SHALL revert with `NotPooledProposal`
3. IF the proposal status is not `Pending`, THEN THE PooledFinancingFacet SHALL revert

### Requirement 38: Pool Contribution

**User Story:** As a lender, I want to contribute capital to a pooled financing agreement, so that I earn a proportional share of repayments.

#### Acceptance Criteria

1. WHEN a lender calls `contribute(agreementId)` with a transfer of Settlement_Asset, THE PooledFinancingFacet SHALL record the contribution as a PoolShare with the lender's address and contributed amount
2. WHEN a contribution is made, THE PooledFinancingFacet SHALL increase the agreement's `creditLimit` by the contributed amount
3. WHEN a contribution is made before activation, THE PooledFinancingFacet SHALL allow the contribution to accumulate toward the requested amount
4. IF the agreement has already been activated and the contribution would exceed the requested amount, THEN THE PooledFinancingFacet SHALL revert with `PoolCapExceeded`
5. THE PooledFinancingFacet SHALL transfer the Settlement_Asset from the lender to the contract using `transferFrom`

### Requirement 39: Pool Withdrawal (Pre-Activation)

**User Story:** As a lender, I want to withdraw my contribution before the agreement is activated, so that I can exit the pool if I change my mind.

#### Acceptance Criteria

1. WHEN a lender calls `withdraw(agreementId, amount)` before the agreement is activated, THE PooledFinancingFacet SHALL return the specified amount of Settlement_Asset to the lender and reduce their PoolShare
2. WHEN a withdrawal is made, THE PooledFinancingFacet SHALL decrease the agreement's `creditLimit` by the withdrawn amount
3. IF the agreement has already been activated, THEN THE PooledFinancingFacet SHALL revert with `AgreementAlreadyActive`
4. IF `amount` exceeds the lender's PoolShare, THEN THE PooledFinancingFacet SHALL revert with `InsufficientPoolShare`

### Requirement 40: Pool Share Query

**User Story:** As any participant, I want to view the pool shares for a pooled agreement, so that I can see each lender's contribution and proportional ownership.

#### Acceptance Criteria

1. THE PooledFinancingFacet SHALL provide a view function `getPoolShares(agreementId)` returning an array of PoolShare structs (lender address, amount, proportional share in basis points)
2. THE PooledFinancingFacet SHALL compute each lender's proportional share as `(lenderAmount * 10000) / totalPooled`

### Requirement 41: Pro-Rata Repayment Distribution

**User Story:** As a protocol operator, I want repayments on pooled agreements to be distributed proportionally to pool contributors, so that each lender receives their fair share.

#### Acceptance Criteria

1. WHEN `distributeRepayment(agreementId, amount)` is called for a pooled agreement, THE PooledFinancingFacet SHALL compute each lender's share as `amount * lenderPoolShare / totalPooled`
2. THE PooledFinancingFacet SHALL apply the standard 70/30 fee split before distributing the lender share among pool contributors
3. THE PooledFinancingFacet SHALL handle rounding by assigning any remainder (dust) to the largest pool contributor
4. IF the agreement is not pooled, THEN THE PooledFinancingFacet SHALL revert with `NotPooledAgreement`

### Requirement 42: Governance Proposal Creation

**User Story:** As a pool contributor, I want to create governance proposals for pooled agreements, so that pool decisions (rate changes, collateral actions, termination) are made collectively.

#### Acceptance Criteria

1. WHEN a pool contributor calls `createGovernanceProposal(agreementId, proposalType, data)`, THE GovernanceFacet SHALL create a governance proposal with a unique `voteId` and record the proposer
2. THE GovernanceFacet SHALL support proposal types: RateChange, CollateralAction, DrawTermination, AgreementClosure, ParameterUpdate
3. WHEN a governance proposal is created, THE GovernanceFacet SHALL snapshot the current pool shares for vote weighting
4. IF the caller does not hold a PoolShare in the agreement, THEN THE GovernanceFacet SHALL revert with `NotPoolContributor`
5. IF the agreement is not pooled, THEN THE GovernanceFacet SHALL revert with `NotPooledAgreement`

### Requirement 43: Governance Voting

**User Story:** As a pool contributor, I want to vote on governance proposals, so that I can participate in collective decisions proportional to my pool share.

#### Acceptance Criteria

1. WHEN a pool contributor calls `vote(voteId, support)`, THE GovernanceFacet SHALL record the vote weighted by the contributor's pool share at the snapshot
2. THE GovernanceFacet SHALL prevent double-voting: each address can vote once per proposal
3. IF the caller does not hold a PoolShare at the snapshot, THEN THE GovernanceFacet SHALL revert with `NotPoolContributor`
4. IF the voting period has expired, THEN THE GovernanceFacet SHALL revert with `VotingPeriodExpired`

### Requirement 44: Governance Proposal Execution

**User Story:** As a protocol participant, I want to execute passed governance proposals, so that approved pool decisions take effect on-chain.

#### Acceptance Criteria

1. WHEN `executeProposal(voteId)` is called for a proposal that has met quorum and passed the threshold, THE GovernanceFacet SHALL execute the encoded action
2. THE GovernanceFacet SHALL verify quorum: total votes cast (by pool share weight) must be at least `quorumBps` of total pool shares (default: 2000 = 20%)
3. THE GovernanceFacet SHALL verify pass threshold: votes in favor must be at least `passThresholdBps` of votes cast (default: 5500 = 55%)
4. IF quorum is not met, THEN THE GovernanceFacet SHALL revert with `QuorumNotMet`
5. IF the pass threshold is not met, THEN THE GovernanceFacet SHALL revert with `ProposalNotPassed`
6. IF the proposal has already been executed, THEN THE GovernanceFacet SHALL revert with `ProposalAlreadyExecuted`

### Requirement 45: Governance Quorum Configuration

**User Story:** As a protocol administrator, I want to configure the governance quorum and pass threshold, so that pool voting parameters can be tuned per deployment.

#### Acceptance Criteria

1. WHEN an Admin_Role address calls `setQuorum(quorumBps)`, THE GovernanceFacet SHALL update the global quorum parameter
2. THE GovernanceFacet SHALL validate that `quorumBps` is between 100 (1%) and 10000 (100%)
3. THE GovernanceFacet SHALL provide a `setPassThreshold(passThresholdBps)` function with the same Admin_Role restriction
4. IF the caller does not have Admin_Role, THEN THE GovernanceFacet SHALL revert
