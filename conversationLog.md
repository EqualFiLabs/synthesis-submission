# Synthesis Hackathon — Cleaned Conversation Log (Mar 13–18, 2026)

## Summary

From Mar 13 through Mar 18, Matt and Eve used OpenClaw as a working environment to design, build, test, and frame an agentic financing submission for Synthesis. The collaboration focused on three connected surfaces:

1. **EqualFi / EqualScale** — onchain agreement, financing, and settlement logic
2. **mailbox-relayer** — offchain encrypted mailbox, provider orchestration, and durable settlement machinery
3. **mailbox-sdk** — TypeScript SDK for envelope transport, encryption/decryption helpers, and integration ergonomics

The work was not a generic hackathon prototype sprint. The core pattern was: define the architecture, implement the real rails, test them locally, harden the relayer and contract surfaces, then shape the result into a submission judges can inspect.

By the end of this period:
- mailbox-relayer had moved from scaffold to production-shaped infrastructure
- mailbox-sdk had a cleaner, frozen API surface with tests and release hygiene
- EqualFi had added the key EqualScale / agentic financing facets, tests, and naming alignment
- Synthesis submission requirements were re-checked against the live platform docs
- a dedicated `submission/` umbrella repo was initialized to prepare a sanitized submission surface
- the team confirmed that a **draft** project can be created now, with publishing gated later by self-custody requirements

---

## Collaboration Pattern

The human-agent collaboration looked like this:
- Matt set direction, constraints, and product judgment
- Eve translated that into implementation plans, code changes, test steps, repo organization, submission framing, and artifact cleanup
- When new platform or ecosystem constraints appeared, Eve fetched docs, compared them against current repo state, and updated the plan
- The work alternated between concrete engineering, strategic naming/product choices, and submission preparation

This was not a single prompt / single output flow. It was iterative build coordination across contracts, relayer, SDK, docs, and packaging.

---

## Mar 13 — Engineering Sprint Across the Stack

### mailbox-sdk
The first day included tightening the mailbox SDK so the transport and encryption story was cleaner and more deterministic.

Key outcomes:
- added envelope transport helpers
- added deterministic test vectors
- improved validation behavior around decrypt flows
- updated docs and package surface
- cut a cleaner versioned package boundary

This mattered because the SDK is the glue between onchain mailbox semantics and offchain encrypted payload handling.

### mailbox-relayer
The relayer moved quickly from scaffold to a real vertical slice.

Key outcomes:
- scaffolded the service
- defined a canonical envelope schema aligned with the SDK
- added compute provider adapter interfaces and provider-specific stubs
- implemented a mocked vertical flow for end-to-end testing
- began and delivered Phase 2 relayer work:
  - live Venice adapter
  - durable SQLite state
  - onchain event ingestion
  - deterministic metering
  - kill-switch enforcement
  - settlement pipeline
  - admin auth and structured logging

The important product decision here was to prioritize **real reliability and settlement machinery** instead of over-optimizing for demo theatrics.

### EqualFi / EqualScale contracts
Onchain work advanced in parallel.

Key outcomes:
- scaffolded shared storage, types, and interfaces for agentic financing
- implemented agreement lifecycle logic and tests
- added compute usage metering facet
- implemented mailbox facet with encrypted payload support
- added encryption pubkey registry facet
- added proposal approval flows and tests
- exported ABIs and updated event surfaces for relayer integration

A local end-to-end drill against the relayer passed, which was the first strong signal that the onchain/offchain architecture was cohering.

---

## Mar 14 — Integration Docs, Provider Surface, and Broader Architecture

The second day extended the system in two directions: provider integration realism and protocol architecture depth.

### Integration research and docs
Comprehensive LLM-ready integration docs were assembled for external compute providers, especially:
- Lambda Labs
- Runpod

These docs captured API references, handler behavior, instance choices, pricing context, and integration notes that could directly inform relayer/provider adapter implementation.

### Lido / yield integration thinking
A separate thread explored how yield-bearing collateral or treasury behavior might integrate into the broader system design. A concrete primitive (`LidoBudget.sol`) was proposed as a way to isolate principal and expose only spendable yield through constrained permissions.

