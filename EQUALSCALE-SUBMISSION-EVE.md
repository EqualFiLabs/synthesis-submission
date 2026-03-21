# EqualScale: Agentic Financing Infrastructure

**Alternate Submission Draft**

---

## What EqualScale Is

EqualScale is on-chain financing infrastructure for autonomous agents.

The problem it addresses is simple: agents can execute, but they still cannot natively borrow, draw capital, meter usage into debt, and repay under explicit financial rules. In practice, most "autonomous" agents are still economically dependent on a human operator, a pre-funded wallet, or a centralized platform whenever money starts moving.

EqualScale closes that gap.

It gives an agent with a verifiable identity a way to:
- request financing,
- receive approval from a lender or lender pool,
- draw against a bounded credit line,
- accrue debt deterministically,
- repay on-chain,
- and build a visible repayment history.

This is not a wrapper around an existing lending protocol. It is purpose-built infrastructure for agentic finance: agreements where the borrower may be an autonomous software actor, usage may be metered off-chain, and settlement still happens on-chain under explicit rules.

**EqualScale is not just compute financing.** Compute is one live and useful entrypoint, but the protocol is broader than compute. An agent can borrow for trades, services, deployments, asset acquisition, operating costs, or any other token-denominated need. The financing rails are general. Compute metering is one way of exercising them.

**Judge note:** review the specs in `specs/` alongside this document. They are part of the core evidence for the project, not supplemental marketing. They capture the architecture, phased implementation plan, and constraint-driven build process that made it possible to execute a five-phase project coherently in roughly two days of hackathon work.

---

## The Core Problem

Today, agents can act, but they cannot finance themselves.

That constraint shows up everywhere:
- an agent cannot borrow working capital to execute a strategy,
- an agent cannot open a bounded line of credit for services,
- an agent cannot cleanly convert off-chain usage into on-chain debt,
- an agent cannot accumulate a durable, inspectable repayment history tied to actual performance.

The result is fake autonomy. The intelligence may be real, but the economic agency is still rented from a human operator or centralized service.

EqualScale is designed to remove that boundary.

---

## What Has Been Proven

The system is already implemented as working machinery, not just a spec.

**Timeline clarity:** the EqualScale work represented in this submission was done during the Synthesis hackathon window, after the hackathon began on **March 13, 2026**. This is hackathon-built work, not a pre-existing product being lightly repackaged for submission.

### Live and tested provider path

The metered compute financing flow is implemented across multiple providers, with evidence depth varying by provider:
- **Venice** — live and demonstrated end to end: real inference call, usage polling, deterministic metering (32 rows → 2 aggregated items), and settlement pipeline execution. The initial lifecycle demo used the relayer's webhook mock path for settlement. Real on-chain settlement is now proven via the Phase 2 `TransactionSubmitter` proof run (`DEMO-EVIDENCE-CONSOLIDATED.md` Section 6), which submitted `registerUsage()` to Anvil and produced a verified tx hash (`0xae0ffaec...6e5bc8`, block 87, status: success).
- **Bankr** — live and demonstrated end to end: real inference call, final-pass metering, and settlement pipeline execution. Same real on-chain settlement proof (`0x30213593...656625`, block 88, status: success).
- **Runpod** — live activation and real job submission demonstrated; integration is end to end at the architecture level, but the captured run remained queued and did not complete settlement in-window
- **Lambda** — integrated and exercised through the relayer/provider path; live completion in the captured run was blocked by provider-side capacity rather than protocol or relayer design

For Venice and Bankr, the full loop has been exercised end to end:
- on-chain agreement creation,
- lender approval,
- agreement activation,
- provider provisioning,
- encrypted credential delivery,
- off-chain usage metering,
- on-chain debt registration,
- breach / termination handling,
- and repayment / closure.

RunPod and Lambda are integrated through the same relayer adapter architecture and are accepted at the contract level (`_isSupportedComputeProvider` accepts all four provider IDs), but their captured demo evidence does not include completed settlement — RunPod's job remained queued, and Lambda hit a provider-side capacity constraint.

### Pure financing is implemented and tested

EqualScale is not limited to compute usage conversion.

The `drawPrincipal` function in `AgenticAgreementFacet.sol` allows a borrower to draw capital directly against a credit line without provider-metered usage routing. This supports general financing use cases where debt is not tied to metered provider consumption. The function enforces credit limits, draw freezing, and borrower authorization, and is covered by unit and fuzz tests.

