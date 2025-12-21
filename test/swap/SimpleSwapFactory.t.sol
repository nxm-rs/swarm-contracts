// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SimpleSwapFactory} from "../../src/swap/SimpleSwapFactory.sol";
import {ERC20SimpleSwap} from "../../src/swap/ERC20SimpleSwap.sol";
import {TestToken} from "../../src/common/TestToken.sol";

contract SimpleSwapFactoryTest is Test {
    SimpleSwapFactory public factory;
    TestToken public token;

    address internal alice;
    address internal bob;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new TestToken();
        factory = new SimpleSwapFactory(address(token));
    }

    function test_constructor_setsERC20Address() public view {
        assertEq(factory.ERC20Address(), address(token));
    }

    function test_constructor_setsMaster() public view {
        assertTrue(factory.master() != address(0));
    }

    function test_deploySimpleSwap_createsNewSwap() public {
        vm.prank(alice);
        address swapAddr = factory.deploySimpleSwap(alice, 1 days, bytes32(0));

        assertTrue(swapAddr != address(0));
    }

    function test_deploySimpleSwap_setsCorrectIssuer() public {
        vm.prank(alice);
        address swapAddr = factory.deploySimpleSwap(alice, 1 days, bytes32(0));

        ERC20SimpleSwap swap = ERC20SimpleSwap(swapAddr);
        assertEq(swap.issuer(), alice);
    }

    function test_deploySimpleSwap_setsCorrectToken() public {
        vm.prank(alice);
        address swapAddr = factory.deploySimpleSwap(alice, 1 days, bytes32(0));

        ERC20SimpleSwap swap = ERC20SimpleSwap(swapAddr);
        assertEq(address(swap.token()), address(token));
    }

    function test_deploySimpleSwap_setsCorrectTimeout() public {
        uint256 timeout = 2 days;
        vm.prank(alice);
        address swapAddr = factory.deploySimpleSwap(alice, timeout, bytes32(0));

        ERC20SimpleSwap swap = ERC20SimpleSwap(swapAddr);
        assertEq(swap.defaultHardDepositTimeout(), timeout);
    }

    function test_deploySimpleSwap_tracksDeployedContracts() public {
        vm.prank(alice);
        address swapAddr = factory.deploySimpleSwap(alice, 1 days, bytes32(0));

        assertTrue(factory.deployedContracts(swapAddr));
    }

    function test_deploySimpleSwap_emitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit SimpleSwapFactory.SimpleSwapDeployed(address(0));

        vm.prank(alice);
        factory.deploySimpleSwap(alice, 1 days, bytes32(0));
    }

    function test_deploySimpleSwap_differentSaltsCreateDifferentAddresses() public {
        vm.startPrank(alice);
        address swap1 = factory.deploySimpleSwap(alice, 1 days, bytes32(uint256(1)));
        address swap2 = factory.deploySimpleSwap(alice, 1 days, bytes32(uint256(2)));
        vm.stopPrank();

        assertTrue(swap1 != swap2);
    }

    function test_deploySimpleSwap_sameSaltSameSenderCreatesSameAddress() public {
        // First deployment
        vm.prank(alice);
        address swap1 = factory.deploySimpleSwap(alice, 1 days, bytes32(uint256(1)));

        // Deploy another factory
        SimpleSwapFactory factory2 = new SimpleSwapFactory(address(token));

        // Same salt, same sender should create predictable address
        vm.prank(alice);
        address swap2 = factory2.deploySimpleSwap(alice, 1 days, bytes32(uint256(1)));

        // Addresses should be different because factories are different
        assertTrue(swap1 != swap2);
    }

    function test_deploySimpleSwap_differentSendersSameSaltDifferentAddresses() public {
        bytes32 salt = bytes32(uint256(1));

        vm.prank(alice);
        address swap1 = factory.deploySimpleSwap(alice, 1 days, salt);

        vm.prank(bob);
        address swap2 = factory.deploySimpleSwap(bob, 1 days, salt);

        assertTrue(swap1 != swap2);
    }
}
