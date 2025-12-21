// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { PriceOracle } from "../../src/swap/SwapPriceOracle.sol";

/// @title SwapPriceOracleTest
/// @notice Tests for the Swap PriceOracle contract
contract SwapPriceOracleTest is Test {
    PriceOracle public oracle;

    address public owner;
    address public user;

    uint256 public constant INITIAL_PRICE = 100;
    uint256 public constant INITIAL_DEDUCTION = 50;

    event PriceUpdate(uint256 price);
    event ChequeValueDeductionUpdate(uint256 chequeValueDeduction);

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        oracle = new PriceOracle(INITIAL_PRICE, INITIAL_DEDUCTION);
    }

    // ==================== Constructor Tests ====================

    function test_constructor_setsPrice() public view {
        assertEq(oracle.price(), INITIAL_PRICE);
    }

    function test_constructor_setsChequeValueDeduction() public view {
        assertEq(oracle.chequeValueDeduction(), INITIAL_DEDUCTION);
    }

    function test_constructor_setsOwner() public view {
        assertEq(oracle.owner(), owner);
    }

    function test_constructor_withZeroValues() public {
        PriceOracle zeroOracle = new PriceOracle(0, 0);
        assertEq(zeroOracle.price(), 0);
        assertEq(zeroOracle.chequeValueDeduction(), 0);
    }

    function test_constructor_withLargeValues() public {
        uint256 largePrice = type(uint256).max;
        uint256 largeDeduction = type(uint256).max;
        PriceOracle largeOracle = new PriceOracle(largePrice, largeDeduction);
        assertEq(largeOracle.price(), largePrice);
        assertEq(largeOracle.chequeValueDeduction(), largeDeduction);
    }

    // ==================== getPrice Tests ====================

    function test_getPrice_returnsCorrectValues() public view {
        (uint256 price, uint256 deduction) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
        assertEq(deduction, INITIAL_DEDUCTION);
    }

    function test_getPrice_afterUpdate() public {
        uint256 newPrice = 200;
        oracle.updatePrice(newPrice);

        (uint256 price, uint256 deduction) = oracle.getPrice();
        assertEq(price, newPrice);
        assertEq(deduction, INITIAL_DEDUCTION);
    }

    // ==================== updatePrice Tests ====================

    function test_updatePrice_success() public {
        uint256 newPrice = 200;
        oracle.updatePrice(newPrice);
        assertEq(oracle.price(), newPrice);
    }

    function test_updatePrice_emitsEvent() public {
        uint256 newPrice = 200;

        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(newPrice);

        oracle.updatePrice(newPrice);
    }

    function test_updatePrice_revertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        oracle.updatePrice(200);
    }

    function test_updatePrice_toZero() public {
        oracle.updatePrice(0);
        assertEq(oracle.price(), 0);
    }

    function test_updatePrice_multipleUpdates() public {
        oracle.updatePrice(100);
        assertEq(oracle.price(), 100);

        oracle.updatePrice(200);
        assertEq(oracle.price(), 200);

        oracle.updatePrice(50);
        assertEq(oracle.price(), 50);
    }

    // ==================== updateChequeValueDeduction Tests ====================

    function test_updateChequeValueDeduction_success() public {
        uint256 newDeduction = 100;
        oracle.updateChequeValueDeduction(newDeduction);
        assertEq(oracle.chequeValueDeduction(), newDeduction);
    }

    function test_updateChequeValueDeduction_emitsEvent() public {
        uint256 newDeduction = 100;

        vm.expectEmit(true, true, true, true);
        emit ChequeValueDeductionUpdate(newDeduction);

        oracle.updateChequeValueDeduction(newDeduction);
    }

    function test_updateChequeValueDeduction_revertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        oracle.updateChequeValueDeduction(100);
    }

    function test_updateChequeValueDeduction_toZero() public {
        oracle.updateChequeValueDeduction(0);
        assertEq(oracle.chequeValueDeduction(), 0);
    }

    function test_updateChequeValueDeduction_multipleUpdates() public {
        oracle.updateChequeValueDeduction(100);
        assertEq(oracle.chequeValueDeduction(), 100);

        oracle.updateChequeValueDeduction(200);
        assertEq(oracle.chequeValueDeduction(), 200);

        oracle.updateChequeValueDeduction(25);
        assertEq(oracle.chequeValueDeduction(), 25);
    }

    // ==================== Combined Update Tests ====================

    function test_updateBothValues_independent() public {
        uint256 newPrice = 300;
        uint256 newDeduction = 150;

        oracle.updatePrice(newPrice);
        oracle.updateChequeValueDeduction(newDeduction);

        (uint256 price, uint256 deduction) = oracle.getPrice();
        assertEq(price, newPrice);
        assertEq(deduction, newDeduction);
    }

    function test_updatePrice_doesNotAffectDeduction() public {
        uint256 originalDeduction = oracle.chequeValueDeduction();
        oracle.updatePrice(999);
        assertEq(oracle.chequeValueDeduction(), originalDeduction);
    }

    function test_updateDeduction_doesNotAffectPrice() public {
        uint256 originalPrice = oracle.price();
        oracle.updateChequeValueDeduction(999);
        assertEq(oracle.price(), originalPrice);
    }

    // ==================== Fuzz Tests ====================

    function testFuzz_updatePrice(uint256 newPrice) public {
        oracle.updatePrice(newPrice);
        assertEq(oracle.price(), newPrice);
    }

    function testFuzz_updateChequeValueDeduction(uint256 newDeduction) public {
        oracle.updateChequeValueDeduction(newDeduction);
        assertEq(oracle.chequeValueDeduction(), newDeduction);
    }

    function testFuzz_constructor(uint256 initPrice, uint256 initDeduction) public {
        PriceOracle fuzzOracle = new PriceOracle(initPrice, initDeduction);
        assertEq(fuzzOracle.price(), initPrice);
        assertEq(fuzzOracle.chequeValueDeduction(), initDeduction);
    }
}
