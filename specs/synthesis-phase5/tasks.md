# Implementation Plan: Synthesis Phase 5 — Risk, Recovery & Testing

## Overview

Incremental build of the AgenticRiskFacet (delinquency/default/write-off state machine + circuit breakers), LibCircuitBreaker shared library, DelinquencyMonitor off-chain scheduler, and comprehensive test suites (invariant, differential, stress, security). On-chain Solidity code lives in `EqualFi/` (Diamond proxy pattern). Off-chain TypeScript code lives in `mailbox-relayer/src/`. Tests live in `mailbox-relayer/test/` for TypeScript and `EqualFi/test/` for Solidity.

## Tasks

- [x] 1. Core data models and storage extensions
  - [x] 1.1 Extend AgenticStorage with Phase 5 fields
    - Add `mapping(uint256 => uint40) agreementDelinquentAt` for delinquency timestamp tracking
    - Add `mapping(bytes32 => bool) pauseRegistry` for circuit breaker state
    - Add `WriteOffRecord` struct with `writeOffAmount`, `writtenOffAt`, `isPooled` fields
    - Add `mapping(uint256 => WriteOffRecord) writeOffRecords` for per-agreement write-off records
    - Add `mapping(uint256 => mapping(address => uint256)) writeOffLossShares` for per-lender loss attribution
    - Verify no storage collision with existing `AGENTIC_STORAGE_POSITION`
    - _Requirements: 1, 3, 5, 6, 7, 8, 40_

  - [x] 1.2 Define Phase 5 events and custom errors
    - Add events: `AgreementDelinquent`, `AgreementDelinquencyCured`, `AgreementDefaulted`, `AgreementClosed`, `AgreementWrittenOff`, `WriteOffLossAttributed`, `ReputationFeedbackFailed`, `CircuitBreakerToggled`
    - Add custom errors: `InvalidStatusTransition`, `NotDelinquent`, `DelinquencyNotCured`, `CurePeriodNotExpired`, `ObligationsRemaining`, `NotAuthorized`, `CircuitBreakerActive(bytes32)`
    - _Requirements: 1, 2, 3, 4, 5, 8, 42_

- [x] 2. LibCircuitBreaker shared library
  - [x] 2.1 Implement LibCircuitBreaker
    - Create `LibCircuitBreaker.sol` with constant breaker keys: `PROPOSALS_KEY`, `APPROVALS_KEY`, `DRAWS_KEY`, `GOVERNANCE_KEY`, `ACP_OPS_KEY` (each `keccak256` of the string name)
    - Implement `requireNotPaused(bytes32 breakerKey)` internal view function that reads `pauseRegistry` from AgenticStorage and reverts with `CircuitBreakerActive(breakerKey)` if active
    - _Requirements: 8, 9, 10, 11, 12, 13_

  - [x]* 2.2 Write unit tests for LibCircuitBreaker
    - Test `requireNotPaused` reverts when breaker is active
    - Test `requireNotPaused` passes when breaker is inactive
    - Test all 5 breaker key constants match expected `keccak256` values
    - _Requirements: 8, 9, 10, 11, 12_

- [x] 3. Checkpoint — Storage and library compile
  - Verify Solidity compilation succeeds with new storage fields and LibCircuitBreaker. Ask the user if questions arise.

- [x] 4. AgenticRiskFacet — Delinquency detection and cure
  - [x] 4.1 Implement `detectDelinquency(agreementId)`
    - Verify agreement status is Active, revert with `InvalidStatusTransition` otherwise
    - Check three delinquency conditions: (a) `pastDue > 0 && block.timestamp > firstDueAt + gracePeriod`, (b) coverage covenant breach via CovenantFacet `checkCovenant`, (c) `collateralEnabled == true && collateralRatio < maintenanceCollateralRatioBps`
    - Revert with `NotDelinquent` if no condition is met
    - Set `drawFrozen = true`, record `delinquentAt = block.timestamp`, transition status to Delinquent
    - Emit `AgreementDelinquent(agreementId, pastDue)`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

  - [x] 4.2 Implement `cureDelinquency(agreementId)`
    - Verify agreement status is Delinquent, revert with `InvalidStatusTransition` otherwise
    - Verify all shortfalls resolved (pastDue == 0, no covenant breach, no collateral shortfall), revert with `DelinquencyNotCured` if any remain
    - Set `drawFrozen = false` (unless separate covenant breach freeze is still active), clear `delinquentAt`
    - Transition status to Active, emit `AgreementDelinquencyCured(agreementId)`
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x]* 4.3 Write unit tests for delinquency detection and cure
    - Test detection on payment shortfall after grace period
    - Test detection on covenant breach
    - Test detection on collateral shortfall (collateralEnabled = true)
    - Test revert when no delinquency condition met
    - Test revert when agreement not Active
    - Test cure succeeds when all shortfalls resolved
    - Test cure reverts when shortfalls remain
    - Test cure reverts when agreement not Delinquent
    - Test drawFrozen toggling on detect/cure
    - _Requirements: 1, 2_


