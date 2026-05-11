// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "./GameItems.sol";

contract LootDrop is VRFConsumerBaseV2, Ownable {
    VRFCoordinatorV2Interface public immutable COORDINATOR;
    GameItems public immutable GAME_ITEMS;

    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant CALLBACK_GAS_LIMIT = 200000;
    uint32 public constant NUM_WORDS = 1;

    uint256 public dropRate = 500;
    uint256 public constant DENOMINATOR = 1000;

    mapping(uint256 => address) public requestToPlayer;

    event LootRequested(uint256 indexed requestId, address indexed player);
    event LootDropped(uint256 indexed requestId, address indexed player, uint256 itemId);
    event LootMissed(uint256 indexed requestId, address indexed player);

    constructor(
        address _vrfCoordinator,
        address _gameItems,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address _owner
    ) VRFConsumerBaseV2(_vrfCoordinator) Ownable(_owner) {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        GAME_ITEMS = GameItems(_gameItems);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
    }

    function requestLoot() external returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );
        requestToPlayer[requestId] = msg.sender;
        emit LootRequested(requestId, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address player = requestToPlayer[requestId];
        uint256 rand = randomWords[0];

        if (rand % DENOMINATOR < dropRate) {
            uint256 itemId = rand % 5;
            GAME_ITEMS.mint(player, itemId, 1);
            emit LootDropped(requestId, player, itemId);
        } else {
            emit LootMissed(requestId, player);
        }
    }

    function setDropRate(uint256 newRate) external onlyOwner {
        require(newRate <= DENOMINATOR, "Too high");
        dropRate = newRate;
    }
}