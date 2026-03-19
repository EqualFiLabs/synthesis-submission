# Implementation Plan: Synthesis Phase 1 — Agentic Financing Contracts

## Overview

Incremental build of the on-chain Equalis Agentic Financing protocol as additive EIP-2535 Diamond facets inside the existing `EqualFi/` Foundry codebase. Tasks follow a bottom-up order: shared types and storage first, then facets by dependency order, then integration wiring and final tests.
Fast-track profile: prioritize shipping the demo path with strong unit coverage; broad property/invariant depth is explicitly deferred to Phase 5.

## Tasks

- [x] 1. EqualFi integration baseline and shared types
  - [x] 1.1 Align with existing EqualFi repository layout (no greenfield scaffolding)
    - Reuse existing `EqualFi/foundry.toml` and `EqualFi/remappings.txt` (do not create new project-level Foundry config)
    - Add agentic feature directories inside existing repo layout: `EqualFi/src/agentic/`, `EqualFi/src/agentic/types/`, `EqualFi/test/agentic/`
    - Reuse existing protocol libraries (`LibEncumbrance`, `LibFeeRouter`, `LibPositionNFT`) directly; do not introduce stubs
    - For Agentic financing encumbrance mutations, use native `LibEncumbrance.position(positionKey, poolId).directLent`; do not use `LibModuleEncumbrance` or `LibIndexEncumbrance`
    - _Requirements: 1.1_

  - [x] 1.2 Define enums, structs, constants, custom errors, and events
    - Create `EqualFi/src/agentic/types/AgenticTypes.sol` with all enums (`ProposalType`, `ProposalStatus`, `AgreementMode`, `AgreementStatus`), structs (`FinancingProposal`, `FinancingAgreement`, `ComputeUnitConfig`, `UsageEntry`), constants (`UNIT_SCALE`, `FEE_BPS_LENDER`, `FEE_BPS_TOTAL`, `AGENTIC_ENCUMBRANCE_NAMESPACE` as logical Agentic identifier, reason constants), and all custom errors from the design
    - Create `EqualFi/src/agentic/types/AgenticEvents.sol` with all event declarations matching canonical v1.11 relayer schema: `ProposalCreated`, `ProposalApproved`, `ProposalRejected`, `AgreementActivated(agreementId, proposalId, mode)`, `AgreementClosed(agreementId)`, `AgentEncPubRegistered`, `BorrowerPayloadPublished(agreementId, borrower, envelope)`, `ProviderPayloadPublished(agreementId, provider, envelope)`, `DrawExecuted`, `RepaymentApplied`, `NativeEncumbranceUpdated`
    - _Requirements: 19.1, 19.2, 19.3, 19.4, 19.5, 19.6, 19.7, 19.8, 19.9_

  - [x] 1.3 Implement LibAgenticStorage and AgenticStorage struct
    - Create `EqualFi/src/libraries/LibAgenticStorage.sol` with the `STORAGE_POSITION` constant (`keccak256("equalis.agentic.financing.storage.v1")`) and the `store()` internal pure function using assembly slot assignment
    - Define the full `AgenticStorage` struct with all mappings from the design: proposals, agreements, index mappings, compute units, mailbox payloads, encPubKeys, relayerRole, encumbrance tracking, reentrancyLock, and ID counters
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 1.4 Create facet interface files
    - Create `EqualFi/src/interfaces/IAgenticProposalFacet.sol`, `EqualFi/src/interfaces/IAgenticApprovalFacet.sol`, `EqualFi/src/interfaces/IAgenticAgreementFacet.sol`, `EqualFi/src/interfaces/IAgenticMailboxFacet.sol`, `EqualFi/src/interfaces/IComputeUsageFacet.sol`, `EqualFi/src/interfaces/IAgentEncPubRegistryFacet.sol` with the exact function signatures from the design
    - _Requirements: 17.1, 17.2, 17.3, 17.4, 18.1, 18.2, 10.1, 10.2, 10.3_

- [x] 2. Checkpoint — Compile shared types
  - Ensure `cd EqualFi && forge test --match-path 'test/agentic/*t.sol'` compiles new types, libraries, interfaces, and baseline tests without errors. Ask the user if questions arise.

