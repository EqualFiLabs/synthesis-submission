# EqualScale — Synthesis Hackathon Submission

EqualScale is agentic financing infrastructure built for autonomous agents.

It gives agents a way to:
- establish identity,
- request financing,
- receive approval from a lender or lender pool,
- draw against bounded credit,
- meter usage into debt,
- repay on-chain,
- finance work through ACP,
- and build a visible financial history.

This submission is centered on one core claim:

**agents should not just be able to execute work — they should be able to finance work.**

EqualScale combines:
- **ERC-8004** for agent identity and trust
- **ERC-8183 / ACP** for agent job orchestration and commerce flows
- **EqualFi** as the on-chain financing substrate
- **Venice** and **Bankr** as current inference-provider rails
- **RunPod** and **Lambda** as compute-provider integrations for broader execution portability

---

## Judge Quick-Start

**If you have 5 minutes** — read `EQUALSCALE-SUBMISSION-EVE.md` (main technical overview) and `DEMO-EVIDENCE-CONSOLIDATED.md` (consolidated lifecycle evidence with real provider outputs).

**If you have 15 minutes** — also read `PURE-FINANCING-TIMEWARP-OUTPUTS.md` (on-chain lifecycle from usage through default with real tx hashes) and `LIFECYCLE-OUTPUTS.md` (full Venice end-to-end with 32 metered usage rows).

**If you want to verify the code** — the three codebases are:

| Component | Path | Language | Lines | Tests |
|-----------|------|----------|-------|-------|
| EqualFi (on-chain) | `EqualFi/` | Solidity | ~4,300 (EqualScale facets) | 38 test files, ~12,600 lines |
| Mailbox Relayer | `mailbox-relayer/` | TypeScript | ~9,900 | 40 test files, ~8,400 lines |
| Mailbox SDK | `mailbox-sdk/` | TypeScript | ~120 | 1 test file, 9 tests |

