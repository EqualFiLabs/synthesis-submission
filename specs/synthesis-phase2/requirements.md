# Requirements Document

## Introduction

Phase 2 of the Equalis Agentic Financing protocol builds the integration layer that connects the existing mailbox-relayer (Fastify service) to the Phase 1 Diamond proxy smart contracts. Currently three gaps exist: (1) no service pushes real contract events to the relayer's `POST /events/onchain` endpoint, (2) the relayer's `UsageSettlementService` sends submissions via webhook but nothing calls `registerUsage()` on-chain, and (3) the mailbox system encrypts credentials but nothing calls `publishProviderPayload()` on-chain.

Phase 2 bridges these gaps with an event listener (chain → relayer), a transaction submitter (relayer → chain), relayer wallet management, environment configuration, and end-to-end integration tests.

### Explicitly Out of Scope

- Modifications to the Phase 1 Diamond facets or storage layout
- Large redesign of the mailbox-relayer's core ingestion, metering, or kill-switch logic (minimal provider-event ingestion hooks are in scope)
- Modifications to the mailbox-sdk encryption/decryption library
- Lambda and RunPod adapter implementations (Phase 3)
- Pooled financing, governance, collateral, covenants, trust modes
- Production mainnet deployment or key management (HSM, KMS)
- Frontend or UI components

## Glossary

- **Diamond**: The EIP-2535 Diamond proxy deployed in Phase 1, hosting all agentic financing facets
- **Event_Listener**: A service that subscribes to Diamond proxy contract events via JSON-RPC or WebSocket and forwards decoded events to the relayer's ingestion endpoint
- **Transaction_Submitter**: A service that reads prepared usage submissions from the relayer's SQLite store and submits them as on-chain transactions to the Diamond
- **Relayer_Wallet**: The Ethereum account (private key + address) used by the Transaction_Submitter to sign and send on-chain transactions; must hold Relayer_Role on the Diamond
- **Signing_Key**: The secp256k1 private key used by the Relayer_Wallet for Ethereum transaction signing
- **Encryption_Key**: The secp256k1 private key used by the relayer for ECIES mailbox encryption/decryption via mailbox-sdk; distinct from the Signing_Key
- **Confirmation_Depth**: The number of blocks the Event_Listener waits before treating a log as finalized, to handle chain reorganizations
- **Nonce_Manager**: A component that tracks and assigns sequential nonce values for the Relayer_Wallet to prevent nonce collisions across concurrent transaction submissions
- **OnchainEvent**: The Zod-validated event payload accepted by the relayer's `POST /events/onchain` endpoint, containing `chainId`, `blockNumber`, `logIndex`, `eventType`, `agreementId`, and optional `envelope`/`provider`/`reason` fields
- **UsageSubmissionRecord**: A record in the relayer's SQLite `usage_submissions` table containing aggregated usage items (`unitType`, `amount`) prepared by the `DeterministicMeteringWorker` for on-chain settlement
- **UsageSettlementSender**: The interface (`send(submission) → {status, txHash?, message?}`) that the `UsageSettlementService` delegates to for submitting usage; Phase 2 provides an on-chain implementation
- **Reorg**: A chain reorganization where previously confirmed blocks are replaced, potentially invalidating events the Event_Listener already forwarded
- **Target_Chain**: The chain where the Diamond is deployed and where the relayer submits usage settlement transactions (e.g. Arbitrum Sepolia `421614`, Arbitrum One `42161`, Base Sepolia `84532`)
- **Anvil**: A local Ethereum development node (from Foundry) used for deterministic integration testing

## Requirements

### Requirement 1: Event Listener — Contract Event Subscription

**User Story:** As a relayer operator, I want the Event_Listener to subscribe to Diamond proxy events via JSON-RPC polling, so that on-chain state changes are automatically forwarded to the relayer's ingestion engine.

#### Acceptance Criteria

