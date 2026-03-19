# Implementation Plan: Synthesis Phase 2 — Relayer Integration

## Overview

Incremental build of the EventListener, TransactionSubmitter, and ProviderEventIngress modules inside the existing `mailbox-relayer` TypeScript codebase. Tasks follow bottom-up order: shared utilities and store extensions first, then core components by dependency order, then integration wiring and tests. All new code lives under `mailbox-relayer/src/` and `mailbox-relayer/test/`.

## Tasks

- [x] 1. Shared utilities and store extensions
  - [x] 1.1 Add `ethers` v6 and `async-mutex` dependencies
    - Run `npm install ethers@^6 async-mutex` in `mailbox-relayer/`
    - Add `fast-check` as dev dependency: `npm install -D fast-check`
    - Verify `package.json` updated and `npm run build` still compiles
    - _Requirements: Design Decision 2, Design Decision 4_

  - [x] 1.2 Implement agreement ID and amount conversion utilities
    - Create `mailbox-relayer/src/conversion.ts`
    - Implement `agreementIdToUint256(id: string): bigint` — parse string as non-negative integer, throw on invalid input (negative, fractional, non-numeric, exceeds uint256 max)
    - Implement `uint256ToAgreementId(id: bigint): string` — convert bigint to decimal string
    - Implement `scaleAmountToUint256(decimalAmount: string): bigint` — parse decimal string, multiply by `UNIT_SCALE` (10^18), throw on zero, negative, overflow
    - Implement `uint256ToDecimalAmount(scaled: bigint): string` — divide by `UNIT_SCALE`, format as decimal string with up to 18 decimal places, strip trailing zeros
    - Implement `unitTypeToBytes32(unitType: string): string` — `keccak256(toUtf8Bytes(unitType))` via ethers
    - Export `UNIT_SCALE = 10n ** 18n`
    - _Requirements: 13.1, 13.2, 13.3, 14.1, 14.2, 14.3_

  - [x] 1.3 Extend SQLite store with `block_cursors` and `provider_events` tables
    - Add `block_cursors` table creation to the store's schema initialization: `CREATE TABLE IF NOT EXISTS block_cursors (chain_id INTEGER NOT NULL, last_confirmed INTEGER NOT NULL, block_hash TEXT, updated_at TEXT NOT NULL, PRIMARY KEY (chain_id))`
    - Add `provider_events` table creation: `CREATE TABLE IF NOT EXISTS provider_events (provider TEXT NOT NULL, provider_resource_id TEXT NOT NULL, external_event_id TEXT NOT NULL, payload_json TEXT NOT NULL, observed_at TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY (provider, provider_resource_id, external_event_id))`
    - Add `setBlockCursor(chainId: number, lastConfirmed: number, blockHash?: string): void` to `MessageStore` interface and SQLite implementation
    - Add `getBlockCursor(chainId: number): { lastConfirmed: number; blockHash?: string } | undefined` to `MessageStore` interface and SQLite implementation
    - Add `upsertProviderEvent(...)` and `listProviderEvents(...)` methods to store interface + SQLite implementation
    - _Requirements: 3.1, 3.2, 26.2, 26.3_

  - [x] 1.4 Create environment configuration schema and validator
    - Create `mailbox-relayer/src/env-config.ts`
    - Implement `phase2EnvSchema` Zod schema matching the design doc (RPC_URL, DIAMOND_ADDRESS, CHAIN_ID, EVENT_LISTENER_START_BLOCK, CONFIRMATION_DEPTH, EVENT_POLL_INTERVAL_MS, RELAYER_PRIVATE_KEY, RELAYER_ENCRYPTION_PRIVATE_KEY, TX_TIMEOUT_MS, GAS_LIMIT_MULTIPLIER, MAX_GAS_PRICE_GWEI, LOW_BALANCE_THRESHOLD_ETH, PROVIDER_EVENT_AUTH_TOKEN)
    - Implement `validatePhase2Env(env: Record<string, string | undefined>)` that parses env vars through the schema and returns typed config or throws descriptive errors
    - Implement key separation check: if both keys provided and identical, throw error
    - _Requirements: 9.1, 9.3, 9.4, 10.3, 10.4, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 12.1, 26.1_

