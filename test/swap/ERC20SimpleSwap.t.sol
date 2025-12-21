// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { ERC20SimpleSwap } from "../../src/swap/ERC20SimpleSwap.sol";
import { SimpleSwapFactory } from "../../src/swap/SimpleSwapFactory.sol";
import { TestToken } from "../../src/common/TestToken.sol";
import { EIP712Helper } from "../helpers/EIP712Helper.sol";

contract ERC20SimpleSwapTest is Test, EIP712Helper {
    ERC20SimpleSwap public swap;
    SimpleSwapFactory public factory;
    TestToken public token;

    // Test accounts with known private keys
    uint256 internal issuerPk = 0x1;
    uint256 internal beneficiaryPk = 0x2;
    uint256 internal alicePk = 0x3;

    address internal issuer;
    address internal beneficiary;
    address internal alice;

    uint256 internal constant DEFAULT_HARDDEPOSIT_TIMEOUT = 1 days;
    uint256 internal constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        issuer = vm.addr(issuerPk);
        beneficiary = vm.addr(beneficiaryPk);
        alice = vm.addr(alicePk);

        vm.label(issuer, "issuer");
        vm.label(beneficiary, "beneficiary");
        vm.label(alice, "alice");

        // Deploy token
        token = new TestToken();

        // Deploy factory
        factory = new SimpleSwapFactory(address(token));

        // Deploy swap via factory
        vm.prank(issuer);
        address swapAddr = factory.deploySimpleSwap(issuer, DEFAULT_HARDDEPOSIT_TIMEOUT, bytes32(0));
        swap = ERC20SimpleSwap(swapAddr);

        // Fund the swap
        token.mint(address(swap), INITIAL_BALANCE);
    }

    // ==================== Initialization Tests ====================

    function test_init_setsIssuer() public view {
        assertEq(swap.issuer(), issuer);
    }

    function test_init_setsToken() public view {
        assertEq(address(swap.token()), address(token));
    }

    function test_init_setsDefaultTimeout() public view {
        assertEq(swap.defaultHardDepositTimeout(), DEFAULT_HARDDEPOSIT_TIMEOUT);
    }

    function test_init_revertsIfAlreadyInitialized() public {
        vm.expectRevert("already initialized");
        swap.init(alice, address(token), DEFAULT_HARDDEPOSIT_TIMEOUT);
    }

    // ==================== Balance Tests ====================

    function test_balance_returnsTokenBalance() public view {
        assertEq(swap.balance(), INITIAL_BALANCE);
    }

    function test_liquidBalance_equalsBalanceWithNoHardDeposits() public view {
        assertEq(swap.liquidBalance(), INITIAL_BALANCE);
    }

    // ==================== Cheque Cashing Tests ====================

    function test_cashChequeBeneficiary_transfersTokens() public {
        uint256 amount = 100 ether;
        bytes memory sig = signCheque(issuerPk, address(swap), beneficiary, amount);

        uint256 balanceBefore = token.balanceOf(beneficiary);

        vm.prank(beneficiary);
        swap.cashChequeBeneficiary(beneficiary, amount, sig);

        assertEq(token.balanceOf(beneficiary), balanceBefore + amount);
    }

    function test_cashChequeBeneficiary_updatesPaidOut() public {
        uint256 amount = 100 ether;
        bytes memory sig = signCheque(issuerPk, address(swap), beneficiary, amount);

        vm.prank(beneficiary);
        swap.cashChequeBeneficiary(beneficiary, amount, sig);

        assertEq(swap.paidOut(beneficiary), amount);
    }

    function test_cashChequeBeneficiary_emitsEvent() public {
        uint256 amount = 100 ether;
        bytes memory sig = signCheque(issuerPk, address(swap), beneficiary, amount);

        vm.expectEmit(true, true, true, true);
        emit ERC20SimpleSwap.ChequeCashed(beneficiary, beneficiary, beneficiary, amount, amount, 0);

        vm.prank(beneficiary);
        swap.cashChequeBeneficiary(beneficiary, amount, sig);
    }

    function test_cashChequeBeneficiary_revertsWithInvalidSignature() public {
        uint256 amount = 100 ether;
        // Sign with wrong key
        bytes memory sig = signCheque(alicePk, address(swap), beneficiary, amount);

        vm.prank(beneficiary);
        vm.expectRevert("invalid issuer signature");
        swap.cashChequeBeneficiary(beneficiary, amount, sig);
    }

    function test_cashChequeBeneficiary_issuerCanSkipSignature() public {
        uint256 amount = 100 ether;

        vm.prank(issuer);
        swap.cashChequeBeneficiary(beneficiary, amount, "");

        assertEq(swap.paidOut(issuer), amount);
    }

    function test_cashChequeBeneficiary_cumulativePayouts() public {
        uint256 firstAmount = 50 ether;
        uint256 secondAmount = 150 ether; // Cumulative, not incremental

        bytes memory sig1 = signCheque(issuerPk, address(swap), beneficiary, firstAmount);
        bytes memory sig2 = signCheque(issuerPk, address(swap), beneficiary, secondAmount);

        vm.startPrank(beneficiary);
        swap.cashChequeBeneficiary(beneficiary, firstAmount, sig1);
        swap.cashChequeBeneficiary(beneficiary, secondAmount, sig2);
        vm.stopPrank();

        assertEq(swap.paidOut(beneficiary), secondAmount);
        assertEq(token.balanceOf(beneficiary), secondAmount);
    }

    // ==================== Hard Deposit Tests ====================

    function test_increaseHardDeposit_onlyIssuer() public {
        vm.prank(alice);
        vm.expectRevert("SimpleSwap: not issuer");
        swap.increaseHardDeposit(beneficiary, 100 ether);
    }

    function test_increaseHardDeposit_updatesAmount() public {
        vm.prank(issuer);
        swap.increaseHardDeposit(beneficiary, 100 ether);

        (uint256 amount,,,) = swap.hardDeposits(beneficiary);
        assertEq(amount, 100 ether);
    }

    function test_increaseHardDeposit_updatesTotal() public {
        vm.prank(issuer);
        swap.increaseHardDeposit(beneficiary, 100 ether);

        assertEq(swap.totalHardDeposit(), 100 ether);
    }

    function test_increaseHardDeposit_reducesLiquidBalance() public {
        vm.prank(issuer);
        swap.increaseHardDeposit(beneficiary, 100 ether);

        assertEq(swap.liquidBalance(), INITIAL_BALANCE - 100 ether);
    }

    function test_prepareDecreaseHardDeposit_onlyIssuer() public {
        vm.prank(issuer);
        swap.increaseHardDeposit(beneficiary, 100 ether);

        vm.prank(alice);
        vm.expectRevert("SimpleSwap: not issuer");
        swap.prepareDecreaseHardDeposit(beneficiary, 50 ether);
    }

    function test_decreaseHardDeposit_afterTimeout() public {
        vm.prank(issuer);
        swap.increaseHardDeposit(beneficiary, 100 ether);

        vm.prank(issuer);
        swap.prepareDecreaseHardDeposit(beneficiary, 50 ether);

        // Warp past timeout
        vm.warp(block.timestamp + DEFAULT_HARDDEPOSIT_TIMEOUT + 1);

        swap.decreaseHardDeposit(beneficiary);

        (uint256 amount,,,) = swap.hardDeposits(beneficiary);
        assertEq(amount, 50 ether);
    }

    function test_decreaseHardDeposit_revertsBeforeTimeout() public {
        vm.prank(issuer);
        swap.increaseHardDeposit(beneficiary, 100 ether);

        vm.prank(issuer);
        swap.prepareDecreaseHardDeposit(beneficiary, 50 ether);

        vm.expectRevert("deposit not yet timed out");
        swap.decreaseHardDeposit(beneficiary);
    }

    // ==================== Withdraw Tests ====================

    function test_withdraw_onlyIssuer() public {
        vm.prank(alice);
        vm.expectRevert("not issuer");
        swap.withdraw(100 ether);
    }

    function test_withdraw_transfersToIssuer() public {
        uint256 amount = 100 ether;
        uint256 balanceBefore = token.balanceOf(issuer);

        vm.prank(issuer);
        swap.withdraw(amount);

        assertEq(token.balanceOf(issuer), balanceBefore + amount);
    }

    function test_withdraw_revertsIfExceedsLiquidBalance() public {
        // Set up hard deposit
        vm.prank(issuer);
        swap.increaseHardDeposit(beneficiary, 900 ether);

        // Try to withdraw more than liquid balance
        vm.prank(issuer);
        vm.expectRevert("liquidBalance not sufficient");
        swap.withdraw(200 ether);
    }

    // ==================== Bounced Cheque Tests ====================

    function test_bounced_setWhenInsufficientFunds() public {
        // Cash a cheque for more than balance
        uint256 amount = INITIAL_BALANCE + 100 ether;
        bytes memory sig = signCheque(issuerPk, address(swap), beneficiary, amount);

        vm.prank(beneficiary);
        swap.cashChequeBeneficiary(beneficiary, amount, sig);

        assertTrue(swap.bounced());
    }
}
