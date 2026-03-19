---
name: local-full-stack-lifecycle
description: Clone dependencies, deploy full local EqualFi stack on Anvil (EntryPoint + ERC-8004 + ERC-6551 + Diamond), then run mailbox-relayer provider lifecycles with your own API keys.
---

# Local Full-Stack Lifecycle Skill

Use this skill when you need to spin up the full local stack from scratch and run Venice + Bankr flows with your own keys.

## What this covers

1. Clone required external repos (`account-abstraction`, `erc-8004-contracts`, `erc6551/reference`)
2. Start Anvil (`http://127.0.0.1:8545`, chain `31337`)
3. Deploy contracts:
- ERC-4337 EntryPoint v0.7 (resolve from `account-abstraction/deployments/dev/EntryPoint.json`)
- ERC-8004 reference contracts
- ERC-6551 canonical registry
- EqualFi Diamond (`DeployV1.s.sol`)
4. Start relayer against Anvil
5. Run Venice + Bankr lifecycle flow and persist output

## Preconditions

1. You are in `hackathon/`.
2. Tools available: `git`, `node`, `npm`, `yarn`, `pnpm`, `forge`, `cast`, `jq`, `curl`, `anvil`.
3. You have provider keys:
- Venice admin key
- Venice inference key
- Bankr LLM key

## Step 0: Clone Required Contract Repos

This skill expects `EqualFi/`, `mailbox-relayer/`, and `mailbox-sdk/` in the current `hackathon/` directory.
Only external dependencies (`account-abstraction`, `erc-8004-contracts`, `erc6551/reference`) are cloned to `./.deps` by default.

```bash
set -euo pipefail
PROJECTS_DIR="${PROJECTS_DIR:-$(pwd)/.deps}"
mkdir -p "$PROJECTS_DIR"

[ -d "$PROJECTS_DIR/account-abstraction/.git" ] || git clone https://github.com/eth-infinitism/account-abstraction.git "$PROJECTS_DIR/account-abstraction"
[ -d "$PROJECTS_DIR/erc-8004-contracts/.git" ] || git clone https://github.com/erc-8004/erc-8004-contracts.git "$PROJECTS_DIR/erc-8004-contracts"
[ -d "$PROJECTS_DIR/reference/.git" ] || git clone https://github.com/erc6551/reference.git "$PROJECTS_DIR/reference"
```

## Step 1: Start Anvil

Run in terminal A:

```bash
anvil --host 127.0.0.1 --port 8545 --chain-id 31337 --accounts 10 --balance 10000
```

Use default funded account/private key for local deploys:

- Address: `0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`
- Private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## Step 2: Deploy Local Contract Stack

### 2.1 Deploy EntryPoint v0.7 + SimpleAccountFactory (manual flow)

Run from `hackathon/`:

```bash
set -euo pipefail
PROJECTS_DIR="${PROJECTS_DIR:-$(pwd)/.deps}"
AA_DIR="$PROJECTS_DIR/account-abstraction"
YARN_BIN="${YARN_BIN:-yarn}"

cd "$AA_DIR"
git fetch origin releases/v0.7 --depth 1
git checkout --detach origin/releases/v0.7
echo "test test test test test test test test test test test junk" > ./mnemonic.txt
export MNEMONIC_FILE=./mnemonic.txt
"$YARN_BIN" install
"$YARN_BIN" deploy --network dev

ENTRYPOINT_ADDRESS="$(jq -r '.address // empty' deployments/dev/EntryPoint.json)"
if [ -z "$ENTRYPOINT_ADDRESS" ]; then
  echo "failed to resolve ENTRYPOINT_ADDRESS from deployments/dev/EntryPoint.json" >&2
  exit 1
fi

# must be non-zero bytecode at the deployed address
if [ "$(cast code --rpc-url http://127.0.0.1:8545 "$ENTRYPOINT_ADDRESS")" = "0x" ]; then
  echo "no bytecode at ENTRYPOINT_ADDRESS=$ENTRYPOINT_ADDRESS" >&2
  exit 1
fi

echo "ENTRYPOINT_ADDRESS=$ENTRYPOINT_ADDRESS"
```

