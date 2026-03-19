# Requirements Document

## Introduction

Phase 1 delivered the minimum viable on-chain agentic financing flow. Phase 1.5 extends that completed foundation by adding Bankr as a second managed inference rail while preserving Venice support.

This phase is intentionally focused on provider-choice semantics and adapter parity before Phase 2 relayer-chain integration mechanics proceed.

### Explicitly Out of Scope

- Replacing Venice with Bankr.
- Hard upstream key revocation guarantees for all Bankr key paths in v1.
- New default/delinquency state machine beyond existing Phase 1 behavior.
- Broad Phase 2/3 refactor work outside provider-selection and adapter support.

## Glossary

- **Provider_ID**: On-chain bytes32 identifier for selected inference provider.
- **Provider_Prefixed_Unit_Type**: Canonical unit type namespaced by provider (for example `VENICE_TEXT_TOKEN_IN`, `BANKR_TEXT_TOKEN_IN`).
- **Agreement_Credential**: Provider access credential scoped to one agreement in relayer provisioning.
- **Soft_Kill**: On-chain draw freeze plus relayer-side off-chain access disable, without guaranteed immediate upstream hard revoke.

## Requirements

### Requirement 1: Provider Selection in Proposals

**User Story:** As a borrower agent, I want to choose Venice or Bankr when creating a proposal, so that provider intent is explicit from the start.

#### Acceptance Criteria

1. WHEN a borrower creates a proposal, THE proposal payload SHALL include `providerId`.
2. THE system SHALL support at minimum `PROVIDER_VENICE` and `PROVIDER_BANKR`.
3. IF `providerId` is not in the supported allowlist, THEN proposal creation SHALL revert.
4. WHEN a proposal is retrieved by `getProposal`, THE selected `providerId` SHALL be returned.

### Requirement 2: Provider Propagation to Agreement

**User Story:** As the relayer, I want activated agreements to contain the selected provider, so routing is deterministic.

#### Acceptance Criteria

1. WHEN `activateAgreement` succeeds, THE agreement SHALL copy `providerId` from the source proposal.
2. WHEN `getAgreement` is called, THE stored `providerId` SHALL be returned.
3. IF proposal provider data is invalid or missing at activation time, THEN activation SHALL revert.

### Requirement 3: Additive Provider Support (No Replacement)

**User Story:** As a protocol operator, I want Bankr added without removing Venice, so agents have options.

#### Acceptance Criteria

1. Venice path SHALL remain functional after Bankr integration.
2. Bankr path SHALL be available as a selectable option for new proposals.
3. Core accounting logic SHALL not branch on provider-specific business rules beyond adapter/unit mapping boundaries.

### Requirement 4: One Agreement Credential Per Bankr Agreement

**User Story:** As a lender and borrower, I want each Bankr-routed agreement to use a unique credential assignment, so access scope is isolated.

#### Acceptance Criteria

1. WHEN a Bankr agreement is provisioned, THE relayer SHALL assign a unique agreement credential identifier.
2. THE relayer SHALL persist a one-to-one mapping between `agreementId` and assigned Bankr credential metadata.
3. IF a credential is already assigned to another active agreement, THEN the relayer SHALL reject reuse.
4. Provider payload publication SHALL include the agreement-scoped credential details required by borrower clients.

### Requirement 5: Bankr Adapter Interface Compliance

**User Story:** As a relayer maintainer, I want Bankr integrated through the same adapter interface, so provider routing remains swappable.

#### Acceptance Criteria

1. THE relayer SHALL implement `BankrComputeAdapter` conforming to `provision`, `usage`, and `terminate` methods.
2. THE provider registry SHALL include `bankr` and return it via listing endpoints.
3. Schema unions that enumerate providers SHALL include `bankr`.

### Requirement 6: Bankr Usage Metering Normalization

**User Story:** As a protocol accountant, I want Bankr usage converted into canonical unit rows, so debt accounting is deterministic.

#### Acceptance Criteria

1. WHEN Bankr usage is polled, THE adapter SHALL normalize usage into provider-prefixed unit types.
2. Minimum required Bankr unit mappings SHALL include `BANKR_TEXT_TOKEN_IN` and `BANKR_TEXT_TOKEN_OUT`.
3. THE adapter SHALL use deterministic checkpointing and delta logic to avoid double application.
4. IF usage payloads are missing required fields or cannot be mapped, THEN rows SHALL be quarantined/fail-closed rather than silently dropped.

### Requirement 7: Provider-Prefixed Unit Type Pricing

**User Story:** As an admin, I want separate unit pricing per provider namespace, so Venice and Bankr costs can diverge safely.

#### Acceptance Criteria

1. Compute unit config SHALL support Bankr-prefixed unit types without storage schema redesign.
2. Unit pricing for `VENICE_*` and `BANKR_*` SHALL be configurable independently.
3. Usage registration SHALL continue to validate `(settlementAsset, unitType)` active status for both providers.

### Requirement 8: Soft Kill Semantics for Bankr v1

**User Story:** As a risk operator, I want a clear and testable Bankr soft-kill path, so draw freezes are enforceable immediately.

#### Acceptance Criteria

1. On kill-switch trigger, THE canonical on-chain draw freeze SHALL occur before relayer off-chain disable actions.
2. The Bankr adapter `terminate()` in v1 SHALL disable relayer-side agreement access and mark the agreement termination state.
3. The relayer SHALL emit a structured alert/work item indicating hard revoke follow-up is required when upstream revoke is not confirmed.
4. Post-termination, THE relayer SHALL not generate new usage submissions for that agreement.

### Requirement 9: Backward Compatibility and Migration Safety

**User Story:** As a deployer, I want Phase 1.5 upgrades to remain safe for existing Phase 1 code paths.

#### Acceptance Criteria

1. Existing Venice proposals and agreements SHALL remain readable and operable.
2. Storage updates SHALL be additive and preserve namespace continuity.
3. Existing facet interfaces/functions SHALL remain backward compatible where possible, with explicit versioned updates when signatures change.

### Requirement 10: Differential Parity Between Venice and Bankr

**User Story:** As a protocol developer, I want parity tests between Venice and Bankr, so provider choice does not change canonical accounting guarantees.

#### Acceptance Criteria

1. Equivalent synthetic workload traces through Venice and Bankr adapters SHALL produce deterministic, expected debt deltas under configured unit prices.
2. Disabling Bankr SHALL not impact Venice accounting behavior.
3. Disabling Venice SHALL not impact Bankr accounting behavior.

### Requirement 11: Proposal-Time Provider Choice is Source of Truth

**User Story:** As an auditor, I want provider intent anchored on-chain, so relayer routing cannot drift from borrower-lender agreement terms.

#### Acceptance Criteria

1. Relayer activation routing SHALL use on-chain provider data from proposal/agreement state as canonical input.
2. Off-chain policy payloads MAY augment provider config but SHALL NOT override on-chain selected provider for an activated agreement.
3. Any mismatch between on-chain provider and off-chain override attempt SHALL fail closed.