1. WHEN the Event_Listener starts, THE Event_Listener SHALL connect to the configured RPC endpoint and begin polling for logs from the Diamond proxy address starting at the configured start block
2. THE Event_Listener SHALL subscribe to the following event signatures on the Diamond proxy: `AgreementActivated`, `BorrowerPayloadPublished`, `ProviderPayloadPublished`, `CoverageCovenantBreached`, `DrawRightsTerminated`, `AgreementDefaulted`, `AgreementClosed`, `DrawExecuted`, `RepaymentApplied`, `NativeEncumbranceUpdated`
3. WHEN a new block containing Diamond proxy logs is detected, THE Event_Listener SHALL decode each log using the Diamond ABI and map the event to the corresponding `eventType` field expected by the `onchainEventSchema`
4. THE Event_Listener SHALL map `AgreementActivated` events to `eventType: "activation"` with the `agreementId` extracted from the indexed event parameter
5. BECAUSE `AgreementActivated` does not include provider metadata on-chain, THE relayer SHALL resolve activation context (`provider`, borrower address) from on-chain agreement state (`getAgreement`) before provisioning
6. THE Event_Listener SHALL map `BorrowerPayloadPublished` events to `eventType: "mailbox"` with the `agreementId` and decoded `envelope` fields
7. THE Event_Listener SHALL map `CoverageCovenantBreached`, `DrawRightsTerminated`, `AgreementDefaulted`, and `AgreementClosed` to deterministic risk/lifecycle event types consumed by the ingestion worker kill-switch flow
8. IF the RPC endpoint returns an error or times out, THEN THE Event_Listener SHALL retry the poll with exponential backoff up to a configurable maximum interval
9. IF the Event_Listener encounters an undecodable log from the Diamond proxy address, THEN THE Event_Listener SHALL log a warning with the raw log data and skip the log without halting

### Requirement 2: Event Listener — Reorg Handling

**User Story:** As a relayer operator, I want the Event_Listener to handle chain reorganizations, so that the relayer does not process events from orphaned blocks.

#### Acceptance Criteria

1. THE Event_Listener SHALL maintain a configurable Confirmation_Depth parameter (default SHOULD be chosen per Target_Chain)
2. THE Event_Listener SHALL delay forwarding events to the relayer until the event's block has reached the configured Confirmation_Depth
3. WHEN a previously seen block hash at a given block number changes during polling, THE Event_Listener SHALL discard all pending (unconfirmed) events from the orphaned block and re-scan from the reorganized block number
4. THE Event_Listener SHALL persist the last confirmed block number to durable storage so that restarts resume from the correct position

### Requirement 3: Event Listener — Block Cursor Persistence

**User Story:** As a relayer operator, I want the Event_Listener to persist its scanning position, so that restarts do not re-process already-confirmed events or miss new events.

#### Acceptance Criteria

1. THE Event_Listener SHALL persist the last confirmed block number to the relayer's SQLite database after each successful batch of events is forwarded
2. WHEN the Event_Listener starts and a persisted block cursor exists, THE Event_Listener SHALL resume polling from `lastConfirmedBlock + 1`
3. WHEN the Event_Listener starts and no persisted block cursor exists, THE Event_Listener SHALL begin polling from the configured `startBlock` parameter
4. IF the persisted block cursor is ahead of the chain head, THEN THE Event_Listener SHALL wait for the chain to advance before resuming

### Requirement 4: Event Listener — Event Delivery to Relayer

**User Story:** As a relayer operator, I want decoded contract events to be delivered to the relayer's ingestion engine, so that the existing provisioning, metering, and kill-switch workflows are triggered.

#### Acceptance Criteria

1. WHEN the Event_Listener has a confirmed event, THE Event_Listener SHALL construct an `OnchainEvent` payload matching the `onchainEventSchema` with `chainId`, `blockNumber`, `logIndex`, `txHash`, `eventType`, and `agreementId`
2. WHEN the event is `BorrowerPayloadPublished`, THE Event_Listener SHALL decode the envelope bytes from the log, parse the UTF-8 JSON string, and include the parsed `envelope` object in the `OnchainEvent` payload
3. THE Event_Listener SHALL deliver the constructed `OnchainEvent` to the relayer by calling the `OnchainEventIngestionWorker.ingest()` method directly (in-process) rather than via HTTP
4. WHEN the `OnchainEventIngestionWorker` returns a result with `accepted: false`, THE Event_Listener SHALL log the rejection reason at error level with the event key and agreement ID
5. THE Event_Listener SHALL include the `txHash` field in every delivered `OnchainEvent` payload

### Requirement 5: Transaction Submitter — On-Chain Usage Settlement

**User Story:** As a relayer operator, I want the Transaction_Submitter to submit prepared usage records as on-chain transactions, so that off-chain metered usage is recorded in the Diamond contracts.

