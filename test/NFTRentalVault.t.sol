// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/NFTRentalVault.sol";
import "../src/GameItems.sol";
import "../src/GameToken.sol";

contract NFTRentalVaultTest is Test {
    NFTRentalVault vault;
    GameItems      items;
    GameToken      token;

    address owner = address(0xA);
    address alice = address(0xB);
    address bob   = address(0xC);

    function setUp() public {
        vm.prank(owner);
        token = new GameToken(owner);

        GameItems impl = new GameItems();
        bytes memory data = abi.encodeCall(GameItems.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        items = GameItems(address(proxy));

        vm.prank(owner);
        vault = new NFTRentalVault(address(items), address(token), owner);

        vm.prank(owner);
        token.mint(alice, 10_000e18);
        vm.prank(owner);
        token.mint(bob,   10_000e18);

        // FIX: cache constants BEFORE prank
        uint256 swordId = items.SWORD();
        vm.prank(owner);
        items.mint(alice, swordId, 5);

        vm.prank(alice);
        items.setApprovalForAll(address(vault), true);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // ─── listItem ──────────────────────────────────────────────────────────────

    function test_listItem_basic() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 2, 100e18);

        (address listedOwner, uint256 itemId, uint256 amount, uint256 price, bool active) =
                            vault.listings(listingId);

        assertEq(listedOwner, alice);
        assertEq(itemId, swordId);
        assertEq(amount, 2);
        assertEq(price,  100e18);
        assertTrue(active);
        assertEq(items.balanceOf(address(vault), swordId), 2);
    }

    function test_listItem_revertsZeroAmount() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        vm.expectRevert("Zero amount");
        vault.listItem(swordId, 0, 100e18);
    }

    function test_listItem_revertsZeroPrice() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        vm.expectRevert("Zero price");
        vault.listItem(swordId, 1, 0);
    }

    // ─── rentItem ──────────────────────────────────────────────────────────────

    function test_rentItem_basic() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);

        uint256 bobBalBefore = token.balanceOf(bob);
        vm.prank(bob);
        uint256 rentalId = vault.rentItem(listingId, 3);

        (address renter, uint256 lId, , uint256 endTime, bool active) = vault.rentals(rentalId);
        assertEq(renter, bob);
        assertEq(lId, listingId);
        assertTrue(active);
        assertEq(endTime, block.timestamp + 3 days);

        uint256 totalCost = 30e18;
        assertEq(token.balanceOf(bob), bobBalBefore - totalCost);
    }

    function test_rentItem_revertsOwnItem() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);

        vm.prank(owner);
        token.mint(alice, 1_000e18);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(alice);
        vm.expectRevert("Cannot rent own item");
        vault.rentItem(listingId, 1);
    }

    function test_rentItem_revertsZeroDuration() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);
        vm.prank(bob);
        vm.expectRevert("Invalid duration");
        vault.rentItem(listingId, 0);
    }

    function test_rentItem_revertsExceedsMaxDuration() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);
        vm.prank(bob);
        vm.expectRevert("Invalid duration");
        vault.rentItem(listingId, 8);
    }

    function test_rentItem_revertsAlreadyRented() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);
        vm.prank(bob);
        vault.rentItem(listingId, 1);

        address charlie = address(0xD);
        vm.prank(owner);
        token.mint(charlie, 1_000e18);
        vm.prank(charlie);
        token.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        vm.expectRevert("Not active");
        vault.rentItem(listingId, 1);
    }

    // ─── endRental ─────────────────────────────────────────────────────────────

    function test_endRental_basic() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);
        vm.prank(bob);
        uint256 rentalId = vault.rentItem(listingId, 1);

        vm.warp(block.timestamp + 1 days + 1);
        vault.endRental(rentalId);

        (, , , , bool rentalActive) = vault.rentals(rentalId);
        (, , , , bool listingActive) = vault.listings(listingId);
        assertFalse(rentalActive);
        assertTrue(listingActive);
    }

    function test_endRental_revertsNotExpired() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);
        vm.prank(bob);
        uint256 rentalId = vault.rentItem(listingId, 2);
        vm.prank(bob);
        vm.expectRevert("Rental not expired");
        vault.endRental(rentalId);
    }

    function test_endRental_revertsNotActive() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 10e18);
        vm.prank(bob);
        uint256 rentalId = vault.rentItem(listingId, 1);
        vm.warp(block.timestamp + 1 days + 1);
        vault.endRental(rentalId);
        vm.expectRevert("Not active");
        vault.endRental(rentalId);
    }

    // ─── delistItem ────────────────────────────────────────────────────────────

    function test_delistItem_basic() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 2, 100e18);

        uint256 balBefore = items.balanceOf(alice, swordId);
        vm.prank(alice);
        vault.delistItem(listingId);

        assertEq(items.balanceOf(alice, swordId), balBefore + 2);
        (, , , , bool active) = vault.listings(listingId);
        assertFalse(active);
    }

    function test_delistItem_revertsNotOwner() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 100e18);
        vm.prank(bob);
        vm.expectRevert("Not owner");
        vault.delistItem(listingId);
    }

    // ─── Admin ─────────────────────────────────────────────────────────────────

    function test_setPlatformFee() public {
        vm.prank(owner);
        vault.setPlatformFee(100);
        assertEq(vault.platformFee(), 100);
    }

    function test_setPlatformFee_revertsAboveMax() public {
        vm.prank(owner);
        vm.expectRevert("Max 10%");
        vault.setPlatformFee(101);
    }

    function test_withdrawFees() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        uint256 listingId = vault.listItem(swordId, 1, 100e18);
        vm.prank(bob);
        vault.rentItem(listingId, 1);

        uint256 ownerBalBefore = token.balanceOf(owner);
        vm.prank(owner);
        vault.withdrawFees();
        assertGt(token.balanceOf(owner), ownerBalBefore);
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_rentalCost(uint256 pricePerDay, uint256 durationDays) public {
        durationDays = bound(durationDays, 1, 7);
        pricePerDay  = bound(pricePerDay, 1e15, 100e18);

        uint256 shieldId = items.SHIELD();
        vm.prank(owner);
        items.mint(alice, shieldId, 10);

        vm.prank(alice);
        uint256 listingId = vault.listItem(shieldId, 1, pricePerDay);

        uint256 totalCost = pricePerDay * durationDays;
        vm.prank(owner);
        token.mint(bob, totalCost);

        uint256 balBefore = token.balanceOf(bob);
        vm.prank(bob);
        vault.rentItem(listingId, durationDays);
        assertEq(token.balanceOf(bob), balBefore - totalCost);
    }
}
