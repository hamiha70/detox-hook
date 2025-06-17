// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { BaseHook } from "@v4-periphery/src/utils/BaseHook.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { toBeforeSwapDelta, BeforeSwapDelta } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { IERC20Minimal } from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import { IPyth } from "./libraries/PythLibrary.sol";
import { SimplifiedOracleLib } from "./libraries/SimplifiedOracleLib.sol";
import { SimplifiedArbitrageLib } from "./libraries/SimplifiedArbitrageLib.sol";
import { HookLibrary } from "./libraries/HookLibrary.sol";

/**
 * @title SimplifiedDetoxHook
 * @notice Simplified MEV protection hook with single precision system and confidence bounds
 * @dev Uses 1e18 precision throughout, simplified arbitrage detection, and direct confidence bounds
 */
contract SimplifiedDetoxHook is BaseHook {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;

    // ============ Constants ============
    
    /// @notice Single precision system (18 decimals)
    uint256 private constant PRECISION = 1e18;
    
    /// @notice Default hook share in basis points (80%)
    uint256 private constant DEFAULT_RHO_BPS = 8000;
    
    /// @notice Default staleness threshold (60 seconds)
    uint256 private constant DEFAULT_STALENESS_THRESHOLD = 60;
    
    /// @notice Basis points (100%)
    uint256 private constant BASIS_POINTS = 10000;

    // Chain-specific constants (can be made configurable later)
    address private constant USDC_ON_ARBITRUM = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address private constant PYTH_ORACLE_ON_ARBITRUM_SEPOLIA = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF;
    bytes32 private constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 private constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    // ============ State Variables ============
    
    /// @notice Pyth oracle instance
    IPyth public immutable pythOracle;
    
    /// @notice Contract owner
    address public immutable owner;
    
    /// @notice Hook share in basis points
    uint256 public rhoBps;
    
    /// @notice Oracle staleness threshold in seconds
    uint256 public stalenessThreshold;
    
    /// @notice Mapping from currency to Pyth price ID
    mapping(Currency => bytes32) public pythPriceIds;
    
    /// @notice Accumulated tokens per pool and currency
    mapping(PoolId => mapping(Currency => uint256)) public accumulatedTokens;

    // ============ Constructor ============

    constructor(IPoolManager _poolManager, address _owner, address _oracle) BaseHook(_poolManager) {
        owner = _owner;
        
        // Initialize configurable parameters
        rhoBps = DEFAULT_RHO_BPS;
        stalenessThreshold = DEFAULT_STALENESS_THRESHOLD;

        // Oracle initialization
        if (_oracle != address(0)) {
            pythOracle = IPyth(_oracle);
        } else if (block.chainid == 421614) {
            // Arbitrum Sepolia
            pythOracle = IPyth(PYTH_ORACLE_ON_ARBITRUM_SEPOLIA);
        } else {
            // Other chains (like Anvil)
            pythOracle = IPyth(address(0));
        }

        // Initialize price mappings for ETH/USDC pair
        pythPriceIds[Currency.wrap(address(0))] = ETH_USD_PRICE_ID; // ETH
        pythPriceIds[Currency.wrap(USDC_ON_ARBITRUM)] = USDC_USD_PRICE_ID; // USDC
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ============ Hook Implementation ============

    /**
     * @notice Main hook function - detects and captures arbitrage opportunities
     * @param key The pool key
     * @param params The swap parameters  
     * @param hookData Encoded price update data (optional)
     * @return selector Function selector
     * @return delta BeforeSwapDelta for reducing swap amount
     * @return fee Dynamic fee (unused)
     */
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // 1. Early exit for exact output swaps - never interfere
        if (params.amountSpecified >= 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 2. Decode price update data if provided
        bytes[] memory priceUpdate;
        if (hookData.length > 0) {
            priceUpdate = abi.decode(hookData, (bytes[]));
        }

        // 3. Get oracle price bounds for both currencies
        bytes32 priceId0 = pythPriceIds[key.currency0];
        bytes32 priceId1 = pythPriceIds[key.currency1];
        
        if (priceId0 == bytes32(0) || priceId1 == bytes32(0)) {
            // Price IDs not configured for this pair
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // Get oracle price ratio bounds
        (uint256 oracleLowerBound, uint256 oracleUpperBound, bool valid) = 
            SimplifiedOracleLib.calculatePriceRatioBounds(
                pythOracle, priceId0, priceId1, stalenessThreshold
            );

        if (!valid) {
            // Oracle prices invalid or stale
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 4. Get pool price (normalized to PRECISION)
        uint256 poolPrice = _getPoolPriceNormalized(key);
        if (poolPrice == 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 5. Calculate arbitrage amount using simplified library
        uint256 swapAmount = uint256(-params.amountSpecified);
        uint256 arbitrageAmount = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice,
            oracleLowerBound,
            oracleUpperBound,
            swapAmount,
            params.zeroForOne
        );

        // 6. If no arbitrage, don't interfere
        if (arbitrageAmount == 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 7. Calculate hook share and execute capture
        uint256 hookShare = SimplifiedArbitrageLib.calculateHookShare(arbitrageAmount, rhoBps);
        
        return _executeArbitrageCapture(key, params, hookShare, arbitrageAmount);
    }

    /**
     * @notice Execute arbitrage capture by taking hook's share
     * @param key The pool key
     * @param params The swap parameters
     * @param hookShare The amount the hook should capture
     * @param arbitrageAmount The total arbitrage opportunity detected
     * @return selector Function selector
     * @return delta BeforeSwapDelta for reducing swap amount
     * @return fee Dynamic fee (unused)
     */
    function _executeArbitrageCapture(
        PoolKey calldata key,
        SwapParams calldata params,
        uint256 hookShare,
        uint256 arbitrageAmount
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        // Determine input currency
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;

        // Take hook's share from pool
        poolManager.take(inputCurrency, address(this), hookShare);

        // Track accumulated tokens
        PoolId poolId = key.toId();
        accumulatedTokens[poolId][inputCurrency] += hookShare;

        // Create delta to reduce swap amount by hook's share
        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(hookShare)), 0);

        // Emit arbitrage capture event
        emit ArbitrageCaptured(poolId, inputCurrency, hookShare, arbitrageAmount, params.zeroForOne);

        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    // ============ Pool Price Functions ============

    /**
     * @notice Get pool price normalized to PRECISION (1e18)
     * @param key The pool key
     * @return price Pool price as currency1/currency0 ratio with PRECISION
     */
    function _getPoolPriceNormalized(PoolKey memory key) internal view returns (uint256) {
        uint160 sqrtPriceX96 = HookLibrary.getPoolPrice(poolManager, key);
        if (sqrtPriceX96 == 0) return 0;

        // Convert sqrtPriceX96 to price with PRECISION (1e18)
        uint256 price = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
        
        // HookLibrary.sqrtPriceToPrice already returns 1e18 precision
        return price;
    }

    // ============ Owner Functions ============

    /**
     * @notice Update hook parameters (only owner)
     * @param _rhoBps New rho share in basis points
     * @param _stalenessThreshold New staleness threshold in seconds
     */
    function updateParameters(uint256 _rhoBps, uint256 _stalenessThreshold) external onlyOwner {
        require(_rhoBps <= BASIS_POINTS, "Rho BPS too high");
        require(_stalenessThreshold > 0, "Staleness threshold must be positive");

        uint256 oldRhoBps = rhoBps;
        uint256 oldStaleness = stalenessThreshold;

        rhoBps = _rhoBps;
        stalenessThreshold = _stalenessThreshold;

        emit ParametersUpdated(oldRhoBps, _rhoBps, oldStaleness, _stalenessThreshold);
    }

    /**
     * @notice Set price ID for a currency (only owner)
     * @param currency The currency to set price ID for
     * @param priceId The Pyth price ID
     */
    function setPriceId(Currency currency, bytes32 priceId) external onlyOwner {
        bytes32 oldPriceId = pythPriceIds[currency];
        pythPriceIds[currency] = priceId;
        emit PriceIdUpdated(currency, oldPriceId, priceId);
    }

    /**
     * @notice Withdraw accumulated ETH (only owner)
     * @param poolId The pool ID to withdraw from
     * @param amount The amount to withdraw in wei
     * @param recipient The address to send ETH to
     */
    function withdrawAccumulatedETH(
        PoolId poolId,
        uint256 amount,
        address payable recipient
    ) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than zero");

        Currency ethCurrency = Currency.wrap(address(0));
        uint256 available = accumulatedTokens[poolId][ethCurrency];
        require(available >= amount, "Insufficient accumulated ETH");

        // Update accumulated tokens
        accumulatedTokens[poolId][ethCurrency] -= amount;

        // Transfer ETH to recipient
        recipient.transfer(amount);

        emit ETHWithdrawn(poolId, amount, recipient);
    }

    /**
     * @notice Withdraw accumulated ERC20 tokens (only owner)
     * @param poolId The pool ID to withdraw from
     * @param currency The ERC20 currency to withdraw
     * @param amount The amount to withdraw
     * @param recipient The address to send tokens to
     */
    function withdrawAccumulatedERC20(
        PoolId poolId,
        Currency currency,
        uint256 amount,
        address recipient
    ) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than zero");
        require(Currency.unwrap(currency) != address(0), "Use withdrawAccumulatedETH for ETH");

        uint256 available = accumulatedTokens[poolId][currency];
        require(available >= amount, "Insufficient accumulated tokens");

        // Update accumulated tokens
        accumulatedTokens[poolId][currency] -= amount;

        // Transfer ERC20 tokens to recipient
        IERC20Minimal(Currency.unwrap(currency)).transfer(recipient, amount);

        emit ERC20Withdrawn(poolId, currency, amount, recipient);
    }

    // ============ View Functions ============

    /**
     * @notice Calculate potential arbitrage opportunity for a given swap
     * @param key The pool key
     * @param params The swap parameters
     * @return arbitrageAmount The arbitrage opportunity amount
     * @return hookShare The amount the hook would capture
     * @return shouldInterfere Whether the hook would interfere (arbitrageAmount > 0)
     */
    function calculateArbitrageOpportunity(PoolKey calldata key, SwapParams calldata params)
        external
        view
        returns (uint256 arbitrageAmount, uint256 hookShare, bool shouldInterfere)
    {
        if (params.amountSpecified >= 0) return (0, 0, false);

        bytes32 priceId0 = pythPriceIds[key.currency0];
        bytes32 priceId1 = pythPriceIds[key.currency1];
        
        if (priceId0 == bytes32(0) || priceId1 == bytes32(0)) return (0, 0, false);

        (uint256 oracleLowerBound, uint256 oracleUpperBound, bool valid) = 
            SimplifiedOracleLib.calculatePriceRatioBounds(
                pythOracle, priceId0, priceId1, stalenessThreshold
            );

        if (!valid) return (0, 0, false);

        uint256 poolPrice = _getPoolPriceNormalized(key);
        if (poolPrice == 0) return (0, 0, false);

        arbitrageAmount = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice,
            oracleLowerBound,
            oracleUpperBound,
            uint256(-params.amountSpecified),
            params.zeroForOne
        );

        hookShare = SimplifiedArbitrageLib.calculateHookShare(arbitrageAmount, rhoBps);
        shouldInterfere = arbitrageAmount > 0;
    }

    /**
     * @notice Get current parameters
     * @return _rhoBps Current rho share in basis points
     * @return _stalenessThreshold Current staleness threshold in seconds
     */
    function getParameters() external view returns (uint256 _rhoBps, uint256 _stalenessThreshold) {
        return (rhoBps, stalenessThreshold);
    }

    /**
     * @notice Get accumulated tokens for a pool and currency
     * @param poolId The pool ID
     * @param currency The currency
     * @return amount The accumulated amount
     */
    function getAccumulatedTokens(PoolId poolId, Currency currency) external view returns (uint256) {
        return accumulatedTokens[poolId][currency];
    }

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {
        // Contract can receive ETH for arbitrage capture
    }

    // ============ Hook Permissions ============

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Events ============

    /**
     * @notice Emitted when arbitrage is captured during a swap
     * @param poolId The pool ID
     * @param currency The input currency
     * @param hookShare The amount captured by the hook
     * @param arbitrageOpportunity The total arbitrage opportunity detected
     * @param zeroForOne The swap direction
     */
    event ArbitrageCaptured(
        PoolId indexed poolId,
        Currency indexed currency,
        uint256 hookShare,
        uint256 arbitrageOpportunity,
        bool zeroForOne
    );

    /**
     * @notice Emitted when hook parameters are updated
     * @param oldRhoBps The previous rho share in basis points
     * @param newRhoBps The new rho share in basis points
     * @param oldStaleness The previous staleness threshold
     * @param newStaleness The new staleness threshold
     */
    event ParametersUpdated(
        uint256 oldRhoBps,
        uint256 newRhoBps,
        uint256 oldStaleness,
        uint256 newStaleness
    );

    /**
     * @notice Emitted when a price ID is updated for a currency
     * @param currency The currency whose price ID was updated
     * @param oldPriceId The previous price ID
     * @param newPriceId The new price ID
     */
    event PriceIdUpdated(Currency indexed currency, bytes32 oldPriceId, bytes32 newPriceId);

    /**
     * @notice Emitted when accumulated ETH is withdrawn
     * @param poolId The pool ID
     * @param amount The amount withdrawn in wei
     * @param recipient The recipient address
     */
    event ETHWithdrawn(PoolId indexed poolId, uint256 amount, address indexed recipient);

    /**
     * @notice Emitted when accumulated ERC20 tokens are withdrawn
     * @param poolId The pool ID
     * @param currency The currency withdrawn
     * @param amount The amount withdrawn
     * @param recipient The recipient address
     */
    event ERC20Withdrawn(PoolId indexed poolId, Currency indexed currency, uint256 amount, address indexed recipient);
} 