#### Acceptance Criteria

1. THE Transaction_Submitter SHALL implement the `UsageSettlementSender` interface so that the existing `UsageSettlementService` can delegate to it without modification
2. WHEN the `UsageSettlementService` calls `send(submission)`, THE Transaction_Submitter SHALL read the submission's `items` array and call `registerUsage(agreementId, unitType, amount)` on the `ComputeUsageFacet` for single-item submissions
3. WHEN the `UsageSettlementService` calls `send(submission)` with multiple items, THE Transaction_Submitter SHALL call `batchRegisterUsage(entries)` on the `ComputeUsageFacet` in a single transaction
4. WHEN the on-chain transaction is confirmed, THE Transaction_Submitter SHALL return `{status: "ok", txHash}` to the `UsageSettlementService`
5. IF the on-chain transaction reverts, THEN THE Transaction_Submitter SHALL return `{status: "error", message}` with the revert reason decoded from the transaction receipt
6. IF the on-chain transaction is not confirmed within a configurable timeout (default: 60 seconds), THEN THE Transaction_Submitter SHALL return `{status: "error", message: "tx_timeout"}` and log the pending transaction hash

### Requirement 6: Transaction Submitter — On-Chain Provider Payload Publication

**User Story:** As a relayer operator, I want the Transaction_Submitter to publish encrypted provider credentials on-chain after successful provider provisioning, so that borrower agents can retrieve their compute access keys from the Diamond mailbox regardless of provider.

#### Acceptance Criteria

1. WHEN the `OnchainEventIngestionWorker` completes a successful activation (`provider` in `{"venice","bankr","lambda","runpod"}`), THE Transaction_Submitter SHALL encrypt the provider credentials using the borrower's registered encryption public key via the mailbox-sdk
2. WHEN the encrypted envelope is ready, THE Transaction_Submitter SHALL call `publishProviderPayload(agreementId, envelopeBytes)` on the `AgenticMailboxFacet`
3. THE Transaction_Submitter SHALL read the borrower's encryption public key from the `AgentEncPubRegistryFacet.getEncPubKey()` view function before encrypting
4. IF the borrower has no registered encryption public key, THEN THE Transaction_Submitter SHALL log an error and skip the provider payload publication for that agreement
5. IF the `publishProviderPayload` transaction reverts, THEN THE Transaction_Submitter SHALL log the revert reason and trigger an alert via the relayer's alerting webhook
6. THE encrypted provider payload format SHALL include provider identifier and provider resource reference (`provider`, `providerResourceId`) so borrower agents can deterministically route decryption output to the correct provider client

### Requirement 7: Nonce Manager

**User Story:** As a relayer operator, I want the Transaction_Submitter to manage nonces sequentially, so that concurrent transaction submissions do not fail due to nonce collisions.

#### Acceptance Criteria

1. THE Nonce_Manager SHALL track the next nonce for the Relayer_Wallet locally, initializing from `eth_getTransactionCount(address, "pending")` on startup
2. WHEN a transaction is submitted, THE Nonce_Manager SHALL assign the next sequential nonce and increment the local counter
3. IF a transaction fails with a nonce-related error (nonce too low, replacement underpriced), THEN THE Nonce_Manager SHALL re-sync the local nonce from the chain via `eth_getTransactionCount` and retry the transaction once
4. THE Nonce_Manager SHALL serialize transaction submissions to prevent concurrent nonce assignment races

### Requirement 8: Gas Estimation and Pricing

**User Story:** As a relayer operator, I want the Transaction_Submitter to estimate gas and set appropriate gas prices, so that transactions are confirmed promptly without overpaying.

#### Acceptance Criteria

1. THE Transaction_Submitter SHALL use EIP-1559 gas pricing with `maxFeePerGas` and `maxPriorityFeePerGas` derived from the RPC provider's `eth_feeHistory` or `eth_gasPrice` response
2. THE Transaction_Submitter SHALL estimate gas for each transaction via `eth_estimateGas` before submission and apply a configurable gas limit multiplier (default: 1.2) as a safety margin
3. IF `eth_estimateGas` fails (indicating the transaction would revert), THEN THE Transaction_Submitter SHALL skip submission and return `{status: "error", message}` with the estimated revert reason
4. THE Transaction_Submitter SHALL enforce a configurable maximum gas price ceiling to prevent runaway costs on gas spikes

