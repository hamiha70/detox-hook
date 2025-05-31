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
        mockOracle.setPrice(ETH_USD_PRICE_ID, int64(int256(ETH_PRICE_BASE * 1e6)), -8);
        mockOracle.setPrice(USDC_USD_PRICE_ID, int64(int256(USDC_PRICE_BASE * 1e6)), -8);
    }

    function setETHPrice(uint256 priceUSD) internal {
        mockOracle.setPrice(ETH_USD_PRICE_ID, int64(int256(priceUSD * 1e6)), -8);
    }

    function setUSDCPrice(uint256 priceUSD) internal {
        mockOracle.setPrice(USDC_USD_PRICE_ID, int64(int256(priceUSD * 1e6)), -8);
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
        // Setup: Pool price = 1:1, Market ETH = $0.90 (10% lower than pool implies)
        setETHPrice(90); // $0.90
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(0.1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== ZeroForOne Arbitrage Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Hook share:", hookShare);
        console.log("Should interfere:", shouldInterfere);

        assertGt(arbitrageOpp, 0, "Should detect arbitrage opportunity when pool price > market price");
        
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

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
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
        // Test just below threshold (4% difference)
        setETHPrice(96); // $0.96 (4% below $1.00)
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== Just Below Threshold Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Should interfere:", shouldInterfere);

        // Should not interfere as arbitrage is below 5% threshold
        assertFalse(shouldInterfere, "Should not interfere when arbitrage is below 5% threshold");
        assertEq(hookShare, 0, "Hook share should be 0 when not interfering");
    }

    function testThresholdBehaviorJustAbove() public {
        // Test just above threshold (6% difference)
        setETHPrice(94); // $0.94 (6% below $1.00)
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        console.log("=== Just Above Threshold Test ===");
        console.log("Arbitrage opportunity:", arbitrageOpp);
        console.log("Should interfere:", shouldInterfere);

        // Should interfere as arbitrage is above 5% threshold
        assertTrue(shouldInterfere, "Should interfere when arbitrage is above 5% threshold");
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

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
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

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
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

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
            hook.calculateArbitrageOpportunity(testKey, params);

        assertEq(arbitrageOpp, 0, "Should be no arbitrage when oracle fails");
        assertFalse(shouldInterfere, "Should not interfere when oracle fails");
        assertEq(hookShare, 0, "Hook share should be 0 when oracle fails");
    }

    function testParameterUpdates() public {
        // Test updating arbitrage parameters
        vm.prank(owner);
        hook.updateParameters(1000, 7000, 120); // 10% threshold, 70% share, 120s staleness

        (uint256 alphaBps, uint256 rhoBps, uint256 stalenessThreshold) = hook.getParameters();
        assertEq(alphaBps, 1000, "Alpha BPS should be updated");
        assertEq(rhoBps, 7000, "Rho BPS should be updated");
        assertEq(stalenessThreshold, 120, "Staleness threshold should be updated");

        // Test that new parameters affect arbitrage calculation
        setETHPrice(91); // $0.91 (9% below $1.00)
        setUSDCPrice(100); // $1.00

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        // With 9% arbitrage and 10% threshold, should not interfere
        assertFalse(shouldInterfere, "Should not interfere with 9% arbitrage and 10% threshold");

        // But if we set 8% threshold, it should interfere
        vm.prank(owner);
        hook.updateParameters(800, 7000, 120); // 8% threshold

        (arbitrageOpp, hookShare, shouldInterfere) = 
            hook.calculateArbitrageOpportunity(poolKey, params);

        assertTrue(shouldInterfere, "Should interfere with 9% arbitrage and 8% threshold");
        
        // Hook share should be 70% now
        if (shouldInterfere) {
            assertApproxEqRel(hookShare, (arbitrageOpp * 7000) / 10000, 1e15, "Hook share should be 70% of arbitrage");
        }
    }

    function testArbitrageWithDifferentSwapSizes() public {
        // Test arbitrage calculation with different swap sizes
        setETHPrice(90); // $0.90 (10% below $1.00)
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

            (uint256 arbitrageOpp, uint256 hookShare, bool shouldInterfere) = 
                hook.calculateArbitrageOpportunity(poolKey, params);

            console.log("=== Swap Size Test ===");
            console.log("Swap amount:", swapAmounts[i]);
            console.log("Arbitrage opportunity:", arbitrageOpp);
            console.log("Should interfere:", shouldInterfere);

            // All should interfere as 10% is above 5% threshold
            assertTrue(shouldInterfere, "Should interfere with 10% arbitrage");
            
            // Arbitrage opportunity should scale with swap amount (approximately 10%)
            assertApproxEqRel(arbitrageOpp, swapAmounts[i] / 10, 5e16, "Arbitrage should be ~10% of swap amount");
        }
    }

    function testBothSwapDirections() public {
        // Test arbitrage in both directions
        
        // Direction 1: ETH cheap in market (zeroForOne arbitrage)
        setETHPrice(90); // $0.90
        setUSDCPrice(100); // $1.00

        SwapParams memory paramsZeroForOne = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(1 ether),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        (uint256 arbitrageOpp1, uint256 hookShare1, bool shouldInterfere1) = 
            hook.calculateArbitrageOpportunity(poolKey, paramsZeroForOne);

        assertTrue(shouldInterfere1, "Should interfere when ETH is cheap in market");
        assertGt(arbitrageOpp1, 0, "Should have arbitrage opportunity");

        // Direction 2: ETH expensive in market (oneForZero arbitrage)
        setETHPrice(110); // $1.10
        setUSDCPrice(100); // $1.00

        SwapParams memory paramsOneForZero = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(110 ether), // Equivalent value in USDC
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        (uint256 arbitrageOpp2, uint256 hookShare2, bool shouldInterfere2) = 
            hook.calculateArbitrageOpportunity(poolKey, paramsOneForZero);

        assertTrue(shouldInterfere2, "Should interfere when ETH is expensive in market");
        assertGt(arbitrageOpp2, 0, "Should have arbitrage opportunity");

        console.log("=== Both Directions Test ===");
        console.log("ZeroForOne arbitrage:", arbitrageOpp1);
        console.log("OneForZero arbitrage:", arbitrageOpp2);
    }
} 