- [x] 1.5 (Hackathon) Offchain ERC-8004 Identity Resolver for cross-chain deployments
  - Goal: allow deploying the Diamond on one chain (e.g. Arbitrum) while treating ERC-8004 identity as a **cross-chain/offchain-resolved** identifier (e.g. ERC-8004 registry on Base), without adding any onchain oracle/bridge for the hackathon.
  - This must be **soft enforcement**: it MUST be possible to run with `IDENTITY_MODE=none` to avoid blocking demo flows while contracts stabilize.
  - [x] 1.5.1 Define identity proof payload shape (offchain only)
    - Add a minimal `identity` object to the borrower mailbox envelope payload (inside the existing encrypted JSON), e.g.:
      - `identity.mode = "erc8004_offchain_v1"`
      - `identity.chainId = 8453` (Base mainnet) or `84532` (Base Sepolia) for the ERC-8004 registry source chain
      - `identity.targetChainId` for the Diamond deployment chain (`CHAIN_ID`)
      - `identity.agentRegistry` + `identity.agentId`
      - `identity.authorizedAddress` (the on-chain borrower EOA on Target_Chain)
      - `identity.signature` (EIP-712 or personal_sign over `(agentRegistry, agentId, authorizedAddress, targetChainId, agreementId, expiresAt)` with explicit domain separation that includes target chain and Diamond address)
      - `identity.expiresAt`
    - The relayer MUST treat this as an offchain gate only; no contract changes required.
    - _Requirements: 27.1, 27.2, 27.3, 27.4, 27.9_

  - [x] 1.5.2 Implement resolver module in relayer
    - Create `mailbox-relayer/src/identity-resolver.ts`
    - Implement `resolveErc8004Wallet(agentRegistry, agentId) -> address` (using a configured ERC-8004 RPC + registry address)
    - Implement `verifyIdentityProof(proof, agreementContext) -> { ok: boolean; reason?: string; resolvedWallet?: string }`
    - If `IDENTITY_MODE=erc8004_offchain`, relayer MUST require a valid proof before provisioning/publishing provider payloads.
    - If `IDENTITY_MODE=none`, relayer MUST skip verification (log only).
    - _Requirements: 27.2, 27.3, 27.4, 27.5, 27.6, 27.7_

  - [x] 1.5.3 Add env config for resolver
    - Add `IDENTITY_MODE` (`none` | `erc8004_offchain`)
    - Add `ERC8004_RPC_URL`, `ERC8004_CHAIN_ID`, `ERC8004_REGISTRY_ADDRESS` (source-of-truth chain, typically Base)
    - Add `IDENTITY_PROOF_MAX_SKEW_SECONDS` (clock skew tolerance)
    - _Requirements: 27.1, 27.8_

  - [x] 1.5.4 Tests
    - Unit tests: signature verification happy-path + failure cases (expired, wrong targetChainId, wrong agreementId)
    - Unit tests: mocked ERC-8004 registry response (resolvedWallet mismatch)
    - Integration-ish: with `IDENTITY_MODE=erc8004_offchain`, ensure relayer refuses to provision/publish without a valid identity proof in borrower payload
    - _Requirements: 27.4, 27.5, 27.6, 27.7, 27.10_

- [x] 2. Checkpoint — Shared utilities compile and store migrates
  - Verify `npm run build` compiles cleanly with new files. Verify SQLite store creates `block_cursors` and `provider_events` tables. Ask the user if questions arise.