### Requirement 9: Relayer Wallet Configuration

**User Story:** As a relayer operator, I want to configure the relayer wallet via environment variables, so that the signing key is provided securely at deployment time without hardcoding.

#### Acceptance Criteria

1. THE Transaction_Submitter SHALL read the Signing_Key from the `RELAYER_PRIVATE_KEY` environment variable as a hex-encoded secp256k1 private key
2. THE Transaction_Submitter SHALL derive the Relayer_Wallet address from the Signing_Key and log the derived address at startup (without logging the private key)
3. IF the `RELAYER_PRIVATE_KEY` environment variable is missing or invalid, THEN THE Transaction_Submitter SHALL fail startup with a descriptive error message
4. THE Transaction_Submitter SHALL read the Encryption_Key from the `RELAYER_ENCRYPTION_PRIVATE_KEY` environment variable, separate from the Signing_Key
5. IF the `RELAYER_ENCRYPTION_PRIVATE_KEY` environment variable is missing, THEN THE Transaction_Submitter SHALL log a warning and disable provider payload publication

### Requirement 10: Key Separation

**User Story:** As a security auditor, I want the relayer's transaction signing key and mailbox encryption key to be separate, so that compromise of one key does not compromise the other.

#### Acceptance Criteria

1. THE Transaction_Submitter SHALL use the Signing_Key exclusively for Ethereum transaction signing (`eth_sendRawTransaction`)
2. THE Transaction_Submitter SHALL use the Encryption_Key exclusively for ECIES encryption of provider payloads via the mailbox-sdk
3. THE Transaction_Submitter SHALL validate at startup that the Signing_Key and Encryption_Key are different private keys
4. IF the Signing_Key and Encryption_Key are identical, THEN THE Transaction_Submitter SHALL fail startup with an error indicating key separation is required


### Requirement 11: Environment Configuration

**User Story:** As a relayer operator, I want all chain-specific parameters to be configurable via environment variables, so that the relayer can target different networks without code changes.

#### Acceptance Criteria

1. THE Event_Listener SHALL read the RPC endpoint URL from the `RPC_URL` environment variable
2. THE Event_Listener SHALL read the Diamond proxy contract address from the `DIAMOND_ADDRESS` environment variable
3. THE Event_Listener SHALL read the chain ID from the `CHAIN_ID` environment variable and validate it matches the chain ID returned by the RPC endpoint
4. THE Event_Listener SHALL read the start block number from the `EVENT_LISTENER_START_BLOCK` environment variable (default: 0)
5. THE Event_Listener SHALL read the Confirmation_Depth from the `CONFIRMATION_DEPTH` environment variable (default: 12)
6. IF `RPC_URL` or `DIAMOND_ADDRESS` is missing, THEN THE Event_Listener SHALL fail startup with a descriptive error message
7. IF `CHAIN_ID` does not match the RPC endpoint's chain ID, THEN THE Event_Listener SHALL fail startup with a chain ID mismatch error

### Requirement 12: Event Listener — Polling Interval Configuration

**User Story:** As a relayer operator, I want to configure the event polling interval, so that I can balance latency against RPC rate limits for different network environments.

#### Acceptance Criteria

1. THE Event_Listener SHALL read the polling interval from the `EVENT_POLL_INTERVAL_MS` environment variable (default: 2000 milliseconds)
2. THE Event_Listener SHALL poll for new blocks at the configured interval using `eth_blockNumber` followed by `eth_getLogs` for any new block range
3. WHILE no new blocks are available, THE Event_Listener SHALL wait for the next polling interval without making `eth_getLogs` calls

### Requirement 13: Transaction Submitter — Agreement ID Encoding

**User Story:** As a relayer operator, I want the Transaction_Submitter to correctly encode agreement IDs for on-chain calls, so that the relayer's string-based agreement IDs map to the Diamond's uint256 agreement IDs.

#### Acceptance Criteria

1. WHEN the Transaction_Submitter prepares a `registerUsage` or `publishProviderPayload` call, THE Transaction_Submitter SHALL convert the `UsageSubmissionRecord.agreementId` string to a `uint256` value for the contract call
2. WHEN the Event_Listener decodes an on-chain event, THE Event_Listener SHALL convert the `uint256 agreementId` from the event log to the string representation used by the relayer's `onchainEventSchema`
3. IF the agreement ID string cannot be parsed as a valid uint256, THEN THE Transaction_Submitter SHALL reject the submission with `{status: "error", message: "invalid_agreement_id"}`