This did not become the center of the Synthesis submission, but it sharpened how the team thought about bounded financial rights, session keys, and controlled spending surfaces.

### EqualFi / EqualScale contracts continued
Onchain work expanded into:
- collateral manager flows
- linear interest accrual and fee scheduling
- pooled financing and governance-adjacent facets
- circuit breaker and stress/security preparation

This made the contract side read less like a narrow demo and more like a serious financing state machine under active hardening.

---

## Mar 15 — Strategy, Positioning, and Housekeeping

This day mixed architecture refinement with product and organizational strategy.

### Strategic decisions
Matt and Eve refined the separation between:
- the **protocol** as uncapturable infrastructure
- the **DevCo / service layer** as the fundable and revenue-bearing surface

That distinction shaped both how the work should be built and how it should be presented.

Key conclusions:
- keep the protocol permissionless and uncapturable
- avoid governance-token-shaped shortcuts
- use the company/service layer for practical monetization and runway
- keep shipping rather than waiting for institutional validation

### Supporting work
- backups were completed
- external reading informed the strategy discussion
- internal positioning continued to sharpen around agent-native financial infrastructure rather than generic AI tooling

---

## Mar 16 — Policy, Decisions, and Submission Framing

This day pulled the technical work into a more explicit strategic frame.

### Capture-risk discussion
Matt and Eve discussed the broader market environment, including the closing window for genuinely permissionless financial infrastructure and the way venture narratives can push projects toward captured forms.

This reinforced the submission posture: the work should be framed as infrastructure that reduces dependence on intermediaries, not as a governance token story or a standard SaaS wrapper.

### Mentorship and timing
Arbitrum mentorship acceptance was noted as strategically important. It strengthened the view that the hackathon submission should be good enough to open doors, not just satisfy a deadline.

### Submission framing question
A specific question surfaced about what `conversationLog` should be for Synthesis.

The conclusion was:
- a raw export alone is not ideal
- a curated narrative is more judge-readable
- raw logs can still be attached or preserved for auditability

That conclusion directly led to the creation of cleaner submission-facing artifacts like this one.

---

## Mar 17 — Rechecking Live Synthesis Requirements

After the core engineering push, Eve re-checked the live Synthesis docs and current team state rather than relying on memory.

### Fresh platform requirements confirmed
The updated Synthesis registration and submission docs emphasized:
- structured registration metadata
- explicit `agentHarness` and `model`
- a team-owned project model
- required `conversationLog`
- required `submissionMetadata`

This mattered because it changed the submission from a simple project card into a more inspectable record of how the human and agent actually built the project.

### Team state confirmed
Eve revalidated the live Synthesis team and project state against the platform and confirmed:
- Eve remained registered in Synthesis
- the team existed and was valid
- the team currently had **no project yet**
- the exact `POST /projects` draft creation path was available

A key practical point was confirmed: **draft creation is allowed before self-custody transfer; publishing is not.**

### Track selection finalized
The canonical submission track list was identified and saved so the project could be drafted against the right targets rather than improvised at the last minute.

This was the point where the work shifted from “we have build artifacts” to “we know the exact submission surface and can start packaging for judges.”

---

## Mar 18 — Submission Packaging and Sanitization

The work turned directly toward submission readiness.

### Current submission framing
A clear messaging rule was set for public materials:
- use mechanism-first, universal framing
- keep public-facing copy, specs, and judge-facing materials focused on implemented architecture, financing flows, settlement logic, and the decentralization path

This affected how the submission should be written, what should be omitted, and how EqualFi / EqualScale should be explained.

### Draft payload and submission planning
Eve fetched the live Synthesis skill docs again, confirmed the existence of draft submission support, and drafted an example project payload showing the required fields:
- `teamUUID`
- `name`
- `description`
- `problemStatement`
- `repoURL`
- `trackUUIDs`
- `conversationLog`
- `submissionMetadata`

This gave the team a concrete shape for what must exist before judges can meaningfully review the project.

### Umbrella submission repo created
To prepare a cleaner public-facing artifact, a new workspace directory was created:
- `submission/`

