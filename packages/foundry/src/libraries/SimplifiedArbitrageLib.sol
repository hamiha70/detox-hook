// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SimplifiedArbitrageLib
 * @notice Simplified arbitrage library for unit testing
 * @dev Contains isolated arbitrage detection logic without complex integrations
 */
library SimplifiedArbitrageLib {
    /// @notice Precision for calculations (1e18)
    uint256 internal constant PRECISION = 1e18;
    
    /// @notice Basis points for percentage calculations
    uint256 internal constant BASIS_POINTS = 10000;

    /**
     * @notice Calculate arbitrage amount based on pool vs oracle price comparison
     * @param poolPrice Pool price (same units as oracle bounds)
     * @param oracleLower Oracle lower bound price
     * @param oracleUpper Oracle upper bound price
     * @param swapAmount Amount being swapped (input currency units)
     * @param zeroForOne Swap direction (true = currency0->currency1, false = currency1->currency0)
     * @return arbitrageAmount Amount of arbitrage opportunity in input currency units
     */
    function calculateArbitrageAmount(
        uint256 poolPrice,
        uint256 oracleLower,
        uint256 oracleUpper,
        uint256 swapAmount,
        bool zeroForOne
    ) internal pure returns (uint256) {
        // Validate inputs
        if (!validateParameters(poolPrice, oracleLower, oracleUpper, swapAmount)) {
            return 0;
        }

        // Check for arbitrage opportunities in both directions
        if (zeroForOne) {
            // zeroForOne: selling currency0 for currency1 (e.g., ETH -> USDC)
            if (poolPrice > oracleUpper) {
                // Pool overpaying: poolPrice > market upper bound
                // arbitrageAmount = swapAmount * (poolPrice - oracleUpper) / poolPrice
                return (swapAmount * (poolPrice - oracleUpper)) / poolPrice;
            } else if (poolPrice < oracleLower) {
                // Pool underpricing: poolPrice < market lower bound  
                // arbitrageAmount = swapAmount * (oracleLower - poolPrice) / oracleLower
                return (swapAmount * (oracleLower - poolPrice)) / oracleLower;
            }
        } else {
            // oneForZero: selling currency1 for currency0 (e.g., USDC -> ETH)
            if (poolPrice < oracleLower) {
                // Pool underpricing: poolPrice < market lower bound
                // arbitrageAmount = swapAmount * (oracleLower - poolPrice) / oracleLower
                return (swapAmount * (oracleLower - poolPrice)) / oracleLower;
            } else if (poolPrice > oracleUpper) {
                // Pool overpaying: poolPrice > market upper bound
                // arbitrageAmount = swapAmount * (poolPrice - oracleUpper) / poolPrice
                return (swapAmount * (poolPrice - oracleUpper)) / poolPrice;
            }
        }

        return 0; // No arbitrage opportunity
    }

    /**
     * @notice Calculate hook's share of arbitrage opportunity
     * @param arbitrageAmount Total arbitrage opportunity
     * @param rhoBps Hook share percentage in basis points
     * @return hookShare Amount hook should capture
     */
    function calculateHookShare(uint256 arbitrageAmount, uint256 rhoBps) internal pure returns (uint256) {
        if (arbitrageAmount == 0 || rhoBps == 0) {
            return 0;
        }
        return (arbitrageAmount * rhoBps) / BASIS_POINTS;
    }

    /**
     * @notice Validate arbitrage calculation parameters
     * @param poolPrice Pool price (must be > 0)
     * @param oracleLower Oracle lower bound (must be > 0)
     * @param oracleUpper Oracle upper bound (must be >= oracleLower)
     * @param swapAmount Swap amount (must be > 0)
     * @return isValid Whether parameters are valid
     */
    function validateParameters(
        uint256 poolPrice,
        uint256 oracleLower,
        uint256 oracleUpper,
        uint256 swapAmount
    ) internal pure returns (bool) {
        return poolPrice > 0 && 
               oracleLower > 0 && 
               oracleUpper >= oracleLower && 
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