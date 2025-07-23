// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Gas Limits Configuration
/// @notice Centralized gas limit constants based on DetoxHook analysis
/// @dev Use these constants across all tests for consistency
library GasLimitsConfig {
    // ============ Test Environment Limits ============

    /// @notice MockPyth environment gas limits (test environment)
    uint256 public constant MOCK_PYTH_BEFORE_SWAP = 80000; // DetoxHook beforeSwap with MockPyth
    uint256 public constant MOCK_PYTH_FULL_SWAP = 200000; // Complete swap with MockPyth
    uint256 public constant MOCK_PYTH_ORACLE_CALL = 30000; // Single MockPyth price call

    // ============ Production Environment Limits ============

    /// @notice Real Pyth environment gas limits (production)
    uint256 public constant REAL_PYTH_BEFORE_SWAP = 300000; // DetoxHook beforeSwap with real Pyth
    uint256 public constant REAL_PYTH_FULL_SWAP = 900000; // Complete swap with real Pyth
    uint256 public constant REAL_PYTH_ORACLE_CALL = 100000; // Single real Pyth price call

    // ============ Optimization Targets ============

    /// @notice Gas optimization goals
    uint256 public constant OPTIMIZED_BEFORE_SWAP = 200000; // Target for optimized beforeSwap
    uint256 public constant OPTIMIZED_FULL_SWAP = 600000; // Target for optimized full swap
    uint256 public constant OPTIMIZED_ORACLE_CALL = 50000; // Target for optimized oracle calls

    // ============ Component-Specific Limits ============

    /// @notice Individual component gas limits
    uint256 public constant PRICE_REGISTRY_SET_MAPPING = 140000; // PriceRegistry operations
    uint256 public constant PRICE_REGISTRY_BATCH_SET = 2000000; // Batch operations
    uint256 public constant VANILLA_SWAP_BASELINE = 200000; // Swap without DetoxHook
    uint256 public constant DETOX_HOOK_OVERHEAD_MAX = 700000; // Max acceptable overhead

    // ============ Network-Specific Limits ============

    /// @notice Arbitrum Sepolia specific limits
    uint256 public constant ARBITRUM_SEPOLIA_MAX_GAS = 10000000; // Network max gas limit
    uint256 public constant ARBITRUM_SEPOLIA_SAFE_GAS = 8000000; // Safe limit for complex operations

    // ============ Testing Helper Functions ============

    /// @notice Get appropriate gas limit for testing environment
    /// @param isProduction Whether to use production (real Pyth) limits
    /// @return gasLimit Appropriate gas limit for full swap testing
    function getSwapTestLimit(
        bool isProduction
    ) internal pure returns (uint256 gasLimit) {
        return isProduction ? REAL_PYTH_FULL_SWAP : MOCK_PYTH_FULL_SWAP;
    }

    /// @notice Get gas limit with safety buffer
    /// @param baseLimit Base gas limit
    /// @param bufferPercent Buffer percentage (e.g., 20 for 20% buffer)
    /// @return bufferedLimit Gas limit with buffer applied
    function withBuffer(
        uint256 baseLimit,
        uint256 bufferPercent
    ) internal pure returns (uint256 bufferedLimit) {
        return baseLimit + ((baseLimit * bufferPercent) / 100);
    }

    /// @notice Check if gas usage is within acceptable range
    /// @param gasUsed Actual gas used
    /// @param expectedLimit Expected gas limit
    /// @param tolerance Tolerance percentage (e.g., 10 for 10% tolerance)
    /// @return isAcceptable Whether gas usage is acceptable
    function isGasUsageAcceptable(
        uint256 gasUsed,
        uint256 expectedLimit,
        uint256 tolerance
    ) internal pure returns (bool isAcceptable) {
        uint256 maxAcceptable = expectedLimit +
            ((expectedLimit * tolerance) / 100);
        return gasUsed <= maxAcceptable;
    }
}
