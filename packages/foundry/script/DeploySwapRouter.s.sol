// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DeploySwapRouterFixed } from "./DeploySwapRouterFixed.s.sol";

/// @title DeploySwapRouter (LEGACY - Use DeploySwapRouterFixed.s.sol instead)
/// @notice DEPRECATED: Legacy deployment script - redirects to SwapRouterFixed deployment
/// @dev This script is kept for compatibility but delegates to DeploySwapRouterFixed
contract DeploySwapRouter is Script {
    
    /// @notice Main deployment function - delegates to DeploySwapRouterFixed
    function run() external {
        console.log("=== LEGACY SWAP ROUTER DEPLOYMENT SCRIPT ===");
        console.log("[WARNING] This is a legacy script!");
        console.log("[INFO] Delegating to DeploySwapRouterFixed.s.sol for actual deployment...");
        console.log("");
        
        // Create and run the Fixed deployment script
        DeploySwapRouterFixed fixedDeployer = new DeploySwapRouterFixed();
        fixedDeployer.run();
        
        console.log("");
        console.log("[SUCCESS] Legacy script completed - actual deployment handled by DeploySwapRouterFixed");
    }

    /// @notice Test deployment configuration - delegates to Fixed version
    function testDeployment() external {
        console.log("=== LEGACY TEST FUNCTION ===");
        console.log("[WARNING] DeploySwapRouterFixed doesn't have testDeployment()");
        console.log("[INFO] Use DeploySwapRouterFixed.run() for deployment");
        
        DeploySwapRouterFixed fixedDeployer = new DeploySwapRouterFixed();
        fixedDeployer.run();
    }
} 