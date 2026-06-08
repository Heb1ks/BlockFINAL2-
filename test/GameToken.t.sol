// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GameToken.sol";

contract GameTokenTest is Test {
    GameToken token;
    address owner = address(0xA);
    address alice = address(0xB);
    address bob = address(0xC);

    function setUp() public {
        vm.prank(owner);
        token = new GameToken(owner);
    }

    function test_initialMint() public view {
        assertEq(token.totalSupply(), 100_000e18);
        assertEq(token.balanceOf(owner), 100_000e18);
    }

    function test_maxSupply() public view {
        assertEq(token.MAX_SUPPLY(), 1_000_000e18);
    }

    function test_tokenMetadata() public view {
        assertEq(token.name(), "GameToken");
        assertEq(token.symbol(), "GAME");
    }

    function test_mint_basic() public {
        vm.prank(owner);
        token.mint(alice, 1_000e18);
        assertEq(token.balanceOf(alice), 1_000e18);
    }

    function test_mint_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1e18);
    }

    function test_mint_revertsIfExceedsMaxSupply() public {
        vm.prank(owner);
        vm.expectRevert("Exceeds max supply");
        token.mint(alice, 900_001e18);
    }

    function test_mint_exactlyAtMaxSupply() public {
        vm.prank(owner);
        token.mint(alice, 900_000e18);
        assertEq(token.totalSupply(), 1_000_000e18);
    }

    function test_transfer_basic() public {
        vm.prank(owner);
        token.transfer(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
    }

    function test_transferFrom_withApproval() public {
        vm.prank(owner);
        token.approve(alice, 200e18);
        vm.prank(alice);
        token.transferFrom(owner, bob, 200e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    function test_delegate_self() public {
        vm.prank(owner);
        token.delegate(owner);
        assertEq(token.getVotes(owner), 100_000e18);
    }

    function test_delegate_toAlice() public {
        vm.prank(owner);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 100_000e18);
    }

    function test_votingPower_transferUpdatesVotes() public {
        vm.startPrank(owner);
        token.delegate(owner);
        token.transfer(alice, 10_000e18);
        vm.stopPrank();

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 10_000e18);
        assertEq(token.getVotes(owner), 90_000e18);
    }

    function test_getPastVotes() public {
        vm.prank(owner);
        token.delegate(owner);

        // FIX: advance 2 units (covers both block-based and timestamp-based clocks)
        // Then query at block.number - 1 which is strictly in the past
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 2);

        assertEq(token.getPastVotes(owner, block.number - 1), 100_000e18);
    }

    function test_permit() public {
        uint256 privKey = 0xBEEF;
        address signer = vm.addr(privKey);

        vm.prank(owner);
        token.transfer(signer, 1_000e18);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 domainSep = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                alice,
                500e18,
                token.nonces(signer),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);

        token.permit(signer, alice, 500e18, deadline, v, r, s);
        assertEq(token.allowance(signer, alice), 500e18);
    }

    function testFuzz_mint(uint256 amount) public {
        uint256 remaining = token.MAX_SUPPLY() - token.totalSupply();
        amount = bound(amount, 0, remaining);
        vm.prank(owner);
        token.mint(alice, amount);
        assertLe(token.totalSupply(), token.MAX_SUPPLY());
    }

    function testFuzz_delegateVotingPower(address delegatee) public {
        vm.assume(delegatee != address(0));
        vm.prank(owner);
        token.delegate(delegatee);
        assertEq(token.getVotes(delegatee), 100_000e18);
    }
}