- [x] 5. AgenticRiskFacet — Default transition and recovery
  - [x] 5.1 Implement `triggerDefault(agreementId)`
    - Verify agreement status is Delinquent, revert with `InvalidStatusTransition` otherwise
    - Verify `block.timestamp - delinquentAt >= covenantCurePeriod`, revert with `CurePeriodNotExpired` otherwise
    - Set `drawTerminated = true` permanently, transition status to Defaulted
    - Apply penalty schedule: add `liquidationPenaltyBps * outstandingPrincipal / 10000` to `feesAccrued`
    - Emit `AgreementDefaulted(agreementId, pastDue)`
    - Call `submitReputationFeedback` on ERC8004Facet with tag1 = `"delinquency"` and negative score (non-blocking: catch failure, emit `ReputationFeedbackFailed`)
    - _Requirements: 3.1, 3.2, 3.3, 3.6, 3.7, 42.1, 42.3_

  - [x] 5.2 Implement `closeRecoveredAgreement(agreementId)`
    - Verify agreement status is Defaulted, revert with `InvalidStatusTransition` otherwise
    - Verify all outstanding obligations (principal + interest + fees) are fully satisfied, revert with `ObligationsRemaining` otherwise
    - Transition status to Closed, emit `AgreementClosed(agreementId)`
    - _Requirements: 4.2, 4.3, 4.4_

  - [x]* 5.3 Write unit tests for default transition and recovery
    - Test default triggers after cure period expires
    - Test default reverts before cure period expires
    - Test default reverts when not Delinquent
    - Test penalty fee application on default
    - Test `drawTerminated` is set permanently
    - Test repayments still accepted on Defaulted agreement
    - Test `claimAcpRefund` still callable on Defaulted agreement
    - Test collateral seizure allowed on Defaulted agreement with collateralEnabled
    - Test close recovered agreement succeeds on full recovery
    - Test close recovered agreement reverts with obligations remaining
    - Test reputation feedback emission on default (success and failure paths)
    - _Requirements: 3, 4, 42_

  - [x]* 5.4 Write property test for delinquency state machine transitions
    - **Property P5-1: Delinquency state machine transition correctness**
    - Fuzz all status × function combinations, verify only canonical transitions succeed (Active→Delinquent, Delinquent→Active, Delinquent→Defaulted, Defaulted→Closed, Defaulted→WrittenOff, Active→Closed)
    - Verify WrittenOff and Closed are terminal — no outbound transitions
    - **Validates: Requirements 1, 2, 3, 4, 5, 31**

  - [x]* 5.5 Write property test for delinquency detection completeness
    - **Property P5-2: Delinquency detection completeness**
    - Fuzz pastDue, covenant state, collateral ratios — verify detection iff at least one condition met
    - **Validates: Requirements 1, 2, 3**

  - [x]* 5.6 Write property test for draw freeze vs termination
    - **Property P5-3: Draw freeze reversibility vs. termination permanence**
    - Fuzz delinquency/cure/default sequences — verify freeze is reversible, termination is permanent
    - **Validates: Requirements 1, 2, 3, 21, 31**

  - [x]* 5.7 Write property test for cure period timing
    - **Property P5-4: Cure period timing boundary**
    - Fuzz timestamps and cure periods — verify `triggerDefault` reverts before boundary, succeeds at/after boundary
    - **Validates: Requirements 2, 3, 22**

  - [x]* 5.8 Write property test for penalty schedule correctness
    - **Property P5-20: Penalty schedule correctness**
    - Fuzz outstanding principal and liquidationPenaltyBps — verify penalty = `bps * principal / 10000` applied exactly once
    - **Validates: Requirements 3**

