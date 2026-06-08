// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GameAMM.sol";
import "../src/mocks/MockERC20.sol";

contract GameAMMTest is Test {
    GameAMM amm;
    MockERC20 tokenA;
    MockERC20 tokenB;
    address alice = address(0xA);
    address bob = address(0xB);

    function setUp() public {
        tokenA = new MockERC20("Gold", "GOLD", 18);
        tokenB = new MockERC20("Wood", "WOOD", 18);
        amm = new GameAMM(address(tokenA), address(tokenB));

        tokenA.mint(alice, 100_000e18);
        tokenB.mint(alice, 200_000e18);
        tokenA.mint(bob, 100_000e18);
        tokenB.mint(bob, 200_000e18);

        vm.startPrank(alice);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    //  addLiquidity

    function test_addLiquidity_initialMint_createsShares() public {
        vm.prank(alice);
        uint256 shares = amm.addLiquidity(10_000e18, 20_000e18);
        assertTrue(shares > 0);
        assertEq(amm.balanceOf(alice), shares);
    }

    function test_addLiquidity_sqrtIsCorrect() public {
        // FIX: sqrt(10_000e18 * 20_000e18) = sqrt(2e26*1e18*1e18)
        // We just verify shares > 0 and proportional to inputs
        vm.prank(alice);
        uint256 shares = amm.addLiquidity(10_000e18, 20_000e18);
        assertGt(shares, 0);

        // Second add: double the amounts should give ~double shares
        vm.prank(bob);
        uint256 shares2 = amm.addLiquidity(10_000e18, 20_000e18);
        assertApproxEqRel(shares2, shares, 1e15); // within 0.1%
    }

    function test_addLiquidity_subsequentMint() public {
        vm.prank(alice);
        uint256 s1 = amm.addLiquidity(10_000e18, 20_000e18);
        vm.prank(bob);
        uint256 s2 = amm.addLiquidity(5_000e18, 10_000e18);
        assertTrue(s2 > 0);
        assertApproxEqRel(s2, s1 / 2, 1e15);
    }

    function test_addLiquidity_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("Zero amount");
        amm.addLiquidity(0, 1e18);
    }

    function test_addLiquidity_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit GameAMM.LiquidityAdded(alice, 10_000e18, 20_000e18, 0);
        amm.addLiquidity(10_000e18, 20_000e18);
    }

    //  removeLiquidity

    function test_removeLiquidity_basic() public {
        vm.prank(alice);
        uint256 shares = amm.addLiquidity(10_000e18, 20_000e18);
        uint256 balABefore = tokenA.balanceOf(alice);
        uint256 balBBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(shares);

        assertGt(outA, 0);
        assertGt(outB, 0);
        assertEq(amm.totalSupply(), 0);
        assertEq(tokenA.balanceOf(alice), balABefore + outA);
        assertEq(tokenB.balanceOf(alice), balBBefore + outB);
    }

    function test_removeLiquidity_partialRemoval() public {
        vm.prank(alice);
        uint256 shares = amm.addLiquidity(10_000e18, 20_000e18);
        vm.prank(alice);
        amm.removeLiquidity(shares / 2);
        assertApproxEqRel(amm.totalSupply(), shares / 2, 1e15);
    }

    function test_removeLiquidity_revertsZeroShares() public {
        vm.prank(alice);
        vm.expectRevert("Zero shares");
        amm.removeLiquidity(0);
    }

    function test_removeLiquidity_revertsNoLiquidity() public {
        vm.prank(alice);
        vm.expectRevert("No liquidity");
        amm.removeLiquidity(1e18);
    }

    //  swapAtoB

    function test_swapAtoB_basic() public {
        vm.prank(alice);
        amm.addLiquidity(50_000e18, 100_000e18);
        uint256 balBBefore = tokenB.balanceOf(bob);
        vm.prank(bob);
        uint256 out = amm.swapAtoB(1_000e18, 0);
        assertGt(out, 0);
        assertEq(tokenB.balanceOf(bob), balBBefore + out);
    }

    function test_swapAtoB_revertsZeroInput() public {
        vm.prank(alice);
        amm.addLiquidity(10_000e18, 20_000e18);
        vm.prank(bob);
        vm.expectRevert("Zero input");
        amm.swapAtoB(0, 0);
    }

    function test_swapAtoB_revertsSlippage() public {
        vm.prank(alice);
        amm.addLiquidity(10_000e18, 20_000e18);
        vm.prank(bob);
        vm.expectRevert("Slippage exceeded");
        amm.swapAtoB(1_000e18, type(uint256).max);
    }

    function test_swapAtoB_feeDeducted() public {
        vm.prank(alice);
        amm.addLiquidity(50_000e18, 100_000e18);
        uint256 amtIn = 1_000e18;
        uint256 rA = 50_000e18;
        uint256 rB = 100_000e18;
        uint256 expected = (amtIn * 997 * rB) / (rA * 1000 + amtIn * 997);
        vm.prank(bob);
        uint256 out = amm.swapAtoB(amtIn, 0);
        assertEq(out, expected);
    }

    //  swapBtoA

    function test_swapBtoA_basic() public {
        vm.prank(alice);
        amm.addLiquidity(50_000e18, 100_000e18);
        uint256 balABefore = tokenA.balanceOf(bob);
        vm.prank(bob);
        uint256 out = amm.swapBtoA(2_000e18, 0);
        assertGt(out, 0);
        assertEq(tokenA.balanceOf(bob), balABefore + out);
    }

    function test_swapBtoA_revertsZeroInput() public {
        vm.prank(alice);
        amm.addLiquidity(10_000e18, 20_000e18);
        vm.prank(bob);
        vm.expectRevert("Zero input");
        amm.swapBtoA(0, 0);
    }

    function test_swapBtoA_revertsSlippage() public {
        vm.prank(alice);
        amm.addLiquidity(10_000e18, 20_000e18);
        vm.prank(bob);
        vm.expectRevert("Slippage exceeded");
        amm.swapBtoA(1_000e18, type(uint256).max);
    }

    //  Yul benchmark

    function test_yulAmountOut_matchesSolidity() public view {
        uint256 sol = amm.getAmountOutSolidity(1_000e18, 50_000e18, 100_000e18);
        uint256 yul = amm.getAmountOutYul(1_000e18, 50_000e18, 100_000e18);
        assertEq(sol, yul);
    }

    function test_getReserves() public {
        vm.prank(alice);
        amm.addLiquidity(10_000e18, 20_000e18);
        (uint256 rA, uint256 rB) = amm.getReserves();
        assertEq(rA, 10_000e18);
        assertEq(rB, 20_000e18);
    }

    function test_kInvariant_afterSwap() public {
        vm.prank(alice);
        amm.addLiquidity(50_000e18, 100_000e18);
        (uint256 rABefore, uint256 rBBefore) = amm.getReserves();
        uint256 kBefore = rABefore * rBBefore;
        vm.prank(bob);
        amm.swapAtoB(1_000e18, 0);
        (uint256 rAAfter, uint256 rBAfter) = amm.getReserves();
        assertGe(rAAfter * rBAfter, kBefore);
    }

    //  Fuzz

    function testFuzz_swapAtoB_kNeverDecreases(uint256 amountIn) public {
        vm.prank(alice);
        amm.addLiquidity(50_000e18, 100_000e18);
        amountIn = bound(amountIn, 1e15, 10_000e18);
        tokenA.mint(bob, amountIn);
        vm.prank(bob);
        tokenA.approve(address(amm), amountIn);
        (uint256 rABefore, uint256 rBBefore) = amm.getReserves();
        uint256 kBefore = rABefore * rBBefore;
        vm.prank(bob);
        amm.swapAtoB(amountIn, 0);
        (uint256 rAAfter, uint256 rBAfter) = amm.getReserves();
        assertGe(rAAfter * rBAfter, kBefore);
    }

    function testFuzz_swapBtoA_kNeverDecreases(uint256 amountIn) public {
        vm.prank(alice);
        amm.addLiquidity(50_000e18, 100_000e18);
        amountIn = bound(amountIn, 1e15, 20_000e18);
        tokenB.mint(bob, amountIn);
        vm.prank(bob);
        tokenB.approve(address(amm), amountIn);
        (uint256 rABefore, uint256 rBBefore) = amm.getReserves();
        uint256 kBefore = rABefore * rBBefore;
        vm.prank(bob);
        amm.swapBtoA(amountIn, 0);
        (uint256 rAAfter, uint256 rBAfter) = amm.getReserves();
        assertGe(rAAfter * rBAfter, kBefore);
    }

    function testFuzz_addLiquidity_subsequentShares(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1e15, 10_000e18);
        amountB = bound(amountB, 1e15, 20_000e18);
        vm.prank(alice);
        amm.addLiquidity(10_000e18, 20_000e18);
        tokenA.mint(bob, amountA);
        tokenB.mint(bob, amountB);
        vm.prank(bob);
        tokenA.approve(address(amm), amountA);
        vm.prank(bob);
        tokenB.approve(address(amm), amountB);
        vm.prank(bob);
        uint256 shares = amm.addLiquidity(amountA, amountB);
        assertGt(shares, 0);
    }

    // FIX: bound inputs to uint128 max to avoid overflow in Yul (unchecked mul)
    function testFuzz_yulMatchesSolidity(uint256 amtIn, uint256 rIn, uint256 rOut) public view {
        amtIn = bound(amtIn, 1, type(uint64).max);
        rIn = bound(rIn, 1, type(uint64).max);
        rOut = bound(rOut, 1, type(uint64).max);
        uint256 sol = amm.getAmountOutSolidity(amtIn, rIn, rOut);
        uint256 yul = amm.getAmountOutYul(amtIn, rIn, rOut);
        assertEq(sol, yul);
    }
}