- [x] 3. AgenticProposalFacet — Proposal CRUD
  - [x] 3.1 Implement `createProposal`
    - Create `EqualFi/src/agentic/AgenticProposalFacet.sol`
    - Validate all inputs: `expiresAt > block.timestamp`, `requestedAmount > 0`, `requestedUnits > 0`, `settlementAsset != address(0)`, `counterparty != address(0)`
    - Assign sequential `proposalId` from `nextProposalId`, increment counter
    - Store `FinancingProposal` with status `Pending`, `creator = msg.sender`, `createdAt = uint40(block.timestamp)`
    - Append `proposalId` to `agentToProposals[agentId]` and `lenderToProposals[counterparty]`
    - Emit `ProposalCreated(proposalId, ProposalType.SoloCompute, agentId)`
    - Revert with descriptive custom errors on validation failure
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 21.1, 21.2, 21.4_

  - [x] 3.2 Implement `cancelProposal`
    - Validate `proposalId` exists, status is `Pending`, caller is `proposal.creator`
    - Transition status to `Cancelled`
    - _Requirements: 3.1, 3.2, 3.3, 21.3_

  - [x] 3.3 Implement view functions (`getProposal`, `getProposalsByAgent`, `getProposalsByLender`)
    - `getProposal` returns full `FinancingProposal` struct, reverts if ID not found
    - `getProposalsByAgent` returns `agentToProposals[agentId]`
    - `getProposalsByLender` returns `lenderToProposals[lender]`
    - _Requirements: 18.1, 18.2, 17.3, 21.3_

  - [x] 3.4 Write unit tests for AgenticProposalFacet
    - Test successful proposal creation with known parameters and verify all stored fields
    - Test all validation reverts: zero amount, zero units, zero address, expired timestamp
    - Test cancel by creator succeeds, cancel by non-creator reverts, cancel non-pending reverts
    - Test view functions return correct data, non-existent ID reverts
    - Test event emission with exact parameters
    - _Requirements: 2.1–2.9, 3.1–3.3, 18.1, 18.2_

  - [x]* 3.5 Write property test: Proposal creation produces valid pending proposal (Property 1)
    - **Property 1: Proposal creation produces valid pending proposal with sequential ID**
    - Fuzz all valid input combinations, verify status is `Pending`, ID is sequential, proposal is retrievable, ID appears in both index arrays
    - **Validates: Requirements 2.1, 2.7, 2.8**

  - [x]* 3.6 Write property test: Proposal cancellation by creator (Property 4)
    - **Property 4: Proposal cancellation by creator transitions status**
    - Fuzz creator vs non-creator callers, pending vs non-pending states
    - **Validates: Requirements 3.1, 3.2, 3.3**

- [x] 4. AgenticApprovalFacet — Lender approval and rejection
  - [x] 4.1 Implement `approveProposal`
    - Create `EqualFi/src/agentic/AgenticApprovalFacet.sol`
    - Validate `proposalId` exists, status is `Pending`, caller is `proposal.counterparty`, `block.timestamp < expiresAt`
    - Transition status to `Approved`
    - Emit `ProposalApproved(proposalId, msg.sender)`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 21.3_

  - [x] 4.2 Implement `rejectProposal`
    - Validate `proposalId` exists, status is `Pending`, caller is `proposal.counterparty`
    - Transition status to `Rejected`
    - Emit `ProposalRejected(proposalId, msg.sender)`
    - _Requirements: 5.1, 5.2, 5.3, 21.3_

  - [x] 4.3 Write unit tests for AgenticApprovalFacet
    - Test approve by counterparty succeeds, non-counterparty reverts, non-pending reverts, expired reverts
    - Test reject by counterparty succeeds, non-counterparty reverts
    - Test event emissions
    - _Requirements: 4.1–4.5, 5.1–5.3_

  - [x]* 4.4 Write property test: Proposal approval transitions status (Property 2)
    - **Property 2: Proposal approval transitions status and emits event**
    - Fuzz valid pending proposals with correct counterparty and non-expired timestamp
    - **Validates: Requirements 4.1, 4.2**

  - [x]* 4.5 Write property test: Proposal rejection transitions status (Property 3)
    - **Property 3: Proposal rejection transitions status and emits event**
    - Fuzz valid pending proposals with correct counterparty
    - **Validates: Requirements 5.1, 5.2**

