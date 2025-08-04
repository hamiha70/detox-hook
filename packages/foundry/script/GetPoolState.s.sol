// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {HookLibrary} from "../src/libraries/HookLibrary.sol";
import {ChainAddresses} from "./ChainAddresses.sol";
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
        _displayPoolState("DetoxHook Pool 1 (ETH/USDC 0.3%)", pool1);

        // Real DetoxHook Pool 2: ETH/USDC 0.05% fee
        PoolKey memory pool2 = _getDetoxPool2Key();
        _displayPoolState("DetoxHook Pool 2 (ETH/USDC 0.05%)", pool2);

        // Real DetoxHook Pool 3: ETH/MockUSDC 0.05% fee
        PoolKey memory pool3 = _getDetoxPool3Key();
        _displayPoolState("DetoxHook Pool 3 (ETH/MockUSDC 0.05%)", pool3);
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
        console.log("  Current Tick:", uint256(int256(tick)));
        console.log("  Protocol Fee:", protocolFee);
        console.log("  LP Fee:", lpFee);
        console.log("  Liquidity:", liquidity);

        // Calculate human-readable price
        if (sqrtPriceX96 > 0) {
            uint256 humanPrice = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
            console.log("  Human Price (USDC/ETH):", humanPrice);
            console.log("  ETH/USDC Rate:", 1e36 / humanPrice);
        }
    }

    function _getDetoxPool1Key() internal pure returns (PoolKey memory) {
        return
            PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(
                    0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
                ), // USDC
                fee: 3000, // 0.3%
                tickSpacing: 60,
                hooks: IHooks(0x444F320aA27e73e1E293c14B22EfBDCbce0e0088) // DetoxHook
            });
    }

    function _getDetoxPool2Key() internal pure returns (PoolKey memory) {
        return
            PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(
                    0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
                ), // USDC
                fee: 500, // 0.05%
                tickSpacing: 10,
                hooks: IHooks(0x444F320aA27e73e1E293c14B22EfBDCbce0e0088) // DetoxHook
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
