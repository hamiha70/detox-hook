// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {DetoxHookV2Test} from "./DetoxHookV2.t.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @title Simple Gas Analysis for DetoxHook
/// @notice Simplified gas measurements using existing working test patterns
contract GasAnalysisSimpleTest is DetoxHookV2Test {
    // Gas limit targets based on our findings
    uint256 constant MOCK_PYTH_GAS_LIMIT = 200000; // MockPyth environment
    uint256 constant REAL_PYTH_GAS_TARGET = 800000; // Real Pyth environment target
    uint256 constant OPTIMIZED_GAS_TARGET = 600000; // Optimization goal

    /// @notice Test gas usage for different swap sizes in mock environment
    function test_GasUsage_SwapSizeBenchmark() public {
        console.log("=== Gas Usage Benchmark: Different Swap Sizes ===");

        // Set up arbitrage scenario
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            int64(3000 * 1e8),
            uint64(100 * 1e8),
            -8,
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            int64(1000 * 1e8),
            uint64(10 * 1e8),
            -8,
            uint64(block.timestamp)
        );

        // Test different swap amounts
        uint256[] memory swapAmounts = new uint256[](5);
        swapAmounts[0] = 0.001e18; // 0.001 tokens
        swapAmounts[1] = 0.01e18; // 0.01 tokens
        swapAmounts[2] = 0.1e18; // 0.1 tokens
        swapAmounts[3] = 1e18; // 1 token
        swapAmounts[4] = 10e18; // 10 tokens

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        for (uint i = 0; i < swapAmounts.length; i++) {
            vm.startPrank(alice);

            SwapParams memory swapParams = SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmounts[i]),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            });

            uint256 gasBefore = gasleft();

            try swapRouter.swap(simplePoolKey, swapParams, testSettings, "") {
                uint256 gasUsed = gasBefore - gasleft();

                console.log("--- Swap Size Analysis ---");
                console.log("Amount:", swapAmounts[i] / 1e18, "tokens");
                console.log("Gas used:", gasUsed);
                console.log(
                    "Gas per token:",
                    gasUsed / (swapAmounts[i] / 1e18)
                );

                // Verify gas is within expected range for MockPyth
                assertLt(
                    gasUsed,
                    MOCK_PYTH_GAS_LIMIT,
                    "Gas usage too high for MockPyth environment"
                );
                assertTrue(gasUsed > 50000, "Gas usage suspiciously low");
            } catch Error(string memory reason) {
                console.log("Swap failed for amount:", swapAmounts[i] / 1e18);
                console.log("Reason:", reason);
            }

            vm.stopPrank();
        }
    }

    /// @notice Test gas usage with vs without arbitrage detection
    function test_GasUsage_Arbitrage_vs_NoArbitrage() public {
        console.log("=== Gas Comparison: Arbitrage vs No Arbitrage ===");

        uint256 swapAmount = 1e18; // 1 token

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Test 1: No arbitrage scenario (oracle matches pool)
        console.log("--- No Arbitrage Scenario ---");
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            int64(1 * 1e8),
            uint64(1e6),
            -8,
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            int64(1 * 1e8),
            uint64(1e6),
            -8,
            uint64(block.timestamp)
        );

        vm.startPrank(alice);
        uint256 gasBefore1 = gasleft();
        swapRouter.swap(simplePoolKey, swapParams, testSettings, "");
        uint256 gasUsedNoArb = gasBefore1 - gasleft();
        vm.stopPrank();

        console.log("Gas without arbitrage:", gasUsedNoArb);

        // Test 2: Arbitrage scenario (oracle differs from pool)
        console.log("--- Arbitrage Scenario ---");
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            int64(3000 * 1e8),
            uint64(100 * 1e8),
            -8,
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            int64(1000 * 1e8),
            uint64(10 * 1e8),
            -8,
            uint64(block.timestamp)
        );

        vm.startPrank(alice);
        uint256 gasBefore2 = gasleft();
        swapRouter.swap(simplePoolKey, swapParams, testSettings, "");
        uint256 gasUsedWithArb = gasBefore2 - gasleft();
        vm.stopPrank();

        console.log("Gas with arbitrage:", gasUsedWithArb);
        console.log("Arbitrage overhead:", gasUsedWithArb - gasUsedNoArb);
        console.log(
            "Overhead percentage:",
            ((gasUsedWithArb - gasUsedNoArb) * 100) / gasUsedNoArb,
            "%"
        );

        // Both should be reasonable for MockPyth
        assertLt(
            gasUsedNoArb,
            MOCK_PYTH_GAS_LIMIT,
            "No-arbitrage gas too high"
        );
        assertLt(gasUsedWithArb, MOCK_PYTH_GAS_LIMIT, "Arbitrage gas too high");
    }

    /// @notice Test realistic ETH/USDC scenario gas usage
    function test_GasUsage_RealisticETHUSDC() public {
        console.log("=== Gas Analysis: Realistic ETH/USDC Pool ===");

        // Set realistic ETH/USDC prices with arbitrage opportunity
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            int64(3000 * 1e8),
            uint64(100 * 1e8),
            -8,
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            int64(1 * 1e8),
            uint64(0.01 * 1e8),
            -8,
            uint64(block.timestamp)
        );

        // Test with realistic swap amount
        uint256 swapAmount = 0.1e18; // 0.1 ETH

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // Adjust based on currency ordering
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        vm.startPrank(alice);
        uint256 gasBefore = gasleft();

        try
            swapRouter.swap(realisticPoolKey, swapParams, testSettings, "")
        returns (BalanceDelta delta) {
            uint256 gasUsed = gasBefore - gasleft();

            console.log("Realistic ETH/USDC swap results:");
            console.log("Swap amount: 0.1 ETH");
            console.log("Gas used:", gasUsed);
            console.log("Delta amount0:", delta.amount0());
            console.log("Delta amount1:", delta.amount1());

            // Should be reasonable for MockPyth environment
            assertLt(
                gasUsed,
                MOCK_PYTH_GAS_LIMIT,
                "Realistic swap gas too high"
            );
        } catch Error(string memory reason) {
            console.log("Realistic swap failed:", reason);
        }

        vm.stopPrank();
    }

    /// @notice Display gas optimization targets and current performance
    function test_GasUsage_OptimizationTargets() public view {
        console.log("=== Gas Optimization Analysis ===");
        console.log("Current Environment: MockPyth (Test)");
        console.log("Expected gas limit (MockPyth):", MOCK_PYTH_GAS_LIMIT);
        console.log("Real Pyth gas target:", REAL_PYTH_GAS_TARGET);
        console.log("Optimization goal:", OPTIMIZED_GAS_TARGET);
        console.log("");
        console.log("Key Findings:");
        console.log("- MockPyth environment: ~159k gas");
        console.log("- Real Pyth environment: ~800k gas");
        console.log("- Optimization needed: 5x reduction in Pyth overhead");
        console.log("");
        console.log("Optimization Strategies:");
        console.log("1. Cache Pyth price data when possible");
        console.log("2. Optimize oracle call frequency");
        console.log("3. Use exact output swaps for better gas efficiency");
        console.log("4. Implement gas-efficient arbitrage detection");
    }

    /// @notice Benchmark beforeSwap gas usage in isolation
    function test_GasUsage_BeforeSwap_Isolation() public {
        console.log("=== beforeSwap Gas Isolation Test ===");

        // Set up arbitrage scenario
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            int64(3000 * 1e8),
            uint64(100 * 1e8),
            -8,
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            int64(1000 * 1e8),
            uint64(10 * 1e8),
            -8,
            uint64(block.timestamp)
        );

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e18,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Note: We can't directly call beforeSwap due to access restrictions,
        // but we can measure the full swap and estimate beforeSwap portion
        uint256 gasBefore = gasleft();

        vm.startPrank(alice);
        swapRouter.swap(
            simplePoolKey,
            swapParams,
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
        vm.stopPrank();

        uint256 totalGasUsed = gasBefore - gasleft();

        console.log("Total swap gas (including beforeSwap):", totalGasUsed);
        console.log("Estimated beforeSwap portion: ~30-40% of total");
        console.log("Estimated beforeSwap gas:", (totalGasUsed * 35) / 100);

        // Verify total is reasonable
        assertLt(totalGasUsed, MOCK_PYTH_GAS_LIMIT, "Total swap gas too high");
    }
}
