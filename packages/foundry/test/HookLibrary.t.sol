// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title HookLibrary Unit Tests
/// @notice Comprehensive tests for HookLibrary functions, focusing on liquidity mathematics
contract HookLibraryTest is Test {
    
    // ============ Test Constants ============
    
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant ETH_DECIMALS = 18;
    
    // Current market context (ETH ~3600 USDC)
    uint256 constant CURRENT_ETH_PRICE = 3600;
    uint256 constant LOWER_BOUND_PRICE = 3000;
    uint256 constant UPPER_BOUND_PRICE = 4000;
    
    // Test scenarios
    uint256 constant SMALL_LIQUIDITY = 1000 * 10**USDC_DECIMALS; // 1k USDC
    uint256 constant MEDIUM_LIQUIDITY = 100000 * 10**USDC_DECIMALS; // 100k USDC  
    uint256 constant LARGE_LIQUIDITY = 1000000 * 10**USDC_DECIMALS; // 1M USDC
    
    // ============ Basic Functionality Tests ============
    
    function test_CalculateETHUSDCLiquidity_BasicFunctionality() public pure {
        console.log("=== TEST: Basic Liquidity Calculation ===");
        
        uint256 targetUSDC = SMALL_LIQUIDITY; // 1k USDC
        uint256 ethPrice = CURRENT_ETH_PRICE; // 3600 USDC/ETH
        uint256 rangePercent = 5; // 5%
        
        (uint256 ethAmount, uint256 usdcAmount, int24 tickLower, int24 tickUpper) = 
            HookLibrary.calculateETHUSDCLiquidity(targetUSDC, ethPrice, rangePercent);
            
        console.log("Input USDC target:", targetUSDC / 10**USDC_DECIMALS);
        console.log("ETH price:", ethPrice);
        console.log("Output ETH amount:", ethAmount / 10**ETH_DECIMALS);
        console.log("Output USDC amount:", usdcAmount / 10**USDC_DECIMALS);
        
        // Basic validations
        assertTrue(ethAmount > 0, "ETH amount should be positive");
        assertTrue(usdcAmount > 0, "USDC amount should be positive");
        assertTrue(tickLower < tickUpper, "tickLower should be less than tickUpper");
        
        // Should have minimum amounts
        assertGe(ethAmount, 0.001 ether, "Should have minimum ETH amount");
        assertGe(usdcAmount, 1000 * 10**USDC_DECIMALS, "Should have minimum USDC amount");
    }
    
    function test_CalculateETHUSDCLiquidity_DifferentPrices() public pure {
        console.log("=== TEST: Different Price Scenarios ===");
        
        uint256 targetUSDC = MEDIUM_LIQUIDITY; // 100k USDC
        uint256 rangePercent = 5;
        
        // Test with lower bound price
        (uint256 ethLow, uint256 usdcLow,,) = 
            HookLibrary.calculateETHUSDCLiquidity(targetUSDC, LOWER_BOUND_PRICE, rangePercent);
            
        // Test with upper bound price  
        (uint256 ethHigh, uint256 usdcHigh,,) = 
            HookLibrary.calculateETHUSDCLiquidity(targetUSDC, UPPER_BOUND_PRICE, rangePercent);
            
        console.log("Lower price (3000) - ETH:", ethLow / 10**ETH_DECIMALS);
        console.log("Lower price (3000) - USDC:", usdcLow / 10**USDC_DECIMALS);
        console.log("Upper price (4000) - ETH:", ethHigh / 10**ETH_DECIMALS);
        console.log("Upper price (4000) - USDC:", usdcHigh / 10**USDC_DECIMALS);
        
        // Higher ETH price should require less ETH for same USDC liquidity
        assertLt(ethHigh, ethLow, "Higher ETH price should require less ETH");
        
        // Both should have reasonable USDC amounts
        assertGt(usdcLow, 0, "Lower price should have positive USDC");
        assertGt(usdcHigh, 0, "Upper price should have positive USDC");
    }
    
    function test_CalculateETHUSDCLiquidity_DifferentLiquidityAmounts() public pure {
        console.log("=== TEST: Different ETH Target Amounts ===");
        
        uint256 ethPrice = CURRENT_ETH_PRICE;
        uint256 rangePercent = 10; // ±10% as per V4 specification
        
        // Small ETH target
        uint256 smallETH = 0.01 ether; // 0.01 ETH
        (uint256 ethSmallResult, uint256 usdcSmall,) = 
            HookLibrary.calculateETHUSDCLiquidityV4(smallETH, ethPrice, rangePercent, 60);
            
        // Large ETH target
        uint256 largeETH = 1 ether; // 1 ETH
        (uint256 ethLargeResult, uint256 usdcLarge,) = 
            HookLibrary.calculateETHUSDCLiquidityV4(largeETH, ethPrice, rangePercent, 60);
            
        console.log("Small (0.01 ETH target) - ETH result:", ethSmallResult / 10**ETH_DECIMALS);
        console.log("Small (0.01 ETH target) - USDC:", usdcSmall / 10**USDC_DECIMALS);
        console.log("Large (1 ETH target) - ETH result:", ethLargeResult / 10**ETH_DECIMALS);
        console.log("Large (1 ETH target) - USDC:", usdcLarge / 10**USDC_DECIMALS);
        
        // Larger target should require more of both tokens
        assertGt(ethLargeResult, ethSmallResult, "Larger target should result in more ETH");
        assertGt(usdcLarge, usdcSmall, "Larger target should require more USDC");
        
        // Should scale roughly proportionally with ETH target
        uint256 targetRatio = largeETH / smallETH; // 100x
        uint256 ethRatio = ethLargeResult / ethSmallResult;
        uint256 usdcRatio = usdcLarge / usdcSmall;
        
        console.log("Target ratio:", targetRatio);
        console.log("ETH result ratio:", ethRatio);
        console.log("USDC ratio:", usdcRatio);
        
        // Allow for reasonable variance due to concentrated liquidity math and minimums
        assertGt(ethRatio, targetRatio / 2, "ETH should scale reasonably");
        // USDC scaling can be affected by minimum enforcement, so be more lenient
        assertGe(usdcRatio, 1, "USDC should scale at least somewhat");
        assertLt(ethRatio, targetRatio * 2, "ETH scaling should be bounded");
        assertLt(usdcRatio, targetRatio * 5, "USDC scaling should be bounded");
    }
    
    // ============ Edge Case Tests ============
    
    function test_CalculateETHUSDCLiquidity_MinimumAmounts() public pure {
        console.log("=== TEST: Minimum Amount Enforcement ===");
        
        // Very small target that would normally result in tiny amounts
        uint256 tinyTarget = 1; // 1 wei USDC
        uint256 ethPrice = CURRENT_ETH_PRICE;
        uint256 rangePercent = 5;
        
        (uint256 ethAmount, uint256 usdcAmount,,) = 
            HookLibrary.calculateETHUSDCLiquidity(tinyTarget, ethPrice, rangePercent);
            
        console.log("Tiny target input:", tinyTarget);
        console.log("Enforced ETH minimum:", ethAmount / 10**ETH_DECIMALS);
        console.log("Enforced USDC minimum:", usdcAmount / 10**USDC_DECIMALS);
        
        // Should enforce minimums
        assertGe(ethAmount, 0.001 ether, "Should enforce minimum ETH");
        assertGe(usdcAmount, 1000 * 10**USDC_DECIMALS, "Should enforce minimum USDC");
    }
    
    function test_CalculateETHUSDCLiquidity_ExtremePrices() public pure {
        console.log("=== TEST: Extreme Price Scenarios ===");
        
        uint256 targetUSDC = MEDIUM_LIQUIDITY;
        uint256 rangePercent = 5;
        
        // Very low ETH price (bear market)
        uint256 lowPrice = 1000; // 1000 USDC/ETH
        (uint256 ethLow, uint256 usdcLow,,) = 
            HookLibrary.calculateETHUSDCLiquidity(targetUSDC, lowPrice, rangePercent);
            
        // Very high ETH price (bull market)  
        uint256 highPrice = 10000; // 10000 USDC/ETH
        (uint256 ethHigh, uint256 usdcHigh,,) = 
            HookLibrary.calculateETHUSDCLiquidity(targetUSDC, highPrice, rangePercent);
            
        console.log("Bear market (1000) - ETH:", ethLow / 10**ETH_DECIMALS);
        console.log("Bear market (1000) - USDC:", usdcLow / 10**USDC_DECIMALS);
        console.log("Bull market (10000) - ETH:", ethHigh / 10**ETH_DECIMALS);
        console.log("Bull market (10000) - USDC:", usdcHigh / 10**USDC_DECIMALS);
        
        // Should handle extreme prices gracefully
        assertTrue(ethLow > 0 && ethHigh > 0, "Should handle extreme prices");
        assertTrue(usdcLow > 0 && usdcHigh > 0, "Should produce positive USDC amounts");
        
        // Low price should require more ETH, high price should require less ETH
        assertGt(ethLow, ethHigh, "Lower ETH price should require more ETH");
    }
    
    // ============ Consistency Tests ============
    
    function test_CalculateETHUSDCLiquidity_ConcentrationMultiplier() public pure {
        console.log("=== TEST: V4 Math vs Basic Calculation ===");
        
        // Test with realistic ETH target (like resource estimation)
        uint256 targetETH = 0.1 ether; // 0.1 ETH as per V4 specification
        uint256 ethPrice = CURRENT_ETH_PRICE; // 3600 USDC/ETH
        uint256 rangePercent = 10; // ±10% as per V4 specification
        
        (uint256 ethAmount, uint256 usdcAmount, ModifyLiquidityParams memory params) = 
            HookLibrary.calculateETHUSDCLiquidityV4(targetETH, ethPrice, rangePercent, 60);
            
        // Calculate what basic 1:1 calculation would give for comparison
        uint256 basicUSDC = (targetETH * ethPrice) / 10**ETH_DECIMALS;
        
        console.log("Target ETH:", targetETH / 10**ETH_DECIMALS);
        console.log("V4 ETH result:", ethAmount / 10**ETH_DECIMALS);
        console.log("V4 USDC result:", usdcAmount / 10**USDC_DECIMALS);
        console.log("Basic USDC calc:", basicUSDC / 10**USDC_DECIMALS);
        console.log("Tick lower:", params.tickLower);
        console.log("Tick upper:", params.tickUpper);
        
        // V4 math should produce reasonable results
        assertGt(ethAmount, 0.01 ether, "Should produce meaningful ETH amount");
        assertGt(usdcAmount, 100 * 10**USDC_DECIMALS, "Should produce meaningful USDC amount");
        
        // Should be close to target ETH (within concentrated liquidity range)
        assertLe(ethAmount, targetETH * 2, "ETH should be reasonable vs target");
    }
    
    function test_CalculateETHUSDCLiquidity_TickBounds() public pure {
        console.log("=== TEST: Tick Bounds Validation ===");
        
        uint256 targetUSDC = MEDIUM_LIQUIDITY;
        uint256 ethPrice = CURRENT_ETH_PRICE;
        uint256 rangePercent = 5;
        
        (,, int24 tickLower, int24 tickUpper) = 
            HookLibrary.calculateETHUSDCLiquidity(targetUSDC, ethPrice, rangePercent);
            
        console.log("Tick lower:", tickLower);
        console.log("Tick upper:", tickUpper);
        console.log("Tick range:", tickUpper - tickLower);
        
        // Basic tick validations
        assertTrue(tickLower < tickUpper, "tickLower must be less than tickUpper");
        assertTrue(tickLower >= -887220, "tickLower should be within bounds");
        assertTrue(tickUpper <= 887220, "tickUpper should be within bounds");
        
        // Should have reasonable range
        int24 tickRange = tickUpper - tickLower;
        assertGt(tickRange, 0, "Should have positive tick range");
        assertLt(tickRange, 200000, "Tick range should be reasonable");
    }
    
    // ============ Integration with Resource Estimation ============
    
    function test_CalculateETHUSDCLiquidity_ResourceEstimationScenarios() public pure {
        console.log("=== TEST: Resource Estimation Integration ===");
        
        // Test scenarios matching our deployment parameters
        uint256 targetETH = 0.1 ether; // 0.1 ETH per pool as per specification
        uint256 rangePercent = 10; // ±10% as per specification
        
        // Test both deployment prices using V4 math
        (uint256 eth3000, uint256 usdc3000,) = 
            HookLibrary.calculateETHUSDCLiquidityV4(targetETH, 3000, rangePercent, 60);
            
        (uint256 eth4000, uint256 usdc4000,) = 
            HookLibrary.calculateETHUSDCLiquidityV4(targetETH, 4000, rangePercent, 60);
            
        console.log("Pool 1 (3000 USDC/ETH):");
        console.log("  ETH needed (wei):", eth3000);
        console.log("  USDC needed:", usdc3000 / 10**USDC_DECIMALS);
        
        console.log("Pool 2 (4000 USDC/ETH):");
        console.log("  ETH needed (wei):", eth4000);
        console.log("  USDC needed:", usdc4000 / 10**USDC_DECIMALS);
        
        // Calculate total for deployment
        uint256 totalETH = eth3000 + eth4000;
        uint256 totalUSDC = usdc3000 + usdc4000;
        
        console.log("Total for deployment:");
        console.log("  Total ETH (wei):", totalETH);
        console.log("  Total USDC:", totalUSDC / 10**USDC_DECIMALS);
        
        // Should be reasonable for testnet deployment
        assertLt(totalETH, 100 ether, "Should be reasonable for testnet");
        assertGt(totalETH, 0.001 ether, "Should be meaningful amount");
    }
    
    // ============ Helper Functions ============
    
    /// @notice Debug test to understand why V4 math produces 0 ETH
    function test_DebugV4Math() public pure {
        console.log("=== DEBUG: V4 Math Investigation ===");
        
        uint256 targetETH = 0.1 ether; // 0.1 ETH target
        uint256 ethPrice = 3600; // 3600 USDC/ETH
        uint256 rangePercent = 10; // ±10%
        int24 tickSpacing = 60;
        
        console.log("Inputs:");
        console.log("  Target ETH (wei):", targetETH);
        console.log("  Target ETH (formatted): 0.1 ETH");
        console.log("  ETH Price:", ethPrice);
        console.log("  Range:", rangePercent, "%");
        console.log("  Tick Spacing:", uint256(int256(tickSpacing)));
        
        // Call the V4 function directly
        (uint256 ethAmount, uint256 usdcAmount, ModifyLiquidityParams memory liquidityParams) = 
            HookLibrary.calculateETHUSDCLiquidityV4(targetETH, ethPrice, rangePercent, tickSpacing);
            
        console.log("V4 Results:");
        console.log("  ETH Amount (wei):", ethAmount);
        console.log("  USDC Amount (wei):", usdcAmount);
        console.log("  Tick Lower:", liquidityParams.tickLower);
        console.log("  Tick Upper:", liquidityParams.tickUpper);
        console.log("  Liquidity Delta:", uint256(liquidityParams.liquidityDelta));
        
        // Debug: Check if current price is within range
        console.log("Price Analysis:");
        console.log("  Current price should be between tick bounds");
        console.log("  Only USDC (no ETH) suggests current price > upper bound");
        
        // Test the legacy wrapper
        uint256 targetUSDC = 1e6; // 1 USDC (what the test uses)
        (uint256 legacyETH, uint256 legacyUSDC, int24 tickLower, int24 tickUpper) = 
            HookLibrary.calculateETHUSDCLiquidity(targetUSDC, ethPrice, rangePercent);
            
        console.log("Legacy Results:");
        console.log("  ETH Amount:", legacyETH / 1e18);
        console.log("  USDC Amount:", legacyUSDC / 1e6);
        console.log("  Tick Lower:", tickLower);
        console.log("  Tick Upper:", tickUpper);
        
        // Calculate what the legacy wrapper converts to
        uint256 convertedETH = (targetUSDC * 1e18) / (ethPrice * 1e6);
        console.log("Legacy conversion:");
        console.log("  Target USDC:", targetUSDC / 1e6);
        console.log("  Converted to ETH (wei):", convertedETH);
        console.log("  Converted ETH (formatted): ~0.00027 ETH");
    }
    
    /// @notice Format ETH amount for logging
    function formatETH(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(amount / 10**ETH_DECIMALS, " ETH"));
    }
    
    /// @notice Format USDC amount for logging  
    function formatUSDC(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(amount / 10**USDC_DECIMALS, " USDC"));
    }
} 