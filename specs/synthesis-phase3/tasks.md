# Implementation Plan: Synthesis Phase 3 — Provider Adapters

## Overview

Incremental build of the Lambda and RunPod adapter implementations, adapter routing policy, canonical unit type registry, and differential/no-lock-in test suites. All code lives in `mailbox-relayer/src/providers/` and `mailbox-relayer/test/`. The existing `ComputeProviderAdapter` interface and API-inference adapters (`VeniceComputeAdapter`, `BankrComputeAdapter`) are unchanged.

## Tasks

- [x] 1. Canonical unit type registry and compute policy schema
  - [x] 1.1 Create canonical unit type registry
    - Create `mailbox-relayer/src/providers/unit-types.ts`
    - Define `CanonicalUnitType` interface with `id`, `name`, and `providerMappings`
    - Define `CANONICAL_UNIT_TYPES` array with all unit types from the design doc (GPU_HOUR_A100, GPU_HOUR_H100, GPU_HOUR_A10, RUNPOD_GPU_SEC, RUNPOD_INFERENCE_REQUEST, VENICE_TEXT_TOKEN_IN, VENICE_TEXT_TOKEN_OUT, VENICE_IMAGE_GEN, VENICE_AUDIO_TTS_CHAR, VENICE_AUDIO_STT_SEC, BANKR_TEXT_TOKEN_IN, BANKR_TEXT_TOKEN_OUT)
    - Implement `resolveCanonicalUnitType(provider, providerMetric)` — lookup canonical unit type for a provider-specific metric string
    - Implement `getProviderUnitTypes(provider)` — return all canonical unit type IDs for a provider
    - Export from `providers/index.ts`
    - _Requirements: 20.1, 20.2, 20.3, 20.4_

  - [x] 1.2 Create compute policy schema and router extension
    - Create `mailbox-relayer/src/providers/policy.ts`
    - Define `computePolicySchema` Zod schema with all fields from the design doc
    - Export `ComputePolicy` type
    - Define `MODE_TO_PROVIDER` mapping: `dedicated → lambda`, `burst → runpod`, `api_inference → venice` (default API-inference rail; `provider=bankr` remains valid explicit override)
    - _Requirements: 8.1, 8.2, 8.3_

  - [x] 1.3 Extend ComputeAdapterRegistry with routing and circuit-breaker
    - Add `resolve(policy: ComputePolicy): ComputeProviderAdapter | undefined` method to `ComputeAdapterRegistry`
    - Routing logic: explicit `policy.provider` first, then `MODE_TO_PROVIDER[policy.computeMode]`, then `undefined`
    - Add `disable(provider)`, `enable(provider)`, `isEnabled(provider)` methods using a `Set<ComputeProvider>` of disabled providers
    - `resolve()` returns `undefined` if resolved provider is disabled
    - Log routing decisions with `agreementId`, resolved provider, and policy fields
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

  - [x]* 1.4 Write unit tests for unit type registry, policy schema, and router
    - Test `resolveCanonicalUnitType` for all provider/metric combinations
    - Test `getProviderUnitTypes` returns correct IDs per provider
    - Test `computePolicySchema` accepts valid policies, rejects invalid
    - Test `resolve()` for all 12 `{provider} × {computeMode}` combinations
    - Test `resolve()` returns `undefined` for disabled providers
    - Test `disable()`/`enable()` circuit-breaker behavior
    - _Requirements: 7.1–7.6, 8.1–8.3, 20.1–20.4_

- [x] 2. Checkpoint — Registry and routing compile
  - Verify `npm run build` compiles cleanly. Ask the user if questions arise.

