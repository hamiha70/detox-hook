// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

/// @title DisplayPoolInfoScript
/// @notice Display DetoxHook pool information and PoolKeys
contract DisplayPoolInfo is Script {
    using ChainAddresses for uint256;
    using PoolIdLibrary for PoolKey;

    // DetoxHook address
    address constant DETOX_HOOK = 0x444F320aA27e73e1E293c14B22EfBDCbce0e0088;

    function run() external view {
        console.log("=== DetoxHook Pool Information ===");
        console.log("Chain:", ChainAddresses.getChainName(block.chainid));
        console.log("DetoxHook Address:", DETOX_HOOK);
        console.log("USDC Address:", ChainAddresses.getUSDC(block.chainid));
        console.log("Pool Manager:", ChainAddresses.getPoolManager(block.chainid));
        console.log("");

        _displayPool1();
        console.log("");
        _displayPool2();
        console.log("");
        _displayPoolKeys();
    }

    function _displayPool1() internal view {
        console.log("=== Pool 1 (0.3% fee, ~2500 USDC/ETH) ===");
        console.log("PoolId: 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f");
        console.log("Description: ETH/USDC 0.3% fee pool");
        console.log("Target Price: ~2500 USDC/ETH");
        console.log("Fee: 3000 (0.3%)");
        console.log("Tick Spacing: 60");
        console.log("Status: Initialized & Funded");
        console.log("Initial Liquidity: 1 USDC + 0.0004 ETH");
    }

    function _displayPool2() internal view {
        console.log("=== Pool 2 (0.05% fee, ~2600 USDC/ETH) ===");
        console.log("PoolId: 0x10fe1bb5300768c6f5986ee70c9ee834ea64ea704f92b0fd2cda0bcbe829ec90");
        console.log("Description: ETH/USDC 0.05% fee pool");
        console.log("Target Price: ~2600 USDC/ETH");
        console.log("Fee: 500 (0.05%)");
        console.log("Tick Spacing: 10");
        console.log("Status: Initialized & Funded");
        console.log("Initial Liquidity: 1 USDC + ~0.000385 ETH");
    }

    function _displayPoolKeys() internal view {
        console.log("=== PoolKey Structures ===");
        
        address usdc = ChainAddresses.getUSDC(block.chainid);
        
        // Pool 1 PoolKey
        PoolKey memory poolKey1 = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(usdc), // USDC
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(DETOX_HOOK)
        });
        
        // Pool 2 PoolKey
        PoolKey memory poolKey2 = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(usdc), // USDC
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(DETOX_HOOK)
        });
        
        console.log("Pool 1 PoolKey:");
        console.log("  currency0 (ETH):", Currency.unwrap(poolKey1.currency0));
        console.log("  currency1 (USDC):", Currency.unwrap(poolKey1.currency1));
        console.log("  fee:", poolKey1.fee);
        console.log("  tickSpacing:", poolKey1.tickSpacing);
        console.log("  hooks:", address(poolKey1.hooks));
        console.log("  Computed PoolId:", vm.toString(PoolId.unwrap(poolKey1.toId())));
        
        console.log("");
        console.log("Pool 2 PoolKey:");
        console.log("  currency0 (ETH):", Currency.unwrap(poolKey2.currency0));
        console.log("  currency1 (USDC):", Currency.unwrap(poolKey2.currency1));
        console.log("  fee:", poolKey2.fee);
        console.log("  tickSpacing:", poolKey2.tickSpacing);
        console.log("  hooks:", address(poolKey2.hooks));
        console.log("  Computed PoolId:", vm.toString(PoolId.unwrap(poolKey2.toId())));
    }

    /// @notice Get PoolKey for Pool 1
    function getPool1Key() external view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(ChainAddresses.getUSDC(block.chainid)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(DETOX_HOOK)
        });
    }

    /// @notice Get PoolKey for Pool 2
    function getPool2Key() external view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(ChainAddresses.getUSDC(block.chainid)),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(DETOX_HOOK)
        });
    }

    /// @notice Get both PoolKeys
    function getBothPoolKeys() external view returns (PoolKey memory pool1, PoolKey memory pool2) {
        pool1 = this.getPool1Key();
        pool2 = this.getPool2Key();
    }
} 