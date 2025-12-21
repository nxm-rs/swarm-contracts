// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { RedistributionBase } from "./RedistributionBase.t.sol";
import { Redistribution } from "../../../src/incentives/Redistribution.sol";

/// @title RedistributionCommitTest
/// @notice Tests for the commit phase of the Redistribution contract
contract RedistributionCommitTest is RedistributionBase {
    // ==================== Commit Requirement Tests ====================

    function test_commit_revertsIfNotStaked() public {
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        vm.expectRevert(Redistribution.NotStaked.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    function test_commit_revertsIfStakedTooRecently() public {
        stakeNode(node1, bytes32(uint256(1)));
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        vm.expectRevert(Redistribution.MustStake2Rounds.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    function test_commit_revertsIfNotCommitPhase() public {
        setupStakedNodes();
        mineToCommitPhaseStart();
        mineToRevealPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        vm.expectRevert(Redistribution.NotCommitPhase.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    function test_commit_revertsIfRoundOver() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound() - 1;

        vm.prank(node1);
        vm.expectRevert(Redistribution.CommitRoundOver.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    function test_commit_revertsIfRoundNotStarted() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound() + 1;

        vm.prank(node1);
        vm.expectRevert(Redistribution.CommitRoundNotStarted.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    function test_commit_revertsInLastBlockOfPhase() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        // Move to last block of commit phase
        uint256 currentBlock = block.number;
        uint256 roundStart = (currentBlock / ROUND_LENGTH) * ROUND_LENGTH;
        uint256 lastCommitBlock = roundStart + (ROUND_LENGTH / 4) - 1;
        vm.roll(lastCommitBlock);

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        vm.expectRevert(Redistribution.PhaseLastBlock.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    // ==================== Successful Commit Tests ====================

    function test_commit_success() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        assertEq(redistribution.currentCommitRound(), roundNumber);
    }

    function test_commit_storesCommitData() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        // Read the commit from storage
        (
            bytes32 overlay,
            address owner,
            bool revealed,
            uint8 height,
            uint256 stake,
            bytes32 storedHash,
            uint256 revealIndex
        ) = redistribution.currentCommits(0);

        assertEq(overlay, node1Overlay);
        assertEq(owner, node1);
        assertFalse(revealed);
        assertEq(storedHash, obfuscatedHash);
    }

    function test_commit_emitsEvent() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        // Height is set during staking (DEFAULT_HEIGHT = 16)
        vm.expectEmit(true, true, true, true);
        emit Redistribution.Committed(roundNumber, node1Overlay, DEFAULT_HEIGHT);

        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    // ==================== Multiple Commit Tests ====================

    function test_commit_revertsIfAlreadyCommitted() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.startPrank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        vm.expectRevert(Redistribution.AlreadyCommitted.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
        vm.stopPrank();
    }

    function test_commit_multipleNodesCanCommit() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        redistribution.commit(keccak256("node1"), roundNumber);

        vm.prank(node2);
        redistribution.commit(keccak256("node2"), roundNumber);

        vm.prank(node3);
        redistribution.commit(keccak256("node3"), roundNumber);

        // Verify all commits were stored
        (, address owner1,,,,,) = redistribution.currentCommits(0);
        (, address owner2,,,,,) = redistribution.currentCommits(1);
        (, address owner3,,,,,) = redistribution.currentCommits(2);

        assertEq(owner1, node1);
        assertEq(owner2, node2);
        assertEq(owner3, node3);
    }

    // ==================== New Round Resets Commits ====================

    function test_commit_newRoundResetsCommits() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint64 round1 = redistribution.currentRound();

        vm.prank(node1);
        redistribution.commit(keccak256("round1"), round1);

        // Move to next round
        minePastRounds(1);
        mineToCommitPhaseStart();

        uint64 round2 = redistribution.currentRound();
        assertTrue(round2 > round1);

        // Node2 commits in new round
        vm.prank(node2);
        redistribution.commit(keccak256("round2"), round2);

        // The first commit should now be node2's
        (, address owner,,,,,) = redistribution.currentCommits(0);
        assertEq(owner, node2);
    }

    // ==================== Pause Tests ====================

    function test_commit_revertsWhenPaused() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        vm.prank(deployer);
        redistribution.pause();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        vm.expectRevert(Redistribution.EnforcedPause.selector);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    function test_commit_worksAfterUnpause() public {
        setupStakedNodes();

        vm.prank(deployer);
        redistribution.pause();

        vm.prank(deployer);
        redistribution.unPause();

        mineToCommitPhaseStart();

        bytes32 obfuscatedHash = keccak256("test");
        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        assertEq(redistribution.currentCommitRound(), roundNumber);
    }

    // ==================== Commit with Proper Hash ====================

    function test_commit_withProperWrapCommit() public {
        setupStakedNodes();
        mineToCommitPhaseStart();

        uint8 depth = 16;
        bytes32 reserveCommitment = keccak256("reserve");
        bytes32 revealNonce = keccak256("nonce");

        bytes32 obfuscatedHash = redistribution.wrapCommit(node1Overlay, depth, reserveCommitment, revealNonce);

        uint64 roundNumber = redistribution.currentRound();

        vm.prank(node1);
        redistribution.commit(obfuscatedHash, roundNumber);

        (,,,,, bytes32 storedHash,) = redistribution.currentCommits(0);
        assertEq(storedHash, obfuscatedHash);
    }
}
