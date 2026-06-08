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

    //  Admin

    function setCraftingEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        craftingEnabled = enabled;
        emit CraftingToggled(enabled);
    }

    function registerRecipe(uint256[] calldata inputIds, uint256[] calldata inputAmounts, uint256 outputId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(inputIds.length == inputAmounts.length, "Length mismatch");
        bytes32 key = keccak256(abi.encode(inputIds, inputAmounts, outputId));
        craftingRecipes[key] = true;
        emit RecipeRegistered(inputIds, inputAmounts, outputId);
    }

    //  Crafting

    function craft(uint256[] calldata inputIds, uint256[] calldata inputAmounts, uint256 outputId, uint256 outputAmount)
        external
        nonReentrant
    {
        require(craftingEnabled, "Crafting disabled");
        require(inputIds.length == inputAmounts.length, "Length mismatch");

        bytes32 key = keccak256(abi.encode(inputIds, inputAmounts, outputId));
        require(craftingRecipes[key], "Invalid recipe");

        _burnBatch(msg.sender, inputIds, inputAmounts);
        _mint(msg.sender, outputId, outputAmount, "");

        emit ItemCrafted(msg.sender, outputId, outputAmount);
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data)
        public
        override
        nonReentrant
    {
        super.safeTransferFrom(from, to, id, value, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public override nonReentrant {
        super.safeBatchTransferFrom(from, to, ids, values, data);
    }

    function mint(address to, uint256 id, uint256 amount) external override onlyRole(MINTER_ROLE) nonReentrant {
        _mint(to, id, amount, "");
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts)
        external
        override
        onlyRole(MINTER_ROLE)
        nonReentrant
    {
        _mintBatch(to, ids, amounts, "");
    }
}
