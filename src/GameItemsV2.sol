// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameItems.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract GameItemsV2 is GameItems, ReentrancyGuard {
    /// @custom:storage-location erc7201:gamefi.gameitems.v2
    bool public craftingEnabled;

    mapping(bytes32 => bool) public craftingRecipes;

    event CraftingToggled(bool enabled);
    event RecipeRegistered(uint256[] inputIds, uint256[] inputAmounts, uint256 outputId);
    event ItemCrafted(address indexed player, uint256 outputId, uint256 amount);

    /// @notice Toggle crafting on/off — callable by admin via governance
    function setCraftingEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        craftingEnabled = enabled;
        emit CraftingToggled(enabled);
    }

    /// @notice Register a crafting recipe
    function registerRecipe(
        uint256[] calldata inputIds,
        uint256[] calldata inputAmounts,
        uint256 outputId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(inputIds.length == inputAmounts.length, "Length mismatch");
        bytes32 key = keccak256(abi.encode(inputIds, inputAmounts, outputId));
        craftingRecipes[key] = true;
        emit RecipeRegistered(inputIds, inputAmounts, outputId);
    }

    function craft(
        uint256[] calldata inputIds,
        uint256[] calldata inputAmounts,
        uint256 outputId,
        uint256 outputAmount
    ) external nonReentrant{
        // Checks
        require(craftingEnabled, "Crafting disabled");
        require(inputIds.length == inputAmounts.length, "Length mismatch");

        bytes32 key = keccak256(abi.encode(inputIds, inputAmounts, outputId));
        require(craftingRecipes[key], "Invalid recipe");

        // Effects (state changes before interactions)
        // Note: _burnBatch and _mint are internal state-changing operations
        // Burn inputs first
        _burnBatch(msg.sender, inputIds, inputAmounts);

        // Then mint output
        _mint(msg.sender, outputId, outputAmount, "");
        
        // Interactions & Events (after all state changes)
        emit ItemCrafted(msg.sender, outputId, outputAmount);
    }
}