Set `ENTRYPOINT_ADDRESS` for `DeployV1.s.sol`:

```bash
export ENTRYPOINT_ADDRESS="$(jq -r '.address // empty' "$PROJECTS_DIR/account-abstraction/deployments/dev/EntryPoint.json")"
```

### 2.2 Deploy ERC-8004 reference contracts (manual flow)

Run from `hackathon/`:

```bash
set -euo pipefail
PROJECTS_DIR="${PROJECTS_DIR:-$(pwd)/.deps}"
ERC8004_DIR="$PROJECTS_DIR/erc-8004-contracts"
RPC_URL=http://127.0.0.1:8545

cd "$ERC8004_DIR"
# Hardhat 3 validates all configured networks; set these for local runs.
export SEPOLIA_RPC_URL="${SEPOLIA_RPC_URL:-$RPC_URL}"
export MAINNET_RPC_URL="${MAINNET_RPC_URL:-$RPC_URL}"

npm run local:factory
npm run local:deploy:vanity | tee /tmp/erc8004_local_deploy.log
```

Upgrade vanity proxies to latest implementations by impersonating ERC-8004 owner on Anvil:

```bash
set -euo pipefail
RPC_URL=http://127.0.0.1:8545
IDENTITY_PROXY=0x8004A818BFB912233c491871b3d84c89A494BD9e
REPUTATION_PROXY=0x8004B663056A597Dffe9eCcC1965A193B7388713
VALIDATION_PROXY=0x8004Cb1BF31DAf7788923b405b754f57acEB4272

IDENTITY_IMPL="$(grep -E 'IdentityRegistry:[[:space:]]+0x[0-9a-fA-F]{40}$' /tmp/erc8004_local_deploy.log | tail -n1 | awk '{print $2}')"
REPUTATION_IMPL="$(grep -E 'ReputationRegistry:[[:space:]]+0x[0-9a-fA-F]{40}$' /tmp/erc8004_local_deploy.log | tail -n1 | awk '{print $2}')"
VALIDATION_IMPL="$(grep -E 'ValidationRegistry:[[:space:]]+0x[0-9a-fA-F]{40}$' /tmp/erc8004_local_deploy.log | tail -n1 | awk '{print $2}')"

for value in "$IDENTITY_IMPL" "$REPUTATION_IMPL" "$VALIDATION_IMPL"; do
  if ! [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "failed to parse implementation address from /tmp/erc8004_local_deploy.log" >&2
    exit 1
  fi
done

ERC8004_OWNER="$(cast call --rpc-url "$RPC_URL" "$IDENTITY_PROXY" "owner()(address)")"

cast rpc --rpc-url "$RPC_URL" anvil_impersonateAccount "$ERC8004_OWNER" >/dev/null
cast rpc --rpc-url "$RPC_URL" anvil_setBalance "$ERC8004_OWNER" "0x56BC75E2D63100000" >/dev/null

cast send --rpc-url "$RPC_URL" --from "$ERC8004_OWNER" --unlocked \
  "$IDENTITY_PROXY" "upgradeToAndCall(address,bytes)" "$IDENTITY_IMPL" "$(cast calldata "initialize()")"
cast send --rpc-url "$RPC_URL" --from "$ERC8004_OWNER" --unlocked \
  "$REPUTATION_PROXY" "upgradeToAndCall(address,bytes)" "$REPUTATION_IMPL" "$(cast calldata "initialize(address)" "$IDENTITY_PROXY")"
cast send --rpc-url "$RPC_URL" --from "$ERC8004_OWNER" --unlocked \
  "$VALIDATION_PROXY" "upgradeToAndCall(address,bytes)" "$VALIDATION_IMPL" "$(cast calldata "initialize(address)" "$IDENTITY_PROXY")"

cast rpc --rpc-url "$RPC_URL" anvil_stopImpersonatingAccount "$ERC8004_OWNER" >/dev/null
```

Optional verification:

