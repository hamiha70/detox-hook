// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PythLibrary
 * @notice Minimal Pyth oracle interfaces and structs for DetoxHook
 * @dev This replaces the full Pyth SDK dependency with just what we need
 */

library PythStructs {
    struct Price {
        // Price value with a given precision
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent (power of 10)
        int32 expo;
        // Unix timestamp when the price was published
        uint256 publishTime;
    }
}

/**
 * @title IPyth
 * @notice Minimal Pyth oracle interface
 */
interface IPyth {
    /**
     * @notice Returns the price and confidence interval for the given price feed id.
     * @dev This function returns the price without any safety checks.
     * @param id The price feed id
     * @return price The price data
     */
    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256);
    function getUpdateFee(uint256 updateDataSize) external view returns (uint256);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
    function getPriceNoOlderThan(bytes32 id, uint age) external view returns (PythStructs.Price memory);
} 