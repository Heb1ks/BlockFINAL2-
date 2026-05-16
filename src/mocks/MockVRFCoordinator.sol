// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/// @title MockVRFCoordinator — test double for Chainlink VRF Coordinator V2
contract MockVRFCoordinator {
    uint256 private _nonce;

    event RandomWordsRequested(uint256 requestId, address requester);

    function requestRandomWords(
        bytes32,  // keyHash
        uint64,   // subId
        uint16,   // confirmations
        uint32,   // callbackGasLimit
        uint32    // numWords
    ) external returns (uint256 requestId) {
        requestId = ++_nonce;
        emit RandomWordsRequested(requestId, msg.sender);
    }

    /// @notice Called by tests to simulate VRF callback
    function fulfillRandomWords(
        address consumer,
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        VRFConsumerBaseV2(consumer).rawFulfillRandomWords(requestId, randomWords);
    }
}
