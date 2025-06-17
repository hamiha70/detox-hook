// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { console } from "forge-std/console.sol";

/**
 * @title ArbitrageLib
 * @notice Library for arbitrage opportunity calculations with high precision
 * @dev Uses 18-decimal precision throughout for maximum accuracy in arbitrage detection
 */
library ArbitrageLib {
    // ============ Constants ============
    
    /// @notice Arbitrage calculations use 18 decimal precision for maximum accuracy
    uint256 internal constant ARBITRAGE_PRECISION = 1e18;
    
    /// @notice Legacy price precision for backward compatibility
    uint256 internal constant PRICE_PRECISION = 1e8;
    
    /// @notice Basis points for percentage calculations
    uint256 internal constant BASIS_POINTS = 10000;

    // ============ Public Getters for Tests ============
    
    /// @notice Get the arbitrage precision constant for external use
    function getArbitragePrecision() internal pure returns (uint256) {
        return ARBITRAGE_PRECISION;
    }

    // ============ Structs ============

    /**
     * @notice Parameters for arbitrage calculation
     * @param poolPrice Pool price ratio with ARBITRAGE_PRECISION (18 decimals)
     * @param inputPrice Input currency price in USD with ARBITRAGE_PRECISION
     * @param outputPrice Output currency price in USD with ARBITRAGE_PRECISION
     * @param inputPriceConf Input currency price confidence with ARBITRAGE_PRECISION
     * @param outputPriceConf Output currency price confidence with ARBITRAGE_PRECISION
     * @param exactInputAmount The exact input amount for the swap in token decimals
     * @param zeroForOne The swap direction (true = currency0 → currency1)
     */
    struct ArbitrageParams {
        uint256 poolPrice;
        uint256 inputPrice;
        uint256 outputPrice;
        uint256 inputPriceConf;
        uint256 outputPriceConf;
        uint256 exactInputAmount;
        bool zeroForOne;
    }

    /**
     * @notice Result of arbitrage calculation
     * @param arbitrageOpportunity The total arbitrage opportunity amount in input token decimals
     * @param shouldInterfere Whether the hook should interfere with the swap
     * @param hookShare The amount the hook should capture in input token decimals
     * @param isOutsideConfidenceBand Whether pool price is outside oracle confidence band
     */
    struct ArbitrageResult {
        uint256 arbitrageOpportunity;
        bool shouldInterfere;
        uint256 hookShare;
        bool isOutsideConfidenceBand;
    }

    // ============ Market Price Calculation ============

    /**
     * @notice Calculate market price ratio from USD prices with proper precision and token decimals
     * @dev For USDC/ETH pool: marketPrice = ETH_USD / USDC_USD * (10^(ETH_decimals - USDC_decimals))
     * @param inputCurrencyUSD Input currency price in USD (ARBITRAGE_PRECISION)
     * @param outputCurrencyUSD Output currency price in USD (ARBITRAGE_PRECISION) 
     * @param inputDecimals Input token decimals (e.g., 18 for ETH)
     * @param outputDecimals Output token decimals (e.g., 6 for USDC)
     * @return marketPrice Market price ratio with ARBITRAGE_PRECISION
     */
    function calculateMarketPriceRatio(
        uint256 inputCurrencyUSD,
        uint256 outputCurrencyUSD,
        uint8 inputDecimals,
        uint8 outputDecimals
    ) internal pure returns (uint256 marketPrice) {
        if (outputCurrencyUSD == 0) return 0;
        
        // Simple price ratio calculation: input_USD / output_USD  
        // Both inputs are already in ARBITRAGE_PRECISION, result should be too
        marketPrice = FullMath.mulDiv(inputCurrencyUSD, ARBITRAGE_PRECISION, outputCurrencyUSD);
        
        console.log("[ARB] calculateMarketPriceRatio:");
        console.log("inputCurrencyUSD:", inputCurrencyUSD / 1e15); // Show in thousands for readability
        console.log("outputCurrencyUSD:", outputCurrencyUSD / 1e15);
        console.log("marketPrice:", marketPrice / 1e15);
        
        return marketPrice;
    }

    /**
     * @notice Calculate market price bounds with confidence intervals
     * @param inputCurrencyUSD Input currency USD price (ARBITRAGE_PRECISION)
     * @param outputCurrencyUSD Output currency USD price (ARBITRAGE_PRECISION)
     * @param inputCurrencyConf Input currency confidence (ARBITRAGE_PRECISION)
     * @param outputCurrencyConf Output currency confidence (ARBITRAGE_PRECISION)
     * @param inputDecimals Input token decimals
     * @param outputDecimals Output token decimals
     * @return lower Lower bound of market price ratio
     * @return upper Upper bound of market price ratio
     */
    function calculateMarketPriceBounds(
        uint256 inputCurrencyUSD,
        uint256 outputCurrencyUSD,
        uint256 inputCurrencyConf,
        uint256 outputCurrencyConf,
        uint8 inputDecimals,
        uint8 outputDecimals
    ) internal pure returns (uint256 lower, uint256 upper) {
        console.log("[ARB:ENTRY] calculateMarketPriceBounds");
        console.log("inputCurrencyUSD:", inputCurrencyUSD / 1e15);
        console.log("outputCurrencyUSD:", outputCurrencyUSD / 1e15);
        console.log("inputCurrencyConf:", inputCurrencyConf / 1e15);
        console.log("outputCurrencyConf:", outputCurrencyConf / 1e15);
        
        if (outputCurrencyUSD == 0) {
            console.log("[ARB:DEFENSE] outputCurrencyUSD is zero, returning (0,0)");
            return (0, 0);
        }

        // Calculate bounds for input/output ratio with confidence
        // Lower bound: (inputPrice - inputConf) / (outputPrice + outputConf)
        // Upper bound: (inputPrice + inputConf) / (outputPrice - outputConf)
        
        uint256 inputLower = inputCurrencyUSD > inputCurrencyConf ? inputCurrencyUSD - inputCurrencyConf : 0;
        uint256 inputUpper = inputCurrencyUSD + inputCurrencyConf;
        uint256 outputLower = outputCurrencyUSD > outputCurrencyConf ? outputCurrencyUSD - outputCurrencyConf : 1; // Avoid division by zero
        uint256 outputUpper = outputCurrencyUSD + outputCurrencyConf;
        
        if (outputLower == 0 || outputUpper == 0) {
            console.log("[ARB:DEFENSE] output bounds invalid, returning (0,0)");
            return (0, 0);
        }
        
        console.log("[ARB] inputLower:", inputLower / 1e15);
        console.log("[ARB] inputUpper:", inputUpper / 1e15);
        console.log("[ARB] outputLower:", outputLower / 1e15);
        console.log("[ARB] outputUpper:", outputUpper / 1e15);
        
        // Calculate price bounds: input/output ratio with ARBITRAGE_PRECISION
        lower = FullMath.mulDiv(inputLower, ARBITRAGE_PRECISION, outputUpper);
        upper = FullMath.mulDiv(inputUpper, ARBITRAGE_PRECISION, outputLower);
        
        console.log("[ARB] lower:", lower / 1e15);
        console.log("[ARB] upper:", upper / 1e15);
    }

    // ============ Arbitrage Opportunity Calculation ============

    /**
     * @notice Calculate arbitrage opportunity based on price differences with confidence adjustment
     * @param params The arbitrage calculation parameters
     * @return arbitrageOpp Arbitrage opportunity in input currency units
     */
    function calculateArbitrageOpportunity(ArbitrageParams memory params) internal pure returns (uint256) {
        console.log("[ARB:ENTRY] calculateArbitrageOpportunity");
        console.log("exactInputAmount:", params.exactInputAmount);
        console.log("poolPrice:", params.poolPrice / 1e15);
        console.log("zeroForOne:", params.zeroForOne);
        
        if (params.exactInputAmount == 0) {
            console.log("[ARB:DEFENSE] exactInputAmount is zero, returning 0");
            return 0;
        }

        // For simplified calculation, assume ETH (18 decimals) and USDC (6 decimals)
        // This should be parameterized in a real implementation
        uint8 inputDecimals = params.zeroForOne ? 18 : 6;  // ETH : USDC
        uint8 outputDecimals = params.zeroForOne ? 6 : 18; // USDC : ETH
        
        (uint256 marketPriceLower, uint256 marketPriceUpper) = calculateMarketPriceBounds(
            params.inputPrice,
            params.outputPrice,
            params.inputPriceConf,
            params.outputPriceConf,
            inputDecimals,
            outputDecimals
        );

        if (params.zeroForOne) {
            // zeroForOne: selling currency0 (ETH) for currency1 (USDC)
            // Arbitrage exists if pool price > market upper bound
            console.log("[ARB:CHECK] poolPrice:", params.poolPrice / 1e15);
            console.log("[ARB:CHECK] marketPriceUpper:", marketPriceUpper / 1e15);
            
            if (params.poolPrice <= marketPriceUpper) {
                console.log("[ARB:DEFENSE] poolPrice <= marketPriceUpper, no arbitrage");
                return 0;
            }
            
            uint256 priceDiff = params.poolPrice - marketPriceUpper;
            console.log("[ARB] priceDiff (zeroForOne):", priceDiff / 1e15);
            
            // arbitrageOpp = exactInputAmount * (poolPrice - marketPriceUpper) / poolPrice
            return FullMath.mulDiv(params.exactInputAmount, priceDiff, params.poolPrice);
        } else {
            // oneForZero: selling currency1 (USDC) for currency0 (ETH)
            // Arbitrage exists if pool price < market lower bound
            console.log("[ARB:CHECK] poolPrice:", params.poolPrice / 1e15);
            console.log("[ARB:CHECK] marketPriceLower:", marketPriceLower / 1e15);
            
            if (params.poolPrice >= marketPriceLower) {
                console.log("[ARB:DEFENSE] poolPrice >= marketPriceLower, no arbitrage");
                return 0;
            }
            
            uint256 priceDiff = marketPriceLower - params.poolPrice;
            console.log("[ARB] priceDiff (oneForZero):", priceDiff / 1e15);
            
            // arbitrageOpp = exactInputAmount * (marketPriceLower - poolPrice) / marketPriceLower
            return FullMath.mulDiv(params.exactInputAmount, priceDiff, marketPriceLower);
        }
    }

    /**
     * @notice Check if pool price is outside oracle confidence band
     * @param params The arbitrage calculation parameters
     * @return isOutside Whether pool price is outside confidence bounds
     */
    function isOutsideConfidenceBand(ArbitrageParams memory params) internal pure returns (bool) {
        if (params.inputPrice == 0 || params.outputPrice == 0) return false;

        // If both confidence values are zero, there's no confidence band - always return true
        if (params.inputPriceConf == 0 && params.outputPriceConf == 0) return true;

        // For simplified calculation, assume ETH (18 decimals) and USDC (6 decimals)
        uint8 inputDecimals = params.zeroForOne ? 18 : 6;
        uint8 outputDecimals = params.zeroForOne ? 6 : 18;

        // Calculate market price bounds with confidence
        (uint256 marketPriceLower, uint256 marketPriceUpper) = calculateMarketPriceBounds(
            params.inputPrice,
            params.outputPrice,
            params.inputPriceConf,
            params.outputPriceConf,
            inputDecimals,
            outputDecimals
        );

        // Check if pool price is outside the confidence band
        return params.poolPrice < marketPriceLower || params.poolPrice > marketPriceUpper;
    }

    /**
     * @notice Check if we should interfere based on confidence bounds and advantage to swapper
     * @param params The arbitrage calculation parameters
     * @return shouldInterfere Whether the hook should interfere
     */
    function shouldInterfere(ArbitrageParams memory params) internal pure returns (bool) {
        // First check if we're outside confidence band
        if (!isOutsideConfidenceBand(params)) return false;

        // Use the same logic as calculateArbitrageOpportunity for consistency
        uint8 inputDecimals = params.zeroForOne ? 18 : 6;
        uint8 outputDecimals = params.zeroForOne ? 6 : 18;
        
        (uint256 marketPriceLower, uint256 marketPriceUpper) = calculateMarketPriceBounds(
            params.inputPrice,
            params.outputPrice,
            params.inputPriceConf,
            params.outputPriceConf,
            inputDecimals,
            outputDecimals
        );

        // Use the same arbitrage detection logic as calculateArbitrageOpportunity
        if (params.zeroForOne) {
            // zeroForOne: selling currency0 for currency1
            // Arbitrage exists if pool price > market upper bound
            return params.poolPrice > marketPriceUpper;
        } else {
            // oneForZero: selling currency1 for currency0  
            // Arbitrage exists if pool price < market lower bound
            return params.poolPrice < marketPriceLower;
        }
    }

    /**
     * @notice Calculate hook's share of arbitrage opportunity
     * @param arbitrageOpp The total arbitrage opportunity
     * @param rhoBps The hook's share percentage in basis points
     * @return hookShare The amount the hook should capture
     */
    function calculateHookShare(uint256 arbitrageOpp, uint256 rhoBps) internal pure returns (uint256) {
        if (arbitrageOpp == 0 || rhoBps == 0) return 0;
        return FullMath.mulDiv(arbitrageOpp, rhoBps, BASIS_POINTS);
    }

    /**
     * @notice Comprehensive arbitrage analysis with precision preservation
     * @param params The arbitrage calculation parameters
     * @param rhoBps The hook's share percentage in basis points
     * @return result Complete arbitrage analysis result
     */
    function analyzeArbitrageOpportunity(
        ArbitrageParams memory params,
        uint256 rhoBps
    ) internal pure returns (ArbitrageResult memory result) {
        console.log("[ARB] analyzeArbitrageOpportunity: poolPrice");
        console.logUint(params.poolPrice);
        console.log("[ARB] inputPrice");
        console.logUint(params.inputPrice);
        console.log("[ARB] outputPrice");
        console.logUint(params.outputPrice);
        console.log("[ARB] inputPriceConf");
        console.logUint(params.inputPriceConf);
        console.log("[ARB] outputPriceConf");
        console.logUint(params.outputPriceConf);
        console.log("[ARB] exactInputAmount");
        console.logUint(params.exactInputAmount);
        console.log("[ARB] zeroForOne");
        console.logBool(params.zeroForOne);
        console.log("[ARB] rhoBps");
        console.logUint(rhoBps);
        
        // Check if pool price is outside confidence band
        result.isOutsideConfidenceBand = isOutsideConfidenceBand(params);
        
        // Check if we should interfere (simplified logic)
        result.shouldInterfere = shouldInterfere(params);
        
        // Calculate arbitrage opportunity with confidence adjustment
        result.arbitrageOpportunity = calculateArbitrageOpportunity(params);
        
        // Calculate hook share if we're interfering
        if (result.shouldInterfere) {
            result.hookShare = calculateHookShare(result.arbitrageOpportunity, rhoBps);
        }
        
        console.log("[ARB] ArbitrageResult.arbitrageOpportunity");
        console.logUint(result.arbitrageOpportunity);
        console.log("[ARB] ArbitrageResult.shouldInterfere");
        console.logBool(result.shouldInterfere);
        console.log("[ARB] ArbitrageResult.hookShare");
        console.logUint(result.hookShare);
        console.log("[ARB] ArbitrageResult.isOutsideConfidenceBand");
        console.logBool(result.isOutsideConfidenceBand);
    }

    // ============ Legacy Functions (Backward Compatibility) ============

    /**
     * @notice Calculate market price bounds (legacy interface)
     * @dev Converts from legacy 8-decimal to 18-decimal precision
     */
    function calculateMarketPriceBounds(
        uint256 outputPrice,
        uint256 inputPrice,
        uint256 outputPriceConf,
        uint256 inputPriceConf
    ) internal pure returns (uint256 lower, uint256 upper) {
        // Convert from 8-decimal to 18-decimal precision
        uint256 inputPrice18 = FullMath.mulDiv(inputPrice, ARBITRAGE_PRECISION, PRICE_PRECISION);
        uint256 outputPrice18 = FullMath.mulDiv(outputPrice, ARBITRAGE_PRECISION, PRICE_PRECISION);
        uint256 inputConf18 = FullMath.mulDiv(inputPriceConf, ARBITRAGE_PRECISION, PRICE_PRECISION);
        uint256 outputConf18 = FullMath.mulDiv(outputPriceConf, ARBITRAGE_PRECISION, PRICE_PRECISION);
        
        (uint256 lower18, uint256 upper18) = calculateMarketPriceBounds(
            inputPrice18,      // inputCurrencyUSD
            outputPrice18,     // outputCurrencyUSD
            inputConf18,       // inputCurrencyConf
            outputConf18,      // outputCurrencyConf
            18,                // inputDecimals (assume ETH)
            6                  // outputDecimals (assume USDC)
        );
        
        // Convert back to 8-decimal precision for compatibility
        lower = FullMath.mulDiv(lower18, PRICE_PRECISION, ARBITRAGE_PRECISION);
        upper = FullMath.mulDiv(upper18, PRICE_PRECISION, ARBITRAGE_PRECISION);
    }

    /**
     * @notice Calculate market price ratio (legacy interface)
     */
    function calculateMarketPrice(
        uint256 outputPriceUSD,
        uint256 inputPriceUSD
    ) internal pure returns (uint256) {
        // Convert from 8-decimal to 18-decimal precision
        uint256 inputPrice18 = FullMath.mulDiv(inputPriceUSD, ARBITRAGE_PRECISION, PRICE_PRECISION);
        uint256 outputPrice18 = FullMath.mulDiv(outputPriceUSD, ARBITRAGE_PRECISION, PRICE_PRECISION);
        
        uint256 result18 = calculateMarketPriceRatio(
            inputPrice18,   // inputCurrencyUSD
            outputPrice18,  // outputCurrencyUSD
            18,             // inputDecimals (assume ETH)
            6               // outputDecimals (assume USDC)
        );
        
        // Convert back to 8-decimal precision for compatibility
        return FullMath.mulDiv(result18, PRICE_PRECISION, ARBITRAGE_PRECISION);
    }

    /**
     * @notice Validate arbitrage parameters
     * @param params The parameters to validate
     * @return isValid Whether parameters are valid
     */
    function validateArbitrageParams(ArbitrageParams memory params) internal pure returns (bool) {
        return params.inputPrice > 0 && 
               params.outputPrice > 0 && 
               params.exactInputAmount > 0 &&
               params.poolPrice > 0;
    }
} 