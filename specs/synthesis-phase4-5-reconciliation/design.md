# Design Document — Synthesis Phase 4.5 Reconciliation

## Overview

Phase 4.5 is a reconciliation layer that restores a single documentation source of truth between `.kiro` phase plans and canonical v1.11.

The target is to eliminate implementation ambiguity before further execution work.

## Reconciliation Strategy

1. Normalize all event signatures to canonical v1.11 Section 11.
2. Normalize relayer trigger coverage to orchestration trigger set.
3. Normalize covenant semantics to net-draw period accounting.
4. Normalize interest semantics to linear accrual baseline.
5. Add missing execution artifacts (`synthesis-phase4/tasks.md`).
6. Add explicit traceability and a hard completion gate.

## Patch Domains

### Domain A: Event Contract

Scope:
- Phase 1 and Phase 2 docs.

Invariant:
- One event schema only; no local variants.

### Domain B: Risk Trigger Contract

Scope:
- Phase 2 docs.

Invariant:
- Listener trigger set is sufficient for provisioning and kill-switch lifecycle.

### Domain C: Covenant Contract

Scope:
- Phase 4 docs.

Invariant:
- Covenant breach is payment-vs-net-draw based, not collateral-ratio based.

### Domain D: Interest Contract

Scope:
- Phase 4 docs.

Invariant:
- Linear accrual is the v1.11 baseline behavior.

### Domain E: Phase Dependency Contract

Scope:
- Phase 5 docs.

Invariant:
- Reconciliation patches are allowed when needed to restore canonical conformance.

## Verification Plan

1. Static drift scan for old signatures/phrases:
- `providerKey` in mailbox/activation events
- ratio-based covenant formula text
- compound-interest baseline language

2. Traceability gate:
- every canonical v1.11 section (4-17) must map to at least one phase requirement and one phase task.

3. Decision output:
- `PASS`: no canonical section missing.
- `FAIL`: at least one section unowned or only partially covered without explicit deferral.
