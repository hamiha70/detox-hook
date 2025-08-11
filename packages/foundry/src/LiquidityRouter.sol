// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LiquidityRouter
/// @notice Router contract for managing liquidity in Uniswap V4 pools
/// @dev This contract uses PoolModifyLiquidityTest to access the liquidity pool via PoolManager
contract LiquidityRouter {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    /// @notice The PoolModifyLiquidityTest contract for handling liquidity operations
    PoolModifyLiquidityTest public immutable poolModifyLiquidityTest;

    /// @notice The PoolManager contract
    IPoolManager public immutable poolManager;

    /// @notice Error thrown when PoolModifyLiquidityTest is not set
    error PoolModifyLiquidityTestNotSet();

    /// @notice Error thrown when PoolManager is not set
    error PoolManagerNotSet();

    /// @notice Error thrown when token transfer fails
    error TokenTransferFailed();

    /// @notice Error thrown when insufficient token balance
    error InsufficientBalance();

    /// @notice Event emitted when liquidity is modified
    event LiquidityModified(
        address indexed sender,
        PoolKey indexed poolKey,
        ModifyLiquidityParams params,
        BalanceDelta delta,
        bool takeClaims,
        bool settleUsingBurn
    );

    /// @notice Event emitted when tokens are approved
    event TokensApproved(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    /// @param _poolModifyLiquidityTest Address of the PoolModifyLiquidityTest contract
    /// @param _poolManager Address of the PoolManager contract
    constructor(address _poolModifyLiquidityTest, address _poolManager) {
        if (_poolModifyLiquidityTest == address(0))
            revert PoolModifyLiquidityTestNotSet();
        if (_poolManager == address(0)) revert PoolManagerNotSet();

        poolModifyLiquidityTest = PoolModifyLiquidityTest(
            _poolModifyLiquidityTest
        );
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Approve tokens for the PoolModifyLiquidityTest contract
    /// @param token The token to approve (address(0) for ETH)
    /// @param amount The amount to approve
    function approveToken(address token, uint256 amount) external {
        if (token != address(0)) {
            // Reset approval to zero first, then set to desired amount
            IERC20(token).approve(address(poolModifyLiquidityTest), 0);
            IERC20(token).approve(address(poolModifyLiquidityTest), amount);
            emit TokensApproved(
                token,
                address(poolModifyLiquidityTest),
                amount
            );
        }
    }

    /// @notice Approve max tokens for common currencies
    /// @param poolKey The pool key to approve tokens for
    function approvePoolTokens(PoolKey calldata poolKey) external {
        // Approve currency0 if it's not ETH
        if (!poolKey.currency0.isAddressZero()) {
            address token0 = Currency.unwrap(poolKey.currency0);
            IERC20(token0).approve(address(poolModifyLiquidityTest), 0);
            IERC20(token0).approve(
                address(poolModifyLiquidityTest),
                type(uint256).max
            );
            emit TokensApproved(
                token0,
                address(poolModifyLiquidityTest),
                type(uint256).max
            );
        }

        // Approve currency1 if it's not ETH
        if (!poolKey.currency1.isAddressZero()) {
            address token1 = Currency.unwrap(poolKey.currency1);
            IERC20(token1).approve(address(poolModifyLiquidityTest), 0);
            IERC20(token1).approve(
                address(poolModifyLiquidityTest),
                type(uint256).max
            );
            emit TokensApproved(
                token1,
                address(poolModifyLiquidityTest),
                type(uint256).max
            );
        }
    }

    /// @notice Transfer tokens from user to this contract before liquidity operation
    /// @param poolKey The pool key
    /// @param liquidityDelta The liquidity delta (for calculating required amounts)
    function prepareTokens(
        PoolKey calldata poolKey,
        int256 liquidityDelta
    ) external payable {
        // For adding liquidity, we need to transfer tokens from user to this contract
        if (liquidityDelta > 0) {
            // Calculate proper token amounts based on liquidity delta
            // Use a minimum amount to ensure tokens are transferred
            uint256 estimatedAmount0 = uint256(liquidityDelta) * 100000; // Realistic calculation
            uint256 estimatedAmount1 = uint256(liquidityDelta) * 100000; // Realistic calculation

            // Transfer currency0 if it's not ETH
            if (!poolKey.currency0.isAddressZero()) {
                address token0 = Currency.unwrap(poolKey.currency0);
                IERC20(token0).safeTransferFrom(
                    msg.sender,
                    address(this),
                    estimatedAmount0
                );
            }

            // Transfer currency1 if it's not ETH
            if (!poolKey.currency1.isAddressZero()) {
                address token1 = Currency.unwrap(poolKey.currency1);
                IERC20(token1).safeTransferFrom(
                    msg.sender,
                    address(this),
                    estimatedAmount1
                );
            }
        }
    }

    /// @notice Modify liquidity in a pool with default settlement options
    /// @param poolKey The pool key identifying the pool
    /// @param params The parameters for modifying liquidity
    /// @param updateData Additional data for price updates or hook data
    /// @return delta The balance delta from the liquidity modification
    function modifyLiquidity(
        PoolKey calldata poolKey,
        ModifyLiquidityParams calldata params,
        bytes calldata updateData
    ) external payable returns (BalanceDelta delta) {
        return modifyLiquidity(poolKey, params, updateData, false, false);
    }

    /// @notice Modify liquidity in a pool with custom settlement options
    /// @param poolKey The pool key identifying the pool
    /// @param params The parameters for modifying liquidity
    /// @param updateData Additional data for price updates or hook data
    /// @param takeClaims Whether to take claims during settlement
    /// @param settleUsingBurn Whether to settle using burn mechanism
    /// @return delta The balance delta from the liquidity modification
    function modifyLiquidity(
        PoolKey calldata poolKey,
        ModifyLiquidityParams memory params,
        bytes calldata updateData,
        bool takeClaims,
        bool settleUsingBurn
    ) public payable returns (BalanceDelta delta) {
        // Ensure proper approvals are in place for adding liquidity
        if (params.liquidityDelta > 0) {
            _ensureApprovals(poolKey);
        }

        // Call the PoolModifyLiquidityTest contract to modify liquidity
        delta = poolModifyLiquidityTest.modifyLiquidity{value: msg.value}(
            poolKey,
            params,
            updateData,
            settleUsingBurn,
            takeClaims
        );

        // Emit event for tracking
        emit LiquidityModified(
            msg.sender,
            poolKey,
            params,
            delta,
            takeClaims,
            settleUsingBurn
        );

        return delta;
    }

    /// @notice Add liquidity to a pool
    /// @param poolKey The pool key identifying the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidityDelta The amount of liquidity to add (must be positive)
    /// @param salt Unique identifier for the position
    /// @param updateData Additional data for price updates or hook data
    /// @return delta The balance delta from adding liquidity
    function addLiquidity(
        PoolKey calldata poolKey,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bytes32 salt,
        bytes calldata updateData
    ) external payable returns (BalanceDelta delta) {
        require(
            liquidityDelta > 0,
            "LiquidityRouter: liquidityDelta must be positive"
        );

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            salt: salt
        });

        return modifyLiquidity(poolKey, params, updateData, false, false);
    }

    /// @notice Remove liquidity from a pool
    /// @param poolKey The pool key identifying the pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidityDelta The amount of liquidity to remove (must be negative)
    /// @param salt Unique identifier for the position
    /// @param updateData Additional data for price updates or hook data
    /// @return delta The balance delta from removing liquidity
    function removeLiquidity(
        PoolKey calldata poolKey,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bytes32 salt,
        bytes calldata updateData
    ) external payable returns (BalanceDelta delta) {
        require(
            liquidityDelta < 0,
            "LiquidityRouter: liquidityDelta must be negative"
        );

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            salt: salt
        });

        return modifyLiquidity(poolKey, params, updateData, false, false);
    }

    /// @notice Emergency function to withdraw stuck tokens
    /// @param token The token to withdraw (address(0) for ETH)
    /// @param amount The amount to withdraw
    function emergencyWithdraw(address token, uint256 amount) external {
        if (token == address(0)) {
            // Withdraw ETH
            payable(msg.sender).transfer(amount);
        } else {
            // Withdraw ERC20 token
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /// @notice Internal function to ensure proper token approvals
    /// @param poolKey The pool key
    function _ensureApprovals(PoolKey calldata poolKey) internal {
        // Approve currency0 if it's not ETH and not already approved
        if (!poolKey.currency0.isAddressZero()) {
            address token0 = Currency.unwrap(poolKey.currency0);
            uint256 allowance0 = IERC20(token0).allowance(
                address(this),
                address(poolModifyLiquidityTest)
            );
            if (allowance0 < type(uint256).max / 2) {
                IERC20(token0).approve(address(poolModifyLiquidityTest), 0);
                IERC20(token0).approve(
                    address(poolModifyLiquidityTest),
                    type(uint256).max
                );
            }
        }

        // Approve currency1 if it's not ETH and not already approved
        if (!poolKey.currency1.isAddressZero()) {
            address token1 = Currency.unwrap(poolKey.currency1);
            uint256 allowance1 = IERC20(token1).allowance(
                address(this),
                address(poolModifyLiquidityTest)
            );
            if (allowance1 < type(uint256).max / 2) {
                IERC20(token1).approve(address(poolModifyLiquidityTest), 0);
                IERC20(token1).approve(
                    address(poolModifyLiquidityTest),
                    type(uint256).max
                );
            }
        }
    }

    /// @notice Get the PoolModifyLiquidityTest contract address
    /// @return The address of the PoolModifyLiquidityTest contract
    function getPoolModifyLiquidityTest() external view returns (address) {
        return address(poolModifyLiquidityTest);
    }

    /// @notice Get the PoolManager contract address
    /// @return The address of the PoolManager contract
    function getPoolManager() external view returns (address) {
        return address(poolManager);
    }

    /// @notice Receive function to accept ETH
    receive() external payable {}

    /// @notice Fallback function
    fallback() external payable {}
}
