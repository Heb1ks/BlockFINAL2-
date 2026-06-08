# Architecture & Design Document

**Project:** GameFi Economy Protocol  
**Option:** B — GameFi Economy  
**Team:** Eskender Rymbaev · Nazerke Kaliyeva · Diar Gizatov  
**Version:** 1.0

---

## Table of Contents

1. [System Context (C4 Level 1)](#1-system-context-c4-level-1)
2. [Container / Component Diagram](#2-container--component-diagram)
3. [Sequence Diagrams](#3-sequence-diagrams)
4. [Data Model & Storage Layouts](#4-data-model--storage-layouts)
5. [Trust Assumptions & Access Control](#5-trust-assumptions--access-control)
6. [Design Decisions Log (ADRs)](#6-design-decisions-log-adrs)

---

## 1. System Context (C4 Level 1)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        External Actors                              │
│                                                                     │
│   [Player]          [LP Provider]      [Token Holder / Voter]       │
│   Mints items,      Adds liquidity     Proposes and votes on        │
│   requests loot,    to AMM, earns      governance actions via       │
│   rents NFTs        trading fees       GameDAO                      │
└──────────┬─────────────────┬──────────────────┬────────────────────┘
           │                 │                  │
           ▼                 ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   GameFi Protocol (Arbitrum Sepolia)                │
│                                                                     │
│  ┌────────────┐  ┌──────────┐  ┌───────────┐  ┌─────────────────┐  │
│  │  GameItems │  │ GameAMM  │  │ GameVault │  │ NFTRentalVault  │  │
│  │  (ERC-1155)│  │ (x·y=k)  │  │ (ERC-4626)│  │                 │  │
│  └────────────┘  └──────────┘  └───────────┘  └─────────────────┘  │
│                                                                     │
│  ┌────────────┐  ┌──────────────────────────┐  ┌───────────────┐   │
│  │  LootDrop  │  │  GameDAO + Timelock       │  │  GameFactory  │   │
│  │  (VRF)     │  │  (Governor + 2-day delay) │  │               │   │
│  └────────────┘  └──────────────────────────┘  └───────────────┘   │
└──────┬──────────────────────────────────────────────────────────────┘
       │                        │                         │
       ▼                        ▼                         ▼
┌─────────────┐      ┌──────────────────┐      ┌──────────────────────┐
│  Chainlink  │      │   The Graph      │      │  Arbitrum Sepolia    │
│  VRF v2     │      │   (subgraph)     │      │  L2 infrastructure   │
│  Price Feed │      │   indexes events │      │  ~300x cheaper gas   │
└─────────────┘      └──────────────────┘      └──────────────────────┘
```

**External systems:**
- **Chainlink VRF v2** — provides verifiable randomness for loot drops
- **Chainlink Price Feed** — provides GAME/USD price for vault valuation, with staleness protection
- **The Graph** — indexes protocol events for efficient frontend queries
- **Arbitrum Sepolia** — L2 execution environment; all contracts deployed and verified here

---

## 2. Container / Component Diagram

### 2.1 Contract Relationships

```
                    ┌──────────────────────────────────────────┐
                    │            GameDAO (Governor)             │
                    │  votingDelay=1day  votingPeriod=1week     │
                    │  quorum=4%  proposalThreshold=1%          │
                    └───────────────────┬──────────────────────┘
                                        │ queues actions to
                                        ▼
                    ┌──────────────────────────────────────────┐
                    │         TimelockController               │
                    │         minDelay = 2 days                │
                    │  PROPOSER: GameDAO                       │
                    │  EXECUTOR: address(0) (anyone)           │
                    │  CANCELLER: GameDAO                      │
                    └───┬──────────────┬───────────────────────┘
                        │ owns         │ owns
              ┌─────────▼──┐     ┌─────▼──────────┐
              │  GameToken  │     │   GameItems    │
              │  ERC20Votes │     │   ERC-1155     │
              │  ERC20Permit│     │   UUPS Proxy   │
              └─────────────┘     └───────┬────────┘
                                          │ upgradeable to
                                          ▼
                                  ┌────────────────┐
                                  │  GameItemsV2   │
                                  │  + crafting    │
                                  └────────────────┘

┌─────────────┐    trades     ┌──────────────┐
│  GameAMM    │◄──────────────│   Players    │
│  x·y=k AMM │               └──────────────┘
│  LP: GLP    │                      │ deposits GAME
└─────────────┘                      ▼
                              ┌──────────────┐    price from
                              │  GameVault   │◄──────────── Chainlink
                              │  ERC-4626    │              Price Feed
                              └──────────────┘
                                      ▲
                              yield deposited by
                              ┌──────────────────┐   random words from
                              │  NFTRentalVault  │   ┌──────────────┐
                              │  ERC-1155 rental │   │   LootDrop   │◄── Chainlink VRF
                              └──────────────────┘   └──────────────┘
                                                            │ mints items via
                                                      MINTER_ROLE on GameItems
```

### 2.2 Proxy Layout

```
┌─────────────────────────────────┐
│        ERC1967Proxy             │  ← users interact with this address
│  (slot: EIP-1967 impl slot)     │
│  stores: impl address           │
└────────────────┬────────────────┘
                 │ delegatecall
                 ▼
┌─────────────────────────────────┐        ┌─────────────────────────────┐
│     GameItems (V1 impl)         │  ──────►│     GameItemsV2 (V2 impl)   │
│  - ERC1155Upgradeable           │ upgrade │  - inherits GameItems       │
│  - AccessControlUpgradeable     │  via    │  - adds craftingEnabled     │
│  - UUPSUpgradeable              │ Timelock│  - adds craftingRecipes     │
│  - Initializable                │         │  - adds craft()             │
└─────────────────────────────────┘         └─────────────────────────────┘
```

**Storage is append-only between V1 and V2.** V2 only adds new variables after all V1 slots, making storage collision impossible. See Section 4 for full layout.

### 2.3 Access Control Roles

| Role | Holder | Capabilities |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | TimelockController | Grant/revoke all roles on GameItems |
| `MINTER_ROLE` | LootDrop, TimelockController | Mint ERC-1155 items |
| `UPGRADER_ROLE` | TimelockController | Call `upgradeToAndCall` on GameItems proxy |
| `PROPOSER_ROLE` (Timelock) | GameDAO | Queue operations in Timelock |
| `EXECUTOR_ROLE` (Timelock) | `address(0)` | Anyone can execute after delay |
| `CANCELLER_ROLE` (Timelock) | GameDAO | Cancel queued operations |
| `owner()` | TimelockController | Admin of GameToken, GameVault, NFTRentalVault |

---

## 3. Sequence Diagrams

### 3.1 Player Swap (GameAMM)

```
Player          GameAMM         TokenA          TokenB
  │                │               │               │
  │─approve(amm, amountIn)────────►│               │
  │                │               │               │
  │─swapAtoB(amountIn, minOut)────►│               │
  │                │               │               │
  │           [checks: amountIn > 0]               │
  │                │               │               │
  │                │─safeTransferFrom(player,amm,amountIn)──►│
  │                │               │               │
  │           [calculates amountOut = (amountIn*997*reserveB)
  │                                  / (reserveA*1000 + amountIn*997)]
  │                │               │               │
  │           [checks: amountOut >= minOut]         │
  │                │                               │
  │                │─safeTransfer(player, amountOut)────────►│
  │                │                               │
  │◄─ emit Swap(player, amountIn, amountOut, true) │
  │                │               │               │
```

### 3.2 Governance: Propose → Vote → Queue → Execute

```
TokenHolder     GameDAO         TimelockController    TargetContract
     │              │                   │                  │
     │─delegate(self)                   │                  │
     │              │                   │                  │
     │─propose(targets,values,          │                  │
     │   calldatas,description)─────────►               │
     │              │                   │                  │
     │         [proposalId created]      │                  │
     │         [state = Pending]         │                  │
     │              │                   │                  │
     │   ~~~ vm.warp +1 day ~~~          │                  │
     │         [state = Active]          │                  │
     │              │                   │                  │
     │─castVote(proposalId, 1)──────────►               │
     │              │                   │                  │
     │   ~~~ vm.warp +1 week ~~~         │                  │
     │         [state = Succeeded]       │                  │
     │              │                   │                  │
     │─queue(targets,values,             │                  │
     │   calldatas,descHash)────────────►               │
     │              │──scheduleBatch()──►│                  │
     │         [state = Queued]          │                  │
     │              │                   │                  │
     │   ~~~ vm.warp +2 days ~~~         │                  │
     │              │                   │                  │
     │─execute(targets,values,           │                  │
     │   calldatas,descHash)────────────►               │
     │              │──executeBatch()───►│                  │
     │              │                   │─call()───────────►│
     │         [state = Executed]        │                  │
     │              │                   │                  │
```

### 3.3 NFT Rental Flow

```
Owner        NFTRentalVault      GameItems       GameToken       Renter
  │                │                 │               │              │
  │─setApprovalForAll(vault,true)────►               │              │
  │                │                 │               │              │
  │─listItem(itemId, amount,         │               │              │
  │   pricePerDay)──────────────────►│               │              │
  │                │─safeTransferFrom(owner,vault,itemId,amount)    │
  │                │                 │               │              │
  │           [listing created, active=true]         │              │
  │                │                 │               │              │
  │                │                 │               │◄─approve(vault,cost)
  │                │                 │               │              │
  │                │◄───────────────────────────────rentItem(listingId, days)
  │                │                 │               │              │
  │           [checks: active, not owner, duration ≤ 7 days]       │
  │                │                 │               │              │
  │                │─safeTransferFrom(renter,owner,ownerAmount)─────►
  │                │─safeTransferFrom(renter,vault,fee)─────────────►
  │                │                 │               │              │
  │           [listing.active = false, rental created]              │
  │                │                 │               │              │
  │   ~~~ time passes, rental expires ~~~            │              │
  │                │                 │               │              │
  │                │◄───────────────────────────────endRental(rentalId)
  │           [listing.active = true, rental.active = false]       │
  │                │                 │               │              │
```

---

## 4. Data Model & Storage Layouts

### 4.1 GameItems (UUPS Upgradeable) — Critical: Storage Collision Prevention

Upgradeable contracts use `delegatecall`, so storage layout must be identical between implementations. OpenZeppelin's upgradeable contracts reserve storage using gaps (`uint256[N] __gap`).

```
Slot (approximate)    Variable                         Origin
─────────────────────────────────────────────────────────────────────
[OZ ERC1155 slots]    _balances, _operatorApprovals,   ERC1155Upgradeable
                      _uri
[OZ AccessControl]    _roles                           AccessControlUpgradeable
[OZ UUPS slots]       (implementation slot at          UUPSUpgradeable
                       EIP-1967: 0x360894...)
[OZ Initializable]    _initialized, _initializing      Initializable
─────────────────────────────────────────────────────────────────────
V2 APPENDS:
next free slot        craftingEnabled (bool)           GameItemsV2
next free slot        craftingRecipes (mapping)        GameItemsV2
```

V2 only **appends** new variables — it never reorders or removes V1 variables. Storage collision is impossible.

### 4.2 GameAMM Storage

```solidity
// Inherited from ERC20 (LP token "GLP")
mapping(address => uint256) _balances;
mapping(address => mapping(address => uint256)) _allowances;
uint256 _totalSupply;

// Own state (immutables — not in storage)
IERC20 immutable TOKEN_A;   // stored in bytecode
IERC20 immutable TOKEN_B;   // stored in bytecode

// Constants (not in storage)
uint256 constant FEE = 3;
uint256 constant FEE_DENOMINATOR = 1000;
```

Reserves are read directly from `TOKEN_A.balanceOf(address(this))` — no separate storage variable needed. This eliminates a class of reserve-manipulation bugs.

### 4.3 GameVault Storage

```solidity
// Inherited ERC4626 → ERC20
mapping(address => uint256) _balances;     // sGAME share balances
uint256 _totalSupply;                       // total sGAME shares

// Inherited Ownable
address _owner;

// Own state
AggregatorV3Interface immutable priceFeed;
uint256 stalenessThreshold;
mapping(address => bool) yieldDepositors;
```

### 4.4 NFTRentalVault Storage

```solidity
IERC1155 immutable GAME_ITEMS;
IERC20   immutable GAME_TOKEN;

uint256 platformFee;        // basis points /1000, default 50 = 5%
uint256 listingCount;
uint256 rentalCount;

struct Listing {
    address owner;
    uint256 itemId;
    uint256 amount;
    uint256 pricePerDay;
    bool    active;
}

struct Rental {
    address renter;
    uint256 listingId;
    uint256 startTime;
    uint256 endTime;
    bool    active;
}

mapping(uint256 => Listing) listings;
mapping(uint256 => Rental)  rentals;
```

### 4.5 GameDAO Storage

GameDAO is not upgradeable and inherits entirely from OpenZeppelin Governor. Key governor state:

```solidity
// GovernorSettings
uint256 _votingDelay;    // = 1 days  (86400 seconds, timestamp-based)
uint256 _votingPeriod;   // = 1 weeks (604800 seconds)
uint256 _proposalThreshold; // = 1_000e18 GAME (1% of initial 100k)

// GovernorVotesQuorumFraction
uint256 _quorumNumerator; // = 4 (4%)

// Governor
mapping(uint256 => ProposalCore) _proposals;
// ProposalCore: voteStart, voteEnd, executed, canceled
```

### 4.6 The Graph — Entities

| Entity | Immutable | Key fields |
|---|---|---|
| `TokenTransfer` | yes | from, to, value, blockTimestamp |
| `Swap` | yes | user, amountIn, amountOut, aToB, blockTimestamp |
| `LiquidityEvent` | yes | user, amountA, amountB, shares, type |
| `AMMPool` | no | reserveA, reserveB, totalSupply (updated on each event) |
| `Listing` | no | owner, itemId, pricePerDay, active |
| `Rental` | no | renter, listingId, startTime, endTime, active |
| `Proposal` | no | proposalId, proposer, state |
| `Vote` | yes | voter, proposalId, support, weight |
| `LootRequest` | no | requestId, player, fulfilled, itemId |
| `VaultDeposit` | yes | depositor, assets, shares, blockTimestamp |

---

## 5. Trust Assumptions & Access Control

### 5.1 Who controls what

| Actor | What they control | Risk if compromised |
|---|---|---|
| **TimelockController** | Owns GameToken, GameVault, NFTRentalVault; DEFAULT_ADMIN_ROLE on GameItems | Can mint unlimited tokens, drain vault, change all parameters. However requires 2-day delay — gives time to react. |
| **GameDAO** | PROPOSER_ROLE on Timelock — can queue any action | Cannot execute immediately; Timelock delay enforces 2-day waiting period. |
| **Deployer** (EOA) | Only during deployment; all ownership transferred to Timelock in `_step9_postSetup` | Post-deployment deployer has zero privileged access. |
| **LootDrop** | MINTER_ROLE on GameItems | Can mint arbitrary items. VRF callback is only callable from Chainlink coordinator address. |
| **Chainlink feeds** | Price data consumed by GameVault | A corrupted feed could return stale/manipulated price. Mitigated by staleness check and `answeredInRound >= roundId` check. |

### 5.2 Post-deployment ownership verification

After deployment, `Deploy.s.sol` runs `_runChecks()` which asserts:

```
gameToken.owner()   == address(timelock)   ✓
gameVault.owner()   == address(timelock)   ✓
rentalVault.owner() == address(timelock)   ✓
timelock.getMinDelay() == 2 days           ✓
gameItems.hasRole(DEFAULT_ADMIN_ROLE, timelock) == true  ✓
```

No admin backdoor remains after deployment.

### 5.3 Timelock powers

The Timelock has 2-day mandatory delay on all actions. It can:
- Upgrade GameItems proxy to a new implementation
- Change `stalenessThreshold` in GameVault
- Change `platformFee` in NFTRentalVault
- Mint new GameToken supply (up to MAX_SUPPLY)
- Grant/revoke MINTER_ROLE on GameItems

**What the Timelock cannot do:** bypass the 2-day delay; steal user funds directly (CEI + ReentrancyGuard prevent re-entrancy); the Timelock itself is not upgradeable.

### 5.4 What happens if the multisig is compromised

The protocol has no multisig — governance is fully on-chain via GameDAO. A malicious actor would need to:
1. Acquire ≥ 1% of total supply to submit a proposal
2. Convince ≥ 4% of total supply to vote in favour
3. Wait 1 day (voting delay) + 1 week (voting period) + 2 days (timelock)

Total minimum attack window: **~10 days**, which gives token holders time to exit or counter-vote.

---

## 6. Design Decisions Log (ADRs)

### ADR-01: UUPS vs Transparent Proxy

**Context:** GameItems needs upgradeability for the V2 crafting system.

**Options considered:**
- Transparent Proxy (OpenZeppelin): simpler but ~3,500 extra gas per call due to admin slot check
- UUPS (EIP-1822): upgrade logic in implementation; cheaper per-call; standard in modern OZ

**Decision:** UUPS. The `_authorizeUpgrade` function is gated by `UPGRADER_ROLE` which is held by the Timelock, ensuring upgrades go through governance.

**Consequences:** Implementation must include `_authorizeUpgrade`. If a broken implementation is upgraded, recovery requires governance (2-day delay). V2 storage append-only to prevent collisions.

---

### ADR-02: Timestamp-based Governor clock vs block-number

**Context:** OpenZeppelin Governor v5 supports both block-number and timestamp clocks via EIP-6372.

**Options considered:**
- Block-number (default): L2 block times vary (Arbitrum ~0.25s), so "1 day" in blocks is inconsistent
- Timestamp: deterministic and chain-independent

**Decision:** Timestamp-based clock implemented in `GameToken.clock()` returning `uint48(block.timestamp)`. `CLOCK_MODE()` returns `"mode=timestamp"`. Governor inherits this automatically through `GovernorVotes`.

**Consequences:** `vm.warp` used in tests instead of `vm.roll`. Voting delay (86400) and period (604800) are now human-readable seconds.

---

### ADR-03: AMM reserves from balanceOf vs stored variables

**Context:** AMM needs to know current reserves for swap calculations.

**Options considered:**
- Store `reserveA` and `reserveB` in state variables (Uniswap V2 style): extra SSTORE/SLOAD on every operation
- Read directly from `token.balanceOf(address(this))`: always accurate, no sync needed

**Decision:** `balanceOf` approach. The protocol controls all token inflows (only via `safeTransferFrom` in `addLiquidity`/`swapAtoB`/`swapBtoA`), so balance = reserves at all times.

**Consequences:** Eliminates a class of reserve-desync bugs. Slightly higher SLOAD cost per swap but no SSTORE for reserve update.

---

### ADR-04: ERC-4626 for yield vault vs custom vault

**Context:** GameVault needs to hold GAME tokens and distribute yield to depositors.

**Options considered:**
- Custom vault: more control but re-implements share math
- ERC-4626 standard: audited share math, composable with other protocols

**Decision:** ERC-4626 via OpenZeppelin. Share price automatically increases as `depositYield` adds tokens to `totalAssets()` without minting new shares. Passes all ERC-4626 rounding invariants (tested in `VaultInvariantTest`).

**Consequences:** Vault is composable with any ERC-4626-aware aggregator. The inflation attack is mitigated by OZ's built-in virtual shares offset.

---

### ADR-05: Factory with both CREATE and CREATE2

**Context:** Protocol needs to deploy multiple GameItems and GameAMM instances.

**Options considered:**
- Always CREATE: simpler but non-deterministic addresses
- Always CREATE2: deterministic but requires managing salts
- Both: CREATE for regular deployment, CREATE2 for cases where address must be known in advance

**Decision:** Both in `GameFactory`. `deployGameItems()` uses CREATE; `deployGameItemsWithSalt()` uses CREATE2. `predictGameItemsAddress(salt)` lets off-chain tooling predict the proxy address before deployment.

**Consequences:** Slightly more complex factory but covers both use cases. CREATE2 deployment allows frontend/subgraph to be pre-configured before actual deployment.

---

### ADR-06: Chainlink staleness check implementation

**Context:** Price feeds can become stale if Chainlink nodes are offline. Using a stale price is a critical vulnerability.

**Options considered:**
- Single check: `block.timestamp - updatedAt > threshold`
- Double check: above + `answeredInRound >= roundId`

**Decision:** Both checks. `answeredInRound < roundId` means the oracle returned data from an older round — a separate class of staleness not caught by the timestamp check alone.

**Consequences:** More robust oracle safety. `stalenessThreshold` is configurable by governance (default 3600 seconds).

---

### ADR-07: Pull-over-push for rental payments

**Context:** NFTRentalVault collects platform fees. Options: push to owner immediately, or accumulate and let owner pull.

**Options considered:**
- Push (send to owner on every rental): simpler but owner could be a contract that reverts, blocking rentals
- Pull (accumulate in vault, owner calls `withdrawFees`): safe, owner controls timing

**Decision:** Pull. `withdrawFees()` transfers full balance to `owner()`. This is the standard pull-over-push pattern which eliminates DoS via reverting recipient.

**Consequences:** Owner must call `withdrawFees` manually. Fees sit in contract until claimed — no yield on accumulated fees (acceptable for a GameFi protocol).