The on-chain Pure Financing demo (Anvil timewarp) exercises the full risk state machine: Active → Delinquent → Defaulted with real tx hashes. See `DEMO-EVIDENCE-CONSOLIDATED.md` Section 5.

### Proposal surface

The on-chain proposal layer exposes dedicated public entrypoints for all three financing modes:
- `createSoloComputeProposal(...)` — solo compute financing (also available via the legacy `createProposal(...)` alias)
- `createPooledComputeProposal(...)` — pooled compute financing
- `createPooledAgenticProposal(...)` — pooled agentic financing (no provider restriction)

All three are implemented and tested in `AgenticProposalFacet.sol`.

---

## Architecture

EqualScale is implemented as a set of Diamond facets on EqualFi.

This is not architectural theater. The point is to separate the financing lifecycle into explicit modules while preserving shared protocol storage and upgrade infrastructure.

The system includes dedicated surfaces for:
- proposal creation,
- lender approval,
- agreement activation and lifecycle management,
- compute usage registration,
- risk controls,
- collateral,
- pooled financing,
- agent identity and trust,
- encrypted mailbox delivery,
- and venue / ACP integration.

At a high level, the system has five layers:

1. **Proposal layer** — define the financing request
2. **Approval layer** — accept backing from a lender or pool
3. **Agreement layer** — activate, draw, repay, close
4. **Risk layer** — detect breaches, freeze draw, default, write off
5. **Identity / integration layer** — bind agreements to agent identity, venues, and encrypted payload delivery

The result is a financing state machine, not an ad hoc API workflow.

---

## How the Lifecycle Works

### 1. Proposal

An agent, or its operator, creates a proposal defining:
- agent identity,
- counterparty,
- settlement asset,
- requested credit amount,
- unit budget when relevant,
- expiry,
- provider or venue binding when relevant,
- and a hash of off-chain terms.

Proposals can now be created through explicit on-chain entrypoints for solo compute, pooled compute, and pooled agentic financing.

This creates an on-chain pending financing request.

### 2. Approval

A lender approves the proposal, or multiple lenders participate through pooled financing.

Optional terms can be attached, including:
- interest configuration,
- covenant checks,
- collateral requirements,
- trust / validation requirements,
- and fee parameters.

### 3. Activation

Once approved, the borrower activates the agreement.

Activation does three important things:
- encumbers lender capital,
- instantiates the agreement with its configured terms,
- and opens a live credit line for the borrower.

### 4. Draw / Usage Registration

The protocol supports two draw modes:

**Metered usage** (`registerUsage`): the relayer measures actual provider usage and registers it on-chain, converting off-chain consumption into deterministic on-chain debt under pre-agreed pricing rules.

**Direct draw** (`drawPrincipal`): the borrower draws capital directly against the credit line without provider-metered usage routing. This supports general financing use cases — trades, services, operating capital — where debt is not tied to metered provider consumption.

Both modes enforce the agreement's **credit limit**. Metered usage additionally enforces a **unit limit**. If either bound is exceeded, the transaction reverts. Draw freezing and termination apply to both modes.

### 5. Repayment

The borrower repays on-chain.

Repayment is applied in strict order:
1. fees,
2. interest,
3. principal.

As principal is repaid, encumbered lender capital is released.

### 6. Closure

Once debt is fully cleared, the agreement can be closed and remaining encumbrance is released.

---

## Risk and Default

EqualScale has an explicit risk state machine:

`Active → Delinquent → Defaulted → WrittenOff`

A cured agreement can also return to a healthy path and ultimately close.

This matters because agent financing needs bounded exposure, not vague promises.

The risk machinery includes:
- delinquency detection,
- draw freezing,
- default handling,
- write-off accounting,
- pooled loss attribution,
- and circuit breakers for sensitive operation classes.

That turns the system into an actual financing protocol rather than a compute billing wrapper.

---

## Why This Is More Than Compute Financing

Compute usage metering is the easiest way to demonstrate the loop end to end, but it is not the scope boundary.

The deeper claim is:

**an agent should be able to enter a bounded financial agreement on-chain, draw value, and repay under enforceable rules.**