- [x] 3. Lambda adapter — HTTP client and provisioning
  - [x] 3.1 Implement Lambda HTTP client helper
    - Add HTTP request helper to `LambdaComputeAdapter` (same pattern as Venice: private `request()` method)
    - Constructor accepts `LambdaAdapterOptions { apiKey?, baseUrl?, fetchFn? }`
    - Read `LAMBDA_API_KEY` and `LAMBDA_BASE_URL` from env if not provided in options
    - Implement retry logic: HTTP 429 → wait `Retry-After` (or 5s default), HTTP 5xx → exponential backoff (1s, 2s, 4s), max 3 retries
    - Include `x-request-id` or correlation headers from responses in `meta`
    - _Requirements: 1.2, 1.3, 9.1, 9.2, 9.3, 9.4, 18.1, 18.2, 18.3_

  - [x] 3.2 Implement Lambda instance type mapping
    - Add `INSTANCE_TYPE_MAP` constant with canonical → Lambda mappings from the design doc
    - Implement `mapInstanceType(canonical: string): string | undefined` — returns Lambda type or `undefined`
    - If input starts with `gpu_`, treat as direct Lambda type (passthrough)
    - Implement `getSupportedInstanceTypes()` returning the mapping
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

  - [x] 3.3 Implement Lambda SSH key management
    - Implement `ensureSshKey(agreementId, publicKey)`:
      - Derive key name: `equalfi-{agreementId}`
      - `GET /ssh-keys` → check if key name exists
      - If not found: `POST /ssh-keys { name, public_key }` → create
      - Return key name on success, throw on failure
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

  - [x] 3.4 Implement Lambda `provision()`
    - Validate `LAMBDA_API_KEY` configured
    - Map `policy.instanceType` via `mapInstanceType()` — return error if unmappable
    - Call `ensureSshKey()` with `payload.sshPublicKey` — return error if fails
    - Call `POST /instance-operations/launch` with `{ region_name, instance_type_name, ssh_key_names: [keyName], name: "equalfi-{agreementId}", quantity: 1 }`
    - Extract `instance_ids[0]` from response
    - Call `GET /instances/{id}` to get IP/status
    - If instance is not yet SSH-ready (launch in progress): return `{ status: "ok", providerResourceId: instanceId, connectionPending: true, meta: { agreementId, traceId } }`
    - If instance is ready: return `{ status: "ok", providerResourceId: instanceId, connection: { ssh_host, ssh_port: 22, ssh_user: "ubuntu" }, meta: { agreementId, traceId } }`
    - On API error: return `{ status: "error", message }` with error detail
    - _Requirements: 1.1, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9_

  - [x]* 3.5 Write unit tests for Lambda provisioning
    - Test successful provision with mocked API responses (SSH key check, key create, launch, instance details)
    - Test SSH key already exists (skip creation)
    - Test missing `LAMBDA_API_KEY` returns error
    - Test unmappable instance type returns error
    - Test SSH key creation failure returns error without launching
    - Test API error on launch returns error with detail
    - Test rate limit (429) retry behavior
    - Test 5xx retry behavior
    - Test non-ready launch path returns `connectionPending: true`
    - Test instance name includes agreementId
    - _Requirements: 1.1–1.9, 9.1–9.4, 11.1–11.4, 12.1–12.4_

- [x] 4. Lambda adapter — usage metering and termination
  - [x] 4.1 Implement Lambda `usage()`
    - Validate `LAMBDA_API_KEY` configured
    - Call `GET /instances/{providerResourceId}` to get instance status and `launch_time`
    - Compute elapsed hours: `(min(to, now, terminationTime) - max(from, launchTime)) / 3600`
    - Map instance type to canonical unit type via `resolveCanonicalUnitType('lambda', instanceType)`
    - Return `{ status: "ok", usage: [{ unitType, amount: elapsedHours.toFixed(18), observedAt }] }`
    - If instance terminated/errored: include `meta.instanceStatus`, compute usage up to stop time
    - On API error: return `{ status: "error", usage: [], message }`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [x] 4.2 Implement Lambda `terminate()`
    - Validate `LAMBDA_API_KEY` configured
    - Call `POST /instance-operations/terminate { instance_ids: [providerResourceId] }`
    - On success: return `{ status: "ok", terminated: true, meta: { agreementId, providerResourceId, reason } }`
    - On instance not found / already terminated: return `{ status: "ok", terminated: true }` (idempotent)
    - On API error: return `{ status: "error", terminated: false, message }`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x]* 4.3 Write unit tests for Lambda usage and termination
    - Test usage calculation for running instance (known launch_time, from, to)
    - Test usage for terminated instance (usage up to termination time)
    - Test usage with missing instance (error response)
    - Test canonical unit type mapping in usage output
    - Test terminate success
    - Test terminate already-terminated (idempotent)
    - Test terminate API error
    - _Requirements: 2.1–2.6, 3.1–3.5_

