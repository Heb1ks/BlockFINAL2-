// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./GameItems.sol";
import "./GameAMM.sol";

/// @title 
contract GameFactory is Ownable {

    event GameItemsDeployed(address indexed instance, uint256 indexed salt);
    event GameAMMDeployed(address indexed instance, address tokenA, address tokenB);

    mapping(uint256 => address) public gameItemsInstances;
    address[] public ammInstances;

    constructor(address _owner) Ownable(_owner) {}

    /// @notice Deploy GameItems with CREATE 
    function deployGameItems(address admin) external onlyOwner returns (address instance) {
        GameItems items = new GameItems();
        items.initialize(admin);
        instance = address(items);
        emit GameItemsDeployed(instance, 0);
    }

    /// @notice Deploy GameItems with CREATE2 
    function deployGameItemsWithSalt(address admin, uint256 salt)
        external onlyOwner returns (address instance)
    {
        bytes32 saltBytes = bytes32(salt);
        GameItems items = new GameItems{salt: saltBytes}();
        items.initialize(admin);
        instance = address(items);
        gameItemsInstances[salt] = instance;
        emit GameItemsDeployed(instance, salt);
    }

    /// @notice Predict address before deploying with crate2
    function predictGameItemsAddress(uint256 salt) external view returns (address) {
        bytes32 saltBytes = bytes32(salt);
        bytes memory bytecode = type(GameItems).creationCode;
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), saltBytes, keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }

    /// @notice Deploy GameAMM with create
    function deployGameAMM(address tokenA, address tokenB)
        external onlyOwner returns (address instance)
    {
        GameAMM amm = new GameAMM(tokenA, tokenB);
        instance = address(amm);
        ammInstances.push(instance);
        emit GameAMMDeployed(instance, tokenA, tokenB);
    }

    function getAMMCount() external view returns (uint256) {
        return ammInstances.length;
    }
}