### Requirement 14: Transaction Submitter — Unit Amount Scaling

**User Story:** As a relayer operator, I want the Transaction_Submitter to correctly scale usage amounts for on-chain submission, so that the relayer's decimal string amounts map to the Diamond's uint256 scaled integers.

#### Acceptance Criteria

1. WHEN the Transaction_Submitter prepares a `registerUsage` call, THE Transaction_Submitter SHALL convert each item's `amount` from the relayer's decimal string representation to a `uint256` scaled by `UNIT_SCALE` (10^18) as expected by the `ComputeUsageFacet`
2. IF the decimal string amount results in a value that exceeds `uint256` range after scaling, THEN THE Transaction_Submitter SHALL reject the submission with `{status: "error", message: "amount_overflow"}`
3. IF the decimal string amount is zero or negative, THEN THE Transaction_Submitter SHALL reject the submission with `{status: "error", message: "invalid_amount"}`

### Requirement 15: Health Check and Status Reporting

**User Story:** As a relayer operator, I want health check endpoints for the Event_Listener and Transaction_Submitter, so that I can monitor the integration layer's operational status.

#### Acceptance Criteria

1. THE Event_Listener SHALL expose its status via the relayer's existing health endpoint, reporting `lastConfirmedBlock`, `chainHead`, `blocksBehind`, and `isPolling`
2. THE Transaction_Submitter SHALL expose its status via the relayer's existing health endpoint, reporting `walletAddress`, `walletBalance`, `pendingNonce`, and `isEnabled`
3. WHEN the Relayer_Wallet balance falls below a configurable threshold (default: 0.01 ETH), THE Transaction_Submitter SHALL log a warning and trigger an alert via the relayer's alerting webhook
4. THE provider event ingress SHALL expose callback ingest health via the relayer's health endpoint, including ingress enabled flag and most recent accepted callback time when available

### Requirement 16: Structured Logging

**User Story:** As a relayer operator, I want the Event_Listener and Transaction_Submitter to produce structured logs with correlation IDs, so that I can trace events from chain detection through on-chain settlement.

#### Acceptance Criteria

1. THE Event_Listener SHALL include `chainId`, `blockNumber`, `logIndex`, `txHash`, `eventType`, and `agreementId` in every log entry related to event processing
2. THE Transaction_Submitter SHALL include `agreementId`, `submissionId`, `txHash`, `nonce`, and `gasUsed` in every log entry related to transaction submission
3. WHEN a `traceId` is available from the relayer's event processing context, THE Event_Listener and Transaction_Submitter SHALL propagate the `traceId` in log entries
4. THE provider event ingress SHALL include `provider`, `providerResourceId`, `externalEventId`, and auth result (`accepted`/`rejected`) in callback processing logs

### Requirement 17: Integration Test — Full Lifecycle

**User Story:** As a developer, I want an end-to-end integration test covering the complete financing lifecycle, so that I can verify the relayer-to-contract integration works correctly.

#### Acceptance Criteria

1. THE integration test SHALL deploy the Phase 1 Diamond contracts to a local Anvil instance
2. THE integration test SHALL grant Relayer_Role to the test relayer wallet address on the deployed Diamond
3. THE integration test SHALL execute the full lifecycle: create proposal → approve proposal → activate agreement → Event_Listener detects `AgreementActivated` → relayer auto-resolves activation context from on-chain agreement state → relayer provisions provider credentials (mocked) → Transaction_Submitter calls `publishProviderPayload` on-chain → `DeterministicMeteringWorker` polls usage (mocked) → Transaction_Submitter calls `registerUsage` on-chain → borrower calls `applyRepayment` → borrower calls `closeAgreement`
4. THE integration test SHALL verify that the on-chain agreement state reflects the correct `principalDrawn` after usage registration
5. THE integration test SHALL verify that the on-chain mailbox contains the provider payload after publication
6. THE integration test SHALL verify that the Event_Listener's block cursor advances correctly through the lifecycle

### Requirement 18: Integration Test — Reorg Simulation

