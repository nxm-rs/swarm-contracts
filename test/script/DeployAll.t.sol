// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { DeployAll } from "../../script/DeployAll.s.sol";
import { TestToken } from "../../src/common/TestToken.sol";
import { PostageStamp } from "../../src/incentives/PostageStamp.sol";
import { PriceOracle as StoragePriceOracle } from "../../src/incentives/StoragePriceOracle.sol";
import { PriceOracle as SwapPriceOracle } from "../../src/swap/SwapPriceOracle.sol";
import { StakeRegistry } from "../../src/incentives/Staking.sol";
import { Redistribution } from "../../src/incentives/Redistribution.sol";
import { SimpleSwapFactory } from "../../src/swap/SimpleSwapFactory.sol";

contract DeployAllTest is Test {
    DeployAll public deployer;

    uint256 internal deployerPk = 0x1;
    address internal deployerAddr;

    function setUp() public {
        deployerAddr = vm.addr(deployerPk);
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPk));

        deployer = new DeployAll();
    }

    function test_run_deploysAllContracts() public {
        deployer.run();

        assertTrue(deployer.token() != address(0), "Token not deployed");
        assertTrue(deployer.postageStamp() != address(0), "PostageStamp not deployed");
        assertTrue(deployer.storagePriceOracle() != address(0), "StoragePriceOracle not deployed");
        assertTrue(deployer.swapPriceOracle() != address(0), "SwapPriceOracle not deployed");
        assertTrue(deployer.stakeRegistry() != address(0), "StakeRegistry not deployed");
        assertTrue(deployer.redistribution() != address(0), "Redistribution not deployed");
        assertTrue(deployer.swapFactory() != address(0), "SwapFactory not deployed");
    }

    function test_run_configuresPostageStampRoles() public {
        deployer.run();

        PostageStamp postage = PostageStamp(deployer.postageStamp());

        // StoragePriceOracle should have PRICE_ORACLE_ROLE
        assertTrue(
            postage.hasAllRoles(deployer.storagePriceOracle(), postage.PRICE_ORACLE_ROLE()),
            "StoragePriceOracle missing PRICE_ORACLE_ROLE on PostageStamp"
        );

        // Redistribution should have REDISTRIBUTOR_ROLE
        assertTrue(
            postage.hasAllRoles(deployer.redistribution(), postage.REDISTRIBUTOR_ROLE()),
            "Redistribution missing REDISTRIBUTOR_ROLE on PostageStamp"
        );
    }

    function test_run_configuresStakeRegistryRoles() public {
        deployer.run();

        StakeRegistry staking = StakeRegistry(deployer.stakeRegistry());

        // Redistribution should have REDISTRIBUTOR_ROLE
        assertTrue(
            staking.hasAllRoles(deployer.redistribution(), staking.REDISTRIBUTOR_ROLE()),
            "Redistribution missing REDISTRIBUTOR_ROLE on StakeRegistry"
        );
    }

    function test_run_configuresStoragePriceOracleRoles() public {
        deployer.run();

        StoragePriceOracle oracle = StoragePriceOracle(deployer.storagePriceOracle());

        // Redistribution should have PRICE_UPDATER_ROLE
        assertTrue(
            oracle.hasAllRoles(deployer.redistribution(), oracle.PRICE_UPDATER_ROLE()),
            "Redistribution missing PRICE_UPDATER_ROLE on StoragePriceOracle"
        );
    }

    function test_run_setsCorrectOwners() public {
        deployer.run();

        PostageStamp postage = PostageStamp(deployer.postageStamp());
        StoragePriceOracle storageOracle = StoragePriceOracle(deployer.storagePriceOracle());
        SwapPriceOracle swapOracle = SwapPriceOracle(deployer.swapPriceOracle());
        StakeRegistry staking = StakeRegistry(deployer.stakeRegistry());
        Redistribution redist = Redistribution(deployer.redistribution());

        assertEq(postage.owner(), deployerAddr, "PostageStamp owner incorrect");
        assertEq(storageOracle.owner(), deployerAddr, "StoragePriceOracle owner incorrect");
        assertEq(swapOracle.owner(), deployerAddr, "SwapPriceOracle owner incorrect");
        assertEq(staking.owner(), deployerAddr, "StakeRegistry owner incorrect");
        assertEq(redist.owner(), deployerAddr, "Redistribution owner incorrect");
    }

    function test_run_contractsAreConnected() public {
        deployer.run();

        PostageStamp postage = PostageStamp(deployer.postageStamp());
        StoragePriceOracle oracle = StoragePriceOracle(deployer.storagePriceOracle());
        StakeRegistry staking = StakeRegistry(deployer.stakeRegistry());

        // Verify contract linkages
        assertEq(postage.bzzToken(), deployer.token(), "PostageStamp token mismatch");
        assertEq(address(oracle.postageStamp()), deployer.postageStamp(), "StoragePriceOracle postageStamp mismatch");
        assertEq(staking.bzzToken(), deployer.token(), "StakeRegistry token mismatch");
    }

    function test_run_swapFactoryWorks() public {
        deployer.run();

        SimpleSwapFactory factory = SimpleSwapFactory(deployer.swapFactory());

        // Verify factory is configured correctly
        assertEq(factory.ERC20Address(), deployer.token(), "Factory token mismatch");
        assertTrue(factory.master() != address(0), "Factory master not deployed");
    }

    function test_run_storagePriceOracleCanSetPrice() public {
        deployer.run();

        StoragePriceOracle oracle = StoragePriceOracle(deployer.storagePriceOracle());
        PostageStamp postage = PostageStamp(deployer.postageStamp());

        // Owner should be able to set price
        vm.prank(deployerAddr);
        oracle.setPrice(50_000);

        assertEq(oracle.currentPrice(), 50_000, "Oracle price not updated");
        assertEq(postage.lastPrice(), 50_000, "PostageStamp price not updated");
    }

    function test_run_swapPriceOracleWorks() public {
        deployer.run();

        SwapPriceOracle oracle = SwapPriceOracle(deployer.swapPriceOracle());

        // Verify initial values from deployment
        (uint256 price, uint256 deduction) = oracle.getPrice();
        assertEq(price, deployer.SWAP_INITIAL_PRICE(), "SwapPriceOracle initial price incorrect");
        assertEq(deduction, deployer.SWAP_CHEQUE_VALUE_DEDUCTION(), "SwapPriceOracle initial deduction incorrect");

        // Owner should be able to update price
        vm.prank(deployerAddr);
        oracle.updatePrice(20000);

        (price, ) = oracle.getPrice();
        assertEq(price, 20000, "SwapPriceOracle price not updated");
    }

    function test_run_redistributionCanFreezeStakes() public {
        deployer.run();

        StakeRegistry staking = StakeRegistry(deployer.stakeRegistry());
        Redistribution redist = Redistribution(deployer.redistribution());

        // Redistribution contract should be able to freeze stakes
        address testStaker = makeAddr("staker");

        // This should not revert (Redistribution has the role)
        vm.prank(address(redist));
        staking.freezeDeposit(testStaker, 100);
    }

    function test_run_redistributionHasWithdrawRole() public {
        deployer.run();

        PostageStamp postage = PostageStamp(deployer.postageStamp());

        // Verify Redistribution has the REDISTRIBUTOR_ROLE which allows withdraw
        assertTrue(
            postage.hasAllRoles(deployer.redistribution(), postage.REDISTRIBUTOR_ROLE()),
            "Redistribution should have REDISTRIBUTOR_ROLE for withdraw"
        );
    }
}
