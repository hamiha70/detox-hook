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
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IPyth, PythStructs } from "./libraries/PythLibrary.sol";
import { HookLibrary } from "./libraries/HookLibrary.sol";
import { ArbitrageLib } from "./libraries/ArbitrageLib.sol";
import { OracleLib } from "./libraries/OracleLib.sol";

contract DetoxHook is BaseHook {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;

    // Configuration constants
    uint256 private constant RHO_BPS = 8000; // 80% hook share in basis points
    uint256 private constant PRICE_PRECISION = 1e8; // 8 decimal precision like USDC
    uint256 private constant STALENESS_THRESHOLD = 60; // Oracle staleness limit in seconds
    uint256 private constant BASIS_POINTS = 10000; // 100% in basis points

    // Chain-specific constants
    address private constant USDC_ON_ARBITRUM = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address private constant PYTH_ORACLE_ON_ARBITRUM_SEPOLIA = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF;
    bytes32 private constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 private constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    // Contract state
    IPyth public immutable pythOracle;
    address public immutable owner;
    mapping(Currency => bytes32) public pythPriceIds;

    // Mapping to track accumulated tokens per pool and token
    mapping(PoolId => mapping(Currency => uint256)) public accumulatedTokens;

    // Configurable parameters
    uint256 public rhoBps;
    uint256 public stalenessThreshold;

    constructor(IPoolManager _poolManager, address _owner, address _oracle) BaseHook(_poolManager) {
        owner = _owner;
        
        // Initialize configurable parameters
        rhoBps = RHO_BPS;
        stalenessThreshold = STALENESS_THRESHOLD;

        // If oracle is provided, use it; otherwise use default logic
        if (_oracle != address(0)) {
            pythOracle = IPyth(_oracle);
        } else if (block.chainid == 421614) {
            // Only initialize Pyth oracle on Arbitrum Sepolia (chain ID 421614)
            pythOracle = IPyth(PYTH_ORACLE_ON_ARBITRUM_SEPOLIA);
        } else {
            // On other chains (like Anvil), set to zero address
            pythOracle = IPyth(address(0));
        }

        // Initialize the price oracle mappings for the currency pairs we need
        pythPriceIds[Currency.wrap(address(0))] = ETH_USD_PRICE_ID;
        pythPriceIds[Currency.wrap(USDC_ON_ARBITRUM)] = USDC_USD_PRICE_ID;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // 1. Early exit for exact output swaps - no interference
        if (params.amountSpecified >= 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 2. Get currencies and oracle prices with confidence
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;

        (uint256 inputPrice, uint256 inputConf, bool inputValid) = _getOraclePriceWithConfidence(inputCurrency);
        (uint256 outputPrice, uint256 outputConf, bool outputValid) = _getOraclePriceWithConfidence(outputCurrency);

        // 3. Fallback to no interference if oracle fails
        if (!inputValid || !outputValid) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 4. Get pool price and prepare arbitrage parameters
        uint256 poolPrice = _getPoolPrice(key);
        if (poolPrice == 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 5. Use ArbitrageLib to analyze opportunity with confidence bounds
        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            ArbitrageLib.ArbitrageParams({
                poolPrice: poolPrice,
                inputPrice: inputPrice,
                outputPrice: outputPrice,
                inputPriceConf: inputConf,
                outputPriceConf: outputConf,
                exactInputAmount: uint256(-params.amountSpecified),
                zeroForOne: params.zeroForOne
            }),
            rhoBps
        );

        // 6. Check if we should interfere (both confidence and threshold requirements)
        if (!result.shouldInterfere) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 7. Execute arbitrage capture
        return _executeArbitrageCapture(key, params, result.hookShare);
    }

    /**
     * @notice Get oracle price with confidence for a currency
     * @param currency The currency to get price for
     * @return price The price in PRICE_PRECISION format
     * @return confidence The confidence in PRICE_PRECISION format
     * @return valid Whether the price is valid and fresh
     */
    function _getOraclePriceWithConfidence(Currency currency) internal view returns (uint256 price, uint256 confidence, bool valid) {
        bytes32 priceId = pythPriceIds[currency];
        return OracleLib.getOraclePriceWithConfidence(pythOracle, priceId, stalenessThreshold);
    }

    /**
     * @notice Get oracle price for a currency (legacy function for backward compatibility)
     * @param currency The currency to get price for
     * @return price The price in PRICE_PRECISION format (8 decimals)
     * @return valid Whether the price is valid and fresh
     */
    function _getOraclePrice(Currency currency) internal view returns (uint256 price, bool valid) {
        (price, , valid) = _getOraclePriceWithConfidence(currency);
    }

    /**
     * @notice Get pool price in comparable format
     * @param key The pool key
     * @return price Pool price as currency1/currency0 ratio with PRICE_PRECISION
     */
    function _getPoolPrice(PoolKey memory key) internal view returns (uint256) {
        uint160 sqrtPriceX96 = HookLibrary.getPoolPrice(poolManager, key);
        if (sqrtPriceX96 == 0) return 0;

        // Convert sqrtPriceX96 to currency1/currency0 price with 18 decimals
        uint256 price = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);

        // Normalize to PRICE_PRECISION (8 decimals)
        return FullMath.mulDiv(price, PRICE_PRECISION, 1e18);
    }

    /**
     * @notice Execute arbitrage capture by taking hook's share
     * @param key The pool key
     * @param params The swap parameters
     * @param hookShare The amount the hook should capture
     * @return selector The function selector
     * @return delta The BeforeSwapDelta
     * @return fee The dynamic fee (unused)
     */
    function _executeArbitrageCapture(PoolKey calldata key, SwapParams calldata params, uint256 hookShare)
        internal
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Determine input currency
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;

        // Take hook's share from pool
        poolManager.take(inputCurrency, address(this), hookShare);

        // Track accumulated tokens
        PoolId poolId = key.toId();
        accumulatedTokens[poolId][inputCurrency] += hookShare;

        // Create delta to reduce swap amount by hook's share
        BeforeSwapDelta delta = params.zeroForOne
            ? toBeforeSwapDelta(int128(int256(hookShare)), 0)
            : toBeforeSwapDelta(0, int128(int256(hookShare)));

        return (BaseHook.beforeSwap.selector, delta, 0);
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

        rhoBps = _rhoBps;
        stalenessThreshold = _stalenessThreshold;
    }

    /**
     * @notice Set price ID for a currency (only owner)
     * @param currency The currency to set price ID for
     * @param priceId The Pyth price ID
     */
    function setPriceId(Currency currency, bytes32 priceId) external onlyOwner {
        pythPriceIds[currency] = priceId;
    }

    // ============ View Functions ============

    /**
     * @notice Get the current oracle price for a currency (external view function)
     * @param currency The currency to get price for
     * @return price The price in PRICE_PRECISION format
     * @return valid Whether the price is valid
     * @return publishTime The timestamp when the price was published
     */
    function getOraclePrice(Currency currency) external view returns (uint256 price, bool valid, uint256 publishTime) {
        (price, valid) = _getOraclePrice(currency);
        
        if (valid) {
            bytes32 priceId = pythPriceIds[currency];
            publishTime = OracleLib.getPublishTime(pythOracle, priceId);
        }
    }

    /**
     * @notice Get the current oracle price with confidence for a currency
     * @param currency The currency to get price for
     * @return price The price in PRICE_PRECISION format
     * @return confidence The confidence in PRICE_PRECISION format
     * @return valid Whether the price is valid
     * @return publishTime The timestamp when the price was published
     */
    function getOraclePriceWithConfidence(Currency currency) 
        external 
        view 
        returns (uint256 price, uint256 confidence, bool valid, uint256 publishTime) 
    {
        (price, confidence, valid) = _getOraclePriceWithConfidence(currency);

        if (valid) {
            bytes32 priceId = pythPriceIds[currency];
            publishTime = OracleLib.getPublishTime(pythOracle, priceId);
        }
    }

    /**
     * @notice Calculate potential arbitrage opportunity for a given swap (view function)
     * @param key The pool key
     * @param params The swap parameters
     * @return arbitrageOpp The arbitrage opportunity amount (confidence-adjusted)
     * @return hookShare The amount the hook would capture
     * @return shouldInterfere Whether the hook would interfere
     * @return isOutsideConfidenceBand Whether pool price is outside oracle confidence band
     */
    function calculateArbitrageOpportunity(PoolKey calldata key, SwapParams calldata params)
        external
        view
        returns (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand)
    {
        if (params.amountSpecified >= 0) return (0, 0, false, false);

        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;

        (uint256 inputPrice, uint256 inputConf, bool inputValid) = _getOraclePriceWithConfidence(inputCurrency);
        (uint256 outputPrice, uint256 outputConf, bool outputValid) = _getOraclePriceWithConfidence(outputCurrency);

        if (!inputValid || !outputValid) return (0, 0, false, false);

        uint256 poolPrice = _getPoolPrice(key);
        if (poolPrice == 0) return (0, 0, false, false);

        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            ArbitrageLib.ArbitrageParams({
                poolPrice: poolPrice,
                inputPrice: inputPrice,
                outputPrice: outputPrice,
                inputPriceConf: inputConf,
                outputPriceConf: outputConf,
                exactInputAmount: uint256(-params.amountSpecified),
                zeroForOne: params.zeroForOne
            }),
            rhoBps
        );

        return (result.arbitrageOpportunity, result.hookShare, result.shouldInterfere, result.isOutsideConfidenceBand);
    }

    /**
     * @notice Get current parameters
     * @return rhoBps Current rho share in basis points
     * @return stalenessThreshold Current staleness threshold in seconds
     */
    function getParameters() external view returns (uint256, uint256) {
        return (rhoBps, stalenessThreshold);
    }

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
} 