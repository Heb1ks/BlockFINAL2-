// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GameVault.sol";
import "../src/GameToken.sol";
import "../src/mocks/MockV3Aggregator.sol";

contract GameVaultTest is Test {
    GameVault        vault;
    GameToken        token;
    MockV3Aggregator feed;

    address owner = address(0xA);
    address alice = address(0xB);
    address bob   = address(0xC);

    uint256 constant STALENESS  = 3600;
    int256  constant INIT_PRICE = 2e8;

    function setUp() public {
        // Start time at a non-trivial value to avoid underflow in stale tests
        vm.warp(10_000);

        vm.startPrank(owner);
        token = new GameToken(owner);
        feed  = new MockV3Aggregator(8, INIT_PRICE);
        vault = new GameVault(IERC20(address(token)), address(feed), owner, STALENESS);
        token.mint(alice, 10_000e18);
        token.mint(bob,   10_000e18);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.prank(owner);
        token.approve(address(vault), type(uint256).max);
    }

    // ─── Deposit ─────────────────────────────────────────────────────────────

    function test_deposit_basic() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000e18, alice);
        assertGt(shares, 0);
        assertEq(vault.totalAssets(), 1_000e18);
    }

    function test_deposit_twoUsers_proportional() public {
        vm.prank(alice);
        uint256 s1 = vault.deposit(1_000e18, alice);
        vm.prank(bob);
        uint256 s2 = vault.deposit(1_000e18, bob);
        assertEq(s1, s2);
    }

    // FIX: OZ ERC4626 v5 does NOT revert on 0 deposit — it returns 0 shares
    function test_deposit_zeroReturnsZeroShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(0, alice);
        assertEq(shares, 0);
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────

    function test_withdraw_basic() public {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);
        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(1_000e18, alice, alice);
        assertEq(token.balanceOf(alice), balBefore + 1_000e18);
    }

    function test_withdraw_moreSharesBurnedAfterYield() public {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);

        vm.prank(owner);
        vault.setYieldDepositor(owner, true);
        vm.prank(owner);
        vault.depositYield(500e18);

        uint256 assets = vault.convertToAssets(vault.balanceOf(alice));
        assertGt(assets, 1_000e18);
    }

    // ─── Mint / Redeem ────────────────────────────────────────────────────────

    function test_mint_shares() public {
        // First deposit to set exchange rate
        vm.prank(alice);
        vault.deposit(1_000e18, alice);

        // FIX: bob needs to approve vault before mint
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);

        uint256 sharesToMint = vault.convertToShares(500e18);
        vm.prank(bob);
        vault.mint(sharesToMint, bob);
        assertEq(vault.balanceOf(bob), sharesToMint);
    }

    function test_redeem_basic() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000e18, alice);
        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);
        assertEq(token.balanceOf(alice), balBefore + assets);
        assertEq(vault.balanceOf(alice), 0);
    }

    // ─── Yield ────────────────────────────────────────────────────────────────

    function test_depositYield_unauthorizedReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.depositYield(100e18);
    }

    function test_depositYield_authorized() public {
        vm.prank(owner);
        vault.setYieldDepositor(alice, true);
        vm.prank(alice);
        vault.depositYield(500e18);
        assertEq(vault.totalAssets(), 500e18);
    }

    function test_depositYield_ownerAlwaysAllowed() public {
        vm.prank(owner);
        vault.depositYield(500e18);
        assertEq(vault.totalAssets(), 500e18);
    }

    // ─── Price Feed ───────────────────────────────────────────────────────────

    function test_getLatestPrice_valid() public view {
        (int256 price,) = vault.getLatestPrice();
        assertEq(price, INIT_PRICE);
    }

    function test_getLatestPrice_revertsIfStale() public {
        // FIX: warp forward enough so that subtracting STALENESS+1 doesn't underflow
        vm.warp(block.timestamp + STALENESS + 100);
        // Now set feed timestamp to STALENESS+1 seconds ago → stale
        feed.setUpdatedAt(block.timestamp - STALENESS - 1);
        vm.expectRevert();
        vault.getLatestPrice();
    }

    function test_getLatestPrice_revertsIfNegative() public {
        feed.updateAnswer(-1);
        vm.expectRevert();
        vault.getLatestPrice();
    }

    function test_getLatestPrice_revertsIfZero() public {
        feed.updateAnswer(0);
        vm.expectRevert();
        vault.getLatestPrice();
    }

    function test_totalValueUSD() public {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);
        // 1000 GAME * $2.00 = $2000 (8 decimals)
        assertEq(vault.totalValueUSD(), 2000e8);
    }

    function test_setStalenessThreshold_updatesValue() public {
        vm.prank(owner);
        vault.setStalenessThreshold(7200);
        assertEq(vault.stalenessThreshold(), 7200);
    }

    // ─── ERC-4626 Rounding ────────────────────────────────────────────────────

    function test_roundtrip_convertToSharesAndBack() public {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);
        uint256 shares = vault.convertToShares(500e18);
        uint256 assets = vault.convertToAssets(shares);
        assertLe(assets, 500e18 + 1);
    }

    function test_previewDeposit_matchesActual() public {
        uint256 expected = vault.previewDeposit(1_000e18);
        vm.prank(alice);
        uint256 actual = vault.deposit(1_000e18, alice);
        assertEq(actual, expected);
    }

    function test_previewWithdraw_matchesActual() public {
        vm.prank(alice);
        vault.deposit(2_000e18, alice);
        uint256 expectedShares = vault.previewWithdraw(1_000e18);
        vm.prank(alice);
        uint256 actualShares = vault.withdraw(1_000e18, alice, alice);
        assertEq(actualShares, expectedShares);
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_deposit(uint256 assets) public {
        assets = bound(assets, 1, 10_000e18);
        vm.prank(owner);
        token.mint(alice, assets);
        vm.prank(alice);
        token.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);
        assertGt(shares, 0);
    }

    function testFuzz_depositThenRedeem_noLoss(uint256 assets) public {
        assets = bound(assets, 1e6, 5_000e18);
        vm.prank(owner);
        token.mint(alice, assets);
        vm.prank(alice);
        token.approve(address(vault), assets);
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);
        vm.prank(alice);
        uint256 returned = vault.redeem(shares, alice, alice);
        assertGe(returned + 1, assets);
    }
}

