// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v4-core/src/types/PoolKey.sol";
import "@uniswap/v4-core/src/types/PoolId.sol";
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract PoolStateViewer {
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Get pool state by poolId (internal function)
    /// @param poolId The bytes32 identifier of the pool
    /// @return sqrtPriceX96 Current sqrt price
    /// @return tick Current tick
    /// @return protocolFee Protocol fee in hundredths of a bip (1e-6)
    /// @return lpFee Liquidity provider fee
    /// @return liquidity Current in-range liquidity
    /// @return success True if pool exists and state read successfully
    function _getPoolStateById(
        bytes32 poolId
    )
        public
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
        // Use StateLibrary functions directly - they will revert if pool doesn't exist
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(
            poolManager,
            PoolId.wrap(poolId)
        );

        // Get liquidity using StateLibrary
        liquidity = StateLibrary.getLiquidity(poolManager, PoolId.wrap(poolId));
        success = true;
    }

    /// @notice Get pool state by poolId (external function)
    /// @param poolId The bytes32 identifier of the pool
    /// @return sqrtPriceX96 Current sqrt price
    /// @return tick Current tick
    /// @return protocolFee Protocol fee in hundredths of a bip (1e-6)
    /// @return lpFee Liquidity provider fee
    /// @return liquidity Current in-range liquidity
    /// @return success True if pool exists and state read successfully
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
        try this._getPoolStateById(poolId) returns (
            uint160 _sqrtPriceX96,
            int24 _tick,
            uint24 _protocolFee,
            uint24 _lpFee,
            uint128 _liquidity,
            bool _success
        ) {
            sqrtPriceX96 = _sqrtPriceX96;
            tick = _tick;
            protocolFee = _protocolFee;
            lpFee = _lpFee;
            liquidity = _liquidity;
            success = _success;
        } catch {
            // Pool doesn't exist or not initialized
            success = false;
        }
    }

    /// @notice Get poolId by PoolKey
    /// @param poolKey Struct describing the pool
    /// @return poolId Deterministic ID used internally by PoolManager
    function getIdByKey(
        PoolKey memory poolKey
    ) external view returns (bytes32 poolId) {
        poolId = PoolId.unwrap(PoolIdLibrary.toId(poolKey));
    }

    /// @notice Get tick info (liquidity) for a given tick in a pool
    /// @param poolId The pool identifier
    /// @param tick The tick to inspect
    /// @return liquidity Net liquidity at the tick
    /// @return success True if the tick info was read successfully
    function getTickInfo(
        bytes32 poolId,
        int24 tick
    ) external view returns (uint128 liquidity, bool success) {
        try this._getTickInfo(poolId, tick) returns (
            uint128 _liquidity,
            bool _success
        ) {
            liquidity = _liquidity;
            success = _success;
        } catch {
            // Tick doesn't exist or pool not initialized
            success = false;
        }
    }

    /// @notice Get tick info (internal function)
    /// @param poolId The pool identifier
    /// @param tick The tick to inspect
    /// @return liquidity Net liquidity at the tick
    /// @return success True if the tick info was read successfully
    function _getTickInfo(
        bytes32 poolId,
        int24 tick
    ) public view returns (uint128 liquidity, bool success) {
        // Use StateLibrary function directly - it will revert if tick doesn't exist
        (liquidity, , , ) = StateLibrary.getTickInfo(
            poolManager,
            PoolId.wrap(poolId),
            tick
        );
        success = true;
    }

    /// @notice Get pool state by PoolKey (convenience function)
    /// @param poolKey Struct describing the pool
    /// @return sqrtPriceX96 Current sqrt price
    /// @return tick Current tick
    /// @return protocolFee Protocol fee in hundredths of a bip (1e-6)
    /// @return lpFee Liquidity provider fee
    /// @return liquidity Current in-range liquidity
    /// @return success True if pool exists and state read successfully
    function getPoolStateByKey(
        PoolKey memory poolKey
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
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(poolKey));
        try this.getPoolStateById(poolId) returns (
            uint160 _sqrtPriceX96,
            int24 _tick,
            uint24 _protocolFee,
            uint24 _lpFee,
            uint128 _liquidity,
            bool _success
        ) {
            sqrtPriceX96 = _sqrtPriceX96;
            tick = _tick;
            protocolFee = _protocolFee;
            lpFee = _lpFee;
            liquidity = _liquidity;
            success = _success;
        } catch {
            // Pool doesn't exist or not initialized
            success = false;
        }
    }
}
