# Implementation Plan — Synthesis Phase 4.5 Reconciliation

## Overview

This plan patches documentation drift so `.kiro/specs/synthesis-phase1` through `synthesis-phase5` align with canonical v1.11.

## Tasks

- [x] 1. Patch Phase 1 event schemas to canonical v1.11
  - Files:
    - `.kiro/specs/synthesis-phase1/requirements.md`
    - `.kiro/specs/synthesis-phase1/design.md`
  - Changes:
    - Replace `AgreementActivated(..., AgreementMode mode, bytes32 providerKey)` with canonical `AgreementActivated(..., AgreementMode mode)`.
    - Replace `BorrowerPayloadPublished(..., bytes32 providerKey, bytes envelope)` with canonical `BorrowerPayloadPublished(..., bytes envelope)`.
    - Replace `ProviderPayloadPublished(..., bytes32 providerKey, address indexed borrower, bytes envelope)` with canonical `ProviderPayloadPublished(..., address indexed provider, bytes envelope)`.
    - Remove any claims that non-canonical variants are required by relayer schema.
  - Validates: Req 1

- [x] 2. Patch Phase 2 listener signatures and trigger set
  - Files:
    - `.kiro/specs/synthesis-phase2/requirements.md`
    - `.kiro/specs/synthesis-phase2/design.md`
    - `.kiro/specs/synthesis-phase2/tasks.md`
  - Changes:
    - Update `DIAMOND_EVENT_SIGNATURES` list to canonical mailbox/activation signatures.
    - Add trigger coverage for `CoverageCovenantBreached`, `DrawRightsTerminated`, `AgreementDefaulted`, `AgreementClosed`.
    - Update `EVENT_TYPE_MAP` and ingestion flow text for kill-switch and risk transitions.
    - Update tests and acceptance criteria to include these events.
  - Validates: Req 1, Req 2

- [x] 3. Patch Phase 4 covenant semantics to periodic net-draw model
  - Files:
    - `.kiro/specs/synthesis-phase4/requirements.md`
    - `.kiro/specs/synthesis-phase4/design.md`
  - Changes:
    - Replace ratio-based `checkCovenant` formulation with period accounting:
      - `grossDraw_p`, `refunds_p`, `netDraw_p`
      - `requiredPayment_p` formula from canonical Section 4.11
    - Ensure breach detection references `actualPayment_p < requiredPayment_p`.
    - Keep collateral shortfall logic as separate risk input, not covenant definition.
    - Ensure breach/cure/termination wording matches canonical default workflow handoff.
  - Validates: Req 3

- [x] 4. Patch Phase 4 interest model to linear v1.11 baseline
  - Files:
    - `.kiro/specs/synthesis-phase4/requirements.md`
    - `.kiro/specs/synthesis-phase4/design.md`
  - Changes:
    - Remove compound-interest requirements from baseline scope.
    - Keep linear accrual and fee schedule semantics.
    - If desired, add explicit “post-v1.11 extension” note for compounding.
  - Validates: Req 4

- [x] 5. Add missing Phase 4 execution plan (`tasks.md`)
  - Files:
    - Add `.kiro/specs/synthesis-phase4/tasks.md`
  - Changes:
    - Add implementation tasks mapped to Requirement IDs 1-45.
    - Add explicit test tasks for:
      - trust-mode gating
      - ACP terminal-state sync
      - Reference8183 vs MockGeneric portability
      - covenant breach/cure/termination
      - collateral toggle invariants
      - pooled governance and pro-rata distribution
  - Validates: Req 6

- [x] 6. Patch Phase 5 dependency language to permit reconciliation touches
  - Files:
    - `.kiro/specs/synthesis-phase5/requirements.md`
    - `.kiro/specs/synthesis-phase5/design.md`
  - Changes:
    - Replace strict “no modifications to Phase 1-4” wording with:
      - “No semantic feature changes to Phase 1-4; canonical reconciliation patches allowed.”
    - Add prerequisite note: execute Phase 4.5 reconciliation before final Phase 5 completion gate.
  - Validates: Req 5

- [x] 7. Build v1.11 traceability matrix and completion gate
  - Files:
    - Add `.kiro/specs/synthesis-phase4-5-reconciliation/v1_11_traceability.md`
  - Changes:
    - Map canonical Sections 4-17 to owning phase requirements and tasks.
    - Mark each section as `covered`, `partial`, or `missing`.
    - Define go/no-go completion gate with objective checks.
  - Validates: Req 7

- [x] 8. Final reconciliation review
  - Checks:
    - Re-run drift scan over `.kiro/specs/synthesis-phase1..5/*.md` for event/covenant/interest mismatches.
    - Confirm every prior finding is closed or explicitly deferred as post-v1.11.
    - Produce final gap summary with zero `missing` entries for v1.11 baseline.

## Notes

- This phase is documentation-first and unblocks implementation correctness.
- No Solidity/API behavior should be inferred from stale `.kiro` text after this phase is applied.
- Any future divergence from canonical spec must be tagged explicitly as extension scope.