- [x] 6. Checkpoint — State machine compile and unit tests
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. AgenticRiskFacet — Write-off execution and accounting
  - [x] 7.1 Implement `writeOff(agreementId)`
    - Verify caller is `Governance_Timelock`, revert with `NotAuthorized` otherwise
    - Verify agreement status is Defaulted, revert with `InvalidStatusTransition` otherwise
    - Compute `writeOffAmount = principalDrawn - principalRepaid + interestAccrued + feesAccrued - cumulativePayments - collateralSeized`
    - Set `principalEncumbered = 0`, emit `NativeEncumbranceUpdated` with reason `keccak256("WRITE_OFF")`
    - Transition status to WrittenOff, emit `AgreementWrittenOff(agreementId, writeOffAmount)`
    - Call `submitReputationFeedback` on ERC8004Facet with tag1 = `"default"` and negative score (non-blocking)
    - Delegate to solo or pooled write-off accounting based on agreement product type
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 42.2, 42.3_

  - [x] 7.2 Implement solo write-off accounting
    - Attribute full `writeOffAmount` to single lender from agreement's `lenderPositionKey`
    - Emit `WriteOffLossAttributed(agreementId, lenderAddress, writeOffAmount)`
    - Reduce lender's position value by `writeOffAmount` via native encumbrance update
    - Prevent further repayment distribution to the written-off agreement
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x] 7.3 Implement pooled write-off accounting
    - Query pool shares from PooledFinancingFacet
    - Compute each contributor's loss share: `floor(writeOffAmount * lenderPoolShare / totalPooled)`
    - Assign rounding remainder (dust) to the largest pool contributor
    - Emit `WriteOffLossAttributed(agreementId, lenderAddress, lossShare)` for each contributor
    - Reduce each contributor's pool share value by their computed loss share
    - Prevent further repayment distribution to the written-off agreement
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x]* 7.4 Write unit tests for write-off execution
    - Test governance-only authorization (non-governance caller reverts)
    - Test writeOffAmount computation correctness
    - Test principalEncumbered zeroed after write-off
    - Test solo write-off full attribution to single lender
    - Test pooled write-off pro-rata distribution with dust handling
    - Test reputation feedback on write-off (success and failure paths)
    - Test revert when not Defaulted
    - Test no further repayment distribution after write-off
    - _Requirements: 5, 6, 7, 42_

  - [x]* 7.5 Write property test for write-off amount computation
    - **Property P5-5: Write-off amount computation correctness**
    - Fuzz principal/interest/fees/payments/collateral — verify formula correctness
    - **Validates: Requirements 5**

  - [x]* 7.6 Write property test for solo write-off attribution
    - **Property P5-6: Solo write-off full attribution**
    - Fuzz solo agreements — verify full writeOffAmount attributed to single lender, exactly one event emitted
    - **Validates: Requirements 6**

  - [x]* 7.7 Write property test for pooled write-off conservation
    - **Property P5-7: Pooled write-off pro-rata conservation**
    - Fuzz pool configurations and write-off amounts — verify `sum(individual_shares) == writeOffAmount`, dust to largest contributor
    - **Validates: Requirements 7, 24**

  - [x]* 7.8 Write property test for default recovery completeness
    - **Property P5-24: Default recovery completeness**
    - Fuzz repayment and collateral recovery amounts — verify `closeRecoveredAgreement` succeeds iff all obligations met
    - **Validates: Requirements 4**

  - [x]* 7.9 Write property test for governance-only write-off authorization
    - **Property P5-21: Governance-only write-off authorization**
    - Fuzz caller addresses — verify only Governance_Timelock succeeds
    - **Validates: Requirements 5, 38**

  - [x]* 7.10 Write property test for reputation feedback non-blocking
    - **Property P5-22: Reputation feedback non-blocking semantics**
    - Deploy mock ERC8004Facet that reverts — verify state transitions complete regardless
    - **Validates: Requirements 42**

