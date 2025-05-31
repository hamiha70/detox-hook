// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {SwapRouter, IPoolSwapTest} from "../src/swapRouter.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title SwapRouterTest
/// @notice Basic tests for the SwapRouter contract
contract SwapRouterTest is Test {

    SwapRouter public swapRouterContract;
    
    address public mockPoolSwapTest = makeAddr("mockPoolSwapTest");
    Currency public currency0 = Currency.wrap(makeAddr("token0"));
    Currency public currency1 = Currency.wrap(makeAddr("token1"));
    
    PoolKey public testKey;
    
    uint24 constant FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;
    
    function setUp() public {
        // Create pool key
        testKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
        
        // Deploy SwapRouter
        swapRouterContract = new SwapRouter(mockPoolSwapTest, testKey);
    }
    
    /// @notice Test contract deployment and initialization
    function test_Deployment() public {
        assertEq(address(swapRouterContract.poolSwapTest()), mockPoolSwapTest);
        
        PoolKey memory retrievedKey = swapRouterContract.getPoolConfiguration();
        assertEq(Currency.unwrap(retrievedKey.currency0), Currency.unwrap(testKey.currency0));
        assertEq(Currency.unwrap(retrievedKey.currency1), Currency.unwrap(testKey.currency1));
        assertEq(retrievedKey.fee, testKey.fee);
        assertEq(retrievedKey.tickSpacing, testKey.tickSpacing);
        
        // Test default settings
        IPoolSwapTest.TestSettings memory settings = swapRouterContract.getTestSettings();
        assertFalse(settings.takeClaims);
        assertFalse(settings.settleUsingBurn);
        
        console.log("SwapRouter deployed successfully");
    }
    
    /// @notice Test constructor reverts with zero address
    function test_DeploymentRevertsWithZeroAddress() public {
        vm.expectRevert(SwapRouter.PoolSwapTestNotSet.selector);
        new SwapRouter(address(0), testKey);
    }
    
    /// @notice Test updating pool configuration
    function test_UpdatePoolConfiguration() public {
        // Create new pool key
        PoolKey memory newKey = PoolKey({
            currency0: currency1, // Swap order
            currency1: currency0,
            fee: 10000, // 1%
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });
        
        // Update configuration
        swapRouterContract.updatePoolConfiguration(newKey);
        
        // Verify update
        PoolKey memory retrievedKey = swapRouterContract.getPoolConfiguration();
        assertEq(Currency.unwrap(retrievedKey.currency0), Currency.unwrap(newKey.currency0));
        assertEq(Currency.unwrap(retrievedKey.currency1), Currency.unwrap(newKey.currency1));
        assertEq(retrievedKey.fee, newKey.fee);
        assertEq(retrievedKey.tickSpacing, newKey.tickSpacing);
        
        console.log("Pool configuration updated successfully");
    }
    
    /// @notice Test updating test settings
    function test_UpdateTestSettings() public {
        // Update settings
        swapRouterContract.updateTestSettings(true, true);
        
        // Verify update
        IPoolSwapTest.TestSettings memory settings = swapRouterContract.getTestSettings();
        assertTrue(settings.takeClaims);
        assertTrue(settings.settleUsingBurn);
        
        // Update back to false
        swapRouterContract.updateTestSettings(false, false);
        settings = swapRouterContract.getTestSettings();
        assertFalse(settings.takeClaims);
        assertFalse(settings.settleUsingBurn);
        
        console.log("Test settings updated successfully");
    }
    
    /// @notice Test that swap function calls require non-zero amounts
    function test_SwapRevertsWithZeroAmount() public {
        bytes memory updateData = "";
        
        vm.expectRevert(SwapRouter.InvalidSwapAmount.selector);
        swapRouterContract.swap(0, updateData);
        
        console.log("Zero amount validation working correctly");
    }
    
    /// @notice Test getters return correct values
    function test_Getters() public {
        PoolKey memory retrievedKey = swapRouterContract.getPoolConfiguration();
        IPoolSwapTest.TestSettings memory settings = swapRouterContract.getTestSettings();
        
        assertTrue(Currency.unwrap(retrievedKey.currency0) == Currency.unwrap(testKey.currency0));
        assertFalse(settings.takeClaims);
        
        console.log("All getter functions working correctly");
    }
    
    /// @notice Test the contract interface matches expected functionality
    function test_ContractInterface() public {
        // Test that the contract has all expected public functions
        assertTrue(address(swapRouterContract.poolSwapTest()) != address(0));
        
        // Test that default pool configuration is stored correctly
        PoolKey memory config = swapRouterContract.getPoolConfiguration();
        assertTrue(config.fee == FEE);
        assertTrue(config.tickSpacing == TICK_SPACING);
        
        console.log("Contract interface validation passed");
    }
} 