```bash
set -euo pipefail
PROJECTS_DIR="${PROJECTS_DIR:-$(pwd)/.deps}"
cd "$PROJECTS_DIR/erc-8004-contracts"
npm run local:verify:vanity
```

Set `IDENTITY_REGISTRY` for `DeployV1.s.sol`:

```bash
export IDENTITY_REGISTRY=0x8004A818BFB912233c491871b3d84c89A494BD9e
```

### 2.3 Deploy ERC-6551 canonical registry (manual flow)

Run from `hackathon/`:

```bash
set -euo pipefail
PROJECTS_DIR="${PROJECTS_DIR:-$(pwd)/.deps}"
REFERENCE_DIR="$PROJECTS_DIR/reference"
RPC_URL=http://127.0.0.1:8545
ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ERC6551_REGISTRY=0x000000006551c19487814612e58FE06813775758

cd "$REFERENCE_DIR"
git submodule update --init --recursive

if [ "$(cast code --rpc-url "$RPC_URL" "$ERC6551_REGISTRY")" = "0x" ]; then
  forge script script/DeployRegistry.s.sol:DeployRegistry \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --private-key "$ANVIL_PRIVATE_KEY"
fi
```

Set `ERC6551_REGISTRY` for `DeployV1.s.sol`:

```bash
export ERC6551_REGISTRY=0x000000006551c19487814612e58FE06813775758
```

### 2.4 Deploy EqualFi Diamond (must use DeployV1.s.sol)

This step is required and must use `EqualFi/script/DeployV1.s.sol`.

Run from `hackathon/EqualFi/`:

```bash
set -euo pipefail
export RPC_URL=http://127.0.0.1:8545
export OWNER=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
export TIMELOCK=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# from 2.1 / 2.2 / 2.3:
# ENTRYPOINT_ADDRESS
# IDENTITY_REGISTRY
# ERC6551_REGISTRY

forge script script/DeployV1.s.sol:DeployV1Script \
  --sig "runDeployV1()" \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --skip-simulation
```

Extract the deployed Diamond address:

```bash
jq -r '.transactions[] | select(.contractName=="Diamond" and .transactionType=="CREATE") | .contractAddress' \
  broadcast/DeployV1.s.sol/31337/runDeployV1-latest.json | tail -n 1
```

Save that as `DIAMOND_ADDRESS` for relayer startup.

## Step 3: Set Provider Keys (optional per provider)

```bash
# Venice
export VENICE_ADMIN_API_KEY="..."
export VENICE_INFERENCE_API_KEY="..."

# Bankr
export BANKR_LLM_KEY="..."

# Lambda
export LAMBDA_API_KEY="..."
export LAMBDA_BASE_URL="${LAMBDA_BASE_URL:-https://cloud.lambdalabs.com/api/v1}"

# RunPod
export RUNPOD_API_KEY="..."
export RUNPOD_SERVERLESS_BASE_URL="${RUNPOD_SERVERLESS_BASE_URL:-https://api.runpod.ai/v2}"
export RUNPOD_INFRA_BASE_URL="${RUNPOD_INFRA_BASE_URL:-https://rest.runpod.io/v1}"
```

## Step 3.1: Detect Available Keys + Ask Which Lifecycles to Run

If running this as an agent, **ask the user which lifecycles to run** from:
- `bankr`
- `venice`
- `lambda`
- `runpod`

Then set:

```bash
# comma-separated list, e.g. "venice,bankr" or "lambda,runpod"
export LIFECYCLES="venice,bankr"
```

If `LIFECYCLES` is unset, default to all providers with detected keys:

```bash
AVAILABLE=()
if [ -n "${VENICE_ADMIN_API_KEY:-}" ] && [ -n "${VENICE_INFERENCE_API_KEY:-}" ]; then AVAILABLE+=("venice"); fi
if [ -n "${BANKR_LLM_KEY:-}" ]; then AVAILABLE+=("bankr"); fi
if [ -n "${LAMBDA_API_KEY:-}" ]; then AVAILABLE+=("lambda"); fi
if [ -n "${RUNPOD_API_KEY:-}" ]; then AVAILABLE+=("runpod"); fi
echo "Detected lifecycle providers: ${AVAILABLE[*]:-none}"
```

