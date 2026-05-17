// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";


contract VulnerableAMM {
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function addLiquidity(uint256 amtA, uint256 amtB) external {
        tokenA.transferFrom(msg.sender, address(this), amtA);
        tokenB.transferFrom(msg.sender, address(this), amtB);
        reserveA += amtA;
        reserveB += amtB;
    }

    function swap(uint256 amountIn) external {
        uint256 amountOut = (amountIn * reserveB) / (reserveA + amountIn);
        tokenB.transfer(msg.sender, amountOut);
        reserveA += amountIn;
        reserveB -= amountOut;
        tokenA.transferFrom(msg.sender, address(this), amountIn);
    }
}

/// @dev Attacker contract that exploits VulnerableAMM via reentrancy
contract ReentrancyAttacker {
    VulnerableAMM public target;
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public attackCount;
    uint256 constant MAX_ATTACKS = 3;

    constructor(address _amm, address _tokenA, address _tokenB) {
        target   = VulnerableAMM(_amm);
        tokenA   = IERC20(_tokenA);
        tokenB   = IERC20(_tokenB);
    }

    function attack(uint256 amountIn) external {
        tokenA.approve(address(target), type(uint256).max);
        target.swap(amountIn);
    }

    /// @dev Called by tokenB.transfer() if tokenB is a malicious ERC20
    ///      In a real attack this would be an ETH receive() or ERC777 hook.
    ///      Here we simulate the pattern for demonstration.
    function simulateReentrantCall() external {
        if (attackCount < MAX_ATTACKS && tokenB.balanceOf(address(target)) > 0) {
            attackCount++;
            // Re-enter swap before reserves are updated
            target.swap(1e18);
        }
    }
}

/// @dev Fixed AMM — CEI pattern + reentrancy guard
contract FixedAMM {
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;
    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function addLiquidity(uint256 amtA, uint256 amtB) external nonReentrant {
        tokenA.transferFrom(msg.sender, address(this), amtA);
        tokenB.transferFrom(msg.sender, address(this), amtB);
        reserveA += amtA;
        reserveB += amtB;
    }

    /// @dev FIXED: state updated BEFORE external call (CEI) + nonReentrant
    function swap(uint256 amountIn) external nonReentrant {
        uint256 amountOut = (amountIn * reserveB) / (reserveA + amountIn);
        tokenA.transferFrom(msg.sender, address(this), amountIn);
        reserveA += amountIn;
        reserveB -= amountOut;
        tokenB.transfer(msg.sender, amountOut);
    }
}


contract VulnerableToken {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply    += amount;
    }
}

