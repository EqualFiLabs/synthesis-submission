# Demo Evidence (Consolidated)

Generated: 2026-03-21

This document consolidates all lifecycle evidence into a single judge-facing reference.
For full raw JSON, see the individual source files listed at the end.

---

## Evidence Summary

| Demo | Provider | Activation | Metering | Settlement | Risk Lifecycle | Status |
|------|----------|-----------|----------|------------|---------------|--------|
| Venice E2E | Venice | ok | 32 usage rows, 2 aggregated items | 1 settled (txHash) | breach → termination → close | **Full lifecycle** |
| Bankr E2E | Bankr | ok | 2 usage rows | 1 settled (txHash) | breach → termination → close | **Full lifecycle** |
| RunPod Activation | RunPod | ok (resource: `iv85r0j8t8ubau`) | no_usage (job stayed IN_QUEUE) | none | breach → close | Activation verified |
| RunPod Real Job | RunPod | N/A | N/A | N/A | N/A | Real API call, job accepted |
| Lambda Live | Lambda | error (insufficient capacity) | skipped | none | breach → close | Provider reached |
| Pure Financing (Anvil) | N/A | N/A | registerUsage tx | N/A | Active → Delinquent → Defaulted | **Full on-chain lifecycle** |

---

## 1. Venice — Full End-to-End Lifecycle

**Run:** 2026-03-19T02:04:12Z | **Agreement:** 177388580901

This is the strongest evidence path. It demonstrates the complete pipeline: activation → provider provisioning → real inference call → usage polling → deterministic metering → settlement → breach → kill-switch → close.

**Activation:**
- Provider: Venice
- Status: `ok`
- Resource ID: `ea08ad26-33dc-4f3d-859a-c388f494c0ee` (Venice API key)
- Usage seed: real inference call to `venice-uncensored` model (HTTP 200)

**Metering (32 raw usage rows → 2 aggregated items):**
```json
{
  "submissionId": "9c48e47f-9e91-45f2-af11-fe711de739f7",
  "usageRows": 32,
  "aggregatedItems": [
    { "unitType": "VENICE_TEXT_TOKEN_IN", "amount": "0.596235" },
    { "unitType": "VENICE_TEXT_TOKEN_OUT", "amount": "0.00232" }
  ],
  "usageDigest": "90aafd263b475bc21b59e7abac5a3d897f6f7a8e4b80077fea325f720c6e7dba"
}
```

**Settlement (webhook mock — see note below):**
```json
{
  "status": "ok",
  "settled": true,
  "txHash": "0xsettled-177388580901-1773885831166",
  "attempt": 1
}
```

> **Settlement mode note:** The Venice and Bankr demos used the relayer's webhook settlement path, which generates deterministic mock tx hashes (`0xsettled-{agreementId}-{timestamp}`). These hashes confirm the settlement pipeline executed end-to-end but are **not real on-chain transactions**. Real on-chain settlement is demonstrated separately in the relayer's Anvil integration tests (see Section 6) and the Pure Financing demo (Section 5), where `registerUsage` calls produce actual Anvil tx hashes verified via `eth_getTransactionReceipt`.

**Risk Lifecycle:**
- Breach event processed → draw frozen → Venice key terminated (`terminated: true`)
- Final metering on breach: `no_usage` (key already revoked)
- Agreement closed

**Verification checks (all passing):**
- `activationAccepted: true`
- `providerProvisioned: true`
- `meteringPrepared: true`
- `submissionCount: 1`
- `settlementCount: 1`

---

## 2. Bankr — Full End-to-End Lifecycle

**Run:** 2026-03-19T03:09:22Z | **Agreement:** 177388974701

**Activation:**
- Status: `ok`
- Resource ID: `bankr:177388974701`

**Metering:**
- Usage seed: real inference call to `claude-opus-4.6` model (HTTP 200)
- Final-pass metering on breach: 2 usage rows prepared
- Submission ID: `1a7dbb4e-8ebd-499f-9ab2-f274f8117492`

**Settlement (webhook mock):**
```json
{
  "processed": 1,
  "settled": 1,
  "txHash": "0xsettled-177388974701-1773889762572"
}
```
> Same webhook settlement path as Venice — see settlement mode note in Section 1.

---

## 3. RunPod — Activation + Real Job Submission

**Activation retest:** 2026-03-19T02:34:16Z | **Agreement:** 177388750601

