# EqualScale DIEM Inference Lending — Extension Specification

**Status:** Draft v0.3  
**Date:** 2026-03-20  
**Extends:** `specs/agentic-financing-spec.md` (Canonical v1.3)  
**Protocol:** Equalis (EqualFi)  
**Venue:** Venice.ai (Base)

---

## 1) Purpose

Define one specialized extension for **DIEM-backed inference lending** on Venice with two product surfaces:

1. **Solo DIEM Inference Lending** (single DIEM supplier / backing position ↔ single agent)
2. **Pooled DIEM Inference Lending** (many DIEM suppliers ↔ single agent or demand set under pool policy)

Both products must share:
- One proposal lifecycle
- One agreement accounting model
- One collateral model
- One risk state machine
- One mailbox delivery model
- One fee routing model
- One Venice child-key provisioning model

This extension reuses the canonical EqualScale financing framework and specializes Product C / Product D style compute-inference lending for **staked DIEM-backed Venice API access**.

---

## 2) Design Goals

1. **Keep DIEM principal under protocol control.** Borrowers receive inference access, not token principal.
2. **Use actual consumption as debt basis.** Unused allocation must not create debt.
3. **Fail closed on credit impairment.** Revocation of inference access is the first enforcement action.
4. **Reuse EqualScale rails.** Agreement lifecycle, collateral, repayment routing, and risk logic remain canonical.
5. **Stay venue-aware but not venue-owned.** Venice-specific mechanics are isolated to this extension and relayer logic.

---

## 3) Product Matrix

| Product | Capital Source | Underwriting | Release Style | Repayment Source |
|---|---|---|---|---|
| Solo DIEM Inference Lending | Single DIEM supplier / backing position | Supplier policy | Scoped Venice child key | Metered usage + manual repay |
| Pooled DIEM Inference Lending | Pooled DIEM supplier positions | Governance + policy | Scoped Venice child key | Metered usage + manual repay |

---

## 4) Shared Primitives

### 4.1 Identity Model

Borrower identity reuses the canonical ERC-8004 borrower model:
- `agentRegistry`
- `agentId`
- wallet resolution from ERC-8004 semantics at execution time

### 4.2 Proposal Primitive

DIEM inference lending proposals specialize the canonical compute/inference proposal path.

```solidity
struct DiemInferenceProposal {
    uint256 id;
    ProposalType proposalType;      // SoloCompute or PooledCompute specialization
    string agentRegistry;
    uint256 agentId;
    address settlementAsset;        // USDC for v1
    uint256 requestedDiemLimit;     // max DIEM-backed usage budget
    uint256 requestedCreditLimit;   // max USD debt tolerance
    uint40 createdAt;
    uint40 expiresAt;
    bytes32 termsHash;
    string uri;
    bytes32 uriHash;
    uint16 uriSchemaVersion;
    address counterparty;           // supplier for solo, zero for pooled
    ProposalStatus status;

    // DIEM-specific
    bool collateralEnabled;
    address collateralAsset;
    uint256 collateralAmount;
    bytes32[] allowedModels;
}
```

Rules:
- `expiresAt > createdAt`
- activation requires valid `termsHash` binding
- `proposalType` MUST map to `SoloCompute` / `PooledCompute` specialization, not agentic financing specialization
- initial launch SHOULD restrict `proposalType` to solo path first
- `requestedDiemLimit` is provider-native budgeting metadata and SHOULD map cleanly to canonical unit accounting

### 4.3 Agreement Primitive

DIEM inference agreements specialize the canonical compute/inference agreement path.

