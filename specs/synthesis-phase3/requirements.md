# Requirements Document

## Introduction

Phase 3 of the Equalis Agentic Financing protocol completes the two remaining compute provider adapters — Lambda (dedicated GPU instances) and RunPod (serverless/burst inference) — and adds an adapter routing policy that selects the correct provider based on agreement configuration. Currently the `LambdaComputeAdapter` and `RunPodComputeAdapter` are scaffolded stubs returning `status: "not_implemented"`. The API-inference adapters (`VeniceComputeAdapter`, `BankrComputeAdapter`) are already live implementations.

Phase 3 replaces both stubs with production HTTP implementations, adds a routing layer to the `ComputeAdapterRegistry`, and introduces differential accounting tests that prove canonical debt outcomes are identical across all four providers for equivalent workloads. This phase also enforces the no-lock-in acceptance gates defined in the compute-provider-decision-spec.

### Explicitly Out of Scope

- Modifications to Phase 1 Diamond facets or storage layout
- Large redesign of the EventListener or TransactionSubmitter (Phase 2); this phase may consume minimal provider-webhook wiring added in Phase 2
- Modifications to existing API-inference adapters (`VeniceComputeAdapter`, `BankrComputeAdapter`)
- Pooled financing, governance, collateral, covenants, trust modes
- ERC-8004 / ERC-8183 integration (Phase 4)
- Production mainnet deployment or HSM/KMS key management
- Frontend or UI components
- Modal or Vast provider integrations

## Glossary

- **Lambda**: Lambda Labs — a GPU cloud provider offering dedicated instance provisioning via REST API at `https://cloud.lambdalabs.com/api/v1`
- **RunPod**: RunPod — a GPU cloud provider offering serverless inference at `https://api.runpod.ai/v2` and infrastructure lifecycle APIs at `https://rest.runpod.io/v1`
- **Instance**: A dedicated GPU virtual machine provisioned on Lambda with a fixed hourly rate, SSH access, and persistent storage
- **Pod**: A RunPod on-demand GPU container with configurable GPU type, volume, and runtime
- **Serverless_Endpoint**: A RunPod serverless inference endpoint that auto-scales workers and processes inference requests via queue
- **Adapter_Router**: A component that selects the appropriate `ComputeProviderAdapter` for a given agreement based on the agreement's compute policy configuration
- **Compute_Policy**: A JSON object attached to a financing proposal/agreement that specifies the desired provider, instance type, model, region, and resource constraints
- **Canonical_Unit_Type**: A provider-agnostic usage metric identifier (e.g., `GPU_HOUR_A100`, `INFERENCE_REQUEST`, `VENICE_TEXT_TOKEN_IN`, `BANKR_TEXT_TOKEN_IN`) used for on-chain `registerUsage` calls
- **Differential_Test**: A test that replays identical synthetic workload traces through two or more provider adapters and asserts that the resulting canonical debt/accounting outcomes are identical
- **No_Lock_In_Gate**: An acceptance criterion from the compute-provider-decision-spec that must pass before mainnet release, ensuring no provider-specific coupling in core protocol logic

## Requirements

### Requirement 1: Lambda Adapter — Instance Provisioning

**User Story:** As a relayer operator, I want the LambdaComputeAdapter to provision dedicated GPU instances via the Lambda API, so that borrower agents receive financed dedicated compute capacity.

#### Acceptance Criteria

