// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeployDetoxHookV2 } from "../DeployDetoxHookV2.s.sol";

/// @title Example: Deploy DetoxHook to Arbitrum Sepolia (DEPRECATED)
/// @notice DEPRECATED: Use DeployDetoxHookV2.s.sol instead
/// @dev This example script redirects to the production deployment
contract DeployToArbitrumSepolia is Script {

    /// @notice Deploy DetoxHookV2 to Arbitrum Sepolia - delegates to production script
    function run() external {
        console.log("=== DEPRECATED EXAMPLE SCRIPT ===");
        console.log("[WARNING] This example is deprecated!");
        console.log("[INFO] Use DeployDetoxHookV2.s.sol for production deployment");
        console.log("[INFO] Delegating to DeployDetoxHookV2...");
        console.log("");
        
        // Create and run the V2 deployment script
        DeployDetoxHookV2 v2Deployer = new DeployDetoxHookV2();
        v2Deployer.run();
        
        console.log("");
        console.log("[SUCCESS] Example completed - actual deployment handled by DeployDetoxHookV2");
    }
} 