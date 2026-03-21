---
name: local-full-stack-lifecycle
description: Deploy full local EqualFi stack on Anvil, run provider lifecycles, ACP job lifecycle, and on-chain settlement with real tx hashes.
---

# Local Full-Stack Lifecycle Skill

Use this skill to spin up the full local stack from scratch and run Venice + Bankr provider flows, ERC-8183 ACP job lifecycle, and real on-chain settlement.

## What this covers

1. Start Anvil
2. Deploy contracts (two paths: full external deps or lightweight stubs)
3. Seed agreements
4. Start relayer (Phase 2 mode for real on-chain settlement)
5. Run provider lifecycles (Venice, Bankr, Lambda, RunPod)
6. Run ERC-8183 ACP job lifecycle
7. Run pure financing default scenario
8. Persist output

## Preconditions

1. You are in the submission root directory (contains `EqualFi/`, `mailbox-relayer/`, `mailbox-sdk/`, `scripts/`).
2. Tools available: `git`, `node` (≥20), `pnpm`, `forge`, `cast`, `jq`, `curl`, `anvil`.
3. Provider keys (optional per provider):
   - `VENICE_ADMIN_API_KEY` + `VENICE_INFERENCE_API_KEY` — for Venice
   - `BANKR_LLM_KEY` — for Bankr
   - `LAMBDA_API_KEY` — for Lambda
   - `RUNPOD_API_KEY` — for RunPod

## Step 1: Start Anvil

```bash
anvil --host 127.0.0.1 --port 8545 --chain-id 31337 --accounts 10 --balance 10000
```

Default deployer (Anvil account 0):
- Address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## Step 2: Deploy Contracts

Two paths are available. Path A is lightweight and sufficient for all demos. Path B deploys the real external dependencies.

### Path A: Lightweight Stubs (recommended for demos)

Set dummy bytecode at the three external dependency addresses so the Diamond deploy succeeds without cloning external repos:

```bash
set -euo pipefail
RPC_URL=http://127.0.0.1:8545

# EntryPoint, IdentityRegistry, ERC6551Registry stubs
cast rpc anvil_setCode 0x0000000000000000000000000000000000000001 0x00 --rpc-url $RPC_URL
cast rpc anvil_setCode 0x0000000000000000000000000000000000000002 0x00 --rpc-url $RPC_URL
cast rpc anvil_setCode 0x0000000000000000000000000000000000000003 0x00 --rpc-url $RPC_URL

export ENTRYPOINT_ADDRESS=0x0000000000000000000000000000000000000001
export IDENTITY_REGISTRY=0x0000000000000000000000000000000000000002
export IDENTITY_REGISTRY_ADDRESS=0x0000000000000000000000000000000000000002
export ERC6551_REGISTRY=0x0000000000000000000000000000000000000003
export ERC6551_REGISTRY_ADDRESS=0x0000000000000000000000000000000000000003
```

### Path B: Full External Dependencies

Clone and deploy the real contracts. Only needed if you want real EntryPoint/ERC-8004/ERC-6551 functionality.

```bash
set -euo pipefail
DEPS_DIR="${DEPS_DIR:-$(pwd)/.deps}"
mkdir -p "$DEPS_DIR"

[ -d "$DEPS_DIR/account-abstraction/.git" ] || git clone https://github.com/eth-infinitism/account-abstraction.git "$DEPS_DIR/account-abstraction"
[ -d "$DEPS_DIR/erc-8004-contracts/.git" ] || git clone https://github.com/erc-8004/erc-8004-contracts.git "$DEPS_DIR/erc-8004-contracts"
[ -d "$DEPS_DIR/reference/.git" ] || git clone https://github.com/erc6551/reference.git "$DEPS_DIR/reference"
```

**EntryPoint v0.7:**
```bash
cd "$DEPS_DIR/account-abstraction"
git fetch origin releases/v0.7 --depth 1 && git checkout --detach origin/releases/v0.7
echo "test test test test test test test test test test test junk" > ./mnemonic.txt
MNEMONIC_FILE=./mnemonic.txt yarn install && yarn deploy --network dev
export ENTRYPOINT_ADDRESS="$(jq -r '.address' deployments/dev/EntryPoint.json)"
```

