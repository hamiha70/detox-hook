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
import { SimplifiedArbitrageLib } from "./libraries/SimplifiedArbitrageLib.sol";
import { OracleLib } from "./libraries/OracleLib.sol";
import { IERC20Minimal } from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import { PriceRegistry } from "./PriceRegistry.sol";
import "forge-std/console.sol";

contract DetoxHook is BaseHook {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;

    // Configuration constants
    uint256 private constant RHO_BPS = 8000; // 80% hook share in basis points
    uint256 private constant PRICE_PRECISION = 1e8; // 8 decimal precision like USDC
    uint256 private constant STALENESS_THRESHOLD = 60; // Oracle staleness limit in seconds
    uint256 private constant BASIS_POINTS = 10000; // 100% in basis points

    // Contract state
    IPyth public immutable pythOracle;
    PriceRegistry public immutable priceRegistry;
    address public immutable owner;

    // Mapping to track accumulated tokens per pool and token
    mapping(PoolId => mapping(Currency => uint256)) public accumulatedTokens;

    // Configurable parameters
    uint256 public rhoBps;
    uint256 public stalenessThreshold;

    /**
     * @notice Initialize DetoxHook with modular architecture
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
        require(_owner != address(0), "Invalid owner address");
        require(_oracle != address(0), "Invalid oracle address");
        require(_priceRegistry != address(0), "Invalid price registry address");
        
        owner = _owner;
        pythOracle = IPyth(_oracle);
        priceRegistry = PriceRegistry(_priceRegistry);
        
        // Initialize configurable parameters
        rhoBps = RHO_BPS;
        stalenessThreshold = STALENESS_THRESHOLD;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // 0. Decode priceUpdate from hookData if present
        bytes[] memory priceUpdate;
        if (hookData.length > 0) {
            priceUpdate = abi.decode(hookData, (bytes[]));
        }
        // 1. Early exit for exact output swaps - no interference
        if (params.amountSpecified >= 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }
        // 2. Get currencies
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;
        // --- DIRECTIONALITY EXPLANATION ---
        // For zeroForOne (ETH->USDC):
        //   - poolPrice: USDC/ETH (how many USDC per 1 ETH)
        //   - currency0Price: ETH/USD (from oracle)
        //   - currency1Price: USDC/USD (from oracle)
        // For oneForZero (USDC->ETH):
        //   - poolPrice: USDC/ETH (how many USDC per 1 ETH)
        //   - currency0Price: ETH/USD (from oracle)
        //   - currency1Price: USDC/USD (from oracle)
        // --- NATIVE ETH NOTE ---
        // In Uniswap v4, Currency type abstracts both native ETH (address(0)) and ERC20. If inputCurrency or outputCurrency is address(0), it means native ETH. If not, it's an ERC20. This is important for funding and for correct price ID mapping.
        // --- Fetch Pyth prices for both currencies ---
        // Get prices for both currencies in currency0/currency1 order (consistent regardless of swap direction)
        (uint256 currency0PriceUSD, uint256 currency0Conf, bool currency0Valid) = _getOraclePriceWithConfidence(key.currency0);
        (uint256 currency1PriceUSD, uint256 currency1Conf, bool currency1Valid) = _getOraclePriceWithConfidence(key.currency1);
        
        // Logging for debugging oracle validity
        bytes32 currency0PriceId = priceRegistry.getPriceId(Currency.unwrap(key.currency0));
        bytes32 currency1PriceId = priceRegistry.getPriceId(Currency.unwrap(key.currency1));
        
        if (currency0PriceId != bytes32(0)) {
            PythStructs.Price memory currency0Raw = IPyth(pythOracle).getPriceUnsafe(currency0PriceId);
            console.log("[HOOK] CURRENCY0_RAW.price:"); console.logInt(currency0Raw.price);
            console.log("[HOOK] CURRENCY0_RAW.conf:"); console.logUint(currency0Raw.conf);
            console.log("[HOOK] CURRENCY0_RAW.expo:"); console.logInt(currency0Raw.expo);
            console.log("[HOOK] CURRENCY0_RAW.publishTime:"); console.logUint(currency0Raw.publishTime);
        }
        
        if (currency1PriceId != bytes32(0)) {
            PythStructs.Price memory currency1Raw = IPyth(pythOracle).getPriceUnsafe(currency1PriceId);
            console.log("[HOOK] CURRENCY1_RAW.price:"); console.logInt(currency1Raw.price);
            console.log("[HOOK] CURRENCY1_RAW.conf:"); console.logUint(currency1Raw.conf);
            console.log("[HOOK] CURRENCY1_RAW.expo:"); console.logInt(currency1Raw.expo);
            console.log("[HOOK] CURRENCY1_RAW.publishTime:"); console.logUint(currency1Raw.publishTime);
        }
        
        console.log("[HOOK] block.timestamp:"); console.logUint(block.timestamp);
        console.log("[HOOK] stalenessThreshold:"); console.logUint(stalenessThreshold);
        console.log("[HOOK] currency0Valid:"); console.logBool(currency0Valid);
        console.log("[HOOK] currency1Valid:"); console.logBool(currency1Valid);
        require(currency0Valid && currency1Valid, "Oracle prices invalid");
        
        // 2. Calculate prices for arbitrage analysis
        // Convert to ARBITRAGE_PRECISION (18 decimals) for ArbitrageLib
        uint256 currency0Price = FullMath.mulDiv(currency0PriceUSD, 1e18, PRICE_PRECISION);
        uint256 currency1Price = FullMath.mulDiv(currency1PriceUSD, 1e18, PRICE_PRECISION);
        
        // Granular logging: Oracle prices and confidence
        console.log("[HOOK] inputCurrency (should be asset IN):");
        console.logAddress(Currency.unwrap(inputCurrency));
        console.log("[HOOK] outputCurrency (should be asset OUT):");
        console.logAddress(Currency.unwrap(outputCurrency));
        console.log("[HOOK] currency0PriceUSD (8 decimals):");
        console.logUint(currency0PriceUSD);
        console.log("[HOOK] currency1PriceUSD (8 decimals):");
        console.logUint(currency1PriceUSD);
        console.log("[HOOK] currency0Conf (8 decimals):");
        console.logUint(currency0Conf);
        console.log("[HOOK] currency1Conf (8 decimals):");
        console.logUint(currency1Conf);
        console.log("[HOOK] currency0Price (18 decimals):");
        console.logUint(currency0Price);
        console.log("[HOOK] currency1Price (18 decimals):");
        console.logUint(currency1Price);

        // 3. Get pool price and prepare arbitrage parameters
        uint256 poolPrice = _getPoolPrice(key);
        if (poolPrice == 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }
        // Granular logging: Pool price
        console.log("[HOOK] poolPrice");
        console.logUint(poolPrice);
        console.log("[HOOK] amountSpecified");
        console.logInt(params.amountSpecified);
        console.log("[HOOK] zeroForOne");
        console.logBool(params.zeroForOne);

        // 4. Use SimplifiedArbitrageLib to analyze opportunity with confidence bounds
        // Convert poolPrice from PRICE_PRECISION (8 decimals) to ARBITRAGE_PRECISION (18 decimals)
        uint256 poolPriceInArbitragePrecision = FullMath.mulDiv(poolPrice, 1e18, PRICE_PRECISION);
        
        // Calculate oracle bounds: currency1/currency0 ratio with confidence intervals
        // Lower bound: (currency1USD - currency1Conf) / (currency0USD + currency0Conf)
        // Upper bound: (currency1USD + currency1Conf) / (currency0USD - currency0Conf)
        uint256 currency0Lower = currency0PriceUSD > currency0Conf ? currency0PriceUSD - currency0Conf : 1;
        uint256 currency0Upper = currency0PriceUSD + currency0Conf;
        uint256 currency1Lower = currency1PriceUSD > currency1Conf ? currency1PriceUSD - currency1Conf : 1;
        uint256 currency1Upper = currency1PriceUSD + currency1Conf;
        
        // Ensure non-zero values to avoid division by zero
        if (currency0Lower == 0 || currency0Upper == 0) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }
        
        // Calculate oracle bounds in 18-decimal precision
        uint256 oracleLower = FullMath.mulDiv(currency0Lower, 1e18, currency1Upper);
        uint256 oracleUpper = FullMath.mulDiv(currency0Upper, 1e18, currency1Lower);
        
        console.log("[SIMPLIFIED] poolPrice (18 decimals):");
        console.logUint(poolPriceInArbitragePrecision);
        console.log("[SIMPLIFIED] oracleLower (18 decimals):");
        console.logUint(oracleLower);
        console.log("[SIMPLIFIED] oracleUpper (18 decimals):");
        console.logUint(oracleUpper);
        
        // Calculate arbitrage opportunity
        uint256 swapAmount = uint256(-params.amountSpecified);
        uint256 arbitrageAmount = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPriceInArbitragePrecision,
            oracleLower,
            oracleUpper,
            swapAmount,
            params.zeroForOne
        );
        
        // Calculate hook share if arbitrage exists
        uint256 hookShare = SimplifiedArbitrageLib.calculateHookShare(arbitrageAmount, rhoBps);
        bool shouldInterfere = arbitrageAmount > 0;
        bool isOutsideConfidenceBand = (poolPriceInArbitragePrecision < oracleLower) || (poolPriceInArbitragePrecision > oracleUpper);
        
        // Granular logging: Simplified arbitrage result
        console.log("[SIMPLIFIED] arbitrageAmount:");
        console.logUint(arbitrageAmount);
        console.log("[SIMPLIFIED] shouldInterfere:");
        console.logBool(shouldInterfere);
        console.log("[SIMPLIFIED] hookShare:");
        console.logUint(hookShare);
        console.log("[SIMPLIFIED] isOutsideConfidenceBand:");
        console.logBool(isOutsideConfidenceBand);
        // Additional logging for clarity
        console.log("[HOOK] --- Arbitrage Opportunity (input units) ---");
        console.logUint(arbitrageAmount);
        console.log("[HOOK] --- Hook Share (input units) ---");
        console.logUint(hookShare);

        // 5. Check if we should interfere
        if (!shouldInterfere) {
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // 6. Execute arbitrage capture
        return _executeArbitrageCapture(key, params, hookShare);
    }

    /**
     * @notice Get oracle price with confidence for a currency (view-only, for use in view functions)
     * @param currency The currency to get price for
     * @return price The price in PRICE_PRECISION format
     * @return confidence The confidence in PRICE_PRECISION format
     * @return valid Whether the price is valid
     */
    function _getOraclePriceWithConfidence(Currency currency) internal view returns (uint256 price, uint256 confidence, bool valid) {
        bytes32 priceId = priceRegistry.getPriceId(Currency.unwrap(currency));
        if (priceId == bytes32(0)) {
            return (0, 0, false); // Currency not registered in price registry
        }
        return OracleLib.getOraclePriceWithConfidence(pythOracle, priceId, stalenessThreshold);
    }

    /**
     * @notice Get fresh oracle price with confidence (state-changing, for use in _beforeSwap)
     * @param currency The currency to get price for
     * @param priceUpdate The price update data
     * @return price The price in PRICE_PRECISION format
     * @return confidence The confidence in PRICE_PRECISION format
     * @return valid Whether the price is valid and fresh
     */
    function _getFreshOraclePriceWithConfidence(Currency currency, bytes[] memory priceUpdate) internal returns (uint256 price, uint256 confidence, bool valid) {
        bytes32 priceId = priceRegistry.getPriceId(Currency.unwrap(currency));
        if (priceId == bytes32(0)) {
            return (0, 0, false); // Currency not registered in price registry
        }
        return OracleLib.getFreshOraclePrice(pythOracle, priceId, stalenessThreshold, priceUpdate);
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
        console.log("[POOL] sqrtPriceX96");
        console.logUint(uint256(sqrtPriceX96));
        if (sqrtPriceX96 == 0) return 0;
        // Convert sqrtPriceX96 to currency1/currency0 price with 18 decimals
        uint256 price = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
        console.log("[POOL] price");
        console.logUint(price);
        // Normalize to PRICE_PRECISION (8 decimals)
        uint256 normPrice = FullMath.mulDiv(price, PRICE_PRECISION, 1e18);
        console.log("[POOL] normPrice");
        console.logUint(normPrice);
        return normPrice;
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

        // Create delta to reduce the swap amount by hook's share
        // For exact input swaps, hookShare reduces the magnitude of amountSpecified
        // This should work for both directions since amountSpecified is always the input
        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(hookShare)), 0);

        // Emit arbitrage capture event
        // Note: We don't have the full arbitrage opportunity here, so we'll emit hookShare as a proxy
        emit ArbitrageCaptured(poolId, inputCurrency, hookShare, hookShare, params.zeroForOne);
        
        // Logging for debugging (Forge console: max 3 params, use type-specific log functions)
        console.log("[HOOK] beforeSwap: poolId");
        console.logBytes32(PoolId.unwrap(poolId));
        console.log("[HOOK] inputCurrency");
        console.logAddress(Currency.unwrap(inputCurrency));
        console.log("[HOOK] amountSpecified");
        console.logInt(params.amountSpecified);
        console.log("[HOOK] accumulatedTokens after update:");
        console.logUint(accumulatedTokens[poolId][inputCurrency]);

        // Additional logging for what is actually captured
        console.log("[HOOK] --- Captured by Hook (input units) ---");
        console.logUint(hookShare);

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

        uint256 oldRhoBps = rhoBps;
        uint256 oldStaleness = stalenessThreshold;

        rhoBps = _rhoBps;
        stalenessThreshold = _stalenessThreshold;

        emit ParametersUpdated(oldRhoBps, _rhoBps, oldStaleness, _stalenessThreshold);
    }

    /**
     * @notice Get the price registry contract address
     * @return Address of the price registry contract
     */
    function getPriceRegistry() external view returns (address) {
        return address(priceRegistry);
    }

    /**
     * @notice Withdraw accumulated ETH from arbitrage capture (only owner)
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
        
        // Logging for debugging (Forge console: max 3 params, use type-specific log functions)
        console.log("[HOOK] Withdrawn (ETH)");
        console.logBytes32(PoolId.unwrap(poolId));
        console.logUint(amount);
        console.logAddress(recipient);
        console.log("[HOOK] accumulatedTokens after withdraw:");
        console.logUint(accumulatedTokens[poolId][ethCurrency]);
        
        emit ETHWithdrawn(poolId, amount, recipient);
    }

    /**
     * @notice Withdraw accumulated ERC20 tokens from arbitrage capture (only owner)
     * @param poolId The pool ID to withdraw from
     * @param currency The ERC20 currency to withdraw (must not be ETH)
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
        
        // Logging for debugging (Forge console: max 3 params, use type-specific log functions)
        console.log("[HOOK] Withdrawn (ERC20)");
        console.logBytes32(PoolId.unwrap(poolId));
        console.logAddress(Currency.unwrap(currency));
        console.logUint(amount);
        console.logAddress(recipient);
        console.log("[HOOK] accumulatedTokens after withdraw:");
        console.logUint(accumulatedTokens[poolId][currency]);
        
        emit ERC20Withdrawn(poolId, currency, amount, recipient);
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
            bytes32 priceId = priceRegistry.getPriceId(Currency.unwrap(currency));
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
            bytes32 priceId = priceRegistry.getPriceId(Currency.unwrap(currency));
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

        (uint256 currency0PriceUSD, uint256 currency0Conf, bool currency0Valid) = _getOraclePriceWithConfidence(key.currency0);
        (uint256 currency1PriceUSD, uint256 currency1Conf, bool currency1Valid) = _getOraclePriceWithConfidence(key.currency1);

        if (!currency0Valid || !currency1Valid) return (0, 0, false, false);

        uint256 poolPrice = _getPoolPrice(key);
        if (poolPrice == 0) return (0, 0, false, false);

        // Convert poolPrice from PRICE_PRECISION (8 decimals) to ARBITRAGE_PRECISION (18 decimals)
        uint256 poolPriceInArbitragePrecision = FullMath.mulDiv(poolPrice, 1e18, PRICE_PRECISION);
        
        // Calculate oracle bounds: currency1/currency0 ratio with confidence intervals
        uint256 currency0Lower = currency0PriceUSD > currency0Conf ? currency0PriceUSD - currency0Conf : 1;
        uint256 currency0Upper = currency0PriceUSD + currency0Conf;
        uint256 currency1Lower = currency1PriceUSD > currency1Conf ? currency1PriceUSD - currency1Conf : 1;
        uint256 currency1Upper = currency1PriceUSD + currency1Conf;
        
        // Ensure non-zero values to avoid division by zero
        if (currency0Lower == 0 || currency0Upper == 0) return (0, 0, false, false);
        
        // Calculate oracle bounds in 18-decimal precision
        uint256 oracleLower = FullMath.mulDiv(currency0Lower, 1e18, currency1Upper);
        uint256 oracleUpper = FullMath.mulDiv(currency0Upper, 1e18, currency1Lower);

        // Calculate arbitrage opportunity using SimplifiedArbitrageLib
        arbitrageOpp = SimplifiedArbitrageLib.calculateArbitrageAmount(
            poolPriceInArbitragePrecision,
            oracleLower,
            oracleUpper,
            uint256(-params.amountSpecified),
            params.zeroForOne
        );

        hookShare = SimplifiedArbitrageLib.calculateHookShare(arbitrageOpp, rhoBps);
        shouldInterfere = arbitrageOpp > 0;
        isOutsideConfidenceBand = (poolPriceInArbitragePrecision < oracleLower) || (poolPriceInArbitragePrecision > oracleUpper);

        return (arbitrageOpp, hookShare, shouldInterfere, isOutsideConfidenceBand);
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
     * @notice Emitted when accumulated ETH are withdrawn
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