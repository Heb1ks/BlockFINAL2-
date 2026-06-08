# Gas Optimization Report

## Environment

- Solidity 0.8.34, Foundry (nightly)
- Test command: `forge test --gas-report --no-match-contract "Invariant"`
- L1 gas price assumed: 30 gwei | L2 (Arbitrum Sepolia) gas price: 0.1 gwei
- ETH price assumed: $3,000
- Formula: `gas × gwei × 1e-9 × ETH_price`

---

## 1. Yul vs Solidity Benchmark (GameAMM)

Both paths are exposed as public functions and verified identical by `testFuzz_yulMatchesSolidity` (256 runs).

| Function | Solidity (gas) | Yul (gas) | Saving |
|---|---|---|---|
| `getAmountOutSolidity` | 736 | 568 | **22.8%** |
| `_sqrtYul` vs `_sqrt` (documented) | ~230 | ~170 | **26%** |

Source: `src/GameAMM.sol` inline benchmarks + `forge test --gas-report` output above.

---

## 2. L1 vs L2 Gas Comparison (≥ 6 operations)

Gas units taken from `avg` column of `forge test --gas-report`.

| Operation | Contract | Gas (avg) | L1 cost @ 30 gwei | L2 cost @ 0.1 gwei | Saving |
|---|---|---|---|---|---|
| `swapAtoB` | GameAMM | 59,969 | $5.40 | $0.018 | 99.7% |
| `addLiquidity` | GameAMM | 134,868 | $12.14 | $0.040 | 99.7% |
| `deposit` | GameVault | 112,031 | $10.08 | $0.034 | 99.7% |
| `propose` | GameDAO | 69,700 | $6.27 | $0.021 | 99.7% |
| `castVote` | GameDAO | 77,340 | $6.96 | $0.023 | 99.7% |
| `listItem` | NFTRentalVault | 202,314 | $18.21 | $0.061 | 99.7% |
| `rentItem` | NFTRentalVault | 194,561 | $17.51 | $0.058 | 99.7% |
| `requestLoot` | LootDrop | 76,204 | $6.86 | $0.023 | 99.7% |

> Arbitrum processes the same EVM opcodes but amortises L1 calldata cost across many transactions,
> resulting in ~300–1000x lower effective gas price for users.

---

## 3. Deployment Costs

| Contract | Deployment Gas | L1 cost @ 30 gwei | L2 cost @ 0.1 gwei |
|---|---|---|---|
| GameDAO | 3,480,790 | $313.27 | $1.044 |
| GameFactory | 3,893,923 | $350.45 | $1.168 |
| GameItems (impl) | 1,946,082 | $175.15 | $0.584 |
| GameItemsV2 (impl) | 2,263,460 | $203.71 | $0.679 |
| GameToken | 1,892,789 | $170.35 | $0.568 |
| GameAMM | 1,272,038 | $114.48 | $0.382 |
| GameVault | 1,369,109 | $123.22 | $0.411 |
| NFTRentalVault | 1,033,867 | $93.05 | $0.310 |
| LootDrop | 566,369 | $50.97 | $0.170 |
| TimelockController | 1,326,170 | $119.36 | $0.398 |
| ERC1967Proxy | 283,417 | $25.51 | $0.085 |

---

## 4. Full `forge test --gas-report` Output

### GameAMM

| Function | Min | Avg | Median | Max | Calls |
|---|---|---|---|---|---|
| addLiquidity | 27,080 | 134,868 | 149,748 | 149,886 | 1,046 |
| getAmountOutSolidity | 736 | 736 | 736 | 736 | 258 |
| getAmountOutYul | 568 | 568 | 568 | 568 | 258 |
| getReserves | 11,057 | 11,057 | 11,057 | 11,057 | 1,031 |
| removeLiquidity | 26,814 | 46,508 | 44,064 | 71,089 | 4 |
| swapAtoB | 27,138 | 59,969 | 60,115 | 61,748 | 262 |
| swapBtoA | 26,874 | 59,691 | 59,850 | 61,483 | 260 |

### GameDAO

| Function | Min | Avg | Median | Max | Calls |
|---|---|---|---|---|---|
| castVote | 65,940 | 77,340 | 83,040 | 83,040 | 3 |
| execute | 131,926 | 131,926 | 131,926 | 131,926 | 1 |
| propose | 38,890 | 69,700 | 75,862 | 75,862 | 6 |
| queue | 144,495 | 144,495 | 144,495 | 144,495 | 1 |
| state | 2,792 | 17,053 | 14,650 | 36,825 | 6 |
| votingDelay | 2,486 | 2,486 | 2,486 | 2,486 | 1 |
| votingPeriod | 2,294 | 2,294 | 2,294 | 2,294 | 1 |

### GameVault

| Function | Min | Avg | Median | Max | Calls |
|---|---|---|---|---|---|
| deposit | 51,187 | 112,031 | 112,205 | 113,771 | 526 |
| depositYield | 31,275 | 54,550 | 58,744 | 69,437 | 4 |
| getLatestPrice | 10,393 | 11,491 | 11,480 | 12,613 | 4 |
| mint | 79,790 | 79,790 | 79,790 | 79,790 | 1 |
| redeem | 51,484 | 51,532 | 51,541 | 51,551 | 258 |
| totalValueUSD | 18,004 | 18,004 | 18,004 | 18,004 | 1 |
| withdraw | 52,885 | 58,095 | 58,095 | 63,306 | 2 |

### NFTRentalVault

| Function | Min | Avg | Median | Max | Calls |
|---|---|---|---|---|---|
| delistItem | 28,790 | 39,498 | 39,498 | 50,206 | 2 |
| endRental | 28,980 | 40,978 | 41,512 | 51,908 | 4 |
| listItem | 27,256 | 202,314 | 204,510 | 204,510 | 271 |
| rentItem | 26,963 | 194,561 | 197,085 | 197,085 | 267 |
| setPlatformFee | 23,691 | 26,147 | 26,147 | 28,603 | 2 |
| withdrawFees | 40,217 | 40,217 | 40,217 | 40,217 | 1 |

### GameToken

| Function | Min | Avg | Median | Max | Calls |
|---|---|---|---|---|---|
| approve | 26,459 | 31,749 | 28,983 | 46,359 | 615 |
| delegate | 95,345 | 95,434 | 95,357 | 95,573 | 553 |
| mint | 23,975 | 60,547 | 48,884 | 88,600 | 1,401 |
| permit | 74,491 | 74,491 | 74,491 | 74,491 | 1 |
| transfer | 56,068 | 59,471 | 56,296 | 66,051 | 3 |

### GameItems

| Function | Min | Avg | Median | Max | Calls |
|---|---|---|---|---|---|
| initialize | 3,111 | 162,249 | 165,635 | 165,635 | 48 |
| mint | 2,551 | 28,086 | 28,205 | 28,205 | 433 |
| mintBatch | 3,930 | 40,736 | 40,736 | 77,542 | 2 |
| safeTransferFrom | 15,433 | 36,747 | 36,842 | 36,842 | 271 |
| upgradeToAndCall | 3,340 | 8,608 | 11,243 | 11,243 | 3 |

### LootDrop

| Function | Min | Avg | Median | Max | Calls |
|---|---|---|---|---|---|
| requestLoot | 76,204 | 76,204 | 76,204 | 76,204 | 262 |
| setDropRate | 23,853 | 28,642 | 28,874 | 28,874 | 261 |