- [x] 8. Checkpoint — Write-off accounting compile and tests
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. AgenticRiskFacet — Circuit breakers
  - [x] 9.1 Implement `setCircuitBreaker(breakerKey, enabled)`
    - Verify caller is `Governance_Timelock`, revert with `NotAuthorized` otherwise
    - Store `pauseRegistry[breakerKey] = enabled`
    - Emit `CircuitBreakerToggled(breakerKey, enabled, msg.sender)`
    - _Requirements: 8.1, 8.3, 8.4, 8.5, 9.1, 9.4, 10.1, 11.1, 12.1_

  - [x] 9.2 Implement `getCircuitBreaker` and `getAllCircuitBreakers` view functions
    - `getCircuitBreaker(breakerKey)` returns `pauseRegistry[breakerKey]`
    - `getAllCircuitBreakers()` returns tuple of all 5 breaker states (proposals, approvals, draws, governance, acpOps)
    - _Requirements: 14.1, 14.2_

  - [x] 9.3 Integrate circuit breaker checks into existing facets
    - Add `LibCircuitBreaker.requireNotPaused(PROPOSALS_KEY)` guard to `AgenticProposalFacet.createProposal`
    - Add `LibCircuitBreaker.requireNotPaused(APPROVALS_KEY)` guard to `AgenticApprovalFacet` approve/activate functions
    - Add `LibCircuitBreaker.requireNotPaused(DRAWS_KEY)` guard to `AgenticAgreementFacet.draw`, `ComputeUsageFacet.registerUsage`, `ERC8183Facet.createAcpJob`, `ERC8183Facet.setAcpBudget`, `ERC8183Facet.fundAcpJob`
    - Add `LibCircuitBreaker.requireNotPaused(GOVERNANCE_KEY)` guard to `GovernanceFacet.executeProposal`
    - Add `LibCircuitBreaker.requireNotPaused(ACP_OPS_KEY)` guard to `ERC8183Facet.createAcpJob`, `ERC8183Facet.setAcpBudget`, `ERC8183Facet.fundAcpJob`
    - Ensure `claimAcpRefund` has NO circuit breaker check (refund liveness non-pausable)
    - Ensure repayment functions have NO circuit breaker check
    - _Requirements: 8.2, 9.2, 9.3, 10.2, 10.3, 10.4, 10.5, 11.2, 11.3, 12.2, 12.3, 13.1, 13.2, 13.3_

  - [x]* 9.4 Write unit tests for circuit breakers
    - Test governance-only toggle authorization
    - Test each breaker key blocks its specified operations
    - Test each breaker key does NOT block unrelated operations
    - Test `claimAcpRefund` bypasses all breakers
    - Test repayment bypasses all breakers
    - Test `getAllCircuitBreakers` returns correct state
    - Test `CircuitBreakerToggled` event emission
    - _Requirements: 8, 9, 10, 11, 12, 13, 14_

  - [x]* 9.5 Write property test for circuit breaker isolation
    - **Property P5-8: Circuit breaker isolation and independence**
    - Enumerate all 32 breaker combinations (2^5) — verify operation blocking matrix matches spec
    - **Validates: Requirements 8, 9, 10, 11, 12, 32**

  - [x]* 9.6 Write property test for refund liveness non-pausability
    - **Property P5-9: Refund liveness non-pausability**
    - Fuzz all breaker state combinations — verify `claimAcpRefund` always succeeds
    - **Validates: Requirements 13**

  - [x]* 9.7 Write property test for repayment liveness
    - **Property P5-10: Repayment liveness under all pause states**
    - Fuzz all breaker state combinations — verify repayment always succeeds
    - **Validates: Requirements 3, 10, 32**

  - [x]* 9.8 Write property test for circuit breaker governance authorization
    - **Property P5-25: Circuit breaker governance authorization**
    - Fuzz caller addresses — verify only Governance_Timelock can toggle breakers
    - **Validates: Requirements 8, 9, 10, 11, 12, 38**

