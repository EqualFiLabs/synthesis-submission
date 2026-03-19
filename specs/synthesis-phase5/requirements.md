# Requirements Document

## Introduction

Phase 5 of the Equalis Agentic Financing protocol delivers production-grade risk management and comprehensive test coverage. Building on Phase 1's core proposal/agreement/accounting facets, Phase 2's event infrastructure, Phase 3's compute provider adapters, and Phase 4's ERC-8004/ERC-8183/collateral/covenant/interest/pooled/governance subsystems, Phase 5 adds:

1. **Delinquency/Default/Write-Off State Machine** — Formal state transitions from Active through Delinquent, Defaulted, and WrittenOff with deterministic triggers
2. **Circuit Breakers** — Global and per-facet pause switches controlled by governance/timelock, with non-pausable refund liveness
3. **Write-Off Accounting** — Solo lender-borne loss and pooled pro-rata loss distribution
4. **Full Invariant Test Suite** — Cross-product accounting, native encumbrance conservation, covenant enforcement, collateral toggle, ACP terminal-state sync, trust-mode gating, position transfer continuity
5. **Differential Portability Tests** — Identical core accounting outcomes across at least 2 ERC-8183 adapters and at least 2 compute adapters
6. **Stress Testing and Gas Optimization** — High-volume agreement creation, concurrent metering, gas profiling
7. **Security Audit Preparation** — Access control review, reentrancy analysis, storage collision checks, upgrade safety verification

Phase 5 is additive. No semantic feature changes to Phase 1–4 facets or storage layouts are required; canonical reconciliation patches to Phase 1–4 documentation are allowed.
Phase 5 is the sole owner of `Delinquent`, `Defaulted`, and `WrittenOff` status transitions; earlier phases may freeze/terminate draws but do not mutate these risk statuses.
Before marking Phase 5 complete, Phase 4.5 reconciliation outputs SHALL be applied so all upstream docs align with canonical v1.11.

### Cross-Chain Note (ERC-8004)

Phase 5 assumes Phase 4 ERC-8004 adapters are callable on-chain and therefore deployed on the same chain as the Diamond. If ERC-8004 identity lives on another chain (e.g. Base) while the Diamond is deployed on Arbitrum, then ERC-8004-driven gating/feedback cannot be trustlessly enforced on-chain without an oracle/bridge design. For hackathon scope, treat cross-chain identity as an offchain concern (Phase 2 offchain resolver).

### Explicitly Out of Scope

- Semantic feature modifications to Phase 1 Diamond facets or storage layout
- Semantic feature modifications to Phase 2 EventListener or TransactionSubmitter
- Semantic feature modifications to Phase 3 compute provider adapters (Lambda, RunPod, Venice, Bankr)
- Semantic feature modifications to Phase 4 ERC-8004, ERC-8183, collateral, covenant, interest, pooled, or governance facets
- Frontend or UI components
- Production mainnet deployment or HSM/KMS key management
- Module mirror bridge from native encumbrance state (optional, non-canonical)
- Token economics beyond the fee/interest model defined in canonical spec

## Glossary

- **Delinquency_State_Machine**: The formal state transition logic governing agreement progression from Active to Delinquent, Defaulted, and WrittenOff based on payment shortfalls, covenant breaches, and collateral shortfalls
- **Delinquent**: An agreement status indicating past-due obligations exist (payment shortfall, coverage covenant breach, or collateral shortfall) beyond the grace period boundary
- **Defaulted**: An agreement status indicating unresolved delinquency past the cure/grace period threshold, with draw rights permanently terminated
- **WrittenOff**: A terminal agreement status indicating the remaining debt has been recognized as a loss and distributed according to product type
- **Circuit_Breaker**: A pause switch that halts specific protocol operations (proposals, approvals, draws, governance) while preserving repayment and refund liveness
- **Pause_Registry**: The on-chain storage mapping circuit breaker keys to their enabled/disabled state, controlled by governance/timelock authority
- **Write_Off_Amount**: The remaining unpaid debt (principal + accrued interest + accrued fees minus cumulative repayments and recovered collateral) recognized as a loss at write-off
- **Pro_Rata_Loss**: The proportional distribution of write-off losses to pooled agreement contributors based on their pool share weight
- **Grace_Period**: The time window (3 to 30 days per canonical defaults) after a payment due date before delinquency is triggered
- **Default_Threshold**: The elapsed time after delinquency detection at which the agreement transitions to Defaulted (equal to covenantCurePeriod, default 7 days)
- **Penalty_Schedule**: The set of penalty fees applied to defaulted agreements (late fees, liquidation penalty)
- **Invariant_Test**: A property-based test that verifies a condition holds across all valid inputs and state transitions
- **Differential_Test**: A test that runs identical operation sequences through two or more adapter implementations and asserts identical core accounting outcomes
- **Cross_Product_Accounting**: The property that SoloAgentic, PooledAgentic, SoloCompute, and PooledCompute agreements produce identical repayment waterfall and fee routing behavior for equivalent inputs
- **Encumbrance_Conservation**: The property that `principalEncumbered` always reflects the true financing position after any state transition (draw, repay, refund, default, write-off)
- **Position_Transfer_Continuity**: The property that agreement accounting remains consistent when the underlying position NFT is transferred
- **AgenticRiskFacet**: The Diamond facet responsible for delinquency detection, default transitions, write-off execution, and circuit breaker management
- **Governance_Timelock**: The governance-controlled address authorized to toggle circuit breakers and execute write-offs
- **Settlement_Asset**: The ERC-20 token (e.g., USDC) used for agreement accounting, repayments, and settlements
- **P4_Invariants**: The set of canonical invariants P4-1 through P4-7 defined in the canonical spec Section 11 testing properties, covering collateral conservation, interest monotonicity, covenant breach detection, draw freeze enforcement, cure period timing, pool share conservation, and pro-rata distribution correctness

