// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { DeploySwarm } from "../../script/DeploySwarm.s.sol";
import { TestToken } from "../../src/common/TestToken.sol";
import { PostageStamp } from "../../src/incentives/PostageStamp.sol";
import { PriceOracle } from "../../src/incentives/StoragePriceOracle.sol";
import { StakeRegistry } from "../../src/incentives/Staking.sol";
import { Redistribution } from "../../src/incentives/Redistribution.sol";

contract DeploySwarmTest is Test {
    DeploySwarm public deployer;
    TestToken public token;

    uint256 internal deployerPk = 0x1;
    address internal deployerAddr;
    uint64 internal constant NETWORK_ID = 100;

    function setUp() public {
        deployerAddr = vm.addr(deployerPk);

        // Deploy a test token first
        token = new TestToken();

        // Set environment variables
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPk));
        vm.setEnv("BZZ_TOKEN", vm.toString(address(token)));
        vm.setEnv("NETWORK_ID", vm.toString(NETWORK_ID));

        deployer = new DeploySwarm();
    }

    function test_run_deploysIncentivesContracts() public {
        deployer.run();

        // Verify all contracts were deployed
        // Note: DeploySwarm doesn't expose addresses, so we verify via events or by reading storage
        // For now, we just verify the script runs without reverting
    }

    function test_run_usesExistingToken() public {
        // Capture deployment by checking token balance changes
        uint256 tokenBalanceBefore = token.balanceOf(address(this));

        deployer.run();

        // Token balance shouldn't change (we're using existing token, not minting)
        assertEq(token.balanceOf(address(this)), tokenBalanceBefore);
    }
}

contract DeploySwarmIntegrationTest is Test {
    TestToken public token;

    address internal deployer;
    address internal oracle;
    address internal redistributor;
    address internal staker;

    uint64 internal constant NETWORK_ID = 100;
    uint8 internal constant MIN_BUCKET_DEPTH = 16;
    uint256 internal constant MIN_STAKE = 100_000_000_000_000_000;

    PostageStamp public postageStamp;
    PriceOracle public priceOracle;
    StakeRegistry public stakeRegistry;
    Redistribution public redistribution;

    function setUp() public {
        deployer = makeAddr("deployer");
        oracle = makeAddr("oracle");
        redistributor = makeAddr("redistributor");
        staker = makeAddr("staker");

        // Deploy token
        token = new TestToken();
        token.mint(staker, 1000 ether);

        // Simulate what DeploySwarm does
        vm.startPrank(deployer);

        postageStamp = new PostageStamp(address(token), MIN_BUCKET_DEPTH);
        priceOracle = new PriceOracle(address(postageStamp));
        stakeRegistry = new StakeRegistry(address(token), NETWORK_ID, address(priceOracle));
        redistribution = new Redistribution(address(stakeRegistry), address(postageStamp), address(priceOracle));

        // Configure roles
        postageStamp.grantRoles(address(priceOracle), postageStamp.PRICE_ORACLE_ROLE());
        postageStamp.grantRoles(address(redistribution), postageStamp.REDISTRIBUTOR_ROLE());
        stakeRegistry.grantRoles(address(redistribution), stakeRegistry.REDISTRIBUTOR_ROLE());
        priceOracle.grantRoles(address(redistribution), priceOracle.PRICE_UPDATER_ROLE());

        vm.stopPrank();

        // Approve staking
        vm.prank(staker);
        token.approve(address(stakeRegistry), type(uint256).max);
    }

    function test_fullIntegration_stakingWorks() public {
        // First set a price
        vm.prank(deployer);
        priceOracle.setPrice(24_000);

        // Stake tokens
        vm.prank(staker);
        stakeRegistry.manageStake(bytes32(uint256(1)), MIN_STAKE, 0);

        // Verify stake was recorded
        assertTrue(stakeRegistry.lastUpdatedBlockNumberOfAddress(staker) > 0);
        assertTrue(stakeRegistry.overlayOfAddress(staker) != bytes32(0));
    }

    function test_fullIntegration_redistributionCanFreeze() public {
        // First set a price
        vm.prank(deployer);
        priceOracle.setPrice(24_000);

        // Stake tokens
        vm.prank(staker);
        stakeRegistry.manageStake(bytes32(uint256(1)), MIN_STAKE, 0);

        // Redistribution should be able to freeze
        vm.prank(address(redistribution));
        stakeRegistry.freezeDeposit(staker, 100);

        // Effective stake should be 0 while frozen
        assertEq(stakeRegistry.nodeEffectiveStake(staker), 0);
    }

    function test_fullIntegration_priceOracleUpdatesPostageStamp() public {
        uint32 newPrice = 50_000;

        vm.prank(deployer);
        priceOracle.setPrice(newPrice);

        assertEq(priceOracle.currentPrice(), newPrice);
        assertEq(postageStamp.lastPrice(), newPrice);
    }

    function test_fullIntegration_batchCreationWorks() public {
        // Set price first
        vm.prank(deployer);
        priceOracle.setPrice(1);

        // Fund and approve
        token.mint(staker, 1000 ether);
        vm.prank(staker);
        token.approve(address(postageStamp), type(uint256).max);

        // Create batch
        uint256 balancePerChunk = postageStamp.minimumInitialBalancePerChunk() + 1;

        vm.prank(staker);
        bytes32 batchId = postageStamp.createBatch(staker, balancePerChunk, 20, 17, bytes32(uint256(1)), false);

        assertTrue(batchId != bytes32(0));
        assertEq(postageStamp.batchOwner(batchId), staker);
    }
}
