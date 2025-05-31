// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PythStructs } from "../libraries/PythLibrary.sol";

/**
 * @title ArbitrageLib
 * @notice Library for arbitrage opportunity calculations and price normalization
 * @dev Contains pure functions extracted from DetoxHook for better modularity and testing
 */
library ArbitrageLib {
    // Constants
    uint256 internal constant PRICE_PRECISION = 1e8; // 8 decimal precision like USDC
    uint256 internal constant BASIS_POINTS = 10000; // 100% in basis points

    /**
     * @notice Parameters for arbitrage calculation
     * @param poolPrice Pool price (currency1/currency0) with PRICE_PRECISION
     * @param inputPrice Input currency price in USD with PRICE_PRECISION
     * @param outputPrice Output currency price in USD with PRICE_PRECISION
     * @param inputPriceConf Input currency price confidence with PRICE_PRECISION
     * @param outputPriceConf Output currency price confidence with PRICE_PRECISION
     * @param exactInputAmount The exact input amount for the swap
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
     * @param arbitrageOpportunity The total arbitrage opportunity amount (confidence-adjusted)
     * @param shouldInterfere Whether the opportunity exceeds the threshold and confidence bounds
     * @param hookShare The amount the hook should capture (based on rhoBps)
     * @param isOutsideConfidenceBand Whether pool price is outside oracle confidence band
     */
    struct ArbitrageResult {
        uint256 arbitrageOpportunity;
        bool shouldInterfere;
        uint256 hookShare;
        bool isOutsideConfidenceBand;
    }

    /**
     * @notice Calculate arbitrage opportunity based on price differences with confidence adjustment
     * @param params The arbitrage calculation parameters
     * @return arbitrageOpp Arbitrage opportunity in input currency units (confidence-adjusted)
     */
    function calculateArbitrageOpportunity(ArbitrageParams memory params) internal pure returns (uint256) {
        if (params.exactInputAmount == 0 || params.inputPrice == 0 || params.outputPrice == 0) {
            return 0;
        }

        // Calculate market price bounds with confidence
        (uint256 marketPriceLower, uint256 marketPriceUpper) = calculateMarketPriceBounds(
            params.outputPrice,
            params.inputPrice,
            params.outputPriceConf,
            params.inputPriceConf
        );

        if (params.zeroForOne) {
            // Case 1: zeroForOne = true (currency0 → currency1)
            // Use upper bound for conservative arbitrage calculation
            if (params.poolPrice <= marketPriceUpper) return 0;

            uint256 priceDiff = params.poolPrice - marketPriceUpper;
            return FullMath.mulDiv(params.exactInputAmount, priceDiff, PRICE_PRECISION);
        } else {
            // Case 2: zeroForOne = false (currency1 → currency0)
            // Use lower bound for conservative arbitrage calculation
            if (params.poolPrice >= marketPriceLower) return 0;

            uint256 priceDiff = marketPriceLower - params.poolPrice;
            return FullMath.mulDiv(params.exactInputAmount, priceDiff, PRICE_PRECISION);
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

        // Calculate market price bounds with confidence
        (uint256 marketPriceLower, uint256 marketPriceUpper) = calculateMarketPriceBounds(
            params.outputPrice,
            params.inputPrice,
            params.outputPriceConf,
            params.inputPriceConf
        );

        // Check if pool price is outside the confidence band
        return params.poolPrice < marketPriceLower || params.poolPrice > marketPriceUpper;
    }

    /**
     * @notice Calculate market price bounds with confidence intervals
     * @param outputPrice Output currency price in USD with PRICE_PRECISION
     * @param inputPrice Input currency price in USD with PRICE_PRECISION
     * @param outputPriceConf Output currency price confidence with PRICE_PRECISION
     * @param inputPriceConf Input currency price confidence with PRICE_PRECISION
     * @return lower Lower bound of market price
     * @return upper Upper bound of market price
     */
    function calculateMarketPriceBounds(
        uint256 outputPrice,
        uint256 inputPrice,
        uint256 outputPriceConf,
        uint256 inputPriceConf
    ) internal pure returns (uint256 lower, uint256 upper) {
        if (inputPrice == 0) return (0, 0);

        // Calculate bounds for output/input ratio
        // Lower bound: (outputPrice - outputConf) / (inputPrice + inputConf)
        // Upper bound: (outputPrice + outputConf) / (inputPrice - inputConf)
        
        uint256 outputLower = outputPrice > outputPriceConf ? outputPrice - outputPriceConf : 0;
        uint256 outputUpper = outputPrice + outputPriceConf;
        uint256 inputLower = inputPrice > inputPriceConf ? inputPrice - inputPriceConf : 1; // Avoid division by zero
        uint256 inputUpper = inputPrice + inputPriceConf;

        lower = FullMath.mulDiv(outputLower, PRICE_PRECISION, inputUpper);
        upper = FullMath.mulDiv(outputUpper, PRICE_PRECISION, inputLower);
    }

    /**
     * @notice Check if we should interfere based on confidence bounds and advantage to swapper
     * @param params The arbitrage calculation parameters
     * @return shouldInterfere Whether the hook should interfere
     */
    function shouldInterfere(ArbitrageParams memory params) internal pure returns (bool) {
        // First check if we're outside confidence band
        if (!isOutsideConfidenceBand(params)) return false;

        // Calculate market price (without confidence adjustment for this check)
        uint256 marketPrice = calculateMarketPrice(params.outputPrice, params.inputPrice);
        if (marketPrice == 0) return false;

        // Check if arbitrage is advantageous for the swapper
        if (params.zeroForOne) {
            // zeroForOne: selling currency0 for currency1
            // Advantageous if pool gives better rate than market (poolPrice > marketPrice)
            return params.poolPrice > marketPrice;
        } else {
            // oneForZero: selling currency1 for currency0  
            // Advantageous if pool gives better rate than market (poolPrice < marketPrice)
            return params.poolPrice < marketPrice;
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
     * @notice Comprehensive arbitrage analysis with simplified logic
     * @param params The arbitrage calculation parameters
     * @param rhoBps The hook's share percentage in basis points
     * @return result Complete arbitrage analysis result
     */
    function analyzeArbitrageOpportunity(
        ArbitrageParams memory params,
        uint256 rhoBps
    ) internal pure returns (ArbitrageResult memory result) {
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
    }

    /**
     * @notice Normalize Pyth price to PRICE_PRECISION format
     * @param pythPrice The Pyth price struct
     * @return normalizedPrice Price normalized to 8 decimals
     */
    function normalizePythPrice(PythStructs.Price memory pythPrice) internal pure returns (uint256) {
        if (pythPrice.price <= 0) return 0;

        uint256 price = uint256(uint64(pythPrice.price));
        int32 exponent = pythPrice.expo;

        // Convert to PRICE_PRECISION (8 decimals)
        if (exponent >= -8) {
            // If exponent is -8 or higher, multiply
            uint256 multiplier = 10 ** uint256(int256(exponent + 8));
            return price * multiplier;
        } else {
            // If exponent is lower than -8, divide
            uint256 divisor = 10 ** uint256(int256(-8 - exponent));
            return price / divisor;
        }
    }

    /**
     * @notice Normalize Pyth confidence to PRICE_PRECISION format
     * @param pythPrice The Pyth price struct
     * @return normalizedConf Confidence normalized to 8 decimals
     */
    function normalizePythConfidence(PythStructs.Price memory pythPrice) internal pure returns (uint256) {
        if (pythPrice.conf == 0) return 0;

        uint256 conf = uint256(pythPrice.conf);
        int32 exponent = pythPrice.expo;

        // Convert to PRICE_PRECISION (8 decimals) using same logic as price
        if (exponent >= -8) {
            // If exponent is -8 or higher, multiply
            uint256 multiplier = 10 ** uint256(int256(exponent + 8));
            return conf * multiplier;
        } else {
            // If exponent is lower than -8, divide
            uint256 divisor = 10 ** uint256(int256(-8 - exponent));
            return conf / divisor;
        }
    }

    /**
     * @notice Calculate market price ratio from two USD prices (without confidence)
     * @param outputPriceUSD Output currency price in USD with PRICE_PRECISION
     * @param inputPriceUSD Input currency price in USD with PRICE_PRECISION
     * @return marketPrice Market price as output/input ratio with PRICE_PRECISION
     */
    function calculateMarketPrice(
        uint256 outputPriceUSD,
        uint256 inputPriceUSD
    ) internal pure returns (uint256) {
        if (inputPriceUSD == 0) return 0;
        return FullMath.mulDiv(outputPriceUSD, PRICE_PRECISION, inputPriceUSD);
    }

    /**
     * @notice Validate arbitrage parameters
     * @param params The arbitrage parameters to validate
     * @return isValid Whether all parameters are valid
     */
    function validateArbitrageParams(ArbitrageParams memory params) internal pure returns (bool) {
        return params.poolPrice > 0 &&
               params.inputPrice > 0 &&
               params.outputPrice > 0 &&
               params.exactInputAmount > 0;
    }

    /**
     * @notice Calculate percentage difference between pool and market price
     * @param poolPrice Pool price with PRICE_PRECISION
     * @param marketPrice Market price with PRICE_PRECISION
     * @return percentageDiff Percentage difference in basis points
     */
    function calculatePriceDifferencePercentage(
        uint256 poolPrice,
        uint256 marketPrice
    ) internal pure returns (uint256) {
        if (poolPrice == 0 || marketPrice == 0) return 0;
        
        uint256 diff = poolPrice > marketPrice ? 
            poolPrice - marketPrice : 
            marketPrice - poolPrice;
            
        return FullMath.mulDiv(diff, BASIS_POINTS, marketPrice);
    }
} 