## Requirements

### Requirement 1: Delinquency Detection

**User Story:** As a protocol operator, I want the system to detect when an agreement becomes delinquent, so that risk management actions are triggered promptly when obligations are not met.

#### Acceptance Criteria

1. WHEN `detectDelinquency(agreementId)` is called for an Active agreement where `pastDue > 0` and `block.timestamp > firstDueAt + gracePeriod`, THE AgenticRiskFacet SHALL transition the agreement status from Active to Delinquent
2. WHEN `detectDelinquency(agreementId)` is called for an Active agreement where a coverage covenant breach exists (as determined by CovenantFacet `checkCovenant`), THE AgenticRiskFacet SHALL transition the agreement status from Active to Delinquent
3. WHEN `detectDelinquency(agreementId)` is called for an Active agreement with `collateralEnabled = true` where the collateral ratio falls below `maintenanceCollateralRatioBps`, THE AgenticRiskFacet SHALL transition the agreement status from Active to Delinquent
4. WHEN an agreement transitions to Delinquent, THE AgenticRiskFacet SHALL set `drawFrozen = true` on the agreement and emit `AgreementDelinquent(agreementId, pastDue)`
5. IF the agreement status is not Active, THEN THE AgenticRiskFacet SHALL revert with `InvalidStatusTransition`
6. IF no delinquency condition is met (no payment shortfall, no covenant breach, no collateral shortfall), THEN THE AgenticRiskFacet SHALL revert with `NotDelinquent`

### Requirement 2: Delinquency Cure

**User Story:** As a borrower, I want to cure a delinquent agreement by resolving all shortfalls, so that my agreement returns to Active status and draw rights are restored.

#### Acceptance Criteria

1. WHEN `cureDelinquency(agreementId)` is called for a Delinquent agreement where all shortfalls are resolved (pastDue = 0, no covenant breach, no collateral shortfall), THE AgenticRiskFacet SHALL transition the agreement status from Delinquent to Active
2. WHEN a delinquency is cured, THE AgenticRiskFacet SHALL set `drawFrozen = false` (unless a separate covenant breach freeze is still active) and emit `AgreementDelinquencyCured(agreementId)`
3. IF any shortfall condition remains unresolved, THEN THE AgenticRiskFacet SHALL revert with `DelinquencyNotCured`
4. IF the agreement status is not Delinquent, THEN THE AgenticRiskFacet SHALL revert with `InvalidStatusTransition`

### Requirement 3: Default Transition

**User Story:** As a protocol operator, I want the system to transition a delinquent agreement to Defaulted status when the cure period expires, so that permanent risk controls are applied to protect lenders.

#### Acceptance Criteria

1. WHEN `triggerDefault(agreementId)` is called for a Delinquent agreement where `block.timestamp - delinquentAt >= covenantCurePeriod`, THE AgenticRiskFacet SHALL transition the agreement status from Delinquent to Defaulted
2. WHEN an agreement transitions to Defaulted, THE AgenticRiskFacet SHALL set `drawTerminated = true` permanently and emit `AgreementDefaulted(agreementId, pastDue)`
3. WHEN an agreement transitions to Defaulted, THE AgenticRiskFacet SHALL apply the penalty schedule: add `liquidationPenaltyBps` of outstanding principal to `feesAccrued`
4. WHILE an agreement has status Defaulted, THE AgenticAgreementFacet SHALL continue to accept repayment calls
5. WHILE an agreement has status Defaulted, THE ERC8183Facet SHALL continue to allow `claimAcpRefund` calls
6. IF `block.timestamp - delinquentAt` is less than `covenantCurePeriod`, THEN THE AgenticRiskFacet SHALL revert with `CurePeriodNotExpired`
7. IF the agreement status is not Delinquent, THEN THE AgenticRiskFacet SHALL revert with `InvalidStatusTransition`

### Requirement 4: Default Recovery

**User Story:** As a lender, I want to recover funds from a defaulted agreement through collateral seizure and continued repayments, so that losses are minimized before write-off.

#### Acceptance Criteria

1. WHILE an agreement has status Defaulted and `collateralEnabled = true`, THE AgenticRiskFacet SHALL allow collateral seizure via CollateralManagerFacet up to `collateralPosted - collateralSeized`
2. WHEN a defaulted agreement receives sufficient repayments and collateral recovery to fully satisfy all outstanding obligations (principal + interest + fees), THE AgenticRiskFacet SHALL allow transition from Defaulted to Closed via `closeRecoveredAgreement(agreementId)`
3. WHEN a defaulted agreement is closed through full recovery, THE AgenticRiskFacet SHALL emit `AgreementClosed(agreementId)` and set the agreement status to Closed
4. IF outstanding obligations remain when `closeRecoveredAgreement` is called, THEN THE AgenticRiskFacet SHALL revert with `ObligationsRemaining`

### Requirement 5: Write-Off Transition

**User Story:** As a governance participant, I want to write off an unrecoverable defaulted agreement, so that the loss is formally recognized and distributed according to the product type.

#### Acceptance Criteria

1. WHEN a Governance_Timelock address calls `writeOff(agreementId)` for a Defaulted agreement, THE AgenticRiskFacet SHALL transition the agreement status from Defaulted to WrittenOff
2. WHEN an agreement is written off, THE AgenticRiskFacet SHALL compute `writeOffAmount = principalDrawn - principalRepaid + interestAccrued + feesAccrued - cumulativePayments - collateralSeized` (the net unrecovered loss)
3. WHEN an agreement is written off, THE AgenticRiskFacet SHALL emit `AgreementWrittenOff(agreementId, writeOffAmount)`
4. WHEN an agreement is written off, THE AgenticRiskFacet SHALL set `principalEncumbered = 0` and emit `NativeEncumbranceUpdated` with reason `keccak256("WRITE_OFF")`
5. IF the caller is not the Governance_Timelock address, THEN THE AgenticRiskFacet SHALL revert with `NotAuthorized`
6. IF the agreement status is not Defaulted, THEN THE AgenticRiskFacet SHALL revert with `InvalidStatusTransition`

