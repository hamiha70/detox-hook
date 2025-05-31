// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { CurrencyLibrary, Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { DetoxHook } from "../src/DetoxHook.sol";
import { IERC20Minimal } from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import { SwapParams, ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { MockPyth, PythStructs } from "../src/libraries/PythLibrary.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract DetoxHookWave2Test is Test, Deployers {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using TickMath for uint160;
    using StateLibrary for IPoolManager;

    DetoxHook hook;
    MockPyth mockOracle;
    address owner = address(0x1234);
    PoolKey poolKey;
    PoolId poolId;

    // Price IDs from DetoxHook
    bytes32 constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    // Test constants
    uint256 constant PRICE_PRECISION = 1e8;
    uint256 constant ETH_PRICE_BASE = 100; // $1.00 in 2 decimal format (to match 1:1 pool)
    uint256 constant USDC_PRICE_BASE = 100; // $1.00 in 2 decimal format

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Deploy mock oracle for testing
        mockOracle = new MockPyth(60, 1); // 60 second validity, 1 wei fee

        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        deployCodeTo("DetoxHook.sol", abi.encode(manager, owner, address(mockOracle)), hookAddress);
        hook = DetoxHook(hookAddress);

        // Create pool key manually
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        poolId = poolKey.toId();
        
        // Initialize the pool
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Add liquidity to the pool
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -9960, 
            tickUpper: 9960, 
            liquidityDelta: 10000e18, 
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(poolKey, liquidityParams, "");

        // Approve tokens for swap router
        IERC20Minimal(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);

        // Set up price mappings for test currencies
        vm.startPrank(owner);
        hook.setPriceId(currency0, ETH_USD_PRICE_ID); // currency0 represents ETH
        hook.setPriceId(currency1, USDC_USD_PRICE_ID); // currency1 represents USDC
        vm.stopPrank();

        // Set standard prices
        setStandardPrices();
    }

    // ============ Helper Functions ============

    function setStandardPrices() internal {
        // Set prices with realistic confidence intervals
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID, 
            int64(int256(ETH_PRICE_BASE * 1e6)), 
            uint64(2 * 1e6), // $2 confidence for ETH
            -8, 
            block.timestamp
        );
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID, 
            int64(int256(USDC_PRICE_BASE * 1e6)), 
            uint64(1e4), // $0.01 confidence for USDC
            -8, 
            block.timestamp
        );
    }

    function setETHPrice(uint256 priceUSD) internal {
        // Set ETH price with $2 confidence interval
        mockOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID, 
            int64(int256(priceUSD * 1e6)), 
            uint64(2 * 1e6), // $2 confidence
            -8, 
            block.timestamp
        );
    }

    function setUSDCPrice(uint256 priceUSD) internal {
        // Set USDC price with $0.01 confidence interval
        mockOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID, 
            int64(int256(priceUSD * 1e6)), 
            uint64(1e4), // $0.01 confidence
            -8, 
            block.timestamp
        );
    }

    function performSwap(bool zeroForOne, uint256 amountIn)
        internal
        returns (uint256 hookBalanceBefore, uint256 hookBalanceAfter)
    {
        Currency inputCurrency = zeroForOne ? currency0 : currency1;

        hookBalanceBefore = IERC20Minimal(Currency.unwrap(inputCurrency)).balanceOf(address(hook));

        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ""
        );

        hookBalanceAfter = IERC20Minimal(Currency.unwrap(inputCurrency)).balanceOf(address(hook));
    }

    // ============ Wave 2 Tests: Arbitrage Detection & Calculation Logic ============

    function testArbitrageCalculationZeroForOne() public {
        // Setup: Pool price = 1:1, Market ETH = $1.10 (pool gives better rate for selling ETH)
        setETHPrice(110); // $1.10 - ETH is more expensive in market
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Debug: Check actual prices
        (uint256 ethPrice, uint256 ethConf, bool ethValid, ) = hook.getOraclePriceWithConfidence(currency0);
        (uint256 usdcPrice, uint256 usdcConf, bool usdcValid, ) = hook.getOraclePriceWithConfidence(currency1);
        
        // Get pool price using HookLibrary
        uint160 sqrtPriceX96 = HookLibrary.getPoolPrice(manager, poolKey);
        uint256 poolPriceRaw = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
        uint256 poolPrice = FullMath.mulDiv(poolPriceRaw, 100000000, 1e18); // Convert to PRICE_PRECISION
        
        uint256 marketPrice = (usdcPrice * 100000000) / ethPrice; // USDC/ETH market price

        console.log("=== Debug Info ===");
        console.log("ETH price:", ethPrice);
        console.log("ETH confidence:", ethConf);
        console.log("USDC price:", usdcPrice);
        console.log("USDC confidence:", usdcConf);
        console.log("Pool price:", poolPrice);
        console.log("Market price:", marketPrice);
        console.log("Pool > Market:", poolPrice > marketPrice);

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== ZeroForOne Arbitrage Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Hook share:", hookShare);
        console.log("Should interfere:", shouldInterfere);

        assertGt(arbitrageOpp, 0, "Should detect arbitrage opportunity when pool price > market price");
        assertTrue(shouldInterfere, "Should interfere when arbitrage is advantageous");
        
        if (shouldInterfere) {
            assertGt(hookShare, 0, "Hook share should be positive when interfering");
            // Hook share should be 80% of arbitrage opportunity
            assertApproxEqRel(hookShare, (arbitrageOpp * 8000) / 10000, 1e15, "Hook share should be 80% of arbitrage");
        }
    }

    function testArbitrageCalculationOneForZero() public {
        // Setup: Pool price = 1:1, Market ETH = $1.10 (10% higher than pool implies)
        setETHPrice(110); // $1.10
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(100 ether), // Swap USDC for ETH
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== OneForZero Arbitrage Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Hook share:", hookShare);
        console.log("Should interfere:", shouldInterfere);

        assertGt(arbitrageOpp, 0, "Should detect arbitrage opportunity when pool price < market price");
        
        if (shouldInterfere) {
            assertGt(hookShare, 0, "Hook share should be positive when interfering");
            // Hook share should be 80% of arbitrage opportunity
            assertApproxEqRel(hookShare, (arbitrageOpp * 8000) / 10000, 1e15, "Hook share should be 80% of arbitrage");
        }
    }

    function testThresholdBehaviorJustBelow() public {
        // Test when arbitrage is not advantageous for swapper
        setETHPrice(90); // $0.90 - not advantageous for zeroForOne (pool gives worse rate)
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== Not Advantageous Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Should interfere:", shouldInterfere);

        // Should not interfere as arbitrage is not advantageous for swapper
        assertFalse(shouldInterfere, "Should not interfere when arbitrage is not advantageous for swapper");
        assertEq(hookShare, 0, "Hook share should be 0 when not interfering");
    }

    function testThresholdBehaviorJustAbove() public {
        // Test when arbitrage is advantageous for swapper
        setETHPrice(110); // $1.10 - advantageous for zeroForOne (pool gives better rate)
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== Advantageous Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Should interfere:", shouldInterfere);

        // Should interfere as arbitrage is advantageous for swapper
        assertTrue(shouldInterfere, "Should interfere when arbitrage is advantageous for swapper");
        assertGt(hookShare, 0, "Hook share should be positive when interfering");
    }

    function testNoArbitrageWhenPricesEqual() public {
        // Test when market and pool prices are equal
        setETHPrice(100); // $1.00 (same as pool implies)
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== No Arbitrage Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Should interfere:", shouldInterfere);

        assertEq(arbitrageOpp, 0, "Should be no arbitrage when prices are equal");
        assertFalse(shouldInterfere, "Should not interfere when no arbitrage");
        assertEq(hookShare, 0, "Hook share should be 0 when no arbitrage");
    }

    function testExactOutputSwapNotAnalyzed() public {
        // Test that exact output swaps are not analyzed for arbitrage
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(0.1 ether), // Positive = exact output
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        assertEq(arbitrageOpp, 0, "Exact output swaps should not be analyzed");
        assertFalse(shouldInterfere, "Should not interfere with exact output swaps");
        assertEq(hookShare, 0, "Hook share should be 0 for exact output swaps");
    }

    function testOracleFailureHandling() public {
        // Test behavior when oracle fails (no price mapping)
        Currency unknownCurrency = Currency.wrap(address(0x9999));
        
        PoolKey memory testKey = PoolKey({
            currency0: unknownCurrency,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(testKey, params);

        assertEq(arbitrageOpp, 0, "Should be no arbitrage when oracle fails");
        assertFalse(shouldInterfere, "Should not interfere when oracle fails");
        assertEq(hookShare, 0, "Hook share should be 0 when oracle fails");
    }

    function testParameterUpdates() public {
        // Test updating arbitrage parameters
        vm.prank(owner);
        hook.updateParameters(7000, 120); // 70% share, 120s staleness

        (uint256 rhoBps, uint256 stalenessThreshold) = hook.getParameters();
        assertEq(rhoBps, 7000, "Rho BPS should be updated");
        assertEq(stalenessThreshold, 120, "Staleness threshold should be updated");

        // Test that new parameters affect arbitrage calculation
        setETHPrice(110); // $1.10 - advantageous for zeroForOne
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        // Should interfere since it's advantageous and outside confidence band
        assertTrue(shouldInterfere, "Should interfere when advantageous and outside confidence band");
        
        // Hook share should be 70% now
        if (shouldInterfere) {
            assertApproxEqRel(hookShare, (arbitrageOpp * 7000) / 10000, 1e15, "Hook share should be 70% of arbitrage");
        }
    }

    function testArbitrageWithDifferentSwapSizes() public {
        // Test arbitrage calculation with different swap sizes
        setETHPrice(110); // $1.10 - advantageous for zeroForOne (pool gives better rate)
        setUSDCPrice(100); // $1.00

        uint256[] memory swapAmounts = new uint256[](4);
        swapAmounts[0] = 0.01 ether;
        swapAmounts[1] = 0.1 ether;
        swapAmounts[2] = 1 ether;
        swapAmounts[3] = 10 ether;

        for (uint256 i = 0; i < swapAmounts.length; i++) {
            SwapParams memory params = SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmounts[i]),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            });

            (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere, bool isOutsideConfidenceBand) = 
                hook.calculateArbitrageOpportunity(poolKey, params);

            console.log("=== Swap Size Test ===");
            console.log("Swap amount:", swapAmounts[i]);
            console.log("Arbitrage opportunity:", arbitrageOpp);
            console.log("Should interfere:", shouldInterfere);

            // All should interfere as it's advantageous and outside confidence band
            assertTrue(shouldInterfere, "Should interfere when advantageous and outside confidence band");
            
            // Arbitrage opportunity should scale with swap amount
            assertGt(arbitrageOpp, 0, "Should have arbitrage opportunity");
        }
    }

    function testBothSwapDirections() public {
        // Test arbitrage in both directions
        
        // Direction 1: ETH expensive in market (advantageous for zeroForOne - selling ETH)
        setETHPrice(110); // $1.10 - pool gives better rate for selling ETH
        setUSDCPrice(100); // $1.00

        SwapParams memory paramsZeroForOne = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp1, uint256 hookShare1, bool shouldInterfere1, bool isOutsideConfidenceBand1) = 
            hook.calculateArbitrageOpportunity(poolKey, paramsZeroForOne);

        assertTrue(shouldInterfere1, "Should interfere when selling ETH is advantageous");
        assertGt(arbitrageOpp1, 0, "Should have arbitrage opportunity");

        // Direction 2: ETH expensive in market (advantageous for oneForZero - buying ETH)
        setETHPrice(110); // $1.10 - pool gives better rate for buying ETH (1 ETH for 100 USDC vs 110 USDC in market)
        setUSDCPrice(100); // $1.00

        SwapParams memory paramsOneForZero = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(100 ether), // Selling USDC for ETH
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        (uint256 arbitrageOpp2, uint256 hookShare2, bool shouldInterfere2, bool isOutsideConfidenceBand2) = 
            hook.calculateArbitrageOpportunity(poolKey, paramsOneForZero);

        assertTrue(shouldInterfere2, "Should interfere when buying ETH is advantageous");
        assertGt(arbitrageOpp2, 0, "Should have arbitrage opportunity");

        console.log("=== Both Directions Test ===");
        console.log("ZeroForOne arbitrage:", arbitrageOpp1);
        console.log("OneForZero arbitrage:", arbitrageOpp2);
    }
} 