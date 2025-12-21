// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { PostageStamp } from "../src/incentives/PostageStamp.sol";
import { PriceOracle } from "../src/incentives/StoragePriceOracle.sol";
import { StakeRegistry } from "../src/incentives/Staking.sol";
import { Redistribution } from "../src/incentives/Redistribution.sol";

/**
 * @title DeploySwarm
 * @notice Deploys Swarm storage incentives contracts using an existing token
 * @dev Run with:
 *   BZZ_TOKEN=0x... NETWORK_ID=1 forge script script/DeploySwarm.s.sol:DeploySwarm --rpc-url <rpc_url> --broadcast
 */
contract DeploySwarm is Script {
    uint8 public constant MIN_BUCKET_DEPTH = 16;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bzzToken = vm.envAddress("BZZ_TOKEN");
        uint64 networkId = uint64(vm.envUint("NETWORK_ID"));

        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("BZZ Token:", bzzToken);
        console.log("Network ID:", networkId);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PostageStamp
        PostageStamp postageStamp = new PostageStamp(bzzToken, MIN_BUCKET_DEPTH);
        console.log("PostageStamp deployed at:", address(postageStamp));

        // 2. Deploy PriceOracle
        PriceOracle priceOracle = new PriceOracle(address(postageStamp));
        console.log("PriceOracle deployed at:", address(priceOracle));

        // 3. Deploy StakeRegistry
        StakeRegistry stakeRegistry = new StakeRegistry(bzzToken, networkId, address(priceOracle));
        console.log("StakeRegistry deployed at:", address(stakeRegistry));

        // 4. Deploy Redistribution
        Redistribution redistribution =
            new Redistribution(address(stakeRegistry), address(postageStamp), address(priceOracle));
        console.log("Redistribution deployed at:", address(redistribution));

        // Configure roles
        postageStamp.grantRoles(address(priceOracle), postageStamp.PRICE_ORACLE_ROLE());
        postageStamp.grantRoles(address(redistribution), postageStamp.REDISTRIBUTOR_ROLE());
        stakeRegistry.grantRoles(address(redistribution), stakeRegistry.REDISTRIBUTOR_ROLE());
        priceOracle.grantRoles(address(redistribution), priceOracle.PRICE_UPDATER_ROLE());

        console.log("Roles configured");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Storage Incentives Deployment Complete ===");
        console.log("PostageStamp:", address(postageStamp));
        console.log("PriceOracle:", address(priceOracle));
        console.log("StakeRegistry:", address(stakeRegistry));
        console.log("Redistribution:", address(redistribution));
    }
}
