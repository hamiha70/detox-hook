// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {SwapRouterFixed} from "../src/SwapRouterFixed.sol";
import {ChainAddresses} from "./ChainAddresses.sol";
import {PoolParameters} from "./PoolParameters.sol";

/// @title SwapRouterFixed Deployment Script
/// @notice Standalone script to deploy SwapRouterFixed for DetoxHook demo
contract DeploySwapRouterFixed is Script {
    using ChainAddresses for uint256;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    // Contract instances
    SwapRouterFixed public swapRouterFixedInstance;
    IPoolManager public poolManager;

    // Deployment state
    address public deployer;

    /// @notice Main deployment function
    function run() external {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("=== SwapRouterFixed Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);

        // Initialize contracts
        _initializeContracts();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SwapRouterFixed
        _deploySwapRouterFixed();

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    /// @notice Initialize contract addresses
    function _initializeContracts() internal {
        console.log("=== Contract Initialization ===");

        // Get PoolManager address
        poolManager = IPoolManager(
            ChainAddresses.getPoolManager(block.chainid)
        );
        console.log("Pool Manager:", address(poolManager));

        // Verify PoolManager exists
        require(address(poolManager).code.length > 0, "PoolManager not found");
        console.log("PoolManager verified");
    }

    /// @notice Deploy SwapRouterFixed
    function _deploySwapRouterFixed() internal {
        console.log("=== Deploying SwapRouterFixed ===");

        // Get PoolSwapTest address
        address poolSwapTest = ChainAddresses.getPoolSwapTest(block.chainid);
        require(
            poolSwapTest != address(0),
            "PoolSwapTest address not set for this chain"
        );
        console.log("PoolSwapTest:", poolSwapTest);

        // Get DetoxHook address (our deployed DetoxHookV2)
        address detoxHook = 0x444F320aA27e73e1E293c14B22EfBDCbce0e0088;
        require(detoxHook != address(0), "DetoxHook address not found");
        console.log("DetoxHook:", detoxHook);

        // Get USDC address
        address usdc = ChainAddresses.getUSDC(block.chainid);
        require(usdc != address(0), "USDC address not set for this chain");
        console.log("USDC:", usdc);

        // Create pool key
        PoolKey memory poolKey = PoolParameters.getPoolKey1(
            block.chainid,
            detoxHook,
            usdc
        );
        console.log("Pool Key created:");
        console.log("  Currency0:", Currency.unwrap(poolKey.currency0));
        console.log("  Currency1:", Currency.unwrap(poolKey.currency1));
        console.log("  Fee:", poolKey.fee);
        console.log("  TickSpacing:", poolKey.tickSpacing);
        console.log("  Hooks:", address(poolKey.hooks));

        // Deploy SwapRouterFixed
        swapRouterFixedInstance = new SwapRouterFixed(poolSwapTest, poolKey);
        console.log(
            "SwapRouterFixed deployed at:",
            address(swapRouterFixedInstance)
        );

        // Verify configuration
        PoolKey memory deployedPoolKey = swapRouterFixedInstance
            .getPoolConfiguration();
        console.log("Configuration verified:");
        console.log("  Currency0:", Currency.unwrap(deployedPoolKey.currency0));
        console.log("  Currency1:", Currency.unwrap(deployedPoolKey.currency1));
        console.log("  Fee:", deployedPoolKey.fee);
        console.log("  TickSpacing:", deployedPoolKey.tickSpacing);
        console.log("  Hooks:", address(deployedPoolKey.hooks));

        require(
            address(deployedPoolKey.hooks) == detoxHook,
            "SwapRouterFixed not configured with correct DetoxHook"
        );
        console.log("SwapRouterFixed configuration verified successfully");
    }

    /// @notice Log deployment summary
    function _logDeploymentSummary() internal view {
        console.log("");
        console.log("===============================================");
        console.log("        SWAPROUTERFIXED DEPLOYED!            ");
        console.log("===============================================");
        console.log("");
        console.log(
            "[SWAPROUTERFIXED ADDRESS]:",
            address(swapRouterFixedInstance)
        );
        console.log("");

        console.log("=== Deployment Summary ===");
        console.log("Chain:", ChainAddresses.getChainName(block.chainid));
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("SwapRouterFixed:", address(swapRouterFixedInstance));
        console.log("Pool Manager:", address(poolManager));

        console.log("");
        console.log("=== Demo Ready ===");
        console.log("You can now test the demo with:");
        console.log("yarn swap-router --getpool");
        console.log("yarn swap-router --swap 0.00002 false");
        console.log("");
    }

    /// @notice Test deployment configuration without broadcasting
    /// @dev This function validates all deployment parameters and dependencies
    function testDeployment() external {
        // Skip this test on local Anvil since it requires real network infrastructure
        vm.skip(block.chainid == 31337);

        console.log("=== TESTING SWAPROUTERFIXED DEPLOYMENT CONFIGURATION ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));

        // Initialize contracts (validates addresses exist)
        _initializeContracts();

        // Validate all required addresses
        console.log("=== Validating Dependencies ===");

        // Check PoolSwapTest
        address poolSwapTest = ChainAddresses.getPoolSwapTest(block.chainid);
        require(
            poolSwapTest != address(0),
            "PoolSwapTest address not set for this chain"
        );
        require(
            poolSwapTest.code.length > 0,
            "PoolSwapTest contract not deployed"
        );
        console.log("[SUCCESS] PoolSwapTest validated:", poolSwapTest);

        // Check DetoxHook (hardcoded address)
        address detoxHook = 0x07Fae0457E31b0047363d63ac3Dc3e446abf0088;
        require(detoxHook != address(0), "DetoxHook address is zero");
        require(detoxHook.code.length > 0, "DetoxHook contract not deployed");
        console.log("[SUCCESS] DetoxHook validated:", detoxHook);

        // Check USDC
        address usdc = ChainAddresses.getUSDC(block.chainid);
        require(usdc != address(0), "USDC address not set for this chain");
        require(usdc.code.length > 0, "USDC contract not deployed");
        console.log("[SUCCESS] USDC validated:", usdc);

        // Validate pool key creation
        PoolKey memory poolKey = PoolParameters.getPoolKey1(
            block.chainid,
            detoxHook,
            usdc
        );
        console.log("[SUCCESS] Pool Key created successfully:");
        console.log("  Currency0:", Currency.unwrap(poolKey.currency0));
        console.log("  Currency1:", Currency.unwrap(poolKey.currency1));
        console.log("  Fee:", poolKey.fee);
        console.log("  TickSpacing:", poolKey.tickSpacing);
        console.log("  Hooks:", address(poolKey.hooks));

        // Validate currency ordering (ETH should be currency0)
        require(
            Currency.unwrap(poolKey.currency0) == address(0),
            "ETH should be currency0"
        );
        require(
            Currency.unwrap(poolKey.currency1) == usdc,
            "USDC should be currency1"
        );
        console.log("[SUCCESS] Currency ordering validated (ETH < USDC)");

        console.log("");
        console.log("[SUCCESS] All deployment configuration tests PASSED!");
        console.log(
            "[SUCCESS] SwapRouterFixed deployment is ready for:",
            ChainAddresses.getChainName(block.chainid)
        );
        console.log("");
        console.log("To deploy, run:");
        console.log("make deploy-swap-router-arbitrum-sepolia");
        console.log("");
    }
}