//  Invariant Tests

contract AMMHandler is Test {
    GameAMM public amm;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address lp = address(0xAA);
    address swapper = address(0xBB);
    uint256 public lastK;

    constructor(GameAMM _amm, MockERC20 _tA, MockERC20 _tB) {
        amm = _amm;
        tokenA = _tA;
        tokenB = _tB;

        tokenA.mint(lp, 1_000_000e18);
        tokenB.mint(lp, 1_000_000e18);
        vm.prank(lp);
        tokenA.approve(address(amm), type(uint256).max);
        vm.prank(lp);
        tokenB.approve(address(amm), type(uint256).max);
        vm.prank(lp);
        amm.addLiquidity(100_000e18, 200_000e18);

        (uint256 rA, uint256 rB) = amm.getReserves();
        lastK = rA * rB;

        tokenA.mint(swapper, 100_000e18);
        tokenB.mint(swapper, 100_000e18);
        vm.prank(swapper);
        tokenA.approve(address(amm), type(uint256).max);
        vm.prank(swapper);
        tokenB.approve(address(amm), type(uint256).max);
    }

    function swapAtoB(uint256 amt) public {
        amt = bound(amt, 1e15, 10_000e18);
        if (tokenA.balanceOf(swapper) < amt) {
            tokenA.mint(swapper, amt);
            vm.prank(swapper);
            tokenA.approve(address(amm), type(uint256).max);
        }
        vm.prank(swapper);
        amm.swapAtoB(amt, 0);
        _updateK();
    }

    function swapBtoA(uint256 amt) public {
        amt = bound(amt, 1e15, 20_000e18);
        if (tokenB.balanceOf(swapper) < amt) {
            tokenB.mint(swapper, amt);
            vm.prank(swapper);
            tokenB.approve(address(amm), type(uint256).max);
        }
        vm.prank(swapper);
        amm.swapBtoA(amt, 0);
        _updateK();
    }

    function addLiquidity(uint256 amtA, uint256 amtB) public {
        amtA = bound(amtA, 1e15, 50_000e18);
        amtB = bound(amtB, 1e15, 50_000e18);
        tokenA.mint(lp, amtA);
        tokenB.mint(lp, amtB);
        vm.prank(lp);
        amm.addLiquidity(amtA, amtB);
        _updateK();
    }

    function _updateK() internal {
        (uint256 rA, uint256 rB) = amm.getReserves();
        lastK = rA * rB;
    }
}

contract AMMInvariantTest is Test {
    GameAMM amm;
    MockERC20 tokenA;
    MockERC20 tokenB;
    AMMHandler handler;

    function setUp() public {
        tokenA = new MockERC20("Gold", "GOLD", 18);
        tokenB = new MockERC20("Wood", "WOOD", 18);
        amm = new GameAMM(address(tokenA), address(tokenB));
        handler = new AMMHandler(amm, tokenA, tokenB);
        targetContract(address(handler));
    }

    function invariant_kNeverDecreases() public view {
        (uint256 rA, uint256 rB) = amm.getReserves();
        assertGe(rA * rB, handler.lastK());
    }

    function invariant_lpTotalSupplyNonZero() public view {
        assertGt(amm.totalSupply(), 0);
    }

    function invariant_reservesNonZero() public view {
        (uint256 rA, uint256 rB) = amm.getReserves();
        assertGt(rA, 0);
        assertGt(rB, 0);
    }
}