1. WHEN the `LambdaComputeAdapter.provision()` is called with a valid `ProvisionRequest`, THE adapter SHALL call `POST https://cloud.lambdalabs.com/api/v1/instance-operations/launch` with the instance type, region, SSH key, and name derived from the request's `policy` and `payload` fields
2. THE adapter SHALL read the Lambda API key from the `LAMBDA_API_KEY` environment variable
3. IF the `LAMBDA_API_KEY` environment variable is missing, THEN THE adapter SHALL return `{status: "error", message: "LAMBDA_API_KEY not configured"}`
4. WHEN the Lambda API returns a successful launch response and the instance is SSH-ready, THE adapter SHALL extract the `instance_id` from the response and return `{status: "ok", providerResourceId: instance_id, connection: {ssh_host, ssh_port, ssh_user}}`
5. THE adapter SHALL map the `policy.instanceType` field to a Lambda instance type string (e.g., `"gpu_1x_a100"`, `"gpu_1x_h100"`)
6. THE adapter SHALL inject the borrower's SSH public key from `payload.sshPublicKey` into the launch request's `ssh_key_names` parameter, creating the key via `POST /ssh-keys` if it does not already exist
7. IF the Lambda API returns an error (capacity unavailable, invalid instance type, auth failure), THEN THE adapter SHALL return `{status: "error", message}` with the error detail from the API response
8. THE adapter SHALL include the `agreementId` and `traceId` in the instance name or description for operational traceability
9. THE adapter SHALL treat instance launch as asynchronous: if the instance is not yet ready for SSH, it SHALL return `{status: "ok", connectionPending: true}` with the `providerResourceId` and defer connection readiness until a later successful status check

### Requirement 2: Lambda Adapter — Usage Metering

**User Story:** As a relayer operator, I want the LambdaComputeAdapter to meter runtime usage for provisioned instances, so that compute consumption is accurately tracked for on-chain debt accrual.

#### Acceptance Criteria

1. WHEN `LambdaComputeAdapter.usage()` is called, THE adapter SHALL call `GET /instances/{instance_id}` to retrieve the instance's current status and runtime metadata
2. THE adapter SHALL compute usage as elapsed runtime since the last checkpoint, using the instance's `launch_time` or the `from` parameter as the start boundary and `to` or current time as the end boundary
3. THE adapter SHALL map instance runtime to canonical unit types based on the instance type: `GPU_HOUR_A100`, `GPU_HOUR_H100`, `GPU_HOUR_A10`, or a generic `GPU_HOUR_{type}` pattern
4. THE adapter SHALL compute the usage `amount` as fractional hours of runtime (e.g., 30 minutes = `"0.5"`) as a decimal string
5. IF the instance is in a non-running state (terminated, error), THE adapter SHALL return usage up to the termination/error time and include `meta.instanceStatus` in the response
6. IF the Lambda API returns an error, THEN THE adapter SHALL return `{status: "error", usage: [], message}` with the error detail

### Requirement 3: Lambda Adapter — Instance Termination

**User Story:** As a relayer operator, I want the LambdaComputeAdapter to terminate provisioned instances on kill-switch triggers, so that financed compute access is revoked when agreements are breached or defaulted.

#### Acceptance Criteria

1. WHEN `LambdaComputeAdapter.terminate()` is called, THE adapter SHALL call `POST /instance-operations/terminate` with the `instance_ids` array containing the `providerResourceId`
2. WHEN the Lambda API confirms termination, THE adapter SHALL return `{status: "ok", terminated: true}`
3. IF the instance is already terminated or not found, THE adapter SHALL return `{status: "ok", terminated: true}` (idempotent)
4. IF the Lambda API returns an error, THEN THE adapter SHALL return `{status: "error", terminated: false, message}` with the error detail
5. THE adapter SHALL include `agreementId`, `providerResourceId`, and `reason` in the response `meta` for traceability

### Requirement 4: RunPod Adapter — Serverless Endpoint Provisioning

**User Story:** As a relayer operator, I want the RunPodComputeAdapter to provision serverless inference endpoints via the RunPod API, so that borrower agents receive financed burst inference capacity.

#### Acceptance Criteria

