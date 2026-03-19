# ERC-4337 Local Deployment Guide

> Complete setup for EntryPoint, SimpleAccountFactory, and Bundler for local EqualScale testing

---

## Overview

This guide covers deploying the full ERC-4337 stack locally.

**Scope note:** this document is an operator-facing local deployment guide, not a claim that the submission repo is a turnkey one-command demo environment for every reviewer. Some flows require external API credentials, local dependencies, and provider availability.

This guide covers deploying the full ERC-4337 stack locally:

| Component | Purpose |
|-----------|---------|
| **EntryPoint** | Core contract that validates and executes UserOperations |
| **SimpleAccountFactory** | Deploys smart contract wallets (SimpleAccount) |
| **Bundler** | Collects UserOps from mempool and submits to EntryPoint |

---

## Part 1: EntryPoint Deployment

### What is EntryPoint?

**EntryPoint** is the core contract of ERC-4337. It acts as the universal gateway for all smart contract wallet interactions:

| Function | Purpose |
|----------|---------|
| `handleOps(UserOperation[] ops, address beneficiary)` | Main entry for bundlers — validates and executes UserOps |
| `simulateValidation(UserOperation op)` | Off-chain validation check before inclusion |
| `depositTo(address target)` | Fund wallet/paymaster gas deposits |
| `balanceOf(address)` | Check deposited balance |
| `addStake()`, `unlockStake()`, `withdrawStake()` | Paymaster staking (anti-griefing) |

### Key Insight: Deterministic Addresses

The official deployment scripts use **CREATE2** with a fixed salt. This means:

```
Same salt → Same address across all networks
```

Local EntryPoint address will match mainnet/testnet addresses, ensuring:
- Tooling compatibility (bundler SDKs expect this address)
- No config changes when moving between environments
- Portable tests

### Deployment Steps

#### 1. Clone the Official Repo

```bash
cd ~/workspace  # or wherever you keep repos
git clone https://github.com/eth-infinitism/account-abstraction.git
cd account-abstraction
git fetch origin releases/v0.7 --depth 1
git checkout releases/v0.7
yarn install
```

#### 2. Configure Local Network

`releases/v0.7` already includes a `dev` network at `http://localhost:8545`.

```typescript
networks: {
  dev: { url: "http://localhost:8545" },
}
```

#### 3. Create Deployer Mnemonic

```bash
echo "test test test test test test test test test test test junk" > ./mnemonic.txt
export MNEMONIC_FILE=./mnemonic.txt
```

#### 4. Start Local Node

```bash
# Hardhat
npx hardhat node

# Or Anvil (Foundry)
anvil --chain-id 31337
```

#### 5. Deploy EntryPoint

```bash
yarn deploy --network dev
```

### Expected Output

```
Deploying EntryPoint to network: dev
EntryPoint deployed at: 0x0000000071727De22Ee835bAF822C1d29692AA4B
```

### Canonical Addresses

| Version | Address |
|---------|---------|
| v0.6 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` |
| v0.7 | `0x0000000071727De22Ee835bAF822C1d29692AA4B` |
| v0.8 | `0x4337084d9e255ff0702461cf8895ce9e3b5ff108` |

---

## Part 2: SimpleAccountFactory Deployment

### What is SimpleAccountFactory?

**SimpleAccountFactory** deploys `SimpleAccount` contracts — minimal ERC-4337 compliant smart contract wallets. It uses CREATE2 for deterministic addresses.

| Function | Purpose |
|----------|---------|
| `createAccount(address owner, uint256 salt)` | Deploy a new SimpleAccount |
| `getAddress(address owner, uint256 salt)` | Get counterfactual address before deployment |

### Deployment Steps

SimpleAccountFactory is included in the same repo and deploys with EntryPoint:

```bash
# Already in account-abstraction repo
yarn deploy --network localhost
```

This deploys both:
1. EntryPoint
2. SimpleAccountFactory

### Manual Deployment (if needed)

```bash
# Using Hardhat console
npx hardhat console --network localhost

