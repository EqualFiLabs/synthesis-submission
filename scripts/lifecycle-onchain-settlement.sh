#!/usr/bin/env bash
# Lifecycle demo with REAL on-chain settlement (no webhook mock).
#
# Prerequisites:
#   - Anvil running on 127.0.0.1:8545
#   - Diamond deployed (DIAMOND_ADDRESS set)
#   - Agreements seeded via SeedAgreement.s.sol
#   - Relayer built (pnpm --dir mailbox-relayer install)
#   - At least one provider key (VENICE_ADMIN_API_KEY or BANKR_LLM_KEY)
#
# This script starts the relayer in Phase 2 mode so settlement goes through
# TransactionSubmitter → registerUsage() on-chain, NOT the webhook mock.

set -euo pipefail

: "${DIAMOND_ADDRESS:?Set DIAMOND_ADDRESS from Step 2.4}"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="${CHAIN_ID:-31337}"
RELAYER_PRIVATE_KEY="${RELAYER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
BASE="http://127.0.0.1:3113"
AUTH="Authorization: Bearer local-admin-token"
BORROWER_ADDRESS="${BORROWER_ADDRESS:-0xf39Fd6e51aad88F6F4ce6ab8827279cfffb92266}"

echo "=== Starting relayer in Phase 2 mode (real on-chain settlement) ==="

# Start relayer in background with Phase 2 env (TransactionSubmitter as settlement sender)
export RPC_URL CHAIN_ID DIAMOND_ADDRESS RELAYER_PRIVATE_KEY
export ADMIN_AUTH_TOKEN="local-admin-token"
export PORT="3113"
export HOST="127.0.0.1"
export RELAYER_DB_PATH="/tmp/mailbox-relayer-onchain-settlement.sqlite"
export METERING_ENABLED="false"
export KILLSWITCH_RETRY_ENABLED="false"
export USAGE_SETTLEMENT_ENABLED="false"
export COVENANT_MONITOR_ENABLED="false"
export INTEREST_ACCRUAL_ENABLED="false"
# Phase 2 env vars are set (RPC_URL, DIAMOND_ADDRESS, CHAIN_ID, RELAYER_PRIVATE_KEY)
# so bootstrapPhase2() will wire TransactionSubmitter as the settlement sender.
# We do NOT set USAGE_SETTLEMENT_WEBHOOK_URL — no webhook mock needed.

export VENICE_API_KEY="${VENICE_ADMIN_API_KEY:-}"
export BANKR_LLM_KEY="${BANKR_LLM_KEY:-}"
export VENICE_BASE_URL="${VENICE_BASE_URL:-https://api.venice.ai/api/v1}"
export BANKR_LLM_BASE_URL="${BANKR_LLM_BASE_URL:-https://llm.bankr.bot}"
export BANKR_USAGE_PATH="${BANKR_USAGE_PATH:-/v1/usage}"

rm -f "$RELAYER_DB_PATH"
pnpm --dir mailbox-relayer dev &
RELAYER_PID=$!
trap "kill $RELAYER_PID 2>/dev/null || true" EXIT

echo "Waiting for relayer to start..."
for i in $(seq 1 30); do
  if curl -sS "$BASE/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -sS "$BASE/health" || { echo "Relayer failed to start"; exit 1; }

echo ""
echo "=== Relayer ready (Phase 2 mode) ==="
curl -sS "$BASE/health/ready" | jq .

# Pick a provider
PROVIDER=""
if [ -n "${VENICE_ADMIN_API_KEY:-}" ]; then PROVIDER="venice"; fi
if [ -z "$PROVIDER" ] && [ -n "${BANKR_LLM_KEY:-}" ]; then PROVIDER="bankr"; fi
if [ -z "$PROVIDER" ]; then
  echo "No provider keys detected. Set VENICE_ADMIN_API_KEY or BANKR_LLM_KEY."
  exit 1
fi

AID="$(date +%s)"
BLK=900000

echo ""
echo "=== Running $PROVIDER lifecycle with real on-chain settlement ==="

# 1. Activation
ACTIVATION_PAYLOAD="{\"chainId\":$CHAIN_ID,\"blockNumber\":$BLK,\"logIndex\":1,\"eventType\":\"activation\",\"agreementId\":\"$AID\",\"provider\":\"$PROVIDER\",\"payload\":{\"borrowerAddress\":\"$BORROWER_ADDRESS\"}}"
echo "1. Activation..."
curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' -d "$ACTIVATION_PAYLOAD" | jq .

sleep 2

# 2. Metering
echo "2. Metering..."
curl -sS -X POST "$BASE/metering/run" -H "$AUTH" -H 'content-type: application/json' -d "{\"agreementId\":\"$AID\"}" | jq .

# 3. Settlement — this now goes through TransactionSubmitter → registerUsage() on Anvil
echo "3. Settlement (real on-chain via TransactionSubmitter)..."
SETTLEMENT_RESULT=$(curl -sS -X POST "$BASE/settlement/run" -H "$AUTH" -H 'content-type: application/json' -d "{}")
echo "$SETTLEMENT_RESULT" | jq .

# 4. Verify the tx hash is a real Keccak-256 hash (not 0xsettled-...)
TX_HASH=$(echo "$SETTLEMENT_RESULT" | jq -r '.results[0].txHash // empty')
if [ -n "$TX_HASH" ] && [[ "$TX_HASH" != 0xsettled-* ]]; then
  echo ""
  echo "=== Verifying on-chain receipt ==="
  cast receipt --rpc-url "$RPC_URL" "$TX_HASH" --json | jq '{status, blockNumber, gasUsed, transactionHash}'
  echo ""
  echo "✅ Real on-chain settlement confirmed: $TX_HASH"
else
  echo ""
  echo "⚠️  Settlement tx hash: $TX_HASH"
  echo "   (If this starts with 0xsettled-, the webhook mock was used instead of TransactionSubmitter)"
fi

# 5. Breach + close
echo ""
echo "4. Breach..."
curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' \
  -d "{\"chainId\":$CHAIN_ID,\"blockNumber\":$((BLK+1)),\"logIndex\":1,\"eventType\":\"risk_covenant_breached\",\"agreementId\":\"$AID\",\"provider\":\"$PROVIDER\"}" | jq .

echo "5. Close..."
curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' \
  -d "{\"chainId\":$CHAIN_ID,\"blockNumber\":$((BLK+2)),\"logIndex\":1,\"eventType\":\"agreement_closed\",\"agreementId\":\"$AID\",\"provider\":\"$PROVIDER\"}" | jq .

echo ""
echo "=== Final state ==="
curl -sS "$BASE/agreements/$AID/state" | jq .

echo ""
echo "=== Done ==="