## Step 4: Start Settlement Mock Webhook

Run in terminal B:

```bash
node -e 'const http=require("http");const port=3213;const token="local-settlement-token";const server=http.createServer((req,res)=>{let body="";req.on("data",c=>body+=c);req.on("end",()=>{if(req.method!=="POST"){res.writeHead(405,{"content-type":"application/json"});return res.end(JSON.stringify({error:"method_not_allowed"}));}if(req.url!=="/settle"){res.writeHead(404,{"content-type":"application/json"});return res.end(JSON.stringify({error:"not_found"}));}if(req.headers.authorization!=="Bearer "+token){res.writeHead(401,{"content-type":"application/json"});return res.end(JSON.stringify({error:"unauthorized"}));}let agreement="unknown";try{const parsed=JSON.parse(body||"{}");agreement=(parsed&&parsed.submission&&parsed.submission.agreementId)||"unknown";}catch{}res.writeHead(200,{"content-type":"application/json"});res.end(JSON.stringify({ok:true,txHash:"0xsettled-"+agreement+"-"+Date.now()}));});});server.listen(port,"127.0.0.1",()=>console.log("settlement mock listening on http://127.0.0.1:"+port+"/settle"));'
```

## Step 5: Start Relayer Against Anvil

Run in terminal C:

```bash
export VENICE_API_KEY="$VENICE_ADMIN_API_KEY"
export BANKR_LLM_KEY="${BANKR_LLM_KEY:-}"
export LAMBDA_API_KEY="${LAMBDA_API_KEY:-}"
export RUNPOD_API_KEY="${RUNPOD_API_KEY:-}"
export VENICE_BASE_URL="https://api.venice.ai/api/v1"
export BANKR_LLM_BASE_URL="https://llm.bankr.bot"
export BANKR_USAGE_PATH="/v1/usage"
export LAMBDA_BASE_URL="${LAMBDA_BASE_URL:-https://cloud.lambdalabs.com/api/v1}"
export RUNPOD_SERVERLESS_BASE_URL="${RUNPOD_SERVERLESS_BASE_URL:-https://api.runpod.ai/v2}"
export RUNPOD_INFRA_BASE_URL="${RUNPOD_INFRA_BASE_URL:-https://rest.runpod.io/v1}"

export ADMIN_AUTH_TOKEN="local-admin-token"
export USAGE_SETTLEMENT_WEBHOOK_URL="http://127.0.0.1:3213/settle"
export USAGE_SETTLEMENT_WEBHOOK_TOKEN="local-settlement-token"

export RPC_URL="http://127.0.0.1:8545"
export CHAIN_ID="31337"
export DIAMOND_ADDRESS="<paste_diamond_address>"
export RELAYER_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

export PORT="3113"
export HOST="127.0.0.1"
export RELAYER_DB_PATH="/tmp/mailbox-relayer-provider-lifecycles.sqlite"

export METERING_ENABLED="false"
export KILLSWITCH_RETRY_ENABLED="false"
export USAGE_SETTLEMENT_ENABLED="false"
export COVENANT_MONITOR_ENABLED="false"
export INTEREST_ACCRUAL_ENABLED="false"

pnpm --dir mailbox-relayer dev
```

## Step 6: Run Selected Provider Lifecycles (Bankr/Venice/Lambda/RunPod)

Run in terminal D:

