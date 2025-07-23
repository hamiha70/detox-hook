// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { IERC20Minimal } from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

/// @title SafetyChecks
/// @notice Comprehensive safety validation library for DetoxHook deployment and operations
/// @dev Provides reusable safety checks to prevent common deployment and operational failures
library SafetyChecks {
    using PoolIdLibrary for PoolKey;

    // ============ Custom Errors ============
    
    error ContractAlreadyDeployed(address contractAddress, string contractName);
    error InvalidDeploymentAddress(address contractAddress);
    error InsufficientETHBalance(address account, uint256 required, uint256 actual, string operation);
    error InsufficientTokenBalance(address token, address account, uint256 required, uint256 actual, string operation);
    error PoolAlreadyInitialized(PoolId poolId);
    error InsufficientAllowance(address token, address owner, address spender, uint256 required, uint256 actual);
    error ContractNotDeployed(address contractAddress, string contractName);

    // ============ Deployment Safety Checks ============

    /// @notice Check if address is safe for deployment (no existing code)
    /// @param expectedAddress The address where deployment is planned
    /// @param contractName Name of contract for error messages
    function checkDeploymentSafety(address expectedAddress, string memory contractName) internal view {
        if (expectedAddress == address(0)) {
            revert InvalidDeploymentAddress(expectedAddress);
        }
        
        if (expectedAddress.code.length > 0) {
            console.log("[SAFETY] Contract already deployed at:", expectedAddress);
            console.log("[SAFETY] Contract name:", contractName);
            revert ContractAlreadyDeployed(expectedAddress, contractName);
        }
        
        console.log("[SAFETY] Deployment address safe:", expectedAddress);
    }

    /// @notice Check if contract exists at expected address
    /// @param contractAddress The address to check
    /// @param contractName Name of contract for error messages
    function checkContractExists(address contractAddress, string memory contractName) internal view {
        if (contractAddress.code.length == 0) {
            console.log("[SAFETY] Contract not found at:", contractAddress);
            console.log("[SAFETY] Contract name:", contractName);
            revert ContractNotDeployed(contractAddress, contractName);
        }
        
        console.log("[SAFETY] Contract verified at:", contractAddress);
    }

    /// @notice Check if contract is already deployed and return status
    /// @param expectedAddress The address to check
    /// @param contractName Name of contract for logging
    /// @return isDeployed True if contract exists at address
    function isContractDeployed(address expectedAddress, string memory contractName) internal view returns (bool isDeployed) {
        isDeployed = expectedAddress.code.length > 0;
        
        if (isDeployed) {
            console.log("[SAFETY] Contract already deployed:", contractName, "at", expectedAddress);
        } else {
            console.log("[SAFETY] Contract not deployed:", contractName, "- safe to deploy at", expectedAddress);
        }
    }

    // ============ Balance Validation Checks ============

    /// @notice Validate ETH balance for operations
    /// @param account Account to check
    /// @param requiredAmount Minimum ETH required
    /// @param operation Description of operation for error messages
    function validateETHBalance(address account, uint256 requiredAmount, string memory operation) internal view {
        uint256 balance = account.balance;
        
        if (balance < requiredAmount) {
            console.log("[SAFETY] Insufficient ETH for:", operation);
            console.log("[SAFETY] Account:", account);
            console.log("[SAFETY] Required:", requiredAmount);
            console.log("[SAFETY] Actual:", balance);
            revert InsufficientETHBalance(account, requiredAmount, balance, operation);
        }
        
        console.log("[SAFETY] ETH balance sufficient for:", operation);
        console.log("[SAFETY] Account:", account, "Balance:", balance);
    }

    /// @notice Validate token balance for operations
    /// @param token Token contract to check
    /// @param account Account to check
    /// @param requiredAmount Minimum tokens required
    /// @param operation Description of operation for error messages
    function validateTokenBalance(IERC20Minimal token, address account, uint256 requiredAmount, string memory operation) internal view {
        uint256 balance = token.balanceOf(account);
        
        if (balance < requiredAmount) {
            console.log("[SAFETY] Insufficient token balance for:", operation);
            console.log("[SAFETY] Token:", address(token));
            console.log("[SAFETY] Account:", account);
            console.log("[SAFETY] Required:", requiredAmount);
            console.log("[SAFETY] Actual:", balance);
            revert InsufficientTokenBalance(address(token), account, requiredAmount, balance, operation);
        }
        
        console.log("[SAFETY] Token balance sufficient for:", operation);
        console.log("[SAFETY] Token:", address(token));
        console.log("[SAFETY] Account:", account);
        console.log("[SAFETY] Balance:", balance);
    }

    // ============ ERC20 Approval Checks ============

    /// @notice Check and ensure sufficient ERC20 allowance
    /// @param token Token contract
    /// @param owner Token owner
    /// @param spender Address that will spend tokens
    /// @param requiredAmount Minimum allowance required
    /// @return wasApprovalNeeded True if approval was executed
    function ensureApproval(IERC20Minimal token, address owner, address spender, uint256 requiredAmount) internal returns (bool wasApprovalNeeded) {
        uint256 currentAllowance = token.allowance(owner, spender);
        
        if (currentAllowance < requiredAmount) {
            console.log("[SAFETY] Insufficient allowance - approving token");
            console.log("[SAFETY] Token:", address(token));
            console.log("[SAFETY] Owner:", owner);
            console.log("[SAFETY] Spender:", spender);
            console.log("[SAFETY] Required:", requiredAmount);
            console.log("[SAFETY] Current:", currentAllowance);
            
            // Approve maximum amount to avoid repeated approvals
            token.approve(spender, type(uint256).max);
            wasApprovalNeeded = true;
            
            console.log("[SAFETY] Token approved successfully");
        } else {
            console.log("[SAFETY] Token allowance sufficient");
            console.log("[SAFETY] Token:", address(token));
            console.log("[SAFETY] Allowance:", currentAllowance);
            wasApprovalNeeded = false;
        }
    }

    /// @notice Validate existing ERC20 allowance without modifying
    /// @param token Token contract
    /// @param owner Token owner
    /// @param spender Address that will spend tokens
    /// @param requiredAmount Minimum allowance required
    function validateApproval(IERC20Minimal token, address owner, address spender, uint256 requiredAmount) internal view {
        uint256 currentAllowance = token.allowance(owner, spender);
        
        if (currentAllowance < requiredAmount) {
            console.log("[SAFETY] Insufficient allowance detected");
            console.log("[SAFETY] Token:", address(token));
            console.log("[SAFETY] Owner:", owner);
            console.log("[SAFETY] Spender:", spender);
            console.log("[SAFETY] Required:", requiredAmount);
            console.log("[SAFETY] Current:", currentAllowance);
            revert InsufficientAllowance(address(token), owner, spender, requiredAmount, currentAllowance);
        }
        
        console.log("[SAFETY] Token allowance validated");
    }

    // ============ Pool State Checks ============

    /// @notice Check if pool is already initialized
    /// @param poolManager The pool manager contract
    /// @param poolKey Pool configuration
    function checkPoolNotInitialized(IPoolManager poolManager, PoolKey memory poolKey) internal view {
        PoolId poolId = poolKey.toId();
        
        // Get pool state directly - StateLibrary functions are internal
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
        
        if (sqrtPriceX96 != 0) {
            console.log("[SAFETY] Pool already initialized");
            console.log("[SAFETY] PoolId:", uint256(PoolId.unwrap(poolId)));
            console.log("[SAFETY] SqrtPriceX96:", sqrtPriceX96);
            revert PoolAlreadyInitialized(poolId);
        }
        
        console.log("[SAFETY] Pool not initialized - safe to initialize");
        console.log("[SAFETY] Pool initialization check passed");
    }

    /// @notice Check if pool is initialized and return status
    /// @param poolManager The pool manager contract
    /// @param poolKey Pool configuration
    /// @return isInitialized True if pool is already initialized
    function isPoolInitialized(IPoolManager poolManager, PoolKey memory poolKey) internal view returns (bool isInitialized) {
        PoolId poolId = poolKey.toId();
        
        // Get pool state directly
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
        isInitialized = (sqrtPriceX96 != 0);
        
        if (isInitialized) {
            console.log("[SAFETY] Pool is initialized");
            console.log("[SAFETY] PoolId:", uint256(PoolId.unwrap(poolId)));
            console.log("[SAFETY] SqrtPriceX96:", sqrtPriceX96);
        } else {
            console.log("[SAFETY] Pool not initialized");
        }
    }

    // ============ Comprehensive Pre-Operation Checks ============

    /// @notice Comprehensive check before liquidity operations
    /// @param token Token to provide as liquidity
    /// @param account Account providing liquidity
    /// @param tokenAmount Amount of tokens needed
    /// @param ethAmount Amount of ETH needed
    /// @param spender Contract that will spend tokens (router)
    function validateLiquidityOperation(
        IERC20Minimal token,
        address account,
        uint256 tokenAmount,
        uint256 ethAmount,
        address spender
    ) internal {
        console.log("[SAFETY] Validating liquidity operation");
        
        // Check ETH balance
        validateETHBalance(account, ethAmount, "liquidity provision");
        
        // Check token balance
        validateTokenBalance(token, account, tokenAmount, "liquidity provision");
        
        // Check token approval
        validateApproval(token, account, spender, tokenAmount);
        
        console.log("[SAFETY] Liquidity operation validation passed");
    }

    /// @notice Comprehensive check before swap operations
    /// @param token Token to swap
    /// @param account Account performing swap
    /// @param tokenAmount Amount of tokens needed for swap
    /// @param spender Contract that will spend tokens (router)
    function validateSwapOperation(
        IERC20Minimal token,
        address account,
        uint256 tokenAmount,
        address spender
    ) internal {
        console.log("[SAFETY] Validating swap operation");
        
        // Check token balance
        validateTokenBalance(token, account, tokenAmount, "swap operation");
        
        // Check token approval
        validateApproval(token, account, spender, tokenAmount);
        
        console.log("[SAFETY] Swap operation validation passed");
    }

    /// @notice Comprehensive check before deployment operations
    /// @param deployer Deployer account
    /// @param estimatedGas Estimated gas cost for deployment
    /// @param contractName Name of contract being deployed
    function validateDeploymentOperation(
        address deployer,
        uint256 estimatedGas,
        string memory contractName
    ) internal view {
        console.log("[SAFETY] Validating deployment operation for:", contractName);
        
        // Check ETH balance for gas
        validateETHBalance(deployer, estimatedGas, string(abi.encodePacked("deployment of ", contractName)));
        
        console.log("[SAFETY] Deployment operation validation passed");
    }

    // ============ Utility Functions ============

    /// @notice Log comprehensive account status
    /// @param account Account to check
    /// @param token Token to check balance for
    function logAccountStatus(address account, IERC20Minimal token) internal view {
        console.log("=== Account Status ===");
        console.log("Account:", account);
        console.log("ETH Balance:", account.balance);
        console.log("Token Balance:", token.balanceOf(account));
        console.log("Token Address:", address(token));
        console.log("======================");
    }

    /// @notice Log contract deployment status
    /// @param contractAddress Address to check
    /// @param contractName Name for logging
    function logContractStatus(address contractAddress, string memory contractName) internal view {
        console.log("=== Contract Status ===");
        console.log("Contract:", contractName);
        console.log("Address:", contractAddress);
        console.log("Code Length:", contractAddress.code.length);
        console.log("Deployed:", contractAddress.code.length > 0 ? "Yes" : "No");
        console.log("=======================");
    }
} 