That value can correspond to:
- inference spend,
- software services,
- delegated work,
- operational capital,
- direct token-denominated borrowing,
- or any other financed activity that can be bounded, monitored, and settled.

What matters is the agreement framework:
- explicit proposal,
- lender approval,
- bounded draw,
- risk controls,
- deterministic repayment,
- visible history.

That is what makes agent activity financeable.

---

## Identity and Reputation

EqualScale integrates agent identity and trust through ERC-8004-style primitives.

That matters because undercollateralized agent credit only becomes legible when lender decisions can reference something more durable than a wallet balance.

The system supports:
- binding an agreement to an agent identity,
- configuring trust requirements,
- validating against those requirements before activation,
- and recording negative reputation outcomes on default / write-off paths.

Over time, this creates the foundation for reputation-backed credit markets for agents.

---

## Encrypted Delivery: The Mailbox Model

EqualScale includes an on-chain encrypted mailbox flow for credential handoff.

The borrower can publish an encrypted payload such as an agent public key. The relayer can then encrypt provider credentials to that key and publish the resulting ciphertext on-chain.

The architectural point is simple:

**the chain is the mailbox.**

That removes the need for a trusted off-chain message broker to deliver credentials between infrastructure operator and agent. The relayer may provision access, but it does not need to remain a permanent trusted transport layer for secret delivery.

For agent systems, where credential handoff is usually one of the weakest parts of the stack, this matters.

---

## The Relayer Today

The current off-chain relayer is centralized. That is a conscious hackathon-stage tradeoff, not a hidden dependency being hand-waved away.

**Post-hackathon direction:** the relayer is intended to be decentralized after the hackathon. Judges should review `mailbox-relayer/DECENTRALIZED-DESIGN.md` for the planned control-plane, data-plane, and settlement architecture that removes the single-operator assumption.

Today it is responsible for:
- listening for agreement lifecycle events,
- provisioning provider access,
- encrypting and publishing credentials,
- polling provider usage,
- registering usage on-chain,
- and terminating access when agreements breach or close.

It has adapters for Venice, Bankr, Runpod, and Lambda, and the same relayer architecture supports provisioning, metering, settlement, and termination across those provider surfaces.

This is enough to prove the full financing loop between on-chain agreements and off-chain service delivery.

### Reproducibility note
The hackathon repo also contains a local full-stack lifecycle skill (`hackathon/SKILL.md`) that documents how to deploy the stack on Anvil and exercise provider-backed flows. That skill is an operator runbook. This submission repo is packaged primarily as judge-facing evidence and code references rather than a one-command demo environment.

Provider-backed reproducibility also depends on external API credentials and provider-side availability. Venice and Bankr were exercised live; Runpod and Lambda are integrated and tested, with live execution subject to credentials and provider capacity.

---

## Current Limitations

The interesting question is not whether there are limitations. There are. The important question is whether they are honestly scoped.

### Provider key management is uneven
Venice supports clean programmatic key creation. Other providers, such as Bankr, can require more centralized credential handling, including managed key-pool patterns. That is a provider constraint, not a protocol constraint.

### Some provider constraints are operational, not architectural
Lambda capacity availability can prevent a live run even when the integration path itself is functioning correctly. That should not be confused with protocol incompleteness.

### The relayer is still a single-operator service
That is acceptable for a hackathon proof of operation, but not the final form. The intended next step after the hackathon is relayer decentralization, with the planned architecture documented in `mailbox-relayer/DECENTRALIZED-DESIGN.md`.

### Compute remains the cleanest demo path, not the scope boundary
Compute is the easiest path to inspect end to end because it naturally exercises provisioning, usage metering, debt registration, and termination. The financing framework is broader than compute. A non-metered direct-capital draw path (`drawPrincipal`) is now implemented and tested in `AgenticAgreementFacet.sol`, allowing borrowers to draw capital without provider-metered usage routing. Both `MeteredUsage` and `DirectDraw` agreement modes are supported.

---

## What Has Been Built

EqualScale is not just a concept note.

The shipped system includes:
- on-chain facets for proposal, approval, agreement management, risk, collateral, pooled financing, identity, and integration,
- explicit on-chain proposal entrypoints for solo compute, pooled compute, and pooled agentic financing,
- contract-level support for all four providers (Venice, Bankr, RunPod, Lambda),
- both metered-usage and direct-draw capital paths (`registerUsage` and `drawPrincipal`),
- an off-chain relayer with provider adapters and durable state,
- an SDK for encrypted mailbox payloads,
- and 823 passing tests across lifecycle, security, fuzz, invariant, and integration suites.