- [x] 3. NonceManager implementation
  - [x] 3.1 Implement NonceManager class
    - Create `mailbox-relayer/src/nonce-manager.ts`
    - Constructor takes an ethers `JsonRpcProvider` and wallet address
    - `init()`: call `eth_getTransactionCount(address, "pending")`, store as local nonce counter
    - `acquireNonce()`: acquire async mutex lock, return current nonce, increment counter, release lock
    - `confirmNonce(nonce)`: no-op if nonce matches expected (counter already incremented in acquire)
    - `resync()`: re-fetch `eth_getTransactionCount(address, "pending")`, update local counter
    - `currentNonce()`: return current local counter value
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [x]* 3.2 Write unit tests for NonceManager
    - Test `init()` fetches nonce from mock provider
    - Test sequential `acquireNonce()` calls return monotonically increasing values
    - Test `resync()` updates local counter from chain
    - Test concurrent `acquireNonce()` calls are serialized (no duplicate nonces)
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [x] 4. GasEstimator implementation
  - [x] 4.1 Implement GasEstimator class
    - Create `mailbox-relayer/src/gas-estimator.ts`
    - Constructor takes an ethers `JsonRpcProvider`, `gasLimitMultiplier` (default 1.2), and `maxGasPriceGwei` (default 100)
    - `estimateGas(tx)`: call `eth_estimateGas`, multiply result by `gasLimitMultiplier`, ceil to integer
    - `getFeeData()`: call provider `getFeeData()`, cap `maxFeePerGas` at `maxGasPriceGwei * 10^9`, return `{ maxFeePerGas, maxPriorityFeePerGas }`
    - If `eth_estimateGas` throws, re-throw with descriptive message (caller handles)
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [x]* 4.2 Write unit tests for GasEstimator
    - Test gas estimate applies multiplier correctly
    - Test gas price ceiling enforcement
    - Test `eth_estimateGas` failure propagation
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 5. Checkpoint — NonceManager and GasEstimator
  - Verify `npm run build` compiles cleanly. Ask the user if questions arise.

- [x] 6. TransactionSubmitter implementation
  - [x] 6.1 Implement TransactionSubmitter class — core `send()` method
    - Create `mailbox-relayer/src/tx-submitter.ts`
    - Constructor takes `TxSubmitterConfig`, ethers `JsonRpcProvider`, `NonceManager`, `GasEstimator`, ethers `Wallet`, and optional `AlertingService`
    - Implement `UsageSettlementSender.send(submission)`:
      - Validate `agreementId` via `agreementIdToUint256()` — return `{status: "error", message: "invalid_agreement_id"}` on failure
      - Validate and scale each item's `amount` via `scaleAmountToUint256()` — return `{status: "error", message: "invalid_amount"}` or `"amount_overflow"` on failure
      - Convert each item's `unitType` via `unitTypeToBytes32()`
      - If single item: encode `registerUsage(uint256,bytes32,uint256)` calldata
      - If multiple items: encode `batchRegisterUsage((uint256,bytes32,uint256)[])` calldata
      - Call `GasEstimator.estimateGas()` — on failure return `{status: "error", message}` with revert reason
      - Call `GasEstimator.getFeeData()` — if `maxFeePerGas > maxGasPriceGwei * 10^9`, return `{status: "error", message: "gas_price_exceeded"}`
      - Call `NonceManager.acquireNonce()`
      - Sign and send raw transaction via wallet
      - Poll for receipt until confirmed or `txTimeoutMs` exceeded
      - On receipt `status: 1`: return `{status: "ok", txHash}`
      - On receipt `status: 0`: decode revert reason, return `{status: "error", message, txHash}`
      - On timeout: return `{status: "error", message: "tx_timeout"}`
      - On nonce error: call `NonceManager.resync()`, retry once
    - Log all submissions with `agreementId`, `submissionId`, `txHash`, `nonce`, `gasUsed` per Requirement 16.2
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 7.3, 8.1, 8.2, 8.3, 8.4, 13.1, 13.3, 14.1, 14.2, 14.3, 16.2, 23.1, 23.2, 23.3, 23.4_

  - [x] 6.2 Implement TransactionSubmitter — `publishProviderPayload()` method
    - Read borrower's encryption public key via `AgentEncPubRegistryFacet.getEncPubKey(borrowerAddress)` view call
    - If empty/no key: log error, return `{ error: "no_encryption_key" }` — skip publication
    - Accept provider credentials from any activated provider path (Venice/Bankr/Lambda/RunPod)
    - Encrypt `providerCredentials` using mailbox-sdk `MailboxCompat.encryptPayload(borrowerPubKey, credentials)`
    - Convert encrypted envelope to bytes via `MailboxCompat.envelopeToBytes()` or UTF-8 encode the envelope string
    - Encode `publishProviderPayload(uint256,bytes)` calldata
    - Submit transaction using same gas estimation + nonce management flow as `send()`
    - On revert: log revert reason, trigger alert via `AlertingService`
    - Return `{ txHash }` on success or `{ error }` on failure
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x] 6.3 Implement TransactionSubmitter — `status()` method
    - Return `{ walletAddress, walletBalance, pendingNonce, isEnabled }`
    - `walletAddress`: derived from signing key at construction
    - `walletBalance`: call `eth_getBalance(walletAddress)`, format as ETH string
    - `pendingNonce`: from `NonceManager.currentNonce()`
    - `isEnabled`: true if signing key is configured
    - If balance < `lowBalanceThresholdEth`: log warning, trigger alert (at most once per check)
    - _Requirements: 15.2, 15.3_

  - [x]* 6.4 Write unit tests for TransactionSubmitter
    - Test `send()` with single-item submission dispatches `registerUsage` calldata
    - Test `send()` with multi-item submission dispatches `batchRegisterUsage` calldata
    - Test invalid agreement ID returns `{status: "error", message: "invalid_agreement_id"}`
    - Test zero/negative amount returns `{status: "error", message: "invalid_amount"}`
    - Test amount overflow returns `{status: "error", message: "amount_overflow"}`
    - Test gas estimate failure returns error without submitting
    - Test gas price ceiling exceeded returns `{status: "error", message: "gas_price_exceeded"}`
    - Test successful tx returns `{status: "ok", txHash}`
    - Test reverted tx returns `{status: "error", message, txHash}` with decoded revert reason
    - Test timeout returns `{status: "error", message: "tx_timeout"}`
    - Test nonce error triggers resync and retry
    - Test `publishProviderPayload` with missing borrower key skips publication
    - Test `publishProviderPayload` with valid key encrypts and submits
    - Test `publishProviderPayload` receives Bankr/Lambda/RunPod provider credentials and publishes correctly
    - Test low balance alert fires once per check cycle
    - _Requirements: 5.1–5.6, 6.1–6.6, 7.3, 8.1–8.4, 13.1–13.3, 14.1–14.3, 15.2, 15.3, 23.1–23.4_

