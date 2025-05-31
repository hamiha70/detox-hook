// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {SwapRouter, IPoolSwapTest} from "../src/SwapRouter.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ChainAddresses} from "./ChainAddresses.sol";

/// @title DeploySwapRouter
/// @notice Deployment script for SwapRouter contract
/// @dev Deploys SwapRouter with proper PoolSwapTest integration for Arbitrum Sepolia
contract DeploySwapRouter is Script {
    using ChainAddresses for uint256;

    // Default pool configuration for USDC/ETH pool
    uint24 constant DEFAULT_FEE = 3000; // 0.3%
    int24 constant DEFAULT_TICK_SPACING = 60;

    // Events for deployment tracking
    event SwapRouterDeployed(
        address indexed swapRouter,
        address indexed poolSwapTest,
        uint256 chainId,
        address currency0,
        address currency1
    );
    event PoolConfigurationSet(
        address indexed swapRouter,
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    );

    /// @notice Main deployment function
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        vm.startBroadcast(deployerPrivateKey);

        SwapRouter swapRouter = deploySwapRouter();

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("SwapRouter deployed at:", address(swapRouter));
        console.log("Chain ID:", block.chainid);
        console.log("Block Explorer:", ChainAddresses.getBlockExplorer(block.chainid));
        console.log("Contract URL:", string.concat(
            ChainAddresses.getBlockExplorer(block.chainid),
            "/address/",
            vm.toString(address(swapRouter))
        ));
    }

    /// @notice Deploy SwapRouter with default configuration
    /// @return swapRouter The deployed SwapRouter instance
    function deploySwapRouter() public returns (SwapRouter swapRouter) {
        console.log("=== SwapRouter Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Deployer:", msg.sender);

        // Validate chain support
        require(ChainAddresses.isChainSupported(block.chainid), "Unsupported chain");

        // Get chain-specific addresses
        address poolSwapTest = getPoolSwapTestAddress();
        PoolKey memory poolKey = getDefaultPoolKey();

        // Deploy SwapRouter
        console.log("=== Deploying SwapRouter ===");
        console.log("PoolSwapTest address:", poolSwapTest);
        console.log("Pool currency0:", Currency.unwrap(poolKey.currency0));
        console.log("Pool currency1:", Currency.unwrap(poolKey.currency1));
        console.log("Pool fee:", poolKey.fee);
        console.log("Pool tick spacing:", poolKey.tickSpacing);

        swapRouter = new SwapRouter(poolSwapTest, poolKey);

        console.log("SwapRouter deployed at:", address(swapRouter));

        // Validate deployment
        validateDeployment(swapRouter, poolSwapTest, poolKey);

        // Emit deployment event
        emit SwapRouterDeployed(
            address(swapRouter),
            poolSwapTest,
            block.chainid,
            Currency.unwrap(poolKey.currency0),
            Currency.unwrap(poolKey.currency1)
        );

        return swapRouter;
    }

    /// @notice Deploy SwapRouter with custom pool configuration
    /// @param customPoolKey Custom pool configuration
    /// @return swapRouter The deployed SwapRouter instance
    function deploySwapRouterWithCustomPool(PoolKey memory customPoolKey) public returns (SwapRouter swapRouter) {
        console.log("=== SwapRouter Custom Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Deployer:", msg.sender);

        // Validate chain support
        require(ChainAddresses.isChainSupported(block.chainid), "Unsupported chain");

        // Get PoolSwapTest address
        address poolSwapTest = getPoolSwapTestAddress();

        // Deploy SwapRouter with custom configuration
        console.log("=== Deploying SwapRouter with Custom Pool ===");
        console.log("PoolSwapTest address:", poolSwapTest);
        console.log("Custom currency0:", Currency.unwrap(customPoolKey.currency0));
        console.log("Custom currency1:", Currency.unwrap(customPoolKey.currency1));
        console.log("Custom fee:", customPoolKey.fee);
        console.log("Custom tick spacing:", customPoolKey.tickSpacing);

        swapRouter = new SwapRouter(poolSwapTest, customPoolKey);

        console.log("SwapRouter deployed at:", address(swapRouter));

        // Validate deployment
        validateDeployment(swapRouter, poolSwapTest, customPoolKey);

        // Emit deployment event
        emit SwapRouterDeployed(
            address(swapRouter),
            poolSwapTest,
            block.chainid,
            Currency.unwrap(customPoolKey.currency0),
            Currency.unwrap(customPoolKey.currency1)
        );

        return swapRouter;
    }

    /// @notice Get PoolSwapTest address for the current chain
    /// @return The PoolSwapTest address
    function getPoolSwapTestAddress() public view returns (address) {
        if (block.chainid == ChainAddresses.LOCAL_ANVIL) {
            // For local development, you might need to deploy PoolSwapTest first
            // or use a mock address for testing
            revert("PoolSwapTest address not set for local development");
        }

        address poolSwapTest = ChainAddresses.getPoolSwapTest(block.chainid);
        require(poolSwapTest != address(0), "PoolSwapTest address not found for this chain");

        return poolSwapTest;
    }

    /// @notice Get default pool configuration (USDC/ETH pool)
    /// @return poolKey The default pool configuration
    function getDefaultPoolKey() public view returns (PoolKey memory poolKey) {
        address usdc = ChainAddresses.getUSDC(block.chainid);
        address eth = address(0); // ETH represented as address(0)

        // Ensure proper token ordering (currency0 < currency1)
        Currency currency0;
        Currency currency1;

        if (eth < usdc) {
            currency0 = Currency.wrap(eth);
            currency1 = Currency.wrap(usdc);
        } else {
            currency0 = Currency.wrap(usdc);
            currency1 = Currency.wrap(eth);
        }

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: DEFAULT_FEE,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(address(0)) // No hooks for basic setup
        });

        return poolKey;
    }

    /// @notice Create a custom pool configuration
    /// @param token0 Address of first token
    /// @param token1 Address of second token
    /// @param fee Pool fee (in hundredths of a bip, i.e. 3000 = 0.3%)
    /// @param tickSpacing Tick spacing for the pool
    /// @param hooks Hook contract address (use address(0) for no hooks)
    /// @return poolKey The custom pool configuration
    function createCustomPoolKey(
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) public pure returns (PoolKey memory poolKey) {
        // Ensure proper token ordering
        Currency currency0;
        Currency currency1;

        if (token0 < token1) {
            currency0 = Currency.wrap(token0);
            currency1 = Currency.wrap(token1);
        } else {
            currency0 = Currency.wrap(token1);
            currency1 = Currency.wrap(token0);
        }

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hooks)
        });

        return poolKey;
    }

    /// @notice Validate the deployed SwapRouter
    /// @param swapRouter The deployed SwapRouter instance
    /// @param expectedPoolSwapTest The expected PoolSwapTest address
    /// @param expectedPoolKey The expected pool configuration
    function validateDeployment(
        SwapRouter swapRouter,
        address expectedPoolSwapTest,
        PoolKey memory expectedPoolKey
    ) public view {
        console.log("=== Deployment Validation ===");

        // Check PoolSwapTest address
        address actualPoolSwapTest = address(swapRouter.poolSwapTest());
        require(actualPoolSwapTest == expectedPoolSwapTest, "PoolSwapTest address mismatch");
        console.log("PoolSwapTest address: VERIFIED");

        // Check pool configuration
        PoolKey memory actualPoolKey = swapRouter.getPoolConfiguration();
        require(
            Currency.unwrap(actualPoolKey.currency0) == Currency.unwrap(expectedPoolKey.currency0),
            "Currency0 mismatch"
        );
        require(
            Currency.unwrap(actualPoolKey.currency1) == Currency.unwrap(expectedPoolKey.currency1),
            "Currency1 mismatch"
        );
        require(actualPoolKey.fee == expectedPoolKey.fee, "Fee mismatch");
        require(actualPoolKey.tickSpacing == expectedPoolKey.tickSpacing, "Tick spacing mismatch");
        require(address(actualPoolKey.hooks) == address(expectedPoolKey.hooks), "Hooks mismatch");
        console.log("Pool configuration: VERIFIED");

        // Check test settings
        IPoolSwapTest.TestSettings memory settings = swapRouter.getTestSettings();
        require(!settings.takeClaims, "takeClaims should be false by default");
        require(!settings.settleUsingBurn, "settleUsingBurn should be false by default");
        console.log("Test settings: VERIFIED");

        console.log("=== All Validations Passed ===");
    }

    /// @notice Test deployment function that validates configuration without requiring private key
    function testDeployment() public view {
        console.log("=== Testing SwapRouter Deployment Configuration ===");
        
        // Skip test if not on Arbitrum Sepolia
        if (block.chainid != 421614) {
            console.log("Skipping SwapRouter deployment test - only runs on Arbitrum Sepolia (Chain ID: 421614)");
            console.log("Current chain ID:", block.chainid);
            return;
        }
        
        require(block.chainid == 421614, "Must be on Arbitrum Sepolia (Chain ID: 421614)");
        
        // Validate PoolSwapTest address
        address poolSwapTestAddr = ChainAddresses.getPoolSwapTest(block.chainid);
        require(poolSwapTestAddr != address(0), "PoolSwapTest address not configured");
        console.log("[OK] PoolSwapTest address:", poolSwapTestAddr);
        
        // Check PoolSwapTest contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(poolSwapTestAddr)
        }
        require(codeSize > 0, "PoolSwapTest contract not found at address");
        console.log("[OK] PoolSwapTest contract exists (code size:", codeSize, "bytes)");
        
        // Validate default pool configuration
        PoolKey memory poolKey = getDefaultPoolKey();
        console.log("[OK] Default pool configuration:");
        console.log("  Currency0 (ETH):", Currency.unwrap(poolKey.currency0));
        console.log("  Currency1 (USDC):", Currency.unwrap(poolKey.currency1));
        console.log("  Fee (0.3%):", poolKey.fee);
        console.log("  Tick Spacing:", poolKey.tickSpacing);
        console.log("  Hooks:", address(poolKey.hooks));
        
        console.log("=== Configuration Test Complete ===");
        console.log("[SUCCESS] All parameters validated successfully");
        console.log("[READY] Ready for deployment with DEPLOYMENT_KEY");
    }

    /// @notice Get deployment summary for the current chain
    function getDeploymentSummary() public view returns (string memory) {
        return string.concat(
            "Network: ", ChainAddresses.getChainName(block.chainid), "\n",
            "Chain ID: ", vm.toString(block.chainid), "\n",
            "PoolSwapTest: ", vm.toString(getPoolSwapTestAddress()), "\n",
            "Block Explorer: ", ChainAddresses.getBlockExplorer(block.chainid)
        );
    }
} 