1. WHEN `RunPodComputeAdapter.provision()` is called with a valid `ProvisionRequest`, THE adapter SHALL create a serverless endpoint via RunPod infrastructure REST API (`https://rest.runpod.io/v1/endpoints`) using model, GPU type, and scaling configuration from the request's `policy` fields
2. THE adapter SHALL read the RunPod API key from the `RUNPOD_API_KEY` environment variable
3. IF the `RUNPOD_API_KEY` environment variable is missing, THEN THE adapter SHALL return `{status: "error", message: "RUNPOD_API_KEY not configured"}`
4. WHEN the RunPod API returns a successful endpoint creation response, THE adapter SHALL extract the `endpoint_id` and return `{status: "ok", providerResourceId: endpoint_id, connection: {endpoint_url, api_key}}`
5. THE adapter SHALL configure the endpoint with `minWorkers`, `maxWorkers`, `idleTimeout`, `executionTimeoutMs`, and `jobTtlMs` from policy, with sensible defaults (minWorkers: 0, maxWorkers: 1, idleTimeout: 60, executionTimeoutMs: 600000, jobTtlMs: 86400000)
6. IF the RunPod API returns an error, THEN THE adapter SHALL return `{status: "error", message}` with the error detail
7. THE adapter SHALL include the `agreementId` in the endpoint name for operational traceability
8. THE adapter SHALL configure webhook delivery when `policy.webhookUrl` is provided, so async completion events can be ingested by Phase 2 provider event ingress

### Requirement 5: RunPod Adapter — Inference Usage Metering

**User Story:** As a relayer operator, I want the RunPodComputeAdapter to meter inference usage for provisioned endpoints, so that burst compute consumption is accurately tracked for on-chain debt accrual.

#### Acceptance Criteria

1. WHEN `RunPodComputeAdapter.usage()` is called, THE adapter SHALL read persisted provider completion events (webhook-ingested) as the primary source for completed jobs since the last checkpoint
2. THE adapter SHALL map each completed job to a canonical unit type: `RUNPOD_INFERENCE_REQUEST` for per-request metering, or `RUNPOD_GPU_SEC` for GPU-second metering based on job execution time
3. THE adapter SHALL compute the usage `amount` as the count of completed requests or total GPU-seconds as a decimal string
4. THE adapter SHALL use the `from` and `to` parameters to bound the query window, and include `observedAt` timestamps from provider completion times
5. IF the RunPod API returns an error, THEN THE adapter SHALL return `{status: "error", usage: [], message}` with the error detail
6. THE adapter SHALL deduplicate usage rows by job ID to prevent double-counting across metering windows
7. IF webhook events are missing or delayed, THEN THE adapter SHALL poll RunPod `/status/{job_id}` for tracked in-flight jobs before result retention expiry windows (1 minute for `runsync`, 30 minutes for `run`)

### Requirement 6: RunPod Adapter — Endpoint Termination

**User Story:** As a relayer operator, I want the RunPodComputeAdapter to terminate provisioned endpoints on kill-switch triggers, so that financed inference access is revoked when agreements are breached or defaulted.

#### Acceptance Criteria

1. WHEN `RunPodComputeAdapter.terminate()` is called, THE adapter SHALL delete the serverless endpoint via RunPod infrastructure REST API (`DELETE /endpoints/{id}`) using the `providerResourceId` as the endpoint ID
2. WHEN the RunPod API confirms deletion, THE adapter SHALL return `{status: "ok", terminated: true}`
3. IF the endpoint is already deleted or not found, THE adapter SHALL return `{status: "ok", terminated: true}` (idempotent)
4. IF the RunPod API returns an error, THEN THE adapter SHALL return `{status: "error", terminated: false, message}` with the error detail
5. THE adapter SHALL include `agreementId`, `providerResourceId`, and `reason` in the response `meta` for traceability

### Requirement 7: Adapter Router — Provider Selection by Agreement Config

**User Story:** As a relayer operator, I want the adapter registry to automatically select the correct provider adapter based on the agreement's compute policy, so that activation events are routed to the appropriate provider without manual intervention.

#### Acceptance Criteria

