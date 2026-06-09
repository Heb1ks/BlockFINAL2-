// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/LootDrop.sol";
import "../src/GameItems.sol";
import "../src/mocks/MockVRFCoordinator.sol";

contract LootDropTest is Test {
    LootDrop lootDrop;
    GameItems items;
    MockVRFCoordinator vrf;

    address owner = address(0xA);
    address alice = address(0xB);

    bytes32 constant KEY_HASH = keccak256("testKeyHash");
    uint64 constant SUB_ID = 1;

    function setUp() public {
        GameItems impl = new GameItems();
        bytes memory data = abi.encodeCall(GameItems.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        items = GameItems(address(proxy));

        vrf = new MockVRFCoordinator();

        vm.prank(owner);
        lootDrop = new LootDrop(address(vrf), address(items), KEY_HASH, SUB_ID);

        // FIX: cache role hash BEFORE prank to avoid prank being consumed
        bytes32 minterRole = items.MINTER_ROLE();
        vm.prank(owner);
        items.grantRole(minterRole, address(lootDrop));
    }

    function test_requestLoot_basic() public {
        vm.prank(alice);
        uint256 requestId = lootDrop.requestLoot();
        assertGt(requestId, 0);
        assertEq(lootDrop.requestToPlayer(requestId), alice);
    }

    function test_requestLoot_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(false, true, false, false);
        emit LootDrop.LootRequested(0, alice);
        lootDrop.requestLoot();
    }

    function test_fulfillRandomWords_drop() public {
        vm.prank(alice);
        uint256 requestId = lootDrop.requestLoot();

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 499; // 499 % 1000 = 499 < 500 → drop

        uint256 itemId = 499 % 5;
        vrf.fulfillRandomWords(address(lootDrop), requestId, randomWords);
        assertEq(items.balanceOf(alice, itemId), 1);
    }

    function test_fulfillRandomWords_miss() public {
        vm.prank(alice);
        uint256 requestId = lootDrop.requestLoot();

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 500; // 500 % 1000 = 500, NOT < 500 → miss

        vrf.fulfillRandomWords(address(lootDrop), requestId, randomWords);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(items.balanceOf(alice, i), 0);
        }
    }

    function test_fulfillRandomWords_dropRateZero_alwaysMisses() public {
        vm.prank(owner);
        lootDrop.setDropRate(0);

        vm.prank(alice);
        uint256 requestId = lootDrop.requestLoot();
        uint256[] memory rw = new uint256[](1);
        rw[0] = 0;
        vrf.fulfillRandomWords(address(lootDrop), requestId, rw);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(items.balanceOf(alice, i), 0);
        }
    }

    function test_setDropRate_basic() public {
        vm.prank(owner);
        lootDrop.setDropRate(750);
        assertEq(lootDrop.dropRate(), 750);
    }

    function test_setDropRate_revertsAboveMax() public {
        vm.prank(owner);
        vm.expectRevert("Too high");
        lootDrop.setDropRate(1001);
    }

    function test_setDropRate_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        lootDrop.setDropRate(100);
    }

    function testFuzz_dropRate(uint256 randomWord, uint256 dropRate) public {
        dropRate = bound(dropRate, 0, 1000);
        vm.prank(owner);
        lootDrop.setDropRate(dropRate);

        vm.prank(alice);
        uint256 requestId = lootDrop.requestLoot();

        uint256[] memory rw = new uint256[](1);
        rw[0] = randomWord;
        vrf.fulfillRandomWords(address(lootDrop), requestId, rw);

        uint256 totalBalance;
        for (uint256 i = 0; i < 5; i++) {
            totalBalance += items.balanceOf(alice, i);
        }

        bool shouldDrop = (randomWord % 1000) < dropRate;
        if (shouldDrop) {
            assertEq(totalBalance, 1);
        } else {
            assertEq(totalBalance, 0);
        }
    }
}