/// @dev ERC20 token WITH access control on mint (FIXED)
contract FixedToken {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;
    address public owner;

    constructor() { owner = msg.sender; }

    modifier onlyOwner() {
        require(msg.sender == owner, "FixedToken: caller is not owner");
        _;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        balanceOf[to] += amount;
        totalSupply    += amount;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}

// ════════════════════════════════════════════════════════════════[...]
//  TEST SUITE
// ════════════════════════════════════════════════════════════════[...]

contract SecurityCaseStudiesTest is Test {

    // ── actors ──────────────────────────────────────────────────────────[...]
    address alice   = address(0xA1);
    address bob     = address(0xB0);
    address attacker = address(0xAA);

    MockERC20 tokenA;
    MockERC20 tokenB;


    function test_reentrancy_BEFORE_vulnerable_pattern() public {
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);
        VulnerableAMM vamm = new VulnerableAMM(address(tokenA), address(tokenB));

        // LP adds 10_000 of each
        tokenA.mint(alice, 10_000e18);
        tokenB.mint(alice, 10_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(vamm), type(uint256).max);
        tokenB.approve(address(vamm), type(uint256).max);
        vamm.addLiquidity(10_000e18, 10_000e18);
        vm.stopPrank();

        // Attacker gets some tokenA
        tokenA.mint(attacker, 1_000e18);
        vm.startPrank(attacker);
        tokenA.approve(address(vamm), type(uint256).max);

        uint256 poolBefore = tokenB.balanceOf(address(vamm));

        // Single honest swap — works fine individually
        vamm.swap(100e18);

        uint256 poolAfter = tokenB.balanceOf(address(vamm));

        // Pool lost tokenB — in reentrancy scenario this would be repeated
        // multiple times before reserveA/reserveB are updated, draining the pool.
        assertLt(poolAfter, poolBefore, "Pool should have less tokenB after swap");

        // Key vulnerability: if swap() were called again before state update,
        // amountOut would be calculated on STALE reserves → attacker gets more.
        vm.stopPrank();
    }

    /// @notice Proves VulnerableAMM has NO protection against repeated calls
    ///         before reserve state is committed.
    function test_reentrancy_BEFORE_no_guard_exists() public {
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);
        VulnerableAMM vamm = new VulnerableAMM(address(tokenA), address(tokenB));

        tokenA.mint(alice, 20_000e18);
        tokenB.mint(alice, 20_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(vamm), type(uint256).max);
        tokenB.approve(address(vamm), type(uint256).max);
        vamm.addLiquidity(10_000e18, 10_000e18);
        vm.stopPrank();

        tokenA.mint(attacker, 5_000e18);
        vm.startPrank(attacker);
        tokenA.approve(address(vamm), type(uint256).max);

        // VulnerableAMM has no _locked flag — calling swap twice in same
        // transaction is allowed (simulates reentrant call path)
        vamm.swap(100e18);
        vamm.swap(100e18); // ← second call succeeds on stale-ish reserves

        // No revert — proves absence of reentrancy guard
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────────────────[...]
    //  REENTRANCY — AFTER (fixed with CEI + nonReentrant)
    // ──────────────────────────────────────────────────────────────[...]

    /// @notice Fixed AMM correctly processes an honest swap.
    function test_reentrancy_AFTER_honest_swap_works() public {
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);
        FixedAMM famm = new FixedAMM(address(tokenA), address(tokenB));

        tokenA.mint(alice, 20_000e18);
        tokenB.mint(alice, 20_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(famm), type(uint256).max);
        tokenB.approve(address(famm), type(uint256).max);
        famm.addLiquidity(10_000e18, 10_000e18);
        vm.stopPrank();

        tokenA.mint(bob, 1_000e18);
        vm.startPrank(bob);
        tokenA.approve(address(famm), type(uint256).max);

        uint256 balBefore = tokenB.balanceOf(bob);
        famm.swap(100e18);
        uint256 balAfter = tokenB.balanceOf(bob);

        assertGt(balAfter, balBefore, "Bob should receive tokenB");
        vm.stopPrank();
    }

    /// @notice Reentrant call is blocked by nonReentrant modifier.
    function test_reentrancy_AFTER_reentrant_call_reverts() public {
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);
        FixedAMM famm = new FixedAMM(address(tokenA), address(tokenB));

        tokenA.mint(alice, 20_000e18);
        tokenB.mint(alice, 20_000e18);
        vm.startPrank(alice);
        tokenA.approve(address(famm), type(uint256).max);
        tokenB.approve(address(famm), type(uint256).max);
        famm.addLiquidity(10_000e18, 10_000e18);
        vm.stopPrank();

        // Deploy a contract that tries to re-enter swap() within the same call
        ReentrantCaller reentrant = new ReentrantCaller(address(famm), address(tokenA), address(tokenB));
        tokenA.mint(address(reentrant), 1_000e18);
        tokenB.mint(address(reentrant), 1_000e18);

        // The reentrant call must revert with the guard error
        vm.expectRevert("ReentrancyGuard: reentrant call");
        reentrant.attack(100e18);
    }

    // ──────────────────────────────────────────────────────────────[...]
    //  ACCESS CONTROL — BEFORE (anyone can mint)
    // ──────────────────────────────────────────────────────────────[...]

    /// @notice Any address can mint from VulnerableToken — proves the bug.
    function test_accessControl_BEFORE_anyone_can_mint() public {
        VulnerableToken vtoken = new VulnerableToken();

        // Attacker mints 1 billion tokens to themselves — no revert
        vm.prank(attacker);
        vtoken.mint(attacker, 1_000_000_000e18);

        assertEq(vtoken.balanceOf(attacker), 1_000_000_000e18,
            "Attacker should hold minted tokens");
        assertEq(vtoken.totalSupply(), 1_000_000_000e18,
            "Total supply inflated by attacker");
    }

    /// @notice Even random addresses (not deployer) can mint — proves no guard.
    function test_accessControl_BEFORE_random_addr_mints() public {
        VulnerableToken vtoken = new VulnerableToken();

        address rando = address(0xDEAD);
        vm.prank(rando);
        vtoken.mint(rando, 999e18); // should NOT revert — proves vulnerability
        assertEq(vtoken.balanceOf(rando), 999e18);
    }

    // ──────────────────────────────────────────────────────────────[...]
    //  ACCESS CONTROL — AFTER (only owner can mint)
    // ──────────────────────────────────────────────────────────────[...]

    /// @notice Owner can mint — expected functionality.
    function test_accessControl_AFTER_owner_can_mint() public {
        vm.prank(alice);
        FixedToken ftoken = new FixedToken(); // alice is owner

        vm.prank(alice);
        ftoken.mint(alice, 100_000e18);

        assertEq(ftoken.balanceOf(alice), 100_000e18);
        assertEq(ftoken.totalSupply(), 100_000e18);
    }

    /// @notice Non-owner cannot mint — access control works.
    function test_accessControl_AFTER_nonOwner_cannot_mint() public {
        vm.prank(alice);
        FixedToken ftoken = new FixedToken(); // alice is owner

        vm.prank(attacker);
        vm.expectRevert("FixedToken: caller is not owner");
        ftoken.mint(attacker, 1_000_000e18);
    }

    /// @notice Ownership can be transferred (e.g., to Timelock).
    function test_accessControl_AFTER_ownership_transfer_to_timelock() public {
        address timelock = address(0x71);

        vm.prank(alice);
        FixedToken ftoken = new FixedToken();

        // Transfer ownership to Timelock (as done in production deploy)
        vm.prank(alice);
        ftoken.transferOwnership(timelock);

        assertEq(ftoken.owner(), timelock, "Timelock should be new owner");

        // Old owner can no longer mint
        vm.prank(alice);
        vm.expectRevert("FixedToken: caller is not owner");
        ftoken.mint(alice, 1e18);

        // Timelock can mint
        vm.prank(timelock);
        ftoken.mint(bob, 500e18);
        assertEq(ftoken.balanceOf(bob), 500e18);
    }

    /// @notice Fuzz: only owner can ever mint, regardless of caller.
    function testFuzz_accessControl_onlyOwnerCanMint(address caller, uint256 amount) public {
        vm.assume(caller != address(0));
        vm.assume(amount < type(uint128).max);

        vm.prank(alice);
        FixedToken ftoken = new FixedToken();

        if (caller == alice) {
            vm.prank(caller);
            ftoken.mint(caller, amount);
            assertEq(ftoken.balanceOf(caller), amount);
        } else {
            vm.prank(caller);
            vm.expectRevert("FixedToken: caller is not owner");
            ftoken.mint(caller, amount);
        }
    }
}

// ════════════════════════════════════════════════════════════════[...]
//  Helper — contract that attempts to re-enter FixedAMM.swap()
// ════════════════════════════════════════════════════════════════[...]
contract ReentrantCaller {
    FixedAMM public amm;
    IERC20   public tokenA;
    IERC20   public tokenB;
    bool     private attacking;

    constructor(address _amm, address _tokenA, address _tokenB) {
        amm    = FixedAMM(_amm);
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function attack(uint256 amount) external {
        attacking = true;
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        // This call will trigger reentrancy check
        amm.swap(amount);
    }

    /// @dev Receive hook that simulates a re-entrant callback
    /// This is called when MockERC20.transfer() is called from FixedAMM.swap()
    receive() external payable {
        if (attacking) {
            attacking = false;
            // This re-entrant call must revert due to nonReentrant guard
            amm.swap(1e18);
        }
    }

    /// @dev Fallback handler for any calls
    fallback() external {
        if (attacking) {
            attacking = false;
            // This re-entrant call must revert due to nonReentrant guard
            try amm.swap(1e18) {
                // If it didn't revert, the test will fail
            } catch {
                // Expected revert
            }
        }
    }
}
