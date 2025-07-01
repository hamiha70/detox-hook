// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { SimplifiedArbitrageLib } from "../../src/libraries/SimplifiedArbitrageLib.sol";

/**
 * @title ArbitrageLibTest
 * @notice Unit tests for arbitrage detection and hook share calculation
 * @dev Tests economic logic in isolation before integration testing
 */
contract ArbitrageLibTest is Test {
    uint256 constant PRECISION = 1e18;
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant RHO_BPS = 8000; // 80%
    
    /// @notice Test basic arbitrage detection with clear scenarios
    function test_ArbitrageDetection_BasicScenarios() public pure {
        console.log("=== TEST: Basic Arbitrage Detection Logic ===");
        
        // Scenario 1: Pool overpaying (zeroForOne arbitrage)
        console.log("\n--- Scenario 1: Pool overpaying for currency1 (zeroForOne arbitrage) ---");
        console.log("Pool: 3000 USDC/ETH, Oracle: 2400-2600 USDC/ETH -> Pool overpaying");
        
        uint256 poolPrice = 3000 * PRECISION;      // Pool gives 3000 USDC per ETH
        uint256 oracleLower = 2400 * PRECISION;    // Oracle lower bound: 2400 USDC/ETH
        uint256 oracleUpper = 2600 * PRECISION;    // Oracle upper bound: 2600 USDC/ETH
        uint256 swapAmount = 1 * PRECISION;        // 1 ETH swap
        
        uint256 arbitrage1 = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, true // zeroForOne
        );
        
        console.log("Pool price USDC/ETH:", poolPrice / PRECISION);
        console.log("Oracle lower bound:", oracleLower / PRECISION);
        console.log("Oracle upper bound:", oracleUpper / PRECISION);
        console.log("Swap amount ETH:", swapAmount / PRECISION);
        console.log("Arbitrage amount:", arbitrage1);
        console.log("Expected: swapAmount * (poolPrice - oracleUpper) / poolPrice");
        
        uint256 expected1 = swapAmount * (poolPrice - oracleUpper) / poolPrice;
        console.log("Expected arbitrage:", expected1);
        
        assertEq(arbitrage1, expected1, "ZeroForOne arbitrage should match formula");
        assertGt(arbitrage1, 0, "Should detect arbitrage when pool overpaying");
        
        // Scenario 2: Pool underpaying (oneForZero arbitrage)
        console.log("\n--- Scenario 2: Pool underpaying for currency0 (oneForZero arbitrage) ---");
        console.log("Pool: 2000 USDC/ETH, Oracle: 2400-2600 USDC/ETH -> Pool underpaying");
        
        poolPrice = 2000 * PRECISION;              // Pool gives only 2000 USDC per ETH
        // Oracle bounds stay the same: 2400-2600
        swapAmount = 2500 * 1e6;                   // 2500 USDC swap (6 decimals)
        
        uint256 arbitrage2 = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, false // oneForZero
        );
        
        console.log("Pool price USDC/ETH:", poolPrice / PRECISION);
        console.log("Oracle lower bound:", oracleLower / PRECISION);
        console.log("Oracle upper bound:", oracleUpper / PRECISION);
        console.log("Swap amount USDC units:", swapAmount);
        console.log("Arbitrage amount:", arbitrage2);
        console.log("Expected: swapAmount * (oracleLower - poolPrice) / oracleLower");
        
        uint256 expected2 = swapAmount * (oracleLower - poolPrice) / oracleLower;
        console.log("Expected arbitrage:", expected2);
        
        assertEq(arbitrage2, expected2, "OneForZero arbitrage should match formula");
        assertGt(arbitrage2, 0, "Should detect arbitrage when pool underpaying");
        
        // Scenario 3: Pool within bounds (no arbitrage)
        console.log("\n--- Scenario 3: Pool within oracle bounds (no arbitrage) ---");
        poolPrice = 2500 * PRECISION;              // Pool at 2500 (within 2400-2600)
        
        uint256 arbitrage3a = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, true // zeroForOne
        );
        
        uint256 arbitrage3b = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, false // oneForZero
        );
        
        console.log("Pool price USDC/ETH:", poolPrice / PRECISION);
        console.log("ZeroForOne arbitrage:", arbitrage3a);
        console.log("OneForZero arbitrage:", arbitrage3b);
        
        assertEq(arbitrage3a, 0, "No zeroForOne arbitrage when pool within bounds");
        assertEq(arbitrage3b, 0, "No oneForZero arbitrage when pool within bounds");
        
        console.log("[PASS] Basic arbitrage detection logic working correctly");
    }
    
    /// @notice Test hook share calculation
    function test_HookShareCalculation() public pure {
        console.log("=== TEST: Hook Share Calculation ===");
        
        uint256 arbitrageAmount = 1000 * PRECISION; // 1000 units of arbitrage
        
        // Test different hook percentages
        uint256[] memory rhoBpsValues = new uint256[](4);
        rhoBpsValues[0] = 5000;  // 50%
        rhoBpsValues[1] = 8000;  // 80%
        rhoBpsValues[2] = 10000; // 100%
        rhoBpsValues[3] = 0;     // 0%
        
        for (uint i = 0; i < rhoBpsValues.length; i++) {
            uint256 rhoBps = rhoBpsValues[i];
            uint256 hookShare = SimplifiedArbitrageLib.calculateHookShare(arbitrageAmount, rhoBps);
            uint256 expectedShare = arbitrageAmount * rhoBps / BASIS_POINTS;
            
            console.log("Arbitrage:", arbitrageAmount / PRECISION);
            console.log("Hook %:", rhoBps / 100);
            console.log("Hook share:", hookShare);
            console.log("Expected:", expectedShare);
            
            assertEq(hookShare, expectedShare, "Hook share should match percentage calculation");
        }
        
        console.log("[PASS] Hook share calculation working correctly");
    }
    
    /// @notice Test symmetric arbitrage detection
    function test_SymmetricArbitrageDetection() public pure {
        console.log("=== TEST: Symmetric Arbitrage Detection ===");
        console.log("Same price difference should create arbitrage in one direction");
        
        uint256 poolPrice = 2000 * PRECISION;     // Pool: 2000 USDC/ETH
        uint256 oracleLower = 2400 * PRECISION;   // Oracle: 2400-2600 USDC/ETH  
        uint256 oracleUpper = 2600 * PRECISION;
        uint256 swapAmount = 1 * PRECISION;       // 1 ETH equivalent
        
        console.log("\n--- Setup ---");
        console.log("Pool price USDC/ETH:", poolPrice / PRECISION);
        console.log("Oracle lower bound:", oracleLower / PRECISION);
        console.log("Oracle upper bound:", oracleUpper / PRECISION);
        console.log("Analysis: Pool < Oracle -> Pool underpaying -> OneForZero arbitrage expected");
        
        uint256 zeroForOneArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, true
        );
        
        uint256 oneForZeroArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, false
        );
        
        console.log("\n--- Results ---");
        console.log("ZeroForOne arbitrage:", zeroForOneArb);
        console.log("OneForZero arbitrage:", oneForZeroArb);
        
        // Only ONE direction should show arbitrage (pool underpaying case)
        assertEq(zeroForOneArb, 0, "ZeroForOne: Pool < Oracle upper, no arbitrage");
        assertGt(oneForZeroArb, 0, "OneForZero: Pool < Oracle lower, arbitrage exists");
        
        console.log("[PASS] Symmetric logic working - only one direction has arbitrage");
        
        // Now test the opposite: pool overpaying
        console.log("\n--- Opposite Test: Pool Overpaying ---");
        poolPrice = 3000 * PRECISION;             // Pool: 3000 USDC/ETH (overpaying)
        // Oracle bounds stay 2400-2600
        
        console.log("Pool price USDC/ETH:", poolPrice / PRECISION);
        console.log("Analysis: Pool > Oracle -> Pool overpaying -> ZeroForOne arbitrage expected");
        
        zeroForOneArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, true
        );
        
        oneForZeroArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, false
        );
        
        console.log("ZeroForOne arbitrage:", zeroForOneArb);
        console.log("OneForZero arbitrage:", oneForZeroArb);
        
        assertGt(zeroForOneArb, 0, "ZeroForOne: Pool > Oracle upper, arbitrage exists");
        assertEq(oneForZeroArb, 0, "OneForZero: Pool > Oracle lower, no arbitrage");
        
        console.log("[PASS] Opposite direction working correctly");
    }
    
    /// @notice Test edge cases and error conditions
    function test_EdgeCasesAndErrors() public pure {
        console.log("=== TEST: Edge Cases and Error Conditions ===");
        
        // Test Case 1: Zero swap amount
        console.log("\n--- Test Case 1: Zero swap amount ---");
        uint256 arbitrage = SimplifiedArbitrageLib.calculateArbitrageAmount(
            1000 * PRECISION, 800 * PRECISION, 1200 * PRECISION, 0, true
        );
        assertEq(arbitrage, 0, "Zero swap amount should return zero arbitrage");
        
        // Test Case 2: Zero pool price
        console.log("\n--- Test Case 2: Zero pool price ---");
        arbitrage = SimplifiedArbitrageLib.calculateArbitrageAmount(
            0, 800 * PRECISION, 1200 * PRECISION, 1 * PRECISION, true
        );
        assertEq(arbitrage, 0, "Zero pool price should return zero arbitrage");
        
        // Test Case 3: Invalid bounds (upper < lower)
        console.log("\n--- Test Case 3: Invalid bounds ---");
        arbitrage = SimplifiedArbitrageLib.calculateArbitrageAmount(
            1000 * PRECISION, 1200 * PRECISION, 800 * PRECISION, 1 * PRECISION, true
        );
        assertEq(arbitrage, 0, "Invalid bounds should return zero arbitrage");
        
        // Test Case 4: Equal bounds (no confidence interval) but pool price differs
        console.log("\n--- Test Case 4: Equal bounds with arbitrage ---");
        console.log("Pool: 1000, Oracle: 900 (exact) -> Pool overpaying by 10%");
        arbitrage = SimplifiedArbitrageLib.calculateArbitrageAmount(
            1000 * PRECISION, 900 * PRECISION, 900 * PRECISION, 1 * PRECISION, true
        );
        uint256 expectedArbitrage = 1 * PRECISION * (1000 - 900) / 1000; // 10% arbitrage
        assertEq(arbitrage, expectedArbitrage, "Should detect arbitrage even with equal bounds when pool differs");
        console.log("Arbitrage detected:", arbitrage);
        console.log("Expected (10%):", expectedArbitrage);
        
        // Test Case 5: Equal bounds with no arbitrage (pool price equals oracle)
        console.log("\n--- Test Case 5: Equal bounds, no arbitrage ---");
        console.log("Pool: 900, Oracle: 900 (exact) -> No arbitrage");
        arbitrage = SimplifiedArbitrageLib.calculateArbitrageAmount(
            900 * PRECISION, 900 * PRECISION, 900 * PRECISION, 1 * PRECISION, true
        );
        assertEq(arbitrage, 0, "No arbitrage when pool price equals oracle price");
        console.log("Arbitrage (should be 0):", arbitrage);
        
        console.log("[PASS] Edge cases handled correctly");
    }
    
    /// @notice Test realistic ETH/USDC scenario with correct decimals
    function test_RealisticETHUSDCScenario() public pure {
        console.log("=== TEST: Realistic ETH/USDC Scenario ===");
        console.log("Simulates: ETH=$2500, USDC=$1.00, Pool=2000 USDC/ETH");
        
        // Oracle setup (realistic)
        uint256 ethPrice = 2500 * PRECISION;      // $2500 ETH
        uint256 usdcPrice = 1 * PRECISION;        // $1.00 USDC
        
        // Calculate oracle ratio: USDC/ETH = 1/2500 = 0.0004
        uint256 oracleRatio = usdcPrice * PRECISION / ethPrice;
        console.log("Oracle ratio (USDC/ETH):");
        console.log("Value * 1e-6:", oracleRatio * 1e6 / PRECISION);
        
        // Add confidence bands: +/-1% 
        uint256 oracleLower = oracleRatio * 99 / 100;
        uint256 oracleUpper = oracleRatio * 101 / 100;
        
        console.log("Oracle lower bound * 1e-6:", oracleLower * 1e6 / PRECISION);
        console.log("Oracle upper bound * 1e-6:", oracleUpper * 1e6 / PRECISION);
        
        // Pool price: 2000 USDC/ETH (much higher than oracle ~0.0004)
        uint256 poolPrice = 2000 * PRECISION;
        console.log("Pool price USDC/ETH:", poolPrice / PRECISION);
        
        console.log("\n--- Analysis ---");
        console.log("Pool (2000) >> Oracle upper (~0.0004) -> MASSIVE overpaying");
        console.log("This should create huge zeroForOne arbitrage opportunity");
        
        // Test both directions
        uint256 swapAmount = 1 * PRECISION; // 1 ETH
        
        uint256 zeroForOneArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, true
        );
        
        uint256 oneForZeroArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, false
        );
        
        console.log("\n--- Results ---");
        console.log("ZeroForOne arbitrage:", zeroForOneArb);
        console.log("OneForZero arbitrage:", oneForZeroArb);
        
        // Should see massive zeroForOne arbitrage (pool overpaying by 5000x!)
        assertGt(zeroForOneArb, 0, "Should detect massive zeroForOne arbitrage");
        assertEq(oneForZeroArb, 0, "Should not detect oneForZero arbitrage");
        
        // The arbitrage should be nearly the full swap amount (pool paying way too much)
        uint256 expectedZeroForOne = swapAmount * (poolPrice - oracleUpper) / poolPrice;
        assertEq(zeroForOneArb, expectedZeroForOne, "ZeroForOne arbitrage should match formula");
        
        console.log("Expected zeroForOne:", expectedZeroForOne);
        console.log("Arbitrage captures % of swap:", zeroForOneArb * 100 / swapAmount);
        
        console.log("[PASS] Realistic scenario working - detects massive overpayment");
    }
    
    /// @notice Test parameter validation
    function test_ParameterValidation() public pure {
        console.log("=== TEST: Parameter Validation ===");
        
        // Valid parameters
        bool valid1 = SimplifiedArbitrageLib.validateParameters(
            1000 * PRECISION, // poolPrice
            900 * PRECISION,  // oracleLower
            1100 * PRECISION, // oracleUpper
            1 * PRECISION     // swapAmount
        );
        assertTrue(valid1, "Valid parameters should pass");
        
        // Invalid: zero pool price
        bool valid2 = SimplifiedArbitrageLib.validateParameters(
            0, 900 * PRECISION, 1100 * PRECISION, 1 * PRECISION
        );
        assertFalse(valid2, "Zero pool price should fail");
        
        // Invalid: zero oracle bounds
        bool valid3 = SimplifiedArbitrageLib.validateParameters(
            1000 * PRECISION, 0, 1100 * PRECISION, 1 * PRECISION
        );
        assertFalse(valid3, "Zero oracle lower should fail");
        
        // Invalid: upper < lower
        bool valid4 = SimplifiedArbitrageLib.validateParameters(
            1000 * PRECISION, 1100 * PRECISION, 900 * PRECISION, 1 * PRECISION
        );
        assertFalse(valid4, "Upper < Lower should fail");
        
        // Invalid: zero swap amount
        bool valid5 = SimplifiedArbitrageLib.validateParameters(
            1000 * PRECISION, 900 * PRECISION, 1100 * PRECISION, 0
        );
        assertFalse(valid5, "Zero swap amount should fail");
        
        console.log("[PASS] Parameter validation working correctly");
    }
    
    /// @notice Test the exact failing scenario from integration tests
    function test_IntegrationTestFailureScenario() public pure {
        console.log("=== TEST: Integration Test Failure Scenario ===");
        console.log("Reproducing the exact scenario that shows asymmetric behavior");
        
        // From the failing tests: ETH=$3000, USDC=$1500 (unrealistic!)
        console.log("\n--- Reproducing Problematic Test Setup ---");
        console.log("ETH: $3000 +/- $100");
        console.log("USDC: $1500 +/- $10 <- UNREALISTIC!");
        
        // Calculate oracle ratio: USDC/ETH = 1500/3000 = 0.5
        uint256 ethPrice = 3000 * PRECISION;
        uint256 usdcPrice = 1500 * PRECISION;  // This is the problem!
        uint256 oracleRatio = usdcPrice * PRECISION / ethPrice; // 0.5 * PRECISION
        
        console.log("Oracle ratio USDC/ETH * 1e-3:", oracleRatio / (PRECISION / 1000));
        
        // Add confidence (+/-100 for ETH, +/-10 for USDC)
        // Lower: (1500-10)/(3000+100) = 1490/3100
        // Upper: (1500+10)/(3000-100) = 1510/2900
        uint256 oracleLower = (1490 * PRECISION) * PRECISION / (3100 * PRECISION);
        uint256 oracleUpper = (1510 * PRECISION) * PRECISION / (2900 * PRECISION);
        
        console.log("Oracle lower * 1e-3:", oracleLower / (PRECISION / 1000));
        console.log("Oracle upper * 1e-3:", oracleUpper / (PRECISION / 1000));
        
        // Pool price: 2000 USDC/ETH (from the logs)
        uint256 poolPrice = 2000 * PRECISION;
        console.log("Pool price USDC/ETH:", poolPrice / PRECISION);
        
        console.log("\n--- Comparison ---");
        console.log("Pool (2000) vs Oracle (0.48-0.52) -> Pool MASSIVELY higher");
        console.log("This should create huge zeroForOne arbitrage, not oneForZero!");
        
        // Test both directions
        uint256 swapAmount = 1 * PRECISION;
        
        uint256 zeroForOneArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, true
        );
        
        uint256 oneForZeroArb = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice, oracleLower, oracleUpper, swapAmount, false
        );
        
        console.log("\n--- Results ---");
        console.log("ZeroForOne arbitrage:", zeroForOneArb);
        console.log("OneForZero arbitrage:", oneForZeroArb);
        console.log("ZeroForOne percent of swap:", zeroForOneArb * 100 / swapAmount);
        
        // With these artificial prices, we SHOULD see massive zeroForOne arbitrage
        assertGt(zeroForOneArb, 0, "Should detect massive zeroForOne arbitrage");
        assertEq(oneForZeroArb, 0, "Should NOT detect oneForZero arbitrage");
        
        console.log("\n[ANALYSIS] Unit test shows CORRECT behavior!");
        console.log("The integration test's asymmetric behavior must be due to:");
        console.log("1. Wrong price ratio calculation in oracle lib");
        console.log("2. Wrong currency ordering (ETH vs USDC confusion)");
        console.log("3. Decimal conversion errors");
        
        console.log("[PASS] Arbitrage lib logic is correct - problem is elsewhere");
    }
} 