### Requirement 6: Solo Write-Off Accounting

**User Story:** As a solo lender, I want write-off losses on my solo agreements to be borne entirely by me, so that loss attribution is clear and deterministic.

#### Acceptance Criteria

1. WHEN a solo agreement (SoloAgentic or SoloCompute) is written off, THE AgenticRiskFacet SHALL attribute the full `writeOffAmount` to the single lender's position
2. WHEN a solo write-off is executed, THE AgenticRiskFacet SHALL emit `WriteOffLossAttributed(agreementId, lenderAddress, writeOffAmount)` with the lender address from the agreement's `lenderPositionKey`
3. WHEN a solo write-off is executed, THE AgenticRiskFacet SHALL reduce the lender's position value by the `writeOffAmount` via native encumbrance update
4. THE AgenticRiskFacet SHALL prevent any further repayment distribution to the written-off solo agreement

### Requirement 7: Pooled Write-Off Accounting

**User Story:** As a pool contributor, I want write-off losses on pooled agreements to be distributed pro-rata to all pool contributors, so that each lender bears a fair share of the loss.

#### Acceptance Criteria

1. WHEN a pooled agreement (PooledAgentic or PooledCompute) is written off, THE AgenticRiskFacet SHALL compute each contributor's loss share as `writeOffAmount * lenderPoolShare / totalPooled`
2. WHEN a pooled write-off is executed, THE AgenticRiskFacet SHALL emit `WriteOffLossAttributed(agreementId, lenderAddress, lossShare)` for each pool contributor
3. WHEN a pooled write-off is executed, THE AgenticRiskFacet SHALL handle rounding by assigning any remainder (dust) to the largest pool contributor
4. THE AgenticRiskFacet SHALL reduce each contributor's pool share value by their computed loss share
5. THE AgenticRiskFacet SHALL prevent any further repayment distribution to the written-off pooled agreement

### Requirement 8: Circuit Breaker — Proposal Pause

**User Story:** As a governance operator, I want to pause new proposal creation, so that the protocol can halt new financing requests during emergencies.

#### Acceptance Criteria

1. WHEN a Governance_Timelock address calls `setCircuitBreaker(keccak256("PROPOSALS"), true)`, THE AgenticRiskFacet SHALL store the pause state in the Pause_Registry
2. WHILE the `PROPOSALS` circuit breaker is active, THE AgenticProposalFacet SHALL revert all `createProposal` calls with `CircuitBreakerActive("PROPOSALS")`
3. WHEN a Governance_Timelock address calls `setCircuitBreaker(keccak256("PROPOSALS"), false)`, THE AgenticRiskFacet SHALL clear the pause state and resume normal proposal creation
4. WHEN a circuit breaker state changes, THE AgenticRiskFacet SHALL emit `CircuitBreakerToggled(breakerKey, enabled, caller)`
5. IF the caller is not the Governance_Timelock address, THEN THE AgenticRiskFacet SHALL revert with `NotAuthorized`

### Requirement 9: Circuit Breaker — Approval Pause

**User Story:** As a governance operator, I want to pause new agreement approvals, so that the protocol can halt new financing activations during emergencies.

#### Acceptance Criteria

1. WHEN a Governance_Timelock address calls `setCircuitBreaker(keccak256("APPROVALS"), true)`, THE AgenticRiskFacet SHALL store the pause state in the Pause_Registry
2. WHILE the `APPROVALS` circuit breaker is active, THE AgenticApprovalFacet SHALL revert all approval and activation calls with `CircuitBreakerActive("APPROVALS")`
3. WHEN the `APPROVALS` circuit breaker is deactivated, THE AgenticApprovalFacet SHALL resume normal approval processing
4. WHEN a circuit breaker state changes, THE AgenticRiskFacet SHALL emit `CircuitBreakerToggled(breakerKey, enabled, caller)`

### Requirement 10: Circuit Breaker — Draw Pause

**User Story:** As a governance operator, I want to pause all new draw operations, so that the protocol can halt capital deployment during emergencies.

#### Acceptance Criteria

1. WHEN a Governance_Timelock address calls `setCircuitBreaker(keccak256("DRAWS"), true)`, THE AgenticRiskFacet SHALL store the pause state in the Pause_Registry
2. WHILE the `DRAWS` circuit breaker is active, THE AgenticAgreementFacet SHALL revert all draw calls with `CircuitBreakerActive("DRAWS")`
3. WHILE the `DRAWS` circuit breaker is active, THE ComputeUsageFacet SHALL revert all `registerUsage` calls with `CircuitBreakerActive("DRAWS")`
4. WHILE the `DRAWS` circuit breaker is active, THE ERC8183Facet SHALL revert `createAcpJob`, `setAcpBudget`, and `fundAcpJob` calls with `CircuitBreakerActive("DRAWS")`
5. WHILE the `DRAWS` circuit breaker is active, THE AgenticAgreementFacet SHALL continue to accept repayment calls
6. WHEN the `DRAWS` circuit breaker is deactivated, all draw operations SHALL resume normal processing

### Requirement 11: Circuit Breaker — Governance Pause

**User Story:** As a governance operator, I want to pause governance proposal finalization, so that the protocol can halt pool governance actions during emergencies.

#### Acceptance Criteria