- [x] 5. Checkpoint — Proposal and approval flow
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. AgentEncPubRegistryFacet — Encryption key registry
  - [x] 6.1 Implement `registerEncPubKey` and `getEncPubKey`
    - Create `EqualFi/src/agentic/AgentEncPubRegistryFacet.sol`
    - Validate key length is exactly 33 bytes, first byte is `0x02` or `0x03`
    - Store key mapped to `msg.sender` in `encPubKeys`, overwrite if exists
    - Emit `AgentEncPubRegistered(msg.sender, pubkey)`
    - `getEncPubKey` returns stored bytes for any address
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

  - [x] 6.2 Write unit tests for AgentEncPubRegistryFacet
    - Test valid key registration and retrieval, overwrite behavior
    - Test invalid key length revert, invalid prefix revert
    - Test event emission
    - _Requirements: 7.1–7.6_

  - [x]* 6.3 Write property test: Encryption public key round-trip (Property 6)
    - **Property 6: Encryption public key round-trip**
    - Fuzz valid 33-byte keys with 0x02/0x03 prefix, verify round-trip identity and overwrite
    - **Validates: Requirements 7.1, 7.2, 7.3**

- [x] 7. AgenticMailboxFacet — Encrypted credential handoff
  - [x] 7.1 Implement `publishBorrowerPayload` and `publishProviderPayload`
    - Create `EqualFi/src/agentic/AgenticMailboxFacet.sol`
    - `publishBorrowerPayload`: validate caller is borrower of agreement, agreement is `Active`, envelope is non-empty; overwrite `borrowerPayloads[agreementId]`; emit `BorrowerPayloadPublished`
    - `publishProviderPayload`: validate caller has `Relayer_Role`, agreement is `Active`, envelope is non-empty; overwrite `providerPayloads[agreementId]`; emit `ProviderPayloadPublished`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 9.1, 9.2, 9.3, 9.4, 9.5_

  - [x] 7.2 Implement view functions (`getBorrowerPayload`, `getProviderPayload`)
    - Return stored bytes for given `agreementId`, return empty bytes if no payload published
    - _Requirements: 10.1, 10.2, 10.3_

  - [x] 7.3 Write unit tests for AgenticMailboxFacet
    - Test borrower publish succeeds, non-borrower reverts, inactive agreement reverts, empty envelope reverts
    - Test provider publish with relayer role succeeds, without role reverts
    - Test view functions return correct data and empty bytes for unpublished
    - Test repeated publish overwrites prior payload and latest payload is authoritative
    - _Requirements: 8.1–8.5, 9.1–9.5, 10.1–10.3_

  - [x]* 7.4 Write property test: Mailbox envelope round-trip (Property 7)
    - **Property 7: Mailbox envelope round-trip (borrower and provider)**
    - Fuzz arbitrary non-empty byte arrays, verify byte-identical round-trip for both borrower and provider payloads
    - **Validates: Requirements 24.1, 24.2, 24.3, 8.1, 9.1**