- [x] 7. Checkpoint — TransactionSubmitter
  - Verify `npm run build` compiles cleanly. Ask the user if questions arise.

- [x] 8. EventListener implementation
  - [x] 8.1 Implement EventListener class — polling loop and event decoding
    - Create `mailbox-relayer/src/event-listener.ts`
    - Constructor takes `EventListenerConfig`, ethers `JsonRpcProvider`, `MessageStore`, `OnchainEventIngestionWorker`, and a Pino logger
    - Build ethers `Interface` from Diamond ABI fragment containing the subscribed event signatures (activation, mailbox, risk/enforcement, and observability events)
    - Compute topic0 hashes for each event signature for `eth_getLogs` filter
    - `start()`:
      - Validate chain ID matches RPC endpoint (`eth_chainId`)
      - Load block cursor from store; if exists, resume from `lastConfirmed + 1`; if not, start from `config.startBlock`
      - If cursor ahead of chain head, wait for chain to advance
      - Begin poll loop at `config.pollIntervalMs`
    - Poll loop:
      - Call `eth_blockNumber` to get chain head
      - If no new blocks since last scan, skip
      - Call `eth_getLogs(diamondAddress, fromBlock, toBlock)` for new block range
      - Decode each log via ethers `Interface.parseLog()` — skip undecodable logs with warning
      - Group decoded events into `PendingBlock` objects by block number, storing block hash
      - Sort events within each block by `logIndex` ascending
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 11.3, 11.7, 12.1, 12.2, 12.3_

  - [x] 8.2 Implement EventListener — confirmation depth and reorg handling
    - After each poll, check pending blocks buffer:
      - For each pending block where `chainHead - blockNumber >= confirmationDepth`:
        - Fetch block hash via `eth_getBlockByNumber` (or cache from `eth_getLogs` response)
        - Compare with stored `PendingBlock.blockHash`
        - If hash changed (reorg): discard ALL pending blocks at `>= blockNumber`, reset scan position to `blockNumber`, log warning
        - If hash matches (confirmed): mark block ready for delivery
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 8.3 Implement EventListener — event delivery and cursor persistence
    - For each confirmed block (in ascending block number order):
      - For each event in the block (ascending logIndex order):
        - Map event to `OnchainEvent` payload:
          - `AgreementActivated` → `eventType: "activation"`, `agreementId: args.agreementId.toString()`; activation context (`provider`, borrower address) is resolved from on-chain `getAgreement` before provisioning
          - `BorrowerPayloadPublished` → `eventType: "mailbox"`, `agreementId: args.agreementId.toString()`, `envelope: JSON.parse(Buffer.from(args.envelope).toString('utf-8'))`
          - `ProviderPayloadPublished` → log only, do not deliver (emitted by relayer itself)
          - `CoverageCovenantBreached` → `eventType: "risk_covenant_breached"`, include `agreementId` and breach fields
          - `DrawRightsTerminated` → `eventType: "risk_draw_terminated"`, include `agreementId` and `reason`
          - `AgreementDefaulted` → `eventType: "risk_defaulted"`, include `agreementId` and `pastDue`
          - `AgreementClosed` → `eventType: "agreement_closed"`, include `agreementId`
          - `DrawExecuted`, `RepaymentApplied`, `NativeEncumbranceUpdated` → log only, do not deliver
        - Include `chainId`, `blockNumber`, `logIndex`, `txHash` in every payload
        - Call `OnchainEventIngestionWorker.ingest(onchainEvent)`
        - If `accepted: false`: log rejection at error level with event key and agreement ID
        - If ingestion throws: log error, abort block delivery (retry entire block next cycle)
      - After ALL events in block delivered successfully: persist block cursor via `store.setBlockCursor(chainId, blockNumber, blockHash)`
      - Remove block from pending buffer
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 22.1, 22.2, 22.3, 24.1, 24.2, 24.3_

  - [x] 8.4 Implement EventListener — RPC retry with exponential backoff
    - Wrap `eth_blockNumber` and `eth_getLogs` calls in retry logic
    - On RPC error or timeout: double the poll interval (starting from `pollIntervalMs`), cap at `maxRetryIntervalMs`
    - On first successful poll after failures: reset interval to `pollIntervalMs`
    - Log each retry attempt with error details
    - _Requirements: 1.6_

  - [x] 8.5 Implement EventListener — graceful shutdown
    - `stop()`:
      - Set `isPolling = false` to prevent new poll cycles
      - If a poll cycle is in-flight, wait for it to complete (await the current poll promise)
      - Persist final block cursor
      - Return when fully stopped
    - `status()`: return `{ lastConfirmedBlock, chainHead, blocksBehind, isPolling }`
    - _Requirements: 21.1, 21.2, 15.1_

  - [x] 8.6 Implement EventListener — structured logging
    - Include `chainId`, `blockNumber`, `logIndex`, `txHash`, `eventType`, `agreementId` in every event processing log entry
    - Propagate `traceId` when available from ingestion context
    - Log deduplicated events (ingestion worker returns deduped) at debug level
    - _Requirements: 16.1, 16.3, 20.3_

  - [x] 8.7 Implement ProviderEventIngress webhook endpoint
    - Create `mailbox-relayer/src/provider-event-ingress.ts`
    - Expose authenticated endpoint (e.g. `POST /events/provider`) that validates provider callback payloads
    - Persist deduped rows keyed by `(provider, providerResourceId, externalEventId)` to SQLite
    - Return idempotent success on duplicate events (no duplicate persistence)
    - Emit structured logs with provider callback identifiers and trace metadata
    - _Requirements: 16.4, 26.1, 26.2, 26.5, 26.6_

  - [x]* 8.8 Write unit tests for ProviderEventIngress
    - Test valid authenticated callback persists exactly one event row
    - Test duplicate callback key is idempotent and does not create a second row
    - Test invalid auth is rejected and not persisted
    - Test malformed payload returns validation error
    - _Requirements: 16.4, 26.1, 26.2, 26.5, 26.6_

  - [x]* 8.9 Write unit tests for EventListener
    - Test event decoding: mock `eth_getLogs` returning known ABI-encoded logs, verify correct `eventType` mapping
    - Test `AgreementActivated` → `activation` mapping with correct `agreementId`
    - Test `BorrowerPayloadPublished` → `mailbox` mapping with decoded envelope
    - Test `CoverageCovenantBreached` → `risk_covenant_breached` mapping
    - Test `DrawRightsTerminated` → `risk_draw_terminated` mapping
    - Test `AgreementDefaulted` → `risk_defaulted` mapping
    - Test `AgreementClosed` → `agreement_closed` mapping
    - Test undecodable log is skipped with warning (not crash)
    - Test confirmation depth: events at depth < `confirmationDepth` are NOT delivered
    - Test confirmation depth: events at depth >= `confirmationDepth` ARE delivered
    - Test reorg detection: change block hash between polls, verify orphaned events discarded
    - Test reorg detection: verify re-scan from reorged block number
    - Test block cursor persistence: verify cursor written after successful block delivery
    - Test block cursor resume: verify polling starts from `lastConfirmed + 1` on restart
    - Test block cursor missing: verify polling starts from `startBlock`
    - Test cursor ahead of chain head: verify wait behavior
    - Test event ordering: multiple events across blocks delivered in `(blockNumber, logIndex)` order
    - Test block-atomic delivery: if ingestion throws mid-block, cursor not advanced
    - Test RPC retry with backoff: mock RPC failures, verify interval doubles then resets
    - Test graceful shutdown: verify in-flight batch completes and cursor persisted
    - Test `ProviderPayloadPublished` logged but not delivered to ingestion worker
    - Test `DrawExecuted`, `RepaymentApplied`, `NativeEncumbranceUpdated` logged but not delivered
    - _Requirements: 1.1–1.7, 2.1–2.4, 3.1–3.4, 4.1–4.5, 12.1–12.3, 20.1–20.3, 21.1–21.2, 22.1–22.3_

