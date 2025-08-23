// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {PoolStateReader} from "../src/PoolStateReader.sol";

/**
 * @title TestPoolStateReader
 * @notice Script to test the PoolStateReader contract
 */
contract TestPoolStateReader is Script {
    address constant POOL_MANAGER = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;

    function run() external {
        console.log("=== Testing PoolStateReader ===");

        // Create the PoolStateReader (simulate deployment)
        PoolStateReader reader = new PoolStateReader(POOL_MANAGER);

        console.log("PoolStateReader created at:", address(reader));

        // Test Pool 1
        console.log("\n--- Testing DetoxHook Pool 1 ---");
        (
            uint160 sqrtPriceX96_1,
            int24 tick_1,
            uint24 protocolFee_1,
            uint24 lpFee_1,
            uint128 liquidity_1,
            bool success_1
        ) = reader.getDetoxPool1State();

        if (success_1) {
            console.log("[SUCCESS] Pool 1 State:");
            console.log("  sqrtPriceX96:", sqrtPriceX96_1);
            console.log("  tick:", uint256(int256(tick_1)));
            console.log("  protocolFee:", protocolFee_1);
            console.log("  lpFee:", lpFee_1);
            console.log("  liquidity:", liquidity_1);
        } else {
            console.log("[ERROR] Failed to get Pool 1 state");
        }

        // Test Pool 2
        console.log("\n--- Testing DetoxHook Pool 2 ---");
        (
            uint160 sqrtPriceX96_2,
            int24 tick_2,
            uint24 protocolFee_2,
            uint24 lpFee_2,
            uint128 liquidity_2,
            bool success_2
        ) = reader.getDetoxPool2State();

        if (success_2) {
            console.log("[SUCCESS] Pool 2 State:");
            console.log("  sqrtPriceX96:", sqrtPriceX96_2);
            console.log("  tick:", uint256(int256(tick_2)));
            console.log("  protocolFee:", protocolFee_2);
            console.log("  lpFee:", lpFee_2);
            console.log("  liquidity:", liquidity_2);
        } else {
            console.log("[ERROR] Failed to get Pool 2 state");
        }

        // Test pool IDs
        console.log("\n--- Testing Pool ID Generation ---");
        (bytes32 pool1Id, bytes32 pool2Id) = reader.getDetoxPoolIds();
        console.log("Pool 1 ID:");
        console.logBytes32(pool1Id);
        console.log("Pool 2 ID:");
        console.logBytes32(pool2Id);
    }
}