- [x] 8. AgenticAgreementFacet — Agreement lifecycle, repayment, closure, and access control
  - [x] 8.1 Implement `grantRelayerRole` and `revokeRelayerRole`
    - Create `EqualFi/src/agentic/AgenticAgreementFacet.sol`
    - Only Diamond owner/admin can call; set/unset `relayerRole[account]`
    - _Requirements: 16.1, 16.2, 16.3, 16.4_

  - [x] 8.2 Implement `activateAgreement` with reentrancy guard
    - Validate `proposalId` exists, proposal status is `Approved`
    - Create `FinancingAgreement` with status `Active`, mode `MeteredUsage`, `creditLimit = proposal.requestedAmount`, `unitLimit = proposal.requestedUnits`
    - Derive `lenderPositionKey` via `LibPositionNFT.getPositionKey(positionNFTContract, lenderPositionId)`
    - Encumber on native rails by increasing `LibEncumbrance.position(lenderPositionKey, lenderPoolId).directLent` by `creditLimit` (no module/index encumbrance wrappers)
    - Apply Active Credit Index encumbrance delta hooks consistent with native encumbrance mutations
    - Set `principalEncumbered = creditLimit`, `unitsEncumbered = unitLimit`, `borrower = proposal.creator`
    - Transition proposal status to `Activated`
    - Append `agreementId` to `agentToAgreements[agentId]` and `lenderToAgreements[lender]`
    - Emit `AgreementActivated(agreementId, proposalId, AgreementMode.MeteredUsage)` and `NativeEncumbranceUpdated` with reason `ACTIVATION`
    - Apply `nonReentrant` modifier
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9, 6.10, 20.2, 23.1_

  - [x] 8.3 Implement `applyRepayment` with waterfall and revenue split
    - Validate agreement is `Active`, `amount > 0`, apply `nonReentrant`
    - Waterfall: allocate to `feesAccrued` first, then `interestAccrued`, then `principalDrawn - principalRepaid`
    - Compute `revenueBase = toFees + toInterest`, `lenderShare = revenueBase * 7000 / 10000`, `protocolShare = revenueBase - lenderShare`
    - If principal portion > 0: increase `principalRepaid`, decrease `principalEncumbered` by same amount, and decrease lender native `directLent` reservation by the same amount
    - Apply Active Credit Index encumbrance delta hooks for principal-release path
    - Update all storage state before external calls (CEI pattern)
    - Call `IERC20(settlementAsset).transferFrom(borrower, address(this), amount)`
    - Route `protocolShare` through `LibFeeRouter` and route `lenderShare` through lender fee index for pro-rata lender distribution
    - Emit `RepaymentApplied(agreementId, amount, toFees, toInterest, toPrincipal)` and `NativeEncumbranceUpdated` with reason `REPAYMENT`
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7, 14.8, 14.9, 14.10, 20.1, 20.2, 22.1, 22.2, 22.3, 23.2_

  - [x] 8.4 Implement `closeAgreement`
    - Validate agreement is `Active`, `principalDrawn == principalRepaid`, `feesAccrued == 0`, `interestAccrued == 0`
    - Transition status to `Closed`
    - Release all remaining encumbrance by decreasing lender native `directLent` reservation by the remaining reserved amount, set `principalEncumbered = 0`
    - Apply Active Credit Index encumbrance delta hooks for closure release path
    - Emit `AgreementClosed(agreementId)` and `NativeEncumbranceUpdated` with reason `CLOSURE`
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 23.3_

  - [x] 8.5 Implement view functions (`getAgreement`, `getAgreementsByAgent`, `getEncumbrance`)
    - `getAgreement` returns full `FinancingAgreement` struct, reverts if not found
    - `getAgreementsByAgent` returns `agentToAgreements[agentId]`
    - `getEncumbrance` returns `(principalEncumbered, unitsEncumbered)` for an agreement
    - _Requirements: 17.1, 17.2, 17.4, 21.3_

  - [x] 8.6 Write unit tests for AgenticAgreementFacet
    - Test activation from approved proposal, non-approved reverts
    - Test repayment waterfall with known values (fees + interest + principal), verify exact allocations
    - Test repayment revenue split (70/30 on fees+interest), verify lenderShare + protocolShare == revenueBase
    - Test closure with zero debt succeeds, with outstanding debt reverts
    - Test overpayment repayment reverts (`amount > totalOutstandingDebt`)
    - Test relayer role grant/revoke by admin, non-admin reverts
    - Test view functions and non-existent ID reverts
    - Test reentrancy guard on applyRepayment and activateAgreement
    - _Requirements: 6.1–6.10, 14.1–14.10, 15.1–15.4, 16.1–16.4, 17.1–17.4, 20.1–20.3_

  - [x] 8.7 Write property test: Agreement activation and encumbrance (Property 5)
    - **Property 5: Agreement activation creates correct agreement and encumbers full credit limit**
    - Fuzz approved proposals, verify agreement fields, encumbrance == creditLimit, events emitted
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9, 23.1**

  - [x]* 8.8 Write property test: Repayment waterfall allocation (Property 10)
    - **Property 10: Repayment waterfall allocation sums to applied amount**
    - Fuzz arbitrary fee/interest/principal balances and repayment amounts, verify `toFees + toInterest + toPrincipal == amount`
    - **Validates: Requirements 14.1, 14.6, 22.1**

  - [x]* 8.9 Write property test: Fee split conservation (Property 11)
    - **Property 11: Fee split conservation**
    - Fuzz repayment amounts, verify `lenderShare + protocolShare == revenueBase` with at most 1 wei rounding
    - **Validates: Requirements 14.2, 22.3**

  - [x]* 8.10 Write property test: Closure requires zero outstanding debt (Property 18)
    - **Property 18: Closure requires zero outstanding debt**
    - Fuzz agreements with various debt states, verify closure only succeeds when fully repaid
    - **Validates: Requirements 15.1, 15.2, 15.3, 15.4**

  - [x]* 8.11 Write property test: Relayer role grant/revoke round-trip (Property 16)
    - **Property 16: Relayer role grant/revoke round-trip**
    - Fuzz addresses, verify grant enables access, revoke disables, multiple holders supported
    - **Validates: Requirements 16.2, 16.3, 16.4**

