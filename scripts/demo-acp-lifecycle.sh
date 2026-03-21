#!/usr/bin/env bash
# ERC-8183 ACP Job Lifecycle Demo — real tx hashes on Anvil.
#
# No API keys needed. Purely on-chain.
#
# Prerequisites:
#   - Anvil running on 127.0.0.1:8545
#   - Diamond deployed (DIAMOND_ADDRESS set)
#   - forge + cast available
#
# Flow exercised:
#   createAcpJob → setAcpBudget → fundAcpJob → submitAcpJob → completeAcpJob
#
# Three actors: borrower (Anvil account 0), provider (account 1), evaluator (account 2)

set -euo pipefail

: "${DIAMOND_ADDRESS:?Set DIAMOND_ADDRESS from the deploy step}"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
AGREEMENT_ID="${ACP_AGREEMENT_ID:-200}"

# Anvil default accounts
BORROWER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BORROWER_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
PROVIDER_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
PROVIDER_ADDR="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
EVALUATOR_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
EVALUATOR_ADDR="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

VENUE_KEY="$(cast keccak 'demo-venue')"

echo "=== ERC-8183 ACP Lifecycle Demo ==="
echo "Diamond:    $DIAMOND_ADDRESS"
echo "Borrower:   $BORROWER_ADDR"
echo "Provider:   $PROVIDER_ADDR"
echo "Evaluator:  $EVALUATOR_ADDR"
echo "Agreement:  $AGREEMENT_ID"
echo ""

# ── Step 1: Seed ACP-enabled agreement ──
echo "Step 1: Seeding ACP-enabled agreement..."
cd "$(dirname "$0")/../EqualFi"

export DIAMOND_ADDRESS PRIVATE_KEY="$BORROWER_KEY" ACP_AGREEMENT_ID="$AGREEMENT_ID"

forge script script/SeedACPAgreement.s.sol:SeedACPAgreementScript \
  --sig "run()" \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --skip-simulation 2>&1 | tail -5

echo ""

# ── Step 2: createAcpJob (borrower) ──
echo "Step 2: createAcpJob (borrower)..."
EXPIRY=$(($(date +%s) + 86400))
CREATE_TX=$(cast send --rpc-url "$RPC_URL" --private-key "$BORROWER_KEY" --json \
  "$DIAMOND_ADDRESS" \
  "createAcpJob(uint256,bytes32,address,address,uint256,string,address)" \
  "$AGREEMENT_ID" "$VENUE_KEY" "$PROVIDER_ADDR" "$EVALUATOR_ADDR" "$EXPIRY" "ACP demo job" "0x0000000000000000000000000000000000000000")

CREATE_HASH=$(echo "$CREATE_TX" | jq -r '.transactionHash')
echo "  tx: $CREATE_HASH"

# Decode the returned jobId from logs or return data
# The function returns uint256, decode from tx receipt logs
JOB_ID=$(cast call --rpc-url "$RPC_URL" \
  "$DIAMOND_ADDRESS" \
  "getAgreementJobs(uint256)(uint256[])" "$AGREEMENT_ID" | tr -d '[]' | tr ',' '\n' | tail -1 | tr -d ' ')
echo "  jobId: $JOB_ID"
echo ""

# ── Step 3: setAcpBudget (provider) ──
echo "Step 3: setAcpBudget (provider, 100e18)..."
BUDGET_TX=$(cast send --rpc-url "$RPC_URL" --private-key "$PROVIDER_KEY" --json \
  "$DIAMOND_ADDRESS" \
  "setAcpBudget(uint256,uint256,bytes)" \
  "$JOB_ID" "100000000000000000000" "0x")

echo "  tx: $(echo "$BUDGET_TX" | jq -r '.transactionHash')"
echo ""

# ── Step 4: fundAcpJob (borrower) ──
echo "Step 4: fundAcpJob (borrower)..."
FUND_TX=$(cast send --rpc-url "$RPC_URL" --private-key "$BORROWER_KEY" --json \
  "$DIAMOND_ADDRESS" \
  "fundAcpJob(uint256,bytes)" \
  "$JOB_ID" "0x")

echo "  tx: $(echo "$FUND_TX" | jq -r '.transactionHash')"
echo ""

# ── Step 5: submitAcpJob (provider) ──
echo "Step 5: submitAcpJob (provider)..."
DELIVERABLE=$(cast keccak "demo-deliverable-content")
SUBMIT_TX=$(cast send --rpc-url "$RPC_URL" --private-key "$PROVIDER_KEY" --json \
  "$DIAMOND_ADDRESS" \
  "submitAcpJob(uint256,bytes32,bytes)" \
  "$JOB_ID" "$DELIVERABLE" "0x")

echo "  tx: $(echo "$SUBMIT_TX" | jq -r '.transactionHash')"
echo ""

# ── Step 6: completeAcpJob (evaluator) ──
echo "Step 6: completeAcpJob (evaluator)..."
REASON=$(cast keccak "accepted")
COMPLETE_TX=$(cast send --rpc-url "$RPC_URL" --private-key "$EVALUATOR_KEY" --json \
  "$DIAMOND_ADDRESS" \
  "completeAcpJob(uint256,bytes32,bytes)" \
  "$JOB_ID" "$REASON" "0x")

COMPLETE_HASH=$(echo "$COMPLETE_TX" | jq -r '.transactionHash')
echo "  tx: $COMPLETE_HASH"
echo ""

# ── Step 7: Verify final state ──
echo "=== Verifying final state ==="

JOB_STATE=$(cast call --rpc-url "$RPC_URL" \
  "$DIAMOND_ADDRESS" \
  "getAcpJob(uint256)((uint256,uint256,bytes32,address,address,address,uint8,uint256,uint40,uint40,uint40,uint40,bytes32,bytes32,uint8))" \
  "$JOB_ID")
echo "Job state: $JOB_STATE"

AGR_STATE=$(cast call --rpc-url "$RPC_URL" \
  "$DIAMOND_ADDRESS" \
  "getAgreement(uint256)((uint256,uint256,string,uint256,uint256,bytes32,address,uint8,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,bytes32))" \
  "$AGREEMENT_ID")
echo "Agreement state: $AGR_STATE"

echo ""
echo "=== Summary ==="
echo "ACP Job Lifecycle (all real Anvil tx hashes):"
echo "  createAcpJob:   $CREATE_HASH"
echo "  setAcpBudget:   $(echo "$BUDGET_TX" | jq -r '.transactionHash')"
echo "  fundAcpJob:     $(echo "$FUND_TX" | jq -r '.transactionHash')"
echo "  submitAcpJob:   $(echo "$SUBMIT_TX" | jq -r '.transactionHash')"
echo "  completeAcpJob: $COMPLETE_HASH"
echo ""
echo "The fundAcpJob step drew 100e18 against the agreement's credit limit."
echo "The completeAcpJob step marked the job terminal (Completed)."
echo "All transitions are real on-chain state changes with verifiable tx receipts."