**ERC-8004:**
```bash
cd "$DEPS_DIR/erc-8004-contracts"
export SEPOLIA_RPC_URL=http://127.0.0.1:8545 MAINNET_RPC_URL=http://127.0.0.1:8545
npm run local:factory && npm run local:deploy:vanity
export IDENTITY_REGISTRY=0x8004A818BFB912233c491871b3d84c89A494BD9e
export IDENTITY_REGISTRY_ADDRESS=$IDENTITY_REGISTRY
```

**ERC-6551:**
```bash
cd "$DEPS_DIR/reference"
git submodule update --init --recursive
forge script script/DeployRegistry.s.sol:DeployRegistry \
  --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ERC6551_REGISTRY=0x000000006551c19487814612e58FE06813775758
export ERC6551_REGISTRY_ADDRESS=$ERC6551_REGISTRY
```

### Deploy EqualFi Diamond

The Diamond deploy requires three separate calls in order:

```bash
set -euo pipefail
cd EqualFi

export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export OWNER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export TIMELOCK=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# ENTRYPOINT_ADDRESS, IDENTITY_REGISTRY, IDENTITY_REGISTRY_ADDRESS,
# ERC6551_REGISTRY, ERC6551_REGISTRY_ADDRESS must be set from above.

# 1. Deploy base Diamond + core facets
forge script script/DeployV1.s.sol --sig "runBase()" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation

# Extract Diamond address
export DIAMOND_ADDRESS=$(jq -r '.transactions[] | select(.contractName=="Diamond" and .transactionType=="CREATE") | .contractAddress' \
  broadcast/DeployV1.s.sol/31337/runBase-latest.json | tail -n 1)
export DIAMOND=$DIAMOND_ADDRESS
export POSITION_NFT=$(jq -r '.transactions[] | select(.contractName=="PositionNFT" and .transactionType=="CREATE") | .contractAddress' \
  broadcast/DeployV1.s.sol/31337/runBase-latest.json | tail -n 1)

echo "DIAMOND_ADDRESS=$DIAMOND_ADDRESS"
echo "POSITION_NFT=$POSITION_NFT"

# 2. Install V1 facets (lending, pools, views, agent wallet)
forge script script/DeployV1.s.sol --sig "runDeployV1()" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation

# 3. Install agentic facets (EqualScale: metering, risk, ACP/ERC-8183)
export DIAMOND_ADDRESS=$DIAMOND_ADDRESS
forge script script/DeployV1.s.sol --sig "runInstallAgenticOnExistingDiamond()" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation
```

## Step 3: Seed Agreements

### Metered-usage agreements (for provider lifecycles + settlement)

```bash
cd EqualFi
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# DIAMOND_ADDRESS must be set from Step 2

forge script script/SeedAgreement.s.sol --tc SeedAgreementScript \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation
```

This seeds agreements 100, 101, 102 with metered-usage mode, credit limits, and unit pricing.

### ACP-enabled agreement (for ERC-8183 lifecycle)

```bash
forge script script/SeedACPAgreement.s.sol --tc SeedACPAgreementScript \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --skip-simulation
```

This seeds agreement 200 with ACP mode enabled, deploys a `MockGeneric8183Adapter`, and authorizes the Diamond as a caller on the adapter.

## Step 4: Build and Start Relayer

**Important:** The relayer must be built before running. Using `pnpm dev` (tsx) fails because `better-sqlite3`'s native module doesn't resolve correctly through pnpm's symlinked `.pnpm` store under tsx. Build first, then run with `node`.

```bash
cd mailbox-relayer
pnpm install
pnpm build   # produces dist/index.js via tsup
```

### Phase 2 mode (real on-chain settlement — recommended)

When `RPC_URL`, `DIAMOND_ADDRESS`, `CHAIN_ID`, and `RELAYER_PRIVATE_KEY` are all set, the relayer starts in Phase 2 mode. This wires `TransactionSubmitter` as the `UsageSettlementSender`, so `POST /settlement/run` submits real `registerUsage()` transactions on-chain instead of using the webhook mock.