- [x] 9. Checkpoint — Agreement lifecycle
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. ComputeUsageFacet — Usage metering and unit pricing
  - [x] 10.1 Implement `setComputeUnitConfig`
    - Create `EqualFi/src/agentic/ComputeUsageFacet.sol`
    - Admin-only; validate `unitPrice > 0` for active configs
    - Store `ComputeUnitConfig` keyed by `(settlementAsset, unitType)`
    - _Requirements: 11.1, 11.2, 11.4_

  - [x] 10.2 Implement `registerUsage` with CEI pattern
    - Validate caller has `Relayer_Role`, agreement is `Active`, `(agreement.settlementAsset, unitType)` is active, `amount > 0`
    - Compute `debtDelta = amount * unitPrice / UNIT_SCALE`
    - Validate `principalDrawn + debtDelta <= creditLimit` and total units <= `unitLimit`
    - Update `principalDrawn`, `agreementUnitUsage[agreementId][unitType]`, and `agreementTotalUnitsUsed[agreementId]`
    - Emit `DrawExecuted(agreementId, debtDelta, amount, address(0))` and `NativeEncumbranceUpdated` with reason `USAGE`
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7, 12.8, 12.9, 12.10, 20.3_

  - [x] 10.3 Implement `batchRegisterUsage`
    - Validate caller has `Relayer_Role`; iterate entries array, apply same logic as `registerUsage` per entry
    - Revert entire batch if any entry fails
    - _Requirements: 13.1, 13.2_

  - [x] 10.4 Implement view functions (`getComputeUnitConfig`, `getUnitUsage`)
    - `getComputeUnitConfig` returns `ComputeUnitConfig` for a `(settlementAsset, unitType)` pair
    - `getUnitUsage` returns `agreementUnitUsage[agreementId][unitType]`
    - _Requirements: 11.3_

  - [x] 10.5 Write unit tests for ComputeUsageFacet
    - Test config set by admin, non-admin reverts, zero price for active reverts
    - Test single usage registration with known values, verify debt delta calculation
    - Test credit limit exceeded revert, unit limit exceeded revert, inactive unit type revert, zero amount revert
    - Test batch registration processes all entries, batch reverts entirely on single failure
    - Test view functions
    - _Requirements: 11.1–11.4, 12.1–12.10, 13.1–13.2_

  - [x]* 10.6 Write property test: Usage registration computes correct debt delta (Property 8)
    - **Property 8: Usage registration computes correct debt delta and accumulates units**
    - Fuzz valid usage parameters, verify `principalDrawn` increases by exactly `amount * unitPrice / UNIT_SCALE`
    - **Validates: Requirements 12.1, 12.2, 12.5, 12.6**

  - [x]* 10.7 Write property test: Batch usage equivalence (Property 9)
    - **Property 9: Batch usage equivalence (metamorphic)**
    - Fuzz sequences of usage entries, compare `batchRegisterUsage` result with sequential `registerUsage` calls
    - **Validates: Requirements 13.1**

  - [x]* 10.8 Write property test: Principal drawn never exceeds credit limit (Property 14)
    - **Property 14: Principal drawn never exceeds credit limit**
    - Fuzz sequences of usage registrations, verify `principalDrawn <= creditLimit` always holds
    - **Validates: Requirements 22.4, 12.3**

  - [x]* 10.9 Write property test: Unit usage never exceeds unit limit (Property 15)
    - **Property 15: Unit usage never exceeds unit limit**
    - Fuzz sequences of usage registrations, verify total units <= `unitLimit`
    - **Validates: Requirements 12.4**

  - [x]* 10.10 Write property test: Deactivated unit types reject usage (Property 19)
    - **Property 19: Deactivated unit types reject usage registration**
    - Fuzz deactivated unit types, verify `registerUsage` always reverts
    - **Validates: Requirements 11.4, 12.9**

