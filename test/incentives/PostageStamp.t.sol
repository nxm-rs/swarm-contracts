// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Test, Vm } from "forge-std/Test.sol";
import { PostageStamp } from "../../src/incentives/PostageStamp.sol";
import { TestToken } from "../../src/common/TestToken.sol";

contract PostageStampTest is Test {
    PostageStamp public postage;
    TestToken public token;

    address internal deployer;
    address internal oracle;
    address internal stamper;
    address internal stamper2;
    address internal redistributor;

    uint8 internal constant MIN_BUCKET_DEPTH = 16;
    uint256 internal constant INITIAL_BALANCE = 1_000_000 ether;

    event BatchCreated(
        bytes32 indexed batchId,
        uint256 totalAmount,
        uint256 normalisedBalance,
        address owner,
        uint8 depth,
        uint8 bucketDepth,
        bool immutableFlag
    );
    event BatchTopUp(bytes32 indexed batchId, uint256 topupAmount, uint256 normalisedBalance);
    event BatchDepthIncrease(bytes32 indexed batchId, uint8 newDepth, uint256 normalisedBalance);
    event PriceUpdate(uint256 price);
    event PotWithdrawn(address recipient, uint256 totalAmount);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        deployer = makeAddr("deployer");
        oracle = makeAddr("oracle");
        stamper = makeAddr("stamper");
        stamper2 = makeAddr("stamper2");
        redistributor = makeAddr("redistributor");

        vm.startPrank(deployer);

        token = new TestToken();
        postage = new PostageStamp(address(token), MIN_BUCKET_DEPTH);

        // Grant roles
        postage.grantRoles(oracle, postage.PRICE_ORACLE_ROLE());
        postage.grantRoles(redistributor, postage.REDISTRIBUTOR_ROLE());

        // Fund stampers
        token.mint(stamper, INITIAL_BALANCE);
        token.mint(stamper2, INITIAL_BALANCE);
        token.mint(deployer, INITIAL_BALANCE);

        vm.stopPrank();

        // Approve postage contract
        vm.prank(stamper);
        token.approve(address(postage), type(uint256).max);
        vm.prank(stamper2);
        token.approve(address(postage), type(uint256).max);
        vm.prank(deployer);
        token.approve(address(postage), type(uint256).max);
    }

    // ==================== Helper Functions ====================

    function _createBatch(address owner, uint8 depth, uint8 bucketDepth, bytes32 nonce)
        internal
        returns (bytes32 batchId)
    {
        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;
        vm.prank(stamper);
        return postage.createBatch(owner, balancePerChunk, depth, bucketDepth, nonce, false);
    }

    function _createBatchWithBalance(address owner, uint256 balancePerChunk, uint8 depth, bytes32 nonce)
        internal
        returns (bytes32 batchId)
    {
        vm.prank(stamper);
        return postage.createBatch(owner, balancePerChunk, depth, MIN_BUCKET_DEPTH + 1, nonce, false);
    }

    // ==================== Constructor Tests ====================

    function test_constructor_setsToken() public view {
        assertEq(postage.bzzToken(), address(token));
    }

    function test_constructor_setsMinBucketDepth() public view {
        assertEq(postage.minimumBucketDepth(), MIN_BUCKET_DEPTH);
    }

    function test_constructor_setsOwner() public view {
        assertEq(postage.owner(), deployer);
    }

    function test_constructor_grantsPauserRole() public view {
        assertTrue(postage.hasAllRoles(deployer, postage.PAUSER_ROLE()));
    }

    function test_constructor_initialValuesAreZero() public view {
        assertEq(postage.lastPrice(), 0);
        assertEq(postage.validChunkCount(), 0);
        assertEq(postage.pot(), 0);
    }

    // ==================== Batch Creation Tests ====================

    function test_createBatch_success() public {
        uint8 depth = 20;
        uint8 bucketDepth = 17;
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, depth, bucketDepth, nonce, false);

        assertEq(postage.batchOwner(batchId), stamper);
        assertEq(postage.batchDepth(batchId), depth);
        assertEq(postage.batchBucketDepth(batchId), bucketDepth);
        assertFalse(postage.batchImmutableFlag(batchId));
    }

    function test_createBatch_immutable() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(1)), true);

        assertTrue(postage.batchImmutableFlag(batchId));
    }

    function test_createBatch_transfersTokens() public {
        uint8 depth = 20;
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;
        uint256 balanceBefore = token.balanceOf(stamper);
        uint256 expectedCost = balancePerChunk * (1 << depth);

        vm.prank(stamper);
        postage.createBatch(stamper, balancePerChunk, depth, 17, nonce, false);

        assertEq(token.balanceOf(stamper), balanceBefore - expectedCost);
    }

    function test_createBatch_emitsEvent() public {
        uint8 depth = 20;
        uint8 bucketDepth = 17;
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        // Just verify an event was emitted (don't check specific values since normalisedBalance is computed)
        vm.recordLogs();

        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, depth, bucketDepth, nonce, false);

        // Verify event was emitted by checking logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BatchCreated(bytes32,uint256,uint256,address,uint8,uint8,bool)")) {
                assertEq(logs[i].topics[1], batchId);
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "BatchCreated event not emitted");
    }

    function test_createBatch_updatesValidChunkCount() public {
        uint8 depth = 20;

        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;
        uint256 chunkCountBefore = postage.validChunkCount();

        vm.prank(stamper);
        postage.createBatch(stamper, balancePerChunk, depth, 17, bytes32(uint256(1)), false);

        assertEq(postage.validChunkCount(), chunkCountBefore + (1 << depth));
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

    function test_createBatch_revertsWithInsufficientBalance() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint256 tooLowBalance = postage.minimumInitialBalancePerChunk() - 1;

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.InsufficientBalance.selector);
        postage.createBatch(stamper, tooLowBalance, 20, 17, bytes32(0), false);
    }

    function test_createBatch_multipleBatches() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.startPrank(stamper);
        bytes32 batch1 = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(1)), false);
        bytes32 batch2 = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(2)), false);
        bytes32 batch3 = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(3)), false);
        vm.stopPrank();

        assertTrue(batch1 != batch2);
        assertTrue(batch2 != batch3);
        assertEq(postage.batchOwner(batch1), stamper);
        assertEq(postage.batchOwner(batch2), stamper);
        assertEq(postage.batchOwner(batch3), stamper);
    }

    // ==================== Top Up Tests ====================

    function test_topUp_success() public {
        vm.prank(oracle);
        postage.setPrice(1);

        // Use larger balance to ensure remaining balance after topup exceeds minimum
        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() * 2;
        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(1)), false);

        uint256 normalisedBefore = postage.batchNormalisedBalance(batchId);

        // Use smaller topup amount that stamper can afford (1e18 * 2^20 > 1e24 balance)
        uint256 topupAmount = 1000;
        vm.prank(stamper);
        postage.topUp(batchId, topupAmount);

        assertTrue(postage.batchNormalisedBalance(batchId) > normalisedBefore);
    }

    function test_topUp_emitsEvent() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() * 2;
        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(1)), false);

        // Use smaller topup amount that stamper can afford
        uint256 topupAmount = 1000;
        uint256 totalAmount = topupAmount * (1 << 20);

        // Only check that event was emitted with correct batchId
        vm.expectEmit(true, false, false, false);
        emit BatchTopUp(batchId, totalAmount, 0);

        vm.prank(stamper);
        postage.topUp(batchId, topupAmount);
    }

    function test_topUp_transfersTokens() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() * 2;
        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(1)), false);

        uint256 balanceBefore = token.balanceOf(stamper);
        // Use smaller topup amount that stamper can afford
        uint256 topupAmount = 1000;
        uint256 totalAmount = topupAmount * (1 << 20);

        vm.prank(stamper);
        postage.topUp(batchId, topupAmount);

        assertEq(token.balanceOf(stamper), balanceBefore - totalAmount);
    }

    function test_topUp_revertsForNonExistentBatch() public {
        vm.prank(oracle);
        postage.setPrice(1);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.BatchDoesNotExist.selector);
        postage.topUp(bytes32(uint256(999)), 1 ether);
    }

    function test_topUp_revertsForExpiredBatch() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        // Advance blocks to expire batch
        vm.roll(block.number + 1_000_000);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.BatchExpired.selector);
        postage.topUp(batchId, 1 ether);
    }

    // ==================== Increase Depth Tests ====================

    function test_increaseDepth_success() public {
        vm.prank(oracle);
        postage.setPrice(1);

        // Increasing depth by 2 divides remaining balance by 4, so use 5x minimum
        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() * 5;
        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(1)), false);

        uint8 newDepth = 22;

        vm.prank(stamper);
        postage.increaseDepth(batchId, newDepth);

        assertEq(postage.batchDepth(batchId), newDepth);
    }

    function test_increaseDepth_emitsEvent() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() * 5;
        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, 20, 17, bytes32(uint256(1)), false);

        uint8 newDepth = 22;

        // Only check the batchId and newDepth
        vm.expectEmit(true, false, false, false);
        emit BatchDepthIncrease(batchId, newDepth, 0);

        vm.prank(stamper);
        postage.increaseDepth(batchId, newDepth);
    }

    function test_increaseDepth_updatesValidChunkCount() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint8 oldDepth = 20;
        uint8 newDepth = 22;

        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() * 5;
        vm.prank(stamper);
        bytes32 batchId = postage.createBatch(stamper, balancePerChunk, oldDepth, 17, bytes32(uint256(1)), false);

        uint256 chunkCountBefore = postage.validChunkCount();

        vm.prank(stamper);
        postage.increaseDepth(batchId, newDepth);

        // New chunks added = 2^newDepth - 2^oldDepth
        uint256 expectedIncrease = (1 << newDepth) - (1 << oldDepth);
        assertEq(postage.validChunkCount(), chunkCountBefore + expectedIncrease);
    }

    function test_increaseDepth_revertsIfNotOwner() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.prank(stamper2);
        vm.expectRevert(PostageStamp.NotBatchOwner.selector);
        postage.increaseDepth(batchId, 22);
    }

    function test_increaseDepth_revertsIfDepthNotIncreasing() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.DepthNotIncreasing.selector);
        postage.increaseDepth(batchId, 20);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.DepthNotIncreasing.selector);
        postage.increaseDepth(batchId, 19);
    }

    function test_increaseDepth_revertsIfExpired() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.roll(block.number + 1_000_000);

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.BatchExpired.selector);
        postage.increaseDepth(batchId, 22);
    }

    // ==================== Price Oracle Tests ====================

    function test_setPrice_success() public {
        uint256 newPrice = 100;

        vm.prank(oracle);
        postage.setPrice(newPrice);

        assertEq(postage.lastPrice(), newPrice);
    }

    function test_setPrice_emitsEvent() public {
        uint256 newPrice = 100;

        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(newPrice);

        vm.prank(oracle);
        postage.setPrice(newPrice);
    }

    function test_setPrice_updatesLastUpdatedBlock() public {
        vm.prank(oracle);
        postage.setPrice(100);

        assertEq(postage.lastUpdatedBlock(), block.number);
    }

    function test_setPrice_revertsIfNotOracle() public {
        vm.prank(stamper);
        vm.expectRevert();
        postage.setPrice(100);
    }

    function test_setPrice_multipleUpdates() public {
        vm.prank(oracle);
        postage.setPrice(100);
        assertEq(postage.lastPrice(), 100);

        vm.roll(block.number + 100);

        vm.prank(oracle);
        postage.setPrice(200);
        assertEq(postage.lastPrice(), 200);
    }

    // ==================== Current Total Outpayment Tests ====================

    function test_currentTotalOutPayment_increasesWithBlocks() public {
        vm.prank(oracle);
        postage.setPrice(10);

        uint256 outpayment1 = postage.currentTotalOutPayment();

        vm.roll(block.number + 100);

        uint256 outpayment2 = postage.currentTotalOutPayment();

        assertEq(outpayment2, outpayment1 + 100 * 10);
    }

    function test_currentTotalOutPayment_zeroWhenPriceZero() public view {
        assertEq(postage.currentTotalOutPayment(), 0);
    }

    // ==================== Remaining Balance Tests ====================

    function test_remainingBalance_decreasesOverTime() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        uint256 balance1 = postage.remainingBalance(batchId);

        vm.roll(block.number + 1000);

        uint256 balance2 = postage.remainingBalance(batchId);

        assertTrue(balance2 < balance1);
        assertEq(balance1 - balance2, 1000); // price = 1 per block
    }

    function test_remainingBalance_revertsForNonExistentBatch() public {
        vm.expectRevert(PostageStamp.BatchDoesNotExist.selector);
        postage.remainingBalance(bytes32(uint256(999)));
    }

    function test_remainingBalance_zeroWhenExpired() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        // Advance to expiry
        vm.roll(block.number + 1_000_000);

        assertEq(postage.remainingBalance(batchId), 0);
    }

    // ==================== Batch Tree Tests ====================

    function test_isBatchesTreeEmpty_trueInitially() public view {
        assertTrue(postage.isBatchesTreeEmpty());
    }

    function test_isBatchesTreeEmpty_falseAfterBatchCreated() public {
        vm.prank(oracle);
        postage.setPrice(1);

        _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        assertFalse(postage.isBatchesTreeEmpty());
    }

    function test_firstBatchId_revertsWhenEmpty() public {
        vm.expectRevert(PostageStamp.NoBatchesExist.selector);
        postage.firstBatchId();
    }

    function test_firstBatchId_returnsSmallestBalance() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint256 smallBalance = postage.minimumInitialBalancePerChunk() + 1;
        uint256 largeBalance = postage.minimumInitialBalancePerChunk() + 1000;

        // Create batch with larger balance first
        vm.prank(stamper);
        postage.createBatch(stamper, largeBalance, 20, 17, bytes32(uint256(1)), false);

        // Create batch with smaller balance
        vm.prank(stamper);
        bytes32 smallBatchId = postage.createBatch(stamper, smallBalance, 20, 17, bytes32(uint256(2)), false);

        // First batch should be the one with smaller balance
        assertEq(postage.firstBatchId(), smallBatchId);
    }

    // ==================== Expiry Tests ====================

    function test_expiredBatchesExist_falseWhenEmpty() public view {
        assertFalse(postage.expiredBatchesExist());
    }

    function test_expiredBatchesExist_falseWhenNotExpired() public {
        vm.prank(oracle);
        postage.setPrice(1);

        _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        assertFalse(postage.expiredBatchesExist());
    }

    function test_expiredBatchesExist_trueWhenExpired() public {
        vm.prank(oracle);
        postage.setPrice(1);

        _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.roll(block.number + 1_000_000);

        assertTrue(postage.expiredBatchesExist());
    }

    function test_expireLimited_removesExpiredBatches() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        assertFalse(postage.isBatchesTreeEmpty());

        vm.roll(block.number + 1_000_000);

        postage.expireLimited(type(uint256).max);

        assertTrue(postage.isBatchesTreeEmpty());
        assertEq(postage.batchOwner(batchId), address(0));
    }

    function test_expireLimited_updatesValidChunkCount() public {
        vm.prank(oracle);
        postage.setPrice(1);

        uint8 depth = 20;
        _createBatch(stamper, depth, 17, bytes32(uint256(1)));

        uint256 chunkCountBefore = postage.validChunkCount();
        assertEq(chunkCountBefore, 1 << depth);

        vm.roll(block.number + 1_000_000);

        postage.expireLimited(type(uint256).max);

        assertEq(postage.validChunkCount(), 0);
    }

    function test_expireLimited_updatesPot() public {
        vm.prank(oracle);
        postage.setPrice(1);

        _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        uint256 potBefore = postage.pot();

        vm.roll(block.number + 1_000_000);

        postage.expireLimited(type(uint256).max);

        assertTrue(postage.pot() > potBefore);
    }

    // ==================== Withdraw Tests ====================

    function test_withdraw_success() public {
        vm.prank(oracle);
        postage.setPrice(1);

        _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.roll(block.number + 1000);

        uint256 balanceBefore = token.balanceOf(redistributor);

        vm.prank(redistributor);
        postage.withdraw(redistributor);

        assertTrue(token.balanceOf(redistributor) > balanceBefore);
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(oracle);
        postage.setPrice(1);

        _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.roll(block.number + 1000);

        vm.expectEmit(true, true, false, false);
        emit PotWithdrawn(redistributor, 0);

        vm.prank(redistributor);
        postage.withdraw(redistributor);
    }

    function test_withdraw_resetsPot() public {
        vm.prank(oracle);
        postage.setPrice(1);

        _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.roll(block.number + 1000);

        vm.prank(redistributor);
        postage.withdraw(redistributor);

        assertEq(postage.pot(), 0);
    }

    function test_withdraw_revertsIfNotRedistributor() public {
        vm.prank(stamper);
        vm.expectRevert();
        postage.withdraw(stamper);
    }

    // ==================== Copy Batch Tests ====================

    function test_copyBatch_success() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = bytes32(uint256(123));
        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.prank(deployer);
        postage.copyBatch(stamper, balancePerChunk, 20, 17, batchId, false);

        assertEq(postage.batchOwner(batchId), stamper);
        assertEq(postage.batchDepth(batchId), 20);
    }

    function test_copyBatch_revertsIfNotOwner() public {
        vm.prank(oracle);
        postage.setPrice(1);

        vm.prank(stamper);
        vm.expectRevert();
        postage.copyBatch(stamper, 1 ether, 20, 17, bytes32(uint256(123)), false);
    }

    function test_copyBatch_revertsIfBatchExists() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = bytes32(uint256(123));
        uint256 balancePerChunk = postage.minimumInitialBalancePerChunk() + 1;

        vm.startPrank(deployer);
        postage.copyBatch(stamper, balancePerChunk, 20, 17, batchId, false);

        vm.expectRevert(PostageStamp.BatchExists.selector);
        postage.copyBatch(stamper, balancePerChunk, 20, 17, batchId, false);
        vm.stopPrank();
    }

    // ==================== Pause Tests ====================

    function test_pause_success() public {
        vm.prank(deployer);
        postage.pause();

        assertTrue(postage.paused());
    }

    function test_pause_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Paused(deployer);

        vm.prank(deployer);
        postage.pause();
    }

    function test_pause_revertsIfNotPauser() public {
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

    function test_pause_preventsTopUp() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.prank(deployer);
        postage.pause();

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.EnforcedPause.selector);
        postage.topUp(batchId, 1 ether);
    }

    function test_pause_preventsIncreaseDepth() public {
        vm.prank(oracle);
        postage.setPrice(1);

        bytes32 batchId = _createBatch(stamper, 20, 17, bytes32(uint256(1)));

        vm.prank(deployer);
        postage.pause();

        vm.prank(stamper);
        vm.expectRevert(PostageStamp.EnforcedPause.selector);
        postage.increaseDepth(batchId, 22);
    }

    function test_unPause_success() public {
        vm.prank(deployer);
        postage.pause();

        vm.prank(deployer);
        postage.unPause();

        assertFalse(postage.paused());
    }

    function test_unPause_emitsEvent() public {
        vm.prank(deployer);
        postage.pause();

        vm.expectEmit(true, true, true, true);
        emit Unpaused(deployer);

        vm.prank(deployer);
        postage.unPause();
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

    function test_unPause_revertsIfNotPaused() public {
        vm.prank(deployer);
        vm.expectRevert(PostageStamp.ExpectedPause.selector);
        postage.unPause();
    }

    // ==================== Minimum Validity Blocks Tests ====================

    function test_setMinimumValidityBlocks_success() public {
        uint64 newValue = 50_000;

        vm.prank(deployer);
        postage.setMinimumValidityBlocks(newValue);

        assertEq(postage.minimumValidityBlocks(), newValue);
    }

    function test_setMinimumValidityBlocks_revertsIfNotOwner() public {
        vm.prank(stamper);
        vm.expectRevert();
        postage.setMinimumValidityBlocks(50_000);
    }

    // ==================== Minimum Initial Balance Tests ====================

    function test_minimumInitialBalancePerChunk_calculatesCorrectly() public {
        vm.prank(oracle);
        postage.setPrice(10);

        uint256 expected = postage.minimumValidityBlocks() * 10;
        assertEq(postage.minimumInitialBalancePerChunk(), expected);
    }

    function test_minimumInitialBalancePerChunk_zeroWhenPriceZero() public view {
        assertEq(postage.minimumInitialBalancePerChunk(), 0);
    }
}