```bash
set -euo pipefail
BASE="http://127.0.0.1:3113"
AUTH="Authorization: Bearer local-admin-token"
BORROWER_ADDRESS="${BORROWER_ADDRESS:-0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266}"
LAMBDA_INSTANCE_TYPE="${LAMBDA_INSTANCE_TYPE:-a10_24gb}"

available=()
if [ -n "${VENICE_ADMIN_API_KEY:-}" ] && [ -n "${VENICE_INFERENCE_API_KEY:-}" ]; then available+=("venice"); fi
if [ -n "${BANKR_LLM_KEY:-}" ]; then available+=("bankr"); fi
if [ -n "${LAMBDA_API_KEY:-}" ]; then available+=("lambda"); fi
if [ -n "${RUNPOD_API_KEY:-}" ]; then available+=("runpod"); fi

if [ -z "${LIFECYCLES:-}" ]; then
  if [ "${#available[@]}" -gt 0 ]; then
    LIFECYCLES="$(IFS=,; echo "${available[*]}")"
  else
    LIFECYCLES=""
  fi
fi

selected_csv="$(echo "${LIFECYCLES:-}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
IFS=',' read -r -a selected <<< "$selected_csv"

# If Lambda is selected and no SSH pubkey is supplied, generate a local temporary one.
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

  curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' -d "$activation_payload" > "/tmp/${provider}_activation.json"
  curl -sS -X POST "$BASE/metering/run" -H "$AUTH" -H 'content-type: application/json' -d "{\"agreementId\":\"$aid\"}" > "/tmp/${provider}_metering.json"
  curl -sS "$BASE/metering/submissions?limit=50" | jq --arg aid "$aid" '{submissions:[.submissions[] | select(.agreementId==$aid)]}' > "/tmp/${provider}_submissions.json"
  curl -sS -X POST "$BASE/settlement/run" -H "$AUTH" -H 'content-type: application/json' -d "{}" > "/tmp/${provider}_settlement_before_breach.json"
  curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' -d "$breach_payload" > "/tmp/${provider}_breach.json"
  curl -sS -X POST "$BASE/events/onchain" -H "$AUTH" -H 'content-type: application/json' -d "$close_payload" > "/tmp/${provider}_close.json"
  curl -sS "$BASE/agreements/$aid/state" > "/tmp/${provider}_state.json"

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

BASE_AID="$(date +%s)"
idx=0
for provider in "${selected[@]}"; do
  [ -n "$provider" ] || continue
  case "$provider" in
    venice)
      [ -n "${VENICE_ADMIN_API_KEY:-}" ] && [ -n "${VENICE_INFERENCE_API_KEY:-}" ] || {
        jq --arg p "$provider" '. + {($p): {skipped:true, reason:"missing_keys"}}' /tmp/provider_sections.json > /tmp/provider_sections.next.json
        mv /tmp/provider_sections.next.json /tmp/provider_sections.json
        continue
      }
      ;;
    bankr)
      [ -n "${BANKR_LLM_KEY:-}" ] || {
        jq --arg p "$provider" '. + {($p): {skipped:true, reason:"missing_keys"}}' /tmp/provider_sections.json > /tmp/provider_sections.next.json
        mv /tmp/provider_sections.next.json /tmp/provider_sections.json
        continue
      }
      ;;
    lambda)
      [ -n "${LAMBDA_API_KEY:-}" ] || {
        jq --arg p "$provider" '. + {($p): {skipped:true, reason:"missing_keys"}}' /tmp/provider_sections.json > /tmp/provider_sections.next.json
        mv /tmp/provider_sections.next.json /tmp/provider_sections.json
        continue
      }
      ;;
    runpod)
      [ -n "${RUNPOD_API_KEY:-}" ] || {
        jq --arg p "$provider" '. + {($p): {skipped:true, reason:"missing_keys"}}' /tmp/provider_sections.json > /tmp/provider_sections.next.json
        mv /tmp/provider_sections.next.json /tmp/provider_sections.json
        continue
      }
      ;;
    *)
      jq --arg p "$provider" '. + {($p): {skipped:true, reason:"unknown_provider"}}' /tmp/provider_sections.json > /tmp/provider_sections.next.json
      mv /tmp/provider_sections.next.json /tmp/provider_sections.json
      continue
      ;;
  esac

  aid="$((BASE_AID + idx + 1))"
  blockBase="$((880000 + (idx * 10000)))"
  run_provider_lifecycle "$provider" "$aid" "$blockBase"
  idx=$((idx + 1))
done

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

## Step 7: Always Run Pure Financing Default Scenario (No API Keys)

This step should always run, even if no provider lifecycle is selected.

```bash
set -euo pipefail
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PURE_FINANCING_AGREEMENT_ID="${PURE_FINANCING_AGREEMENT_ID:-1}"
PURE_FINANCING_USAGE_AMOUNT_WEI="${PURE_FINANCING_USAGE_AMOUNT_WEI:-400000000000000000000}" # 400e18
PURE_FINANCING_UNIT_TYPE="${PURE_FINANCING_UNIT_TYPE:-$(cast keccak "VENICE_TEXT_TOKEN_IN")}"
PURE_FINANCING_OWNER_PRIVATE_KEY="${PURE_FINANCING_OWNER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
PURE_FINANCING_RELAYER_PRIVATE_KEY="${PURE_FINANCING_RELAYER_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

