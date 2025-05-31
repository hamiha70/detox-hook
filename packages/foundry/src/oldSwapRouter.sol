// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

interface IPoolSwapTest {
    struct TestSettings {
        bool takeClaims;
        bool settleUsingBurn;
    }
    
    function swap(
        PoolKey memory key,
        SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta);
}

/// @title SwapRouter
/// @notice A router contract that simplifies swapping through PoolSwapTest
/// @dev This contract organizes swap parameters and calls PoolSwapTest.swap
contract SwapRouter {
    
    /// @notice The PoolSwapTest contract address
    IPoolSwapTest public immutable poolSwapTest;
    
    /// @notice Default pool configuration
    PoolKey public poolKey;
    
    /// @notice Default test settings for swaps
    IPoolSwapTest.TestSettings public defaultTestSettings;
    
    /// @notice Error thrown when swap amount is zero
    error InvalidSwapAmount();
    
    /// @notice Error thrown when PoolSwapTest is not set
    error PoolSwapTestNotSet();
    
    /// @notice Event emitted when a swap is executed
    event SwapExecuted(
        address indexed sender,
        int256 amountSpecified,
        bool zeroForOne,
        BalanceDelta delta
    );
    
    /// @notice Event emitted when pool configuration is updated
    event PoolConfigurationUpdated(
        Currency currency0,
        Currency currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );
    
    /// @param _poolSwapTest Address of the PoolSwapTest contract
    /// @param _poolKey Initial pool configuration
    constructor(address _poolSwapTest, PoolKey memory _poolKey) {
        if (_poolSwapTest == address(0)) revert PoolSwapTestNotSet();
        
        poolSwapTest = IPoolSwapTest(_poolSwapTest);
        poolKey = _poolKey;
        
        // Set default test settings
        defaultTestSettings = IPoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
    }
    
    /// @notice Execute a swap with simplified parameters
    /// @param amountToSwap The amount to swap (negative for exact input, positive for exact output)
    /// @param updateData Additional data for price updates or hook data
    /// @return delta The balance delta from the swap
    function swap(int256 amountToSwap, bytes calldata updateData) 
        external 
        payable 
        returns (BalanceDelta delta) 
    {
        if (amountToSwap == 0) revert InvalidSwapAmount();
        
        // Determine swap direction based on amount sign and pool configuration
        bool zeroForOne = amountToSwap < 0; // Negative means exact input (selling token0 for token1)
        
        // Create swap parameters
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountToSwap,
            sqrtPriceLimitX96: zeroForOne ? 4295128739 : 1461446703485210103287273052203988822378723970342 // Min/max prices
        });
        
        // Execute the swap through PoolSwapTest
        delta = poolSwapTest.swap{value: msg.value}(
            poolKey,
            swapParams,
            defaultTestSettings,
            updateData
        );
        
        emit SwapExecuted(msg.sender, amountToSwap, zeroForOne, delta);
        
        return delta;
    }
    
    /// @notice Execute a swap with custom swap direction
    /// @param amountToSwap The amount to swap
    /// @param zeroForOne Direction of the swap (true = token0 for token1, false = token1 for token0)
    /// @param updateData Additional data for price updates or hook data
    /// @return delta The balance delta from the swap
    function swapWithDirection(
        int256 amountToSwap, 
        bool zeroForOne, 
        bytes calldata updateData
    ) external payable returns (BalanceDelta delta) {
        if (amountToSwap == 0) revert InvalidSwapAmount();
        
        // Create swap parameters with custom direction
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountToSwap,
            sqrtPriceLimitX96: zeroForOne ? 4295128739 : 1461446703485210103287273052203988822378723970342
        });
        
        // Execute the swap through PoolSwapTest
        delta = poolSwapTest.swap{value: msg.value}(
            poolKey,
            swapParams,
            defaultTestSettings,
            updateData
        );
        
        emit SwapExecuted(msg.sender, amountToSwap, zeroForOne, delta);
        
        return delta;
    }
    
    /// @notice Execute a swap with custom price limits
    /// @param amountToSwap The amount to swap
    /// @param zeroForOne Direction of the swap
    /// @param sqrtPriceLimitX96 The price limit for the swap
    /// @param updateData Additional data for price updates or hook data
    /// @return delta The balance delta from the swap
    function swapWithPriceLimit(
        int256 amountToSwap,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96,
        bytes calldata updateData
    ) external payable returns (BalanceDelta delta) {
        if (amountToSwap == 0) revert InvalidSwapAmount();
        
        // Create swap parameters with custom price limit
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountToSwap,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        
        // Execute the swap through PoolSwapTest
        delta = poolSwapTest.swap{value: msg.value}(
            poolKey,
            swapParams,
            defaultTestSettings,
            updateData
        );
        
        emit SwapExecuted(msg.sender, amountToSwap, zeroForOne, delta);
        
        return delta;
    }
    
    /// @notice Update the pool configuration
    /// @param newPoolKey The new pool configuration
    function updatePoolConfiguration(PoolKey memory newPoolKey) external {
        poolKey = newPoolKey;
        
        emit PoolConfigurationUpdated(
            newPoolKey.currency0,
            newPoolKey.currency1,
            newPoolKey.fee,
            newPoolKey.tickSpacing,
            newPoolKey.hooks
        );
    }
    
    /// @notice Update test settings for swaps
    /// @param takeClaims Whether to take claims during settlement
    /// @param settleUsingBurn Whether to settle using burn
    function updateTestSettings(bool takeClaims, bool settleUsingBurn) external {
        defaultTestSettings = IPoolSwapTest.TestSettings({
            takeClaims: takeClaims,
            settleUsingBurn: settleUsingBurn
        });
    }
    
    /// @notice Get the current pool configuration
    /// @return The current pool key
    function getPoolConfiguration() external view returns (PoolKey memory) {
        return poolKey;
    }
    
    /// @notice Get the current test settings
    /// @return The current test settings
    function getTestSettings() external view returns (IPoolSwapTest.TestSettings memory) {
        return defaultTestSettings;
    }
} 