```bash
set -a
source .env  # if you have a .env with provider keys
set +a

export VENICE_API_KEY="${VENICE_ADMIN_API_KEY:-}"
export BANKR_LLM_KEY="${BANKR_LLM_KEY:-}"
export RPC_URL=http://127.0.0.1:8545
export CHAIN_ID=31337
export DIAMOND_ADDRESS="<from Step 2>"
export RELAYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ADMIN_AUTH_TOKEN="local-admin-token"
export PORT=3113
export HOST=127.0.0.1
export RELAYER_DB_PATH="/tmp/mailbox-relayer.sqlite"
export METERING_ENABLED=false
export KILLSWITCH_RETRY_ENABLED=false
export USAGE_SETTLEMENT_ENABLED=false
export COVENANT_MONITOR_ENABLED=false
export INTEREST_ACCRUAL_ENABLED=false

node dist/index.js
```

Verify: `curl -sS http://127.0.0.1:3113/health` → `{"ok":true}`

Startup log should show: `{ walletAddress: '0xf39Fd6...' } phase2 signer configured`

### Webhook mock mode (alternative, no on-chain txs)

If you omit `RPC_URL`/`DIAMOND_ADDRESS`/`CHAIN_ID`/`RELAYER_PRIVATE_KEY`, the relayer falls back to webhook settlement. Start a mock webhook first:

```bash
node -e 'const http=require("http");http.createServer((req,res)=>{let b="";req.on("data",c=>b+=c);req.on("end",()=>{let a="unknown";try{a=JSON.parse(b).submission.agreementId||a}catch{}res.writeHead(200,{"content-type":"application/json"});res.end(JSON.stringify({ok:true,txHash:"0xsettled-"+a+"-"+Date.now()}))})}).listen(3213,"127.0.0.1",()=>console.log("mock on :3213"))'
```

Then add to relayer env:
```bash
export USAGE_SETTLEMENT_WEBHOOK_URL="http://127.0.0.1:3213/settle"
export USAGE_SETTLEMENT_WEBHOOK_TOKEN="local-settlement-token"
```

## Step 5: Set Provider Keys + Detect Available Lifecycles

```bash
# Venice
export VENICE_ADMIN_API_KEY="..."
export VENICE_INFERENCE_API_KEY="..."

# Bankr
export BANKR_LLM_KEY="..."

# Lambda (optional)
export LAMBDA_API_KEY="..."
export LAMBDA_BASE_URL="${LAMBDA_BASE_URL:-https://cloud.lambdalabs.com/api/v1}"

# RunPod (optional)
export RUNPOD_API_KEY="..."
export RUNPOD_SERVERLESS_BASE_URL="${RUNPOD_SERVERLESS_BASE_URL:-https://api.runpod.ai/v2}"
export RUNPOD_INFRA_BASE_URL="${RUNPOD_INFRA_BASE_URL:-https://rest.runpod.io/v1}"
```

Detect which lifecycles to run:

```bash
AVAILABLE=()
if [ -n "${VENICE_ADMIN_API_KEY:-}" ] && [ -n "${VENICE_INFERENCE_API_KEY:-}" ]; then AVAILABLE+=("venice"); fi
if [ -n "${BANKR_LLM_KEY:-}" ]; then AVAILABLE+=("bankr"); fi
if [ -n "${LAMBDA_API_KEY:-}" ]; then AVAILABLE+=("lambda"); fi
if [ -n "${RUNPOD_API_KEY:-}" ]; then AVAILABLE+=("runpod"); fi
LIFECYCLES="${LIFECYCLES:-$(IFS=,; echo "${AVAILABLE[*]}")}"
echo "Running lifecycles: $LIFECYCLES"
```

**Provider key mapping for relayer:**
| Provider | Relayer env var | Notes |
|----------|----------------|-------|
| Venice | `VENICE_API_KEY` (= `VENICE_ADMIN_API_KEY`) | Also needs `VENICE_INFERENCE_API_KEY` for usage seed inference call |
| Bankr | `BANKR_LLM_KEY` | Same key for activation + usage |
| Lambda | `LAMBDA_API_KEY` | Same key |
| RunPod | `RUNPOD_API_KEY` | Same key |

## Step 6: Run Provider Lifecycles (Venice/Bankr/Lambda/RunPod)

This script drives the full lifecycle for each selected provider: activation → inference seed → metering → settlement → breach → close.