: "${DIAMOND_ADDRESS:?DIAMOND_ADDRESS must be set from Step 2.4}"

mkdir -p /tmp/pure-finance
RELAYER_ADDRESS="$(cast wallet address --private-key "$PURE_FINANCING_RELAYER_PRIVATE_KEY")"

# Ensure relayer role (idempotent if already granted)
cast send --rpc-url "$RPC_URL" --private-key "$PURE_FINANCING_OWNER_PRIVATE_KEY" \
  "$DIAMOND_ADDRESS" "grantRelayerRole(address)" "$RELAYER_ADDRESS" >/tmp/pure-finance/grant-relayer.txt 2>/dev/null || true

if REGISTER_JSON="$(cast send --rpc-url "$RPC_URL" --private-key "$PURE_FINANCING_RELAYER_PRIVATE_KEY" --json \
  "$DIAMOND_ADDRESS" "registerUsage(uint256,bytes32,uint256)" \
  "$PURE_FINANCING_AGREEMENT_ID" "$PURE_FINANCING_UNIT_TYPE" "$PURE_FINANCING_USAGE_AMOUNT_WEI" 2>/tmp/pure-finance/register-usage.err)"; then

  REGISTER_TX="$(echo "$REGISTER_JSON" | jq -r '.transactionHash // empty')"
  cast call --rpc-url "$RPC_URL" "$DIAMOND_ADDRESS" \
    "getAgreement(uint256)((uint256,uint256,string,uint256,uint256,bytes32,address,uint8,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,bytes32))" \
    "$PURE_FINANCING_AGREEMENT_ID" > /tmp/pure-finance/agreement_after_usage.txt

  cast rpc --rpc-url "$RPC_URL" anvil_increaseTime 86400 >/dev/null
  cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
  ACCRUE_TX="$(cast send --rpc-url "$RPC_URL" --private-key "$PURE_FINANCING_OWNER_PRIVATE_KEY" --json \
    "$DIAMOND_ADDRESS" "accrueInterest(uint256)" "$PURE_FINANCING_AGREEMENT_ID" | jq -r '.transactionHash // empty')"
  cast call --rpc-url "$RPC_URL" "$DIAMOND_ADDRESS" \
    "getAgreement(uint256)((uint256,uint256,string,uint256,uint256,bytes32,address,uint8,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,bytes32))" \
    "$PURE_FINANCING_AGREEMENT_ID" > /tmp/pure-finance/agreement_after_day1_accrual.txt

  cast rpc --rpc-url "$RPC_URL" anvil_increaseTime 172801 >/dev/null
  cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
  DELINQUENCY_TX="$(cast send --rpc-url "$RPC_URL" --private-key "$PURE_FINANCING_OWNER_PRIVATE_KEY" --json \
    "$DIAMOND_ADDRESS" "detectDelinquency(uint256)" "$PURE_FINANCING_AGREEMENT_ID" | jq -r '.transactionHash // empty')"
  cast call --rpc-url "$RPC_URL" "$DIAMOND_ADDRESS" \
    "getAgreement(uint256)((uint256,uint256,string,uint256,uint256,bytes32,address,uint8,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,bytes32))" \
    "$PURE_FINANCING_AGREEMENT_ID" > /tmp/pure-finance/agreement_after_delinquency.txt

  cast rpc --rpc-url "$RPC_URL" anvil_increaseTime 259201 >/dev/null
  cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
  DEFAULT_TX="$(cast send --rpc-url "$RPC_URL" --private-key "$PURE_FINANCING_OWNER_PRIVATE_KEY" --json \
    "$DIAMOND_ADDRESS" "triggerDefault(uint256)" "$PURE_FINANCING_AGREEMENT_ID" | jq -r '.transactionHash // empty')"
  cast call --rpc-url "$RPC_URL" "$DIAMOND_ADDRESS" \
    "getAgreement(uint256)((uint256,uint256,string,uint256,uint256,bytes32,address,uint8,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,bytes32))" \
    "$PURE_FINANCING_AGREEMENT_ID" > /tmp/pure-finance/agreement_after_default.txt

  jq -n \
    --arg runAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg agreementId "$PURE_FINANCING_AGREEMENT_ID" \
    --arg registerTx "$REGISTER_TX" \
    --arg accrueTx "$ACCRUE_TX" \
    --arg detectDelinquencyTx "$DELINQUENCY_TX" \
    --arg triggerDefaultTx "$DEFAULT_TX" \
    '{
      runAt: $runAt,
      mode: "anvil_timewarp",
      agreementId: $agreementId,
      registerUsageTx: $registerTx,
      accrueInterestTx: $accrueTx,
      detectDelinquencyTx: $detectDelinquencyTx,
      triggerDefaultTx: $triggerDefaultTx,
      snapshots: {
        afterUsage: "/tmp/pure-finance/agreement_after_usage.txt",
        afterDay1Accrual: "/tmp/pure-finance/agreement_after_day1_accrual.txt",
        afterDelinquency: "/tmp/pure-finance/agreement_after_delinquency.txt",
        afterDefault: "/tmp/pure-finance/agreement_after_default.txt"
      }
    }' > /tmp/pure_financing_timewarp.json
