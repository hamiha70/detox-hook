// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {PoolStateReader} from "../src/PoolStateReader.sol";

/**
 * @title DeployPoolStateReader
 * @notice Deploy the PoolStateReader contract to Arbitrum Sepolia
 */
contract DeployPoolStateReader is Script {
    address constant POOL_MANAGER = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deploying PoolStateReader ===");
        console.log("Deployer:", deployer);
        console.log("PoolManager:", POOL_MANAGER);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PoolStateReader
        PoolStateReader reader = new PoolStateReader(POOL_MANAGER);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("PoolStateReader deployed at:", address(reader));
        console.log(
            "Contract URL:",
            string.concat(
                "https://arbitrum-sepolia.blockscout.com/address/",
                vm.toString(address(reader))
            )
        );

        // Test the deployed contract
        console.log("\n=== Testing Deployed Contract ===");
        testDeployedContract(reader);
    }

    function testDeployedContract(PoolStateReader reader) internal view {
        // Test Pool 1
        (
            uint160 sqrtPriceX96_1,
            int24 tick_1,
            uint24 protocolFee_1,
            uint24 lpFee_1,
            uint128 liquidity_1,
            bool success_1
        ) = reader.getDetoxPool1State();

        if (success_1) {
            console.log(
                "[SUCCESS] Pool 1 working - Price:",
                sqrtPriceX96_1,
                "Tick:",
                uint256(int256(tick_1))
            );
        } else {
            console.log("[ERROR] Pool 1 failed");
        }

        // Test Pool 2
        (
            uint160 sqrtPriceX96_2,
            int24 tick_2,
            uint24 protocolFee_2,
            uint24 lpFee_2,
            uint128 liquidity_2,
            bool success_2
        ) = reader.getDetoxPool2State();

        if (success_2) {
            console.log(
                "[SUCCESS] Pool 2 working - Price:",
                sqrtPriceX96_2,
                "Tick:",
                uint256(int256(tick_2))
            );
        } else {
            console.log("[ERROR] Pool 2 failed");
        }

        // Verify pool IDs
        (bytes32 pool1Id, bytes32 pool2Id) = reader.getDetoxPoolIds();
        console.log("Pool 1 ID verified:");
        console.logBytes32(pool1Id);
        console.log("Pool 2 ID verified:");
        console.logBytes32(pool2Id);
    }
}