```solidity
struct DiemInferenceAgreement {
    uint256 id;
    uint256 proposalId;
    string agentRegistry;
    uint256 agentId;
    AgreementMode mode;             // MeteredUsage
    AgreementStatus status;

    // Funding limits
    uint256 creditLimit;            // money-denominated debt tolerance
    uint256 unitLimit;              // canonical compute/inference limit mirror
    uint256 diemLimit;              // DIEM-backed usage limit

    // Current balances
    uint256 principalDrawn;         // USD debt principal from metered usage
    uint256 principalRepaid;
    uint256 interestAccrued;
    uint256 feesAccrued;
    uint256 diemConsumed;

    // Payment schedule
    uint256 minPaymentPerPeriod;
    uint32 paymentInterval;
    uint40 firstDueAt;
    uint32 gracePeriod;

    // Risk
    uint16 reserveBps;
    uint16 liquidationPenaltyBps;
    uint16 writeOffThresholdBps;

    // Metadata
    bytes32 termsHash;
    bool pooled;

    // DIEM-specific collateral
    bool collateralEnabled;
    address collateralAsset;
    uint256 collateralAmount;

    // Venice-specific key state
    string veniceApiKeyId;
    uint40 keyExpiresAt;
    bool keyActive;

    // Metering
    uint40 lastMeteredAt;
    uint40 lastSettledEpoch;
}
```

### 4.4 Agreement Mode

Initial DIEM lending SHALL use:
- `MeteredUsage`

### 4.5 Settlement Asset

Initial DIEM lending SHALL settle debt in:
- `USDC`

### 4.6 Unit Compatibility Rule

This extension MUST remain compatible with canonical compute/inference accounting.

- `requestedDiemLimit` SHOULD map to canonical proposal-side unit budgeting
- `diemLimit` SHOULD map to canonical agreement-side `unitLimit`
- DIEM-specific fields MAY remain as provider-native mirrors for UX, relayer policy, and analytics

### 4.7 Capital Backing + Encumbrance

- Backing capital remains under protocol-controlled custody and encumbrance.
- DIEM principal is not transferred to borrowers.
- Borrowers receive bounded provider access, not token principal.

### 4.8 Repayment Routing

Repayment routing SHALL reuse the canonical EqualScale repayment waterfall and protocol rail split unless explicitly overridden by future amendment.

### 4.9 Venice Interoperability Profile

This extension uses the following Venice-specific profile:

- DIEM-backed provider access is controlled under a protocol-controlled Venice principal account
- borrower-facing access is delegated through scoped child API keys
- child keys MAY use `consumptionLimit.diem` and optional `expiresAt`
- provider usage attribution is sourced from Venice billing / usage endpoints
- revoke or clamp operations are part of canonical risk enforcement for this extension

---

## 5) State Machines

### 5.1 Proposal State Machine

```
Pending -> Approved -> Activated
Pending -> Rejected
Pending -> Expired
Pending -> Cancelled
```

### 5.2 Agreement State Machine

```
Active -> Delinquent -> Defaulted -> Closed/WrittenOff
Active -> Closed
Delinquent -> Active
```

### 5.3 Access State Machine

```
NoKey -> KeyProvisioning -> KeyActive -> KeyClamped -> KeyRevoked
```

- `NoKey`: no Venice borrower key exists
- `KeyProvisioning`: relayer is creating and publishing a scoped key
- `KeyActive`: borrower can consume inference subject to policy
- `KeyClamped`: key remains present but limits are reduced or frozen
- `KeyRevoked`: no further intended usage is permitted

---

## 6) Product E — Solo DIEM Inference Lending

### 6.1 Definition

Single DIEM supplier or single backing position provides DIEM-backed inference access to one agent identity.

### 6.2 Supported Modes

- Metered usage

### 6.3 Core Flow

1. Agent submits DIEM inference proposal.
2. Target supplier approves or rejects before expiry.
3. On approval, agreement activates.
4. Relayer provisions scoped Venice child key.
5. Agent consumes inference up to DIEM/key policy limits.
6. Metered usage converts to settlement-asset debt.
7. Agent repays in USDC.
8. Agreement closes when debt is repaid and key is revoked.

### 6.4 Solo Controls

- collateral requirement
- DIEM/key limit per agreement
- optional model allowlist
- per-agreement expiry / revocation policy

---

## 7) Product F — Pooled DIEM Inference Lending

### 7.1 Definition

Many DIEM suppliers back pooled DIEM inference inventory from which borrower agreements draw under pool policy.

### 7.2 Governance

- proposal approval by pool policy or weighted governance process
- quorum and threshold per pool policy
- optional guardian or pause controls for emergency conditions

### 7.3 Core Flow

1. Agent submits DIEM inference proposal.
2. Pool approves or policy checks pass.
3. Agreement activates with pooled backing.
4. Relayer provisions scoped Venice child key.
5. Agent consumes inference subject to pool and agreement constraints.
6. Metered usage converts to settlement-asset debt.
7. Repayments distribute through pooled accounting and canonical protocol rails.

