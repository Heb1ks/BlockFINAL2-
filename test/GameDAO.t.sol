// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/GameDAO.sol";
import "../src/GameToken.sol";

contract GameDAOTest is Test {
    GameToken token;
    TimelockController timelock;
    GameDAO dao;

    address deployer = address(0xAA);
    address proposer = address(0xBB);
    address voter1 = address(0xCC);
    address voter2 = address(0xDD);

    uint256 constant MIN_DELAY = 2 days;
    // GovernorSettings stores delay/period in clock units.
    // If token clock = block.number: 1 days = 86400 blocks, 1 weeks = 604800 blocks
    // We advance both time and blocks to cover both cases.
    uint256 constant VOTING_DELAY = 300; // потом поменять на 86400 для 1 дня
    uint256 constant VOTING_PERIOD = 604800; // 1 week in blocks

    function setUp() public {
        vm.startPrank(deployer);

        token = new GameToken(deployer);

        address[] memory empty = new address[](0);
        timelock = new TimelockController(MIN_DELAY, empty, empty, deployer);
        dao = new GameDAO(IVotes(address(token)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(dao));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(dao));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(dao));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        token.mint(proposer, 5_000e18);
        token.mint(voter1, 50_000e18);
        token.mint(voter2, 50_000e18);
        vm.stopPrank();

        vm.prank(proposer);
        token.delegate(proposer);
        vm.prank(voter1);
        token.delegate(voter1);
        vm.prank(voter2);
        token.delegate(voter2);

        // Roll forward so checkpoints are in the past
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 2);
    }

    //  Parameters

    function test_votingDelay_isOneDay() public view {
        assertEq(dao.votingDelay(), VOTING_DELAY );
    }

    function test_votingPeriod_isOneWeek() public view {
        assertEq(dao.votingPeriod(), 1 weeks);
    }

    function test_quorumFraction_is4pct() public view {
        assertEq(dao.quorumNumerator(), 4);
    }

    function test_proposalThreshold_is1pct() public view {
        assertEq(dao.proposalThreshold(), 1_000e18);
    }

    //  Helpers

    function _makeProposal()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(token);
        calldatas[0] = abi.encodeCall(GameToken.mint, (deployer, 1e18));
        desc = "Proposal #1: mint 1 token";
    }

    function _skipVotingDelay() internal {
        // Advance enough for both block-based and timestamp-based clocks
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.warp(block.timestamp + 1 days + 1);
    }

    function _skipVotingPeriod() internal {
        vm.roll(block.number + VOTING_PERIOD + 1);
        vm.warp(block.timestamp + 1 weeks + 1);
    }

    //  Propose

    function test_propose_succeeds() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = _makeProposal();
        vm.prank(proposer);
        uint256 proposalId = dao.propose(t, v, c, d);
        assertGt(proposalId, 0);
        assertEq(uint8(dao.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
    }

    function test_propose_revertsInsufficientThreshold() public {
        address poorProposer = address(0xFF);
        vm.prank(deployer);
        token.mint(poorProposer, 100e18);
        vm.prank(poorProposer);
        token.delegate(poorProposer);
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 2);

        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = _makeProposal();
        vm.prank(poorProposer);
        vm.expectRevert();
        dao.propose(t, v, c, d);
    }

    //  Vote

    function test_castVote_succeeds() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = _makeProposal();
        vm.prank(proposer);
        uint256 proposalId = dao.propose(t, v, c, d);

        _skipVotingDelay();

        vm.prank(voter1);
        dao.castVote(proposalId, 1);

        (uint256 against, uint256 forVotes,) = dao.proposalVotes(proposalId);
        assertGt(forVotes, 0);
        assertEq(against, 0);
    }

    function test_proposalState_active_afterDelay() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = _makeProposal();
        vm.prank(proposer);
        uint256 proposalId = dao.propose(t, v, c, d);

        _skipVotingDelay();

        assertEq(uint8(dao.state(proposalId)), uint8(IGovernor.ProposalState.Active));
    }

    function test_proposalState_defeated_noQuorum() public {
        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = _makeProposal();
        vm.prank(proposer);
        uint256 proposalId = dao.propose(t, v, c, d);

        _skipVotingDelay();
        _skipVotingPeriod();

        assertEq(uint8(dao.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_fullLifecycle_propose_vote_queue_execute() public {
        vm.prank(deployer);
        token.transferOwnership(address(timelock));

        (address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = _makeProposal();

        vm.prank(proposer);
        uint256 proposalId = dao.propose(t, v, c, d);

        _skipVotingDelay();

        vm.prank(voter1);
        dao.castVote(proposalId, 1);
        vm.prank(voter2);
        dao.castVote(proposalId, 1);

        _skipVotingPeriod();

        assertEq(uint8(dao.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        bytes32 descHash = keccak256(bytes(d));
        dao.queue(t, v, c, descHash);
        assertEq(uint8(dao.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + MIN_DELAY + 1);
        dao.execute(t, v, c, descHash);
        assertEq(uint8(dao.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    //  Fuzz

    function testFuzz_votingPower_proportional(uint256 mintAmount) public {
        mintAmount = bound(mintAmount, 1e18, 100_000e18);
        address user = address(0x999);
        vm.prank(deployer);
        token.mint(user, mintAmount);
        vm.prank(user);
        token.delegate(user);
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 2);
        assertEq(dao.getVotes(user, block.number - 1), mintAmount);
    }
}
