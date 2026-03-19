# Decentralized Mailbox Relay Design

## 1) Goal

Design a mailbox relay that can keep working if the current relayer operator disappears.

This design keeps end-to-end encrypted payloads offchain while moving ordering, incentives, and settlement onchain.

## 2) Design Principles

- Permissionless participation: any relay can serve traffic.
- Minimal onchain footprint: store commitments and settlement state, not ciphertext.
- Incentive-complete state machine: every transition has a profitable caller.
- Censorship resistance: delivery can happen by many relays, and recipients can always pull directly.
- Backward compatibility: preserve current canonical envelope format where possible.

## 3) High-Level Architecture

Three planes:

1. Control plane (onchain contracts)
- Message commitment registry
- Fee escrow and payout
- Expiry/refund logic
- Replay protection for acknowledgements

2. Data plane (decentralized transport/storage)
- Ciphertext envelope stored in IPFS/Arweave (CID)
- Relay gossip network (libp2p/Waku topic by recipient routing tag)
- Pull fallback: recipient can fetch from content address without trusted relay

3. Proof plane (onchain settlement)
- Recipient signs typed acknowledgement binding `messageId` and `relay`
- Relay submits signature onchain and receives escrowed reward
- If not acknowledged before expiry, sender refunds escrow

## 4) Contract Set

## `MailboxCore`

Primary settlement contract.

Suggested storage:

```solidity
enum MessageStatus { None, Posted, Settled, Refunded }

struct Message {
    address sender;
    bytes32 recipientCommitment;   // hashed recipient routing identifier
    bytes32 cipherHash;            // hash(envelope bytes)
    bytes32 cidHash;               // hash(CID bytes)
    uint64  postedAt;
    uint64  expiry;
    uint96  feeWei;
    MessageStatus status;
}
```

Suggested functions:

- `postMessage(...) payable returns (uint256 messageId)`
- `settleWithAck(messageId, relay, ack, sig)` -> pays relay
- `refundExpired(messageId)` -> refunds sender after expiry
- `getMessage(messageId)` view

Suggested events:

- `MessagePosted(messageId, sender, recipientCommitment, cid, cipherHash, expiry, feeWei)`
- `MessageSettled(messageId, relay, recipient, paidWei)`
- `MessageRefunded(messageId, sender, refundedWei)`

## `RelayRegistry` (v2+)

Optional in MVP, required for stronger Sybil resistance.

- Relay staking
- Reputation stats
- Optional slashing hooks (with challenge evidence)

## `MailboxTreasury` (optional)

Fee routing for protocol take-rate (if needed):
- relay payout
- protocol fee
- optional watcher reward

## 5) Message Format and Commitments

Payload remains canonical envelope compatible with existing relayer schema:
- `version`
- `recipient`
- `cipher.{iv,ephemPublicKey,ciphertext,mac}`
- timestamps + `traceId`

Onchain, only commitments are stored:
- `cipherHash = keccak256(envelopeBytes)`
- `cidHash = keccak256(cidBytes)`
- `recipientCommitment = keccak256(namespace || recipientRoutingTag)`

This avoids leaking plaintext or full recipient metadata onchain.

## 6) End-to-End Flow

1. Sender encrypts payload to recipient public key.
2. Sender uploads envelope to decentralized storage and gets CID.
3. Sender calls `postMessage` with commitments and escrow fee.
4. Relays watch `MessagePosted`, fetch ciphertext by CID, attempt delivery.
5. Recipient validates/decrypts envelope.
6. Recipient signs EIP-712 ack:
- includes `messageId`, `relay`, `recipient`, `deadline`, `nonce`, `chainId`, `verifyingContract`.
7. Relay submits `settleWithAck`.
8. Contract verifies signature and nonce, marks message `Settled`, pays relay.
9. If no settlement by expiry, anyone can call `refundExpired` to return funds to sender.

## 7) Incentive Model

Who calls each transition and why:

- `postMessage`: sender pays because they want delivery.
- delivery attempts: relays compete for payout.
- `settleWithAck`: winning relay submits proof to claim escrow.
- `refundExpired`: sender or keepers call to reclaim locked funds.