1. THE `ComputeAdapterRegistry` SHALL support a `resolve(policy: ComputePolicy): ComputeProviderAdapter` method that selects the adapter based on the policy's `provider` field
2. WHEN the `policy.provider` field is explicitly set to `"lambda"`, `"runpod"`, `"venice"`, or `"bankr"`, THE registry SHALL return the corresponding adapter
3. WHEN the `policy.provider` field is not set, THE registry SHALL apply default routing rules: `computeMode: "dedicated"` → Lambda, `computeMode: "burst"` → RunPod, `computeMode: "api_inference"` → Venice (default API-inference rail)
4. IF the resolved provider's adapter is not registered or is disabled, THEN THE registry SHALL return `undefined` and the caller SHALL reject the activation with `"provider_not_supported"`
5. THE registry SHALL support a `disable(provider: ComputeProvider)` method that removes a provider from routing without unregistering it, for operational circuit-breaking
6. THE registry SHALL log the routing decision with `agreementId`, resolved `provider`, and the policy fields that influenced the decision

### Requirement 8: Adapter Router — Compute Policy Schema

**User Story:** As a relayer operator, I want a well-defined compute policy schema, so that agreement configurations are validated before provider routing.

#### Acceptance Criteria

1. THE `ComputePolicy` schema SHALL include: `provider` (optional, one of `"lambda"`, `"runpod"`, `"venice"`, `"bankr"`), `computeMode` (optional, one of `"dedicated"`, `"burst"`, `"api_inference"`), `instanceType` (optional string), `region` (optional string), `model` (optional string), `maxWorkers` (optional number), `minWorkers` (optional number), `idleTimeout` (optional number), `executionTimeoutMs` (optional number), `jobTtlMs` (optional number), `webhookUrl` (optional string URL), `sshPublicKey` (optional string), `consumptionLimit` (optional object)
2. THE `ComputePolicy` schema SHALL be validated via Zod before routing
3. IF the policy fails validation, THEN THE router SHALL reject the activation with a descriptive validation error

### Requirement 9: Lambda Adapter — Rate Limiting and Error Normalization

**User Story:** As a relayer operator, I want the Lambda adapter to handle API rate limits and normalize errors, so that transient failures are retried and permanent failures are surfaced clearly.

#### Acceptance Criteria

1. IF the Lambda API returns HTTP 429 (rate limited), THEN THE adapter SHALL respect the `Retry-After` header and retry the request after the specified delay
2. IF the Lambda API returns HTTP 5xx, THEN THE adapter SHALL retry the request up to 3 times with exponential backoff
3. THE adapter SHALL normalize all Lambda API errors into the standard `{status: "error", message}` format, including the HTTP status code and response body in `meta`
4. THE adapter SHALL include `x-request-id` or equivalent correlation headers from Lambda responses in the `meta` field for debugging

### Requirement 10: RunPod Adapter — Rate Limiting and Error Normalization

**User Story:** As a relayer operator, I want the RunPod adapter to handle API rate limits and normalize errors, so that transient failures are retried and permanent failures are surfaced clearly.

#### Acceptance Criteria

1. IF the RunPod API returns HTTP 429 (rate limited), THEN THE adapter SHALL retry the request with exponential backoff
2. IF the RunPod API returns HTTP 5xx, THEN THE adapter SHALL retry the request up to 3 times with exponential backoff
3. THE adapter SHALL normalize all RunPod API errors into the standard `{status: "error", message}` format
4. THE adapter SHALL normalize RunPod serverless/infrastructure REST error bodies and extract meaningful error messages, including request IDs when present

### Requirement 11: Lambda Adapter — SSH Key Management

**User Story:** As a relayer operator, I want the Lambda adapter to manage SSH keys for instance access, so that borrower agents can connect to their provisioned instances.

#### Acceptance Criteria

1. WHEN provisioning an instance, THE adapter SHALL check if the SSH key name already exists via `GET /ssh-keys`
2. IF the SSH key does not exist, THE adapter SHALL create it via `POST /ssh-keys` with the borrower's public key from `payload.sshPublicKey`
3. THE adapter SHALL use a deterministic key name derived from the agreement ID (e.g., `equalfi-{agreementId}`) to enable idempotent key creation
4. IF SSH key creation fails, THE adapter SHALL return `{status: "error", message}` without proceeding to instance launch

