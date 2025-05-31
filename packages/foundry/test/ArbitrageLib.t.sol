// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { ArbitrageLib } from "../src/libraries/ArbitrageLib.sol";
import { PythStructs } from "../src/libraries/PythLibrary.sol";

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

        uint256 arbitrageOpp = ArbitrageLib.calculateArbitrageOpportunity(params);
        
        // Should calculate against upper bound, not market price
        (,uint256 upperBound) = ArbitrageLib.calculateMarketPriceBounds(
            USDC_PRICE, ETH_PRICE, USDC_CONF, ETH_CONF
        );
        uint256 expected = (1 ether * (params.poolPrice - upperBound)) / PRICE_PRECISION;
        
        assertEq(arbitrageOpp, expected, "Arbitrage should be calculated against upper confidence bound");
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

        uint256 arbitrageOpp = ArbitrageLib.calculateArbitrageOpportunity(params);
        
        // Should calculate against lower bound
        (uint256 lowerBound,) = ArbitrageLib.calculateMarketPriceBounds(
            ETH_PRICE, USDC_PRICE, ETH_CONF, USDC_CONF
        );
        uint256 expected = (params.exactInputAmount * (lowerBound - params.poolPrice)) / PRICE_PRECISION;
        
        assertEq(arbitrageOpp, expected, "Arbitrage should be calculated against lower confidence bound");
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

        uint256 normalized = ArbitrageLib.normalizePythConfidence(pythPrice);
        // expo = -2, target = -8, so multiply by 10^(-2 + 8) = 10^6
        assertEq(normalized, 10 * 1e6, "Confidence normalization incorrect");
    }

    function test_normalizePythConfidence_NegativeExponent() public {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 200000000000,
            conf: 1000000000, // Confidence with 11 decimals
            expo: -11,
            publishTime: block.timestamp
        });

        uint256 normalized = ArbitrageLib.normalizePythConfidence(pythPrice);
        // expo = -11, target = -8, so divide by 10^(-8 - (-11)) = 10^3
        assertEq(normalized, 1000000000 / 1000, "Confidence normalization incorrect");
    }

    function test_normalizePythConfidence_ZeroConfidence() public {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 2000,
            conf: 0,
            expo: -8,
            publishTime: block.timestamp
        });

        uint256 normalized = ArbitrageLib.normalizePythConfidence(pythPrice);
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

        uint256 normalized = ArbitrageLib.normalizePythPrice(pythPrice);
        assertEq(normalized, 2000 * 1e6, "Price normalization incorrect");
    }
} 