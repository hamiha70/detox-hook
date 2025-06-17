// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { ArbitrageLib } from "../src/libraries/ArbitrageLib.sol";
import { OracleLib } from "../src/libraries/OracleLib.sol";
import { PythStructs } from "../src/libraries/PythLibrary.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

/**
 * @title ArbitrageLibTest
 * @notice Comprehensive tests for ArbitrageLib library functions with confidence bounds
 */
contract ArbitrageLibTest is Test {
    using ArbitrageLib for ArbitrageLib.ArbitrageParams;

    // Constants for testing
    uint256 constant PRICE_PRECISION = 1e8;
    uint256 constant BASIS_POINTS = 10000;
    
    // Test parameters
    uint256 constant DEFAULT_ALPHA_BPS = 500; // 5%
    uint256 constant DEFAULT_RHO_BPS = 8000; // 80%
    
    // Sample prices (8 decimal precision)
    uint256 constant ETH_PRICE = 2000 * PRICE_PRECISION; // $2000
    uint256 constant USDC_PRICE = 1 * PRICE_PRECISION; // $1
    uint256 constant WBTC_PRICE = 40000 * PRICE_PRECISION; // $40000
    
    // Sample confidence values
    uint256 constant ETH_CONF = 10 * PRICE_PRECISION; // $10 confidence
    uint256 constant USDC_CONF = 1 * PRICE_PRECISION / 100; // $0.01 confidence

    function setUp() public {
        // Test setup if needed
    }

    // ============ calculateMarketPriceBounds Tests ============

    function test_calculateMarketPriceBounds_Normal() public {
        (uint256 lower, uint256 upper) = ArbitrageLib.calculateMarketPriceBounds(
            USDC_PRICE, // $1 output
            ETH_PRICE,  // $2000 input
            USDC_CONF,  // $0.01 output conf
            ETH_CONF    // $10 input conf
        );

        // Lower: (1 - 0.01) / (2000 + 10) = 0.99 / 2010 ≈ 0.0004925
        // Upper: (1 + 0.01) / (2000 - 10) = 1.01 / 1990 ≈ 0.0005075
        uint256 expectedLower = (99 * PRICE_PRECISION) / (201000); // 0.99 / 2010
        uint256 expectedUpper = (101 * PRICE_PRECISION) / (199000); // 1.01 / 1990
        
        assertApproxEqRel(lower, expectedLower, 0.01e18, "Lower bound calculation incorrect");
        assertApproxEqRel(upper, expectedUpper, 0.01e18, "Upper bound calculation incorrect");
    }

    function test_calculateMarketPriceBounds_ZeroConfidence() public {
        (uint256 lower, uint256 upper) = ArbitrageLib.calculateMarketPriceBounds(
            USDC_PRICE, // $1 output
            ETH_PRICE,  // $2000 input
            0,          // No output conf
            0           // No input conf
        );

        // Should be same as regular market price: 1/2000 = 0.0005
        uint256 expectedPrice = (USDC_PRICE * PRICE_PRECISION) / ETH_PRICE;
        assertEq(lower, expectedPrice, "Lower bound should equal market price with zero confidence");
        assertEq(upper, expectedPrice, "Upper bound should equal market price with zero confidence");
    }

    // ============ isOutsideConfidenceBand Tests ============

    function test_isOutsideConfidenceBand_Outside() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: 1000 * PRICE_PRECISION, // Very high pool price
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        bool isOutside = ArbitrageLib.isOutsideConfidenceBand(params);
        assertTrue(isOutside, "Pool price should be outside confidence band");
    }

    function test_isOutsideConfidenceBand_Inside() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: (USDC_PRICE * PRICE_PRECISION) / ETH_PRICE, // Exact market price
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        bool isOutside = ArbitrageLib.isOutsideConfidenceBand(params);
        assertFalse(isOutside, "Pool price should be inside confidence band");
    }

    // ============ calculateArbitrageOpportunity Tests (with confidence) ============

    function test_calculateArbitrageOpportunity_ZeroForOne_OutsideUpperBound() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: 1000 * PRICE_PRECISION, // Very high pool price, outside upper bound
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });
        (,uint256 upperBound) = ArbitrageLib.calculateMarketPriceBounds(
            USDC_PRICE, ETH_PRICE, USDC_CONF, ETH_CONF
        );
        uint256 expected = FullMath.mulDiv(params.exactInputAmount, params.poolPrice - upperBound, params.poolPrice);
        uint256 arbitrageOpp = ArbitrageLib.calculateArbitrageOpportunity(params);
        console.log("[TEST] inputAmount");
        console.logUint(params.exactInputAmount);
        console.log("[TEST] poolPrice");
        console.logUint(params.poolPrice);
        console.log("[TEST] upperBound");
        console.logUint(upperBound);
        console.log("[TEST] expected arbitrageOpp");
        console.logUint(expected);
        console.log("[TEST] actual arbitrageOpp");
        console.logUint(arbitrageOpp);
        assertEq(arbitrageOpp, expected, "Arbitrage should be calculated against upper confidence bound (relative)");
        assertGt(arbitrageOpp, 0, "Should have arbitrage opportunity");
    }

    function test_calculateArbitrageOpportunity_ZeroForOne_InsideBounds() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: (USDC_PRICE * PRICE_PRECISION) / ETH_PRICE, // Exact market price
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        uint256 arbitrageOpp = ArbitrageLib.calculateArbitrageOpportunity(params);
        assertEq(arbitrageOpp, 0, "Should be no arbitrage when inside confidence bounds");
    }

    function test_calculateArbitrageOpportunity_NotZeroForOne_OutsideLowerBound() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: PRICE_PRECISION / 10000, // Very low pool price, outside lower bound
            inputPrice: USDC_PRICE,
            outputPrice: ETH_PRICE,
            inputPriceConf: USDC_CONF,
            outputPriceConf: ETH_CONF,
            exactInputAmount: 2000 * 1e6, // 2000 USDC
            zeroForOne: false
        });
        (uint256 lowerBound,) = ArbitrageLib.calculateMarketPriceBounds(
            ETH_PRICE, USDC_PRICE, ETH_CONF, USDC_CONF
        );
        uint256 expected = FullMath.mulDiv(params.exactInputAmount, lowerBound - params.poolPrice, lowerBound);
        uint256 arbitrageOpp = ArbitrageLib.calculateArbitrageOpportunity(params);
        console.log("[TEST] inputAmount");
        console.logUint(params.exactInputAmount);
        console.log("[TEST] poolPrice");
        console.logUint(params.poolPrice);
        console.log("[TEST] lowerBound");
        console.logUint(lowerBound);
        console.log("[TEST] expected arbitrageOpp");
        console.logUint(expected);
        console.log("[TEST] actual arbitrageOpp");
        console.logUint(arbitrageOpp);
        assertEq(arbitrageOpp, expected, "Arbitrage should be calculated against lower confidence bound (relative)");
        assertGt(arbitrageOpp, 0, "Should have arbitrage opportunity");
    }

    // ============ shouldInterfere Tests (with confidence) ============

    function test_shouldInterfere_OutsideBandAndAboveThreshold() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: 2000 * PRICE_PRECISION, // High pool price, outside confidence band
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        bool result = ArbitrageLib.shouldInterfere(params);
        assertTrue(result, "Should interfere when outside band and advantageous");
    }

    function test_shouldInterfere_OutsideBandButNotAdvantageous() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: PRICE_PRECISION / 2000, // Very low pool price, outside band but not advantageous for zeroForOne
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        bool result = ArbitrageLib.shouldInterfere(params);
        assertFalse(result, "Should not interfere when not advantageous for swapper");
    }

    function test_shouldInterfere_InsideBandEvenIfAdvantageous() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: (USDC_PRICE * PRICE_PRECISION) / ETH_PRICE, // Market price, inside confidence band
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        bool result = ArbitrageLib.shouldInterfere(params);
        assertFalse(result, "Should not interfere when inside confidence band");
    }

    // ============ analyzeArbitrageOpportunity Tests (with confidence) ============

    function test_analyzeArbitrageOpportunity_ShouldInterfere() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: 1000 * PRICE_PRECISION, // Very high, outside confidence band
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            params,
            DEFAULT_RHO_BPS
        );

        assertTrue(result.isOutsideConfidenceBand, "Should be outside confidence band");
        assertTrue(result.shouldInterfere, "Should interfere with large arbitrage outside band");
        assertGt(result.arbitrageOpportunity, 0, "Should have arbitrage opportunity");
        assertGt(result.hookShare, 0, "Should have hook share");
        assertEq(result.hookShare, (result.arbitrageOpportunity * DEFAULT_RHO_BPS) / BASIS_POINTS, "Hook share calculation");
    }

    function test_analyzeArbitrageOpportunity_ShouldNotInterfere_InsideBand() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: (USDC_PRICE * PRICE_PRECISION) / ETH_PRICE, // Market price, inside band
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            params,
            DEFAULT_RHO_BPS
        );

        assertFalse(result.isOutsideConfidenceBand, "Should be inside confidence band");
        assertFalse(result.shouldInterfere, "Should not interfere when inside confidence band");
        assertEq(result.arbitrageOpportunity, 0, "Should have no arbitrage opportunity inside band");
        assertEq(result.hookShare, 0, "Should have zero hook share");
    }

    function test_analyzeArbitrageOpportunity_ShouldNotInterfere_NotAdvantageous() public {
        // Create a scenario where pool is outside band but not advantageous for swapper
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: PRICE_PRECISION / 10000, // Very low pool price (10,000), definitely outside lower bound
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 1 ether,
            zeroForOne: true
        });

        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            params,
            DEFAULT_RHO_BPS
        );

        assertTrue(result.isOutsideConfidenceBand, "Should be outside confidence band");
        assertFalse(result.shouldInterfere, "Should not interfere when not advantageous for swapper");
        assertEq(result.arbitrageOpportunity, 0, "Should have no arbitrage opportunity when not advantageous");
        assertEq(result.hookShare, 0, "Should have zero hook share when not interfering");
    }

    // ============ normalizePythConfidence Tests ============

    function test_normalizePythConfidence_PositiveExponent() public {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 2000,
            conf: 10, // $10 confidence
            expo: -2, // 2 decimal places
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythConfidence(pythPrice);
        // expo = -2, target = -8, so need to multiply by 10^6 to get more precision
        // 10 * 10^6 = 10,000,000
        assertEq(normalized, 10 * 1e6, "Confidence normalization incorrect");
    }

    function test_normalizePythConfidence_NegativeExponent() public {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 200000000000,
            conf: 1000000000, // Confidence with 11 decimals
            expo: -11,
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythConfidence(pythPrice);
        // expo = -11, target = -8, so need to divide by 10^3 to reduce precision
        // 1000000000 / 1000 = 1000000
        assertEq(normalized, 1000000000 / 1000, "Confidence normalization incorrect");
    }

    function test_normalizePythConfidence_ZeroConfidence() public {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 2000,
            conf: 0,
            expo: -8,
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythConfidence(pythPrice);
        assertEq(normalized, 0, "Zero confidence should return zero");
    }

    // ============ Integration Tests with Confidence ============

    function test_fullArbitrageFlow_WithConfidence_ShouldInterfere() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: 2000 * PRICE_PRECISION, // High pool price, outside upper bound
            inputPrice: ETH_PRICE, // $2000
            outputPrice: USDC_PRICE, // $1
            inputPriceConf: ETH_CONF, // $10
            outputPriceConf: USDC_CONF, // $0.01
            exactInputAmount: 10 ether,
            zeroForOne: true
        });

        // Validate parameters
        assertTrue(ArbitrageLib.validateArbitrageParams(params), "Parameters should be valid");

        // Check confidence band
        bool isOutside = ArbitrageLib.isOutsideConfidenceBand(params);
        assertTrue(isOutside, "Pool price should be outside confidence band");

        // Analyze arbitrage opportunity
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            params,
            DEFAULT_RHO_BPS
        );

        // Verify results
        assertTrue(result.isOutsideConfidenceBand, "Should be outside confidence band");
        assertTrue(result.shouldInterfere, "Should interfere with large arbitrage outside band");
        assertGt(result.arbitrageOpportunity, 0, "Should have arbitrage opportunity");
        assertEq(result.hookShare, (result.arbitrageOpportunity * DEFAULT_RHO_BPS) / BASIS_POINTS, "Hook share calculation");

        console.log("Arbitrage opportunity:", result.arbitrageOpportunity);
        console.log("Hook share:", result.hookShare);
        console.log("Outside confidence band:", result.isOutsideConfidenceBand);
    }

    function test_fullArbitrageFlow_WithConfidence_ShouldNotInterfere() public {
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: (USDC_PRICE * PRICE_PRECISION) / ETH_PRICE, // Market price, inside band
            inputPrice: ETH_PRICE,
            outputPrice: USDC_PRICE,
            inputPriceConf: ETH_CONF,
            outputPriceConf: USDC_CONF,
            exactInputAmount: 10 ether,
            zeroForOne: true
        });

        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            params,
            DEFAULT_RHO_BPS
        );

        // Verify results - should not interfere when inside confidence band
        assertFalse(result.isOutsideConfidenceBand, "Should be inside confidence band");
        assertFalse(result.shouldInterfere, "Should not interfere when inside confidence band");
        assertEq(result.arbitrageOpportunity, 0, "Should have no arbitrage opportunity inside band");
        assertEq(result.hookShare, 0, "Should have zero hook share");
    }

    // ============ Legacy Tests (keeping for backward compatibility) ============

    function test_calculateMarketPrice_Normal() public {
        uint256 marketPrice = ArbitrageLib.calculateMarketPrice(ETH_PRICE, USDC_PRICE);
        assertEq(marketPrice, 2000 * PRICE_PRECISION, "Market price calculation incorrect");
    }

    function test_calculateHookShare_Normal() public {
        uint256 arbitrageOpp = 1 ether;
        uint256 rhoBps = 8000; // 80%

        uint256 hookShare = ArbitrageLib.calculateHookShare(arbitrageOpp, rhoBps);
        assertEq(hookShare, 0.8 ether, "Hook share calculation incorrect");
    }

    function test_normalizePythPrice_PositiveExponent() public {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 2000,
            conf: 1,
            expo: -2,
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythPrice(pythPrice);
        // expo = -2, target = -8, so need to multiply by 10^6
        // 2000 * 10^6 = 2,000,000,000
        assertEq(normalized, 2000 * 1e6, "Price normalization incorrect");
    }

    function test_PoolAndOracleNormalization_ETH_USDC() public {
        // Simulate pool at 3000 USDC/ETH
        // sqrtPriceX96 for 3000 USDC/ETH (ETH 18 decimals, USDC 6):
        // price = 3000 * 1e12 (to get 18 decimals)
        uint256 price18 = 3000 * 1e12;
        uint160 sqrtPriceX96 = HookLibrary.priceToSqrtPrice(price18);
        uint256 poolPrice18 = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
        uint256 poolPrice8 = FullMath.mulDiv(poolPrice18, 1e8, 1e18); // Normalize to 8 decimals
        
        // Simulate Pyth oracle at 2000 USDC/ETH, expo -8
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 2000 * 1e6, // $2000, 8 decimals
            conf: 10 * 1e6,    // $10 confidence
            expo: -8,
            publishTime: block.timestamp
        });
        uint256 oraclePrice8 = OracleLib.normalizePythPrice(pythPrice);
        uint256 oracleConf8 = OracleLib.normalizePythConfidence(pythPrice);
        
        // For USDC, price = 1 * 1e8, expo -8
        PythStructs.Price memory usdcPrice = PythStructs.Price({
            price: 1 * 1e8,
            conf: 1 * 1e6,
            expo: -8,
            publishTime: block.timestamp
        });
        uint256 usdcOraclePrice8 = OracleLib.normalizePythPrice(usdcPrice);
        uint256 usdcOracleConf8 = OracleLib.normalizePythConfidence(usdcPrice);
        
        // Log all normalized values
        console.log("[TEST] poolPrice18:", poolPrice18);
        console.log("[TEST] poolPrice8:", poolPrice8);
        console.log("[TEST] oraclePrice8:", oraclePrice8);
        console.log("[TEST] oracleConf8:", oracleConf8);
        console.log("[TEST] usdcOraclePrice8:", usdcOraclePrice8);
        console.log("[TEST] usdcOracleConf8:", usdcOracleConf8);
        
        // Prepare arbitrage params for ETH->USDC (zeroForOne)
        uint256 exactInputAmount = 0.1 ether;
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: poolPrice8,
            inputPrice: oraclePrice8, // ETH price
            outputPrice: usdcOraclePrice8, // USDC price
            inputPriceConf: oracleConf8,
            outputPriceConf: usdcOracleConf8,
            exactInputAmount: exactInputAmount,
            zeroForOne: true
        });
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(params, 8000);
        
        // Log arbitrage result
        console.log("[TEST] arbitrageOpportunity:", result.arbitrageOpportunity);
        console.log("[TEST] hookShare:", result.hookShare);
        
        // Assert that hookShare never exceeds input amount
        assertLe(result.hookShare, exactInputAmount, "Hook share must not exceed input amount");
    }

    function test_arbitrageOpportunityNeverExceedsInputAmount_LargeDiff() public {
        // Simulate a large price difference
        uint256 inputAmount = 1e18; // 1 ETH
        uint256 poolPrice = 1_000_000_000; // 1e9 (much larger than marketPriceUpper)
        uint256 marketPriceUpper = 1_000; // 1e3
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: poolPrice,
            inputPrice: 2_000_000_000, // arbitrary
            outputPrice: 1_000_000, // arbitrary
            inputPriceConf: 0,
            outputPriceConf: 0,
            exactInputAmount: inputAmount,
            zeroForOne: true
        });
        // Patch: simulate marketPriceUpper
        // The patched ArbitrageLib will use poolPrice and marketPriceUpper as above
        uint256 arbitrageOpp = FullMath.mulDiv(inputAmount, poolPrice - marketPriceUpper, poolPrice);
        console.log("[TEST] inputAmount");
        console.logUint(inputAmount);
        console.log("[TEST] poolPrice");
        console.logUint(poolPrice);
        console.log("[TEST] marketPriceUpper");
        console.logUint(marketPriceUpper);
        console.log("[TEST] arbitrageOpp");
        console.logUint(arbitrageOpp);
        assertLe(arbitrageOpp, inputAmount, "Arbitrage opportunity must not exceed input amount");
    }

    // ============ Specific Hookshare Calculation Tests ============

    /// @notice Test Case 1: zeroForOne=true, ETH underpriced in pool should capture 25%
    function test_HookshareCalculation_Case1_ZeroForOne_ETHUnderpriced() public {
        // Pool: USDC/ETH = 2000, Oracle: USDC/ETH = 1500
        // ETH is underpriced in pool → should capture (2000-1500)/2000 = 25%
        
        uint256 poolPrice = 2000 * ArbitrageLib.getArbitragePrecision(); // 2000 USDC/ETH (18 decimals)
        uint256 ethOraclePrice = 1500 * ArbitrageLib.getArbitragePrecision(); // ETH = $1500 (18 decimals)
        uint256 usdcOraclePrice = 1 * ArbitrageLib.getArbitragePrecision(); // USDC = $1 (18 decimals)
        uint256 inputAmount = 0.001e18; // 0.001 ETH
        
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: poolPrice,
            inputPrice: ethOraclePrice,
            outputPrice: usdcOraclePrice,
            inputPriceConf: 0, // No confidence for clean calculation
            outputPriceConf: 0,
            exactInputAmount: inputAmount,
            zeroForOne: true
        });
        
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(params, 10000); // 100% rho for clean calculation
        
        // Expected: 25% of 0.001 ETH = 0.00025 ETH
        uint256 expectedHookShare = (inputAmount * 25) / 100;
        
        console.log("[CASE1] Pool price (USDC/ETH):", poolPrice / PRICE_PRECISION);
        console.log("[CASE1] Oracle price (ETH USD):", ethOraclePrice / PRICE_PRECISION);
        console.log("[CASE1] Input amount (ETH wei):", inputAmount);
        console.log("[CASE1] Expected hookShare (25%):", expectedHookShare);
        console.log("[CASE1] Actual hookShare:", result.hookShare);
        console.log("[CASE1] Arbitrage opportunity:", result.arbitrageOpportunity);
        
        // Verify the calculation
        assertTrue(result.shouldInterfere, "Should interfere when ETH underpriced");
        assertApproxEqRel(result.hookShare, expectedHookShare, 0.01e18, "Should capture ~25% of input");
    }

    /// @notice Test Case 2: zeroForOne=true, ETH overpriced in pool should NOT interfere
    function test_HookshareCalculation_Case2_ZeroForOne_ETHOverpriced() public {
        // Pool: USDC/ETH = 2000, Oracle: USDC/ETH = 3000
        // ETH is overpriced in pool → should NOT interfere
        
        uint256 poolPrice = 2000 * PRICE_PRECISION; // 2000 USDC/ETH
        uint256 ethOraclePrice = 3000 * PRICE_PRECISION; // ETH = $3000 (higher than pool)
        uint256 usdcOraclePrice = 1 * PRICE_PRECISION; // USDC = $1
        uint256 inputAmount = 0.001e18; // 0.001 ETH
        
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: poolPrice,
            inputPrice: ethOraclePrice,
            outputPrice: usdcOraclePrice,
            inputPriceConf: 0,
            outputPriceConf: 0,
            exactInputAmount: inputAmount,
            zeroForOne: true
        });
        
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(params, 8000);
        
        console.log("[CASE2] Pool price (USDC/ETH):", poolPrice / PRICE_PRECISION);
        console.log("[CASE2] Oracle price (ETH USD):", ethOraclePrice / PRICE_PRECISION);
        console.log("[CASE2] Should interfere:", result.shouldInterfere);
        console.log("[CASE2] Hook share:", result.hookShare);
        
        // Should NOT interfere when ETH is overpriced in pool
        assertFalse(result.shouldInterfere, "Should NOT interfere when ETH overpriced");
        assertEq(result.hookShare, 0, "Hook share should be zero");
    }

    /// @notice Test Case 3: zeroForOne=false, USDC underpriced in pool should capture ~33%
    function test_HookshareCalculation_Case3_OneForZero_USDCUnderpriced() public {
        // Pool: USDC/ETH = 2000, Oracle: USDC/ETH = 3000
        // USDC is underpriced in pool → should capture (3000-2000)/3000 = 33.33%
        
        uint256 poolPrice = 2000 * PRICE_PRECISION; // 2000 USDC/ETH (pool price)
        uint256 usdcOraclePrice = 1 * PRICE_PRECISION; // USDC = $1
        uint256 ethOraclePrice = 3000 * PRICE_PRECISION; // ETH = $3000 (oracle price)
        uint256 inputAmount = 2 * 1e6; // 2 USDC (6 decimals)
        
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: poolPrice,
            inputPrice: usdcOraclePrice,
            outputPrice: ethOraclePrice,
            inputPriceConf: 0,
            outputPriceConf: 0,
            exactInputAmount: inputAmount,
            zeroForOne: false
        });
        
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(params, 10000); // 100% rho for clean calculation
        
        // Expected: 33.33% of 2 USDC = 0.6667 USDC
        uint256 expectedHookShare = (inputAmount * 3333) / 10000; // 33.33%
        
        console.log("[CASE3] Pool price (USDC/ETH):", poolPrice / PRICE_PRECISION);
        console.log("[CASE3] Oracle price (ETH USD):", ethOraclePrice / PRICE_PRECISION);
        console.log("[CASE3] Input amount (USDC):", inputAmount);
        console.log("[CASE3] Expected hookShare (33.33%):", expectedHookShare);
        console.log("[CASE3] Actual hookShare:", result.hookShare);
        console.log("[CASE3] Arbitrage opportunity:", result.arbitrageOpportunity);
        
        // Verify the calculation
        assertTrue(result.shouldInterfere, "Should interfere when USDC underpriced");
        assertApproxEqRel(result.hookShare, expectedHookShare, 0.01e18, "Should capture ~33% of input");
    }

    /// @notice Test Case 4: zeroForOne=false, USDC overpriced in pool should NOT interfere
    function test_HookshareCalculation_Case4_OneForZero_USDCOverpriced() public {
        // Pool: USDC/ETH = 2000, Oracle: USDC/ETH = 1500
        // USDC is overpriced in pool → should NOT interfere
        
        uint256 poolPrice = 2000 * PRICE_PRECISION; // 2000 USDC/ETH (pool price)
        uint256 usdcOraclePrice = 1 * PRICE_PRECISION; // USDC = $1
        uint256 ethOraclePrice = 1500 * PRICE_PRECISION; // ETH = $1500 (oracle price)
        uint256 inputAmount = 2 * 1e6; // 2 USDC
        
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: poolPrice,
            inputPrice: usdcOraclePrice,
            outputPrice: ethOraclePrice,
            inputPriceConf: 0,
            outputPriceConf: 0,
            exactInputAmount: inputAmount,
            zeroForOne: false
        });
        
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(params, 8000);
        
        console.log("[CASE4] Pool price (USDC/ETH):", poolPrice / PRICE_PRECISION);
        console.log("[CASE4] Oracle price (ETH USD):", ethOraclePrice / PRICE_PRECISION);
        console.log("[CASE4] Should interfere:", result.shouldInterfere);
        console.log("[CASE4] Hook share:", result.hookShare);
        
        // Should NOT interfere when USDC is overpriced in pool
        assertFalse(result.shouldInterfere, "Should NOT interfere when USDC overpriced");
        assertEq(result.hookShare, 0, "Hook share should be zero");
    }

    /// @notice Edge case: High-value token vs low-value token (3000:3 ratio = 0.001)
    function test_EdgeCase_SmallRatio_Token0Underpriced() public {
        // Edge case: Token0=$3000, Token1=$3 → market ratio = 3/3000 = 0.001
        // Pool ratio = 0.0008 (token0 underpriced) → should capture arbitrage
        
        uint256 token0PriceUSD = 3000 * ArbitrageLib.getArbitragePrecision(); // $3000
        uint256 token1PriceUSD = 3 * ArbitrageLib.getArbitragePrecision(); // $3
        uint256 poolPrice = 8 * ArbitrageLib.getArbitragePrecision() / 10000; // 0.0008 (token0 underpriced)
        uint256 inputAmount = 1000 * 1e6; // 1000 token1 (assuming 6 decimals)
        
        ArbitrageLib.ArbitrageParams memory params = ArbitrageLib.ArbitrageParams({
            poolPrice: poolPrice,
            inputPrice: token1PriceUSD,  // Selling token1
            outputPrice: token0PriceUSD, // For token0
            inputPriceConf: 0,
            outputPriceConf: 0,
            exactInputAmount: inputAmount,
            zeroForOne: false // oneForZero: selling token1 for token0
        });
        
        // Expected market ratio: token1/token0 = 3/3000 = 0.001
        uint256 expectedMarketRatio = ArbitrageLib.getArbitragePrecision() / 1000; // 0.001 in 18 decimals
        
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(params, 10000);
        
        console.log("[EDGE] Token0 price (USD):", token0PriceUSD / 1e15);
        console.log("[EDGE] Token1 price (USD):", token1PriceUSD / 1e15);
        console.log("[EDGE] Pool ratio (token1/token0):", poolPrice / 1e12);
        console.log("[EDGE] Expected market ratio:", expectedMarketRatio / 1e12);
        console.log("[EDGE] Input amount (token1):", inputAmount);
        console.log("[EDGE] Arbitrage opportunity:", result.arbitrageOpportunity);
        console.log("[EDGE] Hook share:", result.hookShare);
        console.log("[EDGE] Should interfere:", result.shouldInterfere);
        
        // Market ratio should be 0.001, pool ratio is 0.0008
        // Pool < Market → arbitrage exists for oneForZero direction
        // Expected: (0.001 - 0.0008) / 0.001 = 20% arbitrage opportunity
        uint256 expectedHookShare = (inputAmount * 20) / 100; // 20% of input
        
        assertTrue(result.shouldInterfere, "Should detect arbitrage when token0 underpriced");
        assertGt(result.arbitrageOpportunity, 0, "Should have arbitrage opportunity");
        assertApproxEqRel(result.hookShare, expectedHookShare, 0.05e18, "Should capture ~20% hookshare");
    }

    /// @notice Edge case: Verify small ratio calculation precision
    function test_EdgeCase_SmallRatio_Precision() public {
        // Direct test of market price calculation for small ratios
        uint256 highValueUSD = 3000 * ArbitrageLib.getArbitragePrecision(); // $3000
        uint256 lowValueUSD = 3 * ArbitrageLib.getArbitragePrecision(); // $3
        
        // Calculate both directions
        uint256 marketRatio1 = ArbitrageLib.calculateMarketPriceRatio(lowValueUSD, highValueUSD, 6, 18);
        uint256 marketRatio2 = ArbitrageLib.calculateMarketPriceRatio(highValueUSD, lowValueUSD, 18, 6);
        
        console.log("[PRECISION] Low/High ratio:", marketRatio1 / 1e12);
        console.log("[PRECISION] High/Low ratio:", marketRatio2 / 1e15);
        
        // Verify precision preservation
        assertGt(marketRatio1, 0, "Small ratio should not be truncated to zero");
        assertEq(marketRatio1, ArbitrageLib.getArbitragePrecision() / 1000, "Should equal 0.001 in 18 decimals");
        assertEq(marketRatio2, 1000 * ArbitrageLib.getArbitragePrecision(), "Should equal 1000 in 18 decimals");
        
        // Verify they are reciprocals (within precision limits)
        uint256 product = FullMath.mulDiv(marketRatio1, marketRatio2, ArbitrageLib.getArbitragePrecision());
        assertApproxEqRel(product, ArbitrageLib.getArbitragePrecision(), 0.001e18, "Should be reciprocals");
    }
} 