- [x] 11. Checkpoint — Usage metering
  - Ensure all tests pass, ask the user if questions arise.

- [x] 12. Optional cross-cutting invariant property tests (defer to Phase 5)
  - [x]* 12.1 Write property test: Encumbrance conservation invariant (Property 12)
    - **Property 12: Encumbrance conservation invariant**
    - Fuzz full lifecycle sequences (activate → usage → repay → close), verify `principalEncumbered == creditLimit - principalRepaid` at every step
    - **Validates: Requirements 23.1, 23.2, 23.3, 23.4, 14.5, 14.7**

  - [x]* 12.2 Write property test: Principal repaid never exceeds principal drawn (Property 13)
    - **Property 13: Principal repaid never exceeds principal drawn**
    - Fuzz sequences of usage and repayment, verify `principalRepaid <= principalDrawn` always
    - **Validates: Requirements 22.2**

  - [x]* 12.3 Write property test: Non-existent ID lookups revert (Property 17)
    - **Property 17: Non-existent ID lookups revert**
    - Fuzz random IDs beyond `nextProposalId`/`nextAgreementId`, verify all lookup functions revert
    - **Validates: Requirements 21.3**

- [x] 13. Integration wiring and Diamond cut setup
  - [x] 13.1 Create Diamond cut initialization script
    - Create a Foundry script (`EqualFi/script/DeployAgentic.s.sol`) that deploys all 6 facets and performs a Diamond cut against the existing EqualFi Diamond deployment flow
    - Wire new selectors into the existing deployment path in `EqualFi/script/DeployV1.s.sol` (or shared helper used by it)
    - Initialize `nextProposalId = 1` and `nextAgreementId = 1` via an initializer function or Diamond cut init contract
    - Grant initial `Relayer_Role` to a configurable relayer address
    - _Requirements: 1.2, 1.3, 16.2_

  - [x] 13.2 Create test helper base contract
    - Create `EqualFi/test/helpers/AgenticTestBase.sol` with shared setup: deploy Diamond with all facets, configure test accounts (borrower, lender, relayer, admin), mint mock ERC-20 tokens, set up a default compute unit config
    - All unit and property test files should inherit from this base
    - _Requirements: 1.1, 1.2, 1.3_

- [ ] 14. Final checkpoint — Full build and test suite
  - Ensure `cd EqualFi && forge test --match-path 'test/agentic/*t.sol'` passes all unit tests plus required MVP property tests. Ask the user if questions arise.

## Notes

- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major facet
- Only the MVP-critical property path (Property 5: activation + encumbrance) is required in Phase 1; remaining property tests (marked `*`) are intentionally deferred to Phase 5
- All facets share `AgenticStorage` via `LibAgenticStorage.store()`
- Existing libraries (`LibEncumbrance`, `LibFeeRouter`, `LibPositionNFT`) are reused directly from the EqualFi codebase
- Agentic financing MUST use native encumbrance mutations on `LibEncumbrance.position(positionKey, poolId).directLent`; `LibModuleEncumbrance` and `LibIndexEncumbrance` are out of scope for this feature
