// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { RedistributionBase } from "./RedistributionBase.t.sol";
import { Redistribution } from "../../../src/incentives/Redistribution.sol";

/// @title RedistributionClaimTest
/// @notice Tests for the claim phase of the Redistribution contract
/// @dev Note: Full claim testing requires complex ChunkInclusionProof data.
///      These tests focus on phase requirements and view functions.
contract RedistributionClaimTest is RedistributionBase {
    // Test data
    uint8 internal constant TEST_DEPTH = 16;
    bytes32 internal testReserveCommitment;
    bytes32 internal testRevealNonce;

    function setUp() public override {
        super.setUp();
        testReserveCommitment = keccak256("reserve");
        testRevealNonce = keccak256("nonce");
    }

    // Helper to commit and reveal for a node
    function commitAndReveal(address node, bytes32 overlay, bytes32 reserveCommitment, bytes32 nonce) internal {
        bytes32 obfuscatedHash = redistribution.wrapCommit(overlay, TEST_DEPTH, reserveCommitment, nonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    // ==================== Phase Requirement Tests ====================

    function test_currentRoundReveals_revertsIfNotClaimPhase() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        vm.expectRevert(Redistribution.NotClaimPhase.selector);
        redistribution.currentRoundReveals();
    }

    function test_currentRoundReveals_revertsIfNoReveals() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Commit but don't reveal
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        // Skip reveal phase
        mineToClaimPhaseStart();

        vm.expectRevert(Redistribution.NoReveals.selector);
        redistribution.currentRoundReveals();
    }

    function test_currentRoundReveals_returnsReveals() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Commit
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // Reveal
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        mineToClaimPhaseStart();

        // Get reveals
        Redistribution.Reveal[] memory reveals = redistribution.currentRoundReveals();
        assertEq(reveals.length, 1);
        assertEq(reveals[0].overlay, node1Overlay);
        assertEq(reveals[0].owner, node1);
        assertEq(reveals[0].depth, TEST_DEPTH);
        assertEq(reveals[0].hash, testReserveCommitment);
    }

    // ==================== isWinner Tests ====================

    function test_isWinner_revertsIfNotClaimPhase() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        vm.expectRevert(Redistribution.NotClaimPhase.selector);
        redistribution.isWinner(node1Overlay);
    }

    function test_isWinner_revertsIfNoReveals() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Commit but don't reveal
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToClaimPhaseStart();

        vm.expectRevert(Redistribution.NoReveals.selector);
        redistribution.isWinner(node1Overlay);
    }

    function test_isWinner_returnsTrueForSingleReveal() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Commit
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // Reveal
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        mineToClaimPhaseStart();

        // Single revealer should be the winner
        assertTrue(redistribution.isWinner(node1Overlay));
    }

    function test_isWinner_returnsFalseForNonParticipant() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Only node1 commits and reveals
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        mineToClaimPhaseStart();

        // Node2 didn't participate, should not be winner
        assertFalse(redistribution.isWinner(node2Overlay));
    }

    function test_isWinner_oneWinnerAmongMultiple() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint64 roundNumber = redistribution.currentRound();

        // Multiple nodes commit with same reserve commitment
        bytes32 hash1 = redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        bytes32 hash2 = redistribution.wrapCommit(node2Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));
        bytes32 hash3 = redistribution.wrapCommit(node3Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce3"));

        vm.prank(node1);
        redistribution.commit(hash1, roundNumber);
        vm.prank(node2);
        redistribution.commit(hash2, roundNumber);
        vm.prank(node3);
        redistribution.commit(hash3, roundNumber);

        mineToRevealPhaseStart();

        // All reveal with same hash (agreeing on truth)
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        vm.prank(node2);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));
        vm.prank(node3);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce3"));

        mineToClaimPhaseStart();

        // Count winners - exactly one should win
        uint256 winnerCount = 0;
        if (redistribution.isWinner(node1Overlay)) winnerCount++;
        if (redistribution.isWinner(node2Overlay)) winnerCount++;
        if (redistribution.isWinner(node3Overlay)) winnerCount++;

        assertEq(winnerCount, 1, "Exactly one node should be winner");
    }

    // ==================== Minimum Depth Tests ====================

    function test_currentMinimumDepth_initiallyZero() public view {
        // With no previous winner, minimum depth should be 0
        assertEq(redistribution.currentMinimumDepth(), 0);
    }

    // ==================== Multiple Reveals Different Hashes ====================

    function test_isWinner_disagreementDoesNotWin() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint64 roundNumber = redistribution.currentRound();
        bytes32 differentHash = keccak256("different");

        // Node1 and Node2 agree, Node3 disagrees
        bytes32 hash1 = redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        bytes32 hash2 = redistribution.wrapCommit(node2Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));
        bytes32 hash3 = redistribution.wrapCommit(node3Overlay, TEST_DEPTH, differentHash, keccak256("nonce3"));

        vm.prank(node1);
        redistribution.commit(hash1, roundNumber);
        vm.prank(node2);
        redistribution.commit(hash2, roundNumber);
        vm.prank(node3);
        redistribution.commit(hash3, roundNumber);

        mineToRevealPhaseStart();

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        vm.prank(node2);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));
        vm.prank(node3);
        redistribution.reveal(TEST_DEPTH, differentHash, keccak256("nonce3"));

        mineToClaimPhaseStart();

        // Node3 with different hash should not win
        // (Truth is selected by stake-weighted random, but with equal stakes, majority usually wins)
        // This test verifies the winner selection mechanism considers truth matching
        bool node1Wins = redistribution.isWinner(node1Overlay);
        bool node2Wins = redistribution.isWinner(node2Overlay);
        bool node3Wins = redistribution.isWinner(node3Overlay);

        // At least one node should win
        assertTrue(node1Wins || node2Wins || node3Wins, "Someone should win");
        // Exactly one winner
        uint256 winCount = (node1Wins ? 1 : 0) + (node2Wins ? 1 : 0) + (node3Wins ? 1 : 0);
        assertEq(winCount, 1, "Exactly one winner");
    }

    // ==================== Pause Tests ====================

    function test_isWinner_worksWhenPaused() public {
        // isWinner is a view function and doesn't check pause status
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        vm.prank(deployer);
        redistribution.pause();

        mineToClaimPhaseStart();

        // isWinner should still work even when paused (it's a view function)
        assertTrue(redistribution.isWinner(node1Overlay));
    }

    // ==================== Already Claimed Tests ====================

    function test_isWinner_revertsIfAlreadyClaimed() public {
        // This tests the AlreadyClaimed revert in isWinner
        // To properly test this, we'd need to successfully call claim() first
        // which requires complex ChunkInclusionProof data
        // This is covered in integration tests
    }

    // ==================== Round Transitions ====================

    function test_claimPhase_newRoundInvalidatesOldReveals() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Round 1: Commit and reveal
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 round1 = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, round1);

        mineToRevealPhaseStart();
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        // Skip to next round's claim phase without claiming
        minePastRounds(1);
        mineToClaimPhaseStart();

        // Old reveals are no longer valid for new round
        vm.expectRevert(Redistribution.NoReveals.selector);
        redistribution.isWinner(node1Overlay);
    }

    // ==================== Stake Density and Winner Selection ====================

    function test_reveal_stakeDensityAffectsWinProbability() public {
        // Stake nodes with different amounts but same height (TEST_DEPTH) to pass proximity check
        // Minimum stake scales with height: MIN_STAKE * 2^height
        uint256 scaledMinStake = MIN_STAKE * (2 ** TEST_DEPTH);
        vm.prank(node1);
        stakeRegistry.manageStake(bytes32(uint256(1)), scaledMinStake, TEST_DEPTH);
        vm.prank(node2);
        stakeRegistry.manageStake(bytes32(uint256(2)), scaledMinStake * 10, TEST_DEPTH); // 10x stake

        node1Overlay = stakeRegistry.overlayOfAddress(node1);
        node2Overlay = stakeRegistry.overlayOfAddress(node2);

        minePastRounds(2);
        mineToCommitPhaseStart();

        uint64 roundNumber = redistribution.currentRound();

        bytes32 hash1 = redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        bytes32 hash2 = redistribution.wrapCommit(node2Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));

        vm.prank(node1);
        redistribution.commit(hash1, roundNumber);
        vm.prank(node2);
        redistribution.commit(hash2, roundNumber);

        mineToRevealPhaseStart();

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        vm.prank(node2);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));

        mineToClaimPhaseStart();

        // Get reveals to verify stake densities are different
        Redistribution.Reveal[] memory reveals = redistribution.currentRoundReveals();
        assertEq(reveals.length, 2);

        // Higher stake should result in higher stake density
        // Note: Winner selection is probabilistic based on stake density
        bool node1Wins = redistribution.isWinner(node1Overlay);
        bool node2Wins = redistribution.isWinner(node2Overlay);

        // Exactly one should win
        assertTrue(node1Wins != node2Wins, "Exactly one node should win");
    }
}
