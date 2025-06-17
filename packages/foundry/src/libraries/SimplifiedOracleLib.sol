// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPyth, PythStructs } from "./PythLibrary.sol";

/**
 * @title SimplifiedOracleLib
 * @notice Simplified Pyth oracle integration with confidence bounds
 * @dev Single precision system (1e18) with proper exponent normalization for all Pyth feeds
 */
library SimplifiedOracleLib {
    /// @notice Target precision for all calculations (18 decimals)
    uint256 internal constant PRECISION = 1e18;
    
    /// @notice Maximum reasonable exponent to prevent overflow (covers all Pyth feeds)
    int32 internal constant MAX_EXPO = 18;
    int32 internal constant MIN_EXPO = -18;

    // ============ Core Oracle Functions ============

    /**
     * @notice Get oracle price with confidence bounds in single precision system
     * @param oracle The Pyth oracle instance
     * @param priceId The Pyth price ID
     * @param stalenessThreshold Maximum age in seconds
     * @return price Normalized price with PRECISION (1e18)
     * @return lowerBound Price minus confidence with PRECISION
     * @return upperBound Price plus confidence with PRECISION  
     * @return valid Whether the price is valid and fresh
     */
    function getPriceWithBounds(
        IPyth oracle,
        bytes32 priceId,
        uint256 stalenessThreshold
    ) internal view returns (
        uint256 price,
        uint256 lowerBound,
        uint256 upperBound,
        bool valid
    ) {
        if (address(oracle) == address(0) || priceId == bytes32(0)) {
            return (0, 0, 0, false);
        }

        // Get Pyth price safely
        (PythStructs.Price memory pythPrice, bool success) = _safePythCall(oracle, priceId);
        if (!success) return (0, 0, 0, false);

        // Validate freshness and price value
        valid = _isPriceValid(pythPrice, stalenessThreshold);
        if (!valid) return (0, 0, 0, false);

        // Normalize to PRECISION (1e18) regardless of exponent
        price = _normalizeToTargetPrecision(uint256(uint64(pythPrice.price)), pythPrice.expo);
        uint256 confidence = _normalizeToTargetPrecision(pythPrice.conf, pythPrice.expo);

        // Calculate bounds with safety checks to ensure positivity
        lowerBound = price > confidence ? price - confidence : 1; // Minimum 1 wei to avoid zero
        upperBound = price + confidence;

        // Final validation: ensure bounds are positive and properly ordered
        require(lowerBound > 0 && upperBound > 0 && upperBound > lowerBound, "Invalid price bounds");
    }

    /**
     * @notice Get fresh oracle price with confidence bounds (state-changing for real Pyth)
     * @param oracle The Pyth oracle instance
     * @param priceId The Pyth price ID
     * @param stalenessThreshold Maximum age in seconds
     * @param priceUpdate The price update data (empty for mocks)
     * @return price Normalized price with PRECISION
     * @return lowerBound Price minus confidence with PRECISION
     * @return upperBound Price plus confidence with PRECISION
     * @return valid Whether the price is valid and fresh
     */
    function getFreshPriceWithBounds(
        IPyth oracle,
        bytes32 priceId,
        uint256 stalenessThreshold,
        bytes[] memory priceUpdate
    ) internal returns (
        uint256 price,
        uint256 lowerBound,
        uint256 upperBound,
        bool valid
    ) {
        if (address(oracle) == address(0) || priceId == bytes32(0)) {
            return (0, 0, 0, false);
        }

        // For real Pyth, update price feeds first if update data provided
        if (priceUpdate.length > 0) {
            uint256 fee = oracle.getUpdateFee(priceUpdate);
            if (fee > 0) {
                oracle.updatePriceFeeds{value: fee}(priceUpdate);
            }
            
            // Use getPriceNoOlderThan for fresh data
            try oracle.getPriceNoOlderThan(priceId, stalenessThreshold) returns (PythStructs.Price memory pythPrice) {
                valid = _isPriceValid(pythPrice, stalenessThreshold);
                if (!valid) return (0, 0, 0, false);
                
                price = _normalizeToTargetPrecision(uint256(uint64(pythPrice.price)), pythPrice.expo);
                uint256 confidence = _normalizeToTargetPrecision(pythPrice.conf, pythPrice.expo);
                
                lowerBound = price > confidence ? price - confidence : 1;
                upperBound = price + confidence;
                
                require(lowerBound > 0 && upperBound > 0 && upperBound > lowerBound, "Invalid price bounds");
                return (price, lowerBound, upperBound, true);
            } catch {
                return (0, 0, 0, false);
            }
        } else {
            // Fallback to unsafe call for mocks or when no update data
            return getPriceWithBounds(oracle, priceId, stalenessThreshold);
        }
    }

    // ============ Price Ratio Calculation ============

    /**
     * @notice Calculate price ratio bounds between two currencies
     * @dev Implements: (price1 ± conf1) / (price0 ± conf0) with proper exponent handling
     * @param oracle The Pyth oracle instance
     * @param priceId0 Price ID for currency0 (denominator)  
     * @param priceId1 Price ID for currency1 (numerator)
     * @param stalenessThreshold Maximum age in seconds
     * @return lowerBound Lower bound of price1/price0 ratio with PRECISION
     * @return upperBound Upper bound of price1/price0 ratio with PRECISION
     * @return valid Whether both prices are valid
     */
    function calculatePriceRatioBounds(
        IPyth oracle,
        bytes32 priceId0,
        bytes32 priceId1,
        uint256 stalenessThreshold
    ) internal view returns (uint256 lowerBound, uint256 upperBound, bool valid) {
        // Get both prices with bounds
        (, uint256 lower0, uint256 upper0, bool valid0) = 
            getPriceWithBounds(oracle, priceId0, stalenessThreshold);
        (, uint256 lower1, uint256 upper1, bool valid1) = 
            getPriceWithBounds(oracle, priceId1, stalenessThreshold);

        if (!valid0 || !valid1) {
            return (0, 0, false);
        }

        // Calculate ratio bounds: (price1 ± conf1) / (price0 ± conf0)
        // Lower bound: (price1 - conf1) / (price0 + conf0)  
        // Upper bound: (price1 + conf1) / (price0 - conf0)
        lowerBound = (lower1 * PRECISION) / upper0;
        upperBound = (upper1 * PRECISION) / lower0;

        // Validation
        require(lowerBound > 0 && upperBound > 0 && upperBound > lowerBound, "Invalid ratio bounds");
        valid = true;
    }

    // ============ Normalization Functions ============

    /**
     * @notice Normalize Pyth value to target precision (1e18) regardless of exponent
     * @dev Handles all Pyth exponent variations (-18 to +18)
     * @param value The raw value from Pyth
     * @param expo The exponent from Pyth (can be positive or negative)
     * @return normalized The value normalized to PRECISION (1e18)
     */
    function _normalizeToTargetPrecision(uint256 value, int32 expo) internal pure returns (uint256 normalized) {
        if (value == 0) return 0;
        
        // Validate exponent is reasonable
        require(expo >= MIN_EXPO && expo <= MAX_EXPO, "Exponent out of range");

        if (expo == -18) {
            // Already at target precision
            return value;
        } else if (expo > -18) {
            // Need to scale up (multiply)
            uint32 scaleUp = uint32(18 + expo);
            require(scaleUp <= 36, "Scale factor too large"); // Prevent overflow
            normalized = value * (10 ** scaleUp);
        } else {
            // expo < -18: Need to scale down (divide)
            uint32 scaleDown = uint32(-18 - expo);
            require(scaleDown <= 36, "Scale factor too large");
            normalized = value / (10 ** scaleDown);
        }

        // Sanity check: ensure no overflow occurred
        require(normalized >= value || expo > -18, "Normalization overflow");
    }

    /**
     * @notice Alternative normalization function for clarity (equivalent to above)
     * @dev More explicit about the mathematical transformation
     */
    function _normalizeValue(uint256 value, int32 expo) internal pure returns (uint256) {
        if (value == 0) return 0;

        // Target: Convert to 1e18 precision
        // Pyth value represents: value * 10^expo
        // We want: (value * 10^expo) * 10^18 / 10^0 = value * 10^(expo + 18)

        int32 targetExpo = expo + 18; // Exponent adjustment needed

        if (targetExpo == 0) {
            return value; // Already normalized
        } else if (targetExpo > 0) {
            // Multiply by 10^targetExpo
            require(targetExpo <= 36, "Exponent too large");
            return value * (10 ** uint32(targetExpo));
        } else {
            // Divide by 10^(-targetExpo)
            require(targetExpo >= -36, "Exponent too small");
            return value / (10 ** uint32(-targetExpo));
        }
    }

    // ============ Validation Functions ============

    /**
     * @notice Check if Pyth price is valid and fresh
     * @param pythPrice The Pyth price struct
     * @param stalenessThreshold Maximum age in seconds
     * @return Whether the price is valid and fresh
     */
    function _isPriceValid(PythStructs.Price memory pythPrice, uint256 stalenessThreshold) 
        internal view returns (bool) {
        // Check if price is positive
        if (pythPrice.price <= 0) return false;

        // Check staleness
        if (block.timestamp > pythPrice.publishTime + stalenessThreshold) return false;

        // Check exponent is reasonable
        if (pythPrice.expo < MIN_EXPO || pythPrice.expo > MAX_EXPO) return false;

        return true;
    }

    /**
     * @notice Safely call Pyth oracle with error handling
     * @param oracle The Pyth oracle instance
     * @param priceId The price ID to query
     * @return pythPrice The price struct (zero if failed)
     * @return success Whether the call succeeded
     */
    function _safePythCall(IPyth oracle, bytes32 priceId) 
        internal view returns (PythStructs.Price memory pythPrice, bool success) {
        try oracle.getPriceUnsafe(priceId) returns (PythStructs.Price memory price) {
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

    // ============ Utility Functions ============

    /**
     * @notice Get publish time for a price ID
     * @param oracle The Pyth oracle instance
     * @param priceId The price ID to query
     * @return publishTime The timestamp when the price was published (0 if failed)
     */
    function getPublishTime(IPyth oracle, bytes32 priceId) internal view returns (uint256 publishTime) {
        (PythStructs.Price memory pythPrice, bool success) = _safePythCall(oracle, priceId);
        return success ? pythPrice.publishTime : 0;
    }

    /**
     * @notice Check if oracle is available and configured
     * @param oracle The Pyth oracle instance
     * @param priceId The price ID to check
     * @return Whether the oracle is properly configured
     */
    function isOracleConfigured(IPyth oracle, bytes32 priceId) internal pure returns (bool) {
        return address(oracle) != address(0) && priceId != bytes32(0);
    }

    /**
     * @notice Get the target precision constant for external use
     * @return The precision constant (1e18)
     */
    function getPrecision() internal pure returns (uint256) {
        return PRECISION;
    }
} 