- [x] 5. Checkpoint — Lambda adapter complete
  - Verify `npm run build` compiles cleanly. Ask the user if questions arise.

- [x] 6. RunPod adapter — serverless endpoint provisioning
  - [x] 6.1 Implement RunPod REST client helpers
    - Add HTTP request helpers to `RunPodComputeAdapter`:
      - serverless API (`api.runpod.ai/v2`)
      - infrastructure API (`rest.runpod.io/v1`)
    - Constructor accepts `RunPodAdapterOptions { apiKey?, serverlessBaseUrl?, infraBaseUrl?, fetchFn? }`
    - Read `RUNPOD_API_KEY`, `RUNPOD_SERVERLESS_BASE_URL`, and `RUNPOD_INFRA_BASE_URL` from env if not provided
    - Implement retry logic: HTTP 429 → exponential backoff, HTTP 5xx → exponential backoff (1s, 2s, 4s), max 3 retries
    - Normalize REST error payloads and include provider request IDs when present
    - _Requirements: 4.2, 4.3, 10.1, 10.2, 10.3, 10.4, 19.1, 19.2, 19.3, 19.4_

  - [x] 6.2 Implement RunPod serverless `provision()`
    - Validate `RUNPOD_API_KEY` configured
    - Determine mode: if `policy.computeMode === "dedicated"` → delegate to pod provisioning (task 7.1)
    - For serverless: create endpoint via `POST {infraBaseUrl}/endpoints` with `{ name: "equalfi-{agreementId}", gpuIds, minWorkers, maxWorkers, idleTimeout, executionTimeoutMs, jobTtlMs, webhookUrl }` from policy
    - Extract `endpoint_id` from response
    - Return `{ status: "ok", providerResourceId: endpoint_id, connection: { endpoint_url: "{serverlessBaseUrl}/{endpoint_id}", api_key: runpodApiKey } }`
    - On API error: return `{ status: "error", message }`
    - _Requirements: 4.1, 4.4, 4.5, 4.6, 4.7_

  - [x]* 6.3 Write unit tests for RunPod serverless provisioning
    - Test successful endpoint creation with mocked response
    - Test missing `RUNPOD_API_KEY` returns error
    - Test API error returns error with detail
    - Test endpoint name includes agreementId
    - Test policy defaults (minWorkers: 0, maxWorkers: 1, idleTimeout: 60, executionTimeoutMs: 600000, jobTtlMs: 86400000)
    - Test webhook URL is wired when provided
    - _Requirements: 4.1–4.7_

- [x] 7. RunPod adapter — pod provisioning (dedicated mode)
  - [x] 7.1 Implement RunPod pod `provision()` (dedicated mode)
    - When `policy.computeMode === "dedicated"`:
    - Call `POST {infraBaseUrl}/pods` with `{ name, gpuTypeIds, gpuCount, volumeInGb, imageName, ... }`
    - Extract `pod_id` from response
    - Query `GET {infraBaseUrl}/pods/{pod_id}` until running (or timeout)
    - Return `{ status: "ok", providerResourceId: pod_id, connection: { pod_url, ssh_host?, ssh_port? } }`
    - _Requirements: 13.1, 13.2, 13.3_

  - [x]* 7.2 Write unit tests for RunPod pod provisioning
    - Test pod creation with mocked infrastructure REST response
    - Test dedicated mode dispatch (computeMode: "dedicated" + provider: "runpod")
    - Test REST error handling
    - _Requirements: 13.1–13.3_

