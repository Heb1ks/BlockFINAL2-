// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GameFactory.sol";
import "../src/GameItems.sol";
import "../src/mocks/MockERC20.sol";

contract GameFactoryTest is Test {
    GameFactory factory;
    address owner = address(0xA);
    address admin = address(0xB);
    address alice = address(0xC);

    function setUp() public {
        vm.prank(owner);
        factory = new GameFactory(owner);
    }

    //  deployGameItems (CREATE) 

    function test_deployGameItems_basic() public {
        vm.prank(owner);
        address proxy = factory.deployGameItems(admin);

        assertTrue(proxy != address(0));
        assertTrue(proxy.code.length > 0);

        // Proxy should have initialized GameItems with admin roles
        GameItems items = GameItems(proxy);
        assertTrue(items.hasRole(items.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(items.hasRole(items.MINTER_ROLE(), admin));
    }

    function test_deployGameItems_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.deployGameItems(admin);
    }

    function test_deployGameItems_multipleInstances() public {
        vm.prank(owner);
        address a1 = factory.deployGameItems(admin);
        vm.prank(owner);
        address a2 = factory.deployGameItems(alice);

        assertTrue(a1 != a2);

        GameItems i1 = GameItems(a1);
        GameItems i2 = GameItems(a2);
        assertTrue(i1.hasRole(i1.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(i2.hasRole(i2.DEFAULT_ADMIN_ROLE(), alice));
    }

    //  deployGameItemsWithSalt (CREATE2) 

    function test_deployGameItemsWithSalt_basic() public {
        uint256 salt = 42;
        vm.prank(owner);
        address proxy = factory.deployGameItemsWithSalt(admin, salt);

        assertTrue(proxy != address(0));
        assertTrue(proxy.code.length > 0);
        assertEq(factory.gameItemsInstances(salt), proxy);

        GameItems items = GameItems(proxy);
        assertTrue(items.hasRole(items.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_deployGameItemsWithSalt_differentSaltsDifferentAddresses() public {
        vm.prank(owner);
        address a1 = factory.deployGameItemsWithSalt(admin, 1);
        vm.prank(owner);
        address a2 = factory.deployGameItemsWithSalt(admin, 2);
        assertTrue(a1 != a2);
    }

    function test_deployGameItemsWithSalt_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.deployGameItemsWithSalt(admin, 99);
    }

    //  predictGameItemsAddress 

    function test_predictAddress_deterministicForSameSalt() public view {
        address p1 = factory.predictGameItemsAddress(7);
        address p2 = factory.predictGameItemsAddress(7);
        assertEq(p1, p2);
    }

    function test_predictAddress_differentSaltsGiveDifferentAddresses() public view {
        address p1 = factory.predictGameItemsAddress(1);
        address p2 = factory.predictGameItemsAddress(2);
        assertTrue(p1 != p2);
    }

    function test_predictAddress_returnsNonZero() public view {
        address predicted = factory.predictGameItemsAddress(123);
        assertTrue(predicted != address(0));
    }

    //  deployGameAMM 

    function test_deployGameAMM_basic() public {
        MockERC20 tA = new MockERC20("A", "A", 18);
        MockERC20 tB = new MockERC20("B", "B", 18);

        vm.prank(owner);
        address amm = factory.deployGameAMM(address(tA), address(tB));

        assertTrue(amm != address(0));
        assertEq(factory.getAMMCount(), 1);
        assertEq(factory.ammInstances(0), amm);
    }

    function test_deployGameAMM_revertsIfNotOwner() public {
        MockERC20 tA = new MockERC20("A", "A", 18);
        MockERC20 tB = new MockERC20("B", "B", 18);
        vm.prank(alice);
        vm.expectRevert();
        factory.deployGameAMM(address(tA), address(tB));
    }

    function test_deployGameAMM_multipleInstances() public {
        MockERC20 tA = new MockERC20("A", "A", 18);
        MockERC20 tB = new MockERC20("B", "B", 18);
        MockERC20 tC = new MockERC20("C", "C", 18);

        vm.startPrank(owner);
        address amm1 = factory.deployGameAMM(address(tA), address(tB));
        address amm2 = factory.deployGameAMM(address(tA), address(tC));
        vm.stopPrank();

        assertEq(factory.getAMMCount(), 2);
        assertTrue(amm1 != amm2);
    }

    function test_deployGameAMM_correctTokens() public {
        MockERC20 tA = new MockERC20("A", "A", 18);
        MockERC20 tB = new MockERC20("B", "B", 18);

        vm.prank(owner);
        address ammAddr = factory.deployGameAMM(address(tA), address(tB));

        GameAMM amm = GameAMM(ammAddr);
        assertEq(address(amm.TOKEN_A()), address(tA));
        assertEq(address(amm.TOKEN_B()), address(tB));
    }
}
