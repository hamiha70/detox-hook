// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../DeployDetoxHook.s.sol";
import { ChainAddresses } from "../ChainAddresses.sol";

/// @title Example: Deploy DetoxHook to Arbitrum Sepolia
/// @notice This script demonstrates how to deploy DetoxHook to Arbitrum Sepolia testnet
/// @dev Run with: forge script script/examples/DeployToArbitrumSepolia.s.sol --rpc-url $ARB_SEPOLIA_RPC --broadcast
contract DeployToArbitrumSepolia is DeployDetoxHook {
    
    /// @notice Deploy DetoxHook to Arbitrum Sepolia with validation
    function run() external override {
        // Validate we're on the correct network
        require(block.chainid == ChainAddresses.ARBITRUM_SEPOLIA, "Must be run on Arbitrum Sepolia");
        
        console.log("=== Deploying DetoxHook to Arbitrum Sepolia ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        
        // Log all relevant addresses
        logArbitrumSepoliaAddresses();
        
        // Get private key and start broadcast
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the hook
        address poolManager = ChainAddresses.getPoolManager(block.chainid);
        DetoxHook hook = deployDetoxHook(poolManager);
        
        vm.stopBroadcast();
        
        // Log final deployment info
        logFinalDeploymentInfo(hook);
    }
    
    /// @notice Log all Arbitrum Sepolia addresses for reference
    function logArbitrumSepoliaAddresses() internal view {
        console.log("=== Arbitrum Sepolia V4 Ecosystem ===");
        
        ChainAddresses.V4Addresses memory addresses = ChainAddresses.getAllAddresses(block.chainid);
        
        console.log("Pool Manager:", addresses.poolManager);
        console.log("Universal Router:", addresses.universalRouter);
        console.log("Position Manager:", addresses.positionManager);
        console.log("State View:", addresses.stateView);
        console.log("Quoter:", addresses.quoter);
        console.log("Pool Swap Test:", addresses.poolSwapTest);
        console.log("Pool Modify Liquidity Test:", addresses.poolModifyLiquidityTest);
        console.log("Permit2:", addresses.permit2);
        console.log("Pyth Oracle:", addresses.pythOracle);
        console.log("USDC Token:", addresses.usdc);
        console.log("Block Explorer:", ChainAddresses.getBlockExplorer(block.chainid));
        console.log("");
    }
    
    /// @notice Log final deployment information with useful links
    function logFinalDeploymentInfo(DetoxHook hook) internal view {
        console.log("=== Deployment Success! ===");
        console.log("DetoxHook Address:", address(hook));
        console.log("");
        console.log("=== Useful Links ===");
        console.log("Block Explorer:", ChainAddresses.getBlockExplorer(block.chainid));
        console.log("Contract URL:", string.concat(
            ChainAddresses.getBlockExplorer(block.chainid),
            "/address/",
            vm.toString(address(hook))
        ));
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Verify the contract on the block explorer");
        console.log("2. Initialize a pool with this hook");
        console.log("3. Add liquidity to test the hook functionality");
        console.log("4. Test swaps to ensure the hook is working correctly");
        console.log("");
        console.log("=== Pool Initialization Example ===");
        console.log("Pool Manager:", ChainAddresses.getPoolManager(block.chainid));
        console.log("Hook Address:", address(hook));
        console.log("Suggested ETH/USDC Price:", ChainAddresses.getCurrentEthUsdcSqrtPriceX96());
        console.log("USDC Address:", ChainAddresses.getUSDC(block.chainid));
    }
    
    /// @notice Utility function to check deployment readiness
    function checkDeploymentReadiness() external view {
        console.log("=== Deployment Readiness Check ===");
        
        // Check chain
        if (block.chainid != ChainAddresses.ARBITRUM_SEPOLIA) {
            console.log("[FAIL] Wrong chain! Expected Arbitrum Sepolia (421614), got:", block.chainid);
            return;
        }
        console.log("[PASS] Chain: Arbitrum Sepolia");
        
        // Check addresses - validate manually since we can't use try-catch with internal functions
        if (!ChainAddresses.isChainSupported(block.chainid)) {
            console.log("[FAIL] Chain is not supported");
            return;
        }
        
        // Check that Pool Manager is set
        address poolManager = ChainAddresses.getPoolManager(block.chainid);
        if (poolManager == address(0)) {
            console.log("[FAIL] Pool Manager address is not set");
            return;
        }
        console.log("[PASS] All required addresses are configured");
        
        // Check environment variables - we'll just log a note since we can't access env vars in view functions
        console.log("[INFO] Make sure PRIVATE_KEY environment variable is set before deployment");
        
        console.log("[PASS] Ready for deployment!");
        console.log("");
        console.log("Run deployment with:");
        console.log("forge script script/examples/DeployToArbitrumSepolia.s.sol \\");
        console.log("  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \\");
        console.log("  --broadcast \\");
        console.log("  --verify");
    }
} 