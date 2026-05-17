# GameFi Economy Protocol

Blockchain Technologies 2 — Final Project (Option B)

A full-stack decentralized GameFi protocol featuring an ERC-1155 in-game item economy with crafting, a constant-product AMM for fungible resources, an NFT rental vault, Chainlink VRF loot drops, and DAO governance — deployed on Arbitrum Sepolia.

## Team

| Name | Area of ownership |
|---|---|
| Eskender Rymbaev | Frontend, subgraph, deployment & DevOps |
| Nazerke Kaliyeva | Governance (GameDAO, GameToken), security audit |
| Diar Gizatov | Smart contracts (GameAMM, GameVault, GameFactory), testing|

---

## Deployed Contracts — Arbitrum Sepolia

| Contract | Address |
|---|---|
| GameToken (ERC-20 / governance) | [0x407a5Da64E3fc9FF202b76355d0FC0F34390c41A](https://sepolia.arbiscan.io/address/0x407a5Da64E3fc9FF202b76355d0FC0F34390c41A) |
| GameItems proxy (ERC-1155 UUPS) | [0xd38cA79ADFc7300A95adaAc16A5F543c205eBf64](https://sepolia.arbiscan.io/address/0xd38cA79ADFc7300A95adaAc16A5F543c205eBf64) |
| GameFactory | [0x545901c94Ce4bCB7960CeCB69C8b3C505Fcdd836](https://sepolia.arbiscan.io/address/0x545901c94Ce4bCB7960CeCB69C8b3C505Fcdd836) |
| TimelockController (2-day delay) | [0x1ABA8B2a61196EDDd50C4456733D63Ff5f6139e0](https://sepolia.arbiscan.io/address/0x1ABA8B2a61196EDDd50C4456733D63Ff5f6139e0) |
| GameDAO (Governor) | [0xCb0aD118Fc15313305d138097A2E6AE21706A59C](https://sepolia.arbiscan.io/address/0xCb0aD118Fc15313305d138097A2E6AE21706A59C) |
| GameAMM (x·y=k, 0.3% fee) | [0xFf494842f23dbad3b478CDe35486e101cD880AF9](https://sepolia.arbiscan.io/address/0xFf494842f23dbad3b478CDe35486e101cD880AF9) |
| GameVault (ERC-4626) | [0xCB082d44E32f27D30C54c28F947A8C54fDFb6de8](https://sepolia.arbiscan.io/address/0xCB082d44E32f27D30C54c28F947A8C54fDFb6de8) |
| NFTRentalVault | [0x476016df3bE27D697aB1494922Ac5352B936BcbF](https://sepolia.arbiscan.io/address/0x476016df3bE27D697aB1494922Ac5352B936BcbF) |
| LootDrop (Chainlink VRF) | [0xD1d24f55107c7ee9FDE319502d8Bca9fe1bB288c](https://sepolia.arbiscan.io/address/0xD1d24f55107c7ee9FDE319502d8Bca9fe1bB288c) |

---

## The Graph Subgraph

- **Endpoint (HTTP):** `https://api.studio.thegraph.com/query/1753408/gamefi-protocol/v0.0.5`
- **Entities:** TokenTransfer, Swap, LiquidityEvent, AMMPool, Listing, Rental, Proposal, Vote, LootRequest, VaultDeposit
- **Documented queries:** `subgraph/queries.graphql`

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Frontend (app.js)                 │
│          MetaMask · Ethers.js · The Graph            │
└──────────┬──────────────────────────────────────────┘
           │
┌──────────▼──────────────────────────────────────────┐
│                 Arbitrum Sepolia L2                  │
│                                                      │
│  GameToken (ERC20Votes+Permit)                       │
│       │                                              │
│  GameDAO ──► TimelockController                      │
│       │           │ controls                         │
│  GameFactory      ▼                                  │
│  ├── GameItems (UUPS proxy, ERC-1155)                │
│  │       └── GameItemsV2 (+ crafting)                │
│  └── GameAMM (x·y=k, LP tokens)                     │
│                                                      │
│  GameVault (ERC-4626) ◄── Chainlink price feed       │
│  NFTRentalVault (ERC-1155 rentals)                   │
│  LootDrop ◄── Chainlink VRF                          │
└─────────────────────────────────────────────────────┘
           │
┌──────────▼──────────────────────────────────────────┐
│              The Graph (subgraph)                    │
│   indexes: Swap, Proposal, Listing, LootRequest…    │
└─────────────────────────────────────────────────────┘
```

---

## Protocol Overview

### Option B — GameFi Economy

| Component | Description |
|---|---|
| **GameItems** | Upgradeable ERC-1155 with MINTER_ROLE gating. V2 adds on-chain crafting (burn inputs → mint output). |
| **GameAMM** | Constant-product AMM (x·y=k) for fungible game resources. 0.3% fee, slippage protection, LP tokens. Contains inline Yul assembly (~22–26% gas saving over Solidity equivalent). |
| **GameVault** | ERC-4626 tokenized yield vault. Depositors earn yield from protocol fees. Chainlink price feed with staleness check provides USD valuation. |
| **NFTRentalVault** | List ERC-1155 items for rent. Renter pays GAME tokens per day; platform takes 5% fee. |
| **LootDrop** | Chainlink VRF v2 loot drops. Drop rate is DAO-governed. |
| **GameToken** | ERC20Votes + ERC20Permit. Governance token. Timestamp-based clock (EIP-6372). |
| **GameDAO** | Full OpenZeppelin Governor stack. Voting delay 1 day, voting period 1 week, quorum 4%, proposal threshold 1%. |
| **TimelockController** | 2-day delay. Controls treasury and privileged protocol parameters. |
| **GameFactory** | Deploys GameItems (CREATE) and GameAMM (CREATE) instances. Supports deterministic deployment via CREATE2 with salt. |

---

## Getting Started

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build

```bash
forge build
```

### Test

```bash
# Full test suite (unit + fuzz + fork)
forge test

# With gas report
forge test --gas-report --no-match-contract "Invariant"

# Invariant tests (slow — ~60s)
forge test --match-contract "Invariant"

# Coverage
forge coverage --report lcov
```

### Deploy

```bash
# Copy and fill in your keys
cp .env.example .env

# Deploy to Arbitrum Sepolia
forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast --verify \
  --etherscan-api-key $ARBISCAN_API_KEY -vvvv
```

Required environment variables:

```
DEPLOYER_PRIVATE_KEY=
ARBITRUM_SEPOLIA_RPC_URL=
ARBISCAN_API_KEY=
MAINNET_RPC_URL=          # for fork tests
VRF_COORDINATOR=          # optional, uses mock if not set
VRF_KEY_HASH=
VRF_SUBSCRIPTION_ID=
PRICE_FEED_ADDRESS=       # optional, uses mock if not set
```

### Frontend

Open `frontend/index.html` in a browser with MetaMask installed and connected to Arbitrum Sepolia (Chain ID: 421614).

---

## Test Suite Summary

| Category | Count | Requirement |
|---|---|---|
| Unit tests | 110+ | ≥ 50 |
| Fuzz tests | 16 | ≥ 10 |
| Invariant tests | 5 | ≥ 5 |
| Fork tests | 3 | ≥ 3 |
| **Total** | **133** | **≥ 80** |

All tests pass. See `coverage-report.md` for line coverage (≥ 90%).

---

## Security

- ReentrancyGuard on all state-changing external functions
- SafeERC20 for all ERC-20 interactions
- Chainlink staleness check (reverts if price older than threshold)
- No `tx.origin` authorization, no `transfer`/`send`, no `block.timestamp` randomness
- Slither: zero High, zero Medium findings at submission (see `audit-report.pdf`)

See `audit-report.md` for the full internal security audit.

---

## Documentation

| Document | Location |
|---|---|
| Architecture & design | `docs/architecture.md` |
| Security audit report | `docs/audit-report.md` |
| Gas optimization report | `gas-report.md` |
| Coverage report | `coverage-report.md` |
| GraphQL queries | `subgraph/queries.graphql` |

---

## Design Patterns Used

1. **UUPS Proxy** — GameItems upgradeable V1 → V2
2. **Factory** — GameFactory deploys items and AMMs via CREATE / CREATE2
3. **Checks-Effects-Interactions** — all state-changing functions
4. **Reentrancy Guard** — GameAMM, GameVault, NFTRentalVault
5. **Access Control / Role-based permissions** — MINTER_ROLE, UPGRADER_ROLE
6. **Oracle adapter** — AggregatorV3Interface abstraction with staleness check
7. **Timelock** — 2-day delay on all governance-executed actions

---

## Gas Report

See [gas-report.md](report/gas-report.mdrt.md) for full L1 vs L2 comparison and Yul optimization benchmarks.

Key highlight: operations cost **~300x less** on Arbitrum Sepolia vs Ethereum Mainnet (e.g. `swapAtoB`: $5.40 L1 → $0.018 L2).