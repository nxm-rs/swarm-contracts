// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { TestToken } from "../src/common/TestToken.sol";
import { PostageStamp } from "../src/incentives/PostageStamp.sol";
import { PriceOracle as StoragePriceOracle } from "../src/incentives/StoragePriceOracle.sol";
import { PriceOracle as SwapPriceOracle } from "../src/swap/SwapPriceOracle.sol";
import { StakeRegistry } from "../src/incentives/Staking.sol";
import { Redistribution } from "../src/incentives/Redistribution.sol";
import { SimpleSwapFactory } from "../src/swap/SimpleSwapFactory.sol";

/**
 * @title DeployAll
 * @notice Deploys all Swarm contracts in the correct order
 * @dev Run with: forge script script/DeployAll.s.sol:DeployAll --rpc-url <rpc_url> --broadcast
 *
 * Note: Two price oracles are deployed:
 * - StoragePriceOracle: For postage stamp pricing (storage incentives)
 * - SwapPriceOracle: For SWAP protocol cheque payments (BEE_PRICE_ORACLE_ADDRESS)
 */
contract DeployAll is Script {
    // Deployment configuration
    uint8 public constant MIN_BUCKET_DEPTH = 16;

    // SwapPriceOracle configuration
    // Initial price in PLUR per accounting unit (default from beekeeper)
    uint256 public constant SWAP_INITIAL_PRICE = 10000;
    // Initial cheque value deduction in PLUR (default from beekeeper)
    uint256 public constant SWAP_CHEQUE_VALUE_DEDUCTION = 1;

    // Deployed contract addresses
    address public token;
    address public postageStamp;
    address public storagePriceOracle;
    address public swapPriceOracle;
    address public stakeRegistry;
    address public redistribution;
    address public swapFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint64 networkId = uint64(vm.envOr("NETWORK_ID", uint256(1)));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Network ID:", networkId);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy TestToken (or use existing BZZ token address)
        TestToken tokenContract = new TestToken();
        token = address(tokenContract);
        console.log("TestToken deployed at:", token);

        // 2. Deploy PostageStamp
        PostageStamp postageContract = new PostageStamp(token, MIN_BUCKET_DEPTH);
        postageStamp = address(postageContract);
        console.log("PostageStamp deployed at:", postageStamp);

        // 3. Deploy StoragePriceOracle (for postage stamp pricing)
        StoragePriceOracle storageOracleContract = new StoragePriceOracle(postageStamp);
        storagePriceOracle = address(storageOracleContract);
        console.log("StoragePriceOracle deployed at:", storagePriceOracle);

        // 4. Deploy SwapPriceOracle (for SWAP protocol - this is what Bee nodes use)
        SwapPriceOracle swapOracleContract = new SwapPriceOracle(SWAP_INITIAL_PRICE, SWAP_CHEQUE_VALUE_DEDUCTION);
        swapPriceOracle = address(swapOracleContract);
        console.log("SwapPriceOracle deployed at:", swapPriceOracle);

        // 5. Deploy StakeRegistry
        StakeRegistry stakeContract = new StakeRegistry(token, networkId, storagePriceOracle);
        stakeRegistry = address(stakeContract);
        console.log("StakeRegistry deployed at:", stakeRegistry);

        // 6. Deploy Redistribution
        Redistribution redistContract = new Redistribution(stakeRegistry, postageStamp, storagePriceOracle);
        redistribution = address(redistContract);
        console.log("Redistribution deployed at:", redistribution);

        // 7. Deploy SimpleSwapFactory
        SimpleSwapFactory factoryContract = new SimpleSwapFactory(token);
        swapFactory = address(factoryContract);
        console.log("SimpleSwapFactory deployed at:", swapFactory);

        // Configure roles
        _configureRoles(postageContract, storageOracleContract, stakeContract);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("Token:", token);
        console.log("PostageStamp:", postageStamp);
        console.log("StoragePriceOracle:", storagePriceOracle);
        console.log("SwapPriceOracle:", swapPriceOracle);
        console.log("StakeRegistry:", stakeRegistry);
        console.log("Redistribution:", redistribution);
        console.log("SimpleSwapFactory:", swapFactory);

        // Note: Bee nodes should use SwapPriceOracle for BEE_PRICE_ORACLE_ADDRESS
        console.log("");
        console.log("For Bee node configuration:");
        console.log("  BEE_PRICE_ORACLE_ADDRESS:", swapPriceOracle);
    }

    function _configureRoles(
        PostageStamp postageContract,
        StoragePriceOracle storageOracleContract,
        StakeRegistry stakeContract
    ) internal {
        console.log("");
        console.log("Configuring roles...");

        // Grant StoragePriceOracle the PRICE_ORACLE_ROLE on PostageStamp
        postageContract.grantRoles(storagePriceOracle, postageContract.PRICE_ORACLE_ROLE());
        console.log("Granted PRICE_ORACLE_ROLE to StoragePriceOracle on PostageStamp");

        // Grant Redistribution the REDISTRIBUTOR_ROLE on PostageStamp
        postageContract.grantRoles(redistribution, postageContract.REDISTRIBUTOR_ROLE());
        console.log("Granted REDISTRIBUTOR_ROLE to Redistribution on PostageStamp");

        // Grant Redistribution the REDISTRIBUTOR_ROLE on StakeRegistry
        stakeContract.grantRoles(redistribution, stakeContract.REDISTRIBUTOR_ROLE());
        console.log("Granted REDISTRIBUTOR_ROLE to Redistribution on StakeRegistry");

        // Grant Redistribution the PRICE_UPDATER_ROLE on StoragePriceOracle
        storageOracleContract.grantRoles(redistribution, storageOracleContract.PRICE_UPDATER_ROLE());
        console.log("Granted PRICE_UPDATER_ROLE to Redistribution on StoragePriceOracle");
    }
}
