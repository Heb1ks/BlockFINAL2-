// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/// @title MockVRFCoordinator — test double for Chainlink VRF Coordinator V2Plus
contract MockVRFCoordinator {
    uint256 private _nonce;

    event RandomWordsRequested(uint256 requestId, address requester);

    /// @dev Matches IVRFCoordinatorV2Plus — takes a single struct, not 5 args
    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest calldata /* req */
    )
        external
        returns (uint256 requestId)
    {
        requestId = ++_nonce;
        emit RandomWordsRequested(requestId, msg.sender);
    }

    /// @notice Called by tests to simulate a VRF callback
    function fulfillRandomWords(address consumer, uint256 requestId, uint256[] memory randomWords) external {
        // Must use VRFConsumerBaseV2Plus, not V2, so the coordinator check passes
        VRFConsumerBaseV2Plus(consumer).rawFulfillRandomWords(requestId, randomWords);
    }
}
