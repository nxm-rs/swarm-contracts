// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { PriceOracle } from "../../src/incentives/StoragePriceOracle.sol";
import { PostageStamp } from "../../src/incentives/PostageStamp.sol";
import { TestToken } from "../../src/common/TestToken.sol";

contract StoragePriceOracleTest is Test {
    PriceOracle public oracle;
    PostageStamp public postage;
    TestToken public token;

    address internal deployer;
    address internal priceUpdater;
    address internal alice;

    uint8 internal constant MIN_BUCKET_DEPTH = 16;
    uint256 internal constant ROUND_LENGTH = 152;

    function setUp() public {
        deployer = makeAddr("deployer");
        priceUpdater = makeAddr("priceUpdater");
        alice = makeAddr("alice");

        vm.startPrank(deployer);

        token = new TestToken();
        postage = new PostageStamp(address(token), MIN_BUCKET_DEPTH);
        oracle = new PriceOracle(address(postage));

        // Grant oracle the price oracle role on postage
        postage.grantRoles(address(oracle), postage.PRICE_ORACLE_ROLE());

        // Grant price updater role to priceUpdater
        oracle.grantRoles(priceUpdater, oracle.PRICE_UPDATER_ROLE());

        vm.stopPrank();
    }

    // ==================== Initialization Tests ====================

    function test_constructor_setsPostageStamp() public view {
        assertEq(address(oracle.postageStamp()), address(postage));
    }

    function test_constructor_setsOwner() public view {
        assertEq(oracle.owner(), deployer);
    }

    function test_constructor_setsInitialPrice() public view {
        // Initial price should be minimum price (24000)
        assertEq(oracle.currentPrice(), 24_000);
    }

    function test_constructor_setsLastAdjustedRound() public view {
        uint64 expectedRound = uint64(block.number / ROUND_LENGTH);
        assertEq(oracle.lastAdjustedRound(), expectedRound);
    }

    // ==================== Set Price Tests ====================

    function test_setPrice_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.setPrice(50_000);
    }

    function test_setPrice_updatesPrice() public {
        uint32 newPrice = 50_000;

        vm.prank(deployer);
        oracle.setPrice(newPrice);

        assertEq(oracle.currentPrice(), newPrice);
    }

    function test_setPrice_enforcesMinimum() public {
        uint32 lowPrice = 100; // Below minimum

        vm.prank(deployer);
        oracle.setPrice(lowPrice);

        // Should be set to minimum price instead
        assertEq(oracle.currentPrice(), oracle.minimumPrice());
    }

    function test_setPrice_updatesPostageStamp() public {
        uint32 newPrice = 50_000;

        vm.prank(deployer);
        oracle.setPrice(newPrice);

        // PostageStamp should also have updated price
        assertEq(postage.lastPrice(), newPrice);
    }

    // ==================== Adjust Price Tests ====================

    function test_adjustPrice_onlyPriceUpdater() public {
        // Move to next round so we can adjust
        vm.roll(block.number + ROUND_LENGTH);

        vm.prank(alice);
        vm.expectRevert();
        oracle.adjustPrice(4);
    }

    function test_adjustPrice_revertsIfSameRound() public {
        vm.prank(priceUpdater);
        vm.expectRevert(PriceOracle.PriceAlreadyAdjusted.selector);
        oracle.adjustPrice(4);
    }

    function test_adjustPrice_revertsWithZeroRedundancy() public {
        vm.roll(block.number + ROUND_LENGTH);

        vm.prank(priceUpdater);
        vm.expectRevert(PriceOracle.UnexpectedZero.selector);
        oracle.adjustPrice(0);
    }

    function test_adjustPrice_increasesWithLowRedundancy() public {
        vm.roll(block.number + ROUND_LENGTH);

        uint32 priceBefore = oracle.currentPrice();

        vm.prank(priceUpdater);
        oracle.adjustPrice(1); // Low redundancy = price increase

        assertGt(oracle.currentPrice(), priceBefore);
    }

    function test_adjustPrice_decreasesWithHighRedundancy() public {
        // First set a higher price so we have room to decrease
        vm.prank(deployer);
        oracle.setPrice(50_000);

        vm.roll(block.number + ROUND_LENGTH);

        uint32 priceBefore = oracle.currentPrice();

        vm.prank(priceUpdater);
        oracle.adjustPrice(8); // High redundancy = price decrease

        assertLt(oracle.currentPrice(), priceBefore);
    }

    function test_adjustPrice_stableAtTargetRedundancy() public {
        // Target redundancy is 4, which uses changeRate[4] = priceBase (no change)
        vm.roll(block.number + ROUND_LENGTH);

        uint32 priceBefore = oracle.currentPrice();

        vm.prank(priceUpdater);
        oracle.adjustPrice(4);

        // Price should stay approximately the same
        assertEq(oracle.currentPrice(), priceBefore);
    }

    function test_adjustPrice_updatesLastAdjustedRound() public {
        vm.roll(block.number + ROUND_LENGTH);

        vm.prank(priceUpdater);
        oracle.adjustPrice(4);

        assertEq(oracle.lastAdjustedRound(), oracle.currentRound());
    }

    function test_adjustPrice_capsRedundancy() public {
        // Set a high initial price first
        vm.prank(deployer);
        oracle.setPrice(50_000);

        // Move to next round
        vm.roll(block.number + ROUND_LENGTH);

        uint32 priceBefore = oracle.currentPrice();

        // Very high redundancy (100) should be capped at max considered (8)
        // This means it should decrease at the same rate as redundancy=8
        vm.prank(priceUpdater);
        oracle.adjustPrice(100);

        // Price should decrease (max redundancy = price decrease)
        assertLt(oracle.currentPrice(), priceBefore);
    }

    function test_adjustPrice_increasesOnSkippedRounds() public {
        // Set initial price
        vm.prank(deployer);
        oracle.setPrice(30_000);

        // Skip several rounds
        vm.roll(block.number + ROUND_LENGTH * 5);

        uint32 priceBefore = oracle.currentPrice();

        vm.prank(priceUpdater);
        oracle.adjustPrice(4); // Target redundancy

        // Price should have increased due to skipped rounds
        assertGt(oracle.currentPrice(), priceBefore);
    }

    // ==================== Pause Tests ====================

    function test_pause_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.pause();
    }

    function test_pause_setsIsPaused() public {
        vm.prank(deployer);
        oracle.pause();

        assertTrue(oracle.isPaused());
    }

    function test_pause_preventsAdjustment() public {
        vm.prank(deployer);
        oracle.pause();

        vm.roll(block.number + ROUND_LENGTH);

        vm.prank(priceUpdater);
        bool result = oracle.adjustPrice(4);

        // Should return false when paused
        assertFalse(result);
    }

    function test_unPause_onlyOwner() public {
        vm.prank(deployer);
        oracle.pause();

        vm.prank(alice);
        vm.expectRevert();
        oracle.unPause();
    }

    function test_unPause_allowsAdjustment() public {
        vm.prank(deployer);
        oracle.pause();

        vm.prank(deployer);
        oracle.unPause();

        vm.roll(block.number + ROUND_LENGTH);

        uint32 priceBefore = oracle.currentPrice();

        vm.prank(priceUpdater);
        bool result = oracle.adjustPrice(1);

        assertTrue(result);
        assertGt(oracle.currentPrice(), priceBefore);
    }

    // ==================== View Function Tests ====================

    function test_currentRound_calculatesCorrectly() public view {
        uint64 expected = uint64(block.number / ROUND_LENGTH);
        assertEq(oracle.currentRound(), expected);
    }

    function test_minimumPrice_returnsCorrectValue() public view {
        // Minimum price is 24000
        assertEq(oracle.minimumPrice(), 24_000);
    }
}