- [x] 8. RunPod adapter — usage metering and termination
  - [x] 8.1 Implement RunPod serverless `usage()`
    - Read persisted provider webhook completion events in time window `[from, to]` (primary)
    - Poll RunPod `/status/{job_id}` for tracked in-flight jobs before retention expiry (fallback)
    - Deduplicate by job ID using a Set
    - Compute per-request count → `RUNPOD_INFERENCE_REQUEST`
    - Compute total GPU-seconds from job execution times → `RUNPOD_GPU_SEC`
    - Return both unit types in usage array
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [x] 8.2 Implement RunPod pod `usage()` (dedicated mode)
    - Query pod status via `GET {infraBaseUrl}/pods/{pod_id}`
    - Compute elapsed GPU-hours from pod start time to checkpoint boundary
    - Map GPU type to canonical unit type
    - Return `{ status: "ok", usage: [{ unitType: "GPU_HOUR_{type}", amount, observedAt }] }`
    - _Requirements: 13.4_

  - [x] 8.3 Implement RunPod `terminate()`
    - Determine resource type (endpoint vs pod) from stored metadata or resource ID format
    - For serverless endpoint: `DELETE {infraBaseUrl}/endpoints/{id}`
    - For pod: `DELETE {infraBaseUrl}/pods/{id}`
    - Idempotent: already-deleted returns `{ terminated: true }`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 13.5_

  - [x]* 8.4 Write unit tests for RunPod usage and termination
    - Test serverless usage with mocked webhook event rows plus `/status` fallback (deduplication, GPU-second calculation)
    - Test pod usage with mocked pod status (GPU-hour calculation)
    - Test endpoint termination success and idempotent behavior
    - Test pod termination success and idempotent behavior
    - Test API error handling for all operations
    - _Requirements: 5.1–5.6, 6.1–6.5, 13.4–13.5_

- [x] 9. Checkpoint — RunPod adapter complete
  - Verify `npm run build` compiles cleanly. Ask the user if questions arise.

- [x] 10. Integration wiring
  - [x] 10.1 Update `createDefaultComputeAdapterRegistry` to pass env config
    - Update `LambdaComputeAdapter` construction to read `LAMBDA_API_KEY` and `LAMBDA_BASE_URL` from env
    - Update `RunPodComputeAdapter` construction to read `RUNPOD_API_KEY`, `RUNPOD_SERVERLESS_BASE_URL`, and `RUNPOD_INFRA_BASE_URL` from env
    - No changes to existing API-inference adapter construction (Venice/Bankr already read from env)
    - _Requirements: 18.1, 18.2, 18.3, 19.1, 19.2, 19.3, 19.4_

  - [x] 10.2 Update OnchainEventIngestionWorker to use adapter router
    - In `handleActivationEvent`, replace direct `this.providers.get(provider)` with `this.providers.resolve(policy)` when a compute policy is available from the event
    - Fall back to `this.providers.get(provider)` when no policy is present (backward compatible)
    - Log routing decision
    - _Requirements: 7.1, 7.6_

  - [x] 10.3 Export new modules from providers/index.ts
    - Export `unit-types.ts`, `policy.ts` from `providers/index.ts`
    - Update `README.md` environment variables section with `LAMBDA_API_KEY`, `LAMBDA_BASE_URL`, `RUNPOD_API_KEY`, `RUNPOD_SERVERLESS_BASE_URL`, `RUNPOD_INFRA_BASE_URL`
    - _Requirements: 18.1, 19.1, 19.2, 19.3, 19.4_

- [x] 11. Checkpoint — Integration wiring
  - Verify `npm run build` compiles cleanly. Verify `GET /providers` returns all four providers. Ask the user if questions arise.