1. WHEN a Governance_Timelock address calls `setCircuitBreaker(keccak256("GOVERNANCE"), true)`, THE AgenticRiskFacet SHALL store the pause state in the Pause_Registry
2. WHILE the `GOVERNANCE` circuit breaker is active, THE GovernanceFacet SHALL revert `executeProposal` calls with `CircuitBreakerActive("GOVERNANCE")`
3. WHILE the `GOVERNANCE` circuit breaker is active, THE GovernanceFacet SHALL continue to allow vote casting (only execution is paused)
4. WHEN the `GOVERNANCE` circuit breaker is deactivated, governance execution SHALL resume normal processing

### Requirement 12: Circuit Breaker — ACP Operations Pause

**User Story:** As a governance operator, I want to pause ACP job creation and funding operations, so that the protocol can halt new ACP-linked work during emergencies while preserving refund liveness.

#### Acceptance Criteria

1. WHEN a Governance_Timelock address calls `setCircuitBreaker(keccak256("ACP_OPS"), true)`, THE AgenticRiskFacet SHALL store the pause state in the Pause_Registry
2. WHILE the `ACP_OPS` circuit breaker is active, THE ERC8183Facet SHALL revert `createAcpJob`, `setAcpBudget`, and `fundAcpJob` calls with `CircuitBreakerActive("ACP_OPS")`
3. WHILE the `ACP_OPS` circuit breaker is active, THE ERC8183Facet SHALL continue to allow `completeAcpJob`, `rejectAcpJob`, and `claimAcpRefund` calls — terminal state resolution and refund liveness are non-pausable
4. WHEN the `ACP_OPS` circuit breaker is deactivated, ACP job creation and funding SHALL resume normal processing

### Requirement 13: Refund Liveness Non-Pausability

**User Story:** As a protocol participant, I want `claimAcpRefund` to remain callable regardless of any circuit breaker state, so that escrowed funds for expired ACP jobs are always recoverable.

#### Acceptance Criteria

1. THE ERC8183Facet `claimAcpRefund` function SHALL bypass all circuit breaker checks — no circuit breaker key SHALL block refund claims
2. WHILE any combination of circuit breakers is active (PROPOSALS, APPROVALS, DRAWS, GOVERNANCE, ACP_OPS), THE ERC8183Facet SHALL process `claimAcpRefund` calls normally
3. THE `claimAcpRefund` function SHALL apply the standard refund accounting (reduce `principalDrawn`, emit `ACPJobResolved`) regardless of pause state

### Requirement 14: Circuit Breaker View

**User Story:** As any participant, I want to query the current state of all circuit breakers, so that I can determine which protocol operations are currently paused.

#### Acceptance Criteria

1. THE AgenticRiskFacet SHALL provide a view function `getCircuitBreaker(breakerKey)` returning the current enabled/disabled state for the specified breaker key
2. THE AgenticRiskFacet SHALL provide a view function `getAllCircuitBreakers()` returning the state of all defined circuit breaker keys (PROPOSALS, APPROVALS, DRAWS, GOVERNANCE, ACP_OPS)

### Requirement 15: Delinquency Monitor (Off-Chain)

**User Story:** As a relayer operator, I want an off-chain monitor that periodically checks for delinquent agreements and triggers on-chain state transitions, so that risk management is enforced promptly.

#### Acceptance Criteria

1. THE Delinquency_Monitor SHALL periodically query all Active agreements and evaluate delinquency conditions (payment shortfall, covenant breach, collateral shortfall)
2. WHEN the Delinquency_Monitor detects a delinquency condition, THE monitor SHALL call `detectDelinquency(agreementId)` on-chain
3. WHEN the Delinquency_Monitor detects that a Delinquent agreement's cure period has expired, THE monitor SHALL call `triggerDefault(agreementId)` on-chain
4. THE Delinquency_Monitor SHALL be configurable with a check interval (default: 15 minutes)
5. IF an on-chain transaction fails, THE monitor SHALL log the error and retry on the next cycle

### Requirement 16: Cross-Product Accounting Invariant Tests

**User Story:** As a protocol auditor, I want invariant tests proving that all four product types (SoloAgentic, PooledAgentic, SoloCompute, PooledCompute) produce identical repayment waterfall and fee routing behavior, so that accounting consistency is verified across the product matrix.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that for equivalent inputs (same principal, same rate, same fees, same repayment amounts), the repayment waterfall (fees → interest → principal) produces identical allocation across SoloAgentic, PooledAgentic, SoloCompute, and PooledCompute agreements
2. THE Invariant_Test_Suite SHALL verify that the 70/30 lender/protocol fee split is applied identically across all four product types
3. THE Invariant_Test_Suite SHALL verify that `principalDrawn - principalRepaid` is consistent with `principalEncumbered` after any sequence of draw and repay operations across all product types
4. THE Invariant_Test_Suite SHALL use property-based testing (fuzz) with randomized draw amounts, repayment amounts, and operation sequences to exercise the cross-product accounting property

### Requirement 17: Native Encumbrance Conservation Invariant Tests

**User Story:** As a protocol auditor, I want invariant tests proving that `principalEncumbered` always reflects the true financing position, so that the native encumbrance source of truth is verified.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that after any `draw` operation, `principalEncumbered` increases by exactly the drawn amount
2. THE Invariant_Test_Suite SHALL verify that after any `repay` operation applying principal reduction, `principalEncumbered` decreases by exactly the principal portion of the repayment
3. THE Invariant_Test_Suite SHALL verify that after any ACP refund (rejected or expired job), `principalEncumbered` decreases by exactly the refunded amount
4. THE Invariant_Test_Suite SHALL verify that after a write-off, `principalEncumbered` is set to zero
5. THE Invariant_Test_Suite SHALL verify that `principalEncumbered` is never negative (underflow protection)
6. FOR ALL valid operation sequences, THE Invariant_Test_Suite SHALL verify that `principalEncumbered = principalDrawn - principalRepaid` holds as a round-trip conservation property

