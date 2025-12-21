// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { StakeRegistry } from "../../src/incentives/Staking.sol";
import { TestToken } from "../../src/common/TestToken.sol";

// Mock price oracle for testing
contract MockPriceOracle {
    uint32 public price = 24_000;

    function currentPrice() external view returns (uint32) {
        return price;
    }

    function setPrice(uint32 _price) external {
        price = _price;
    }
}

contract StakingTest is Test {
    StakeRegistry public staking;
    TestToken public token;
    MockPriceOracle public oracle;

    address internal deployer;
    address internal redistributor;
    address internal staker;
    address internal alice;

    uint64 internal constant NETWORK_ID = 1;
    uint256 internal constant MIN_STAKE = 100_000_000_000_000_000; // 0.1 ether
    uint256 internal constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        deployer = makeAddr("deployer");
        redistributor = makeAddr("redistributor");
        staker = makeAddr("staker");
        alice = makeAddr("alice");

        vm.startPrank(deployer);

        token = new TestToken();
        oracle = new MockPriceOracle();
        staking = new StakeRegistry(address(token), NETWORK_ID, address(oracle));

        // Grant redistributor role
        staking.grantRoles(redistributor, staking.REDISTRIBUTOR_ROLE());

        // Fund staker
        token.mint(staker, INITIAL_BALANCE);

        vm.stopPrank();

        // Approve staking contract
        vm.prank(staker);
        token.approve(address(staking), type(uint256).max);
    }

    // ==================== Initialization Tests ====================

    function test_constructor_setsToken() public view {
        assertEq(staking.bzzToken(), address(token));
    }

    function test_constructor_setsOwner() public view {
        assertEq(staking.owner(), deployer);
    }

    // ==================== Stake Management Tests ====================

    function test_manageStake_createsNewStake() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        assertEq(staking.lastUpdatedBlockNumberOfAddress(staker), block.number);
        assertTrue(staking.overlayOfAddress(staker) != bytes32(0));
    }

    function test_manageStake_transfersTokens() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        uint256 balanceBefore = token.balanceOf(staker);

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        assertEq(token.balanceOf(staker), balanceBefore - amount);
        assertEq(token.balanceOf(address(staking)), amount);
    }

    function test_manageStake_revertsWithBelowMinimum() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE - 1;
        uint8 height = 0;

        vm.prank(staker);
        vm.expectRevert(StakeRegistry.BelowMinimumStake.selector);
        staking.manageStake(nonce, amount, height);
    }

    function test_manageStake_withHeight() public {
        bytes32 nonce = bytes32(uint256(1));
        uint8 height = 2;
        // With height 2, minimum is MIN_STAKE * 2^2 = MIN_STAKE * 4
        uint256 amount = MIN_STAKE * 4;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        assertEq(staking.heightOfAddress(staker), height);
    }

    function test_manageStake_updatesExistingStake() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        // Add more stake
        bytes32 newNonce = bytes32(uint256(2));
        uint256 additionalAmount = MIN_STAKE;

        vm.roll(block.number + 1); // Advance block so it's not frozen

        vm.prank(staker);
        staking.manageStake(newNonce, additionalAmount, height);

        // Should have transferred additional tokens
        assertEq(token.balanceOf(address(staking)), amount + additionalAmount);
    }

    function test_manageStake_revertsWhenFrozen() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        // Freeze the stake
        vm.prank(redistributor);
        staking.freezeDeposit(staker, 100);

        // Try to manage stake while frozen
        bytes32 newNonce = bytes32(uint256(2));
        vm.prank(staker);
        vm.expectRevert(StakeRegistry.Frozen.selector);
        staking.manageStake(newNonce, amount, height);
    }

    // ==================== Freeze/Slash Tests ====================

    function test_freezeDeposit_onlyRedistributor() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.freezeDeposit(staker, 100);
    }

    function test_freezeDeposit_freezesStake() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        uint256 freezeTime = 100;
        vm.prank(redistributor);
        staking.freezeDeposit(staker, freezeTime);

        // Effective stake should be 0 while frozen
        assertEq(staking.nodeEffectiveStake(staker), 0);
    }

    function test_slashDeposit_onlyRedistributor() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.slashDeposit(staker, MIN_STAKE);
    }

    function test_slashDeposit_reducesStake() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE * 2;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        uint256 slashAmount = MIN_STAKE;
        vm.prank(redistributor);
        staking.slashDeposit(staker, slashAmount);

        // Stake should be reduced but not deleted
        assertTrue(staking.lastUpdatedBlockNumberOfAddress(staker) != 0);
    }

    function test_slashDeposit_deletesStakeIfFullySlashed() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        // Slash more than stake
        vm.prank(redistributor);
        staking.slashDeposit(staker, amount + 1);

        // Stake should be deleted
        assertEq(staking.lastUpdatedBlockNumberOfAddress(staker), 0);
    }

    // ==================== Pause Tests ====================

    function test_pause_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.pause();
    }

    function test_pause_preventsStaking() public {
        vm.prank(deployer);
        staking.pause();

        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        vm.expectRevert(StakeRegistry.EnforcedPause.selector);
        staking.manageStake(nonce, amount, height);
    }

    function test_unPause_allowsStaking() public {
        vm.prank(deployer);
        staking.pause();

        vm.prank(deployer);
        staking.unPause();

        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        assertEq(staking.lastUpdatedBlockNumberOfAddress(staker), block.number);
    }

    // ==================== Migration Tests ====================

    function test_migrateStake_onlyWhenPaused() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        vm.prank(staker);
        vm.expectRevert(StakeRegistry.ExpectedPause.selector);
        staking.migrateStake();
    }

    function test_migrateStake_returnsTokens() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 amount = MIN_STAKE;
        uint8 height = 0;

        vm.prank(staker);
        staking.manageStake(nonce, amount, height);

        uint256 balanceBefore = token.balanceOf(staker);

        vm.prank(deployer);
        staking.pause();

        vm.prank(staker);
        staking.migrateStake();

        assertEq(token.balanceOf(staker), balanceBefore + amount);
        assertEq(staking.lastUpdatedBlockNumberOfAddress(staker), 0);
    }

    // ==================== Network ID Tests ====================

    function test_changeNetworkId_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.changeNetworkId(2);
    }

    function test_changeNetworkId_updatesId() public {
        uint64 newNetworkId = 100;

        vm.prank(deployer);
        staking.changeNetworkId(newNetworkId);

        // Verify by checking overlay calculation changes
        bytes32 nonce = bytes32(uint256(1));
        vm.prank(staker);
        staking.manageStake(nonce, MIN_STAKE, 0);

        bytes32 overlay = staking.overlayOfAddress(staker);
        assertTrue(overlay != bytes32(0));
    }

    // ==================== View Function Tests ====================

    function test_paused_returnsFalseInitially() public view {
        assertFalse(staking.paused());
    }

    function test_paused_returnsTrueWhenPaused() public {
        vm.prank(deployer);
        staking.pause();

        assertTrue(staking.paused());
    }

    function test_nodeEffectiveStake_returnsZeroForUnstaked() public view {
        assertEq(staking.nodeEffectiveStake(alice), 0);
    }
}