```bash
set -euo pipefail
BASE="http://127.0.0.1:3113"
AUTH="Authorization: Bearer local-admin-token"
BORROWER_ADDRESS="${BORROWER_ADDRESS:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
LAMBDA_INSTANCE_TYPE="${LAMBDA_INSTANCE_TYPE:-a10_24gb}"

selected_csv="$(echo "${LIFECYCLES:-}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
IFS=',' read -r -a selected <<< "$selected_csv"

# If Lambda is selected and no SSH pubkey is supplied, generate a temporary one.
if [[ ",$selected_csv," == *",lambda,"* ]] && [ -z "${LAMBDA_SSH_PUBLIC_KEY:-}" ]; then
  if command -v ssh-keygen >/dev/null 2>&1; then
    if [ ! -f /tmp/equalfi_lambda_lifecycle_ed25519 ]; then
      ssh-keygen -t ed25519 -N '' -f /tmp/equalfi_lambda_lifecycle_ed25519 >/dev/null
    fi
    LAMBDA_SSH_PUBLIC_KEY="$(cat /tmp/equalfi_lambda_lifecycle_ed25519.pub)"
  fi
fi

echo '{}' >/tmp/provider_sections.json

run_provider_lifecycle() {
  local provider="$1"
  local aid="$2"
  local blk="$3"
  local activation_payload

  if [ "$provider" = "venice" ]; then
    activation_payload=$(cat <<JSON
{"chainId":31337,"blockNumber":$blk,"logIndex":1,"eventType":"activation","agreementId":"$aid","provider":"venice","policy":{"description":"$aid","apiKeyType":"INFERENCE","consumptionLimit":{"usd":2}},"payload":{"borrowerAddress":"$BORROWER_ADDRESS"}}
JSON
)
  elif [ "$provider" = "bankr" ]; then
    activation_payload=$(cat <<JSON
{"chainId":31337,"blockNumber":$blk,"logIndex":1,"eventType":"activation","agreementId":"$aid","provider":"bankr","payload":{"borrowerAddress":"$BORROWER_ADDRESS"}}
JSON
)
  elif [ "$provider" = "lambda" ]; then
    activation_payload=$(cat <<JSON
{"chainId":31337,"blockNumber":$blk,"logIndex":1,"eventType":"activation","agreementId":"$aid","provider":"lambda","policy":{"instanceType":"$LAMBDA_INSTANCE_TYPE"},"payload":{"borrowerAddress":"$BORROWER_ADDRESS","sshPublicKey":"${LAMBDA_SSH_PUBLIC_KEY:-}"}}
JSON
)
  elif [ "$provider" = "runpod" ]; then
    activation_payload=$(cat <<JSON
{"chainId":31337,"blockNumber":$blk,"logIndex":1,"eventType":"activation","agreementId":"$aid","provider":"runpod","policy":{"computeMode":"api_inference"},"payload":{"borrowerAddress":"$BORROWER_ADDRESS"}}
JSON
)
  else
    echo "unsupported provider: $provider" >&2
    return 1
  fi

  local breach_payload
  breach_payload=$(cat <<JSON
{"chainId":31337,"blockNumber":$((blk+1)),"logIndex":1,"eventType":"risk_covenant_breached","agreementId":"$aid","provider":"$provider"}
JSON
)
  local close_payload
  close_payload=$(cat <<JSON
{"chainId":31337,"blockNumber":$((blk+2)),"logIndex":1,"eventType":"agreement_closed","agreementId":"$aid","provider":"$provider"}
JSON
)

  # Activation
  curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' -d "$activation_payload" > "/tmp/${provider}_activation.json"

  # Metering
  curl -sS -X POST "$BASE/metering/run" -H "$AUTH" -H 'content-type: application/json' -d "{\"agreementId\":\"$aid\"}" > "/tmp/${provider}_metering.json"
  curl -sS "$BASE/metering/submissions?limit=50" | jq --arg aid "$aid" '{submissions:[.submissions[] | select(.agreementId==$aid)]}' > "/tmp/${provider}_submissions.json"

  # Settlement
  curl -sS -X POST "$BASE/settlement/run" -H "$AUTH" -H 'content-type: application/json' -d "{}" > "/tmp/${provider}_settlement_before_breach.json"

  # Breach + close
  curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' -d "$breach_payload" > "/tmp/${provider}_breach.json"
  curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' -d "$close_payload" > "/tmp/${provider}_close.json"
  curl -sS "$BASE/agreements/$aid/state" > "/tmp/${provider}_state.json"

  # Collect into combined JSON
  jq --arg p "$provider" --arg aid "$aid" \
    --slurpfile activation "/tmp/${provider}_activation.json" \
    --slurpfile metering "/tmp/${provider}_metering.json" \
    --slurpfile submissions "/tmp/${provider}_submissions.json" \
    --slurpfile settlementBeforeBreach "/tmp/${provider}_settlement_before_breach.json" \
    --slurpfile breach "/tmp/${provider}_breach.json" \
    --slurpfile close "/tmp/${provider}_close.json" \
    --slurpfile finalState "/tmp/${provider}_state.json" \
    '. + {($p): {
      agreementId:$aid,
      activation:$activation[0],
      metering:$metering[0],
      submissions:$submissions[0],
      settlementBeforeBreach:$settlementBeforeBreach[0],
      breach:$breach[0],
      close:$close[0],
      finalState:$finalState[0]
    }}' /tmp/provider_sections.json > /tmp/provider_sections.next.json
  mv /tmp/provider_sections.next.json /tmp/provider_sections.json
}

# Seed inference calls so providers have usage to meter
if [ -n "${VENICE_INFERENCE_API_KEY:-}" ]; then
  VENICE_MODEL="$(curl -sS https://api.venice.ai/api/v1/models -H "Authorization: Bearer ${VENICE_INFERENCE_API_KEY}" -H 'content-type: application/json' | jq -r '.data[0].id // .models[0].id // empty')"
  if [ -n "$VENICE_MODEL" ]; then
    curl -sS -o /tmp/venice_ping.json https://api.venice.ai/api/v1/chat/completions \
      -H "Authorization: Bearer ${VENICE_INFERENCE_API_KEY}" -H 'content-type: application/json' \
      -d "{\"model\":\"$VENICE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"local lifecycle ping\"}],\"max_tokens\":8}" >/dev/null
  fi
fi

if [ -n "${BANKR_LLM_KEY:-}" ]; then
  BANKR_MODEL="$(curl -sS https://llm.bankr.bot/v1/models -H "Authorization: Bearer ${BANKR_LLM_KEY}" -H "X-API-Key: ${BANKR_LLM_KEY}" -H 'content-type: application/json' | jq -r '.data[0].id // .models[0].id // empty')"
  if [ -n "$BANKR_MODEL" ]; then
    curl -sS -o /tmp/bankr_ping.json https://llm.bankr.bot/v1/chat/completions \
      -H "Authorization: Bearer ${BANKR_LLM_KEY}" -H "X-API-Key: ${BANKR_LLM_KEY}" -H 'content-type: application/json' \
      -d "{\"model\":\"$BANKR_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"local lifecycle ping\"}],\"max_tokens\":8}" >/dev/null
  fi
fi

sleep 2

# Run each selected provider
BASE_AID="$(date +%s)"
idx=0
for provider in "${selected[@]}"; do
  [ -n "$provider" ] || continue
  case "$provider" in
    venice)  [ -n "${VENICE_ADMIN_API_KEY:-}" ] && [ -n "${VENICE_INFERENCE_API_KEY:-}" ] || { echo "skipping venice: missing keys"; continue; } ;;
    bankr)   [ -n "${BANKR_LLM_KEY:-}" ] || { echo "skipping bankr: missing keys"; continue; } ;;
    lambda)  [ -n "${LAMBDA_API_KEY:-}" ] || { echo "skipping lambda: missing keys"; continue; } ;;
    runpod)  [ -n "${RUNPOD_API_KEY:-}" ] || { echo "skipping runpod: missing keys"; continue; } ;;
    *)       echo "unknown provider: $provider"; continue ;;
  esac

  aid="$((BASE_AID + idx + 1))"
  blockBase="$((880000 + (idx * 10000)))"
  run_provider_lifecycle "$provider" "$aid" "$blockBase"
  idx=$((idx + 1))
done

# Final settlement pass + collect all outputs
curl -sS -X POST "$BASE/settlement/run" -H "$AUTH" -H 'content-type: application/json' -d "{}" > /tmp/post_breach_settlement.json
curl -sS "$BASE/metering/submissions?limit=100" > /tmp/all_submissions.json
curl -sS "$BASE/settlement/attempts?limit=100" > /tmp/all_attempts.json

jq -n \
  --arg runAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg lifecycles "${LIFECYCLES:-}" \
  --slurpfile providers /tmp/provider_sections.json \
  '{
    runAt: $runAt,
    selectedLifecycles: ($lifecycles | if . == "" then [] else split(",") end),
    providers: $providers[0],
    postBreachSettlement:(input),
    allSubmissions:(input),
    allSettlementAttempts:(input)
  }' \
  /tmp/post_breach_settlement.json /tmp/all_submissions.json /tmp/all_attempts.json \
  > /tmp/provider_lifecycles.json

cat /tmp/provider_lifecycles.json
```