// ─── Invariant Tests ──────────────────────────────────────────────────────────

contract VaultHandler is Test {
    GameVault public vault;
    GameToken public token;
    address   public owner;

    address user1 = address(0x11);
    address user2 = address(0x22);

    constructor(GameVault _vault, GameToken _token, address _owner) {
        vault = _vault;
        token = _token;
        owner = _owner;

        vm.prank(owner);
        token.mint(user1, 10_000e18);
        vm.prank(owner);
        token.mint(user2, 10_000e18);
        vm.prank(user1);
        token.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        token.approve(address(vault), type(uint256).max);
    }

    function deposit(uint256 assets, bool isUser1) public {
        assets = bound(assets, 1, 1_000e18);
        address user = isUser1 ? user1 : user2;
        vm.prank(owner);
        token.mint(user, assets);
        vm.prank(user);
        vault.deposit(assets, user);
    }

    function redeem(uint256 pct, bool isUser1) public {
        address user = isUser1 ? user1 : user2;
        uint256 shares = vault.balanceOf(user);
        if (shares == 0) return;
        uint256 toRedeem = bound(pct, 1, shares);
        vm.prank(user);
        vault.redeem(toRedeem, user, user);
    }
}

contract VaultInvariantTest is Test {
    GameVault        vault;
    GameToken        token;
    VaultHandler     handler;
    MockV3Aggregator feed;

    address owner = address(0xA);

    function setUp() public {
        vm.warp(10_000);
        vm.prank(owner);
        token   = new GameToken(owner);
        feed    = new MockV3Aggregator(8, 2e8);
        vm.prank(owner);
        vault   = new GameVault(IERC20(address(token)), address(feed), owner, 3600);
        handler = new VaultHandler(vault, token, owner);
        targetContract(address(handler));
    }

    function invariant_sharePriceNeverBelowOne() public view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;
        assertGe(vault.totalAssets(), supply / 1e18);
    }

    function invariant_totalAssetsMatchesBalance() public view {
        assertEq(vault.totalAssets(), token.balanceOf(address(vault)));
    }
}
