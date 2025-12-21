// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../src/common/TestToken.sol";
import {PostageStamp} from "../src/incentives/PostageStamp.sol";
import {PriceOracle} from "../src/incentives/StoragePriceOracle.sol";
import {StakeRegistry} from "../src/incentives/Staking.sol";
import {Redistribution} from "../src/incentives/Redistribution.sol";
import {SimpleSwapFactory} from "../src/swap/SimpleSwapFactory.sol";

/**
 * @title DeployAll
 * @notice Deploys all Swarm contracts in the correct order
 * @dev Run with: forge script script/DeployAll.s.sol:DeployAll --rpc-url <rpc_url> --broadcast
 */
contract DeployAll is Script {
    // Deployment configuration
    uint8 public constant MIN_BUCKET_DEPTH = 16;
    uint64 public constant NETWORK_ID = 1; // Mainnet

    // Deployed contract addresses
    address public token;
    address public postageStamp;
    address public priceOracle;
    address public stakeRegistry;
    address public redistribution;
    address public swapFactory;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Network ID:", NETWORK_ID);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy TestToken (or use existing BZZ token address)
        TestToken tokenContract = new TestToken();
        token = address(tokenContract);
        console.log("TestToken deployed at:", token);

        // 2. Deploy PostageStamp
        PostageStamp postageContract = new PostageStamp(token, MIN_BUCKET_DEPTH);
        postageStamp = address(postageContract);
        console.log("PostageStamp deployed at:", postageStamp);

        // 3. Deploy PriceOracle
        PriceOracle oracleContract = new PriceOracle(postageStamp);
        priceOracle = address(oracleContract);
        console.log("PriceOracle deployed at:", priceOracle);

        // 4. Deploy StakeRegistry
        StakeRegistry stakeContract = new StakeRegistry(token, NETWORK_ID, priceOracle);
        stakeRegistry = address(stakeContract);
        console.log("StakeRegistry deployed at:", stakeRegistry);

        // 5. Deploy Redistribution
        Redistribution redistContract = new Redistribution(stakeRegistry, postageStamp, priceOracle);
        redistribution = address(redistContract);
        console.log("Redistribution deployed at:", redistribution);

        // 6. Deploy SimpleSwapFactory
        SimpleSwapFactory factoryContract = new SimpleSwapFactory(token);
        swapFactory = address(factoryContract);
        console.log("SimpleSwapFactory deployed at:", swapFactory);

        // Configure roles
        _configureRoles(postageContract, oracleContract, stakeContract);

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("Token:", token);
        console.log("PostageStamp:", postageStamp);
        console.log("PriceOracle:", priceOracle);
        console.log("StakeRegistry:", stakeRegistry);
        console.log("Redistribution:", redistribution);
        console.log("SimpleSwapFactory:", swapFactory);
    }

    function _configureRoles(
        PostageStamp postageContract,
        PriceOracle oracleContract,
        StakeRegistry stakeContract
    ) internal {
        console.log("");
        console.log("Configuring roles...");

        // Grant PriceOracle the PRICE_ORACLE_ROLE on PostageStamp
        postageContract.grantRoles(priceOracle, postageContract.PRICE_ORACLE_ROLE());
        console.log("Granted PRICE_ORACLE_ROLE to PriceOracle on PostageStamp");

        // Grant Redistribution the REDISTRIBUTOR_ROLE on PostageStamp
        postageContract.grantRoles(redistribution, postageContract.REDISTRIBUTOR_ROLE());
        console.log("Granted REDISTRIBUTOR_ROLE to Redistribution on PostageStamp");

        // Grant Redistribution the REDISTRIBUTOR_ROLE on StakeRegistry
        stakeContract.grantRoles(redistribution, stakeContract.REDISTRIBUTOR_ROLE());
        console.log("Granted REDISTRIBUTOR_ROLE to Redistribution on StakeRegistry");

        // Grant Redistribution the PRICE_UPDATER_ROLE on PriceOracle
        oracleContract.grantRoles(redistribution, oracleContract.PRICE_UPDATER_ROLE());
        console.log("Granted PRICE_UPDATER_ROLE to Redistribution on PriceOracle");
    }
}
