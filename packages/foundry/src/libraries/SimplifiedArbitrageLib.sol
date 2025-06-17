// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SimplifiedArbitrageLib
 * @notice Ultra-simplified arbitrage calculation library
 * @dev Single function approach: returns 0 for no arbitrage, >0 for arbitrage amount
 */
library SimplifiedArbitrageLib {
    /// @notice Precision for calculations (1e18)
    uint256 internal constant PRECISION = 1e18;
    
    /// @notice Basis points for percentage calculations
    uint256 internal constant BASIS_POINTS = 10000;

    /**
     * @notice Calculate arbitrage amount if opportunity exists
     * @dev This is the ONLY function needed - combines detection and calculation
     * @param poolPrice Pool price ratio (price1/price0) with PRECISION
     * @param oracleLowerBound Oracle lower bound with PRECISION  
     * @param oracleUpperBound Oracle upper bound with PRECISION
     * @param swapAmount Amount being swapped (input token units)
     * @param zeroForOne Swap direction (true = currency0 → currency1)
     * @return arbitrageAmount Amount of arbitrage (0 = no arbitrage, >0 = arbitrage exists)
     */
    function calculateArbitrageAmount(
        uint256 poolPrice,
        uint256 oracleLowerBound,
        uint256 oracleUpperBound, 
        uint256 swapAmount,
        bool zeroForOne
    ) internal pure returns (uint256 arbitrageAmount) {
        // Input validation
        if (swapAmount == 0 || poolPrice == 0 || oracleLowerBound == 0 || oracleUpperBound == 0) {
            return 0;
        }

        // Ensure bounds are properly ordered
        if (oracleUpperBound <= oracleLowerBound) {
            return 0;
        }

        if (zeroForOne) {
            // Selling currency0 for currency1 (e.g., ETH → USDC)
            // Arbitrage exists if pool gives too much currency1 (pool overpaying)
            // Pool overpaying when: poolPrice > oracleUpperBound
            if (poolPrice > oracleUpperBound) {
                // arbitrageAmount = swapAmount * (poolPrice - oracleUpperBound) / poolPrice
                uint256 priceDifference = poolPrice - oracleUpperBound;
                arbitrageAmount = (swapAmount * priceDifference) / poolPrice;
            }
            // else: poolPrice <= oracleUpperBound → no arbitrage → return 0
        } else {
            // Selling currency1 for currency0 (e.g., USDC → ETH)  
            // Arbitrage exists if pool gives too little currency0 (pool underpaying)
            // Pool underpaying when: poolPrice < oracleLowerBound
            if (poolPrice < oracleLowerBound) {
                // arbitrageAmount = swapAmount * (oracleLowerBound - poolPrice) / oracleLowerBound
                uint256 priceDifference = oracleLowerBound - poolPrice;
                arbitrageAmount = (swapAmount * priceDifference) / oracleLowerBound;
            }
            // else: poolPrice >= oracleLowerBound → no arbitrage → return 0
        }

        // No explicit return needed - arbitrageAmount defaults to 0 if no conditions met
    }

    /**
     * @notice Calculate hook's share of arbitrage opportunity
     * @param arbitrageAmount The total arbitrage opportunity
     * @param rhoBps The hook's share percentage in basis points (e.g., 8000 = 80%)
     * @return hookShare The amount the hook should capture
     */
    function calculateHookShare(uint256 arbitrageAmount, uint256 rhoBps) internal pure returns (uint256) {
        if (arbitrageAmount == 0 || rhoBps == 0) {
            return 0;
        }
        
        // Ensure rhoBps is reasonable (max 100%)
        if (rhoBps > BASIS_POINTS) {
            rhoBps = BASIS_POINTS;
        }
        
        return (arbitrageAmount * rhoBps) / BASIS_POINTS;
    }

    /**
     * @notice Validate arbitrage calculation parameters
     * @param poolPrice Pool price ratio
     * @param oracleLowerBound Oracle lower bound
     * @param oracleUpperBound Oracle upper bound
     * @param swapAmount Swap amount
     * @return isValid Whether parameters are valid for calculation
     */
    function validateParameters(
        uint256 poolPrice,
        uint256 oracleLowerBound,
        uint256 oracleUpperBound,
        uint256 swapAmount
    ) internal pure returns (bool isValid) {
        return poolPrice > 0 && 
               oracleLowerBound > 0 && 
               oracleUpperBound > 0 &&
               oracleUpperBound > oracleLowerBound &&
               swapAmount > 0;
    }

    /**
     * @notice Get the precision constant for external use
     * @return The precision constant (1e18)
     */
    function getPrecision() internal pure returns (uint256) {
        return PRECISION;
    }

    /**
     * @notice Get the basis points constant for external use  
     * @return The basis points constant (10000)
     */
    function getBasisPoints() internal pure returns (uint256) {
        return BASIS_POINTS;
    }
} 