// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/GameItems.sol";
import "../src/GameItemsV2.sol";

contract GameItemsTest is Test {
    GameItems    implementation;
    GameItems    items;
    ERC1967Proxy proxy;

    address admin = address(0xA);
    address alice = address(0xB);
    address bob   = address(0xC);

    function setUp() public {
        implementation = new GameItems();
        bytes memory initData = abi.encodeCall(GameItems.initialize, (admin));
        proxy = new ERC1967Proxy(address(implementation), initData);
        items = GameItems(address(proxy));
    }

    // ─── Initialization ───────────────────────────────────────────────────────

    function test_initialize_rolesGranted() public view {
        assertTrue(items.hasRole(items.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(items.hasRole(items.MINTER_ROLE(), admin));
        assertTrue(items.hasRole(items.UPGRADER_ROLE(), admin));
    }

    function test_initialize_revertsOnDoubleInit() public {
        vm.expectRevert();
        items.initialize(alice);
    }

    // ─── Minting ──────────────────────────────────────────────────────────────

    function test_mint_basic() public {
        // FIX: cache constant BEFORE prank — vm.prank is consumed by items.SWORD() call
        uint256 swordId = items.SWORD();
        vm.prank(admin);
        items.mint(alice, swordId, 5);
        assertEq(items.balanceOf(alice, swordId), 5);
    }

    function test_mint_revertsWithoutMinterRole() public {
        uint256 swordId = items.SWORD();
        vm.prank(alice);
        vm.expectRevert();
        items.mint(alice, swordId, 1);
    }

    function test_mint_allItemTypes() public {
        vm.startPrank(admin);
        items.mint(alice, items.SWORD(),     1);
        items.mint(alice, items.SHIELD(),    1);
        items.mint(alice, items.POTION(),    1);
        items.mint(alice, items.ARMOR(),     1);
        items.mint(alice, items.MAGIC_ORB(), 1);
        vm.stopPrank();
        for (uint256 i = 0; i < 5; i++) {
            assertEq(items.balanceOf(alice, i), 1);
        }
    }

    function test_mintBatch_basic() public {
        uint256[] memory ids     = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        ids[0] = items.SWORD();   amounts[0] = 2;
        ids[1] = items.POTION();  amounts[1] = 10;
        ids[2] = items.ARMOR();   amounts[2] = 1;

        vm.prank(admin);
        items.mintBatch(alice, ids, amounts);

        assertEq(items.balanceOf(alice, items.SWORD()),  2);
        assertEq(items.balanceOf(alice, items.POTION()), 10);
        assertEq(items.balanceOf(alice, items.ARMOR()),  1);
    }

    function test_mintBatch_revertsWithoutRole() public {
        uint256[] memory ids     = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 0; amounts[0] = 1;
        vm.prank(alice);
        vm.expectRevert();
        items.mintBatch(alice, ids, amounts);
    }

    // ─── Access Control ───────────────────────────────────────────────────────

    function test_grantMinterRole() public {
        bytes32 minterRole = items.MINTER_ROLE();
        vm.prank(admin);
        items.grantRole(minterRole, alice);
        assertTrue(items.hasRole(minterRole, alice));

        uint256 potionId = items.POTION();
        vm.prank(alice);
        items.mint(bob, potionId, 5);
        assertEq(items.balanceOf(bob, potionId), 5);
    }

    function test_revokeMinterRole() public {
        bytes32 minterRole = items.MINTER_ROLE();
        vm.startPrank(admin);
        items.grantRole(minterRole, alice);
        items.revokeRole(minterRole, alice);
        vm.stopPrank();

        uint256 swordId = items.SWORD();
        vm.prank(alice);
        vm.expectRevert();
        items.mint(bob, swordId, 1);
    }

    // ─── ERC-1155 ─────────────────────────────────────────────────────────────

    function test_supportsInterface_ERC1155() public view {
        assertTrue(items.supportsInterface(0xd9b67a26));
    }

    function test_supportsInterface_AccessControl() public view {
        assertTrue(items.supportsInterface(0x7965db0b));
    }

    function test_safeTransferFrom() public {
        uint256 swordId = items.SWORD();
        vm.prank(admin);
        items.mint(alice, swordId, 3);

        vm.prank(alice);
        items.safeTransferFrom(alice, bob, swordId, 2, "");
        assertEq(items.balanceOf(alice, swordId), 1);
        assertEq(items.balanceOf(bob,   swordId), 2);
    }

    // ─── UUPS Upgrade ─────────────────────────────────────────────────────────

    function test_upgrade_toV2() public {
        GameItemsV2 v2Impl = new GameItemsV2();
        vm.prank(admin);
        items.upgradeToAndCall(address(v2Impl), "");

        GameItemsV2 v2 = GameItemsV2(address(proxy));
        assertTrue(v2.hasRole(v2.DEFAULT_ADMIN_ROLE(), admin));
        vm.prank(admin);
        v2.setCraftingEnabled(true);
        assertTrue(v2.craftingEnabled());
    }

    function test_upgrade_revertsWithoutUpgraderRole() public {
        GameItemsV2 v2Impl = new GameItemsV2();
        vm.prank(alice);
        vm.expectRevert();
        items.upgradeToAndCall(address(v2Impl), "");
    }

    function test_upgrade_v2_craftingRecipeAndCraft() public {
        GameItemsV2 v2Impl = new GameItemsV2();
        vm.prank(admin);
        items.upgradeToAndCall(address(v2Impl), "");
        GameItemsV2 v2 = GameItemsV2(address(proxy));

        uint256 swordId  = v2.SWORD();
        uint256 shieldId = v2.SHIELD();
        uint256 armorId  = v2.ARMOR();

        vm.startPrank(admin);
        v2.setCraftingEnabled(true);

        uint256[] memory inIds     = new uint256[](2);
        uint256[] memory inAmounts = new uint256[](2);
        inIds[0] = swordId;  inAmounts[0] = 2;
        inIds[1] = shieldId; inAmounts[1] = 2;
        v2.registerRecipe(inIds, inAmounts, armorId);

        v2.mint(alice, swordId,  2);
        v2.mint(alice, shieldId, 2);
        vm.stopPrank();

        vm.prank(alice);
        v2.craft(inIds, inAmounts, armorId, 1);

        assertEq(v2.balanceOf(alice, armorId),  1);
        assertEq(v2.balanceOf(alice, swordId),  0);
        assertEq(v2.balanceOf(alice, shieldId), 0);
    }
}
