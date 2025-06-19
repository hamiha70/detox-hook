// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { IPyth, PythStructs } from "../../src/libraries/PythLibrary.sol";
import { SimplifiedOracleLib } from "../../src/libraries/SimplifiedOracleLib.sol";
import { MockPyth } from "../../src/libraries/PythMock.sol";

/**
 * @title OracleLibTest  
 * @notice Unit tests for oracle price normalization and ratio calculations
 * @dev Focuses on decimal/exponent handling correctness before integration testing
 */
contract OracleLibTest is Test {
    MockPyth public mockOracle;
    
    // Test price IDs
    bytes32 constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    
    // Expected precision for normalized values
    uint256 constant PRECISION = 1e18;
    
    function setUp() public {
        mockOracle = new MockPyth(60, 1);
    }
    
    /// @notice Test basic price normalization from different Pyth exponents
    function test_PriceNormalization_DifferentExponents() public {
        console.log("=== TEST: Price Normalization with Different Exponents ===");
        
        // Test Case 1: ETH at $2500 with -8 exponent (typical Pyth format)
        console.log("\n--- Test Case 1: ETH $2500, -8 exponent ---");
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            250000000000, // $2500 * 1e8 (with -8 exponent = $2500)
            2500000000,   // $25 confidence * 1e8
            -8,
            uint64(block.timestamp)
        );
        
        (uint256 price1, uint256 lower1, uint256 upper1, bool valid1) = 
            SimplifiedOracleLib.getPriceWithBounds(mockOracle, ETH_USD_PRICE_ID, 60);
            
        console.log("Raw Pyth value: 250000000000 (represents $2500 with -8 expo)");
        console.log("Normalized price:", price1);
        console.log("Expected price:", 2500 * PRECISION);
        console.log("Lower bound:", lower1);
        console.log("Upper bound:", upper1);
        console.log("Valid:", valid1);
        
        // Validate normalization
        assertEq(price1, 2500 * PRECISION, "ETH price should be $2500 in 1e18 precision");
        assertEq(lower1, 2475 * PRECISION, "Lower bound should be $2475 (2500-25)");
        assertEq(upper1, 2525 * PRECISION, "Upper bound should be $2525 (2500+25)");
        
        // Test Case 2: USDC at $1.00 with -8 exponent  
        console.log("\n--- Test Case 2: USDC $1.00, -8 exponent ---");
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            100000000,    // $1.00 * 1e8 (with -8 exponent = $1.00)
            1000000,      // $0.01 confidence * 1e8
            -8,
            uint64(block.timestamp)
        );
        
        (uint256 price2, uint256 lower2, uint256 upper2, bool valid2) = 
            SimplifiedOracleLib.getPriceWithBounds(mockOracle, USDC_USD_PRICE_ID, 60);
            
        console.log("Raw Pyth value: 100000000 (represents $1.00 with -8 expo)");
        console.log("Normalized price:", price2);
        console.log("Expected price:", 1 * PRECISION);
        console.log("Lower bound:", lower2);
        console.log("Upper bound:", upper2);
        console.log("Valid:", valid2);
        
        // Validate normalization
        assertEq(price2, 1 * PRECISION, "USDC price should be $1.00 in 1e18 precision");
        assertEq(lower2, 99 * PRECISION / 100, "Lower bound should be $0.99 (1.00-0.01)");
        assertEq(upper2, 101 * PRECISION / 100, "Upper bound should be $1.01 (1.00+0.01)");
        
        console.log("[PASS] Price normalization working correctly for -8 exponent");
    }
    
    /// @notice Test price ratio calculation (the critical piece for arbitrage detection)
    function test_PriceRatioCalculation_Realistic() public {
        console.log("=== TEST: Price Ratio Calculation (ETH/USD / USDC/USD -> USDC/ETH) ===");
        
        // Set up realistic prices: ETH=$2500, USDC=$1.00
        console.log("\n--- Setting up: ETH=$2500+/-$25, USDC=$1.00+/-$0.01 ---");
        
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            250000000000, // $2500
            2500000000,   // $25 confidence
            -8,
            uint64(block.timestamp)
        );
        
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            100000000,    // $1.00
            1000000,      // $0.01 confidence
            -8,
            uint64(block.timestamp)
        );
        
        // Calculate price ratio bounds
        (uint256 lowerBound, uint256 upperBound, bool valid) = 
            SimplifiedOracleLib.calculatePriceRatioBounds(
                mockOracle, 
                ETH_USD_PRICE_ID,   // priceId0 (denominator)
                USDC_USD_PRICE_ID,  // priceId1 (numerator)
                60
            );
            
        console.log("Price ratio calculation:");
        console.log("- Formula: (USDC_USD +/- conf) / (ETH_USD +/- conf)");
        console.log("- Lower bound: (1.00 - 0.01) / (2500 + 25) = 0.99/2525");
        console.log("- Upper bound: (1.00 + 0.01) / (2500 - 25) = 1.01/2475");
        
        uint256 expectedLower = (99 * PRECISION / 100) * PRECISION / (2525 * PRECISION);
        uint256 expectedUpper = (101 * PRECISION / 100) * PRECISION / (2475 * PRECISION);
        
        console.log("Expected lower bound:", expectedLower);
        console.log("Expected upper bound:", expectedUpper);
        console.log("Actual lower bound:", lowerBound);
        console.log("Actual upper bound:", upperBound);
        console.log("Valid:", valid);
        
        // The ratio should be very small (USDC is much cheaper than ETH)
        assertGt(upperBound, lowerBound, "Upper bound should be greater than lower bound");
        assertLt(upperBound, PRECISION / 1000, "Ratio should be less than 0.001 (USDC much cheaper than ETH)");
        assertTrue(valid, "Price ratio calculation should be valid");
        
        // Now let's calculate the INVERSE ratio (what we actually want for USDC/ETH pool)
        console.log("\n--- Inverse Ratio Calculation (ETH/USD / USDC/USD -> ETH/USDC, then invert to USDC/ETH) ---");
        
        // For a USDC/ETH pool, we want currency1/currency0 where currency0=ETH, currency1=USDC
        // So we want USDC/ETH ratio
        (uint256 ethUsdcLower, uint256 ethUsdcUpper, bool ethUsdcValid) = 
            SimplifiedOracleLib.calculatePriceRatioBounds(
                mockOracle,
                USDC_USD_PRICE_ID,  // priceId0 (denominator - USDC)  
                ETH_USD_PRICE_ID,   // priceId1 (numerator - ETH)
                60
            );
            
        console.log("ETH/USDC ratio bounds:");
        console.log("- Formula: (ETH_USD +/- conf) / (USDC_USD +/- conf)");
        console.log("- Lower: (2500 - 25) / (1.00 + 0.01) = 2475/1.01");
        console.log("- Upper: (2500 + 25) / (1.00 - 0.01) = 2525/0.99");
        
        console.log("ETH/USDC lower bound:", ethUsdcLower);
        console.log("ETH/USDC upper bound:", ethUsdcUpper);
        console.log("ETH/USDC valid:", ethUsdcValid);
        
        // This should be around 2500 (ETH is 2500x more expensive than USDC)
        assertGt(ethUsdcLower, 2400 * PRECISION, "ETH/USDC lower should be ~2400+");
        assertLt(ethUsdcUpper, 2600 * PRECISION, "ETH/USDC upper should be ~2600-");
        assertTrue(ethUsdcValid, "ETH/USDC ratio should be valid");
        
        console.log("[PASS] Price ratio calculation working for realistic ETH/USDC scenario");
    }
    
    /// @notice Test edge cases in price normalization
    function test_PriceNormalization_EdgeCases() public {
        console.log("=== TEST: Price Normalization Edge Cases ===");
        
        // Test Case 1: Different exponents
        console.log("\n--- Test Case 1: Price with -6 exponent ---");
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            2500000000,   // $2500 * 1e6 (with -6 exponent = $2500)  
            25000000,     // $25 * 1e6 confidence
            -6,
            uint64(block.timestamp)
        );
        
        (uint256 price, , , bool valid) = 
            SimplifiedOracleLib.getPriceWithBounds(mockOracle, ETH_USD_PRICE_ID, 60);
            
        console.log("Raw value: 2500000000 (with -6 expo)");
        console.log("Normalized price:", price);
        console.log("Expected:", 2500 * PRECISION);
        
        assertEq(price, 2500 * PRECISION, "Should normalize -6 exponent correctly");
        assertTrue(valid, "Should be valid");
        
        // Test Case 2: Positive exponent (rare but possible)
        console.log("\n--- Test Case 2: Price with +2 exponent ---");
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            25,           // 25 * 10^2 = 2500 
            1,            // 1 * 10^2 = 100 confidence
            2,
            uint64(block.timestamp)
        );
        
        (price, , , valid) = SimplifiedOracleLib.getPriceWithBounds(mockOracle, ETH_USD_PRICE_ID, 60);
        
        console.log("Raw value: 25 (with +2 expo)");
        console.log("Normalized price:", price);
        console.log("Expected:", 2500 * PRECISION);
        
        assertEq(price, 2500 * PRECISION, "Should normalize +2 exponent correctly");
        assertTrue(valid, "Should be valid");
        
        console.log("[PASS] Edge case price normalization working");
    }
    
    /// @notice Test what happens with zero or invalid prices
    function test_InvalidPriceHandling() public {
        console.log("=== TEST: Invalid Price Handling ===");
        
        // Test Case 1: Zero price
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, 0, 1000000, -8, uint64(block.timestamp));
        
        (uint256 price, , , bool valid) = 
            SimplifiedOracleLib.getPriceWithBounds(mockOracle, ETH_USD_PRICE_ID, 60);
            
        console.log("Zero price test - valid:", valid);
        assertFalse(valid, "Zero price should be invalid");
        
        // Test Case 2: Negative price  
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, -100000000, 1000000, -8, uint64(block.timestamp));
        
        (price, , , valid) = SimplifiedOracleLib.getPriceWithBounds(mockOracle, ETH_USD_PRICE_ID, 60);
        
        console.log("Negative price test - valid:", valid);
        assertFalse(valid, "Negative price should be invalid");
        
        // Test Case 3: Stale price
        // Set a definitely stale timestamp (more than 60 seconds ago)
        vm.warp(1000); // Set current time to 1000
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, 100000000, 1000000, -8, uint64(800)); // 200 seconds ago
        
        (price, , , valid) = SimplifiedOracleLib.getPriceWithBounds(mockOracle, ETH_USD_PRICE_ID, 60);
        
        console.log("Stale price test - valid:", valid);
        assertFalse(valid, "Stale price should be invalid (older than 60s)");
        
        console.log("[PASS] Invalid price handling working correctly");
    }
    
    /// @notice Test the specific scenario that's failing in integration tests
    function test_RealisticeScenario_PoolVsOracle() public {
        console.log("=== TEST: Realistic Pool vs Oracle Comparison ===");
        console.log("This test simulates the failing integration test scenario");
        
        // Set up scenario: Pool at 2000 USDC/ETH, Oracle sees ETH=$3000, USDC=$1500
        console.log("\n--- Scenario Setup ---");
        console.log("Pool: 1 ETH = 2000 USDC (ratio: 2000 USDC/ETH)");
        console.log("Oracle: ETH=$3000, USDC=$1500 (ratio: 3000/1500 = 2 USDC/ETH)");
        console.log("Expected: Pool much better for swapper (2000 vs 2) -> Should detect arbitrage");
        
        // These are the EXACT values from the failing test
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            300000000000, // $3000 with -8 exponent
            10000000000,  // $100 confidence  
            -8,
            uint64(block.timestamp)
        );
        
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            150000000000, // $1500 with -8 exponent (!!! This is the problem !!!)
            1000000000,   // $10 confidence
            -8,
            uint64(block.timestamp)
        ); 
        
        // Calculate the price ratio that the hook would see
        (uint256 lowerBound, uint256 upperBound, bool valid) = 
            SimplifiedOracleLib.calculatePriceRatioBounds(
                mockOracle,
                ETH_USD_PRICE_ID,   // denominator
                USDC_USD_PRICE_ID,  // numerator  
                60
            );
            
        console.log("\n--- Oracle Price Analysis ---");
        console.log("ETH price: $3000 +/- $100");
        console.log("USDC price: $1500 +/- $10 <- THIS IS THE PROBLEM!");
        console.log("USDC/ETH ratio bounds:");
        console.log("- Lower: (1500-10)/(3000+100) =", lowerBound * 1000 / PRECISION, "* 1e15");
        console.log("- Upper: (1500+10)/(3000-100) =", upperBound * 1000 / PRECISION, "* 1e15");
        
        // What should the bounds be?
        console.log("\n--- What Should Happen ---");
        console.log("For realistic prices ETH=$3000, USDC=$1.00:");
        console.log("- USDC/ETH = 1/3000 = 0.000333... ~= 3.33e14 (in 1e18 precision)");
        console.log("But with USDC=$1500, we get:");
        console.log("- USDC/ETH = 1500/3000 = 0.5 = 5e17 (in 1e18 precision)");
        
        // Pool price simulation (what would 2000 USDC/ETH look like in 1e18?)
        uint256 simulatedPoolPrice = 2000 * PRECISION;
        console.log("\n--- Pool vs Oracle Comparison ---");
        console.log("Pool price (2000 USDC/ETH in 1e18):", simulatedPoolPrice);
        console.log("Oracle lower bound:", lowerBound);
        console.log("Oracle upper bound:", upperBound);
        
        if (simulatedPoolPrice > upperBound) {
            console.log("-> Pool > Oracle upper -> ZeroForOne arbitrage exists");
        } else if (simulatedPoolPrice < lowerBound) {
            console.log("-> Pool < Oracle lower -> OneForZero arbitrage exists");
        } else {
            console.log("-> Pool within Oracle bounds -> No arbitrage");
        }
        
        console.log("\n[ANALYSIS] The test uses USDC=$1500 which is unrealistic!");
        console.log("This creates artificial 1000x price discrepancies that hide real bugs.");
        console.log("We need tests with realistic prices: ETH=$3000, USDC=$1.00");
        
        assertTrue(valid, "Oracle calculation should be valid");
    }
} 