Recommended fee formula:

`fee = baseRelayFee + estimatedGasSettlement + urgencyPremium + sizePremium`

Notes:
- Underpriced messages should fail fast (min fee floor).
- Consider EIP-1559-style dynamic floor in v2.

## 8) Signature and Replay Safety

Ack typed struct:

```text
Ack(
  uint256 messageId,
  address relay,
  address recipient,
  uint256 nonce,
  uint64 deadline
)
```

Required checks:
- EIP-712 domain separator includes chain + contract.
- `recipient` resolves from identity registry or envelope metadata commitment.
- `deadline >= block.timestamp`.
- nonce unused (`recipient => nonce => used`).
- message status is `Posted`.
- message not expired.

Binding `relay` inside ack prevents mempool payout theft by copy-submitters.

## 9) Censorship and Availability Strategy

- Multi-relay gossip distribution for redundancy.
- Recipient pull path from CID if no relay push arrives.
- Optional erasure coding / multi-pin policy for high-value traffic.
- No trusted sequencer; chain events are discovery source of truth.

## 10) Abuse and Attack Surface

Top risks and mitigations:

- Spam flooding:
  - enforce minimum escrow per message
  - optional per-sender rate limit via bonded credits (v2)

- Fake delivery claims:
  - require recipient EIP-712 ack signature
  - strict replay protection

- Relay Sybil griefing:
  - stake requirement + delayed withdrawals (v2)
  - reputation-weighted routing offchain

- Front-running settlement:
  - ack binds relay address

- Withholding ciphertext:
  - CID-based public availability and multi-relay replication

- Key compromise:
  - recipient key rotation in identity registry
  - enforce `expiresAt` policy in clients

## 11) Privacy Notes

What is public:
- message timing
- sender address
- commitment hashes
- relay payout activity

What is private:
- message plaintext
- envelope ciphertext contents
- exact recipient identity (if routing commitment is well-designed)

Optional v3 privacy upgrades:
- stealth routing tags
- encrypted recipient hint blobs
- zk-proof based delivery receipts for metadata minimization

## 12) Migration from Current `mailbox-relayer`

Phase A (hybrid MVP):
- Keep existing HTTP endpoints.
- Add onchain `postMessage` + `settleWithAck`.
- Existing service runs as one relay among many.

Phase B (permissionless relay):
- Publish relay node spec and reference client.
- Add gossip + CID fetching + ack submit loop.
- Add dashboard for message states from chain events.

Phase C (crypto-economic hardening):
- Add `RelayRegistry` stake and optional slashing.
- Add protocol-wide fee policy and keeper incentives.
- Add operatorless governance controls (timelock + multisig or immutable params).

## 13) Proposed MVP Contract API (Concrete)

```solidity
function postMessage(
    bytes32 recipientCommitment,
    bytes32 cipherHash,
    bytes calldata cid,
    uint64 expiry
) external payable returns (uint256 messageId);

function settleWithAck(
    uint256 messageId,
    address relay,
    uint256 nonce,
    uint64 deadline,
    bytes calldata recipientSig
) external;

function refundExpired(uint256 messageId) external;
```

MVP constraints:
- One payout per message.
- No relay staking yet.
- No slashing yet.
- Strong signature validation and replay protection from day 1.

## 14) Implementation Checklist

- Define EIP-712 domain + `Ack` struct hash.
- Implement `MailboxCore` with CEI and `nonReentrant`.
- Add Foundry tests:
  - post success/failure
  - valid settlement
  - replay rejection
  - wrong-relay signature rejection
  - expiry refund behavior
  - double settlement/refund prevention
- Extend relay service:
  - chain event watcher
  - CID fetch + delivery worker
  - ack collection endpoint
  - settlement tx submitter
- Add metrics:
  - delivery latency p50/p95
  - settlement success rate
  - refund ratio
  - relay payout distribution

## 15) Why This Is Decentralized

The protocol remains live without a single operator because:
- posting and settlement rules are onchain,
- any relay can compete for rewards,
- recipients can pull ciphertext without trusting one server,
- expiry/refund is permissionless.

That converts relay operation from a centralized service into a permissionless market.
