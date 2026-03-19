# Implementation Plan: Synthesis Phase 4 — Agentic Financing Advanced Features

## Overview

Incremental build of Phase 4 on-chain facet subsystems and off-chain schedulers:
- ERC-8004 integration (identity, trust gating, reputation, validation)
- ERC-8183 ACP lifecycle + adapter registry
- Reference8183Adapter + MockGeneric8183Adapter
- Collateral management
- Net draw coverage covenant enforcement (payment-vs-net-draw)
- Linear interest + fee schedules
- Pooled financing + governance

All tasks map to `requirements.md` Requirement IDs.

## Tasks

- [ ] 1. ERC-8004 foundation and trust profile wiring
  - [ ] 1.1 Implement ERC-8004 registry config and identity resolution in `ERC8004Facet`
    - Add `setERC8004Registry`, `getERC8004Registry`, `validateIdentity(agentRegistry,agentId)`, `requireIdentity(agentRegistry,agentId)`
    - Implement `resolveAgentWallet` then `resolveOwner` fallback behavior
    - _Requirements: 1, 2_
  - [ ] 1.2 Implement trust profile configuration and gating
    - Wire `TrustMode` config into agreement path
    - Enforce `DiscoveryOnly`, `ReputationOnly`, `ValidationRequired`, `Hybrid`
    - Emit `TrustProfileSet`
    - _Requirements: 3_
  - [ ] 1.3 Implement reputation feedback posting
    - Add outcome-tag mapping (`repayment_quality`, `delinquency`, `default`)
    - Emit `ReputationFeedbackPosted`
    - _Requirements: 4_
  - [ ] 1.4 Implement validation request + record path
    - Add `validationRequest`, `getValidationStatus` integration
    - Emit `ValidationRequested`, `ValidationRecorded`
    - _Requirements: 5_
  - [ ]* 1.5 Write tests for ERC-8004 flows
    - Identity resolution (wallet + owner fallback)
    - Trust gating by all 4 modes
    - Reputation/validation emission and threshold behavior
    - _Requirements: 1-5_

- [x] 2. ACP adapter registry + ERC-8183 core lifecycle
  - [x] 2.1 Implement `AdapterRegistryFacet`
    - `registerVenueAdapter`, `setVenueEnabled`, `setAgreementVenue`, read views
    - Emit `ACPVenueAdapterSet`, `ACPAgreementVenueSet`
    - _Requirements: 6, 7, 8_
  - [x] 2.2 Implement `ERC8183Facet` lifecycle
    - `createAcpJob`, `setAcpProvider`, `setAcpBudget`, `fundAcpJob`, `submitAcpJob`, `completeAcpJob`, `rejectAcpJob`, `claimAcpRefund`
    - Ensure `Rejected` and `Expired` refunds reduce both `principalDrawn` and `principalEncumbered` exactly once
    - Enforce terminal finality and draw freeze checks
    - _Requirements: 9-16_
  - [x]* 2.3 Write tests for ACP lifecycle + finality
    - Completed/Rejected/Expired accounting effects
    - Double-terminal transition reverts
    - Refund liveness path remains callable
    - _Requirements: 9-16_

- [x] 3. Reference and mock portability adapters
  - [x] 3.1 Implement `Reference8183Adapter`
    - Full `IACP8183Adapter` conformance
    - Keep venue target registry-configurable; use local ERC-8183 reference venue for test/dev only
    - CEI + reentrancy guard + strict caller auth
    - _Requirements: 17_
  - [x] 3.2 Implement `MockGeneric8183Adapter`
    - Full interface conformance with deterministic mock state
    - _Requirements: 18_
  - [x]* 3.3 Write differential adapter portability suite
    - Replay identical ACP sequences through Reference8183 + MockGeneric
    - Assert identical core accounting outcomes
    - _Requirements: 17, 18_

- [x] 4. Collateral manager flows
  - [x] 4.1 Implement collateral post/release/seize
    - ERC-20 and native handling where applicable
    - Enforce auth and bound checks
    - Emit collateral events
    - _Requirements: 19, 20, 21_
  - [x] 4.2 Implement collateral toggle and view path
    - `setCollateralRequired`, `getCollateral`
    - Apply canonical defaults for min/maintenance ratios
    - _Requirements: 22, 23_
  - [x]* 4.3 Write collateral tests
    - Conservation and maintenance-threshold enforcement
    - Toggle-off independence behavior
    - _Requirements: 19-23_

