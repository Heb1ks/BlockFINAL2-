// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/interfaces/AggregatorV3Interface.sol";
import "../src/GameVault.sol";
import "../src/GameToken.sol";
import "../src/mocks/MockV3Aggregator.sol";

/// @notice Fork tests require an RPC URL set as env var:
///         MAINNET_RPC_URL or ARBITRUM_SEPOLIA_RPC_URL
///
///         Run with:
///           forge test --match-path test/Fork.t.sol \
///             --fork-url $MAINNET_RPC_URL -vvv
///
///         Or configure in foundry.toml:
///           [rpc_endpoints]
///           mainnet = "${MAINNET_RPC_URL}"
///           arbitrum_sepolia = "${ARBITRUM_SEPOLIA_RPC_URL}"
contract ForkTest is Test {
    // ─── Mainnet addresses ────────────────────────────────────────────────────
    address constant CHAINLINK_ETH_USD    = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CHAINLINK_USDC_USD   = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant USDC_MAINNET         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_WHALE           = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;
    address constant UNISWAP_V2_ROUTER    = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant WETH_MAINNET         = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // ─── Fork 1: Chainlink ETH/USD price feed ─────────────────────────────────

    function test_fork_chainlinkEthUsd_validPrice() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20_000_000);

        AggregatorV3Interface feed = AggregatorV3Interface(CHAINLINK_ETH_USD);
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Sanity: ETH/USD > $500 and < $100,000
        assertGt(price, 500e8,     "ETH price too low");
        assertLt(price, 100_000e8, "ETH price too high");
        // Data freshness: answered in the latest round
        assertGe(answeredInRound, roundId);
        assertGt(updatedAt, 0);
    }

    // ─── Fork 2: Chainlink USDC/USD ≈ $1 ─────────────────────────────────────

    function test_fork_chainlinkUsdcUsd_pegged() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20_000_000);

        AggregatorV3Interface feed = AggregatorV3Interface(CHAINLINK_USDC_USD);
        (, int256 price, , , ) = feed.latestRoundData();

        // USDC/USD should be within 1% of $1.00 (= 1e8 with 8 decimals)
        assertGt(price, 0.99e8, "USDC depegged below $0.99");
        assertLt(price, 1.01e8, "USDC depegged above $1.01");
    }

    // ─── Fork 3: USDC real balance via impersonation ──────────────────────────

    function test_fork_usdcWhaleBalance() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 20_000_000);

        IERC20 usdc = IERC20(USDC_MAINNET);
        uint256 balance = usdc.balanceOf(USDC_WHALE);

        // Known whale should have substantial USDC
        assertGt(balance, 1_000_000e6, "whale balance too low");
    }

    // ─── (Optional) Arbitrum Sepolia fork for deployment verification ──────────

    // Uncomment if ARBITRUM_SEPOLIA_RPC_URL is set
    //
    // function test_fork_arbitrumSepolia_deploy() public {
    //     vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC_URL"));
    //     // Verify our deployed contracts exist on testnet
    //     // Replace with actual deployed addresses from deploy output
    //     address gameToken = 0x0000000000000000000000000000000000000000;
    //     assertTrue(gameToken.code.length > 0, "GameToken not deployed");
    // }
}
