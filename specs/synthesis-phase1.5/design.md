# Design Document — Synthesis Phase 1.5: Bankr Additive Inference Rail

## Overview

Phase 1 is complete. Phase 1.5 introduces **Bankr as a complementary managed inference provider** alongside Venice before Phase 2 relayer-chain wiring work proceeds.

Primary goals:
1. Agents choose inference provider at proposal time.
2. Core accounting remains provider-agnostic and no-lock-in.
3. Venice and Bankr coexist (Bankr does not replace Venice).
4. One credential per agreement is enforced in relayer provisioning flow.
5. Kill-switch uses soft enforcement in v1 (on-chain draw freeze + off-chain access disable path), with hard revoke path designed for near-term follow-up.

### Design Decisions

1. **Additive provider set**: keep Venice active and add Bankr; no provider deprecation.
2. **Canonical provider selection in proposal/agreement state**: provider is explicit on-chain and immutable after activation.
3. **Provider-prefixed unit types**: keep pricing and accounting deterministic by unit namespaces (`VENICE_*`, `BANKR_*`) instead of collapsing provider metrics into one shared key too early.
4. **One credential per agreement**: each activated Bankr-routed agreement gets a unique agreement credential assignment from relayer-controlled key material.
5. **Soft kill v1 accepted**: phase freezes draws on-chain first, then disables local/off-chain spend path; hard upstream key revocation is tracked as follow-up work.
6. **No canonical storage migration beyond additive fields**: only append new fields to Phase 1 structs and maintain namespaced storage continuity.

### Out of Scope

- Replacing Venice integration.
- Hard revoke guarantee against every upstream Bankr key path in v1.
- New collateral/default primitives.
- Phase 2 EventListener/TransactionSubmitter delivery mechanics.
- ERC-8183/ACP lifecycle changes.

---

## Architecture

### Provider Selection and Flow

```mermaid
sequenceDiagram
    participant BA as Borrower Agent
    participant D as Diamond (Phase 1 Facets)
    participant MR as mailbox-relayer
    participant V as Venice API
    participant B as Bankr LLM Gateway

    BA->>D: createProposal(..., providerId, ...)
    Note over D: Proposal stores providerId

    LP->>D: approveProposal(proposalId)
    BA->>D: activateAgreement(proposalId)
    Note over D: Agreement stores providerId

    MR-->>D: read agreement providerId

    alt providerId = VENICE
        MR->>V: provision Venice agreement key
    else providerId = BANKR
        MR->>MR: assign unique Bankr agreement credential
        MR->>B: use Bankr gateway for inference path
    end

    MR->>D: publishProviderPayload(agreementId, encryptedEnvelope)
    MR->>D: registerUsage(... provider-prefixed unit types ...)

    Note over D,MR: On risk trigger: draw freeze first; soft kill off-chain path in v1
```

### Data Model Changes (Phase 1.5)

- `FinancingProposal` gains `providerId` (bytes32 provider identifier).
- `FinancingAgreement` gains `providerId`.
- `createProposal(...)` accepts `providerId` and validates against allowlist.
- `activateAgreement(...)` copies `proposal.providerId -> agreement.providerId`.

Suggested provider constants in shared types:
- `PROVIDER_VENICE = keccak256("venice")`
- `PROVIDER_BANKR = keccak256("bankr")`

### Unit Type Strategy

Use provider-prefixed unit IDs for v1.5 pricing and usage:
- Venice: `VENICE_TEXT_TOKEN_IN`, `VENICE_TEXT_TOKEN_OUT` (existing pattern)
- Bankr: `BANKR_TEXT_TOKEN_IN`, `BANKR_TEXT_TOKEN_OUT` (minimum viable)
- Test baseline: `AgenticTestBase` seeds active Bankr IN/OUT unit configs to validate `(settlementAsset, unitType)` keying parity in suite setup.

Optional follow-up (not required for v1.5): `BANKR_CACHE_READ_TOKEN_IN`, `BANKR_CACHE_WRITE_TOKEN_IN`, image/audio classes once telemetry granularity is validated in production traces.

### Bankr Adapter Strategy

`BankrComputeAdapter` is introduced under existing relayer provider interface:
- `provision()`
  - validates Bankr is selected,
  - assigns one unique agreement credential,
  - returns connection payload for mailbox publication.
- `usage()`
  - polls Bankr gateway usage endpoint,
  - computes deterministic deltas from checkpoint snapshots,
  - normalizes into `BANKR_*` canonical unit rows.
- `terminate()`
  - soft-kill in v1: mark agreement access disabled in relayer state and emit alert/work item for hard revoke.

### Soft Kill v1 Semantics

For Bankr-routed agreements in v1:
1. Canonical draw rights freeze on-chain (source of truth).
2. Relayer marks provider link terminated and blocks further usage settlement generation for that agreement.
3. Relayer records termination attempt metadata and alerts operator channel for upstream key revoke follow-up.

This is accepted for v1.5 with explicit follow-up requirement to close hard revoke gap.

Post-v1 TODO:
- Implement upstream Bankr hard revoke execution + confirmation path (not just relayer-local disable).
- Track and expose hard-revoke state transitions in relayer/operator surfaces.

---

## Integration Notes

- Phase 1.5 is a prerequisite to Phase 2 execution.
- Existing Phase 1 event schema can remain stable; relayer resolves provider from `getAgreement()` or activation policy payload.
- `ComputeProvider` unions and schemas in `mailbox-relayer` expand from `lambda|runpod|venice` to `lambda|runpod|venice|bankr`.

---

## Success Criteria

1. Proposal author selects inference provider (`VENICE` or `BANKR`) on-chain.
2. Activated agreements preserve selected provider deterministically.
3. Both Venice and Bankr usage can be registered and priced without storage/schema forks.
4. Bankr path uses one agreement credential assignment per agreement.
5. Soft kill behavior is explicit, tested, and operationally observable.
6. No-lock-in invariants remain true: core accounting correctness does not depend on a specific provider implementation.