## Step 7: Run ERC-8183 ACP Job Lifecycle

This exercises the full multi-actor ACP job lifecycle with 3 Anvil accounts:

```bash
export DIAMOND_ADDRESS="<from Step 2>"
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

bash scripts/demo-acp-lifecycle.sh
```

This runs 5 on-chain transitions with real tx hashes:
1. `createAcpJob` — Borrower creates job on agreement 200
2. `setAcpBudget` — Provider sets budget (100e18)
3. `fundAcpJob` — Borrower funds, drawing against credit facility
4. `submitAcpJob` — Provider submits work product hash
5. `completeAcpJob` — Evaluator marks job complete

Actors:
- Borrower: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (account 0)
- Provider: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (account 1)
- Evaluator: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` (account 2)

## Step 8: Run Pure Financing Default Scenario (No API Keys)

This always works — no provider keys needed. Exercises the on-chain state machine: Active → Delinquent → Defaulted via Anvil time warps.

```bash
set -euo pipefail
RPC_URL=http://127.0.0.1:8545
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
AID=1
UNIT_TYPE=$(cast keccak "VENICE_TEXT_TOKEN_IN")
# DIAMOND_ADDRESS must be set

# Register usage (creates debt)
cast send --rpc-url $RPC_URL --private-key $PK \
  $DIAMOND_ADDRESS "registerUsage(uint256,bytes32,uint256)" $AID $UNIT_TYPE 400000000000000000000

