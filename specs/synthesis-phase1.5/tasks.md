# Implementation Plan: Synthesis Phase 1.5 — Bankr Additive Provider Rail

## Overview

Phase 1.5 executes after completed Phase 1 and before Phase 2. It introduces on-chain provider selection and Bankr adapter support while preserving Venice behavior.

## Tasks

- [x] 1. Shared provider types and constants (on-chain)
  - [x] 1.1 Extend Agentic shared types with provider identifiers
    - Update `EqualFi/src/agentic/types/AgenticTypes.sol`
    - Add provider constants: `PROVIDER_VENICE`, `PROVIDER_BANKR`
    - Add custom error for unsupported provider (`UnsupportedProvider(bytes32 providerId)`)
    - _Requirements: 1.1, 1.2, 1.3, 3.1, 3.2_

  - [x] 1.2 Extend proposal and agreement structs with providerId
    - Append `bytes32 providerId` to `FinancingProposal`
    - Append `bytes32 providerId` to `FinancingAgreement`
    - Ensure additive layout update discipline in storage-backed structs
    - _Requirements: 1.1, 2.1, 2.2, 9.2_

- [x] 2. Proposal facet updates for provider choice
  - [x] 2.1 Update interface and implementation for createProposal provider input
    - Update `EqualFi/src/interfaces/IAgenticProposalFacet.sol`
    - Update `EqualFi/src/agentic/AgenticProposalFacet.sol`
    - Add `providerId` parameter to `createProposal(...)`
    - Validate provider against allowlist (`VENICE`, `BANKR`)
    - Persist providerId in proposal storage
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 2.2 Update proposal tests
    - Update `EqualFi/test/agentic/AgenticProposalFacet.t.sol`
    - Add success tests for both providers
    - Add revert test for unsupported provider
    - _Requirements: 1.1, 1.3, 3.1_

- [x] 3. Agreement activation propagation
  - [x] 3.1 Persist providerId from proposal into agreement
    - Update `EqualFi/src/agentic/AgenticAgreementFacet.sol`
    - On activation, copy `proposal.providerId` to `agreement.providerId`
    - Fail closed on invalid provider values
    - _Requirements: 2.1, 2.3, 11.1_

  - [x] 3.2 Update agreement tests
    - Update `EqualFi/test/agentic/AgenticAgreementFacet.t.sol`
    - Verify provider propagation on activation
    - Verify invalid provider fails activation
    - _Requirements: 2.1, 2.3_

- [x] 4. Compute unit strategy for Bankr-prefixed units
  - [x] 4.1 Add/validate Bankr unit types in test setup and docs
    - Keep existing `(settlementAsset, unitType)` storage keying
    - Add Bankr-prefixed unit types in test configs (minimum: `BANKR_TEXT_TOKEN_IN`, `BANKR_TEXT_TOKEN_OUT`)
    - _Requirements: 6.1, 6.2, 7.1, 7.2, 7.3_

  - [x] 4.2 Update ComputeUsage tests for provider-prefixed unit pricing
    - Extend `EqualFi/test/agentic/ComputeUsageFacet.t.sol`
    - Confirm independent pricing and enforcement across Venice/Bankr unit namespaces
    - _Requirements: 6.1, 7.2, 7.3, 10.1_

- [x] 5. Deployment and initialization compatibility
  - [x] 5.1 Ensure deployment scripts remain compatible
    - Update `EqualFi/script/DeployAgentic.s.sol` and `EqualFi/script/DeployV1.s.sol` only if selector/signature updates require it
    - Ensure no regression in facet cut/install paths
    - Verified no script change required: both deploy paths use facet `.selector` references (`AgenticProposalFacet.createProposal.selector`) and remain compatible.
    - _Requirements: 9.1, 9.3_

  - [x] 5.2 Run agentic suite checkpoint
    - Run `cd EqualFi && forge test --match-path 'test/agentic/*t.sol'`
    - Ensure all updated tests pass
    - Checkpoint: 96 passed, 0 failed.
    - _Requirements: 9.1, 9.2_

- [x] 6. Relayer provider union + schema expansion
  - [x] 6.1 Extend provider unions to include Bankr
    - Update `mailbox-relayer/src/providers/types.ts` (`ComputeProvider` union)
    - Update `mailbox-relayer/src/schema.ts` provider enums
    - Update any other provider enum guards to include `bankr`
    - Updated default API surface validation (`demoVerticalFlowSchema`, `onchainEventSchema`) and `/providers` response assertions to include `bankr`.
    - _Requirements: 3.2, 5.2_

  - [x] 6.2 Register Bankr in default adapter registry
    - Update `mailbox-relayer/src/providers/registry.ts`
    - Ensure `/providers` endpoint reports `bankr`
    - Added scaffolded `BankrComputeAdapter` and registered in default registry.
    - _Requirements: 5.2, 5.3_