**User Story:** As a developer, I want an integration test that simulates a chain reorganization, so that I can verify the Event_Listener correctly discards orphaned events.

#### Acceptance Criteria

1. THE integration test SHALL use Anvil's `evm_revert` and `evm_snapshot` capabilities to simulate a chain reorganization
2. THE integration test SHALL verify that events from the orphaned branch are not forwarded to the relayer's ingestion engine
3. THE integration test SHALL verify that events from the canonical branch are forwarded after the reorg resolves

### Requirement 19: Integration Test — Transaction Failure Recovery

**User Story:** As a developer, I want an integration test that verifies transaction failure recovery, so that I can confirm the retry logic works for reverted or timed-out transactions.

#### Acceptance Criteria

1. THE integration test SHALL simulate a `registerUsage` transaction that reverts (e.g., by submitting usage exceeding the credit limit) and verify the Transaction_Submitter returns `{status: "error"}` with the revert reason
2. THE integration test SHALL verify that the `UsageSettlementService` schedules a retry after a failed settlement attempt
3. THE integration test SHALL simulate a nonce desync and verify the Nonce_Manager re-syncs and retries successfully

### Requirement 20: Event Listener — Idempotent Delivery

**User Story:** As a relayer operator, I want the Event_Listener to guarantee that duplicate event delivery does not cause duplicate processing, so that the system is resilient to restarts and re-scans.

#### Acceptance Criteria

1. THE Event_Listener SHALL rely on the `OnchainEventIngestionWorker`'s existing idempotent deduplication by `chainId:blockNumber:logIndex` event key
2. WHEN the Event_Listener re-scans a block range after a restart, THE Event_Listener SHALL deliver all events from the range and rely on the ingestion worker to deduplicate already-processed events
3. THE Event_Listener SHALL log deduplicated events at debug level without treating them as errors

### Requirement 21: Event Listener — Graceful Shutdown

**User Story:** As a relayer operator, I want the Event_Listener to shut down gracefully, so that in-flight event processing completes and the block cursor is persisted before exit.

#### Acceptance Criteria

1. WHEN a shutdown signal (SIGTERM, SIGINT) is received, THE Event_Listener SHALL stop polling for new blocks
2. WHEN a shutdown signal is received, THE Event_Listener SHALL wait for any in-flight event batch to finish processing before persisting the block cursor
3. WHEN a shutdown signal is received, THE Transaction_Submitter SHALL wait for any in-flight transaction to be confirmed or timed out before exiting

### Requirement 22: Event Delivery Ordering

**User Story:** As a relayer operator, I want events to be delivered in block order and log index order, so that the relayer processes state transitions in the correct sequence.

#### Acceptance Criteria

1. THE Event_Listener SHALL deliver events to the ingestion worker ordered by `blockNumber` ascending, then `logIndex` ascending within each block
2. THE Event_Listener SHALL process events from one block completely before advancing to the next block
3. IF event delivery for a block fails, THEN THE Event_Listener SHALL retry the entire block before advancing

### Requirement 23: Transaction Confirmation Tracking

**User Story:** As a relayer operator, I want the Transaction_Submitter to track transaction confirmations, so that I can verify submitted transactions are included in the canonical chain.

#### Acceptance Criteria

1. WHEN a transaction is submitted, THE Transaction_Submitter SHALL poll for the transaction receipt until it is confirmed or the timeout is reached
2. WHEN a transaction receipt is received with `status: 1` (success), THE Transaction_Submitter SHALL return `{status: "ok", txHash}`
3. WHEN a transaction receipt is received with `status: 0` (revert), THE Transaction_Submitter SHALL decode the revert reason from the receipt and return `{status: "error", message, txHash}`
4. THE Transaction_Submitter SHALL log the confirmed transaction with `blockNumber`, `gasUsed`, `effectiveGasPrice`, and `txHash`

### Requirement 24: Event-to-OnchainEvent Mapping Round-Trip

**User Story:** As a protocol integrator, I want the event decoding and encoding to be lossless, so that on-chain event data is faithfully represented in the relayer's event schema.

#### Acceptance Criteria