- [x] 9. Checkpoint — EventListener
  - Verify `npm run build` compiles cleanly. Ask the user if questions arise.

- [x] 10. Integration wiring
  - [x] 10.1 Extend `buildApp` to accept EventListener and TransactionSubmitter
    - Add optional `eventListener?: EventListener`, `txSubmitter?: TransactionSubmitter`, and `providerEventIngress?: ProviderEventIngress` parameters to `buildApp()` signature
    - Extend `/health/ready` endpoint to include `eventListener.status()`, `txSubmitter.status()`, and `providerEventIngress.status()` in response
    - _Requirements: 15.1, 15.2, 26.5_

  - [x] 10.2 Create bootstrap module for Phase 2 initialization
    - Create `mailbox-relayer/src/bootstrap-phase2.ts`
    - Read and validate environment via `validatePhase2Env(process.env)`
    - Create ethers `JsonRpcProvider` from `RPC_URL`
    - Create ethers `Wallet` from `RELAYER_PRIVATE_KEY` connected to provider
    - Log derived wallet address (never log private key)
    - Validate key separation if encryption key provided
    - Create `NonceManager`, call `init()`
    - Create `GasEstimator`
    - Create `TransactionSubmitter`
    - Create `ProviderEventIngress` with store and auth config
    - Create `EventListener` with store, ingestion worker, and config
    - Wire `TransactionSubmitter` as the `UsageSettlementSender` for `UsageSettlementService` (replacing `DisabledUsageSettlementSender`)
    - Return `{ eventListener, txSubmitter, providerEventIngress }` for passing to `buildApp()`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 10.1, 10.2, 10.3, 10.4, 11.1–11.7, 26.6_

  - [x] 10.3 Update `index.ts` entry point to start EventListener after server listen
    - After `app.listen()`, call `eventListener.start()` if available
    - Register SIGTERM/SIGINT handlers that call `eventListener.stop()` and wait for TransactionSubmitter in-flight transactions before `app.close()`
    - _Requirements: 21.1, 21.2, 21.3_

  - [x] 10.4 Wire TransactionSubmitter into OnchainEventIngestionWorker for provider payload publication
    - After successful provider provisioning in the ingestion worker's activation flow, call `txSubmitter.publishProviderPayload(agreementId, credentials, borrowerAddress)`
    - This replaces the current flow where provider payloads are only stored locally
    - _Requirements: 6.1, 6.2_

  - [x] 10.5 Wire metering to consume provider events
    - Update metering read path to consume persisted provider callback events before fallback polling
    - Ensure dedup across webhook-ingested and polled job completions by external event/job ID
    - _Requirements: 26.3, 26.4_