else
  # Fallback still runs keyless pure-financing logic through harness warps.
  (cd EqualFi && forge test --match-path test/stress/default-cascade.t.sol -vv > /tmp/pure-finance/default-cascade.log 2>&1 || true)
  jq -n \
    --arg runAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg agreementId "$PURE_FINANCING_AGREEMENT_ID" \
    --arg reason "live_anvil_timewarp_flow_failed" \
    --arg stderrPath "/tmp/pure-finance/register-usage.err" \
    --arg fallbackLog "/tmp/pure-finance/default-cascade.log" \
    '{
      runAt: $runAt,
      mode: "fallback_harness_test",
      agreementId: $agreementId,
      reason: $reason,
      registerUsageErrorPath: $stderrPath,
      fallbackLogPath: $fallbackLog
    }' > /tmp/pure_financing_timewarp.json
fi

cat /tmp/pure_financing_timewarp.json
```

## Step 8: Persist Outputs

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
  cat /tmp/pure_financing_timewarp.json
  echo '```'
} > PURE-FINANCING-TIMEWARP-OUTPUTS.md
```

## Expected Success Criteria

1. ERC-6551 registry deployed at canonical `0x000000006551c19487814612e58FE06813775758`.
2. EntryPoint v0.7 bytecode present at the resolved `ENTRYPOINT_ADDRESS` from `account-abstraction/deployments/dev/EntryPoint.json`.
3. Diamond deploy broadcast exists and `DIAMOND_ADDRESS` is set.
4. Relayer starts with Anvil phase2 env (`RPC_URL`, `CHAIN_ID`, `DIAMOND_ADDRESS`, `RELAYER_PRIVATE_KEY`).
5. Selected provider lifecycle outputs (any of Bankr/Venice/Lambda/RunPod) are written to `LIFECYCLE-OUTPUTS.md`.
6. Pure financing timewarp workflow always runs and writes `PURE-FINANCING-TIMEWARP-OUTPUTS.md` (live anvil flow or fallback harness test).

## Cleanup

Stop terminals with `Ctrl+C`.
