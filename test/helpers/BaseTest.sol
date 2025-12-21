// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { TestToken } from "../../src/common/TestToken.sol";

/// @title BaseTest
/// @notice Base contract for all Swarm contract tests
/// @dev Provides common setup, utilities, and test accounts
abstract contract BaseTest is Test {
    // Test accounts
    address public deployer;
    address public admin;
    address public stamper;
    address public oracle;
    address public redistributor;
    address public pauser;
    address public alice;
    address public bob;
    address public carol;

    // Node accounts (for staking/redistribution tests)
    address[] public nodes;

    // Common contracts
    TestToken public token;

    // Constants
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;
    uint256 public constant ROUND_LENGTH = 152;

    function setUp() public virtual {
        // Create labeled accounts
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");
        stamper = makeAddr("stamper");
        oracle = makeAddr("oracle");
        redistributor = makeAddr("redistributor");
        pauser = makeAddr("pauser");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        // Create node accounts
        for (uint256 i = 0; i < 8; i++) {
            nodes.push(makeAddr(string.concat("node_", vm.toString(i))));
        }

        // Deploy test token
        vm.startPrank(deployer);
        token = new TestToken();
        vm.stopPrank();

        // Fund test accounts
        _fundAccounts();
    }

    function _fundAccounts() internal {
        vm.startPrank(deployer);
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
        token.mint(carol, INITIAL_BALANCE);
        token.mint(stamper, INITIAL_BALANCE);
        for (uint256 i = 0; i < nodes.length; i++) {
            token.mint(nodes[i], INITIAL_BALANCE);
        }
        vm.stopPrank();
    }

    // ==================== Utility Functions ====================

    /// @notice Mine blocks to reach a specific round
    function mineToRound(uint256 targetRound) internal {
        uint256 currentRound = block.number / ROUND_LENGTH;
        if (targetRound > currentRound) {
            uint256 blocksToMine = (targetRound - currentRound) * ROUND_LENGTH;
            vm.roll(block.number + blocksToMine);
        }
    }

    /// @notice Mine to the commit phase of the current round
    function mineToCommitPhase() internal {
        uint256 currentRound = block.number / ROUND_LENGTH;
        uint256 roundStart = currentRound * ROUND_LENGTH;
        // Commit phase is first quarter of round
        if (block.number >= roundStart + ROUND_LENGTH / 4) {
            // Already past commit phase, go to next round
            mineToRound(currentRound + 1);
        }
    }

    /// @notice Mine to the reveal phase of the current round
    function mineToRevealPhase() internal {
        uint256 currentRound = block.number / ROUND_LENGTH;
        uint256 roundStart = currentRound * ROUND_LENGTH;
        uint256 revealStart = roundStart + ROUND_LENGTH / 4;
        uint256 revealEnd = roundStart + ROUND_LENGTH / 2;

        if (block.number < revealStart) {
            vm.roll(revealStart);
        } else if (block.number >= revealEnd) {
            // Past reveal phase, go to next round's reveal
            mineToRound(currentRound + 1);
            mineToRevealPhase();
        }
    }

    /// @notice Mine to the claim phase of the current round
    function mineToClaimPhase() internal {
        uint256 currentRound = block.number / ROUND_LENGTH;
        uint256 roundStart = currentRound * ROUND_LENGTH;
        uint256 claimStart = roundStart + ROUND_LENGTH / 2;

        if (block.number < claimStart) {
            vm.roll(claimStart);
        }
    }

    /// @notice Get the current round number
    function currentRound() internal view returns (uint64) {
        return uint64(block.number / ROUND_LENGTH);
    }

    /// @notice Check if currently in commit phase
    function isCommitPhase() internal view returns (bool) {
        return block.number % ROUND_LENGTH < ROUND_LENGTH / 4;
    }

    /// @notice Check if currently in reveal phase
    function isRevealPhase() internal view returns (bool) {
        uint256 pos = block.number % ROUND_LENGTH;
        return pos >= ROUND_LENGTH / 4 && pos < ROUND_LENGTH / 2;
    }

    /// @notice Check if currently in claim phase
    function isClaimPhase() internal view returns (bool) {
        return block.number % ROUND_LENGTH >= ROUND_LENGTH / 2;
    }

    /// @notice Calculate proximity order between two overlays
    function proximity(bytes32 a, bytes32 b) internal pure returns (uint8) {
        bytes32 xorResult = a ^ b;
        if (xorResult == bytes32(0)) return 255;

        uint8 po = 0;
        for (uint256 i = 0; i < 256; i++) {
            if (uint256(xorResult) < (1 << (255 - i))) {
                po++;
            } else {
                break;
            }
        }
        return po;
    }

    /// @notice Compute batch ID from sender and nonce
    function computeBatchId(address sender, bytes32 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender, nonce));
    }
}