# In console
const SimpleAccountFactory = await ethers.getContractFactory("SimpleAccountFactory");
const factory = await SimpleAccountFactory.deploy(ENTRY_POINT_ADDRESS);
console.log("SimpleAccountFactory deployed at:", factory.address);
```

### Using SimpleAccountFactory

```typescript
// Create a new account
const factory = await ethers.getContractAt("SimpleAccountFactory", FACTORY_ADDRESS);
const owner = "0x..."; // Owner address
const salt = 0; // Unique salt for this account

// Get counterfactual address
const accountAddress = await factory.getAddress(owner, salt);
console.log("Account will be deployed at:", accountAddress);

// Fund the account first (for gas)
await signer.sendTransaction({
  to: accountAddress,
  value: ethers.utils.parseEther("0.1")
});

// Deploy the account
await factory.createAccount(owner, salt);
```

---

## Part 3: Bundler Setup

### What is a Bundler?

A **Bundler** collects UserOperations from the mempool, validates them, and submits them to EntryPoint via `handleOps()`. It's the equivalent of a block builder in the AA stack.

### Requirements

- **Geth node** (required for full spec compliance with `debug_traceCall`)
- Hardhat/Anvil work with `--unsafe` flag (skips some security checks)

### Bundler Deployment Steps

#### 1. Clone the Bundler Repo

```bash
cd ~/workspace
git clone https://github.com/eth-infinitism/bundler.git
cd bundler
yarn install
yarn preprocess
```

#### 2. Start Local Geth (for full spec compliance)

```bash
docker run --rm -ti --name geth -p 8545:8545 ethereum/client-go:v1.13.5 \
  --miner.gaslimit 12000000 \
  --http --http.api personal,eth,net,web3,debug \
  --http.vhosts '*,localhost,host.docker.internal' --http.addr "0.0.0.0" \
  --allow-insecure-unlock --rpc.allow-unprotected-txs \
  --dev \
  --verbosity 2 \
  --nodiscover --maxpeers 0 --mine \
  --networkid 1337
```

#### 3. Deploy Contracts

```bash
# From bundler repo
yarn hardhat-deploy --network localhost
```

#### 4. Start the Bundler

```bash
# Full spec (with Geth)
yarn run bundler

# Unsafe mode (with Hardhat/Anvil)
yarn run bundler --unsafe
```

Bundler will be active at: `http://localhost:3000/rpc`

#### 5. Test the Bundler

```bash
yarn run runop --deployFactory --network http://localhost:8545/ --entryPoint 0x0000000071727De22Ee835bAF822C1d29692AA4B
```

This `runop` script:
1. Deploys a wallet deployer (if needed)
2. Creates a random signer (owner for wallet)
3. Determines wallet address and funds it
4. Sends a transaction (creates the wallet)
5. Sends another transaction (on existing wallet)

---

## Part 4: Full Local Stack

### Recommended Setup

For EqualScale testing, run this full stack:

```bash
# Terminal 1: Local node
anvil --chain-id 31337

# Terminal 2: Deploy contracts (EntryPoint + SimpleAccountFactory)
cd ~/workspace/account-abstraction
git fetch origin releases/v0.7 --depth 1
git checkout releases/v0.7
export MNEMONIC_FILE=./mnemonic.txt
yarn deploy --network dev

# Terminal 3: Start bundler
cd ~/workspace/bundler
yarn run bundler --unsafe

# Terminal 4: Your tests
cd ~/workspace/hackathon/EqualFi
forge test --fork-url http://localhost:8545
```

### Environment Variables

Create `.env` for your project:

```bash
# ERC-4337 (v0.7 target)
ENTRY_POINT=0x0000000071727De22Ee835bAF822C1d29692AA4B

# Local
RPC_URL=http://localhost:8545
BUNDLER_URL=http://localhost:3000/rpc

# Get from deployment logs
SIMPLE_ACCOUNT_FACTORY=0x...
```

---

## Integration Examples

### Solidity Tests