### Requirement 12: Lambda Adapter — Instance Type Mapping

**User Story:** As a relayer operator, I want the Lambda adapter to map canonical instance type requests to Lambda-specific instance types, so that agreement policies use provider-agnostic terminology.

#### Acceptance Criteria

1. THE adapter SHALL maintain a mapping from canonical instance type identifiers to Lambda instance type strings (e.g., `"a100_40gb"` → `"gpu_1x_a100"`, `"h100_80gb"` → `"gpu_1x_h100"`)
2. IF the `policy.instanceType` is already a valid Lambda instance type string, THE adapter SHALL use it directly
3. IF the `policy.instanceType` cannot be mapped, THE adapter SHALL return `{status: "error", message: "unsupported_instance_type"}`
4. THE adapter SHALL expose the mapping via a `getSupportedInstanceTypes()` method for operational visibility

### Requirement 13: RunPod Adapter — Pod Provisioning (Alternative Mode)

**User Story:** As a relayer operator, I want the RunPod adapter to support on-demand pod provisioning as an alternative to serverless endpoints, so that agreements requiring persistent GPU access can use RunPod.

#### Acceptance Criteria

1. WHEN `policy.computeMode` is `"dedicated"` and `policy.provider` is `"runpod"`, THE adapter SHALL provision an on-demand pod instead of a serverless endpoint
2. THE adapter SHALL create the pod via RunPod infrastructure REST API (`POST /pods`) with GPU type, volume size, and container image from the `policy` fields
3. WHEN the pod is running, THE adapter SHALL return `{status: "ok", providerResourceId: pod_id, connection: {ssh_host, ssh_port, ssh_user}}` if SSH is enabled, or `{connection: {pod_url}}` for HTTP access
4. THE adapter SHALL meter pod usage as GPU-hours (similar to Lambda instance metering) when in pod mode
5. THE adapter SHALL terminate pods via RunPod infrastructure REST API on kill-switch triggers, with the same idempotent behavior as endpoint termination

### Requirement 14: Differential Accounting Tests — API Inference Adapter vs Lambda

**User Story:** As a protocol developer, I want differential tests proving that an API-inference adapter (Venice or Bankr) and Lambda produce identical canonical debt outcomes for equivalent workloads, so that the no-lock-in guarantee is verified.

#### Acceptance Criteria

1. THE differential test SHALL define a synthetic workload trace with known usage amounts and unit types
2. THE differential test SHALL replay the trace through either `VeniceComputeAdapter` or `BankrComputeAdapter` (mocked) and `LambdaComputeAdapter` (mocked), normalizing usage into canonical unit types
3. THE differential test SHALL assert that the total `principalDrawn` computed from each adapter's usage output is identical after canonical unit pricing is applied
4. THE differential test SHALL assert that the sequence of `registerUsage` calls produced by each adapter's metering output, when processed through the same unit pricing, yields identical debt deltas

### Requirement 15: Differential Accounting Tests — API Inference Adapter vs RunPod

**User Story:** As a protocol developer, I want differential tests proving that an API-inference adapter (Venice or Bankr) and RunPod produce identical canonical debt outcomes for equivalent workloads, so that the no-lock-in guarantee is verified.

#### Acceptance Criteria

1. THE differential test SHALL define a synthetic workload trace with known usage amounts and unit types
2. THE differential test SHALL replay the trace through either `VeniceComputeAdapter` or `BankrComputeAdapter` (mocked) and `RunPodComputeAdapter` (mocked), normalizing usage into canonical unit types
3. THE differential test SHALL assert that the total `principalDrawn` computed from each adapter's usage output is identical after canonical unit pricing is applied
4. THE differential test SHALL include at least one trace that exercises an API-based inference path (Venice or Bankr) vs the burst inference path (RunPod)

### Requirement 16: No-Lock-In Acceptance Gate — Core Independence

**User Story:** As a protocol developer, I want to verify that disabling any single provider adapter does not break canonical agreement accounting, so that the protocol is not locked into any provider.