- Status: `ok`
- Resource ID: `iv85r0j8t8ubau` (RunPod serverless endpoint)
- Usage seed: job submitted but stayed `IN_QUEUE` within polling window
- Metering: `no_usage` (expected — job didn't complete)

**Real job submission:** 2026-03-18T19:50:46Z

- Endpoint: `https://api.runpod.ai/v2/iv85r0j8t8ubau/run`
- HTTP 200 accepted
- Job ID: `7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1`
- Status: `IN_QUEUE` across 5 follow-up polls
- Health snapshot: 2 workers ready, 2 jobs in queue

This proves the RunPod adapter correctly provisions endpoints, submits real jobs, and polls status — the metering gap is purely due to no job completing within the demo window.

---

## 4. Lambda — Provider Reached

**Run:** 2026-03-18T19:36:45Z | **Agreement:** lambda-live2-1773862562

- Activation reached Lambda API
- Result: `insufficient-capacity` for tested instance/region
- Relayer correctly handled the error: no provider link created, metering skipped, breach processed, agreement closed
- Temporary SSH keys created for launch were cleaned up post-run

This demonstrates the Lambda adapter's error handling path. The activation failure is a real-world capacity constraint, not a code bug.

---

## 5. Pure Financing — On-Chain Lifecycle (Anvil Timewarp)

**Run:** 2026-03-18T20:14:15Z | **Chain:** 31337 (Anvil)

This demonstrates the complete on-chain financing state machine with no external provider dependencies. The demo uses `registerUsage` (metered-usage mode) to create debt, but the contracts also support `drawPrincipal` (direct-draw mode) for general capital draws without provider-metered usage routing — see `AgenticAgreementFacet.drawPrincipal()` and associated tests.

**Setup:**
- Diamond: `0xC9a43158891282A2B1475592D5719c001986Aaec`
- Credit: 1000e18 | Units: 1000e18
- Interest: 1200 bps annual | Fees: origination 100, service 200, late 300 bps
- Cure period: 259,200 seconds (3 days)

**State transitions with real tx hashes:**

| Step | Action | Tx Hash | Status |
|------|--------|---------|--------|
| 1 | `registerUsage` (400e18 units @ 1e18) | `0x307309e4...d34b50` | Active |
| 2 | Timewarp +1 day → `accrueInterest` | `0xa0e20fe8...62c4b1f1` | Active (interest accruing) |
| 3 | Timewarp +2d+1s → `detectDelinquency` | `0x733bd556...7410e3` | **Delinquent** |
| 4 | Timewarp +3d+1s → `triggerDefault` | `0x99b63aa9...3ba3f53e` | **Defaulted** |

**Key on-chain artifacts:**
- Risk facet deployed at: `0xe1Fd27F4390DcBE165f4D60DBF821e4B9Bb02dEd`
- Diamond cut tx: `0x5e5fdb4021b5b564ede01e1977e1c2206a02edeb8552078a2dcdea6ec189df77`

---

## What This Evidence Proves

1. **Real provider integration** — Venice and Bankr both activated, served real inference calls, and returned metered usage that was aggregated and settled.
2. **Deterministic metering pipeline** — 32 raw Venice usage rows were normalized into 2 unit types with content-addressable digest.
3. **Settlement pipeline** — Metered submissions were settled via the relayer's webhook path (Venice/Bankr demos) and via real Anvil transactions (Pure Financing demo + relayer integration tests).
4. **Kill-switch enforcement** — On breach events, draws were frozen and provider resources (API keys, endpoints) were terminated.
5. **Multi-provider architecture** — Four providers exercised across inference (Venice, Bankr) and compute (RunPod, Lambda) rails.
6. **On-chain state machine** — Full Active → Delinquent → Defaulted lifecycle with interest accrual, grace periods, and cure period timing verified on Anvil. Both metered-usage (`registerUsage`) and direct-draw (`drawPrincipal`) modes are supported and tested.
7. **Error handling** — Lambda capacity errors and RunPod job queueing were handled gracefully without crashing the relayer.

---

## 6. Test Results (2026-03-21)

All tests pass across all three codebases.

### Solidity (forge test)

```
Ran 155 test suites: 823 tests passed, 0 failed, 0 skipped
```

Breakdown by category:

| Category | Tests | Status |
|----------|-------|--------|
| Agentic unit + fuzz (18 facets) | 225 | All pass |
| Invariant (write-off, cross-cutting, cross-product) | 43 | All pass |
| Differential (solo-vs-pooled, adapter portability) | 7 | All pass |
| Stress (default cascade, gas profiling, high-volume, concurrent metering) | 8 | All pass |
| Security (access control, reentrancy, storage collision, upgrade safety) | 18 | All pass |
| Cross-flow integration | 1 | Pass |
| ERC-8183 ACP lifecycle | 11 | Pass |
| EqualFi base (non-EqualScale) | 510 | All pass |

### Mailbox SDK (vitest)

```
9 tests passed, 0 failed
```

Covers: key generation, encrypt/decrypt round-trip, envelope parsing, bytes encoding, compressed key handling, deterministic test vectors.

### Mailbox Relayer (vitest)

```
39 test files passed, 197 tests passed, 0 failed
Duration: 19.87s
```

Includes Anvil integration tests (`integration.anvil.test.ts`) with real on-chain tx submission:
- Event listener delivery + dedup
- Usage settlement tx submission with real tx hashes
- Idempotent re-delivery with cursor rewind
- Graceful shutdown with block progress persistence

---

## Source Files

| File | Content |
|------|---------|
| `LIFECYCLE-OUTPUTS.md` | Venice + RunPod full lifecycle JSON (Bankr retest, RunPod activation retest) |
| `LIFECYCLE-OUTPUTS-LAMBDA-RUNPOD.md` | Lambda + RunPod live evidence with error analysis |
| `PURE-FINANCING-TIMEWARP-OUTPUTS.md` | On-chain Anvil timewarp lifecycle with tx hashes |
| `RUNPOD-REAL-JOB-LOG.md` | Real RunPod job submission with health snapshot |
