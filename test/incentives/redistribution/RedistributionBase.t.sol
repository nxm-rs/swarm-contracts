// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { Redistribution } from "../../../src/incentives/Redistribution.sol";
import { PostageStamp } from "../../../src/incentives/PostageStamp.sol";
import { StakeRegistry } from "../../../src/incentives/Staking.sol";
import { TestToken } from "../../../src/common/TestToken.sol";
import { BaseTest } from "../../helpers/BaseTest.sol";

/// @title MockPriceOracle
/// @notice Mock price oracle for redistribution testing
contract MockPriceOracle {
    uint32 public price = 24_000;
    bool public adjustPriceResult = true;

    function currentPrice() external view returns (uint32) {
        return price;
    }

    function setPrice(uint32 _price) external {
        price = _price;
    }

    function adjustPrice(uint16) external view returns (bool) {
        return adjustPriceResult;
    }

    function setAdjustPriceResult(bool _result) external {
        adjustPriceResult = _result;
    }
}

/// @title RedistributionBase
/// @notice Base test contract for Redistribution tests with full system setup
/// @dev Inherits from BaseTest for common utilities and sets up the complete
///      redistribution system including PostageStamp, StakeRegistry, and mocks
abstract contract RedistributionBase is BaseTest {
    // Core contracts
    Redistribution public redistribution;
    PostageStamp public postageStamp;
    StakeRegistry public stakeRegistry;
    MockPriceOracle public priceOracle;

    // Test node accounts with private keys for signing
    uint256 internal node1Pk = 0x100;
    uint256 internal node2Pk = 0x200;
    uint256 internal node3Pk = 0x300;
    uint256 internal node4Pk = 0x400;

    address internal node1;
    address internal node2;
    address internal node3;
    address internal node4;

    // Constants
    uint64 internal constant NETWORK_ID = 1;
    uint8 internal constant MIN_BUCKET_DEPTH = 16;
    uint256 internal constant MIN_STAKE = 100_000_000_000_000_000; // 0.1 ether
    uint8 internal constant DEFAULT_HEIGHT = 16; // Height for staking (must match reveal depth for proximity)

    // Node overlays (computed after staking)
    bytes32 internal node1Overlay;
    bytes32 internal node2Overlay;
    bytes32 internal node3Overlay;
    bytes32 internal node4Overlay;

    function setUp() public virtual override {
        super.setUp();

        // Ensure we start at a high enough block number to avoid underflow
        // when checking stake age (block.number - 2 * ROUND_LENGTH)
        vm.roll(ROUND_LENGTH * 10);

        // Derive node addresses from private keys
        node1 = vm.addr(node1Pk);
        node2 = vm.addr(node2Pk);
        node3 = vm.addr(node3Pk);
        node4 = vm.addr(node4Pk);

        vm.label(node1, "node1");
        vm.label(node2, "node2");
        vm.label(node3, "node3");
        vm.label(node4, "node4");

        _deployContracts();
        _configureRoles();
        _fundNodes();
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        priceOracle = new MockPriceOracle();
        postageStamp = new PostageStamp(address(token), MIN_BUCKET_DEPTH);
        stakeRegistry = new StakeRegistry(address(token), NETWORK_ID, address(priceOracle));
        redistribution = new Redistribution(address(stakeRegistry), address(postageStamp), address(priceOracle));

        vm.stopPrank();
    }

    function _configureRoles() internal {
        vm.startPrank(deployer);

        // PostageStamp roles
        postageStamp.grantRoles(address(priceOracle), postageStamp.PRICE_ORACLE_ROLE());
        postageStamp.grantRoles(address(redistribution), postageStamp.REDISTRIBUTOR_ROLE());

        // StakeRegistry roles
        stakeRegistry.grantRoles(address(redistribution), stakeRegistry.REDISTRIBUTOR_ROLE());

        vm.stopPrank();
    }

    function _fundNodes() internal {
        vm.startPrank(deployer);
        token.mint(node1, INITIAL_BALANCE);
        token.mint(node2, INITIAL_BALANCE);
        token.mint(node3, INITIAL_BALANCE);
        token.mint(node4, INITIAL_BALANCE);
        vm.stopPrank();

        // Approve staking for all nodes
        vm.prank(node1);
        token.approve(address(stakeRegistry), type(uint256).max);
        vm.prank(node2);
        token.approve(address(stakeRegistry), type(uint256).max);
        vm.prank(node3);
        token.approve(address(stakeRegistry), type(uint256).max);
        vm.prank(node4);
        token.approve(address(stakeRegistry), type(uint256).max);
    }

    // ==================== Staking Helpers ====================

    /// @notice Stake for a node with a specific nonce
    function stakeNode(address node, bytes32 nonce) internal {
        vm.prank(node);
        stakeRegistry.manageStake(nonce, MIN_STAKE, 0);
    }

    /// @notice Stake for a node with a specific nonce and amount
    function stakeNode(address node, bytes32 nonce, uint256 amount) internal {
        vm.prank(node);
        stakeRegistry.manageStake(nonce, amount, 0);
    }

    /// @notice Stake for a node with nonce, amount, and height
    function stakeNode(address node, bytes32 nonce, uint256 amount, uint8 height) internal {
        vm.prank(node);
        stakeRegistry.manageStake(nonce, amount, height);
    }

    /// @notice Setup all test nodes with stakes and wait required time
    /// @dev Uses DEFAULT_HEIGHT (16) so that depth=16 reveals pass proximity check
    ///      Minimum stake scales with height: MIN_STAKE * 2^height
    function setupStakedNodes() internal {
        uint256 scaledMinStake = MIN_STAKE * (2 ** DEFAULT_HEIGHT);
        stakeNode(node1, bytes32(uint256(1)), scaledMinStake, DEFAULT_HEIGHT);
        stakeNode(node2, bytes32(uint256(2)), scaledMinStake, DEFAULT_HEIGHT);
        stakeNode(node3, bytes32(uint256(3)), scaledMinStake, DEFAULT_HEIGHT);
        stakeNode(node4, bytes32(uint256(4)), scaledMinStake, DEFAULT_HEIGHT);

        // Store overlays
        node1Overlay = stakeRegistry.overlayOfAddress(node1);
        node2Overlay = stakeRegistry.overlayOfAddress(node2);
        node3Overlay = stakeRegistry.overlayOfAddress(node3);
        node4Overlay = stakeRegistry.overlayOfAddress(node4);

        // Wait 2 rounds as required by the protocol
        minePastRounds(2);
    }

    // ==================== Phase Navigation Helpers ====================

    /// @notice Mine to the start of the commit phase
    function mineToCommitPhaseStart() internal {
        uint256 currentBlock = block.number;
        uint256 roundStart = (currentBlock / ROUND_LENGTH) * ROUND_LENGTH;
        uint256 nextRoundStart = roundStart + ROUND_LENGTH;
        vm.roll(nextRoundStart);
    }

    /// @notice Mine to the start of the reveal phase
    function mineToRevealPhaseStart() internal {
        uint256 currentBlock = block.number;
        uint256 roundStart = (currentBlock / ROUND_LENGTH) * ROUND_LENGTH;
        uint256 revealStart = roundStart + (ROUND_LENGTH / 4);
        if (block.number >= revealStart) {
            // Already past reveal start, go to next round's reveal
            vm.roll(roundStart + ROUND_LENGTH + (ROUND_LENGTH / 4));
        } else {
            vm.roll(revealStart);
        }
    }

    /// @notice Mine to the start of the claim phase
    function mineToClaimPhaseStart() internal {
        uint256 currentBlock = block.number;
        uint256 roundStart = (currentBlock / ROUND_LENGTH) * ROUND_LENGTH;
        uint256 claimStart = roundStart + (ROUND_LENGTH / 2);
        if (block.number >= claimStart) {
            // Already in claim phase
            return;
        }
        vm.roll(claimStart);
    }

    /// @notice Mine past a number of rounds
    function minePastRounds(uint256 numRounds) internal {
        vm.roll(block.number + numRounds * ROUND_LENGTH + 1);
    }

    // ==================== Commit/Reveal Helpers ====================

    /// @notice Create an obfuscated commit hash
    function createCommitHash(bytes32 overlay, uint8 depth, bytes32 reserveCommitment, bytes32 revealNonce)
        internal
        view
        returns (bytes32)
    {
        return redistribution.wrapCommit(overlay, depth, reserveCommitment, revealNonce);
    }

    /// @notice Commit for a node
    function commitForNode(address node, bytes32 obfuscatedHash) internal {
        uint64 roundNumber = redistribution.currentRound();
        vm.prank(node);
        redistribution.commit(obfuscatedHash, roundNumber);
    }

    /// @notice Reveal for a node
    function revealForNode(address node, uint8 depth, bytes32 reserveCommitment, bytes32 revealNonce) internal {
        vm.prank(node);
        redistribution.reveal(depth, reserveCommitment, revealNonce);
    }

    // ==================== Assertion Helpers ====================

    /// @notice Assert we're in commit phase
    function assertInCommitPhase() internal view {
        assertTrue(redistribution.currentPhaseCommit(), "Expected to be in commit phase");
    }

    /// @notice Assert we're in reveal phase
    function assertInRevealPhase() internal view {
        assertTrue(redistribution.currentPhaseReveal(), "Expected to be in reveal phase");
    }

    /// @notice Assert we're in claim phase
    function assertInClaimPhase() internal view {
        assertTrue(redistribution.currentPhaseClaim(), "Expected to be in claim phase");
    }
}
