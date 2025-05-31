// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPyth, PythStructs } from "./PythLibrary.sol";

/// @title OracleLib
/// @notice Library for Pyth oracle price fetching, normalization, and validation
/// @dev Handles all oracle interactions including error handling and price normalization
library OracleLib {
    // Constants
    uint256 private constant PRICE_PRECISION = 1e8; // 8 decimal precision like USDC

    // ============ Core Oracle Functions ============

    /**
     * @notice Get oracle price with confidence for a currency
     * @param pythOracle The Pyth oracle instance
     * @param priceId The Pyth price ID for the currency
     * @param stalenessThreshold Maximum age in seconds
     * @return price Normalized price (PRICE_PRECISION format)
     * @return confidence Normalized confidence (PRICE_PRECISION format)
     * @return valid Whether the price is valid and fresh
     */
    function getOraclePriceWithConfidence(
        IPyth pythOracle,
        bytes32 priceId,
        uint256 stalenessThreshold
    ) internal view returns (uint256 price, uint256 confidence, bool valid) {
        if (address(pythOracle) == address(0) || priceId == bytes32(0)) {
            return (0, 0, false);
        }

        (PythStructs.Price memory pythPrice, bool success) = safePythCall(pythOracle, priceId);
        if (!success) return (0, 0, false);

        valid = isPriceValid(pythPrice, stalenessThreshold);
        if (!valid) return (0, 0, false);

        price = normalizePythPrice(pythPrice);
        confidence = normalizePythConfidence(pythPrice);
        
        return (price, confidence, true);
    }

    /**
     * @notice Get oracle price without confidence
     * @param pythOracle The Pyth oracle instance
     * @param priceId The Pyth price ID for the currency
     * @param stalenessThreshold Maximum age in seconds
     * @return price Normalized price (PRICE_PRECISION format)
     * @return valid Whether the price is valid and fresh
     */
    function getOraclePrice(
        IPyth pythOracle,
        bytes32 priceId,
        uint256 stalenessThreshold
    ) internal view returns (uint256 price, bool valid) {
        (price, , valid) = getOraclePriceWithConfidence(pythOracle, priceId, stalenessThreshold);
    }

    // ============ Normalization Functions ============

    /**
     * @notice Normalize Pyth price to PRICE_PRECISION format
     * @param pythPrice The raw Pyth price struct
     * @return Normalized price with 8 decimal precision
     */
    function normalizePythPrice(PythStructs.Price memory pythPrice) internal pure returns (uint256) {
        if (pythPrice.price <= 0) return 0;
        return _normalizeValue(uint256(uint64(pythPrice.price)), pythPrice.expo);
    }

    /**
     * @notice Normalize Pyth confidence to PRICE_PRECISION format
     * @param pythPrice The raw Pyth price struct
     * @return Normalized confidence with 8 decimal precision
     */
    function normalizePythConfidence(PythStructs.Price memory pythPrice) internal pure returns (uint256) {
        return _normalizeValue(pythPrice.conf, pythPrice.expo);
    }

    /**
     * @notice Internal function to normalize any value with given exponent to 8 decimal places
     * @param value The raw value to normalize
     * @param expo The exponent (power of 10)
     * @return Normalized value with 8 decimal precision
     */
    function _normalizeValue(uint256 value, int32 expo) internal pure returns (uint256) {
        if (value == 0) return 0;
        
        // Target is -8 (8 decimal places)
        if (expo == -8) {
            return value;
        } else if (expo > -8) {
            // Need more decimal places, multiply
            uint256 multiplier;
            if (expo >= 0) {
                // expo is positive, multiply by 10^(expo + 8)
                multiplier = 10 ** (uint256(uint32(expo)) + 8);
            } else {
                // expo is negative but > -8
                // Examples: expo = -2, -3, -4, -5, -6, -7
                if (expo == -7) multiplier = 10 ** 1;
                else if (expo == -6) multiplier = 10 ** 2;
                else if (expo == -5) multiplier = 10 ** 3;
                else if (expo == -4) multiplier = 10 ** 4;
                else if (expo == -3) multiplier = 10 ** 5;
                else if (expo == -2) multiplier = 10 ** 6;
                else if (expo == -1) multiplier = 10 ** 7;
                else if (expo == 0) multiplier = 10 ** 8;
                else multiplier = 1; // Fallback
            }
            return value * multiplier;
        } else {
            // expo < -8, need fewer decimal places, divide
            uint256 divisor;
            if (expo == -9) divisor = 10 ** 1;
            else if (expo == -10) divisor = 10 ** 2;
            else if (expo == -11) divisor = 10 ** 3;
            else if (expo == -12) divisor = 10 ** 4;
            else if (expo == -13) divisor = 10 ** 5;
            else if (expo == -14) divisor = 10 ** 6;
            else if (expo == -15) divisor = 10 ** 7;
            else if (expo == -16) divisor = 10 ** 8;
            else if (expo == -17) divisor = 10 ** 9;
            else if (expo == -18) divisor = 10 ** 10;
            else divisor = 1; // Fallback for extreme values
            return value / divisor;
        }
    }

    // ============ Validation Functions ============

    /**
     * @notice Check if Pyth price is valid and fresh
     * @param pythPrice The Pyth price struct
     * @param stalenessThreshold Maximum age in seconds
     * @return Whether the price is valid and fresh
     */
    function isPriceValid(PythStructs.Price memory pythPrice, uint256 stalenessThreshold) internal view returns (bool) {
        // Check if price is positive
        if (pythPrice.price <= 0) return false;

        // Check staleness
        if (block.timestamp > pythPrice.publishTime + stalenessThreshold) return false;

        return true;
    }

    /**
     * @notice Safely get Pyth price with error handling
     * @param pythOracle The Pyth oracle instance
     * @param priceId The price ID to query
     * @return pythPrice The price struct (zero if failed)
     * @return success Whether the call succeeded
     */
    function safePythCall(IPyth pythOracle, bytes32 priceId) internal view returns (PythStructs.Price memory pythPrice, bool success) {
        try pythOracle.getPriceUnsafe(priceId) returns (PythStructs.Price memory price) {
            return (price, true);
        } catch {
            // Return zero price struct if call fails
            return (PythStructs.Price({
                price: 0,
                conf: 0,
                expo: 0,
                publishTime: 0
            }), false);
        }
    }

    // ============ Helper Functions ============

    /**
     * @notice Get publish time for a price ID
     * @param pythOracle The Pyth oracle instance
     * @param priceId The price ID to query
     * @return publishTime The timestamp when the price was published (0 if failed)
     */
    function getPublishTime(IPyth pythOracle, bytes32 priceId) internal view returns (uint256 publishTime) {
        (PythStructs.Price memory pythPrice, bool success) = safePythCall(pythOracle, priceId);
        return success ? pythPrice.publishTime : 0;
    }

    /**
     * @notice Check if oracle is available and configured
     * @param pythOracle The Pyth oracle instance
     * @param priceId The price ID to check
     * @return Whether the oracle is properly configured
     */
    function isOracleConfigured(IPyth pythOracle, bytes32 priceId) internal pure returns (bool) {
        return address(pythOracle) != address(0) && priceId != bytes32(0);
    }
} 