The important claim is not that every edge is finalized. The important claim is that the core loop exists as working machinery rather than diagrams.

---

## Why It Matters

If agents are going to become real economic actors, they need more than inference and orchestration.

They need access to capital under rules.

Without that, agent autonomy stays superficial. The model may choose, the workflow may execute, but the financial boundary remains owned by a human operator or centralized platform.

EqualScale is an attempt to build the missing layer: financing rails for autonomous agents that are explicit, auditable, bounded, and composable on-chain.

The live compute-financing flow demonstrates one working wedge. The larger opportunity is agent credit itself.

That is the bet behind EqualScale.

---

## Track-Specific Notes

### Venice / Private Agents, Trusted Actions
EqualScale fits this track by turning private or semi-private agent work into financeable activity under explicit rules. In the current system, Venice serves as an inference rail that can sit behind a bounded financing agreement, allowing an agent to consume paid inference without requiring an always-preloaded operator wallet.

**DIEM Inference Lending Extension** — We have designed a dedicated inference-financing path for Venice's DIEM credit system. The full spec is in `diem-inference-lending-spec.md`. The core thesis:

- DIEM holders who are not using their full daily $1/DIEM allocation can deposit into a lending pool
- Borrowers post USDC collateral and receive scoped Venice child API keys (not DIEM principal)
- Usage is metered per key and converts to USDC-denominated debt
- Default triggers key revocation first, then collateral recovery
- The protocol controls DIEM custody; borrowers only receive bounded inference access

This extends the same financing framework into a Venice-native product where the capital asset is DIEM credits, not generic USDC. It is a concrete demonstration of how EqualScale's general financing rails can specialize for venue-specific capital structures without forking the underlying agreement model.

The important point for this track is that trusted action is not treated as a vague orchestration story. It is tied to a credit framework with approval, limits, metering, repayment, and failure handling.

### Bankr / Best Bankr LLM Gateway Use
EqualScale fits the Bankr track by treating Bankr as a live inference-provider rail inside an on-chain financing lifecycle. That means an agent can access Bankr-backed inference under a bounded agreement, with usage converted into explicit debt and settled on-chain under pre-agreed rules. The relevant contribution here is not just “we called Bankr.” It is that Bankr usage is integrated into a broader financial control plane for agents.

### ERC-8183 Open Build
EqualScale fits this track through full ACP / ERC-8183 lifecycle integration in code. The system links financing agreements to ACP jobs, supports adapter-based venue routing, and synchronizes job outcomes like completion, rejection, and refund handling back into agreement accounting. The point is that ACP becomes more than a coordination rail. In EqualScale, it becomes finance-aware infrastructure.

### ERC-8004 / Agents With Receipts
EqualScale fits this track by binding financing agreements to verifiable agent identity and trust surfaces. ERC-8004-style identity makes it possible to evaluate borrowers as agents rather than anonymous wallets, and to attach durable history to financing outcomes such as repayment, delinquency, or write-off. In that sense, the “receipt” is not just a transaction trace. It is an inspectable financing history tied to agent identity.

### Synthesis Open Track
EqualScale fits the open track because it combines the full stack into one coherent system: agent identity, financing, inference access, compute access, encrypted delivery, risk state transitions, and on-chain settlement. The broader claim is that agents should not only be able to act. They should be able to enter bounded financial agreements, draw resources, repay obligations, and build durable economic history.

## Submission Summary

**Project:** EqualScale  
**Category:** Agentic financing infrastructure  
**Hackathon timing:** built during Synthesis after the hackathon opened on March 13, 2026  
**Core contribution:** On-chain credit and settlement rails for autonomous agents  
**Proven path:** Metered compute financing (Venice/Bankr E2E, RunPod/Lambda integrated), plus direct-draw capital path (`drawPrincipal`) with full risk lifecycle  
**Review note:** judges should review the specs in `specs/` as part of the core evidence trail for how a five-phase project was designed and executed in roughly two days  
**Long-term direction:** General-purpose financing agreements for autonomous agents with identity, bounded risk, encrypted delivery, and on-chain repayment history
