// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";

/// @title PoolParameters
/// @notice Provides static PoolKey configurations for supported chains
library PoolParameters {
    /// @notice Get PoolKey1 (ETH/USDC, 0.05% fee, tickSpacing 10)
    /// @param chainId The chain ID
    /// @param hook The DetoxHook address
    /// @param usdc The USDC token address
    /// @return poolKey The PoolKey struct
    function getPoolKey1(uint256 chainId, address hook, address usdc) internal pure returns (PoolKey memory poolKey) {
        if (chainId == 31337) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 10,
                hooks: IHooks(hook)
            });
        } else if (chainId == 421614) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 10,
                hooks: IHooks(hook)
            });
        }
        revert("Unsupported chain");
    }

    /// @notice Get PoolKey2 (ETH/USDC, 0.05% fee, tickSpacing 60)
    /// @param chainId The chain ID
    /// @param hook The DetoxHook address
    /// @param usdc The USDC token address
    /// @return poolKey The PoolKey struct
    function getPoolKey2(uint256 chainId, address hook, address usdc) internal pure returns (PoolKey memory poolKey) {
        if (chainId == 31337) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 60,
                hooks: IHooks(hook)
            });
        } else if (chainId == 421614) {
            return PoolKey({
                currency0: Currency.wrap(address(0)), // ETH
                currency1: Currency.wrap(usdc),      // USDC
                fee: 500,
                tickSpacing: 60,
                hooks: IHooks(hook)
            });
        }
        revert("Unsupported chain");
    }
} 