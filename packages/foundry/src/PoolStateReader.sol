// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/**
 * @title PoolStateReader
 * @notice A proxy contract to read Uniswap V4 pool state using StateLibrary
 * @dev This solves the issue where Python web3.py calls don't work the same as Solidity StateLibrary calls
 */
contract PoolStateReader {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /**
     * @notice Get pool state by pool ID (works like our successful Forge script)
     * @param poolId The pool ID to query
     * @return sqrtPriceX96 Current sqrt price
     * @return tick Current tick
     * @return protocolFee Protocol fee
     * @return lpFee LP fee
     * @return liquidity Current liquidity
     * @return success Whether the query was successful
     */
    function getPoolStateById(
        bytes32 poolId
    )
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity,
            bool success
        )
    {
        try this._internalGetPoolState(poolId) returns (
            uint160 _sqrtPriceX96,
            int24 _tick,
            uint24 _protocolFee,
            uint24 _lpFee,
            uint128 _liquidity
        ) {
            return (
                _sqrtPriceX96,
                _tick,
                _protocolFee,
                _lpFee,
                _liquidity,
                true
            );
        } catch {
            return (0, 0, 0, 0, 0, false);
        }
    }

    /**
     * @notice Get pool state for DetoxHook Pool 1
     * @return sqrtPriceX96 Current sqrt price
     * @return tick Current tick
     * @return protocolFee Protocol fee
     * @return lpFee LP fee
     * @return liquidity Current liquidity
     * @return success Whether the query was successful
     */
    function getDetoxPool1State()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity,
            bool success
        )
    {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(
                0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
            ), // USDC
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(0x444F320aA27e73e1E293c14B22EfBDCbce0e0088) // DetoxHook
        });

        PoolId poolId = poolKey.toId();
        return this.getPoolStateById(PoolId.unwrap(poolId));
    }

    /**
     * @notice Get pool state for DetoxHook Pool 2
     * @return sqrtPriceX96 Current sqrt price
     * @return tick Current tick
     * @return protocolFee Protocol fee
     * @return lpFee LP fee
     * @return liquidity Current liquidity
     * @return success Whether the query was successful
     */
    function getDetoxPool2State()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity,
            bool success
        )
    {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(
                0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
            ), // USDC
            fee: 500, // 0.05%
            tickSpacing: 10,
            hooks: IHooks(0x444F320aA27e73e1E293c14B22EfBDCbce0e0088) // DetoxHook
        });

        PoolId poolId = poolKey.toId();
        return this.getPoolStateById(PoolId.unwrap(poolId));
    }

    /**
     * @notice Internal function to get pool state (for try-catch)
     * @param poolId The pool ID to query
     * @return sqrtPriceX96 Current sqrt price
     * @return tick Current tick
     * @return protocolFee Protocol fee
     * @return lpFee LP fee
     * @return liquidity Current liquidity
     */
    function _internalGetPoolState(
        bytes32 poolId
    )
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity
        )
    {
        // Use StateLibrary exactly like our successful Forge script
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(
            poolManager,
            PoolId.wrap(poolId)
        );
        liquidity = StateLibrary.getLiquidity(poolManager, PoolId.wrap(poolId));
    }

    /**
     * @notice Get the pool IDs for both DetoxHook pools
     * @return pool1Id Pool 1 ID
     * @return pool2Id Pool 2 ID
     */
    function getDetoxPoolIds()
        external
        pure
        returns (bytes32 pool1Id, bytes32 pool2Id)
    {
        PoolKey memory pool1Key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(
                0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
            ),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(0x444F320aA27e73e1E293c14B22EfBDCbce0e0088)
        });

        PoolKey memory pool2Key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(
                0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
            ),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(0x444F320aA27e73e1E293c14B22EfBDCbce0e0088)
        });

        pool1Id = PoolId.unwrap(pool1Key.toId());
        pool2Id = PoolId.unwrap(pool2Key.toId());
    }
}
