// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/PoolStateViewer.sol";
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract DeployPoolStateViewer is Script {
    // Arbitrum Sepolia PoolManager address
    address constant POOL_MANAGER_ADDRESS =
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;

    function run() external {
        console.log("Deploying PoolStateViewer to Arbitrum Sepolia");
        console.log("PoolManager Address:", POOL_MANAGER_ADDRESS);

        // Verify we're on the correct network
        uint256 chainId = block.chainid;
        console.log("Chain ID:", chainId);

        if (chainId != 421614) {
            console.log(
                "Warning: Expected Arbitrum Sepolia (421614), got chain ID:",
                chainId
            );
        }

        vm.startBroadcast();

        try new PoolStateViewer(IPoolManager(POOL_MANAGER_ADDRESS)) returns (
            PoolStateViewer viewer
        ) {
            console.log(
                "PoolStateViewer deployed successfully at:",
                address(viewer)
            );

            // Verify deployment by calling a simple function
            try viewer.poolManager() returns (IPoolManager manager) {
                console.log("Contract verification successful");
                console.log(
                    "PoolManager address from contract:",
                    address(manager)
                );

                if (address(manager) == POOL_MANAGER_ADDRESS) {
                    console.log("PoolManager address matches expected value");
                } else {
                    console.log("PoolManager address mismatch");
                }
            } catch {
                console.log("Contract verification failed");
            }
        } catch Error(string memory reason) {
            console.log("Deployment failed:", reason);
            revert("Deployment failed");
        } catch {
            console.log("Deployment failed with unknown error");
            revert("Deployment failed");
        }

        vm.stopBroadcast();

        console.log("Deployment script completed");
    }
}
