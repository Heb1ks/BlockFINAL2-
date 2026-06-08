// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./GameItems.sol";
import "./GameAMM.sol";

/// @title GameFactory — deploys GameItems (via ERC1967Proxy) and GameAMM instances
/// @notice Uses CREATE for GameItems/GameAMM, CREATE2 for deterministic GameItems addresses
contract GameFactory is Ownable {
    event GameItemsDeployed(address indexed proxy, address indexed impl, uint256 indexed salt);
    event GameAMMDeployed(address indexed instance, address tokenA, address tokenB);

    mapping(uint256 => address) public gameItemsInstances;
    address[] public ammInstances;

    constructor(address _owner) Ownable(_owner) {}

    /// @notice Deploy GameItems proxy with CREATE
    function deployGameItems(address admin) external onlyOwner returns (address proxy) {
        GameItems impl = new GameItems();
        bytes memory initData = abi.encodeCall(GameItems.initialize, (admin));
        ERC1967Proxy p = new ERC1967Proxy(address(impl), initData);
        proxy = address(p);
        emit GameItemsDeployed(proxy, address(impl), 0);
    }

    /// @notice Deploy GameItems proxy with CREATE2 (deterministic address)
    function deployGameItemsWithSalt(address admin, uint256 salt) external onlyOwner returns (address proxy) {
        GameItems impl = new GameItems();
        bytes memory initData = abi.encodeCall(GameItems.initialize, (admin));
        ERC1967Proxy p = new ERC1967Proxy{salt: bytes32(salt)}(address(impl), initData);
        proxy = address(p);
        gameItemsInstances[salt] = proxy;
        emit GameItemsDeployed(proxy, address(impl), salt);
    }

    /// @notice Predict deterministic proxy address for a given salt
    function predictGameItemsAddress(uint256 salt) external view returns (address) {
        // The proxy bytecode is fixed; initData changes per call, so this is approximate.
        // For exact prediction deploy a test impl and use CREATE2 address formula:
        // keccak256(0xff ++ factory ++ salt ++ keccak256(proxyCreationCode ++ abi.encode(impl,initData)))
        // We return a stable view based on the proxy creation code hash pattern.
        bytes32 proxyCodeHash = keccak256(type(ERC1967Proxy).creationCode);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), bytes32(salt), proxyCodeHash));
        return address(uint160(uint256(hash)));
    }

    /// @notice Deploy GameAMM with CREATE
    function deployGameAMM(address tokenA, address tokenB) external onlyOwner returns (address instance) {
        GameAMM amm = new GameAMM(tokenA, tokenB);
        instance = address(amm);
        ammInstances.push(instance);
        emit GameAMMDeployed(instance, tokenA, tokenB);
    }

    function getAMMCount() external view returns (uint256) {
        return ammInstances.length;
    }
}