#### Acceptance Criteria

1. THE acceptance test SHALL disable the Lambda adapter and verify that agreements routed to Venice, Bankr, and RunPod still produce correct accounting outcomes
2. THE acceptance test SHALL disable the RunPod adapter and verify that agreements routed to Venice, Bankr, and Lambda still produce correct accounting outcomes
3. THE acceptance test SHALL disable the Venice adapter and verify that agreements routed to Bankr, Lambda, and RunPod still produce correct accounting outcomes
4. THE acceptance test SHALL disable the Bankr adapter and verify that agreements routed to Venice, Lambda, and RunPod still produce correct accounting outcomes
5. THE acceptance test SHALL verify that provider-specific metadata (API key IDs, instance IDs, endpoint IDs) is never required to reconstruct canonical agreement state from on-chain data alone

### Requirement 17: No-Lock-In Acceptance Gate — Storage Independence

**User Story:** As a protocol developer, I want to verify that swapping providers requires no storage migration in core contracts, so that the protocol can evolve provider integrations freely.

#### Acceptance Criteria

1. THE acceptance test SHALL verify that the Phase 1 Diamond storage layout contains no provider-specific fields
2. THE acceptance test SHALL verify that the relayer's SQLite schema uses only the generic `provider_links` table (provider name + resource ID) with no provider-specific columns
3. THE acceptance test SHALL verify that a provider swap (e.g., Lambda → RunPod for a new agreement) requires only a different `policy.provider` value, with no data migration

### Requirement 18: Lambda Adapter — Environment Configuration

**User Story:** As a relayer operator, I want the Lambda adapter to be configurable via environment variables, so that API credentials and base URL can be set at deployment time.

#### Acceptance Criteria

1. THE adapter SHALL read the API key from `LAMBDA_API_KEY` environment variable
2. THE adapter SHALL read the base URL from `LAMBDA_BASE_URL` environment variable (default: `https://cloud.lambdalabs.com/api/v1`)
3. THE adapter SHALL accept an options object at construction for testing (apiKey, baseUrl, fetchFn overrides)

### Requirement 19: RunPod Adapter — Environment Configuration

**User Story:** As a relayer operator, I want the RunPod adapter to be configurable via environment variables, so that API credentials and base URL can be set at deployment time.

#### Acceptance Criteria

1. THE adapter SHALL read the API key from `RUNPOD_API_KEY` environment variable
2. THE adapter SHALL read the serverless API base URL from `RUNPOD_SERVERLESS_BASE_URL` environment variable (default: `https://api.runpod.ai/v2`)
3. THE adapter SHALL read the infrastructure API base URL from `RUNPOD_INFRA_BASE_URL` environment variable (default: `https://rest.runpod.io/v1`)
4. THE adapter SHALL accept an options object at construction for testing (apiKey, serverlessBaseUrl, infraBaseUrl, fetchFn overrides)

### Requirement 20: Canonical Unit Type Registry

**User Story:** As a protocol developer, I want a centralized registry of canonical unit types with their provider mappings, so that usage normalization is consistent and auditable across all adapters.

#### Acceptance Criteria

1. THE registry SHALL define canonical unit types with their human-readable names and the provider-specific metric identifiers that map to them
2. THE registry SHALL include at minimum: `GPU_HOUR_A100`, `GPU_HOUR_H100`, `GPU_HOUR_A10`, `RUNPOD_GPU_SEC`, `RUNPOD_INFERENCE_REQUEST`, `VENICE_TEXT_TOKEN_IN`, `VENICE_TEXT_TOKEN_OUT`, `VENICE_IMAGE_GEN`, `VENICE_AUDIO_TTS_CHAR`, `VENICE_AUDIO_STT_SEC`, `BANKR_TEXT_TOKEN_IN`, `BANKR_TEXT_TOKEN_OUT`
3. THE registry SHALL be importable by all adapters and by the differential test suite
4. THE registry SHALL be extensible without modifying existing adapter code
