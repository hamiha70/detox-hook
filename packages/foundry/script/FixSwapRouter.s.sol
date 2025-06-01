// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @title FixSwapRouter
/// @notice Script to calculate proper price limits for SwapRouter
contract FixSwapRouter is Script {
    
    function run() external view {
        console.log("=== TickMath Price Limit Analysis ===");
        
        uint160 minSqrtPrice = TickMath.MIN_SQRT_PRICE;
        uint160 maxSqrtPrice = TickMath.MAX_SQRT_PRICE;
        
        console.log("TickMath.MIN_SQRT_PRICE:");
        console.log(minSqrtPrice);
        console.log("TickMath.MAX_SQRT_PRICE:");
        console.log(maxSqrtPrice);
        console.log("MIN_SQRT_PRICE + 1:");
        console.log(minSqrtPrice + 1);
        console.log("MAX_SQRT_PRICE - 1:");
        console.log(maxSqrtPrice - 1);
        
        console.log("=== Current SwapRouter Hardcoded Values ===");
        console.log("Current zeroForOne limit:");
        console.log(4295128739);
        
        console.log("=== Comparison ===");
        console.log("MIN_SQRT_PRICE + 1 vs hardcoded min:");
        console.log("Proper:");
        console.log(minSqrtPrice + 1);
        console.log("Current:");
        console.log(4295128739);
        console.log("Match:");
        console.log((minSqrtPrice + 1) == 4295128739);
    }
} 