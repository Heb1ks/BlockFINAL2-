// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GameItemsV2.sol";

/**
 * SetupCrafting.s.sol
 * 
 * This script enables crafting and registers all recipes on the GameItemsV2 contract.
 * Run after deployment to initialize crafting functionality.
 * 
 * Usage:
 * forge script script/SetupCrafting.s.sol \
 *   --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast
 */
contract SetupCrafting is Script {
    address constant GAME_ITEMS_V2 = 0x2D3740Ec560e18F78501Fd04Ca71d996a956d084;

    function run() external {
        vm.startBroadcast();

        GameItemsV2 items = GameItemsV2(GAME_ITEMS_V2);

        // 1. Enable crafting
        items.setCraftingEnabled(true);
        console.log("[SetupCrafting] Crafting enabled ✓");

        // 2. Register recipes — MUST match frontend CRAFTING_RECIPES exactly
        // Recipe keys must be: keccak256(abi.encode(inputIds, inputAmounts, outputId))

        // recipe_0: Forge a Sword
        // Inputs: Potion×2 + Shield×1
        // Output: Sword×1
        {
            uint256[] memory ids   = new uint256[](2);
            ids[0] = 2;  // Potion
            ids[1] = 1;  // Shield
            
            uint256[] memory amts  = new uint256[](2);
            amts[0] = 2;  // 2x Potion
            amts[1] = 1;  // 1x Shield
            
            items.registerRecipe(ids, amts, 0);  // outputId = 0 (Sword)
            console.log("[SetupCrafting] Recipe 0 (Forge Sword) registered ✓");
        }

        // recipe_1: Brew Potions
        // Inputs: MagicOrb×1
        // Output: Potion×3
        {
            uint256[] memory ids   = new uint256[](1);
            ids[0] = 4;  // MagicOrb
            
            uint256[] memory amts  = new uint256[](1);
            amts[0] = 1;  // 1x MagicOrb
            
            items.registerRecipe(ids, amts, 2);  // outputId = 2 (Potion)
            console.log("[SetupCrafting] Recipe 1 (Brew Potions) registered ✓");
        }

        // recipe_2: Craft Epic Armor
        // Inputs: Shield×2 + MagicOrb×1
        // Output: Armor×1
        {
            uint256[] memory ids   = new uint256[](2);
            ids[0] = 1;  // Shield
            ids[1] = 4;  // MagicOrb
            
            uint256[] memory amts  = new uint256[](2);
            amts[0] = 2;  // 2x Shield
            amts[1] = 1;  // 1x MagicOrb
            
            items.registerRecipe(ids, amts, 3);  // outputId = 3 (Armor)
            console.log("[SetupCrafting] Recipe 2 (Craft Epic Armor) registered ✓");
        }

        // recipe_3: Infuse Magic Orb
        // Inputs: Potion×3
        // Output: MagicOrb×1
        {
            uint256[] memory ids   = new uint256[](1);
            ids[0] = 2;  // Potion
            
            uint256[] memory amts  = new uint256[](1);
            amts[0] = 3;  // 3x Potion
            
            items.registerRecipe(ids, amts, 4);  // outputId = 4 (MagicOrb)
            console.log("[SetupCrafting] Recipe 3 (Infuse Magic Orb) registered ✓");
        }

        vm.stopBroadcast();
        console.log("[SetupCrafting] All recipes registered! Crafting is ready.");
    }
}