- [x] 7. Implement BankrComputeAdapter
  - [x] 7.1 Create adapter scaffold
    - Create `mailbox-relayer/src/providers/bankr.ts`
    - Implement `ComputeProviderAdapter` methods (`provision`, `usage`, `terminate`)
    - Add env options: `BANKR_LLM_KEY`, `BANKR_LLM_BASE_URL`, optional `BANKR_KEY_POOL_*` source config
    - Added scaffold + concrete implementation with configurable usage path/pagination and key-pool sources (`BANKR_KEY_POOL_JSON`, `BANKR_KEY_POOL_PATH`, `BANKR_KEY_POOL_ENV_PREFIX`, `BANKR_KEY_POOL_STRICT`).
    - _Requirements: 4.1, 5.1, 5.2_

  - [x] 7.2 Implement provision with one-credential-per-agreement assignment
    - Assign unique Bankr credential metadata per agreement
    - Store unique providerResourceId/key fingerprint mapping in relayer store
    - Reject duplicate active assignment
    - Return connection payload for mailbox publication
    - Added duplicate provider-resource guard in activation ingestion and assignment/fingerprint conflict checks in adapter.
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 7.3 Implement usage polling and normalization
    - Poll Bankr usage endpoint(s)
    - Compute deterministic deltas from checkpoint snapshots
    - Emit normalized `BANKR_TEXT_TOKEN_IN` and `BANKR_TEXT_TOKEN_OUT` rows
    - Quarantine/fail on unmappable payloads
    - Implemented usage polling with pagination support and canonical Bankr unit normalization + quarantine error path.
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x] 7.4 Implement v1 soft-kill terminate path
    - Disable relayer-side agreement access for Bankr agreement
    - Mark termination metadata and emit structured alert for hard revoke follow-up
    - Prevent future usage generation for terminated agreement
    - Bankr terminate now emits soft-kill metadata; kill-switch clears provider link, emits `termination_followup_required` alert, and metering skips agreement once link is removed.
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 8. Relayer workflow routing
  - [x] 8.1 Ensure activation flow uses on-chain provider as canonical source
    - Update event ingestion/routing logic so activated agreement routing honors canonical provider selection
    - Reject off-chain override mismatch
    - Activation ingestion now requires canonical on-chain `event.provider`, rejects provider override mismatches from policy/payload, and fails closed on existing provider-link mismatch.
    - _Requirements: 11.1, 11.2, 11.3_

  - [x] 8.2 Preserve Venice flow unchanged
    - Validate existing Venice route behavior remains intact after Bankr additions
    - Added routing regression tests showing canonical `venice` activation still provisions via Venice adapter and writes Venice provider links unchanged.
    - _Requirements: 3.1, 3.2, 9.1_

- [x] 9. Relayer test coverage
  - [x] 9.1 Unit tests for Bankr adapter
    - Create `mailbox-relayer/test/providers/bankr.test.ts`
    - Test missing config path, successful provision, duplicate assignment rejection, usage normalization, quarantine behavior, soft terminate behavior
    - Completed in `test/providers/bankr.test.ts` covering config failure, assignment behavior, normalization, quarantine, and soft-terminate semantics.
    - _Requirements: 4.1–4.4, 6.1–6.4, 8.2–8.4_

  - [x] 9.2 Update app/events/metering tests for Bankr support
    - Update provider-enum dependent tests in:
      - `mailbox-relayer/test/app.test.ts`
      - `mailbox-relayer/test/events.test.ts`
      - `mailbox-relayer/test/metering.test.ts`
      - `mailbox-relayer/test/killswitch.test.ts`
    - Verify provider listing and routing includes bankr
    - Added Bankr assertions/flows in all listed files for provider listing, activation routing, metering aggregation, and kill-switch termination handling.
    - _Requirements: 3.2, 5.2, 5.3, 11.1_

  - [x] 9.3 Differential parity tests (Venice vs Bankr)
    - Add synthetic trace tests to prove deterministic expected debt deltas under independent provider-prefixed unit prices
    - Confirm disable-one-provider does not break the other
    - Added `test/metering.parity.test.ts` with synthetic Venice/Bankr trace parity and disable-one-provider resilience checks.
    - _Requirements: 10.1, 10.2, 10.3_

- [x] 10. Documentation and operator runbook updates
  - [x] 10.1 Update mailbox-relayer README env docs
    - Document Bankr environment variables and soft-kill behavior
    - Updated `mailbox-relayer/README.md` with Bankr env variables, canonical provider routing notes, and v1.5 soft-kill operator behavior.
    - _Requirements: 8.3, 9.1_

  - [x] 10.2 Add hard-revoke follow-up backlog note
    - Add explicit TODO in spec/docs for upstream hard revoke path closure (post-v1)
    - Added explicit post-v1 hard-revoke TODOs in both `mailbox-relayer/README.md` and `synthesis-phase1.5/design.md`.
    - _Requirements: 8.3_

- [x] 11. Final checkpoint — Phase 1.5 complete
  - Verify contract suite and relayer suite pass:
    - `cd EqualFi && forge test --match-path 'test/agentic/*t.sol'`
    - `cd mailbox-relayer && npm test && npm run build`
  - Confirm both providers appear in relayer provider list and proposal-time provider choice is persisted on-chain.
  - Checkpoint run complete:
    - EqualFi agentic suite: 96 passed, 0 failed.
    - mailbox-relayer suite: 40 passed, 0 failed; build passed.
  - Provider confirmation:
    - Relayer provider listing includes `bankr` (`mailbox-relayer/test/app.test.ts`).
    - On-chain persistence validated by agentic tests (`test_createProposal_acceptsBankrProvider`, `test_activateAgreement_propagatesBankrProvider`).

## Notes

- Bankr is additive, not a Venice replacement.
- One credential assignment per agreement is required for Bankr paths.
- Soft kill is acceptable for v1.5 but must emit operator-visible revoke follow-up signals.
- Unit-type pricing remains provider-prefixed in this phase to prevent hidden cross-provider pricing coupling.
