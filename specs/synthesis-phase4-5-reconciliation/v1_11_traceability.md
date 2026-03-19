# v1.11 Traceability Matrix (Phase 4.5 Baseline)

This matrix maps canonical `agentic-financing-spec.md` Sections 4-17 to `.kiro` phase ownership.

Status keys:
- `covered`: requirements + tasks exist and align semantically
- `partial`: requirements/tasks exist but drift from canonical semantics
- `missing`: no owning requirement or no execution task

| Canonical Section | Owner Phase(s) | Status | Notes |
|---|---|---|---|
| 4 Shared Primitives | 1, 4 | covered | Core primitives are now provider-agnostic in Phase 1/4 docs and aligned to canonical baseline. |
| 5 State Machines | 1, 4, 5 | covered | Covenant/default flows now use canonical period accounting + cure/termination semantics. |
| 6 Solo Agentic Financing | 1 | covered | Baseline proposal/activation/repayment flows present. |
| 7 Pooled Agentic Financing | 4, 5 | covered | Governance + pooled distribution documented. |
| 8 Solo Compute/Inference Lending | 1, 3 | covered | Metered usage and adapter routing captured. |
| 9 Pooled Compute/Inference Lending | 4, 5 | covered | ACP sync + pooled risk/test coverage mapped in requirements and tasks. |
| 10 Risk and Recovery | 4, 5 | covered | Circuit breakers + write-off + covenant/default handoff aligned. |
| 11 Canonical Events | 1, 2, 4, 5 | covered | Activation/mailbox schemas now canonical and relayer mapping updated. |
| 12 Contract Architecture | 1, 4, 5 | covered | Facet mapping and execution tasks now present (including Phase 4 tasks). |
| 13 Storage Layout | 1, 4, 5 | covered | Core storage fields represented across phases. |
| 14 Canonical Policy Defaults | 4, 5 | covered | Covenant/interest defaults now documented in canonical baseline form. |
| 15 Migration and File Policy | 4.5 | partial | Reconciliation process is documented; ongoing hygiene still required for future edits. |
| 16 Implementation Sequence | 1, 2, 3, 4, 5 | covered | Sequence unblocked with updated Phase 2 triggers and new Phase 4 tasks. |
| 17 Success Criteria | 4.5 | covered | Completion gate criteria are explicit and executable. |

## Blocking Gaps

1. No blocking gaps remain for the `v1.11-doc-pass` gate criteria.
2. Section 15 remains intentionally `partial` as ongoing documentation-hygiene process scope, not a canonical behavior gap.

## Gate Definition

`v1.11-doc-pass = true` only when:
1. No `missing` status rows remain.
2. No `partial` status rows remain for Sections 4, 5, 10, 11, 16.
3. Phase 4 has a complete `tasks.md` with requirement-linked test tasks.
4. Phase 2 trigger list includes all orchestration enforcement events.
5. A final drift scan finds no stale event signatures or ratio-covenant text.
