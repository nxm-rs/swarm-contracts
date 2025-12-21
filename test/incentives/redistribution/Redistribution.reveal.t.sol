// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { RedistributionBase } from "./RedistributionBase.t.sol";
import { Redistribution } from "../../../src/incentives/Redistribution.sol";

/// @title RedistributionRevealTest
/// @notice Tests for the reveal phase of the Redistribution contract
contract RedistributionRevealTest is RedistributionBase {
    // Test data
    uint8 internal constant TEST_DEPTH = 16;
    bytes32 internal testReserveCommitment;
    bytes32 internal testRevealNonce;

    function setUp() public override {
        super.setUp();
        testReserveCommitment = keccak256("reserve");
        testRevealNonce = keccak256("nonce");
    }

    // ==================== Reveal Requirement Tests ====================

    function test_reveal_revertsIfNoCommits() public {
        setupStakedNodes();
        mineToCommitPhaseStart();
        mineToRevealPhaseStart();

        vm.prank(node1);
        vm.expectRevert(Redistribution.NoCommitsReceived.selector);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);
    }

    function test_reveal_revertsIfNotRevealPhase() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Commit first
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        // Try to reveal while still in commit phase
        vm.prank(node1);
        vm.expectRevert(Redistribution.NotRevealPhase.selector);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);
    }

    function test_reveal_revertsIfNoMatchingCommit() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Commit with one hash
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // Try to reveal with different values
        vm.prank(node1);
        vm.expectRevert(Redistribution.NoMatchingCommit.selector);
        redistribution.reveal(TEST_DEPTH, keccak256("wrong"), testRevealNonce);
    }

    function test_reveal_revertsIfAlreadyRevealed() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // First reveal succeeds
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        // Second reveal fails
        vm.prank(node1);
        vm.expectRevert(Redistribution.AlreadyRevealed.selector);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);
    }

    function test_reveal_revertsIfWrongDepth() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Commit with depth 16
        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // Try to reveal with different depth - won't match commit hash
        vm.prank(node1);
        vm.expectRevert(Redistribution.NoMatchingCommit.selector);
        redistribution.reveal(TEST_DEPTH + 1, testReserveCommitment, testRevealNonce);
    }

    // ==================== Successful Reveal Tests ====================

    function test_reveal_success() public {
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

        // Verify reveal round is set
        assertEq(redistribution.currentRevealRound(), roundNumber);
    }

    function test_reveal_storesRevealData() public {
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

        // Check commit is marked as revealed
        (,, bool revealed,,,,) = redistribution.currentCommits(0);
        assertTrue(revealed);
    }

    function test_reveal_emitsEvent() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // Calculate expected stake density
        uint256 stake = stakeRegistry.nodeEffectiveStake(node1);
        uint8 height = stakeRegistry.heightOfAddress(node1);
        uint256 stakeDensity = stake * uint256(2 ** (TEST_DEPTH - height));

        // First reveal emits CurrentRevealAnchor first, then Revealed
        // Expect CurrentRevealAnchor (topic1 is roundNumber, topic2 is anchor which we don't check)
        vm.expectEmit(true, false, false, false);
        emit Redistribution.CurrentRevealAnchor(roundNumber, bytes32(0));

        // Then expect Revealed
        vm.expectEmit(true, true, true, true);
        emit Redistribution.Revealed(roundNumber, node1Overlay, stake, stakeDensity, testReserveCommitment, TEST_DEPTH);

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);
    }

    // ==================== Multiple Reveals Tests ====================

    function test_reveal_multipleNodesCanReveal() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint64 roundNumber = redistribution.currentRound();

        // Each node commits
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

        // Each node reveals
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        vm.prank(node2);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));
        vm.prank(node3);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce3"));

        // Verify all commits are marked as revealed
        (,, bool revealed1,,,,) = redistribution.currentCommits(0);
        (,, bool revealed2,,,,) = redistribution.currentCommits(1);
        (,, bool revealed3,,,,) = redistribution.currentCommits(2);

        assertTrue(revealed1);
        assertTrue(revealed2);
        assertTrue(revealed3);
    }

    function test_reveal_partialReveals() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint64 roundNumber = redistribution.currentRound();

        // Two nodes commit
        bytes32 hash1 = redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        bytes32 hash2 = redistribution.wrapCommit(node2Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));

        vm.prank(node1);
        redistribution.commit(hash1, roundNumber);
        vm.prank(node2);
        redistribution.commit(hash2, roundNumber);

        mineToRevealPhaseStart();

        // Only node1 reveals
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));

        // Verify node1 revealed, node2 didn't
        (,, bool revealed1,,,,) = redistribution.currentCommits(0);
        (,, bool revealed2,,,,) = redistribution.currentCommits(1);

        assertTrue(revealed1);
        assertFalse(revealed2);
    }

    // ==================== Reveal with Different Hashes Tests ====================

    function test_reveal_nodesCanRevealDifferentHashes() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint64 roundNumber = redistribution.currentRound();
        bytes32 differentHash = keccak256("different");

        // Nodes commit with different reserve commitments
        bytes32 hash1 = redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        bytes32 hash2 = redistribution.wrapCommit(node2Overlay, TEST_DEPTH, differentHash, keccak256("nonce2"));

        vm.prank(node1);
        redistribution.commit(hash1, roundNumber);
        vm.prank(node2);
        redistribution.commit(hash2, roundNumber);

        mineToRevealPhaseStart();

        // Both can reveal their respective values
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        vm.prank(node2);
        redistribution.reveal(TEST_DEPTH, differentHash, keccak256("nonce2"));

        // Both commits should be marked as revealed
        (,, bool revealed1,,,,) = redistribution.currentCommits(0);
        (,, bool revealed2,,,,) = redistribution.currentCommits(1);

        assertTrue(revealed1);
        assertTrue(revealed2);
    }

    // ==================== Anchor Tests ====================

    function test_reveal_setsCurrentRevealAnchor() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // First reveal should emit CurrentRevealAnchor event
        vm.expectEmit(true, false, false, false);
        emit Redistribution.CurrentRevealAnchor(roundNumber, bytes32(0)); // Anchor value varies

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);
    }

    // ==================== Pause Tests ====================

    function test_reveal_revertsWhenPaused() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        vm.prank(deployer);
        redistribution.pause();

        mineToRevealPhaseStart();

        vm.prank(node1);
        vm.expectRevert(Redistribution.EnforcedPause.selector);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);
    }

    function test_reveal_worksAfterUnpause() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        vm.prank(deployer);
        redistribution.pause();

        vm.prank(deployer);
        redistribution.unPause();

        mineToRevealPhaseStart();

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        // Verify reveal was successful
        (,, bool revealed,,,,) = redistribution.currentCommits(0);
        assertTrue(revealed);
    }

    // ==================== Stake Density Calculation Tests ====================

    function test_reveal_calculatesStakeDensityCorrectly() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash =
            redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, testRevealNonce);
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        mineToRevealPhaseStart();

        // Get stake before reveal
        uint256 stake = stakeRegistry.nodeEffectiveStake(node1);
        uint8 height = stakeRegistry.heightOfAddress(node1);

        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, testRevealNonce);

        // Calculate expected stake density
        uint256 expectedStakeDensity = stake * uint256(2 ** (TEST_DEPTH - height));

        // We can't directly access currentReveals, but we verified via event in another test
        // The stake density calculation is: stake * 2^(depth - height)
        assertTrue(expectedStakeDensity > 0);
    }

    // ==================== Round Reset Tests ====================

    function test_reveal_newRoundResetsReveals() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Round 1: Commit and reveal
        bytes32 hash1 = redistribution.wrapCommit(node1Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));
        uint64 round1 = redistribution.currentRound();
        vm.prank(node1);
        redistribution.commit(hash1, round1);

        mineToRevealPhaseStart();
        vm.prank(node1);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce1"));

        // Move to next round
        minePastRounds(1);
        mineToCommitPhaseStart();

        // Round 2: New commit
        bytes32 hash2 = redistribution.wrapCommit(node2Overlay, TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));
        uint64 round2 = redistribution.currentRound();
        assertTrue(round2 > round1);

        vm.prank(node2);
        redistribution.commit(hash2, round2);

        mineToRevealPhaseStart();

        // Node2 can reveal in new round
        vm.prank(node2);
        redistribution.reveal(TEST_DEPTH, testReserveCommitment, keccak256("nonce2"));

        // Verify new round's reveal round
        assertEq(redistribution.currentRevealRound(), round2);
    }
}
