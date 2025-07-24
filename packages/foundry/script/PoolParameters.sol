// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";

/// @title PoolParameters
/// @notice Provides static PoolKey configurations and deployment parameters for supported chains
library PoolParameters {
    
    /// @notice Comprehensive deployment parameters for resource estimation and deployment
    struct DeploymentParams {
        uint256 hookFundingAmount;      // ETH for hook (1000+ invocations)
        uint256 liquidityUSDCAmount;    // USDC per pool for liquidity
        uint256 pool1Price;             // ETH price for pool 1 (e.g., 3000 USDC)
        uint256 pool2Price;             // ETH price for pool 2 (e.g., 4000 USDC)
        uint256 demoAccountFunding;     // USDC for demo accounts
        uint256 bufferPercentage;       // Safety buffer percentage (e.g., 500)
        uint256 testSwapAmount;         // Amount for testing swaps
        uint256 maxSlippage;           // Maximum slippage for swaps (basis points)
        address[] demoAccounts;         // List of demo accounts to fund
    }
    
    /// @notice Get comprehensive deployment parameters for a given chain
    /// @param chainId The chain ID
    /// @return params The deployment parameters struct
    function getDeploymentParams(uint256 chainId) internal pure returns (DeploymentParams memory params) {
        // Base parameters (same for all chains)
        params.hookFundingAmount = 0.01 ether;        // 10x more for 1000+ invocations
        params.liquidityUSDCAmount = 1e6;             // 1 USDC per pool (6 decimals)
        params.pool1Price = 3000;                     // ETH = 3000 USDC (lower bound, current ~3600)
        params.pool2Price = 4000;                     // ETH = 4000 USDC (upper bound, current ~3600)  
        params.demoAccountFunding = 10_000e6;         // 10k USDC per demo account
        params.bufferPercentage = 500;                // 500% safety buffer
        params.testSwapAmount = 1e6;                  // 1 USDC for test swaps (follows 1/1000th rule)
        params.maxSlippage = 500;                     // 5% max slippage (500 basis points)
        
        // Chain-specific demo accounts
        if (chainId == 31337) {
            // Local Anvil - use default Anvil accounts
            params.demoAccounts = new address[](2);
            params.demoAccounts[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1
            params.demoAccounts[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account 2
        } else if (chainId == 421614) {
            // Arbitrum Sepolia - demo accounts for testing
            params.demoAccounts = new address[](1);
            params.demoAccounts[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Demo account
        } else {
            // Other chains - minimal demo accounts
            params.demoAccounts = new address[](0);
        }
        
        return params;
    }
    
    /// @notice Calculate total ETH needed for deployment
    /// @param params The deployment parameters
    /// @return totalETH Total ETH required including buffer
    function calculateTotalETHNeeded(DeploymentParams memory params) internal pure returns (uint256 totalETH) {
        // Hook funding (main component)
        uint256 hookETH = params.hookFundingAmount;
        
        // Liquidity ETH using proper Uniswap V4 mathematics with realistic ETH targets
        uint256 targetETHPerPool = 0.1 ether; // 0.1 ETH per pool as specified
        
        (uint256 liquidityETH1,,) = HookLibrary.calculateETHUSDCLiquidityV4(
            targetETHPerPool, 
            params.pool1Price, 
            10, // ±10% range as specified
            60  // Standard tick spacing
        );
        (uint256 liquidityETH2,,) = HookLibrary.calculateETHUSDCLiquidityV4(
            targetETHPerPool, 
            params.pool2Price, 
            10, // ±10% range as specified
            60  // Standard tick spacing
        );
        
        // Demo account ETH (for gas)
        uint256 demoETH = 0.01 ether * params.demoAccounts.length;
        
        // Test swap ETH 
        uint256 avgPrice = (params.pool1Price + params.pool2Price) / 2;
        uint256 testSwapETH = (params.testSwapAmount * 1e18) / (avgPrice * 1e6);
        
        uint256 baseETH = hookETH + liquidityETH1 + liquidityETH2 + demoETH + testSwapETH;
        uint256 bufferETH = (baseETH * params.bufferPercentage) / 100;
        
        totalETH = baseETH + bufferETH;
        return totalETH;
    }
    
    /// @notice Calculate total USDC needed for deployment using proper liquidity math
    /// @param params The deployment parameters
    /// @return totalUSDC Total USDC required
    function calculateTotalUSDCNeeded(DeploymentParams memory params) internal pure returns (uint256 totalUSDC) {
        // Liquidity USDC using proper Uniswap V4 calculations
        uint256 targetETHPerPool = 0.1 ether; // 0.1 ETH per pool as specified
        
        (, uint256 usdcForPool1,) = HookLibrary.calculateETHUSDCLiquidityV4(
            targetETHPerPool, 
            params.pool1Price, 
            10, // ±10% range as specified
            60  // Standard tick spacing
        );
        (, uint256 usdcForPool2,) = HookLibrary.calculateETHUSDCLiquidityV4(
            targetETHPerPool, 
            params.pool2Price, 
            10, // ±10% range as specified
            60  // Standard tick spacing
        );
        
        // Demo account funding
        uint256 demoUSDC = params.demoAccountFunding * params.demoAccounts.length;
        
        // Test swap amount
        uint256 testUSDC = params.testSwapAmount;
        
        totalUSDC = usdcForPool1 + usdcForPool2 + demoUSDC + testUSDC;
        return totalUSDC;
    }
    
    /// @notice Get deployment key environment variable name for a chain
    /// @param chainId The chain ID
    /// @return envVarName The environment variable name (e.g., "DEPLOYMENT_KEY_421614")
    function getDeploymentKeyEnvVar(uint256 chainId) internal pure returns (string memory) {
        return string.concat("DEPLOYMENT_KEY_", _uint2str(chainId));
    }
    
    /// @notice Get chain name for display purposes
    /// @param chainId The chain ID
    /// @return chainName Human-readable chain name
    function getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 1) return "Ethereum Mainnet";
        if (chainId == 11155111) return "Ethereum Sepolia";
        if (chainId == 42161) return "Arbitrum One";
        if (chainId == 421614) return "Arbitrum Sepolia";
        if (chainId == 130) return "Unichain Mainnet";
        if (chainId == 1301) return "Unichain Sepolia";
        if (chainId == 31337) return "Local Anvil";
        return string.concat("Chain ", _uint2str(chainId));
    }

    /// @notice Get PoolKey1 (ETH/USDC, 0.05% fee, tickSpacing 10)
    /// @param chainId The chain ID
    /// @param hook The DetoxHook address
    /// @param usdc The USDC token address
    /// @return poolKey The PoolKey struct
    function getPoolKey1(uint256 chainId, address hook, address usdc) internal pure returns (PoolKey memory poolKey) {
        if (chainId == 31337) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 10,
                hooks: IHooks(hook)
            });
        } else if (chainId == 421614) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 10,
                hooks: IHooks(hook)
            });
        }
        revert("Unsupported chain");
    }

    /// @notice Get PoolKey2 (ETH/USDC, 0.05% fee, tickSpacing 60)
    /// @param chainId The chain ID
    /// @param hook The DetoxHook address
    /// @param usdc The USDC token address
    /// @return poolKey The PoolKey struct
    function getPoolKey2(uint256 chainId, address hook, address usdc) internal pure returns (PoolKey memory poolKey) {
        if (chainId == 31337) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 60,
                hooks: IHooks(hook)
            });
        } else if (chainId == 421614) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 60,
                hooks: IHooks(hook)
            });
        }
        revert("Unsupported chain");
    }
    
    /// @notice Convert uint256 to string (internal utility)
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
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
} 