To run tests locally:
```bash
# SDK (fast, no native deps)
cd mailbox-sdk && npx vitest run

# Relayer (requires: pnpm approve-builds for native modules first)
cd mailbox-relayer && pnpm test

# Solidity (requires foundry, slow first build due to aave-v3 deps)
cd EqualFi && forge test
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EqualScale Architecture                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │  ERC-8004    │    │  ERC-8183    │    │   Governance         │  │
│  │  Identity &  │    │  ACP Job     │    │   Proposals/Voting   │  │
│  │  Reputation  │    │  Lifecycle   │    │   Circuit Breakers   │  │
│  └──────┬───────┘    └──────┬───────┘    └──────────┬───────────┘  │
│         │                   │                       │              │
│  ┌──────▼───────────────────▼───────────────────────▼───────────┐  │
│  │              EqualFi Diamond (EIP-2535)                       │  │
│  │  ┌─────────────┐ ┌──────────────┐ ┌────────────────────────┐ │  │
│  │  │  Proposal   │ │  Agreement   │ │   Risk Management      │ │  │
│  │  │  & Approval │ │  Lifecycle   │ │   Delinquency/Default  │ │  │
│  │  └─────────────┘ └──────────────┘ │   Write-Off/Recovery   │ │  │
│  │  ┌─────────────┐ ┌──────────────┐ └────────────────────────┘ │  │
│  │  │  Compute    │ │  Pooled      │ ┌────────────────────────┐ │  │
│  │  │  Usage      │ │  Financing   │ │   Collateral Manager   │ │  │
│  │  │  Metering   │ │  Pro-rata    │ │   Interest & Covenants │ │  │
│  │  └──────┬──────┘ └──────────────┘ └────────────────────────┘ │  │
│  └─────────┼────────────────────────────────────────────────────┘  │
│            │                                                       │
│  ┌─────────▼────────────────────────────────────────────────────┐  │
│  │              Encrypted Mailbox (on-chain bytes)               │  │
│  │         ECIES secp256k1 credential handoff channel            │  │
│  └─────────┬────────────────────────────────────────────────────┘  │
│            │                                                       │
├────────────┼───────────────────────────────────────────────────────┤
│  OFF-CHAIN │                                                       │
│  ┌─────────▼────────────────────────────────────────────────────┐  │
│  │                    Mailbox Relayer                            │  │
│  │  Event Listener → Metering → Settlement → TX Submitter       │  │
│  │  Kill-Switch enforcement    SQLite durable state (WAL)       │  │
│  └─────────┬────────────────────────────────────────────────────┘  │
│            │                                                       │
│  ┌─────────▼────────────────────────────────────────────────────┐  │
│  │                   Provider Adapters                           │  │
│  │  ┌─────────┐  ┌────────┐  ┌─────────┐  ┌────────────────┐   │  │
│  │  │ Venice  │  │ Bankr  │  │ RunPod  │  │    Lambda      │   │  │
│  │  │ (infer) │  │(infer) │  │(compute)│  │   (compute)    │   │  │
│  │  └─────────┘  └────────┘  └─────────┘  └────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Pre-Existing vs Hackathon-Built Code

EqualFi is an existing protocol codebase. The **EqualScale** module (all files under `src/equalscale/`, `src/libraries/LibAgenticStorage.sol`, and the corresponding test files under `test/agentic/`, `test/invariant/`, `test/differential/`, `test/stress/`, `test/security/`) was built during the hackathon window (March 13–18, 2026).

The mailbox-relayer and mailbox-sdk are entirely new codebases built for this hackathon.

| Component | Status | Evidence |
|-----------|--------|---------|
| `EqualFi/src/equalscale/` (18 facets, ~4,300 lines) | **Hackathon-built** | `conversationLog.md` traces day-by-day development |
| `EqualFi/test/agentic/` + invariant/differential/stress/security (~12,600 lines) | **Hackathon-built** | Mirrors facet development timeline |
| `mailbox-relayer/` (34 source files, ~9,900 lines) | **Hackathon-built** | Entirely new repo |
| `mailbox-sdk/` (2 source files, ~120 lines) | **Hackathon-built** | Entirely new repo |
| `EqualFi/` base (Diamond proxy, ERC infrastructure) | **Pre-existing** | Foundation the EqualScale module extends |
| `specs/` design documents | **Hackathon-built** | Phase-by-phase design artifacts |

See `conversationLog.md` for the full human-agent build log showing iterative development between Matt and Eve from March 13–18.

---

## What We Built

EqualScale is not a wrapper around an existing lending app. It is a dedicated financing layer for autonomous agents.

The system supports:
- financing proposals,
- lender approval,
- agreement activation,
- bounded draw / usage registration,
- repayment,
- delinquency and default handling,
- pooled financing,
- solo financing,
- encrypted mailbox delivery,
- and ACP-linked job lifecycle integration.

In practical terms, this means an agent can:
- open a financing agreement,
- create or fund work through ACP,
- route task budgets through a credit line,
- borrow for compute,
- borrow for non-compute capital needs,
- and settle outcomes back into agreement accounting.

That turns ACP from a coordination rail into a **credit-backed coordination rail**.

---

## Financing Modes

EqualScale is designed to support more than one kind of agent financing.

### Solo financing
A single lender backs a specific agent agreement.
This is the cleanest path for direct underwriting, bounded exposure, and one-to-one financing relationships.

### Pooled financing
Multiple lenders contribute capital to a shared pool that can back agent agreements.
This is the path toward portfolio-style agent credit and broader capital formation.

### Compute financing
An agent consumes off-chain provider resources and that usage is converted into deterministic on-chain debt.
This is the clearest live demo path today because it exercises metering, settlement, repayment, and termination.

### Pure financing
EqualScale is not limited to compute.
An agent can also borrow token-denominated capital for non-compute purposes such as:
- paying another agent,
- funding a strategy,
- covering operational costs,
- deploying infrastructure,
- or financing a task budget directly.

That matters because the protocol is meant to finance **agent activity generally**, not just inference spend.

---

## Proposal Types / Surfaces

The design spans multiple proposal and agreement surfaces.

At a high level, EqualScale covers:
- **solo compute financing**
- **pooled compute financing**
- **pooled agentic financing**
- broader pure-financing flows built on the same agreement and risk rails

The current public proposal interface exposes `createProposal(...)` for the live solo-compute path.
Pooled compute and pooled agentic proposal types exist in the model and test surface, but are not yet exposed through dedicated public creation entrypoints in this checkout.

From the contract surface:
- current on-chain proposal validation recognizes the inference-provider ids `venice` and `bankr`
- broader pooled and non-compute financing behavior is represented in the protocol model, pooled financing machinery, and tests
- first-class non-metered direct-capital entrypoints remain post-hackathon work

The important point is that EqualScale is not a one-mode billing wrapper.
It is a general financing framework where compute is the live wedge today, and broader financing paths are part of the protocol direction and partially tested model.

---

## Why This Matters

Today most agents are economically dependent on one of three things:
- a pre-funded wallet,
- a human operator,
- or a centralized platform.

That means most “autonomous” agents still cannot:
- borrow,
- manage bounded debt,
- pay for services through credit,
- finance downstream work,
- or accumulate durable repayment history.

EqualScale is designed to close that gap.

The long-term goal is not just compute billing for AI.
It is **real financing rails for autonomous economic actors**.

---

## Core Architecture

EqualScale is implemented as Diamond facets on EqualFi.

Major components include:
- `AgenticProposalFacet` — proposal creation and cancellation
- `AgenticApprovalFacet` — lender approval flows
- `AgenticAgreementFacet` — activation, repayment, closure
- `ComputeUsageFacet` — metered usage into on-chain debt
- `AgenticRiskFacet` — delinquency, default, write-off
- `PooledFinancingFacet` — multi-lender capital backing
- `ERC8004Facet` — agent identity / validation / reputation hooks
- `ERC8183Facet` — ACP job lifecycle integration
- `AdapterRegistryFacet` — venue adapter registration and routing
- `AgenticMailboxFacet` — encrypted on-chain payload delivery

---

## ACP / ERC-8183 Integration

ACP is not bolted on as marketing.
It is implemented directly in code.

EqualScale includes:
- ACP job creation tied to active agreements
- provider assignment
- budget funding through agreement credit
- terminal state handling for completed / rejected / expired jobs
- refund accounting back into the financing agreement
- venue adapter routing for portability

This enables a powerful flow:
1. an agent establishes identity,
2. enters a financing agreement,
3. opens an ACP job,
4. assigns another agent or provider,
5. funds the job from its credit line,
6. and settles outcomes back into agreement accounting.

That is the heart of the submission.

---

## Provider / Execution Rails

The current implementation spans multiple provider / execution rails:
- **Venice**
- **Bankr**
- **RunPod**
- **Lambda**

These matter because EqualScale is not just theoretical financing.
It is designed to connect financing agreements to real execution environments.

What the codebase shows today:
- on-chain proposal validation currently recognizes **Venice** and **Bankr** provider ids
- those map cleanly to the **inference** side of the stack
- the relayer implements provider adapters for **Venice**, **Bankr**, **RunPod**, and **Lambda**
- **RunPod** and **Lambda** cover the **compute** side of the stack
- the provider registry resolves across all four providers
- policy routing maps dedicated compute toward **Lambda** and burst compute toward **RunPod**
- unit normalization and differential tests are written to preserve accounting portability across providers

So the accurate framing is:
- **Venice** and **Bankr** = inference rails
- **RunPod** and **Lambda** = compute rails
- the adapter model allows broader execution portability over time

The architecture is deliberately designed to avoid lock-in.
ACP venues and provider rails can be swapped or extended without redesigning the financing core.

---

## What Is Live vs What Is Planned

### Implemented now
- on-chain financing lifecycle
- metered usage registration
- repayment and risk state machine
- solo financing flows
- pooled financing machinery
- ERC-8004 identity hooks
- ERC-8183 ACP integration in code
- adapter registry architecture
- mailbox-based encrypted payload delivery
- relayer/provider integrations
- explicit proposal entrypoints for solo compute, pooled compute, and pooled agentic financing
- Venice and Bankr as current inference rails
- RunPod and Lambda as implemented compute adapters

### Still directional / post-hackathon
- fuller relayer decentralization
- broader production hardening
- additional non-metered direct-capital paths as first-class product surfaces

We are being explicit here because we want judges and builders to know what is shipped versus what is next.

---

## Repository Guide

**Primary reading (for judges):**
- `EQUALSCALE-SUBMISSION-EVE.md` — main technical overview of the submission
- `DEMO-EVIDENCE-CONSOLIDATED.md` — consolidated lifecycle evidence with analysis
- `conversationLog.md` — human/agent build log (Mar 13–18)
- `PURE-FINANCING-TIMEWARP-OUTPUTS.md` — on-chain lifecycle with real tx hashes

**Implementation:**
- `EqualFi/` — on-chain contracts (Diamond facets, tests, deployment scripts)
- `mailbox-relayer/` — off-chain relayer, provider adapters, settlement pipeline
- `mailbox-sdk/` — ECIES encrypted mailbox SDK

**Operational reference (not required reading):**
- `SKILL.md` — operator runbook for running the full stack locally
- `ENTRYPOINT-DEPLOYMENT.md` — ERC-4337 local deployment guide
- `LOCAL-DEPLOY.md` — local Anvil address reference

**Directional / post-hackathon (no implementation in submission):**
- `DECENTRALIZED-DESIGN.md` — future relayer decentralization design
- `diem-inference-lending-spec.md` — DIEM inference lending extension spec
- `specs/` — phase-by-phase design artifacts

---

## Submission Framing

This project sits at the intersection of:
- autonomous agents,
- on-chain credit,
- identity,
- ACP-native work execution,
- compute financing,
- and broader financing design.

The simplest way to describe it is:

**EqualScale makes autonomous agents financeable.**

Not just executable.
Not just schedulable.
Financeable.

---

## Team

**Matt / Hooftly.eth** — builder, protocol architect, operator  
**Eve** — agent collaborator, technical planning, writing, execution support

---

## Governance Note: Diamond Upgrade Path

EqualScale supports timelocked governance for diamond upgrades via `AdminGovernanceFacet.executeDiamondCut()`, which enforces `owner OR timelock` access control.

**Current state (hackathon/demo):**
- `DiamondCutFacet.diamondCut()` remains owner-only for testing flexibility
- This creates a bypass path that would not exist in production mainnet

**Production intent:**
- Remove `DiamondCutFacet` or route through `enforceOwnerOrTimelock()`
- Deploy behind OpenZeppelin `TimelockController` with enforced delay
- All admin actions (parameter changes, facet upgrades) would route through timelock

The architecture supports censorship-resistant governance. The bypass exists for hackathon iteration speed, not as a design choice for mainnet.

---

## One-Line Summary

EqualScale is on-chain credit infrastructure for autonomous agents, combining **ERC-8004 identity**, **ERC-8183 / ACP job orchestration**, **Venice / Bankr inference rails**, **RunPod / Lambda compute rails**, and **solo, pooled, and compute financing paths** so agents can do more than act — they can finance action.