### Requirement 18: Collateral Conservation Invariant Tests (P4-1)

**User Story:** As a protocol auditor, I want invariant tests proving that collateral is conserved across all operations, so that no collateral is created or destroyed outside of explicit post/release/seize operations.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that `collateralPosted` only increases via `postCollateral` calls and only decreases via `releaseCollateral` or `seizeCollateral` calls
2. THE Invariant_Test_Suite SHALL verify that `collateralSeized <= collateralPosted` at all times
3. THE Invariant_Test_Suite SHALL verify that `collateralPosted - collateralSeized` equals the actual collateral asset balance held by the contract for the agreement
4. FOR ALL valid operation sequences involving collateral, THE Invariant_Test_Suite SHALL verify that the total collateral in the system is conserved (no creation or destruction)

### Requirement 19: Interest Monotonicity Invariant Tests (P4-2)

**User Story:** As a protocol auditor, I want invariant tests proving that accrued interest never decreases, so that interest accounting integrity is verified.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that `interestAccrued` is monotonically non-decreasing across all `accrueInterest` calls for any agreement
2. THE Invariant_Test_Suite SHALL verify that `interestAccrued` increases by a positive amount when `principalDrawn > 0` and `block.timestamp > lastAccrualAt` and `annualRateBps > 0`
3. THE Invariant_Test_Suite SHALL verify that `interestAccrued` remains unchanged when `principalDrawn = 0` regardless of elapsed time
4. FOR ALL valid sequences of draw, repay, and accrueInterest operations, THE Invariant_Test_Suite SHALL verify that interest monotonicity holds

### Requirement 20: Covenant Breach Detection Correctness Invariant Tests (P4-3)

**User Story:** As a protocol auditor, I want invariant tests proving that covenant breach detection is correct and deterministic, so that false positives and false negatives are eliminated.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that `checkCovenant` computes `requiredPayment_p = feesDue_p + interestDue_p + (netDraw_p * minNetDrawCoverageBps / 10000) + principalFloorPerPeriod` for each period `p`
2. THE Invariant_Test_Suite SHALL verify that `checkCovenant` returns `breached = true` if and only if `actualPayment_p < requiredPayment_p`
3. THE Invariant_Test_Suite SHALL verify that `detectBreach` sets `drawFrozen = true` if and only if `checkCovenant` returns `breached = true`
4. FOR ALL valid combinations of period draws/refunds/payments, THE Invariant_Test_Suite SHALL verify that breach detection produces the correct boolean result deterministically

### Requirement 21: Draw Freeze Enforcement Invariant Tests (P4-4)

**User Story:** As a protocol auditor, I want invariant tests proving that draw operations are blocked when `drawFrozen = true` or `drawTerminated = true`, so that capital deployment is halted during risk events.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that all draw-path functions (`draw`, `registerUsage`, `createAcpJob`, `setAcpBudget`, `fundAcpJob`) revert when `drawFrozen = true`
2. THE Invariant_Test_Suite SHALL verify that all draw-path functions revert when `drawTerminated = true`
3. THE Invariant_Test_Suite SHALL verify that repayment functions remain callable when `drawFrozen = true` or `drawTerminated = true`
4. THE Invariant_Test_Suite SHALL verify that `claimAcpRefund` remains callable when `drawFrozen = true` or `drawTerminated = true`
5. FOR ALL agreement states with `drawFrozen = true`, THE Invariant_Test_Suite SHALL verify that `principalDrawn` does not increase

### Requirement 22: Cure Period Timing Invariant Tests (P4-5)

**User Story:** As a protocol auditor, I want invariant tests proving that cure period timing is enforced correctly, so that defaults cannot be triggered prematurely and cures are accepted within the window.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that `triggerDefault` reverts when `block.timestamp - delinquentAt < covenantCurePeriod`
2. THE Invariant_Test_Suite SHALL verify that `triggerDefault` succeeds when `block.timestamp - delinquentAt >= covenantCurePeriod`
3. THE Invariant_Test_Suite SHALL verify that `cureDelinquency` succeeds at any point during the cure period when all shortfalls are resolved
4. THE Invariant_Test_Suite SHALL verify that `covenantCurePeriod` is bounded between 3 days and 30 days (canonical policy defaults)
5. FOR ALL valid `delinquentAt` and `covenantCurePeriod` combinations, THE Invariant_Test_Suite SHALL verify that the timing boundary is deterministic

### Requirement 23: Pool Share Conservation Invariant Tests (P4-6)

**User Story:** As a protocol auditor, I want invariant tests proving that pool shares are conserved across all operations, so that no pool share value is created or destroyed outside of explicit contribute/withdraw/write-off operations.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that the sum of all pool shares equals the total pooled amount at all times
2. THE Invariant_Test_Suite SHALL verify that pool shares only increase via `contribute` calls and only decrease via `withdraw` (pre-activation) or write-off loss attribution
3. THE Invariant_Test_Suite SHALL verify that each contributor's proportional share in basis points sums to 10000 (100%) across all contributors
4. FOR ALL valid sequences of contribute, withdraw, and write-off operations, THE Invariant_Test_Suite SHALL verify that pool share conservation holds

### Requirement 24: Pro-Rata Distribution Correctness Invariant Tests (P4-7)

