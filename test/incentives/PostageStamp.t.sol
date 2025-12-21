// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PostageStamp} from "../../src/incentives/PostageStamp.sol";
import {TestToken} from "../../src/common/TestToken.sol";

contract PostageStampTest is Test {
    PostageStamp public postage;
    TestToken public token;

    address internal deployer;
    address internal oracle;
    address internal stamper;
    address internal redistributor;

    uint8 internal constant MIN_BUCKET_DEPTH = 16;
    uint256 internal constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        oracle = makeAddr("oracle");
        stamper = makeAddr("stamper");
        redistributor = makeAddr("redistributor");

        vm.startPrank(deployer);

        token = new TestToken();
        postage = new PostageStamp(address(token), MIN_BUCKET_DEPTH);

        // Grant roles
        postage.grantRoles(oracle, postage.PRICE_ORACLE_ROLE());
        postage.grantRoles(redistributor, postage.REDISTRIBUTOR_ROLE());

        // Fund stamper
        token.mint(stamper, INITIAL_BALANCE);

        vm.stopPrank();

        // Approve postage contract
        vm.prank(stamper);
        token.approve(address(postage), type(uint256).max);
    }

    // ==================== Initialization Tests ====================

    function test_constructor_setsToken() public view {
        assertEq(postage.bzzToken(), address(token));
    }

    function test_constructor_setsMinBucketDepth() public view {
        assertEq(postage.minimumBucketDepth(), MIN_BUCKET_DEPTH);
    }

    // ==================== Batch Creation Tests ====================

    function test_createBatch_success() public {
        uint8 depth = 20;
        uint8 bucketDepth = 17;
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        // Balance must exceed minimumInitialBalancePerChunk (minimumValidityBlocks * price)
        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(
            stamper,
            balancePerChunk,
            depth,
            bucketDepth,
            nonce,
            false
        );

        assertEq(postage.batchOwner(batchId), stamper);
        assertEq(postage.batchDepth(batchId), depth);
        assertEq(postage.batchBucketDepth(batchId), bucketDepth);
    }

    function test_createBatch_transfersTokens() public {
        uint8 depth = 20;
        uint8 bucketDepth = 17;
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;
        uint256 balanceBefore = token.balanceOf(stamper);
        uint256 expectedCost = balancePerChunk * (1 << depth);

        vm.prank(stamper);
        postage.createBatch(stamper, balancePerChunk, depth, bucketDepth, nonce, false);

        assertEq(token.balanceOf(stamper), balanceBefore - expectedCost);
    }

    function test_createBatch_revertsWithZeroOwner() public {
        vm.prank(oracle);
        postage.setPrice(1);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.ZeroAddress.selector);
        postage.createBatch(address(0), 1 ether, 20, 17, bytes32(0), false);
    }

    function test_createBatch_revertsWithInvalidDepth() public {
        vm.prank(oracle);
        postage.setPrice(1);

        // bucketDepth >= depth
        vm.prank(stamper);
        vm.expectRevert(PostageStamp.InvalidDepth.selector);
        postage.createBatch(stamper, 1 ether, 17, 17, bytes32(0), false);
    }

    function test_createBatch_revertsWithBucketDepthBelowMinimum() public {
        vm.prank(oracle);
        postage.setPrice(1);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.InvalidDepth.selector);
        postage.createBatch(stamper, 1 ether, 20, 15, bytes32(0), false);
    }

    function test_createBatch_revertsIfBatchExists() public {
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.startPrank(stamper);
        postage.createBatch(stamper, balancePerChunk, 20, 17, nonce, false);

        vm.expectRevert(PostageStamp.BatchExists.selector);
        postage.createBatch(stamper, balancePerChunk, 20, 17, nonce, false);
        vm.stopPrank();
    }

    // ==================== Top Up Tests ====================

    function test_topUp_success() public {
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, nonce, false);

        uint256 topupAmount = 0.5 ether;

        vm.prank(stamper);
        postage.topUp(batchId, topupAmount);

        // Verify normalised balance increased
        assertTrue(postage.batchNormalisedBalance(batchId) > 0);
    }

    function test_topUp_revertsForExpiredBatch() public {
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, nonce, false);

        // Advance blocks to expire batch
        vm.roll(block.number + 1_000_000);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.BatchExpired.selector);
        postage.topUp(batchId, 0.5 ether);
    }

    // ==================== Price Oracle Tests ====================

    function test_setPrice_onlyOracle() public {
        vm.prank(stamper);
        vm.expectRevert();
        postage.setPrice(100);
    }

    function test_setPrice_updatesPrice() public {
        uint256 newPrice = 100;

        vm.prank(oracle);
        postage.setPrice(newPrice);

        assertEq(postage.lastPrice(), newPrice);
    }

    // ==================== Pause Tests ====================

    function test_pause_onlyPauser() public {
        vm.prank(stamper);
        vm.expectRevert();
        postage.pause();
    }

    function test_pause_preventsBatchCreation() public {
        vm.prank(deployer);
        postage.pause();

        vm.prank(oracle);
        postage.setPrice(1);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.EnforcedPause.selector);
        postage.createBatch(stamper, 1 ether, 20, 17, bytes32(0), false);
    }

    function test_unPause_allowsBatchCreation() public {
        vm.prank(deployer);
        postage.pause();

        vm.prank(deployer);
        postage.unPause();

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(0), false);

        assertTrue(batchId != bytes32(0));
    }

    // ==================== Withdraw Tests ====================

    function test_withdraw_onlyRedistributor() public {
        vm.prank(stamper);
        vm.expectRevert();
        postage.withdraw(stamper);
    }
}