### 7.4 Pooled Risk Controls

- max DIEM-backed exposure per agent
- max active agreements per pool
- collateral floor
- pool encumbrance ceiling

---

## 8) Supplier Position Primitive

```solidity
struct DiemSupplierPosition {
    uint256 id;
    address owner;
    uint256 diemDeposited;
    uint256 diemEncumbered;
    uint256 shares;
    uint40 depositedAt;
    bool pooled;
}
```

### 8.1 Position rules

- `diemDeposited` is total contributed backing inventory
- `diemEncumbered` is the amount currently backing active borrower access
- withdrawal MUST fail if it would violate encumbrance constraints

---

## 9) Pool Primitive

```solidity
struct DiemInferencePool {
    uint256 id;
    string name;
    uint256 totalDiemDeposited;
    uint256 totalDiemEncumbered;
    uint256 activeAgreementCount;
    uint256 minimumCollateralBps;
    bool borrowPaused;
}
```

---

## 10) Child Key Provisioning Model

### 10.1 Key requirements

Every active borrower agreement SHOULD map to one scoped Venice child key in the v1 design.

That key SHOULD include:
- `apiKeyType = INFERENCE`
- `description = agreement-specific identifier`
- `consumptionLimit.diem`
- optional `expiresAt`

Example logical payload:

```json
{
  "apiKeyType": "INFERENCE",
  "description": "equalscale-diem-agreement-123",
  "consumptionLimit": { "diem": 5 },
  "expiresAt": "2026-03-21T00:00:00Z"
}
```

### 10.2 Delivery rule

The raw provider secret SHALL NEVER be published onchain in plaintext.

The relayer SHALL:
1. create the child key
2. encrypt the secret to the borrower public key
3. publish the encrypted payload through the mailbox delivery path

### 10.3 Rotation rule

Daily key rotation is **not required** for the initial version.

The minimum viable model is:
- one active child key per agreement
- DIEM-bounded consumption limit
- explicit revoke or clamp on breach/default

Rotation may be added later as a hardening layer.

---

## 11) Debt Basis and Metering

### 11.1 Hard rule

Debt SHALL accrue from **consumed usage only**.

Unused DIEM allocation SHALL NOT create debt.

### 11.2 Metering source

Provider usage attribution SHALL be sourced from Venice billing / usage endpoints, including:
- `/billing/usage`
- `/billing/usage-analytics`
- key-level provider usage data where available

### 11.3 Dual accounting

The protocol SHOULD track both:
- provider-side DIEM consumption
- money-denominated debt principal

This preserves:
- provider-native DIEM semantics for key budgeting
- stable-value accounting for repayment, collateral, and liquidation

### 11.4 Normalization rule

For canonical agreement accounting, metered Venice consumption SHALL be normalized into settlement-asset debt, initially USD / USDC terms.

---

## 12) Collateral Model

### 12.1 Initial launch rule

Initial DIEM lending SHALL be collateralized.

### 12.2 Initial collateral set

Supported collateral for v1:
- `USDC`

Later versions MAY support additional protocol-approved collateral assets.

### 12.3 Collateral purpose

Collateral secures:
- unpaid principal
- accrued interest
- fees
- liquidation penalty when applicable

Collateral does not represent ownership of the backing DIEM principal.

### 12.4 Example policy

```text
Collateral ratio: 150%
Settlement asset: USDC
Usage access budget: DIEM
Liquidation trigger: collateral impairment or payment breach
```

---

## 13) Repayment and Fee Accrual

### 13.1 Waterfall

For repayment amount `R`:
1. `feesAccrued`
2. `interestAccrued`
3. `principalDrawn`

### 13.2 Protocol routing

Protocol rail routing SHALL reuse the canonical EqualScale fee router and split logic unless explicitly amended later.

### 13.3 Interest basis

Interest SHOULD accrue on unpaid debt principal, not on unused DIEM allocation.

---

## 14) Risk and Recovery

### 14.1 Delinquency triggers

Given:
- `periodsElapsed`
- `requiredCumulative = periodsElapsed * minPaymentPerPeriod`
- `actualCumulative` applied via repayment waterfall

