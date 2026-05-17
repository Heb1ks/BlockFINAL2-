// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameItems.sol";

/// @title GameItemsV2 — UUPS upgrade of GameItems adding on-chain crafting
/// @notice V1 → V2 upgrade path:
///   1. Deploy GameItemsV2 implementation
///   2. Call upgradeToAndCall(address(v2), "") from UPGRADER_ROLE via Timelock
///   3. New `craft()` function becomes available; all V1 state is preserved
///      because storage layout is append-only (new vars added at the end).
/// @dev Storage layout — V1 slots are untouched:
///   [OZ ERC1155 slots]  [OZ AccessControl slots]  [OZ UUPS slots]
///   V2 appends: craftingEnabled (bool) at the next free slot.
contract GameItemsV2 is GameItems {
    /// @custom:storage-location erc7201:gamefi.gameitems.v2
    bool public craftingEnabled;

    mapping(bytes32 => bool) public craftingRecipes; // keccak(inputs) => valid

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

    /// @notice Craft items by burning inputs and minting the output
    /// @dev Follows Checks-Effects-Interactions pattern to prevent reentrancy
    function craft(
        uint256[] calldata inputIds,
        uint256[] calldata inputAmounts,
        uint256 outputId,
        uint256 outputAmount
    ) external {
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
