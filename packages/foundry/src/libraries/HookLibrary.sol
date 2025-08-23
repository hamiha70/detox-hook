// SPDX-License-Identifier: MIT
// RULE: Never cast Uniswap V4 wrapper types (e.g., PoolId, Currency) directly to primitive types like uint256 or address. Always use the appropriate unwrap function first.
pragma solidity ^0.8.0;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {console} from "forge-std/console.sol";

/// @title HookLibrary
/// @notice Helper functions for Uniswap V4 hook development
/// @dev Provides common utilities for pool state reading, price calculations, and swap operations
library HookLibrary {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // ============ Pool State Reading ============

    /// @notice Get the current price of a pool
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return sqrtPriceX96 The current sqrt price in Q64.96 format
    function getPoolPrice(
        IPoolManager manager,
        PoolKey memory poolKey
    ) internal view returns (uint160 sqrtPriceX96) {
        PoolId poolId = poolKey.toId();
        (sqrtPriceX96, , , ) = StateLibrary.getSlot0(manager, poolId);
    }

    /// @notice Get the current tick of a pool
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return tick The current tick
    function getPoolTick(
        IPoolManager manager,
        PoolKey memory poolKey
    ) internal view returns (int24 tick) {
        PoolId poolId = poolKey.toId();
        (, tick, , ) = StateLibrary.getSlot0(manager, poolId);
    }

    /// @notice Get the current liquidity of a pool
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return liquidity The current liquidity
    function getPoolLiquidity(
        IPoolManager manager,
        PoolKey memory poolKey
    ) internal view returns (uint128 liquidity) {
        PoolId poolId = poolKey.toId();
        liquidity = StateLibrary.getLiquidity(manager, poolId);
    }

    /// @notice Get complete pool state in one call
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return sqrtPriceX96 The current sqrt price
    /// @return tick The current tick
    /// @return protocolFee The protocol fee
    /// @return lpFee The LP fee
    /// @return liquidity The current liquidity
    function getPoolState(
        IPoolManager manager,
        PoolKey memory poolKey
    )
        internal
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity
        )
    {
        PoolId poolId = poolKey.toId();
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(
            manager,
            poolId
        );
        liquidity = StateLibrary.getLiquidity(manager, poolId);
    }

    // ============ Price Calculations ============

    /// @notice Convert sqrt price to human-readable price ratio
    /// @param sqrtPriceX96 The sqrt price in Q64.96 format
    /// @return price The price as currency1/currency0 with 18 decimals
    function sqrtPriceToPrice(
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 price) {
        // Price = (sqrtPriceX96 / 2^96)^2
        // Multiply by 10^18 for 18 decimal precision
        //console.log("[SQRT2PRICE] sqrtPriceX96");
        //console.logUint(uint256(sqrtPriceX96));

        // Use FullMath.mulDiv to avoid overflow when squaring large sqrtPriceX96
        // priceX192 = sqrtPriceX96^2
        uint256 priceX192 = FullMath.mulDiv(
            uint256(sqrtPriceX96),
            uint256(sqrtPriceX96),
            1
        );

        // Convert from X192 to 18 decimal precision
        // price = priceX192 * 1e18 / 2^192
        price = FullMath.mulDiv(priceX192, 1e18, 1 << 192);

        //console.log("[SQRT2PRICE] price");
        //console.logUint(price);
        //console.log(price / 1e12);
    }

    /// @notice Convert human-readable price to sqrt price
    /// @param price The price as currency1/currency0 with 18 decimals
    /// @return sqrtPriceX96 The sqrt price in Q64.96 format
    function priceToSqrtPrice(
        uint256 price
    ) internal pure returns (uint160 sqrtPriceX96) {
        // sqrtPrice = sqrt(price) * 2^96
        uint256 sqrtPrice = sqrt(price * (1 << 192)) / 1e9; // Adjust for 18 decimals
        require(sqrtPrice <= type(uint160).max, "Price too large");
        sqrtPriceX96 = uint160(sqrtPrice);
    }

    /// @notice Calculate price impact of a swap
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @param params The swap parameters
    /// @return priceImpactBps Price impact in basis points (1 bp = 0.01%)
    function calculatePriceImpact(
        IPoolManager manager,
        PoolKey memory poolKey,
        SwapParams memory params
    ) internal view returns (uint256 priceImpactBps) {
        // For exact input swaps, estimate the price after swap
        // This is a simplified calculation - for precise calculation, you'd need to simulate the swap
        uint128 liquidity = getPoolLiquidity(manager, poolKey);

        if (liquidity == 0) return 0;

        // Simplified price impact calculation
        // Real implementation would need to account for tick spacing and concentrated liquidity
        uint256 swapAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        // Price impact ≈ swapAmount / (2 * liquidity) * 10000 (for basis points)
        priceImpactBps = (swapAmount * 10000) / (2 * uint256(liquidity));

        // Cap at reasonable maximum
        if (priceImpactBps > 10000) priceImpactBps = 10000; // 100% max
    }

    // ============ Swap Utilities ============

    /// @notice Check if a swap is exact input
    /// @param params The swap parameters
    /// @return isExactInput True if exact input, false if exact output
    function isExactInput(
        SwapParams memory params
    ) internal pure returns (bool) {
        return params.amountSpecified < 0;
    }

    /// @notice Get the input currency for a swap
    /// @param poolKey The pool key
    /// @param params The swap parameters
    /// @return inputCurrency The input currency
    function getInputCurrency(
        PoolKey memory poolKey,
        SwapParams memory params
    ) internal pure returns (Currency inputCurrency) {
        inputCurrency = params.zeroForOne
            ? poolKey.currency0
            : poolKey.currency1;
    }

    /// @notice Get the output currency for a swap
    /// @param poolKey The pool key
    /// @param params The swap parameters
    /// @return outputCurrency The output currency
    function getOutputCurrency(
        PoolKey memory poolKey,
        SwapParams memory params
    ) internal pure returns (Currency outputCurrency) {
        outputCurrency = params.zeroForOne
            ? poolKey.currency1
            : poolKey.currency0;
    }

    /// @notice Calculate fee amount for exact input swap
    /// @param swapAmount The swap amount (positive)
    /// @param feePercentage The fee percentage in basis points (e.g., 2000 = 20%)
    /// @return feeAmount The fee amount
    function calculateFee(
        uint256 swapAmount,
        uint256 feePercentage
    ) internal pure returns (uint256 feeAmount) {
        feeAmount = (swapAmount * feePercentage) / 10000;
    }

    /// @notice Create BeforeSwapDelta for reducing swap amount
    /// @param params The swap parameters
    /// @param reductionAmount The amount to reduce from the swap
    /// @return delta The BeforeSwapDelta
    function createSwapReduction(
        PoolKey memory,
        /* poolKey */ SwapParams memory params,
        uint256 reductionAmount
    ) internal pure returns (BeforeSwapDelta delta) {
        require(reductionAmount <= 2 ** 127 - 1, "Reduction amount too large");

        if (params.zeroForOne) {
            // Reducing currency0 (input for zeroForOne swap)
            delta = toBeforeSwapDelta(int128(int256(reductionAmount)), 0);
        } else {
            // Reducing currency1 (input for oneForZero swap)
            delta = toBeforeSwapDelta(0, int128(int256(reductionAmount)));
        }
    }

    // ============ Validation Utilities ============

    /// @notice Validate that a pool exists and is initialized
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return isValid True if pool is valid and initialized
    function isPoolValid(
        IPoolManager manager,
        PoolKey memory poolKey
    ) internal view returns (bool isValid) {
        // Try to get pool state directly using StateLibrary
        PoolId poolId = poolKey.toId();

        // Check if pool exists by trying to get slot0
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(manager, poolId);
        isValid = sqrtPriceX96 > 0;
    }

    /// @notice Check if a price is within reasonable bounds
    /// @param sqrtPriceX96 The sqrt price to check
    /// @return isValid True if price is within bounds
    function isPriceValid(
        uint160 sqrtPriceX96
    ) internal pure returns (bool isValid) {
        isValid =
            sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE &&
            sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE;
    }

    /// @notice Check if a swap amount is reasonable (not too large)
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @param swapAmount The swap amount to check
    /// @return isReasonable True if amount is reasonable relative to pool liquidity
    function isSwapAmountReasonable(
        IPoolManager manager,
        PoolKey memory poolKey,
        uint256 swapAmount
    ) internal view returns (bool isReasonable) {
        uint128 liquidity = getPoolLiquidity(manager, poolKey);
        if (liquidity == 0) return false;

        // Consider reasonable if swap is less than 10% of total liquidity
        isReasonable = swapAmount < (uint256(liquidity) / 10);
    }

    // ============ Proper Uniswap V4 Liquidity Mathematics ============

    /// @notice Calculate proper ETH/USDC liquidity using Uniswap V4 mathematics
    /// @param targetETHAmount Target ETH amount to provide (e.g., 0.1 ETH)
    /// @param ethPriceInUSDC Current ETH price in USDC (e.g., 3600)
    /// @param rangePercent Liquidity range percentage (e.g., 10 for ±10%)
    /// @param tickSpacing Tick spacing for the pool (e.g., 60)
    /// @return ethAmount ETH amount needed
    /// @return usdcAmount USDC amount needed
    /// @return liquidityParams Complete ModifyLiquidityParams for deployment
    function calculateETHUSDCLiquidityV4(
        uint256 targetETHAmount,
        uint256 ethPriceInUSDC,
        uint256 rangePercent,
        int24 tickSpacing
    )
        internal
        pure
        returns (
            uint256 ethAmount,
            uint256 usdcAmount,
            ModifyLiquidityParams memory liquidityParams
        )
    {
        // Step 1: Calculate current price using the working approach from DetoxHookV2.t.sol
        // For ETH/USDC pool where ETH is currency0, USDC is currency1:
        // Price = currency1/currency0 = USDC/ETH in 1e18 precision
        // For ethPriceInUSDC (e.g., 3600): (3600 * 1e6) / (1 * 1e18) = 3.6e-9
        // To get 1e18 precision: 3.6e-9 * 1e18 = 3.6e9
        uint256 currentPrice = ethPriceInUSDC * 1000000; // ethPriceInUSDC * 1e6 (simplified)
        uint160 sqrtPriceX96 = priceToSqrtPrice(currentPrice);

        // Step 2: Calculate tick range for ±rangePercent
        // Note: currentTick calculated but not used - we calculate bounds directly from prices

        // Calculate price bounds (±rangePercent) using the same approach
        uint256 lowerPriceInUSDC = (ethPriceInUSDC * (100 - rangePercent)) /
            100;
        uint256 upperPriceInUSDC = (ethPriceInUSDC * (100 + rangePercent)) /
            100;

        uint256 lowerPrice = lowerPriceInUSDC * 1000000; // Convert to Uniswap format
        uint256 upperPrice = upperPriceInUSDC * 1000000; // Convert to Uniswap format

        uint160 sqrtPriceLowerX96 = priceToSqrtPrice(lowerPrice);
        uint160 sqrtPriceUpperX96 = priceToSqrtPrice(upperPrice);

        int24 tickLower = TickMath.getTickAtSqrtPrice(sqrtPriceLowerX96);
        int24 tickUpper = TickMath.getTickAtSqrtPrice(sqrtPriceUpperX96);

        // Step 3: Round ticks to tick spacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;

        // Ensure tickUpper > tickLower
        if (tickUpper <= tickLower) {
            tickUpper = tickLower + tickSpacing;
        }

        // Step 4: Calculate liquidity from target ETH amount
        // Assume we want to provide targetETHAmount of ETH
        uint128 liquidityFromETH = LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            targetETHAmount
        );

        // Step 5: Calculate required token amounts for this liquidity
        (ethAmount, usdcAmount) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityFromETH
        );

        // Step 6: Create ModifyLiquidityParams
        liquidityParams = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(uint256(liquidityFromETH)),
            salt: 0
        });

        // Step 7: Apply minimums for meaningful liquidity
        if (ethAmount < 0.001 ether) ethAmount = 0.001 ether;
        if (usdcAmount < 1000e6) usdcAmount = 1000e6;
    }

    /// @notice Legacy wrapper for backward compatibility with tests
    /// @param targetUSDCLiquidity Target USDC amount (converted to ETH target)
    /// @param ethPriceInUSDC ETH price in USDC
    /// @param rangePercent Range percentage (±%)
    /// @return ethAmount ETH amount needed
    /// @return usdcAmount USDC amount needed
    /// @return tickLower Lower tick (from liquidityParams)
    /// @return tickUpper Upper tick (from liquidityParams)
    function calculateETHUSDCLiquidity(
        uint256 targetUSDCLiquidity,
        uint256 ethPriceInUSDC,
        uint256 rangePercent
    )
        internal
        pure
        returns (
            uint256 ethAmount,
            uint256 usdcAmount,
            int24 tickLower,
            int24 tickUpper
        )
    {
        // Convert USDC target to ETH target (for backward compatibility)
        uint256 targetETH = (targetUSDCLiquidity * 1e18) /
            (ethPriceInUSDC * 1e6);

        // Use proper V4 math with default tick spacing
        ModifyLiquidityParams memory liquidityParams;
        (ethAmount, usdcAmount, liquidityParams) = calculateETHUSDCLiquidityV4(
            targetETH,
            ethPriceInUSDC,
            rangePercent,
            60 // Default tick spacing
        );

        // Extract ticks for backward compatibility
        tickLower = liquidityParams.tickLower;
        tickUpper = liquidityParams.tickUpper;
    }

    // ============ Math Utilities ============

    /// @notice Calculate square root using Babylonian method
    /// @param x The number to find square root of
    /// @return result The square root
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;

        // Initial guess
        result = x;
        uint256 k = (x >> 1) + 1;

        // Babylonian method
        while (k < result) {
            result = k;
            k = (x / k + k) >> 1;
        }
    }

    /// @notice Convert basis points to percentage
    /// @param bps Basis points (1 bp = 0.01%)
    /// @return percentage Percentage with 18 decimals
    function bpsToPercentage(
        uint256 bps
    ) internal pure returns (uint256 percentage) {
        percentage = (bps * 1e18) / 10000;
    }

    /// @notice Convert percentage to basis points
    /// @param percentage Percentage with 18 decimals
    /// @return bps Basis points
    function percentageToBps(
        uint256 percentage
    ) internal pure returns (uint256 bps) {
        bps = (percentage * 10000) / 1e18;
    }

    // ============ Currency Utilities ============

    /// @notice Check if a currency is ETH (address(0))
    /// @param currency The currency to check
    /// @return isETH True if currency is ETH
    function isETH(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == address(0);
    }

    /// @notice Get currency symbol for logging/debugging
    /// @param currency The currency
    /// @return symbol A string representation
    function getCurrencySymbol(
        Currency currency
    ) internal pure returns (string memory symbol) {
        if (isETH(currency)) {
            symbol = "ETH";
        } else {
            // For non-ETH currencies, return the address as string
            symbol = addressToString(Currency.unwrap(currency));
        }
    }

    /// @notice Convert address to string for logging
    /// @param addr The address to convert
    /// @return str The string representation
    function addressToString(
        address addr
    ) internal pure returns (string memory str) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            result[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            result[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        str = string(result);
    }
}