Then an agreement MAY become delinquent if any of the following occurs:
- `actualCumulative < requiredCumulative` after due boundary
- collateral ratio falls below maintenance threshold
- outstanding debt exceeds configured agreement tolerance
- provider policy breach occurs and is marked non-curable

### 14.2 First enforcement action

On covenant breach or delinquency, the protocol SHALL first:
1. freeze additional borrowing / expansion
2. clamp or revoke Venice child key access
3. update agreement risk state

### 14.3 Default consequences

On default:
- active child key MUST be revoked or reduced to zero usable budget
- new usage access MUST NOT be intentionally granted
- collateral recovery and write-off logic proceed through canonical rails

### 14.4 Core principle

Inference access is the first risk lever to cut.

---

## 15) Solo Lending Flow

```text
1. Supplier deposits DIEM-backed capacity
2. Borrower submits DIEM inference proposal
3. Borrower posts collateral
4. Supplier approves proposal
5. Agreement activates
6. Relayer provisions child Venice key
7. Relayer encrypts and delivers key via mailbox
8. Borrower consumes inference
9. Relayer meters usage and registers debt
10. Borrower repays in USDC
11. Agreement closes; key revoked; encumbrance released
```

---

## 16) Pooled Lending Flow

```text
1. Suppliers deposit DIEM into pool
2. Pool issues shares / position claims
3. Borrower submits DIEM inference proposal under pool policy
4. Pool approves or policy checks pass
5. Agreement activates against pooled backing inventory
6. Relayer provisions and delivers child key
7. Usage is metered and posted to agreement debt
8. Repayments route to pool + protocol rail
9. Losses, if any, are resolved by pool accounting rules
```

---

## 17) On-Chain Modules

### 17.1 New / extended facets

| Facet | Responsibility |
|---|---|
| `DiemInferenceFacet` | DIEM proposal/agreement activation and key-state metadata |
| `DiemPoolFacet` | supplier deposits, shares, encumbrance |
| `DiemMeteringFacet` | DIEM and USD usage registration |
| `DiemCollateralFacet` or collateral extension | DIEM-specific collateral flows |

Notes:
- this extension SHOULD prefer reuse of canonical proposal/agreement/risk rails over bespoke lifecycle branches
- DIEM-specific facets SHOULD focus on provider budgeting, key state, supplier positions, and pool-specific accounting

### 17.2 Reused facets / libraries

| Component | Reuse |
|---|---|
| `AgenticProposalFacet` | canonical compute/inference proposal lifecycle integration |
| `AgenticAgreementFacet` | shared lifecycle integration |
| `AgenticRiskFacet` | shared delinquency/default logic |
| `LibFeeRouter` | shared protocol rail routing |
| `LibModuleEncumbrance` | backing capital encumbrance tracking |
| `LibActiveCreditIndex` | shared protocol rail / value distribution integration |
| mailbox delivery path | encrypted provider payload publishing |

---

## 18) Storage Layout

```solidity
bytes32 constant DIEM_STORAGE_POSITION = keccak256("equalis.diem.inference.storage.v3");

struct DiemStorage {
    uint256 nextPositionId;
    uint256 nextPoolId;

    mapping(uint256 => DiemInferenceAgreement) agreements;
    mapping(uint256 => DiemSupplierPosition) positions;
    mapping(uint256 => DiemInferencePool) pools;

    mapping(uint256 => uint256[]) agreementToPositions;
    mapping(uint256 => uint256[]) poolToAgreements;

    mapping(uint256 => string) agreementToApiKeyId;
    mapping(uint256 => uint40) agreementKeyExpiresAt;
    mapping(uint256 => uint256) agreementDiemConsumed;
    mapping(uint256 => uint256) agreementUsdDebt;
    mapping(uint256 => uint256) agreementUnitUsage;
}
```

---

## 19) Relayer Responsibilities

The relayer SHALL:

1. create borrower child keys under the Venice principal account
2. patch key limits or expiry when needed
3. revoke keys on close, breach, or default
4. fetch Venice balance and usage data
5. attribute usage to agreements
6. encrypt and publish borrower provider payloads
7. trigger risk actions when configured thresholds are crossed