- [x] 10. Checkpoint — Circuit breakers compile and tests
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. DelinquencyMonitor off-chain scheduler
  - [x] 11.1 Implement DelinquencyMonitor class
    - Create `mailbox-relayer/src/schedulers/DelinquencyMonitor.ts`
    - Implement constructor with `provider`, `signer`, `riskFacetAddress`, `agreementFacetAddress`, `intervalMs` (default 900000), `onError` callback
    - Implement `start()` / `stop()` / `status()` lifecycle methods (same pattern as InterestAccrualScheduler and CovenantMonitor)
    - Implement `runCycle()` with `isRunning` guard:
      - Phase 1: Query all Active agreements, call `detectDelinquency` for each (catch `NotDelinquent`/`InvalidStatusTransition`)
      - Phase 2: Query all Delinquent agreements, call `triggerDefault` for each (catch `CurePeriodNotExpired`)
    - Log errors and retry on next cycle
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5_

  - [x]* 11.2 Write unit tests for DelinquencyMonitor
    - Test start/stop lifecycle
    - Test `isRunning` guard prevents concurrent cycles
    - Test detection phase calls `detectDelinquency` for Active agreements
    - Test default phase calls `triggerDefault` for Delinquent agreements
    - Test error handling: failed tx logged, monitor continues
    - Test configurable interval
    - _Requirements: 15_

  - [x]* 11.3 Write property test for delinquency monitor liveness
    - **Property P5-26: Delinquency monitor liveness**
    - Verify `isRunning` guard prevents concurrent cycles, failed txs don't halt monitor
    - **Validates: Requirements 15**

- [x] 12. Checkpoint — Off-chain scheduler compile and tests
  - Ensure all tests pass, ask the user if questions arise.

- [x] 13. Invariant test suite — Encumbrance and cross-product accounting
  - [x]* 13.1 Write property test for encumbrance conservation through write-off
    - **Property P5-11: Encumbrance conservation through write-off**
    - Fuzz draw/repay/refund/write-off sequences — verify `principalEncumbered = principalDrawn - principalRepaid` holds after every operation
    - Verify `principalEncumbered = 0` after write-off, never negative
    - Create test file `test/invariant/encumbrance-conservation.test.ts`
    - **Validates: Requirements 5, 17**

  - [x]* 13.2 Write property test for cross-product accounting equivalence
    - **Property P5-12: Cross-product accounting equivalence**
    - Fuzz equivalent inputs across SoloAgentic, PooledAgentic, SoloCompute, PooledCompute — verify identical repayment waterfall (fees → interest → principal) and 70/30 fee split
    - Create test file `test/invariant/cross-product-accounting.test.ts`
    - **Validates: Requirements 16**

  - [x]* 13.3 Write invariant tests for native encumbrance conservation (Req 17)
    - Verify `principalEncumbered` increases by drawn amount on draw
    - Verify `principalEncumbered` decreases by principal portion on repay
    - Verify `principalEncumbered` decreases by refunded amount on ACP refund
    - Verify `principalEncumbered` is zero after write-off
    - Verify `principalEncumbered` is never negative
    - Verify round-trip conservation: `principalEncumbered = principalDrawn - principalRepaid`
    - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5, 17.6_