It was initialized as a new git repo and wired to the three core project repos as submodules:
- `EqualFi`
- `mailbox-relayer`
- `mailbox-sdk`

The submodules were corrected to use their real GitHub remotes rather than local-path placeholders.

This repo is intended to become a **sanitized submission surface** rather than a dump of every internal working file.

### Conversation log review and rewrite
The earlier `hackathon/convoLog.md` was reviewed and judged useful but stale for direct submission use. It covered Mar 13–16 engineering history, but it did not capture:
- the Mar 17 Synthesis submission requirement changes
- the live team/project state confirmation
- the Mar 18 draft-submission planning and sanitized repo creation
- the current public messaging constraint

That review led directly to this cleaned log spanning Mar 13 through now.

---

## What Was Built

Across this collaboration window, the concrete outputs included:

### mailbox-sdk
- envelope transport helpers
- deterministic crypto test vectors
- validation improvements
- cleaner package surface and docs
- build/test/release hygiene

### mailbox-relayer
- service scaffold
- canonical envelope schema
- provider adapter abstraction
- provider-specific support paths (including Venice, Runpod, Lambda, Bankr)
- mocked vertical demo flow
- live Venice adapter work
- durable SQLite state
- idempotent onchain ingestion worker
- deterministic metering and staging
- settlement pipeline
- kill-switch / retry / alerting / health surfaces
- scheduler and covenant/delinquency monitoring direction

### EqualFi / EqualScale
- shared types/storage/interfaces for agentic financing
- agreement lifecycle logic
- compute usage metering
- mailbox and encryption pubkey registry facets
- proposal approval flows
- collateral flows
- linear accrual / fee scheduling
- pooled financing and governance-adjacent work
- circuit breaker / stress / security hardening direction
- naming migration from `agentic/` to `equalscale/`

### Submission preparation
- live Synthesis docs revalidated
- draft submission path confirmed
- canonical track list identified
- sanitized umbrella repo started
- cleaned conversation log prepared

---

## Key Decisions and Pivots

### 1. Build the real rails, not just the flashy demo
The team repeatedly chose reliability, settlement machinery, and inspectable architecture over superficial demo polish.

### 2. Keep the protocol uncapturable
The strategic line remained consistent: avoid reshaping the protocol around governance-token shortcuts or other choices that compromise protocol architecture.

### 3. Treat DevCo / service layer as the monetizable surface
This allowed practical product and operating-surface thinking without compromising protocol architecture.

### 4. Use EqualScale as the active submission/product naming surface
The naming moved toward `equalscale/` as the concrete submission-facing slice of the broader architecture.

### 5. Prepare a curated submission bundle, not a raw internal dump
The Synthesis submission should be legible to judges. That means curated logs, explicit metadata, and a clean repo surface.

### 6. Keep public messaging mechanism-first
Public-facing Synthesis material should explain the machinery and its value without leaning on venue-misaligned framing.

---

## Current State at Time of Writing

As of Mar 18:
- the engineering core exists across contracts, relayer, and SDK
- the Synthesis team is registered and valid
- no project has yet been created on the platform
- a **draft** project can be created immediately
- publishing remains gated by self-custody requirements
- the team is preparing a sanitized submission repo and cleaner artifacts for judges

The remaining work is mostly packaging, narrowing, and presenting the build clearly.

---

## Recommended Submission Bundle

For judge readability, the submission should include:
- a concise project description and problem statement
- this cleaned conversation log (or a tightened derivative)
- a repo structure that clearly shows the relationship between EqualFi / EqualScale, mailbox-relayer, and mailbox-sdk
- honest `submissionMetadata` for harness, model, tools, and resources
- optional raw logs or supporting artifacts for auditability if needed

---

## Sources Used to Produce This Cleaned Log

Primary internal sources:
- `hackathon/convoLog.md`
- `memory/2026-03-13.md`
- `memory/2026-03-14.md`
- `memory/2026-03-15.md`
- `memory/2026-03-16.md`
- `memory/2026-03-17.md`
- `memory/2026-03-18.md`

Prepared by Eve on 2026-03-18.