- [x] 11. Checkpoint — Integration wiring
  - Verify `npm run build` compiles cleanly. Verify the relayer starts with Phase 2 env vars set (against a local Anvil node if available). Ask the user if questions arise.

- [x] 12. Property-based tests
  - [x]* 12.1 Write property test: Agreement ID encoding round-trip (Property 8)
    - **Property 8: Agreement ID encoding round-trip**
    - Use `fast-check` to generate arbitrary `bigint` values in `[0, 2^256 - 1]`
    - Verify `agreementIdToUint256(uint256ToAgreementId(n)) === n` for all generated values
    - Use `fast-check` to generate arbitrary non-negative integer strings
    - Verify `uint256ToAgreementId(agreementIdToUint256(s)) === s` for all generated strings
    - Verify invalid inputs (`"-1"`, `"abc"`, `"1.5"`, `""`) throw
    - **Validates: Requirements 13.1, 13.2, 24.1**

  - [x]* 12.2 Write property test: Usage amount scaling round-trip (Property 9)
    - **Property 9: Usage amount scaling round-trip**
    - Use `fast-check` to generate arbitrary positive decimal strings with up to 18 decimal places
    - Verify `uint256ToDecimalAmount(scaleAmountToUint256(d)) === d` for all generated values
    - Use `fast-check` to generate arbitrary positive `bigint` values
    - Verify `scaleAmountToUint256(uint256ToDecimalAmount(s)) === s` for all generated values
    - Verify edge cases: `"0.000000000000000001"` (1 wei), near-max values
    - Verify invalid inputs (`"0"`, `"-1"`, overflow) throw
    - **Validates: Requirements 14.1, 25.1, 25.2**

  - [x]* 12.3 Write property test: Event delivery ordering (Property 18)
    - **Property 18: Event delivery ordering**
    - Use `fast-check` to generate random sets of `(blockNumber, logIndex)` pairs
    - Feed through EventListener's sorting/delivery logic (extracted as testable function)
    - Verify output is strictly ordered by `(blockNumber ASC, logIndex ASC)`
    - **Validates: Requirements 22.1, 22.2**

  - [x]* 12.4 Write property test: Nonce monotonicity (Property 13)
    - **Property 13: Nonce monotonicity**
    - Use `fast-check` to generate arbitrary sequences of `acquireNonce()` calls (varying concurrency)
    - Verify all returned nonces are strictly monotonically increasing with no gaps
    - **Validates: Requirements 7.1, 7.2, 7.4**

  - [x]* 12.5 Write property test: Provider callback dedup (Property 26)
    - **Property 26: Provider callback idempotency and metering consumption**
    - Use `fast-check` to generate callback streams with duplicate `(provider, providerResourceId, externalEventId)` tuples
    - Verify persistence keeps at most one row per dedup key
    - Verify metering consumption emits at most one usage contribution per dedup key
    - **Validates: Requirements 26.2, 26.3, 26.4**