- [x] 14. Invariant test suite — P4 invariant preservation
  - [x]* 14.1 Write invariant tests for collateral conservation (P4-1)
    - Verify `collateralPosted` only changes via post/release/seize
    - Verify `collateralSeized <= collateralPosted` at all times
    - Verify `collateralPosted - collateralSeized` equals actual balance
    - Verify total collateral conservation across all operations
    - Create test file `test/invariant/p4-invariant-preservation.test.ts`
    - _Requirements: 18.1, 18.2, 18.3, 18.4_

  - [x]* 14.2 Write invariant tests for interest monotonicity (P4-2)
    - Verify `interestAccrued` is monotonically non-decreasing
    - Verify positive increase when `principalDrawn > 0` and time elapsed
    - Verify unchanged when `principalDrawn = 0`
    - _Requirements: 19.1, 19.2, 19.3, 19.4_

  - [x]* 14.3 Write invariant tests for covenant breach detection correctness (P4-3)
    - Verify `checkCovenant` computes `requiredPayment_p` deterministically and returns `breached = true` iff `actualPayment_p < requiredPayment_p`
    - Verify `breached = false` when `principalDrawn = 0`
    - Verify `detectBreach` sets `drawFrozen = true` iff breach detected
    - _Requirements: 20.1, 20.2, 20.3, 20.4_

  - [x]* 14.4 Write invariant tests for draw freeze enforcement (P4-4)
    - Verify all draw-path functions revert when `drawFrozen = true` or `drawTerminated = true`
    - Verify repayment functions remain callable when frozen/terminated
    - Verify `claimAcpRefund` remains callable when frozen/terminated
    - Verify `principalDrawn` does not increase when `drawFrozen = true`
    - _Requirements: 21.1, 21.2, 21.3, 21.4, 21.5_

  - [x]* 14.5 Write invariant tests for cure period timing (P4-5)
    - Verify `triggerDefault` reverts when `block.timestamp - delinquentAt < covenantCurePeriod`
    - Verify `triggerDefault` succeeds when `>= covenantCurePeriod`
    - Verify `cureDelinquency` succeeds at any point during cure period when shortfalls resolved
    - Verify `covenantCurePeriod` bounded between 3 and 30 days
    - _Requirements: 22.1, 22.2, 22.3, 22.4, 22.5_

  - [x]* 14.6 Write invariant tests for pool share conservation (P4-6)
    - Verify sum of all pool shares equals total pooled amount
    - Verify shares only increase via contribute, decrease via withdraw or write-off
    - Verify proportional shares sum to 10000 bps across all contributors
    - _Requirements: 23.1, 23.2, 23.3, 23.4_

  - [x]* 14.7 Write invariant tests for pro-rata distribution correctness (P4-7)
    - Verify sum of individual pro-rata distributions equals total distribution amount
    - Verify each contributor receives proportional share within 1 wei tolerance
    - Verify rounding dust assigned to largest contributor
    - _Requirements: 24.1, 24.2, 24.3, 24.4_

  - [x]* 14.8 Write property test for P4 invariant preservation under Phase 5 operations
    - **Property P5-13: P4 invariant preservation (P4-1 through P4-7)**
    - Fuzz Phase 5 operations (delinquency, default, write-off, circuit breaker toggles) — verify all P4 invariants still hold
    - **Validates: Requirements 18, 19, 20, 21, 22, 23, 24**

- [x] 15. Invariant test suite — ACP, trust mode, collateral toggle, position transfer, module independence
  - [x]* 15.1 Write invariant tests for ACP terminal-state accounting synchronization
    - **Property P5-14: ACP terminal state accounting synchronization**
    - Verify Completed job leaves `principalDrawn` unchanged
    - Verify Rejected/Expired job reduces `principalDrawn` by refunded amount
    - Verify terminal finality (no double transitions)
    - Verify accounting adjustments applied exactly once
    - Create test file `test/invariant/acp-terminal-sync.test.ts`
    - _Requirements: 25.1, 25.2, 25.3, 25.4, 25.5, 25.6_

  - [x]* 15.2 Write invariant tests for trust-mode gating enforcement
    - **Property P5-15: Trust mode gating determinism**
    - Verify DiscoveryOnly allows activation unconditionally
    - Verify ReputationOnly reverts below `minReputationValue`
    - Verify ValidationRequired reverts below `minValidationResponse`
    - Verify Hybrid requires both thresholds
    - Verify determinism: same inputs → same gating decision
    - _Requirements: 26.1, 26.2, 26.3, 26.4, 26.5_

  - [x]* 15.3 Write invariant tests for collateral toggle independence
    - **Property P5-16: Collateral toggle independence**
    - Verify `collateralEnabled = false` agreements activate without collateral, `postCollateral` reverts
    - Verify `collateralEnabled = true` agreements enforce `minCollateralRatioBps` at activation
    - Verify collateral shortfall delinquency only triggered when enabled
    - _Requirements: 27.1, 27.2, 27.3, 27.4, 27.5_

  - [x]* 15.4 Write invariant tests for position transfer continuity
    - **Property P5-17: Position transfer continuity**
    - Verify accounting fields unchanged after position NFT transfer
    - Verify new holder can execute authorized operations
    - Verify encumbrance conservation holds across transfers
    - _Requirements: 28.1, 28.2, 28.3_

  - [x]* 15.5 Write invariant tests for module independence
    - **Property P5-23: Module independence**
    - Fuzz module registry states (paused/inactive) — verify financing operations succeed regardless
    - Verify native encumbrance updates occur correctly when module bridges unavailable
    - Verify agreement accounting identical whether module bridges active or inactive
    - Create test file `test/invariant/module-independence.test.ts`
    - _Requirements: 43.1, 43.2, 43.3, 43.4_

  - [x]* 15.6 Write invariant tests for state machine transitions (Req 31)
    - Verify only canonical transitions succeed (Active→Delinquent, Delinquent→Active, Delinquent→Defaulted, Defaulted→Closed, Defaulted→WrittenOff, Active→Closed)
    - Verify WrittenOff and Closed are terminal
    - Verify `drawTerminated` set on every Defaulted transition, never reset
    - Create test file `test/invariant/state-machine-transitions.test.ts`
    - _Requirements: 31.1, 31.2, 31.3, 31.4, 31.5_

  - [x]* 15.7 Write invariant tests for circuit breaker correctness (Req 32)
    - Verify each breaker blocks exactly its specified operations
    - Verify repayment and `claimAcpRefund` succeed under all 32 breaker combinations
    - Verify breaker independence
    - Create test file `test/circuit-breakers/breaker-isolation.test.ts`
    - _Requirements: 32.1, 32.2, 32.3, 32.4, 32.5_

  - [x]* 15.8 Write invariant tests for write-off accounting (Req 33)
    - Verify solo write-off full attribution
    - Verify pooled write-off `sum(shares) == writeOffAmount`
    - Verify `principalEncumbered == 0` after write-off
    - Verify no further repayment distribution after write-off
    - _Requirements: 33.1, 33.2, 33.3, 33.4, 33.5_

