// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PoolParameters } from "./PoolParameters.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title Estimate Deployment Resources
/// @notice Standalone script to estimate ETH and USDC requirements for DetoxHook deployment
/// @dev Sources parameters from PoolParameters.sol for consistency
contract EstimateDeploymentResources is Script {
    using PoolParameters for uint256;

    /// @notice Main script entry point - estimates resources for current chain
    function run() external view {
        uint256 chainId = block.chainid;
        string memory chainName = PoolParameters.getChainName(chainId);
        
        console.log("=== DETOXHOOK DEPLOYMENT RESOURCE ESTIMATION ===");
        console.log("Chain ID:", chainId);
        console.log("Chain Name:", chainName);
        console.log("");
        
        // Display assumptions
        _displayAssumptions(chainId);
        
        // Get resource estimates
        (uint256 ethNeeded, uint256 usdcNeeded) = this.getResourceEstimate(chainId);
        
        // Display breakdown
        _displayResourceBreakdown(chainId);
        
        // Display deployer validation
        _displayDeployerValidation(ethNeeded);
        
        // Display final summary
        _displaySummary(ethNeeded, usdcNeeded);
    }
    
    /// @notice Get resource estimate for a specific chain
    /// @param chainId The chain ID to estimate for
    /// @return ethNeeded Total ETH needed for deployment
    /// @return usdcNeeded Total USDC needed (will be minted)
    function getResourceEstimate(uint256 chainId) external pure returns (uint256 ethNeeded, uint256 usdcNeeded) {
        PoolParameters.DeploymentParams memory params = PoolParameters.getDeploymentParams(chainId);
        
        ethNeeded = PoolParameters.calculateTotalETHNeeded(params);
        usdcNeeded = PoolParameters.calculateTotalUSDCNeeded(params);
        
        return (ethNeeded, usdcNeeded);
    }
    
    /// @notice Display detailed resource breakdown
    function _displayResourceBreakdown(uint256 chainId) internal pure {
        PoolParameters.DeploymentParams memory params = PoolParameters.getDeploymentParams(chainId);
        
        console.log("=== RESOURCE BREAKDOWN ===");
        
        // ETH breakdown
        console.log("ETH REQUIREMENTS:");
        console.log("  Hook Funding:", _formatETH(params.hookFundingAmount));
        
        // Calculate liquidity needs using proper Uniswap V4 mathematics with realistic ETH targets
        uint256 targetETHPerPool = 0.1 ether; // 0.1 ETH per pool as per your specification
        
        (uint256 ethForPool1, uint256 usdcForPool1, ModifyLiquidityParams memory liquidityParams1) = 
            HookLibrary.calculateETHUSDCLiquidityV4(
                targetETHPerPool, 
                params.pool1Price, 
                10, // ±10% range as specified
                60  // Standard tick spacing
            );
        (uint256 ethForPool2, uint256 usdcForPool2, ModifyLiquidityParams memory liquidityParams2) = 
            HookLibrary.calculateETHUSDCLiquidityV4(
                targetETHPerPool, 
                params.pool2Price, 
                10, // ±10% range as specified  
                60  // Standard tick spacing
            );
                console.log("  Pool 1 ETH needed:", _formatETH(ethForPool1));
        console.log("  Pool 1 USDC needed:", usdcForPool1 / 1e6, "USDC");
        console.log("  Pool 1 tick lower:", liquidityParams1.tickLower);
        console.log("  Pool 1 tick upper:", liquidityParams1.tickUpper);
        console.log("  Pool 2 ETH needed:", _formatETH(ethForPool2));
        console.log("  Pool 2 USDC needed:", usdcForPool2 / 1e6, "USDC");
        console.log("  Pool 2 tick lower:", liquidityParams2.tickLower);
        console.log("  Pool 2 tick upper:", liquidityParams2.tickUpper);
        
        // Demo account funding (ETH for gas - assume 0.01 ETH per account)
        uint256 demoETH = 0.01 ether * params.demoAccounts.length;
        console.log("  Demo Accounts:", _formatETH(demoETH));
        
        // Test swaps (convert USDC to ETH at average price)
        uint256 avgPrice = (params.pool1Price + params.pool2Price) / 2; // Average ETH price
        uint256 testSwapETH = (params.testSwapAmount * 1e18) / (avgPrice * 1e6);
        console.log("  Test Swaps:", _formatETH(testSwapETH));
        
        // Calculate subtotal and buffer
        uint256 subtotal = params.hookFundingAmount + ethForPool1 + ethForPool2 + demoETH + testSwapETH;
        uint256 buffer = (subtotal * params.bufferPercentage) / 100;
        console.log("  Buffer:", _formatETH(buffer));
        console.log("  Buffer percentage:", params.bufferPercentage);
        
        uint256 totalETH = subtotal + buffer;
        console.log("  TOTAL ETH:", _formatETH(totalETH));
        console.log("");
        
        // Gas cost estimates
        console.log("GAS COST ESTIMATES:");
        uint256 gasPrice = 0.1 gwei; // Conservative estimate
        uint256 deploymentGas = 3_000_000; // ~3M gas for all contracts
        uint256 poolInitGas = 200_000 * 2; // 200k gas per pool * 2 pools
        uint256 liquidityGas = 300_000 * 2; // 300k gas per pool * 2 pools
        uint256 totalGas = deploymentGas + poolInitGas + liquidityGas;
        uint256 totalGasCost = totalGas * gasPrice;
        
        console.log("  Contract deployment:", _formatETH(deploymentGas * gasPrice));
        console.log("  Pool initialization:", _formatETH(poolInitGas * gasPrice));
        console.log("  Liquidity provision:", _formatETH(liquidityGas * gasPrice));
        console.log("  TOTAL GAS COST:", _formatETH(totalGasCost));
        console.log("  Note: Gas included in buffer above");
        console.log("");
        
        // USDC breakdown (using calculated amounts from liquidity math)
        console.log("USDC REQUIREMENTS (MINTED):");
        console.log("  Pool 1 Liquidity:", usdcForPool1 / 1e6, "USDC");
        console.log("  Pool 2 Liquidity:", usdcForPool2 / 1e6, "USDC");
        console.log("  Demo Accounts:", params.demoAccountFunding / 1e6, "USDC each");
        console.log("  Demo Account Count:", params.demoAccounts.length);
        
        uint256 totalUSDC = usdcForPool1 + usdcForPool2 + (params.demoAccountFunding * params.demoAccounts.length);
        console.log("  TOTAL USDC:", totalUSDC / 1e6, "USDC");
        console.log("");
        
        // Validate liquidity-swap consistency
        console.log("=== LIQUIDITY-SWAP CONSISTENCY VALIDATION ===");
        _validateLiquiditySwapConsistency(params, usdcForPool1, usdcForPool2);
        console.log("");
    }
    
    /// @notice Validate that swap amounts are reasonable relative to liquidity
    /// @param params Deployment parameters
    /// @param usdcPool1 USDC liquidity for pool 1
    /// @param usdcPool2 USDC liquidity for pool 2
    function _validateLiquiditySwapConsistency(
        PoolParameters.DeploymentParams memory params,
        uint256 usdcPool1,
        uint256 usdcPool2
    ) internal pure {
        // Rule: Swap amounts should be ≤ 1/1000th of pool liquidity
        uint256 maxRecommendedSwap1 = usdcPool1 / 1000;
        uint256 maxRecommendedSwap2 = usdcPool2 / 1000;
        uint256 minMaxSwap = maxRecommendedSwap1 < maxRecommendedSwap2 ? maxRecommendedSwap1 : maxRecommendedSwap2;
        
        console.log("LIQUIDITY-SWAP RATIO VALIDATION:");
        console.log("  Pool 1 liquidity:", usdcPool1 / 1e6, "USDC");
        console.log("  Pool 1 max recommended swap:", maxRecommendedSwap1 / 1e6, "USDC");
        console.log("  Pool 2 liquidity:", usdcPool2 / 1e6, "USDC");
        console.log("  Pool 2 max recommended swap:", maxRecommendedSwap2 / 1e6, "USDC");
        console.log("  Current test swap amount:", params.testSwapAmount / 1e6, "USDC");
        
        // Validation
        if (params.testSwapAmount <= minMaxSwap) {
            console.log("  Status: [PASS] Swap amount within 1/1000th rule");
        } else {
            console.log("  Status: [WARN] Swap amount exceeds recommended 1/1000th");
            console.log("  Recommendation: Reduce to", minMaxSwap / 1e6, "USDC or less");
        }
        
        // Additional context
        uint256 swapToLiquidityRatio = (params.testSwapAmount * 10000) / minMaxSwap;
        console.log("  Swap/Liquidity ratio:", swapToLiquidityRatio, "basis points");
        console.log("  (1000 bp = 1/100th, 100 bp = 1/1000th)");
    }
    
    /// @notice Display deployer balance validation
    function _displayDeployerValidation(uint256 totalETHNeeded) internal view {
        console.log("=== DEPLOYER BALANCE VALIDATION ===");
        
        // Get deployer address
        string memory keyEnvVar = PoolParameters.getDeploymentKeyEnvVar(block.chainid);
        console.log("Deployment Key Env Var:", keyEnvVar);
        
        // Try to get deployer balance (may fail if key not set)
        try vm.envUint(keyEnvVar) returns (uint256 deployerPrivateKey) {
            address deployer = vm.addr(deployerPrivateKey);
            uint256 deployerBalance = deployer.balance;
            
            console.log("Deployer Address:", deployer);
            console.log("Current ETH Balance:", _formatETH(deployerBalance));
            console.log("Required ETH Balance:", _formatETH(totalETHNeeded));
            
            if (deployerBalance >= totalETHNeeded) {
                console.log("Status: SUFFICIENT ETH [PASS]");
            } else {
                uint256 shortage = totalETHNeeded - deployerBalance;
                console.log("Status: INSUFFICIENT ETH [FAIL]");
                console.log("Shortage:", _formatETH(shortage));
                console.log("Need to fund deployer with additional ETH");
            }
        } catch {
            console.log("Status: Cannot validate (deployment key not set)");
            console.log("Set environment variable:", keyEnvVar);
        }
        
        console.log("");
    }
    
    /// @notice Display final summary
    function _displaySummary(uint256 totalETHNeeded, uint256 totalUSDCNeeded) internal pure {
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("RESOURCE REQUIREMENTS:");
        console.log("  ETH Required:", _formatETH(totalETHNeeded));
        console.log("  USDC Required:", totalUSDCNeeded / 1e6);
        console.log("  Note: USDC will be minted");
        console.log("");
        
        console.log("KEY COMPONENTS:");
        console.log("  Hook: Funded for 1000+ invocations");
        console.log("  Pools: 2 pools with liquidity");
        console.log("  Demo: Accounts funded for testing");
        console.log("  Swaps: Reserve for test swaps");
        console.log("  Buffer: 500% safety margin");
        console.log("");
        
        console.log("NEXT STEPS:");
        console.log("  1. Ensure deployer has sufficient ETH");
        console.log("  2. Set deployment key environment variable");
        console.log("  3. Run: forge script script/DeployDetoxHookComplete.s.sol");
        console.log("");
        
        console.log("TIP: Run this script anytime to check resource requirements");
        console.log("Command: forge script script/EstimateDeploymentResources.s.sol");
        console.log("");
    }
    
    /// @notice Display deployment assumptions and parameters
    function _displayAssumptions(uint256 chainId) internal pure {
        PoolParameters.DeploymentParams memory params = PoolParameters.getDeploymentParams(chainId);
        
        console.log("=== DEPLOYMENT ASSUMPTIONS ===");
        console.log("POOL CONFIGURATION:");
        console.log("  Pool 1 Price:", params.pool1Price, "USDC per ETH");
        console.log("  Pool 2 Price:", params.pool2Price, "USDC per ETH");
        console.log("  Pool Fee: 0.05% (500)");
        console.log("  Tick Spacing: 10 (Pool 1), 60 (Pool 2)");
        console.log("");
        
        console.log("LIQUIDITY PROVISION:");
        console.log("  Target ETH per pool: 0.1 ETH");
        console.log("  Liquidity range: +/-10% around current price");
        console.log("  Proper Uniswap V4 mathematics with TickMath and LiquidityAmounts");
        console.log("  Realistic concentrated liquidity requirements");
        console.log("");
        
        console.log("OPERATIONAL PARAMETERS:");
        console.log("  Hook invocations: 1000+ supported");
        console.log("  Demo accounts:", params.demoAccounts.length);
        console.log("  Demo funding:", params.demoAccountFunding / 1e6, "USDC each");
        console.log("  Test swap reserve:", params.testSwapAmount / 1e6, "USDC");
        console.log("  Safety buffer:", params.bufferPercentage, "%");
        console.log("  Max slippage:", params.maxSlippage / 100, "%");
        console.log("");
        
        console.log("GAS ASSUMPTIONS:");
        console.log("  Contract deployment: ~3M gas");
        console.log("  Pool initialization: ~200k gas each");
        console.log("  Liquidity addition: ~300k gas each");
        console.log("  Hook invocation: ~100k gas each");
        console.log("  Estimated gas price: 0.1 gwei");
        console.log("");
    }

    /// @notice Format wei amount as readable ETH string
    /// @param weiAmount Amount in wei
    /// @return Formatted string like "0.012345 ETH"
    function _formatETH(uint256 weiAmount) internal pure returns (string memory) {
        if (weiAmount == 0) return "0 ETH";
        
        // Convert to ETH (divide by 1e18)
        uint256 ethWhole = weiAmount / 1e18;
        uint256 ethFraction = (weiAmount % 1e18) / 1e12; // 6 decimal places
        
        // Format as string
        if (ethWhole > 0) {
            return string(abi.encodePacked(_uint2str(ethWhole), ".", _padDecimals(ethFraction, 6), " ETH"));
        } else {
            return string(abi.encodePacked("0.", _padDecimals(ethFraction, 6), " ETH"));
        }
    }
    
    /// @notice Convert uint to string
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
    
    /// @notice Pad decimal places for display
    function _padDecimals(uint256 fraction, uint256 places) internal pure returns (string memory) {
        string memory result = _uint2str(fraction);
        bytes memory resultBytes = bytes(result);
        
        // Pad with leading zeros if needed
        if (resultBytes.length < places) {
            uint256 zerosNeeded = places - resultBytes.length;
            bytes memory padded = new bytes(places);
            
            // Add leading zeros
            for (uint256 i = 0; i < zerosNeeded; i++) {
                padded[i] = "0";
            }
            
            // Add the actual digits
            for (uint256 i = 0; i < resultBytes.length; i++) {
                padded[zerosNeeded + i] = resultBytes[i];
            }
            
            return string(padded);
        }
        
        return result;
    }
} 