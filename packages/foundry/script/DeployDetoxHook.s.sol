// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeployDetoxHookV2 } from "./DeployDetoxHookV2.s.sol";

/// @title DetoxHookDeployScript (LEGACY - Use DeployDetoxHookV2.s.sol instead)
/// @notice DEPRECATED: Legacy deployment script - redirects to DetoxHookV2 deployment
/// @dev This script is kept for compatibility but delegates to DeployDetoxHookV2
contract DeployDetoxHook is Script {
    
    /// @notice Main deployment function - delegates to DeployDetoxHookV2
    function run() external {
        console.log("=== LEGACY DEPLOYMENT SCRIPT ===");
        console.log("[WARNING] This is a legacy script!");
        console.log("[INFO] Delegating to DeployDetoxHookV2.s.sol for actual deployment...");
        console.log("");
        
        // Create and run the V2 deployment script
        DeployDetoxHookV2 v2Deployer = new DeployDetoxHookV2();
        v2Deployer.run();
        
        console.log("");
        console.log("[SUCCESS] Legacy script completed - actual deployment handled by DeployDetoxHookV2");
    }
} 