1. FOR ALL `AgreementActivated` events emitted by the Diamond, THE Event_Listener SHALL produce an `OnchainEvent` where `agreementId` equals the string representation of the event's `uint256 agreementId` parameter, and activation context enrichment SHALL resolve `provider` from on-chain agreement state before provisioning
2. FOR ALL `BorrowerPayloadPublished` events emitted by the Diamond, THE Event_Listener SHALL produce an `OnchainEvent` where the `envelope` field, when re-serialized to bytes and compared to the original event's `envelope` parameter, is byte-equivalent (round-trip property)
3. FOR ALL `OnchainEvent` payloads produced by the Event_Listener, THE payload SHALL pass validation against the relayer's `onchainEventSchema` without modification

### Requirement 25: Usage Amount Scaling Round-Trip

**User Story:** As a protocol integrator, I want usage amount conversions between the relayer's decimal strings and the contract's uint256 values to be lossless, so that metered usage is accurately recorded on-chain.

#### Acceptance Criteria

1. FOR ALL `UsageSubmissionRecord` items with valid decimal string amounts, THE Transaction_Submitter SHALL produce a `uint256` scaled value such that `scaledValue / UNIT_SCALE` equals the original decimal amount to the precision supported by uint256
2. FOR ALL `DrawExecuted` events decoded by the Event_Listener, THE Event_Listener SHALL convert the `uint256 amount` and `uint256 units` back to string representations that match the original submission values (round-trip property)

### Requirement 26: Provider Webhook/Event Ingestion

**User Story:** As a relayer operator, I want provider callbacks (for example RunPod async completion webhooks) to be ingested by the relayer, so that usage accounting does not depend solely on short-lived polling windows.

#### Acceptance Criteria

1. THE relayer SHALL expose an authenticated provider event ingress endpoint for signed or bearer-authenticated provider callbacks
2. WHEN a provider event is accepted, THE relayer SHALL persist it to durable storage with dedup key `(provider, providerResourceId, externalEventId)`
3. THE usage metering pipeline SHALL consume persisted provider events as a primary source for async job completion accounting, with polling as fallback
4. IF a provider webhook is unavailable or delayed, THEN THE relayer SHALL continue polling fallback logic without double-counting events already ingested via webhook
5. THE provider event ingress SHALL emit structured logs containing `provider`, `providerResourceId`, `externalEventId`, `agreementId` (if known), and `traceId` when available
6. THE provider event ingress authentication secret SHALL be configurable via environment variable (`PROVIDER_EVENT_AUTH_TOKEN`) and MUST fail closed when auth is configured but missing/invalid on requests

### Requirement 27: Offchain ERC-8004 Identity Resolver (Hackathon Cross-Chain Mode)

**User Story:** As a relayer operator, I want a temporary offchain ERC-8004 identity verification mode for cross-chain deployments, so that provider provisioning and payload publication can be gated without introducing an onchain bridge/oracle in hackathon scope.

#### Acceptance Criteria

1. THE relayer SHALL support `IDENTITY_MODE` with allowed values `none` and `erc8004_offchain`
2. WHEN `IDENTITY_MODE=erc8004_offchain`, THE relayer SHALL require an identity proof from the borrower payload before provider provisioning and `publishProviderPayload` submission
3. THE identity proof payload SHALL include at least `mode`, `chainId` (ERC-8004 source chain), `agentRegistry`, `agentId`, `authorizedAddress`, `agreementId`, `targetChainId`, `expiresAt`, and `signature`
4. WHEN verifying a proof in `erc8004_offchain` mode, THE relayer SHALL reject proofs with mismatched `targetChainId`, mismatched `agreementId`, or expired `expiresAt` (allowing configurable clock skew)
5. THE relayer SHALL resolve the ERC-8004 wallet for `(agentRegistry, agentId)` using configured ERC-8004 RPC/registry settings and SHALL fail verification if resolution fails
6. THE relayer SHALL recover the proof signer and SHALL require signer equivalence with `authorizedAddress`
7. THE relayer SHALL require resolved ERC-8004 wallet equivalence with `authorizedAddress`; mismatches SHALL fail verification
8. WHEN `IDENTITY_MODE=none`, THE relayer SHALL skip identity verification and SHALL log that identity enforcement is disabled
9. THE relayer SHALL treat this identity verification path as offchain-only and SHALL NOT require any Phase 1/Phase 2 Diamond contract changes
10. THE test suite SHALL include positive and negative verification coverage (expired proof, wrong chain, wrong agreement, signature mismatch, resolved wallet mismatch) and an integration path proving gating behavior in `erc8004_offchain` mode