**User Story:** As a protocol auditor, I want invariant tests proving that pro-rata distributions are correct and complete, so that every repayment and write-off loss is fully distributed with no funds lost to rounding.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that the sum of all individual pro-rata distributions equals the total distribution amount (no funds lost)
2. THE Invariant_Test_Suite SHALL verify that each contributor receives a share proportional to their pool share weight within a rounding tolerance of 1 wei per contributor
3. THE Invariant_Test_Suite SHALL verify that rounding dust is assigned to the largest pool contributor
4. FOR ALL valid pool configurations and distribution amounts, THE Invariant_Test_Suite SHALL verify that pro-rata distribution is complete and correct via round-trip property: `sum(individual_shares) == total_amount`

### Requirement 25: ACP Terminal-State Accounting Synchronization Tests

**User Story:** As a protocol auditor, I want tests proving that ACP job terminal states synchronize correctly to agreement accounting, so that completed/rejected/expired jobs produce the correct accounting effects.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that a Completed ACP job leaves `principalDrawn` unchanged (no refund applied)
2. THE Invariant_Test_Suite SHALL verify that a Rejected ACP job reduces `principalDrawn` by exactly the refunded amount
3. THE Invariant_Test_Suite SHALL verify that an Expired ACP job (via `claimAcpRefund`) reduces `principalDrawn` by exactly the refunded amount
4. THE Invariant_Test_Suite SHALL verify that no ACP job can transition to a terminal state more than once (terminal finality)
5. THE Invariant_Test_Suite SHALL verify that accounting adjustments from terminal transitions are applied exactly once
6. FOR ALL valid ACP job lifecycle sequences, THE Invariant_Test_Suite SHALL verify that `principalDrawn` reflects the correct cumulative effect of all terminal state transitions

### Requirement 26: Trust-Mode Gating Enforcement Tests

**User Story:** As a protocol auditor, I want tests proving that trust modes gate transitions correctly across all four modes, so that identity, reputation, and validation requirements are enforced deterministically.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that DiscoveryOnly agreements allow activation without reputation or validation checks
2. THE Invariant_Test_Suite SHALL verify that ReputationOnly agreements revert activation when the borrower's reputation summary value is below `minReputationValue`
3. THE Invariant_Test_Suite SHALL verify that ValidationRequired agreements revert activation when the borrower's validation response is below `minValidationResponse`
4. THE Invariant_Test_Suite SHALL verify that Hybrid agreements revert activation when either the reputation or validation threshold is not met
5. FOR ALL four trust modes and all valid threshold combinations, THE Invariant_Test_Suite SHALL verify that gating is deterministic and consistent

### Requirement 27: Collateral Toggle Invariant Tests

**User Story:** As a protocol auditor, I want tests proving that the optional collateral toggle works deterministically, so that collateral is never required when disabled and always enforced when enabled.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that agreements with `collateralEnabled = false` can be activated without any collateral posted
2. THE Invariant_Test_Suite SHALL verify that agreements with `collateralEnabled = true` require `collateralPosted` to satisfy `minCollateralRatioBps` at activation
3. THE Invariant_Test_Suite SHALL verify that `postCollateral` reverts for agreements with `collateralEnabled = false`
4. THE Invariant_Test_Suite SHALL verify that collateral shortfall delinquency is only triggered for agreements with `collateralEnabled = true`
5. FOR ALL valid toggle states and collateral amounts, THE Invariant_Test_Suite SHALL verify that the toggle behavior is deterministic

### Requirement 28: Position Transfer Continuity Tests

**User Story:** As a protocol auditor, I want tests proving that agreement accounting remains consistent when the underlying position NFT is transferred, so that position portability does not break financing invariants.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that after a position NFT transfer, the agreement's `principalEncumbered`, `principalDrawn`, `principalRepaid`, `interestAccrued`, and `feesAccrued` remain unchanged
2. THE Invariant_Test_Suite SHALL verify that after a position NFT transfer, the new position holder can execute authorized operations (repay, close) on the agreement
3. THE Invariant_Test_Suite SHALL verify that encumbrance conservation holds across position transfers

### Requirement 29: Differential ERC-8183 Adapter Portability Tests

**User Story:** As a protocol auditor, I want differential tests proving that at least two ERC-8183 adapters (Reference8183Adapter and MockGeneric8183Adapter) produce identical core accounting outcomes, so that venue portability is verified.

#### Acceptance Criteria

1. THE Differential_Test_Suite SHALL execute identical ACP job lifecycle sequences (create → fund → submit → complete, create → fund → submit → reject, create → fund → expire → claimRefund) through both Reference8183Adapter and MockGeneric8183Adapter
2. THE Differential_Test_Suite SHALL assert that `principalDrawn`, `principalRepaid`, `principalEncumbered`, `interestAccrued`, and `feesAccrued` are identical on the linked agreement after each lifecycle sequence through both adapters
3. THE Differential_Test_Suite SHALL assert that terminal state accounting (refund amounts for rejected/expired jobs) is identical across both adapters
4. THE Differential_Test_Suite SHALL execute at least 3 distinct lifecycle sequences per adapter pair: full completion, rejection with refund, and expiry with refund
5. FOR ALL tested lifecycle sequences, THE Differential_Test_Suite SHALL verify that the adapter choice does not affect core agreement accounting

### Requirement 30: Differential Compute Adapter Portability Tests

**User Story:** As a protocol auditor, I want differential tests proving that at least two compute adapters produce identical core accounting outcomes, so that compute provider portability is verified.

#### Acceptance Criteria

1. THE Differential_Test_Suite SHALL execute identical compute usage sequences (register usage, accrue interest, repay) through at least two compute adapters (e.g., Venice + Lambda, Bankr + Lambda, Venice + RunPod, or Bankr + RunPod)
2. THE Differential_Test_Suite SHALL assert that `principalDrawn`, `unitsEncumbered`, `interestAccrued`, and `feesAccrued` are identical on the linked agreement after each usage sequence through both adapters
3. THE Differential_Test_Suite SHALL assert that the monetary liability computation (`usedUnits * unitPrice`) is identical across both adapters for the same unit type and quantity
4. THE Differential_Test_Suite SHALL include at least one API-based inference adapter (Venice or Bankr) in the comparison set
5. FOR ALL tested usage sequences, THE Differential_Test_Suite SHALL verify that the compute provider choice does not affect core agreement accounting