```solidity
// test/AAIntegration.t.sol
import {Test} from "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract AAIntegrationTest is Test {
    address constant ENTRY_POINT = 0x0000000071727De22Ee835bAF822C1d29692AA4B;
    
    function setUp() public {
        // Fork local node
        vm.createSelectFork("http://localhost:8545");
    }
    
    function testEntryPointDeployed() public view {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(ENTRY_POINT)
        }
        assertGt(codeSize, 0, "EntryPoint not deployed");
    }
}
```

### TypeScript/ ethers

```typescript
import { ethers } from "ethers";
import { EntryPoint__factory } from "@account-abstraction/contracts";

const provider = new ethers.providers.JsonRpcProvider("http://localhost:8545");
const entryPoint = EntryPoint__factory.connect(
  "0x0000000071727De22Ee835bAF822C1d29692AA4B",
  provider
);

// Check balance
const balance = await entryPoint.balanceOf("0x...");
console.log("Deposit balance:", ethers.utils.formatEther(balance));
```

### Sending a UserOp

```typescript
import { ethers } from "ethers";
import { UserOpBuilder } from "@account-abstraction/sdk";

// Build UserOp
const userOp = {
  sender: accountAddress,
  nonce: 0,
  initCode: factoryAddress + initCallData.slice(2),
  callData: accountInterface.encodeFunctionData("execute", [target, value, data]),
  callGasLimit: 100000,
  verificationGasLimit: 100000,
  preVerificationGas: 21000,
  maxFeePerGas: ethers.utils.parseUnits("10", "gwei"),
  maxPriorityFeePerGas: ethers.utils.parseUnits("1", "gwei"),
  paymasterAndData: "0x",
  signature: "0x"
};

// Sign UserOp
const userOpHash = await entryPoint.getUserOpHash(userOp);
const signature = await owner.signMessage(ethers.utils.arrayify(userOpHash));
userOp.signature = signature;

// Send to bundler
const response = await fetch("http://localhost:3000/rpc", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    jsonrpc: "2.0",
    method: "eth_sendUserOperation",
    params: [userOp, entryPointAddress],
    id: 1
  })
});
```

---

## Common Issues

### 1. "Contract code size exceeded"

EntryPoint is large. Ensure:
- Sufficient gas limit
- Optimizer enabled in Hardhat config

### 2. "Address already in use"

Restart the local node to clear state.

### 3. "Insufficient funds for deployer"

Local nodes pre-fund test accounts. Use:
```bash
anvil --accounts 10 --balance 10000
```

### 4. Version Mismatch

Different EntryPoint versions have different addresses. Check which version your SDK expects.

### 5. Bundler "unsafe" mode

With Hardhat/Anvil, use `--unsafe` flag. Full spec requires Geth with `debug_traceCall`.

---

## Quick Reference

### Addresses

| Contract | v0.6 | v0.7 | v0.8 |
|----------|------|------|------|
| EntryPoint | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | `0x0000000071727De22Ee835bAF822C1d29692AA4B` | `0x4337084d9e255ff0702461cf8895ce9e3b5ff108` |

### Commands

```bash
# Deploy EntryPoint + Factory
cd account-abstraction && yarn deploy --network localhost

# Start bundler
cd bundler && yarn run bundler --unsafe

# Test bundler
yarn run runop --deployFactory --network http://localhost:8545/ --entryPoint 0x0000000071727De22Ee835bAF822C1d29692AA4B
```

### Repos

| Component | Repo |
|-----------|------|
| EntryPoint + Contracts | https://github.com/eth-infinitism/account-abstraction |
| Bundler | https://github.com/eth-infinitism/bundler |
| Bundler Spec Tests | https://github.com/eth-infinitism/bundler-spec-tests |

---

## Resources

- **ERC-4337 Docs**: https://docs.erc4337.io
- **EntryPoint Explainer**: https://docs.erc4337.io/smart-accounts/entrypoint-explainer.html
- **Session Keys**: https://docs.erc4337.io/smart-accounts/session-keys-and-delegation.html
- **Community Discord**: http://discord.gg/fbDyENb6Y9

---

*Last updated: 2026-03-16*