- [x] 12. Differential accounting tests
  - [x]* 12.1 Write differential test: API inference adapter vs Lambda
    - Define synthetic workload trace: 10 usage events with known amounts
    - Run the same trace against Venice and Bankr API-inference adapters
    - Mock API-inference adapter to return normalized usage (VENICE_TEXT_TOKEN_IN/OUT or BANKR_TEXT_TOKEN_IN/OUT)
    - Mock Lambda adapter to return normalized usage (GPU_HOUR_A100)
    - Apply same unit pricing to both outputs
    - Assert `principalDrawn` values are identical (zero difference)
    - **Validates: Property 9, Requirements 14.1–14.4**

  - [x]* 12.2 Write differential test: API inference adapter vs RunPod
    - Same synthetic trace structure
    - Run the same trace against Venice and Bankr API-inference adapters
    - Mock RunPod adapter to return normalized usage (RUNPOD_GPU_SEC, RUNPOD_INFERENCE_REQUEST)
    - Assert identical `principalDrawn` after unit pricing
    - Include API-inference (Venice or Bankr) vs burst-inference (RunPod) trace
    - **Validates: Property 9, Requirements 15.1–15.4**

  - [x]* 12.3 Write differential test: Lambda vs RunPod
    - Same synthetic trace structure
    - Assert identical `principalDrawn` after unit pricing
    - **Validates: Property 9**

- [x] 13. No-lock-in acceptance tests
  - [x]* 13.1 Write acceptance test: Core independence
    - Disable Lambda → run Venice + Bankr + RunPod accounting → verify correct
    - Disable RunPod → run Venice + Bankr + Lambda accounting → verify correct
    - Disable Venice → run Bankr + Lambda + RunPod accounting → verify correct
    - Disable Bankr → run Venice + Lambda + RunPod accounting → verify correct
    - Verify provider-specific metadata not required for canonical state reconstruction
    - **Validates: Property 10, Requirements 16.1–16.5**

  - [x]* 13.2 Write acceptance test: Storage independence
    - Verify Phase 1 Diamond storage struct has no provider-specific fields
    - Verify SQLite `provider_links` table uses generic schema (provider name + resource ID)
    - Verify provider swap requires only `policy.provider` change, no data migration
    - **Validates: Property 10, Requirements 17.1–17.3**

- [x] 14. Property-based tests
  - [x]* 14.1 Write property test: Canonical unit type mapping completeness (Property 7)
    - Fuzz provider metrics through `resolveCanonicalUnitType`, verify all valid metrics map to a registry entry
    - Verify no adapter produces a unitType outside the registry
    - **Validates: Requirements 2.3, 5.2, 20.1, 20.2**

  - [x]* 14.2 Write property test: Adapter routing determinism (Property 8)
    - Fuzz `ComputePolicy` objects through `resolve()`, verify deterministic output
    - Verify same policy always resolves to same provider
    - **Validates: Requirements 7.1–7.4**

  - [x]* 14.3 Write property test: Usage metering determinism (Properties 5, 6)
    - Fuzz time windows and instance/job parameters through Lambda and RunPod usage methods
    - Verify identical inputs always produce identical outputs
    - **Validates: Requirements 2.1–2.4, 5.1–5.6**

- [x] 15. Final checkpoint — Full build and test suite
  - Verify `npm run build` compiles cleanly and `npm test` passes all unit, differential, acceptance, and property tests. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are test tasks and SHOULD be completed before Phase 4 close; RunPod webhook/polling safety tests are REQUIRED before production sign-off
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major component
- The existing API-inference adapters (`VeniceComputeAdapter`, `BankrComputeAdapter`) are not modified — they already implement the full interface
- Lambda and RunPod adapters follow the same constructor pattern as Venice/Bankr (options object with env fallbacks)
- All adapters catch exceptions internally and return `{status: "error"}` — no unhandled throws
- The adapter router is backward compatible — `get(provider)` still works alongside `resolve(policy)`
- Differential tests use mocked adapters with synthetic traces — no live API calls in CI