### Requirement 31: Delinquency/Default/Write-Off State Machine Invariant Tests

**User Story:** As a protocol auditor, I want invariant tests proving that the delinquency/default/write-off state machine follows the canonical transition graph, so that no invalid state transitions are possible.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that the only valid status transitions are: Active → Delinquent, Delinquent → Active (cure), Delinquent → Defaulted, Defaulted → Closed (full recovery), Defaulted → WrittenOff, and Active → Closed (normal closure)
2. THE Invariant_Test_Suite SHALL verify that no transition from WrittenOff to any other status is possible (terminal state)
3. THE Invariant_Test_Suite SHALL verify that no transition from Closed to any other status is possible (terminal state)
4. THE Invariant_Test_Suite SHALL verify that `drawTerminated` is set to true on every Defaulted transition and is never reset to false
5. FOR ALL valid and invalid status transition attempts, THE Invariant_Test_Suite SHALL verify that only canonical transitions succeed and all others revert

### Requirement 32: Circuit Breaker Invariant Tests

**User Story:** As a protocol auditor, I want invariant tests proving that circuit breakers correctly block the intended operations and never block repayments or refund liveness, so that emergency controls are verified.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that each circuit breaker key (PROPOSALS, APPROVALS, DRAWS, GOVERNANCE, ACP_OPS) blocks exactly the operations specified in Requirements 8–12
2. THE Invariant_Test_Suite SHALL verify that repayment calls succeed regardless of any circuit breaker state
3. THE Invariant_Test_Suite SHALL verify that `claimAcpRefund` calls succeed regardless of any circuit breaker state
4. THE Invariant_Test_Suite SHALL verify that circuit breakers are independent: activating one breaker does not affect operations controlled by other breakers
5. FOR ALL combinations of circuit breaker states (2^5 = 32 combinations), THE Invariant_Test_Suite SHALL verify that repayment and refund liveness is preserved

### Requirement 33: Write-Off Accounting Invariant Tests

**User Story:** As a protocol auditor, I want invariant tests proving that write-off accounting is correct for both solo and pooled agreements, so that loss attribution is verified.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that for solo write-offs, the full `writeOffAmount` is attributed to the single lender
2. THE Invariant_Test_Suite SHALL verify that for pooled write-offs, `sum(individual_loss_shares) == writeOffAmount` (complete distribution)
3. THE Invariant_Test_Suite SHALL verify that after write-off, `principalEncumbered == 0` for the written-off agreement
4. THE Invariant_Test_Suite SHALL verify that after write-off, no further repayment distributions occur for the agreement
5. FOR ALL valid write-off scenarios (varying outstanding amounts, collateral recovery, pool configurations), THE Invariant_Test_Suite SHALL verify that write-off accounting is correct

### Requirement 34: Stress Test — High-Volume Agreement Creation

**User Story:** As a protocol operator, I want stress tests proving that the protocol handles high volumes of concurrent agreements without degradation, so that scalability is verified before mainnet.

#### Acceptance Criteria

1. THE Stress_Test_Suite SHALL create at least 100 agreements across all four product types and verify that all accounting invariants hold
2. THE Stress_Test_Suite SHALL execute concurrent draw and repay operations across multiple agreements and verify that no cross-agreement state corruption occurs
3. THE Stress_Test_Suite SHALL measure gas consumption for agreement creation, draw, repay, and close operations and report gas profiles
4. THE Stress_Test_Suite SHALL verify that storage slot access patterns do not cause unexpected gas spikes as agreement count increases

### Requirement 35: Stress Test — Concurrent Metering

**User Story:** As a protocol operator, I want stress tests proving that concurrent compute metering across multiple agreements produces correct accounting, so that metering scalability is verified.

#### Acceptance Criteria

1. THE Stress_Test_Suite SHALL execute concurrent `registerUsage` calls across at least 20 compute agreements with different unit types and verify that each agreement's `principalDrawn` and `unitsEncumbered` are correct
2. THE Stress_Test_Suite SHALL verify that concurrent metering does not cause cross-agreement accounting interference
3. THE Stress_Test_Suite SHALL measure gas consumption for `registerUsage` operations under concurrent load and report gas profiles

### Requirement 36: Stress Test — Default Cascade

**User Story:** As a protocol operator, I want stress tests proving that multiple simultaneous defaults are handled correctly, so that systemic risk scenarios are verified.

#### Acceptance Criteria

1. THE Stress_Test_Suite SHALL trigger delinquency and default on at least 10 agreements simultaneously and verify that each agreement's state machine transitions correctly
2. THE Stress_Test_Suite SHALL execute write-offs on multiple pooled agreements sharing contributors and verify that pro-rata loss distribution is correct across overlapping pools
3. THE Stress_Test_Suite SHALL verify that circuit breakers function correctly during a default cascade scenario

### Requirement 37: Gas Optimization Profiling

**User Story:** As a protocol operator, I want gas profiling for all critical operations, so that gas costs are understood and optimized before mainnet deployment.

#### Acceptance Criteria

1. THE Gas_Profile_Suite SHALL measure and report gas consumption for: proposal creation, agreement activation, draw execution, repayment application, interest accrual, covenant check, delinquency detection, default transition, write-off execution, collateral post/release/seize, ACP job lifecycle (create/setBudget/fund/submit/complete/reject/refund), and circuit breaker toggle
2. THE Gas_Profile_Suite SHALL identify operations exceeding 500,000 gas and flag them for optimization review
3. THE Gas_Profile_Suite SHALL measure gas consumption for the repayment waterfall (fees → interest → principal) with varying numbers of accrued fee/interest components
4. THE Gas_Profile_Suite SHALL measure gas consumption for pooled pro-rata distribution with varying numbers of pool contributors (2, 5, 10, 20)