- [x] 13. Integration tests (Anvil)
  - [x]* 13.1 Write integration test: Full lifecycle (Requirement 17)
    - **Requirement 17: Integration Test — Full Lifecycle**
    - Start local Anvil instance
    - Deploy Phase 1 Diamond contracts (use compiled artifacts or Foundry deploy script)
    - Grant `Relayer_Role` to test relayer wallet
    - Configure compute unit pricing
    - Execute full lifecycle:
      1. Borrower calls `createProposal` on Diamond
      2. Lender calls `approveProposal`
      3. Borrower calls `registerEncPubKey` with test key
      4. Borrower calls `activateAgreement`
      5. EventListener detects `AgreementActivated` event
      6. Activation context resolver reads `getAgreement` and derives canonical provider + borrower
      7. Mock provider provisioning returns credentials
      8. TransactionSubmitter calls `publishProviderPayload` on-chain
      9. Verify `getProviderPayload` returns encrypted envelope
      10. Mock metering produces usage submission
      11. TransactionSubmitter calls `registerUsage` on-chain
      12. Verify `principalDrawn` updated on agreement
      13. Borrower calls `applyRepayment`
      14. Borrower calls `closeAgreement`
    - Verify EventListener block cursor advances through lifecycle
    - **Validates: Requirements 17.1, 17.2, 17.3, 17.4, 17.5, 17.6**

  - [x]* 13.6 Write integration test: Provider webhook ingestion (Requirement 26)
    - Start relayer with ProviderEventIngress enabled
    - Submit authenticated provider callback payloads containing duplicate `externalEventId`
    - Verify only one persisted row per dedup key and structured logs emitted
    - Verify metering consumes provider callback event and emits one usage record
    - Verify fallback polling path does not double-count webhook-ingested usage
    - **Validates: Requirements 26.1, 26.2, 26.3, 26.4, 26.5, 26.6**

  - [x]* 13.2 Write integration test: Reorg simulation (Requirement 18)
    - **Requirement 18: Integration Test — Reorg Simulation**
    - Start Anvil, deploy Diamond
    - Create and activate an agreement (emit `AgreementActivated`)
    - Take Anvil snapshot
    - Mine additional blocks with new events
    - Revert to snapshot (simulating reorg)
    - Mine different blocks on canonical branch
    - Verify EventListener discards orphaned events
    - Verify EventListener delivers canonical branch events
    - **Validates: Requirements 18.1, 18.2, 18.3**

  - [x]* 13.3 Write integration test: Transaction failure recovery (Requirement 19)
    - **Requirement 19: Integration Test — Transaction Failure Recovery**
    - Start Anvil, deploy Diamond, grant relayer role
    - Submit `registerUsage` with amount exceeding credit limit → verify `{status: "error"}` with revert reason
    - Verify `UsageSettlementService` schedules retry
    - Manually send a tx from relayer wallet to desync nonce → submit another `registerUsage` → verify NonceManager re-syncs and retries
    - **Validates: Requirements 19.1, 19.2, 19.3**

  - [x]* 13.4 Write integration test: Idempotent re-delivery (Requirement 20)
    - **Requirement 20: Integration Test — Idempotent Delivery**
    - Start Anvil, deploy Diamond, activate agreement
    - Run EventListener to process activation event
    - Stop EventListener, restart it (cursor should resume)
    - If cursor causes re-scan of same block range, verify ingestion worker deduplicates
    - Verify no duplicate state changes in relayer store
    - **Validates: Requirements 20.1, 20.2, 20.3**

  - [x]* 13.5 Write integration test: Graceful shutdown (Requirement 21)
    - **Requirement 21: Integration Test — Graceful Shutdown**
    - Start Anvil, deploy Diamond, emit several events across blocks
    - Start EventListener with fast polling
    - Call `eventListener.stop()` during active processing
    - Verify block cursor reflects last fully-delivered block
    - Verify no partial block delivery (all-or-nothing per block)
    - **Validates: Requirements 21.1, 21.2, 21.3**

- [x] 14. Final checkpoint — Full build and test suite
  - Verify `npm run build` compiles cleanly and `npm test` passes all unit, property, and integration tests. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are test tasks — can be deferred for faster MVP but should be completed before Phase 3
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major component
- Property tests validate Properties 8, 9, 13, 18, 26 from the design document
- Integration tests validate Requirements 17–21 and 26 against a local Anvil node
- The EventListener, TransactionSubmitter, and ProviderEventIngress are optional in `buildApp()` — the relayer remains functional without Phase 2 env vars (backward compatible)
- All new modules use the existing Pino logger from Fastify for structured logging
- Diamond ABI fragments are hardcoded from Phase 1 event signatures — no runtime ABI fetching
