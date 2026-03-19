# Requirements Document — Synthesis Phase 4.5 Reconciliation

## Introduction

Phase 4.5 reconciles `.kiro` phase documentation with the canonical v1.11 specification in:
- `synthesis/specs/agentic-financing/agentic-financing-spec.md`
- `synthesis/specs/agentic-financing/compute-orchestration-spec.md`
- `synthesis/specs/agentic-financing/venice-adapter-spec.md`
- canonical ERC-8183 adapter guidance used by the Phase 4 adapter design

This phase is documentation-alignment work. It does not introduce new product semantics. It removes drift that would otherwise cause implementation and test plans to diverge from canonical v1.11 behavior.

### Explicitly Out of Scope

- New protocol features not already present in canonical v1.11
- Changes to contract code in this phase
- Changes to non-agentic specs

## Requirements

### Requirement 1: Canonical Event Schema Alignment

All phase docs SHALL use the canonical v1.11 event signatures and argument order for:
- `AgreementActivated`
- `BorrowerPayloadPublished`
- `ProviderPayloadPublished`

Acceptance criteria:
1. Phase docs SHALL remove `providerKey` from these three event schemas.
2. Event listener signatures in Phase 2 SHALL match canonical signatures exactly.
3. Any text claiming compatibility SHALL reference canonical Section 11 without contradictory local variants.

### Requirement 2: Orchestration Trigger Coverage Alignment

Phase 2 listener requirements/design SHALL include risk/enforcement triggers required by orchestration spec.

Acceptance criteria:
1. Subscribed events SHALL include:
   - `CoverageCovenantBreached`
   - `DrawRightsTerminated`
   - `AgreementDefaulted`
   - `AgreementClosed`
2. Phase 2 delivery mapping SHALL define handling for these trigger events.
3. Phase 2 docs SHALL no longer describe a reduced trigger set as sufficient for kill-switch behavior.

### Requirement 3: Net Draw Coverage Covenant Semantic Alignment

Phase 4 covenant requirements/design SHALL use canonical periodic payment-vs-net-draw semantics.

Acceptance criteria:
1. Covenant compliance logic SHALL be defined from period accounting:
   - `grossDraw_p`, `refunds_p`, `netDraw_p`
   - `requiredPayment_p = feesDue_p + interestDue_p + (netDraw_p * minNetDrawCoverageBps / 10000) + principalFloorPerPeriod`
2. Ratio-based collateral coverage SHALL not be used as the covenant breach condition.
3. Breach/cure/termination language SHALL preserve canonical behavior:
   - first breach freezes draws
   - unresolved breach past `covenantCurePeriod` terminates draws and transitions into default workflow

### Requirement 4: Interest Model Alignment

Phase 4 interest requirements/design SHALL align to canonical linear accrual.

Acceptance criteria:
1. Compound interest requirements SHALL be removed or explicitly marked as post-v1.11 extension.
2. Core interest behavior SHALL be linear between checkpoints.
3. Repayment waterfall ordering SHALL remain `fees -> interest -> principal`.

### Requirement 5: Phase Dependency Consistency

Phase docs SHALL not block required reconciliation changes.

Acceptance criteria:
1. Any statement asserting “no modifications to prior phases” SHALL allow canonical reconciliation exceptions.
2. Phase 5 requirements/design SHALL include a dependency note that v1.11 reconciliation patches may touch Phase 1-4 docs before execution.

### Requirement 6: Phase 4 Task Completeness

Phase 4 SHALL include a `tasks.md` file equivalent in fidelity to Phases 1/2/3/5.

Acceptance criteria:
1. `tasks.md` SHALL exist under `.kiro/specs/synthesis-phase4/`.
2. It SHALL include implementable tasks tied to requirement IDs.
3. It SHALL include tests for trust gating, ACP sync, no-lock-in portability, covenant enforcement, collateral toggle, pooled flows, and governance.

### Requirement 7: Canonical Completion Gate

A gate SHALL be defined to mark `.kiro` phase set as v1.11-complete.

Acceptance criteria:
1. A traceability matrix SHALL map v1.11 Sections 4-17 to Phase 1-5 requirements/tasks.
2. The gate SHALL fail if any canonical section lacks owning requirement(s) or test task(s).
3. Differential portability obligations SHALL be explicitly represented for both compute adapters and ERC-8183 adapters.