### Requirement 38: Security Audit Preparation — Access Control Review

**User Story:** As a security auditor, I want a comprehensive access control test suite, so that all privileged operations are verified to enforce correct authorization.

#### Acceptance Criteria

1. THE Security_Test_Suite SHALL verify that every Admin_Role-gated function reverts when called by a non-Admin address
2. THE Security_Test_Suite SHALL verify that every Governance_Timelock-gated function reverts when called by a non-Governance address
3. THE Security_Test_Suite SHALL verify that every borrower-gated function reverts when called by a non-borrower address
4. THE Security_Test_Suite SHALL verify that every lender-gated function reverts when called by a non-lender address
5. THE Security_Test_Suite SHALL verify that circuit breaker toggle functions are restricted to Governance_Timelock only
6. THE Security_Test_Suite SHALL verify that write-off execution is restricted to Governance_Timelock only

### Requirement 39: Security Audit Preparation — Reentrancy Analysis

**User Story:** As a security auditor, I want reentrancy tests for all state-mutating functions that interact with external contracts, so that reentrancy vulnerabilities are identified before audit.

#### Acceptance Criteria

1. THE Security_Test_Suite SHALL verify that all functions calling external ERC-20 `transfer`/`transferFrom` follow the checks-effects-interactions (CEI) pattern
2. THE Security_Test_Suite SHALL verify that all functions calling external adapter contracts (IACP8183Adapter, IERC8004IdentityAdapter, IERC8004ReputationAdapter, IERC8004ValidationAdapter) follow the CEI pattern
3. THE Security_Test_Suite SHALL deploy malicious mock contracts that attempt reentrancy on collateral post/release/seize, ACP job fund/refund, and repayment distribution functions
4. THE Security_Test_Suite SHALL verify that reentrancy guards prevent all tested reentrancy vectors

### Requirement 40: Security Audit Preparation — Storage Collision Checks

**User Story:** As a security auditor, I want storage collision tests for the Diamond proxy architecture, so that facet storage slots do not overlap or corrupt each other.

#### Acceptance Criteria

1. THE Security_Test_Suite SHALL verify that `AGENTIC_STORAGE_POSITION` (`keccak256("equalis.agentic.financing.storage.v1")`) does not collide with any other storage position used by existing Diamond facets
2. THE Security_Test_Suite SHALL verify that adding new facets (AgenticRiskFacet) does not corrupt existing storage values in AgenticStorage
3. THE Security_Test_Suite SHALL verify that Diamond `delegatecall` routing correctly isolates storage access between facets
4. THE Security_Test_Suite SHALL verify that no uninitialized storage slots are read as non-zero values after facet upgrades

### Requirement 41: Security Audit Preparation — Upgrade Safety Verification

**User Story:** As a security auditor, I want upgrade safety tests for the Diamond proxy, so that facet additions and replacements do not break existing functionality.

#### Acceptance Criteria

1. THE Security_Test_Suite SHALL verify that adding the AgenticRiskFacet via `diamondCut` does not affect the behavior of existing facets (AgenticProposalFacet, AgenticApprovalFacet, AgenticAgreementFacet, ComputeUsageFacet, ERC8183Facet, CollateralManagerFacet, CovenantFacet, InterestFacet, PooledFinancingFacet, GovernanceFacet)
2. THE Security_Test_Suite SHALL verify that replacing a facet function selector preserves storage state and does not reset agreement data
3. THE Security_Test_Suite SHALL verify that removing a facet function selector causes calls to that selector to revert cleanly
4. THE Security_Test_Suite SHALL verify that the Diamond proxy's `fallback` function correctly routes calls to the AgenticRiskFacet after registration

### Requirement 42: ERC-8004 Reputation Feedback on Default and Write-Off

**User Story:** As a protocol participant, I want negative reputation feedback to be emitted when agreements default or are written off, so that agent behavior is recorded for future trust decisions.

#### Acceptance Criteria

1. WHEN an agreement transitions to Defaulted, THE AgenticRiskFacet SHALL call `submitReputationFeedback` on the ERC8004Facet with tag1 = `"delinquency"` and a negative score reflecting the default severity
2. WHEN an agreement is written off, THE AgenticRiskFacet SHALL call `submitReputationFeedback` on the ERC8004Facet with tag1 = `"default"` and a negative score reflecting the write-off amount
3. IF the ERC-8004 reputation adapter call fails, THEN THE AgenticRiskFacet SHALL emit a `ReputationFeedbackFailed(agreementId, reason)` event and continue the state transition (reputation feedback is non-blocking)

### Requirement 43: Module Independence Invariant Tests

**User Story:** As a protocol auditor, I want invariant tests proving that financing correctness does not depend on module registry pause/inactive states, so that the canonical no-module-dependency rule is verified.

#### Acceptance Criteria

1. THE Invariant_Test_Suite SHALL verify that all financing state transitions (draw, repay, delinquency, default, write-off, close) succeed regardless of whether any module registry is paused or inactive
2. THE Invariant_Test_Suite SHALL verify that native encumbrance updates occur correctly when module bridges are unavailable or paused
3. THE Invariant_Test_Suite SHALL verify that agreement accounting (principalDrawn, principalRepaid, interestAccrued, feesAccrued) is identical whether module bridges are active or inactive
4. FOR ALL valid financing operation sequences, THE Invariant_Test_Suite SHALL verify that module registry state has no effect on canonical financing outcomes
