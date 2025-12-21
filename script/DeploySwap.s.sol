// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {SimpleSwapFactory} from "../src/swap/SimpleSwapFactory.sol";

/**
 * @title DeploySwap
 * @notice Deploys the SWAP payment channel factory contract
 * @dev Run with:
 *   BZZ_TOKEN=0x... forge script script/DeploySwap.s.sol:DeploySwap --rpc-url <rpc_url> --broadcast
 */
contract DeploySwap is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address bzzToken = vm.envAddress("BZZ_TOKEN");

        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("BZZ Token:", bzzToken);

        vm.startBroadcast(deployerPrivateKey);

        SimpleSwapFactory factory = new SimpleSwapFactory(bzzToken);
        console.log("SimpleSwapFactory deployed at:", address(factory));
        console.log("Master SimpleSwap at:", factory.master());

        vm.stopBroadcast();

        console.log("");
        console.log("=== SWAP Deployment Complete ===");
        console.log("SimpleSwapFactory:", address(factory));
    }
}