- [x] 16. Checkpoint — Invariant test suite
  - Ensure all invariant tests pass, ask the user if questions arise.

- [x] 17. Differential portability tests
  - [x]* 17.1 Write differential test for ERC-8183 adapter portability
    - **Property P5-18: Differential ERC-8183 adapter portability**
    - Replay identical ACP job lifecycle sequences (create→fund→submit→complete, create→fund→submit→reject, create→fund→expire→claimRefund) through Reference8183Adapter and MockGeneric8183Adapter
    - Assert `principalDrawn`, `principalRepaid`, `principalEncumbered`, `interestAccrued`, `feesAccrued` identical after each lifecycle
    - Assert terminal state accounting (refund amounts) identical across adapters
    - At least 3 distinct lifecycle sequences per adapter pair
    - Create test file `test/differential/erc8183-adapter-portability.test.ts`
    - **Validates: Requirements 29.1, 29.2, 29.3, 29.4, 29.5**

  - [x]* 17.2 Write differential test for compute adapter portability
    - **Property P5-19: Differential compute adapter portability**
    - Replay identical compute usage sequences (register usage, accrue interest, repay) through at least one API-inference adapter pair (Venice + Lambda, Bankr + Lambda, Venice + RunPod, or Bankr + RunPod)
    - Assert `principalDrawn`, `unitsEncumbered`, `interestAccrued`, `feesAccrued` identical after each sequence
    - Assert monetary liability computation (`usedUnits * unitPrice`) identical across adapters
    - Include at least one API-based inference adapter (Venice or Bankr) in comparison
    - Create test file `test/differential/compute-adapter-portability.test.ts`
    - **Validates: Requirements 30.1, 30.2, 30.3, 30.4, 30.5**

  - [x]* 17.3 Write differential test for solo vs pooled accounting
    - Same inputs through solo and pooled paths — assert identical totals (distribution differs)
    - Create test file `test/differential/solo-vs-pooled.test.ts`
    - **Validates: Requirements 16**

- [x] 18. Stress tests and gas profiling
  - [x]* 18.1 Write stress test for high-volume agreement creation
    - Create 100+ agreements across all four product types
    - Execute concurrent draw and repay operations across multiple agreements
    - Verify all accounting invariants hold under load
    - Verify no cross-agreement state corruption
    - Measure gas consumption for creation, draw, repay, close
    - Verify no unexpected gas spikes as agreement count increases
    - Create test file `test/stress/high-volume-agreements.test.ts`
    - _Requirements: 34.1, 34.2, 34.3, 34.4_

  - [x]* 18.2 Write stress test for concurrent metering
    - Execute concurrent `registerUsage` calls across 20+ compute agreements with different unit types
    - Verify each agreement's `principalDrawn` and `unitsEncumbered` are correct
    - Verify no cross-agreement accounting interference
    - Measure gas consumption under concurrent load
    - Create test file `test/stress/concurrent-metering.test.ts`
    - _Requirements: 35.1, 35.2, 35.3_

  - [x]* 18.3 Write stress test for default cascade
    - Trigger delinquency and default on 10+ agreements simultaneously
    - Execute write-offs on multiple pooled agreements sharing contributors
    - Verify pro-rata loss distribution correct across overlapping pools
    - Verify circuit breakers function correctly during cascade
    - Create test file `test/stress/default-cascade.test.ts`
    - _Requirements: 36.1, 36.2, 36.3_

  - [x]* 18.4 Write gas profiling suite
    - Measure gas for all critical operations: proposal creation, activation, draw, repay, interest accrual, covenant check, delinquency detection, default transition, write-off, collateral post/release/seize, ACP lifecycle, circuit breaker toggle
    - Flag operations exceeding 500,000 gas
    - Profile repayment waterfall with varying fee/interest components
    - Profile pooled pro-rata distribution with 2, 5, 10, 20 contributors
    - Create test file `test/stress/gas-profiling.test.ts`
    - _Requirements: 37.1, 37.2, 37.3, 37.4_

