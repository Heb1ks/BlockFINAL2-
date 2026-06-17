# GameFi Protocol — Option B: GameFi Economy

A production-grade decentralized GameFi infrastructure built on Arbitrum Sepolia.  
This protocol provides the complete on-chain economic layer for a blockchain game:
in-game currency, NFT items, a decentralized exchange, NFT rental, random loot drops,
yield vaults, and DAO governance — all deployed and verified on L2.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [Deployed Addresses](#deployed-addresses)
- [Technical Requirements](#technical-requirements)
- [Getting Started](#getting-started)
- [Running Tests](#running-tests)
- [Deployment](#deployment)
- [Security](#security)

---

## Overview

GameFi Protocol is a full-stack decentralized protocol that implements the economic
backbone of a blockchain game. Players can:

- **Trade** in-game resources on a decentralized AMM exchange
- **Rent** NFT items from other players and earn passive income
- **Earn yield** by staking the governance token in the ERC-4626 vault
- **Receive random loot drops** powered by Chainlink VRF
- **Govern** the protocol — vote on drop rates, crafting costs, and economic parameters

The protocol is governed by a DAO where token holders vote on all parameter changes.
All admin power is controlled by a 2-day Timelock, eliminating single points of failure.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GameFi Protocol                          │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │  GameToken   │    │  GameItems   │    │    GameVault     │   │
│  │  ERC20Votes  │    │  ERC-1155    │    │    ERC-4626      │   │
│  │  ERC20Permit │    │  UUPS Proxy  │    │  Chainlink Feed  │   │
│  └──────┬───────┘    └──────┬───────┘    └────────┬─────────┘   │
│         │                  │                      │             │
│  ┌──────▼───────┐    ┌──────▼───────┐    ┌────────▼─────────┐   │
│  │   GameDAO    │    │  NFTRental   │    │     GameAMM      │   │
│  │  Governor    │    │    Vault     │    │   x*y=k + Yul    │   │
│  │  Timelock    │    │              │    │    LP tokens     │   │
│  └──────────────┘    └──────────────┘    └──────────────────┘   │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐                           │
│  │  LootDrop    │    │ GameFactory  │                           │
│  │ Chainlink VRF│    │CREATE+CREATE2│                           │
│  └──────────────┘    └──────────────┘                           │
│                                                                 │
│  External: Chainlink VRF · Chainlink Price Feed · The Graph     │
│  Network:  Arbitrum Sepolia (L2)                                │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

- **UUPS Proxy** on GameItems enables upgrades without redeploying (V1 → V2 with crafting)
- **Inline Yul assembly** in GameAMM for `_sqrtYul` (~26% gas saving) and `_getAmountOutYul` (~18% saving)
- **ERC-4626 vault** collects protocol fees from NFTRentalVault and distributes yield to stakers
- **2-day Timelock** controls all admin functions — no instant changes possible
- **Chainlink VRF** ensures provably fair loot drops (cannot be manipulated)
- **Chainlink Price Feed** with staleness check in GameVault for USD valuation

---

## Contracts

| Contract | Description | Standard |
|---|---|---|
| `GameToken` | In-game currency and governance token | ERC-20 + ERC20Votes + ERC20Permit |
| `GameItems` | In-game NFT items (Sword, Shield, Potion, Armor, Magic Orb) | ERC-1155 + UUPS |
| `GameItemsV2` | Upgraded version with on-chain crafting system | ERC-1155 + UUPS |
| `GameAMM` | Constant-product AMM (x·y=k) with 0.3% fee and LP tokens | Custom + Yul |
| `GameVault` | Yield vault for GAME stakers; fees from rental flow here | ERC-4626 |
| `NFTRentalVault` | List, rent, and return NFT items; platform fees → GameVault | Custom |
| `LootDrop` | Request random loot via Chainlink VRF; 50% drop rate by default | VRFConsumerBaseV2 |
| `GameDAO` | On-chain governance: propose, vote, queue, execute | OZ Governor |
| `TimelockController` | 2-day delay on all governance actions | OZ Timelock |
| `GameFactory` | Deploys GameItems and GameAMM instances via CREATE and CREATE2 | Custom |

---

## Deployed Addresses

**Network: Arbitrum Sepolia (Chain ID: 421614)**

| Contract | Address |
|---|---|
| GameToken | [`0x4b733e9e1328F5b7FE865cA87cb073f98A12195f`](https://sepolia.arbiscan.io/address/0x4b733e9e1328F5b7FE865cA87cb073f98A12195f) |
| GameItems (proxy) | [`0xE0fEE3E2080787500889c75dEAaB13863D521C67`](https://sepolia.arbiscan.io/address/0xE0fEE3E2080787500889c75dEAaB13863D521C67) |
| GameItems (impl) | [`0xAe867dF3d109e54FC5E56b5a89661F353CcC9C46`](https://sepolia.arbiscan.io/address/0xAe867dF3d109e54FC5E56b5a89661F353CcC9C46) |
| GameFactory | [`0x4B3b639da23fd9765A106E45a02f6C4F9C86d9fF`](https://sepolia.arbiscan.io/address/0x4B3b639da23fd9765A106E45a02f6C4F9C86d9fF) |
| TimelockController | [`0x7972D6A33163C5299DDC8cD70E3Bf27bc066ad02`](https://sepolia.arbiscan.io/address/0x7972D6A33163C5299DDC8cD70E3Bf27bc066ad02) |
| GameDAO | [`0x27344475649463373e1205A122E33536c34AF8cD`](https://sepolia.arbiscan.io/address/0x27344475649463373e1205A122E33536c34AF8cD) |
| GameAMM | [`0x36E6D1a755c9b81c24C138f4c3FbaCeBe2AbEdB5`](https://sepolia.arbiscan.io/address/0x36E6D1a755c9b81c24C138f4c3FbaCeBe2AbEdB5) |
| GameVault | [`0x642F030B5aB0a6d8Bcf6700f328bbD82DD8F821f`](https://sepolia.arbiscan.io/address/0x642F030B5aB0a6d8Bcf6700f328bbD82DD8F821f) |
| NFTRentalVault | [`0x3A05363578B06a92fCFa7A2C8C57684f72F89B5c`](https://sepolia.arbiscan.io/address/0x3A05363578B06a92fCFa7A2C8C57684f72F89B5c) |
| LootDrop | [`0x38Fd68F4b1DF77937a05F268952f885Bf73dE97E`](https://sepolia.arbiscan.io/address/0x38Fd68F4b1DF77937a05F268952f885Bf73dE97E) |

All contracts are **verified** on [Arbiscan](https://sepolia.arbiscan.io).

---

## Technical Requirements

### Smart Contracts 
- **UUPS Proxy** — GameItems with documented V1 → V2 upgrade path (crafting system)
- **Factory** — GameFactory using both `CREATE` and `CREATE2` with address prediction
- **Inline Yul Assembly** — GameAMM `_sqrtYul` (26% cheaper) and `_getAmountOutYul` (18% cheaper)
- **ERC-20** — GameToken with ERC20Votes + ERC20Permit
- **ERC-1155** — GameItems (upgradeable)
- **ERC-4626** — GameVault with full rounding invariant compliance
- **AMM** — Constant-product x·y=k with 0.3% fee, slippage protection, LP tokens (built from scratch)
- **Chainlink Price Feed** — GameVault with staleness check (reverts if price older than 1 hour)
- **Chainlink VRF** — LootDrop with mock coordinator for tests
- **Governance** — Full OZ Governor stack: 1-day delay, 1-week period, 4% quorum, 1% threshold
- **Timelock** — 2-day delay, controls treasury and all admin functions
- **L2 Deployment** — Arbitrum Sepolia with gas comparison table

### Testing 

| Type | Count | Requirement |
|---|---|---|
| Unit | 90+ | ≥ 50 |
| Fuzz | 11 | ≥ 10 |
| Invariant | 5 | ≥ 5 |
| Fork | 3 | ≥ 3 |
| **Total** | **109+** | **≥ 80** |

### Security 
- Checks-Effects-Interactions pattern throughout
- ReentrancyGuard on all state-changing vault functions
- OpenZeppelin AccessControl on GameItems; Ownable on all other admin contracts
- SafeERC20 for all ERC-20 interactions
- No `tx.origin`, no `block.timestamp` randomness, no `transfer`/`send`
- Slither: zero High, zero Medium findings

### Design Patterns Used 
1. **Factory** — GameFactory (CREATE + CREATE2)
2. **Proxy / UUPS** — GameItems V1 → V2
3. **Checks-Effects-Interactions** — all swap/deposit/rental functions
4. **Access Control / Role-based** — GameItems (MINTER_ROLE, UPGRADER_ROLE)
5. **Timelock** — 2-day governance delay
6. **Reentrancy Guard** — GameVault, GameAMM, NFTRentalVault
7. **Oracle Adapter** — Chainlink price feed abstraction in GameVault
8. **Pull-over-push** — NFTRentalVault fee withdrawal

---

## Getting Started

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify installation
forge --version
```

### Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO

# Install dependencies
forge install

# Build
forge build
```

### Environment Setup

Create a `.env` file in the project root:

```env
DEPLOYER_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
ARBITRUM_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/YOUR_KEY
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
ARBISCAN_API_KEY=YOUR_ARBISCAN_KEY
VRF_COORDINATOR=0x50d47e4142598E3411aA864e08a44284e471AC6f
VRF_KEY_HASH=0x027f94ff1465b3525f9fc03e9ff7d6d2c0953482246dd6ae07570c45d6631414
VRF_SUBSCRIPTION_ID=YOUR_SUBSCRIPTION_ID
```


---

## Running Tests

```bash
# All tests (excluding fork)
forge test -vv

# Specific file
forge test --match-path test/GameAMM.t.sol -vv

# Fuzz tests only
forge test --match-test "testFuzz" -vv

# Invariant tests only
forge test --match-test "invariant_" -vv

# Fork tests (requires MAINNET_RPC_URL)
source .env
forge test --match-path test/Fork.t.sol --fork-url $MAINNET_RPC_URL -vvv

# Coverage report
forge coverage --report summary
```

---

## Deployment

```bash
# Deploy to Arbitrum Sepolia (PowerShell)
.\deploy.ps1

# Or manually
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvvv
```

The deploy script:
1. Deploys all contracts in the correct order
2. Wires roles and permissions
3. Transfers all ownership to the Timelock
4. Runs post-deployment sanity checks automatically

### After Deployment

Add LootDrop as a VRF consumer:
1. Go to https://vrf.chain.link/arbitrum-sepolia
2. Find your subscription → "Add consumer"
3. Paste the LootDrop address

---

## Gas Comparison — L1 vs L2

| Operation | Ethereum Mainnet (est.) | Arbitrum Sepolia | Saving |
|---|---|---|---|
| GameToken deploy | ~1,200,000 gas | ~1,200,000 gas | ~10x cheaper (L2 pricing) |
| addLiquidity (initial) | ~180,000 gas | ~180,000 gas | ~10x cheaper |
| swapAtoB | ~85,000 gas | ~85,000 gas | ~10x cheaper |
| deposit (ERC-4626) | ~95,000 gas | ~95,000 gas | ~10x cheaper |
| listItem (rental) | ~110,000 gas | ~110,000 gas | ~10x cheaper |
| propose (DAO) | ~200,000 gas | ~200,000 gas | ~10x cheaper |

*Arbitrum Sepolia executes the same gas units but ETH cost is ~10x lower due to L2 fee structure.*

### Yul Assembly Benchmark (GameAMM)

| Function | Solidity | Yul | Gas Saving |
|---|---|---|---|
| `_sqrt` | ~230 gas | ~170 gas | **26%** |
| `_getAmountOut` | ~115 gas | ~95 gas | **18%** |

---

## Security

### Access Control

| Role | Holder | Powers |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Timelock | Grant/revoke roles on GameItems |
| `MINTER_ROLE` | LootDrop, Timelock | Mint new GameItems |
| `UPGRADER_ROLE` | Timelock | Upgrade GameItems implementation |
| `owner()` | Timelock | Admin functions on GameToken, GameVault, NFTRentalVault |
| Governor | GameDAO | Create proposals, control Timelock |

### Timelock Powers
- Mint new GAME tokens
- Change drop rates and crafting costs
- Upgrade GameItems contract
- Change platform fees
- Onboard new asset types

### What Cannot Happen
- No instant parameter changes (2-day delay enforced on-chain)
- No unilateral minting (requires governance vote + timelock)
- No reentrancy (ReentrancyGuard on all vault functions)
- No stale price usage (Chainlink staleness check, reverts if >1 hour old)

---

## Project Structure

```
├── src/
│   ├── GameToken.sol          # ERC-20 governance token
│   ├── GameItems.sol          # ERC-1155 NFT items (UUPS V1)
│   ├── GameItemsV2.sol        # UUPS V2 with crafting
│   ├── GameAMM.sol            # Constant-product AMM + Yul
│   ├── GameVault.sol          # ERC-4626 yield vault
│   ├── GameDAO.sol            # OZ Governor + Timelock
│   ├── GameFactory.sol        # CREATE + CREATE2 factory
│   ├── NFTRentalVault.sol     # NFT rental marketplace
│   ├── LootDrop.sol           # Chainlink VRF loot drops
│   └── mocks/                 # Test mocks (not deployed)
├── test/
│   ├── GameToken.t.sol        # 16 tests
│   ├── GameItems.t.sol        # 16 tests
│   ├── GameAMM.t.sol          # 24 tests + invariants
│   ├── GameVault.t.sol        # 24 tests + invariants
│   ├── NFTRentalVault.t.sol   # 18 tests
│   ├── GameDAO.t.sol          # 11 tests
│   ├── GameFactory.t.sol      # 9 tests
│   ├── LootDrop.t.sol         # 10 tests
│   └── Fork.t.sol             # 3 mainnet fork tests
├── script/
│   └── Deploy.s.sol           # Idempotent deploy script
├── foundry.toml
├── deploy.ps1                 # PowerShell deploy helper
└── verify.ps1                 # PowerShell verification helper
```
