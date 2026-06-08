// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "./GameItems.sol";

contract LootDrop is VRFConsumerBaseV2Plus {
    GameItems public immutable GAME_ITEMS;

    bytes32 public keyHash;
    uint256 public subscriptionId;
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
        uint256 _subscriptionId
    )
    VRFConsumerBaseV2Plus(_vrfCoordinator)
    {
        GAME_ITEMS = GameItems(_gameItems);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
    }

    function requestLoot() external returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({ nativePayment: false })
                )
            })
        );
        requestToPlayer[requestId] = msg.sender;
        emit LootRequested(requestId, msg.sender);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
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