- [x] 19. Security audit preparation tests
  - [x]* 19.1 Write access control test suite
    - Verify every Admin_Role-gated function reverts for non-Admin
    - Verify every Governance_Timelock-gated function reverts for non-Governance
    - Verify every borrower-gated function reverts for non-borrower
    - Verify every lender-gated function reverts for non-lender
    - Verify circuit breaker toggle restricted to Governance_Timelock
    - Verify write-off restricted to Governance_Timelock
    - Create test file `test/security/access-control.test.ts`
    - _Requirements: 38.1, 38.2, 38.3, 38.4, 38.5, 38.6_

  - [x]* 19.2 Write reentrancy test suite
    - Verify CEI pattern on all functions calling external ERC-20 transfer/transferFrom
    - Verify CEI pattern on all functions calling external adapter contracts
    - Deploy malicious mock contracts attempting reentrancy on collateral post/release/seize, ACP fund/refund, repayment distribution
    - Verify reentrancy guards prevent all tested vectors
    - Create test file `test/security/reentrancy.test.ts`
    - _Requirements: 39.1, 39.2, 39.3, 39.4_

  - [x]* 19.3 Write storage collision test suite
    - Verify `AGENTIC_STORAGE_POSITION` uniqueness across all Diamond facets
    - Verify adding AgenticRiskFacet does not corrupt existing storage values
    - Verify `delegatecall` routing correctly isolates storage between facets
    - Verify no uninitialized storage slots read as non-zero after facet upgrades
    - Create test file `test/security/storage-collision.test.ts`
    - _Requirements: 40.1, 40.2, 40.3, 40.4_

  - [x]* 19.4 Write upgrade safety test suite
    - Verify `diamondCut` addition of AgenticRiskFacet preserves all existing facet behavior
    - Verify selector replacement preserves storage state
    - Verify selector removal causes clean revert
    - Verify Diamond `fallback` correctly routes to AgenticRiskFacet after registration
    - Create test file `test/security/upgrade-safety.test.ts`
    - _Requirements: 41.1, 41.2, 41.3, 41.4_

- [x] 20. Final checkpoint — Full build and test suite
  - Verify all Solidity compilation succeeds, all TypeScript builds cleanly, and all test suites pass (unit, invariant, differential, stress, security). Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional test tasks — can be deferred for faster MVP but should be completed before security audit
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major component
- Phase 5 is additive — no modifications to Phase 1–4 facets or storage layouts are required
- AgenticRiskFacet is the only new Diamond facet; LibCircuitBreaker is a shared library used by existing facets via `requireNotPaused`
- DelinquencyMonitor follows the same scheduler pattern as InterestAccrualScheduler and CovenantMonitor from Phase 4
- Circuit breaker integration (task 9.3) adds `requireNotPaused` guards to existing facets — these are minimal one-line additions
- Invariant tests use property-based testing (fuzz) with randomized inputs to exercise correctness properties P5-1 through P5-26
- Differential tests use mocked adapters with synthetic traces — no live API calls in CI
- Stress tests may require longer timeouts; gas profiling tests report metrics but do not fail on thresholds (informational)
- Security tests deploy malicious mock contracts for reentrancy testing — these are test-only artifacts
- All 26 correctness properties (P5-1 through P5-26) are covered by at least one task
- All 43 requirements are covered by at least one task
