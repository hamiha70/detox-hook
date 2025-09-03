// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract TestTickMath is Script {
    function run() external {
        console.log("=== TickMath Test ===");

        // Test different ticks to find the correct sqrt price
        int24[] memory ticks = new int24[](5);
        ticks[0] = 0;
        ticks[1] = 60;
        ticks[2] = 120;
        ticks[3] = -60;
        ticks[4] = -120;

        for (uint i = 0; i < ticks.length; i++) {
            int24 tick = ticks[i];
            uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(tick);
            console.log("Tick:", vm.toString(tick));
            console.log("SqrtPriceX96:", sqrtPrice);
            console.log("---");
        }

        // Test our current value
        console.log("Our current value: 79228162514264337593543950336");
        console.log("TickMath tick 0:  ", TickMath.getSqrtPriceAtTick(0));
        console.log(
            "Match:",
            TickMath.getSqrtPriceAtTick(0) == 79228162514264337593543950336
        );
    }
}
