// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {HookLibrary} from "../../src/libraries/HookLibrary.sol";
import {ChainAddresses} from "../Utility/ChainAddresses.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/**
 * @title GetPoolState
 * @notice Script to read actual pool state using StateLibrary
 */
contract GetPoolState is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager constant POOL_MANAGER =
        IPoolManager(0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317);

    function run() external view {
        console.log("=== Pool State Reader ===");
        console.log("PoolManager:", address(POOL_MANAGER));

        // Real DetoxHook Pool 1: ETH/USDC 0.3% fee
        PoolKey memory pool1 = _getDetoxPool1Key();
        _displayPoolState("Pool 1", pool1);

        // Real DetoxHook Pool 2: ETH/USDC 0.05% fee
        PoolKey memory pool2 = _getDetoxPool2Key();
        _displayPoolState("Pool 2", pool2);

        // // Real DetoxHook Pool 3: ETH/MockUSDC 0.05% fee
        PoolKey memory pool3 = _getDetoxPool3Key();
        _displayPoolState("Pool 3", pool3);
    }

    function _displayPoolState(
        string memory poolName,
        PoolKey memory poolKey
    ) internal view {
        console.log("\n--- %s ---", poolName);

        PoolId poolId = poolKey.toId();
        console.log("Pool ID:");
        console.logBytes32(PoolId.unwrap(poolId));

        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity
        ) = HookLibrary.getPoolState(POOL_MANAGER, poolKey);

        console.log("[SUCCESS] Pool State Retrieved:");
        console.log("  sqrtPriceX96:", sqrtPriceX96);
        console.log("  Current Tick:", int24(tick));
        console.log("  Tick Status:", _getTickStatus(tick));
        console.log("  Protocol Fee:", protocolFee);
        console.log("  LP Fee:", lpFee);
        console.log("  Liquidity:", liquidity);

        // Check for zero liquidity condition with helpful context
        // if (liquidity == 0) {
        //     console.log("  [WARNING] Pool has ZERO liquidity!");
        //     console.log(
        //         "  [INFO] No swaps possible - pool needs liquidity first"
        //     );
        //     console.log(
        //         "  [INFO] Price data below shows theoretical price if liquidity existed"
        //     );
        // } else {
        //     console.log(
        //         "  [INFO] Pool has active liquidity - swaps should work"
        //     );
        // }

        // Calculate human-readable price with enhanced safety checks
        // if (sqrtPriceX96 > 0) {
        //     // Wrap in try-catch for maximum safety
        //     try this._calculateAndDisplayPrice(sqrtPriceX96) {
        //         // Success - price displayed in external function
        //     } catch Error(string memory reason) {
        //         console.log("  [ERROR] Price calculation failed:", reason);
        //         console.log(
        //             "  [INFO] Raw sqrtPriceX96 value is available above"
        //         );
        //     } catch (bytes memory) {
        //         console.log(
        //             "  [ERROR] Price calculation failed with low-level error"
        //         );
        //         console.log(
        //             "  [INFO] Raw sqrtPriceX96 value is available above"
        //         );
        //     }
        // } else {
        //     console.log(
        //         "  [ERROR] Invalid sqrtPriceX96 (zero) - pool not initialized"
        //     );
        // }
    }

    /// @notice External function to safely calculate and display price information
    /// @dev Using external function allows try-catch for error handling
    function _calculateAndDisplayPrice(uint160 sqrtPriceX96) external pure {
        uint256 humanPrice = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
        console.log("  Human Price (USDC/ETH):", humanPrice);

        // Enhanced safety checks for rate calculation
        if (humanPrice == 0) {
            console.log("  ETH/USDC Rate: [ZERO_PRICE - Invalid state]");
        } else if (humanPrice > 1e35) {
            console.log(
                "  ETH/USDC Rate: [EXTREME_HIGH_PRICE - Cannot calculate safely]"
            );
            console.log(
                "  Price indicates MockUSDC is extremely expensive vs ETH"
            );
        } else if (humanPrice < 1e6) {
            console.log(
                "  ETH/USDC Rate: [EXTREME_LOW_PRICE - Cannot calculate safely]"
            );
            console.log("  Price indicates MockUSDC is extremely cheap vs ETH");
        } else {
            // Safe to calculate rate
            uint256 ethUsdcRate = 1e36 / humanPrice;
            console.log("  ETH/USDC Rate:", ethUsdcRate);

            // Add helpful context for understanding the price
            if (ethUsdcRate > 5000e18) {
                console.log(
                    "  [INFO] ETH is very expensive relative to MockUSDC"
                );
            } else if (ethUsdcRate < 1000e18) {
                console.log("  [INFO] ETH is very cheap relative to MockUSDC");
            } else {
                console.log("  [INFO] ETH/MockUSDC price in reasonable range");
            }
        }
    }

    function _getTickStatus(int24 tick) internal pure returns (string memory) {
        if (tick == type(int24).max) {
            return "INVALID_TICK";
        } else if (tick == type(int24).min) {
            return "INVALID_TICK";
        } else if (tick < 0) {
            return "NEGATIVE_TICK";
        } else {
            return "POSITIVE_TICK";
        }
    }

    function _getDetoxPool1Key() internal pure returns (PoolKey memory) {
        return
            PoolKey({
                currency0: Currency.wrap(
                    0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E
                ), // USDC
                currency1: Currency.wrap(
                    0x9D5A68fDFEcc14683324640D5e835936422a47b1
                ), // USDC
                fee: 2000, // 0.3%
                tickSpacing: 40,
                hooks: IHooks(address(0)) // DetoxHook
            });
    }

    function _getDetoxPool2Key() internal pure returns (PoolKey memory) {
        return
            PoolKey({
                currency0: Currency.wrap(
                    0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E
                ), // USDC
                currency1: Currency.wrap(
                    0x9D5A68fDFEcc14683324640D5e835936422a47b1
                ), // USDC
                fee: 2000,
                tickSpacing: 40,
                hooks: IHooks(0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088) // DetoxHook
            });
    }

    function _getDetoxPool3Key() internal pure returns (PoolKey memory) {
        return
            PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(
                    0x9D5A68fDFEcc14683324640D5e835936422a47b1
                ),
                fee: 300,
                tickSpacing: 40,
                hooks: IHooks(0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088) // DetoxHook
            });
    }
}
