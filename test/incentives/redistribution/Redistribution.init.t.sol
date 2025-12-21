// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { RedistributionBase } from "./RedistributionBase.t.sol";
import { Redistribution } from "../../../src/incentives/Redistribution.sol";

/// @title RedistributionInitTest
/// @notice Tests for Redistribution contract initialization and basic functionality
contract RedistributionInitTest is RedistributionBase {
    // ==================== Constructor Tests ====================

    function test_constructor_setsStakes() public view {
        assertEq(address(redistribution.Stakes()), address(stakeRegistry));
    }

    function test_constructor_setsPostageContract() public view {
        assertEq(address(redistribution.PostageContract()), address(postageStamp));
    }

    function test_constructor_setsOracleContract() public view {
        assertEq(address(redistribution.OracleContract()), address(priceOracle));
    }

    function test_constructor_setsOwner() public view {
        assertEq(redistribution.owner(), deployer);
    }

    function test_constructor_initialRoundsAreZero() public view {
        assertEq(redistribution.currentCommitRound(), 0);
        assertEq(redistribution.currentRevealRound(), 0);
        assertEq(redistribution.currentClaimRound(), 0);
    }

    // ==================== Phase Detection Tests ====================

    function test_currentPhaseCommit_returnsTrueInCommitPhase() public {
        mineToCommitPhaseStart();
        assertInCommitPhase();
    }

    function test_currentPhaseCommit_returnsFalseInRevealPhase() public {
        mineToCommitPhaseStart();
        mineToRevealPhaseStart();
        assertFalse(redistribution.currentPhaseCommit());
    }

    function test_currentPhaseReveal_returnsTrueInRevealPhase() public {
        mineToCommitPhaseStart();
        mineToRevealPhaseStart();
        assertInRevealPhase();
    }

    function test_currentPhaseReveal_returnsFalseInCommitPhase() public {
        mineToCommitPhaseStart();
        assertFalse(redistribution.currentPhaseReveal());
    }

    function test_currentPhaseClaim_returnsTrueInClaimPhase() public {
        mineToCommitPhaseStart();
        mineToClaimPhaseStart();
        assertInClaimPhase();
    }

    function test_currentPhaseClaim_returnsFalseInCommitPhase() public {
        mineToCommitPhaseStart();
        assertFalse(redistribution.currentPhaseClaim());
    }

    // ==================== Round Number Tests ====================

    function test_currentRound_calculatesCorrectly() public view {
        uint64 expected = uint64(block.number / ROUND_LENGTH);
        assertEq(redistribution.currentRound(), expected);
    }

    function test_currentRound_incrementsAfterRoundLength() public {
        uint64 initialRound = redistribution.currentRound();
        vm.roll(block.number + ROUND_LENGTH);
        assertEq(redistribution.currentRound(), initialRound + 1);
    }

    // ==================== WrapCommit Tests ====================

    function test_wrapCommit_isConsistent() public view {
        bytes32 overlay = bytes32(uint256(1));
        uint8 depth = 16;
        bytes32 hash = bytes32(uint256(2));
        bytes32 revealNonce = bytes32(uint256(3));

        bytes32 result1 = redistribution.wrapCommit(overlay, depth, hash, revealNonce);
        bytes32 result2 = redistribution.wrapCommit(overlay, depth, hash, revealNonce);

        assertEq(result1, result2);
    }

    function test_wrapCommit_differentInputsProduceDifferentOutputs() public view {
        bytes32 overlay = bytes32(uint256(1));
        uint8 depth = 16;
        bytes32 hash = bytes32(uint256(2));

        bytes32 result1 = redistribution.wrapCommit(overlay, depth, hash, bytes32(uint256(3)));
        bytes32 result2 = redistribution.wrapCommit(overlay, depth, hash, bytes32(uint256(4)));

        assertTrue(result1 != result2);
    }

    function test_wrapCommit_differentDepthsProduceDifferentOutputs() public view {
        bytes32 overlay = bytes32(uint256(1));
        bytes32 hash = bytes32(uint256(2));
        bytes32 revealNonce = bytes32(uint256(3));

        bytes32 result1 = redistribution.wrapCommit(overlay, 16, hash, revealNonce);
        bytes32 result2 = redistribution.wrapCommit(overlay, 17, hash, revealNonce);

        assertTrue(result1 != result2);
    }

    // ==================== Proximity Tests ====================

    function test_inProximity_returnsTrueForZeroMinimum() public view {
        bytes32 a = bytes32(uint256(1));
        bytes32 b = bytes32(uint256(2));

        assertTrue(redistribution.inProximity(a, b, 0));
    }

    function test_inProximity_returnsTrueForIdentical() public view {
        bytes32 a = bytes32(uint256(1));

        assertTrue(redistribution.inProximity(a, a, 255));
    }

    function test_inProximity_correctlyCalculatesForHighBitMatch() public view {
        // Two values with matching high bit
        bytes32 a = bytes32(uint256(0x8000000000000000000000000000000000000000000000000000000000000000));
        bytes32 b = bytes32(uint256(0x8000000000000000000000000000000000000000000000000000000000000001));

        assertTrue(redistribution.inProximity(a, b, 1));
    }

    function test_inProximity_returnsFalseForDifferentHighBits() public view {
        bytes32 a = bytes32(uint256(0x8000000000000000000000000000000000000000000000000000000000000000));
        bytes32 b = bytes32(uint256(0x4000000000000000000000000000000000000000000000000000000000000000));

        // Different highest bit means not in proximity at depth 1
        assertFalse(redistribution.inProximity(a, b, 1));
    }

    // ==================== Seed Tests ====================

    function test_currentSeed_derivedFromStoredSeed() public view {
        // currentSeed() returns a derived value based on stored seed and round difference
        // When cr > currentRevealRound + 1, seed is hashed with the difference
        bytes32 seed = redistribution.currentSeed();
        // The seed should be non-zero (derived from initial 0 seed)
        // since currentRound > currentRevealRound + 1 (no reveals yet)
        assertTrue(seed != bytes32(0) || redistribution.currentRevealRound() > 0);
    }

    function test_nextSeed_returnsValue() public view {
        bytes32 seed = redistribution.nextSeed();
        // Just checking it doesn't revert and returns a value
        assertTrue(seed != bytes32(0) || redistribution.currentRevealRound() > 0);
    }

    // ==================== Admin Functions Tests ====================

    function test_setFreezingParams_onlyOwner() public {
        vm.prank(node1);
        vm.expectRevert();
        redistribution.setFreezingParams(2, 3, 50);
    }

    function test_setFreezingParams_success() public {
        vm.prank(deployer);
        redistribution.setFreezingParams(2, 3, 50);
        // No revert means success
    }

    function test_setSampleMaxValue_onlyOwner() public {
        vm.prank(node1);
        vm.expectRevert();
        redistribution.setSampleMaxValue(1000);
    }

    function test_setSampleMaxValue_success() public {
        vm.prank(deployer);
        redistribution.setSampleMaxValue(1000);
        // No revert means success
    }

    // ==================== Pause Tests ====================

    function test_pause_onlyOwner() public {
        vm.prank(node1);
        vm.expectRevert();
        redistribution.pause();
    }

    function test_pause_setsFlag() public {
        vm.prank(deployer);
        redistribution.pause();

        assertTrue(redistribution.paused());
    }

    function test_unPause_onlyOwner() public {
        vm.prank(deployer);
        redistribution.pause();

        vm.prank(node1);
        vm.expectRevert();
        redistribution.unPause();
    }

    function test_unPause_clearsFlag() public {
        vm.prank(deployer);
        redistribution.pause();

        vm.prank(deployer);
        redistribution.unPause();

        assertFalse(redistribution.paused());
    }

    function test_paused_initiallyFalse() public view {
        assertFalse(redistribution.paused());
    }
}