Time-sensitive and provider-specific logic remains off-chain in the initial design.

---

## 20) Canonical Events

```solidity
event DiemInferenceProposalCreated(uint256 indexed proposalId, ProposalType proposalType, uint256 indexed agentId);
event DiemInferenceAgreementActivated(uint256 indexed agreementId, uint256 indexed proposalId, uint256 unitLimit, uint256 diemLimit, uint256 creditLimit);
event DiemInferenceKeyProvisioned(uint256 indexed agreementId, bytes32 indexed apiKeyIdHash);
event DiemInferenceUsageRecorded(uint256 indexed agreementId, uint256 diemConsumed, uint256 debtDelta);
event DiemInferenceKeyClamped(uint256 indexed agreementId);
event DiemInferenceKeyRevoked(uint256 indexed agreementId);
event DiemSupplierPositionCreated(uint256 indexed positionId, address indexed owner, uint256 diemDeposited, bool pooled);
event DiemPoolCreated(uint256 indexed poolId, string name);
```

---

## 21) Safety Invariants

The system MUST preserve the following invariants:

1. borrower never receives underlying DIEM principal
2. debt is created by consumed usage, not mere allocation
3. a defaulted agreement cannot intentionally retain valid inference access
4. supplier withdrawal cannot violate active encumbrance
5. mailbox-published credentials are encrypted before publication
6. agreement accounting remains coherent under relayer retry or provider retry conditions

---

## 22) Failure Handling

| Failure | Required Response |
|---|---|
| Child key creation fails | agreement remains inactive or pending remediation |
| Mailbox publish fails | do not mark credentials delivered; retry safely |
| Usage fetch fails | freeze further access expansion or fail closed per policy |
| Collateral breach | freeze + clamp/revoke access |
| Key revocation failure | retry with backoff; mark emergency risk state |
| Supplier withdrawal while encumbered | revert |

---

## 23) Implementation Sequence

Compatibility decisions in this spec:
- `proposalType` remains `SoloCompute` / `PooledCompute`
- `requestedDiemLimit` is treated as DIEM-specific provider budgeting metadata layered onto canonical unit budgeting
- `diemLimit` SHOULD mirror canonical `unitLimit` for storage and accounting compatibility

### Phase 1 — Solo, collateralized, relayer-managed

Build first:
- solo supplier path
- USDC collateral only
- one child key per agreement
- DIEM-limited key provisioning
- mailbox delivery
- usage-to-debt registration
- revoke-on-breach/default

### Phase 2 — Pooled backing

Add:
- pooled supplier deposits
- share accounting
- pooled loss socialization
- withdrawal queue / encumbrance-aware exits

### Phase 3 — Hardening

Add:
- optional daily key rotation
- richer model restrictions
- alerting and rate-shaping policy
- stronger automated risk triggers

### Phase 4 — Trust expansion

Potential later additions:
- undercollateralized DIEM lending for strong ERC-8004 identities
- hybrid collateral + reputation underwriting
- revolving DIEM-backed inference lines

---

## 24) Open Questions

1. What exact operational path is used to stake DIEM under the Venice principal account?
2. Which principal-account operations are fully API-addressable versus dashboard/manual?
3. Can Venice enforce model allowlists directly on child keys, or only indirectly through monitoring?
4. Should v1 use explicit `expiresAt` on every borrower key, or rely mainly on DIEM limits plus revoke?
5. How should pooled withdrawal timing relate to any Venice-side unstake timing constraints?
6. Should `requestedDiemLimit` and `requestedUnits` collapse to one canonical proposal field in implementation, with DIEM retained only as metadata/adapter configuration?

---

## 25) Final Position

This extension defines DIEM lending as a **collateralized, metered, key-delegated inference credit product**.

The canonical architecture is:
- keep DIEM under protocol control
- delegate bounded Venice inference access with scoped child keys
- deliver credentials through the mailbox
- meter actual usage into settlement-asset debt
- revoke access first on breach/default

This keeps the product aligned with:
- Venice’s DIEM and child-key mechanics
- EqualScale’s canonical financing framework
- EqualFi’s broader thesis that productive access rights can be financed without transferring underlying principal.

---

**End of DIEM Inference Lending Spec v0.3**