- [x] 5. Net draw coverage covenant flows
  - [x] 5.1 Implement covenant parameter config
    - Store `minNetDrawCoverageBps`, `principalFloorPerPeriod`, `covenantCurePeriod`
    - _Requirements: 24_
  - [x] 5.2 Implement `checkCovenant(agreementId, periodId)`
    - Compute `grossDraw_p`, `refunds_p`, `netDraw_p`, `requiredPayment_p`, `actualPayment_p`
    - Return breach status + computed metrics
    - _Requirements: 25_
  - [x] 5.3 Implement breach/cure/termination transitions
    - `detectBreach`, `cureBreach`, `terminateForBreach`
    - Emit `CoverageCovenantBreached`, `CoverageCovenantCured`, `DrawRightsTerminated`
    - _Requirements: 26, 27, 28_
  - [x] 5.4 Implement draw freeze enforcement across draw paths
    - Block `registerUsage`, `createAcpJob`, `fundAcpJob`
    - Keep repayment/refunds callable
    - _Requirements: 29_
  - [x] 5.5 Write covenant enforcement tests
    - Period accounting correctness
    - Breach/cure timing and draw termination behavior
    - _Requirements: 24-29_

- [x] 6. Linear interest and fee schedules
  - [x] 6.1 Implement `setInterestParams(agreementId, annualRateBps)`
    - Linear baseline only
    - _Requirements: 30, 32_
  - [x] 6.2 Implement `accrueInterest` and `pendingInterest`
    - Linear checkpoint accrual
    - No double-accrual at same timestamp
    - _Requirements: 31, 33_
  - [x] 6.3 Implement fee schedule config and accrual interactions
    - Origination/service/late fee behaviors
    - Preserve repayment waterfall ordering
    - _Requirements: 34_
  - [x] 6.4 Implement off-chain `InterestAccrualScheduler`
    - Periodic accrual with retry-on-failure logging
    - _Requirements: 35_
  - [x]* 6.5 Write linear interest + fee tests
    - Deterministic accrual across timestamps
    - Pending-interest consistency
    - _Requirements: 30-35_

- [x] 7. Covenant monitor off-chain service
  - [x] 7.1 Implement `CovenantMonitor`
    - Poll active agreements and evaluate `checkCovenant`
    - Call `detectBreach` or `terminateForBreach` by policy window
    - _Requirements: 36_
  - [x]* 7.2 Write monitor tests
    - Breach detection, cure-period timeout, retry behavior
    - _Requirements: 36_

- [x] 8. Pooled financing and governance
  - [x] 8.1 Implement pooled enable/contribute/withdraw/share query
    - Preserve cap checks and pre-activation constraints
    - _Requirements: 37, 38, 39, 40_
  - [x] 8.2 Implement pooled pro-rata repayment distribution
    - Apply 70/30 split then distribute lender share with deterministic dust handling
    - _Requirements: 41_
  - [x] 8.3 Implement governance proposal/vote/execute/quorum config
    - Snapshot-based weighted voting
    - Quorum + threshold checks
    - _Requirements: 42, 43, 44, 45_
  - [x]* 8.4 Write pooled/governance tests
    - Share conservation, vote weighting, execution guards
    - _Requirements: 37-45_

- [x] 9. Cross-cutting test suites
  - [x]* 9.1 Differential ACP portability tests
    - Reference8183 vs MockGeneric
    - _Requirements: 17, 18_
  - [x]* 9.2 Invariant tests
    - Collateral conservation, interest monotonicity, covenant correctness, draw freeze, pool share conservation, pro-rata correctness
    - _Requirements: 19-41_
  - [x]* 9.3 Integration tests
    - End-to-end trust-gated ACP lifecycle with covenant and repayment behavior
    - _Requirements: 1-45_

- [x] 10. Final checkpoint
  - Verify build and tests pass for Solidity + off-chain scheduler modules.
  - Confirm no-lock-in behavior using at least two ERC-8183 adapter implementations.

## Notes

- Phase 4 uses canonical v1.11 baseline semantics:
  - covenant = payment-vs-net-draw period accounting
  - interest = linear accrual baseline
- Any compound-interest work is post-v1.11 extension scope and must not modify baseline tests.
