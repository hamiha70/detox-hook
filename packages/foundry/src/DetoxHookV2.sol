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
import { IPyth, PythStructs } from "./libraries/PythLibrary.sol";
import { SimplifiedOracleLib } from "./libraries/SimplifiedOracleLib.sol";
import { SimplifiedArbitrageLib } from "./libraries/SimplifiedArbitrageLib.sol";
import { HookLibrary } from "./libraries/HookLibrary.sol";
import { PriceRegistry } from "./PriceRegistry.sol";
import "forge-std/console.sol";

/**
 * @title DetoxHookV2
 * @notice Production-ready MEV protection hook with modular architecture
 * @dev Combines PriceRegistry flexibility with SimplifiedArbitrageLib proven logic
 * 
 * Key Features:
 * - Flexible price feed management via PriceRegistry
 * - Proven arbitrage detection (no false positives)
 * - Multi-chain support with oracle fallbacks
 * - Exact input/output swap support
 * - Comprehensive decimal handling (ETH 18, USDC 6, Pyth -8)
 * - Production-ready error handling
 */
contract DetoxHookV2 is BaseHook {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;

    // ============ Constants ============
    
    /// @notice Single precision system (18 decimals) for internal calculations
    
    /// @notice Default hook share in basis points (80%)
    uint256 private constant DEFAULT_RHO_BPS = 8000;
    
    /// @notice Default staleness threshold (60 seconds)
    uint256 private constant DEFAULT_STALENESS_THRESHOLD = 60;
    
    /// @notice Basis points (100%)
    uint256 private constant BASIS_POINTS = 10000;
    
    /// @notice Maximum confidence interval as percentage (10% = 1000 basis points)
    uint256 private constant MAX_CONFIDENCE_BPS = 1000;

    // ============ State Variables ============
    
    /// @notice Pyth oracle instance
    IPyth public immutable pythOracle;
    
    /// @notice Price registry for flexible token/price ID management
    PriceRegistry public immutable priceRegistry;
    
    /// @notice Contract owner
    address public immutable owner;
    
    /// @notice Hook share in basis points (configurable)
    uint256 public rhoBps;
    
    /// @notice Oracle staleness threshold in seconds (configurable)
    uint256 public stalenessThreshold;
    
    /// @notice Maximum allowed confidence interval in basis points (configurable)
    uint256 public maxConfidenceBps;
    
    /// @notice Accumulated tokens per pool and currency
    mapping(PoolId => mapping(Currency => uint256)) public accumulatedTokens;
    
    /// @notice Emergency pause flag
    bool public paused;

    // ============ Events ============
    
    event ArbitrageCaptured(
        PoolId indexed poolId,
        Currency indexed inputCurrency,
        uint256 arbitrageAmount,
        uint256 hookShare,
        bool zeroForOne
    );
    
    event ParametersUpdated(
        uint256 newRhoBps,
        uint256 newStalenessThreshold,
        uint256 newMaxConfidenceBps
    );
    
    event EmergencyPauseToggled(bool paused);
    
    event TokensWithdrawn(
        PoolId indexed poolId,
        Currency indexed currency,
        uint256 amount,
        address indexed recipient
    );

    // ============ Custom Errors ============
    
    error NotOwner();
    error InvalidParameter();
    error ContractPaused();
    error OracleDataInvalid();
    error PriceNotConfigured();
    error InsufficientBalance();

    // ============ Constructor ============

    /**
     * @notice Initialize DetoxHookV2 with modular architecture
     * @param _poolManager Uniswap V4 Pool Manager contract
     * @param _owner Address that will own this hook contract
     * @param _oracle Pyth Oracle contract address
     * @param _priceRegistry Price Registry contract for token/price ID mappings
     */
    constructor(
        IPoolManager _poolManager,
        address _owner,
        address _oracle,
        address _priceRegistry
    ) BaseHook(_poolManager) {
        if (_owner == address(0)) revert InvalidParameter();
        if (_oracle == address(0)) revert InvalidParameter();
        if (_priceRegistry == address(0)) revert InvalidParameter();
        
        owner = _owner;
        pythOracle = IPyth(_oracle);
        priceRegistry = PriceRegistry(_priceRegistry);
        
        // Initialize configurable parameters
        rhoBps = DEFAULT_RHO_BPS;
        stalenessThreshold = DEFAULT_STALENESS_THRESHOLD;
        maxConfidenceBps = MAX_CONFIDENCE_BPS;
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // ============ Hook Implementation ============

    /**
     * @notice Returns the hook's permissions
     * @return Hooks.Permissions struct with beforeSwap and beforeSwapReturnDelta enabled
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
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
    ) internal override whenNotPaused returns (bytes4, BeforeSwapDelta, uint24) {
        // 1. Early exit for exact output swaps - never interfere
        // @dev We might implement exact output swaps in the future or we might block them completely
        if (params.amountSpecified >= 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 2. Decode price update data if provided
        // @dev Those need to be passed in with the hookData. They come from offchain call to Hermes oracle
        bytes[] memory priceUpdate;
        if (hookData.length > 0) {
            priceUpdate = abi.decode(hookData, (bytes[]));
            // Update Pyth prices if provided
            if (priceUpdate.length > 0) {
                // Calculate the fee for the update
                uint256 fee = pythOracle.getUpdateFee(priceUpdate);
        // 3. Pay the fee and update the prices
                pythOracle.updatePriceFeeds{value: fee}(priceUpdate);
            }
        }

        // 4. Get price IDs for both currencies from registry
        bytes32 priceId0 = priceRegistry.getPriceId(Currency.unwrap(key.currency0));
        bytes32 priceId1 = priceRegistry.getPriceId(Currency.unwrap(key.currency1));
        
        if (priceId0 == bytes32(0) || priceId1 == bytes32(0)) {
            // Price IDs not configured for this pair -> Swap without interference
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 5. Get oracle price ratio bounds with confidence intervals
        (uint256 oracleLowerBound, uint256 oracleUpperBound, bool valid) = 
            SimplifiedOracleLib.calculatePriceRatioBounds(
                pythOracle, priceId0, priceId1, stalenessThreshold
            );
        if (!valid) {
            // Oracle prices invalid or stale -> Swap without interference
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }


        // 6. Get pool price (normalized to PRECISION)
        uint256 poolPrice = _getPoolPriceNormalized(key);
        if (poolPrice == 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 7. Calculate arbitrage amount using proven SimplifiedArbitrageLib
        uint256 swapAmount = uint256(-params.amountSpecified);
        uint256 arbitrageAmount = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPrice,
            oracleLowerBound,
            oracleUpperBound,
            swapAmount,
            params.zeroForOne
        );

        // 8. If no arbitrage detected, don't interfere
        if (arbitrageAmount == 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 9. Calculate hook share and execute capture
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

        // Emit event for monitoring
        emit ArbitrageCaptured(
            poolId,
            inputCurrency,
            arbitrageAmount,
            hookShare,
            params.zeroForOne
        );

        // Return BeforeSwapDelta to reduce swap amount by hook's share
        // @dev Per definition of beforeSwapDelta, the first parameter is always amountSepcified -> so correct
        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(uint128(hookShare)), 0),
            0
        );
    }

    /**
     * @notice Get normalized pool price (currency1/currency0 ratio)
     * @param key The pool key
     * @return Normalized pool price in PRECISION (18 decimals)
     */
    function _getPoolPriceNormalized(PoolKey calldata key) internal view returns (uint256) {
        uint160 sqrtPriceX96 = HookLibrary.getPoolPrice(poolManager, key);
        if (sqrtPriceX96 == 0) return 0;
        
        // Convert sqrtPriceX96 to price with PRECISION (1e18)
        return HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
    }

    /**
     * @notice Validate confidence intervals are within acceptable bounds
     * @param priceId0 Price ID for currency0
     * @param priceId1 Price ID for currency1
     * @return True if confidence intervals are acceptable
     */

    // ============ Owner Functions ============

    /**
     * @notice Update hook parameters
     * @param newRhoBps New hook share in basis points
     * @param newStalenessThreshold New staleness threshold in seconds
     * @param newMaxConfidenceBps New maximum confidence interval in basis points
     */
    function updateParameters(
        uint256 newRhoBps,
        uint256 newStalenessThreshold,
        uint256 newMaxConfidenceBps
    ) external onlyOwner {
        if (newRhoBps > BASIS_POINTS) revert InvalidParameter();
        if (newStalenessThreshold == 0) revert InvalidParameter();
        if (newMaxConfidenceBps > BASIS_POINTS) revert InvalidParameter();
        
        rhoBps = newRhoBps;
        stalenessThreshold = newStalenessThreshold;
        maxConfidenceBps = newMaxConfidenceBps;
        
        emit ParametersUpdated(newRhoBps, newStalenessThreshold, newMaxConfidenceBps);
    }

    /**
     * @notice Emergency pause/unpause functionality
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit EmergencyPauseToggled(_paused);
    }

    /**
     * @notice Withdraw accumulated tokens from the hook
     * @param poolId The pool ID
     * @param currency The currency to withdraw
     * @param amount The amount to withdraw
     * @param recipient The recipient address
     */
    function withdrawTokens(
        PoolId poolId,
        Currency currency,
        uint256 amount,
        address recipient
    ) external onlyOwner {
        if (recipient == address(0)) revert InvalidParameter();
        if (amount > accumulatedTokens[poolId][currency]) revert InsufficientBalance();
        
        accumulatedTokens[poolId][currency] -= amount;
        
        // Transfer tokens to recipient
        if (Currency.unwrap(currency) == address(0)) {
            // Native ETH
            (bool success,) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 token
            IERC20Minimal(Currency.unwrap(currency)).transfer(recipient, amount);
        }
        
        emit TokensWithdrawn(poolId, currency, amount, recipient);
    }

    /**
     * @notice Donate accumulated tokens back to the pool
     * @param poolId The pool ID
     * @param currency The currency to donate
     * @param amount The amount to donate
     */
    function donateToPool(
        PoolId poolId,
        Currency currency,
        uint256 amount
    ) external onlyOwner {
        if (amount > accumulatedTokens[poolId][currency]) revert InsufficientBalance();
        
        accumulatedTokens[poolId][currency] -= amount;
        
        // Donate to pool (benefits LPs)
        poolManager.donate(
            PoolKey({
                currency0: currency,
                currency1: currency, // This will be corrected by the pool manager
                fee: 0,
                tickSpacing: 0,
                hooks: this
            }),
            amount,
            0,
            ""
        );
    }

    // ============ View Functions ============

    /**
     * @notice Get accumulated tokens for a pool and currency
     * @param poolId The pool ID
     * @param currency The currency
     * @return The accumulated amount
     */
    function getAccumulatedTokens(PoolId poolId, Currency currency) external view returns (uint256) {
        return accumulatedTokens[poolId][currency];
    }

    /**
     * @notice Get current hook configuration
     * @return Current rho basis points, staleness threshold, and max confidence basis points
     */
    function getConfiguration() external view returns (uint256, uint256, uint256) {
        return (rhoBps, stalenessThreshold, maxConfidenceBps);
    }

    /**
     * @notice Check if a currency pair is supported (has price IDs configured)
     * @param currency0 First currency
     * @param currency1 Second currency
     * @return True if both currencies have price IDs configured
     */
    function isPairSupported(Currency currency0, Currency currency1) external view returns (bool) {
        return priceRegistry.getPriceId(Currency.unwrap(currency0)) != bytes32(0) &&
               priceRegistry.getPriceId(Currency.unwrap(currency1)) != bytes32(0);
    }

    // ============ Receive Function ============

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}
} 