# Day 1: accrue interest
cast rpc --rpc-url $RPC_URL anvil_increaseTime 86400 && cast rpc --rpc-url $RPC_URL evm_mine
cast send --rpc-url $RPC_URL --private-key $PK $DIAMOND_ADDRESS "accrueInterest(uint256)" $AID

# Day 3: delinquency
cast rpc --rpc-url $RPC_URL anvil_increaseTime 172801 && cast rpc --rpc-url $RPC_URL evm_mine
cast send --rpc-url $RPC_URL --private-key $PK $DIAMOND_ADDRESS "detectDelinquency(uint256)" $AID

# Day 6: default (after cure period)
cast rpc --rpc-url $RPC_URL anvil_increaseTime 259201 && cast rpc --rpc-url $RPC_URL evm_mine
cast send --rpc-url $RPC_URL --private-key $PK $DIAMOND_ADDRESS "triggerDefault(uint256)" $AID
```

## Step 9: Run On-Chain Settlement Proof

Standalone script that proves `TransactionSubmitter` → `registerUsage()` with real Anvil tx hashes:

```bash
cd mailbox-relayer
export RPC_URL=http://127.0.0.1:8545
export DIAMOND_ADDRESS="<from Step 2>"
export CHAIN_ID=31337
export RELAYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

npx tsx scripts/prove-onchain-settlement.ts
```

## Step 10: Persist Outputs

```bash
{
  echo '# Lifecycle Outputs (Selected Providers)'
  echo
  echo '```json'
  cat /tmp/provider_lifecycles.json
  echo '```'
} > LIFECYCLE-OUTPUTS.md

{
  echo '# Pure Financing Lifecycle (Anvil Timewarp)'
  echo
  echo '```json'
  cat /tmp/pure_financing_timewarp.json 2>/dev/null || echo '{}'
  echo '```'
} > PURE-FINANCING-TIMEWARP-OUTPUTS.md
```

## Expected Success Criteria

1. Diamond deployed with all facets (base + V1 + agentic/EqualScale).
2. Relayer starts in Phase 2 mode (`phase2 signer configured` in log).
3. Provider activations succeed for providers with valid API keys.
4. ACP lifecycle produces 5 real tx hashes, all `status: success`.
5. Settlement proof produces real `registerUsage` tx hashes on Anvil.
6. Pure financing timewarp completes Active → Delinquent → Defaulted.

## Cleanup

```bash
pkill -f anvil
pkill -f "node dist/index"
```
