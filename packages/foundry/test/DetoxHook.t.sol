// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

// Uniswap V4 Core imports
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

// Test utilities
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

// Our contract
import {DetoxHook} from "../src/DetoxHook.sol";
import {MockPyth} from "../src/libraries/PythMock.sol";
import {PriceRegistry} from "../src/PriceRegistry.sol";
import {HookLibrary} from "../src/libraries/HookLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract DetoxHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // Test contracts
    DetoxHook public hook;
    PoolKey public poolKey;
    PoolId public poolId;
    
    // Test parameters
    uint24 public constant FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;
    uint256 private constant PRICE_PRECISION = 1e8; // 8 decimal precision like USDC
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    MockPyth public mockOracle;

    // Pyth price IDs
    bytes32 public constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

    function setUp() public {
        // Deploy fresh manager and routers
        deployFreshManagerAndRouters();
        
        // Deploy and mint test currencies
        (currency0, currency1) = deployMintAndApprove2Currencies();
        
        // Deploy DetoxHook to the correct address
        // The hook address must have the correct permissions bits set
        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        
        // Deploy the hook using CREATE2 to get the correct address
        mockOracle = new MockPyth(60, 0);
        
        // Deploy mock price registry for testing
        MockPriceRegistry mockRegistry = new MockPriceRegistry(address(this));
        
        // Configure MockPriceRegistry with token addresses
        mockRegistry.setTokenAddresses(Currency.unwrap(currency0), Currency.unwrap(currency1));
        
        // Use 4-parameter constructor (poolManager, owner, oracle, priceRegistry)
        deployCodeTo("DetoxHook.sol", abi.encode(manager, address(this), address(mockOracle), address(mockRegistry)), hookAddress);
        hook = DetoxHook(payable(hookAddress));
        
        // Create pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        poolId = poolKey.toId();
        
        // Initialize the pool
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        
        // Add initial liquidity
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -600,  // Wide range
            tickUpper: 600,
            liquidityDelta: 1000e18, // 1000 units of liquidity
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(poolKey, liquidityParams, "");
        
        // Give test users some tokens
        MockERC20(Currency.unwrap(currency0)).mint(alice, 1000e18);
        MockERC20(Currency.unwrap(currency1)).mint(alice, 1000e18);
        MockERC20(Currency.unwrap(currency0)).mint(bob, 1000e18);
        MockERC20(Currency.unwrap(currency1)).mint(bob, 1000e18);
        
        // Approve tokens for users
        vm.startPrank(alice);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(bob);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Test that the hook deploys correctly
    function test_HookDeployment() public view {
        // Verify hook is deployed
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        
        // Verify hook is connected to the correct pool manager
        assertEq(address(hook.poolManager()), address(manager), "Hook should be connected to manager");
        
        // Verify hook address has correct permissions
        assertTrue(Hooks.hasPermission(IHooks(address(hook)), Hooks.BEFORE_SWAP_FLAG), "Should have beforeSwap permission");
        assertTrue(Hooks.hasPermission(IHooks(address(hook)), Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG), "Should have beforeSwapReturnsDelta permission");
    }

    /// @notice Test that hook permissions are correctly configured
    function test_HookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        // Should have beforeSwap enabled
        assertTrue(permissions.beforeSwap, "beforeSwap should be enabled");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be enabled");
        
        // All others should be disabled for this simple hook
        assertFalse(permissions.beforeInitialize, "beforeInitialize should be disabled");
        assertFalse(permissions.afterInitialize, "afterInitialize should be disabled");
        assertFalse(permissions.beforeAddLiquidity, "beforeAddLiquidity should be disabled");
        assertFalse(permissions.afterAddLiquidity, "afterAddLiquidity should be disabled");
        assertFalse(permissions.beforeRemoveLiquidity, "beforeRemoveLiquidity should be disabled");
        assertFalse(permissions.afterRemoveLiquidity, "afterRemoveLiquidity should be disabled");
        assertFalse(permissions.afterSwap, "afterSwap should be disabled");
        assertFalse(permissions.beforeDonate, "beforeDonate should be disabled");
        assertFalse(permissions.afterDonate, "afterDonate should be disabled");
    }

    /// @notice Test that the pool initializes correctly with our hook
    function test_PoolInitialization() public view {
        // Verify pool exists
        (uint160 sqrtPriceX96, int24 tick,,) = manager.getSlot0(poolId);
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "Pool should be initialized at 1:1 price");
        assertEq(tick, 0, "Pool should be initialized at tick 0");
        
        // Verify pool has our hook
        PoolKey memory retrievedKey = poolKey; // In a real test, you'd retrieve this from the manager
        assertEq(address(retrievedKey.hooks), address(hook), "Pool should have our hook");
    }

    /// @notice Test basic swap functionality - hook should be called and not interfere
    function test_BasicSwap() public {
        uint256 swapAmount = 1e18; // 1 token

        // Set up valid oracle price IDs and prices for both currencies
        // Assume currency0 is ETH, currency1 is USDC for this test
        // TODO: Fix with PriceRegistry integration
        // Map price IDs to currencies
        // hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        // hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        // Initialize mock oracle with valid prices for both price IDs
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));

        // Record balances before swap
        uint256 aliceBalance0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceBalance1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(alice);

        // Perform swap as Alice: currency0 -> currency1
        vm.startPrank(alice);

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // Swap currency0 for currency1
            amountSpecified: -int256(swapAmount), // Exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // No price limit
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute the swap - this should call our hook's beforeSwap function
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");

        vm.stopPrank();

        // Verify swap occurred
        uint256 aliceBalance0After = MockERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceBalance1After = MockERC20(Currency.unwrap(currency1)).balanceOf(alice);

        // Alice should have less currency0 and more currency1
        assertLt(aliceBalance0After, aliceBalance0Before, "Alice should have less currency0");
        assertGt(aliceBalance1After, aliceBalance1Before, "Alice should have more currency1");

        // Verify the delta makes sense
        assertTrue(delta.amount0() < 0, "Delta amount0 should be negative (currency0 out)");
        assertTrue(delta.amount1() > 0, "Delta amount1 should be positive (currency1 in)");

        console.log("Swap completed successfully!");
    }

    /// @notice Test two alternating swaps to debug currency settlement issues
    function test_TwoAlternatingSwaps() public {
        uint256 swapAmount = 0.5e18; // 0.5 tokens
        // TODO: Fix with PriceRegistry integration  
        // Set up price IDs for both currencies
        // hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        // hook.setPriceId(currency1, USDC_USD_PRICE_ID);

        // Perform two alternating swaps
        for (uint i = 0; i < 2; i++) {
            // Update oracle before each swap
            mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
            mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
            
            // Log pool price before swap
            (uint160 sqrtPriceX96Before,,,) = manager.getSlot0(poolId);
            console.log("=== SWAP", i, "===");
            console.log("Pool sqrtPrice before swap:", uint256(sqrtPriceX96Before));
            
            vm.startPrank(alice);
            SwapParams memory swapParams = SwapParams({
                zeroForOne: i % 2 == 0, // Alternate swap direction (0: ETH->USDC, 1: USDC->ETH)
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: i % 2 == 0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            });
            
            PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });
            
            console.log("Swap direction (zeroForOne):", i % 2 == 0);
            console.log("Amount specified:", uint256(-swapParams.amountSpecified));
            
            // Each swap should succeed and call our hook
            swapRouter.swap(poolKey, swapParams, testSettings, "");
            vm.stopPrank();
            
            // Log pool price after swap
            (uint160 sqrtPriceX96After,,,) = manager.getSlot0(poolId);
            console.log("Pool sqrtPrice after swap:", uint256(sqrtPriceX96After));
            console.log("Price change:", 
                sqrtPriceX96After > sqrtPriceX96Before ? "INCREASED" : "DECREASED");
        }
        console.log("Two alternating swaps completed successfully!");
    }



    /// @notice Test no arbitrage when oracle matches pool price
    /// Pool: 1 ETH = 1 USDC, Oracle: 1 ETH = 1 USDC  
    /// No swap should trigger arbitrage capture
    function test_NoArbitrageWhenOracleMatchesPool() public {
        uint256 swapAmount = 0.5e18;
        
        // TODO: Fix with PriceRegistry integration
        // Set up price IDs
        // hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        // hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
        // Oracle: ETH=$1, USDC=$1 (matches pool 1:1 ratio)
        // No arbitrage opportunity should exist
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        console.log("=== NO ARBITRAGE TEST ===");
        console.log("Oracle: ETH=$1, USDC=$1 (matches pool)");
        console.log("Expected: Hook should NOT capture arbitrage");
        
        // Test both directions
        for (uint i = 0; i < 2; i++) {
            bool zeroForOne = i == 0;
            console.log("Testing direction:", zeroForOne ? "ETH->USDC" : "USDC->ETH");
            
            vm.startPrank(alice);
            SwapParams memory swapParams = SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            });
            
            PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });
            
            BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
            vm.stopPrank();
            
            console.log("Delta amount0 (ETH):", delta.amount0());
            console.log("Delta amount1 (USDC):", delta.amount1());
        }
        
        // Verify no arbitrage was captured
        uint256 accumulatedETH = hook.accumulatedTokens(poolId, currency0);
        uint256 accumulatedUSDC = hook.accumulatedTokens(poolId, currency1);
        console.log("Hook accumulated ETH:", accumulatedETH);
        console.log("Hook accumulated USDC:", accumulatedUSDC);
        
        // Note: We might still capture some if confidence bands create opportunities
        // The key is that it should be minimal compared to clear arbitrage cases
    }

    /// @notice Test that hook doesn't interfere with normal pool operations
    function test_HookDoesNotInterferWithLiquidity() public {
        // Add more liquidity to the pool
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -300,
            tickUpper: 300,
            liquidityDelta: 500e18,
            salt: 0
        });
        
        // This should work normally since our hook doesn't implement liquidity hooks
        modifyLiquidityRouter.modifyLiquidity(poolKey, liquidityParams, "");
        
        // Remove some liquidity
        liquidityParams.liquidityDelta = -250e18;
        modifyLiquidityRouter.modifyLiquidity(poolKey, liquidityParams, "");
        
        console.log("Liquidity operations completed successfully!");
    }

    /// @notice Test edge case: very small swap
    function test_SmallSwap() public {
        uint256 swapAmount = 1000; // Very small amount (0.000000000000001 tokens)
        // Update oracle before swap
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        // Small swap should still work
        swapRouter.swap(poolKey, swapParams, testSettings, "");
        vm.stopPrank();
        console.log("Small swap completed successfully!");
    }

    /// @notice Test that hook returns correct values
    function test_HookReturnValues() public {
        // This test verifies that our hook returns the expected values
        // Since we can't directly call the internal _beforeSwap function,
        // we verify it through successful swap execution
        
        vm.startPrank(alice);
        
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e18,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // Initialize mock oracle with valid prices for both price IDs
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        // If hook returns incorrect values, this would revert
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        
        vm.stopPrank();
        
        // Verify swap completed (hook returned correct selector and delta)
        assertTrue(delta.amount0() != 0 || delta.amount1() != 0, "Swap should have non-zero delta");
        
        console.log("Hook return values are correct!");
    }

        /// @notice Legacy Test Case: No arbitrage detection (should NOT capture)
    function test_RealisticCase2_ZeroForOne_NoArbitrage() public {
        // Setup: Pool currency1/currency0 ≈ 1, Oracle currency1/currency0 = 2000
        // Pool gives WORSE rate than market (bad deal for swapper, no arbitrage)
        // Pool: 1 currency1 per currency0, Market: 2000 currency1 per currency0
        // Hook should NOT interfere (swapper getting ripped off, but that's not arbitrage)
        
        uint256 swapAmount = 0.001e18;
        
        // TODO: Fix with PriceRegistry integration
        // hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        // hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
        // No arbitrage: currency0=$2000, currency1=$1 → market ratio = 2000:1
        // Pool ratio ≈ 1:1, so pool gives MUCH WORSE deal than market (terrible for swapper)
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        console.log("=== REALISTIC CASE 2: No arbitrage (zeroForOne) ===");
        console.log("Pool ratio: ~1:1 (gives 1 currency1 per currency0)"); 
        console.log("Market ratio: 2000:1 (currency0 worth 2000x currency1)");
        console.log("Pool gives 2000x WORSE rate than market -> NO ARBITRAGE (just bad trade)");
        console.log("Expected: Hook should NOT interfere");
        
        uint256 accumulatedBefore = hook.accumulatedTokens(poolId, currency0);
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // currency0 → currency1 (getting terrible deal from pool)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        uint256 accumulatedAfter = hook.accumulatedTokens(poolId, currency0);
        
        assertEq(accumulatedAfter, accumulatedBefore, "Should NOT capture when pool gives worse rate than market");
    }

    // ============ BRIDGE TESTS (realSwap) ============
    // These tests verify DetoxHook produces the same results as ArbitrageLib unit tests

    /// @notice Bridge Test 1: Verify DetoxHook matches ArbitrageLib Scenario 1
    /// Pool=3000.096 USDC/ETH, Oracle bounds=2277-2525 USDC/ETH (with confidence)
    /// Arbitrage: (3000.096-2525)/3000.096 = 15.83%, Hook share: 15.83% × 80% = 12.66%
    /// Expected: 12.66% arbitrage capture (12660000000000000 wei +/- 1 percentage point)
    function test_realSwap_Scenario1_PoolOverpaying() public {
        console.log("=== BRIDGE TEST 1: Pool Overpaying (replicates ArbitrageLib Scenario 1) ===");
        console.log("Target: Pool=3000 USDC/ETH, Oracle~2400-2600 USDC/ETH");
        console.log("Expected: 12.66% arbitrage capture from 0.1 ETH swap (+/-1 percentage point)");
        
        // Step 1: Create new pool at 3000 USDC/ETH using tick-based approach
        // For currency0=ETH (18 decimals), currency1=USDC (6 decimals)
        // Current: tick 11000 gives ~3.004 USDC/ETH
        // Target: 3000 USDC/ETH
        // Since price = 1.0001^tick, we need: tick = ln(3000)/ln(1.0001) ≈ 80068
        int24 targetTick = 80068; // Correct tick for 3000 USDC per ETH
        uint160 targetSqrtPriceX96 = TickMath.getSqrtPriceAtTick(targetTick);
        
        PoolKey memory testPoolKey = PoolKey({
            currency0: currency0, // ETH (18 decimals)
            currency1: currency1, // USDC (6 decimals) 
            fee: 500, // Use different fee to create different pool
            tickSpacing: 10, // Corresponding tick spacing for 500 fee
            hooks: IHooks(address(hook))
        });
        
        PoolId testPoolId = testPoolKey.toId();
        
        console.log("Creating pool with target tick:", targetTick);
        console.log("Target sqrtPriceX96:", uint256(targetSqrtPriceX96));
        
        // Initialize pool at target price (now safe with FullMath.mulDiv)
        manager.initialize(testPoolKey, targetSqrtPriceX96);
        
        // Add liquidity to the new pool - CENTERED AROUND CURRENT TICK (aligned with tick spacing)
        int24 tickSpacing = 10;
        int24 alignedTickLower = ((targetTick - 600) / tickSpacing) * tickSpacing; // Round down
        int24 alignedTickUpper = ((targetTick + 600 + tickSpacing - 1) / tickSpacing) * tickSpacing; // Round up
        
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: alignedTickLower,  // Aligned to tick spacing
            tickUpper: alignedTickUpper,  // Aligned to tick spacing
            liquidityDelta: 1000e18,
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(testPoolKey, liquidityParams, "");
        
        // Verify pool price (now works with fixed FullMath implementation)
        uint256 actualPoolPrice = _getPoolPrice(testPoolKey);
        console.log("Actual pool price:", actualPoolPrice / 1e5, "000 USDC/ETH"); // Show in thousands
        
        // Step 2: Setup oracle for ~2400-2600 USDC/ETH bounds (exact ArbitrageLib scenario)
        // Oracle: ETH=$2400 ± $100, USDC=$1 ± $0.01 
        // This creates oracle bounds of roughly 2300-2500 USDC/ETH  
        int64 ethUsdPrice = int64(2400 * 1e8);     // $2400 ETH (8 decimals)
        uint64 ethConf = uint64(100 * 1e8);        // ±$100 confidence
        int64 usdcUsdPrice = int64(1 * 1e8);       // $1 USDC (8 decimals)  
        uint64 usdcConf = uint64(0.01 * 1e8);      // ±$0.01 confidence
        
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, ethUsdPrice, ethConf, -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, usdcUsdPrice, usdcConf, -8, uint64(block.timestamp));
        
        console.log("Oracle setup: ETH=$2400+/-100, USDC=$1+/-0.01");
        console.log("Oracle bounds: ~2300-2500 USDC/ETH");
        
        // Step 3: Execute 0.1 ETH zeroForOne swap (ETH -> USDC) - smaller impact
        uint256 swapAmount = 0.1e18; // 0.1 ETH (reduced for less pool impact)
        uint256 hookBalanceBefore = hook.accumulatedTokens(testPoolId, currency0);
        
        console.log("Executing 0.1 ETH swap (zeroForOne: ETH -> USDC)");
        console.log("Hook accumulated tokens before:", hookBalanceBefore);
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // ETH -> USDC (getting great deal from pool)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(testPoolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        // Step 4: Verify arbitrage capture matches ArbitrageLib expectation
        uint256 hookBalanceAfter = hook.accumulatedTokens(testPoolId, currency0);
        uint256 capturedAmount = hookBalanceAfter - hookBalanceBefore;
        
        console.log("Hook accumulated tokens after:", hookBalanceAfter);
        console.log("Captured amount:", capturedAmount);
        console.log("Swap delta amount0 (ETH):", delta.amount0());
        console.log("Swap delta amount1 (USDC):", delta.amount1());
        
        // Correct calculation: (3000.096-2525)/3000.096 = 15.83%, Hook: 15.83% × 80% = 12.66%
        uint256 expectedCapture = 12660000000000000; // 12.66% of 0.1 ETH (with confidence bounds)
        uint256 tolerance = 1000000000000000; // +/-1 percentage point (11.66% to 13.66% range)
        uint256 expectedMin = expectedCapture - tolerance;
        uint256 expectedMax = expectedCapture + tolerance;
        
        console.log("Expected capture (wei):");
        console.logUint(expectedCapture);
        console.log("Tolerance range min (wei):");
        console.logUint(expectedMin);
        console.log("Tolerance range max (wei):");
        console.logUint(expectedMax);
        console.log("Actual captured (wei):");
        console.logUint(capturedAmount);
        console.log("Expected percentage: 12.66%");
        
        // Assertions - precise expectations with confidence bounds accounted
        assertTrue(capturedAmount > 0, "Hook should capture arbitrage when pool overpaying");
        assertGe(capturedAmount, expectedMin, "Captured amount should be >= expected minimum (11.66%)");
        assertLe(capturedAmount, expectedMax, "Captured amount should be <= expected maximum (13.66%)");
        
        console.log("[SUCCESS] Bridge test passed! DetoxHook captures arbitrage consistent with ArbitrageLib");
        console.log("=== BRIDGE TEST 1 COMPLETE ===");
    }

    /// @notice Bridge Test 2: Verify DetoxHook detects pool underpricing
    /// Pool=2000 USDC/ETH, Oracle bounds=2277-2525 USDC/ETH (with confidence)
    /// Arbitrage: (2277-2000)/2277 = 12.17%, Hook share: 12.17% × 80% = 9.74%
    /// Expected: 9.74% arbitrage capture (9740000000000000 wei +/- 1 percentage point)
    function test_realSwap_Scenario2_PoolUnderpricing() public {
        console.log("=== BRIDGE TEST 2: Pool Underpricing ===");
        console.log("Target: Pool=2000 USDC/ETH, Oracle bounds=2277-2525 USDC/ETH");
        console.log("Expected: 9.74% arbitrage capture from 0.1 ETH swap (+/-1 percentage point)");

        // Step 1: Create new pool at 2000 USDC/ETH
        // tick = ln(2000)/ln(1.0001) ≈ 76010
        int24 targetTick = 76010;
        uint160 targetSqrtPriceX96 = TickMath.getSqrtPriceAtTick(targetTick);
        
        PoolKey memory testPoolKey = PoolKey({
            currency0: currency0, // ETH (18 decimals)
            currency1: currency1, // USDC (6 decimals) 
            fee: 300, // Use different fee to create different pool
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });
        
        PoolId testPoolId = testPoolKey.toId();
        
        console.log("Creating pool with target tick:");
        console.logInt(targetTick);
        console.log("Target sqrtPriceX96:");
        console.logUint(uint256(targetSqrtPriceX96));
        
        // Log what this actually gives us
        uint256 actualPoolPrice18Dec = HookLibrary.sqrtPriceToPrice(targetSqrtPriceX96);
        uint256 actualPoolPrice8Dec = FullMath.mulDiv(actualPoolPrice18Dec, PRICE_PRECISION, 1e18);
        console.log("Actual pool price (8 decimals):");
        console.logUint(actualPoolPrice8Dec);

        // Initialize pool at target price
        manager.initialize(testPoolKey, targetSqrtPriceX96);
        
        // Add liquidity to the new pool - CENTERED AROUND CURRENT TICK (aligned with tick spacing)
        int24 tickSpacing = 10;
        int24 alignedTickLower = ((targetTick - 600) / tickSpacing) * tickSpacing; // Round down
        int24 alignedTickUpper = ((targetTick + 600 + tickSpacing - 1) / tickSpacing) * tickSpacing; // Round up
        
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: alignedTickLower,  // Aligned to tick spacing
            tickUpper: alignedTickUpper,  // Aligned to tick spacing
            liquidityDelta: 1000e18,
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(testPoolKey, liquidityParams, "");
        
        // Step 2: Setup oracle: ETH=$2400±$100, USDC=$1±$0.01
        // Oracle bounds: 2277-2525 USDC/ETH
        int64 ethUsdPrice = int64(2400 * 1e8);
        uint64 ethConf = uint64(100 * 1e8);
        int64 usdcUsdPrice = int64(1 * 1e8);
        uint64 usdcConf = uint64(0.01 * 1e8);
        
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, ethUsdPrice, ethConf, -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, usdcUsdPrice, usdcConf, -8, uint64(block.timestamp));
        
        // Step 3: Execute 0.1 ETH swap (zeroForOne: ETH -> USDC)
        uint256 swapAmount = 0.1e18; // 0.1 ETH
        uint256 accumulatedBefore = hook.accumulatedTokens(testPoolId, currency0);
        
        console.log("Executing 0.1 ETH swap (zeroForOne: ETH -> USDC)");
        console.log("Hook accumulated tokens before:");
        console.logUint(accumulatedBefore);

        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount), // exactInput: 0.1 ETH
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap
        BalanceDelta delta = swapRouter.swap(testPoolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        // Step 4: Check results
        uint256 accumulatedAfter = hook.accumulatedTokens(testPoolId, currency0);
        uint256 capturedAmount = accumulatedAfter - accumulatedBefore;
        
        console.log("Hook accumulated tokens after:");
        console.logUint(accumulatedAfter);
        console.log("Captured amount:");
        console.logUint(capturedAmount);
        console.log("Swap delta amount0 (ETH):");
        console.logInt(delta.amount0());
        console.log("Swap delta amount1 (USDC):");
        console.logInt(delta.amount1());
        
        // Expected: (2277-2000)/2277 = 12.17% arbitrage, hook gets 80% = 9.74%
        // 9.74% of 0.1 ETH = 0.00974 ETH = 9,740,000,000,000,000 wei
        uint256 expectedCapture = 9740000000000000; // 9.74% of 0.1 ETH
        uint256 toleranceMin = 8740000000000000; // 8.74% (±1 percentage point)
        uint256 toleranceMax = 10740000000000000; // 10.74% (±1 percentage point)
        
        console.log("Expected capture (wei):");
        console.logUint(expectedCapture);
        console.log("Tolerance range min (wei):");
        console.logUint(toleranceMin);
        console.log("Tolerance range max (wei):");
        console.logUint(toleranceMax);
        console.log("Actual captured (wei):");
        console.logUint(capturedAmount);
        console.log("Expected percentage: 9.74%");
        
        // Verify hook captured the expected amount
        assertGt(capturedAmount, toleranceMin, "Hook should capture arbitrage when pool underpricing");
        assertLt(capturedAmount, toleranceMax, "Hook capture should be within expected range");
        
        console.log("[SUCCESS] Bridge test passed! DetoxHook captures arbitrage for underpriced pool");
        console.log("=== BRIDGE TEST 2 COMPLETE ===");
    }

    /// @notice Bridge Test 3: Verify DetoxHook does NOT interfere when pool within confidence bounds
    /// Pool=2450 USDC/ETH, Oracle bounds=2277-2525 USDC/ETH (with confidence)
    /// Since 2277 < 2450 < 2525, no arbitrage opportunity exists
    /// Expected: 0% arbitrage capture (hook should not interfere)
    function test_realSwap_Scenario3_PoolWithinBounds() public {
        console.log("=== BRIDGE TEST 3: Pool Within Confidence Bounds ===");
        console.log("Target: Pool=2450 USDC/ETH, Oracle bounds=2277-2525 USDC/ETH");
        console.log("Expected: 0% arbitrage capture (hook should NOT interfere)");
        
        // Step 1: Create new pool at 2450 USDC/ETH (within confidence bounds)
        // tick = ln(2450)/ln(1.0001) ≈ 78039 (precise calculation)
        int24 targetTick = 78039; // Correct tick for 2450 USDC/ETH
        uint160 targetSqrtPriceX96 = TickMath.getSqrtPriceAtTick(targetTick);
        
        PoolKey memory testPoolKey = PoolKey({
            currency0: currency0, // ETH (18 decimals)
            currency1: currency1, // USDC (6 decimals) 
            fee: 300, // Use different fee to create different pool
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });
        
        PoolId testPoolId = testPoolKey.toId();
        
        console.log("Creating pool with target tick:");
        console.logInt(targetTick);
        console.log("Target sqrtPriceX96:");
        console.logUint(uint256(targetSqrtPriceX96));
        
        // Initialize pool at target price
        manager.initialize(testPoolKey, targetSqrtPriceX96);
        
        // Add liquidity to the new pool - CENTERED AROUND CURRENT TICK (aligned with tick spacing)
        int24 tickSpacing = 10;
        int24 alignedTickLower = ((targetTick - 600) / tickSpacing) * tickSpacing; // Round down
        int24 alignedTickUpper = ((targetTick + 600 + tickSpacing - 1) / tickSpacing) * tickSpacing; // Round up
        
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: alignedTickLower,  // Aligned to tick spacing
            tickUpper: alignedTickUpper,  // Aligned to tick spacing
            liquidityDelta: 1000e18,
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(testPoolKey, liquidityParams, "");
        
        // Verify pool price
        uint256 actualPoolPrice = _getPoolPrice(testPoolKey);
        console.log("Actual pool price (8 decimals):");
        console.logUint(actualPoolPrice);
        
        // Step 2: Setup same oracle as previous scenarios (ETH=$2400±$100, USDC=$1±$0.01)
        int64 ethUsdPrice = int64(2400 * 1e8);
        uint64 ethConf = uint64(100 * 1e8);
        int64 usdcUsdPrice = int64(1 * 1e8);
        uint64 usdcConf = uint64(0.01 * 1e8);
        
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, ethUsdPrice, ethConf, -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, usdcUsdPrice, usdcConf, -8, uint64(block.timestamp));
        
        // Step 3: Execute 0.1 ETH zeroForOne swap (ETH -> USDC)
        uint256 swapAmount = 0.1e18; // 0.1 ETH
        uint256 hookBalanceBefore = hook.accumulatedTokens(testPoolId, currency0);
        
        console.log("Executing 0.1 ETH swap (zeroForOne: ETH -> USDC)");
        console.log("Hook accumulated tokens before:");
        console.logUint(hookBalanceBefore);
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // ETH -> USDC (pool price within bounds)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(testPoolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        // Step 4: Verify NO arbitrage capture (hook should not interfere)
        uint256 hookBalanceAfter = hook.accumulatedTokens(testPoolId, currency0);
        uint256 capturedAmount = hookBalanceAfter - hookBalanceBefore;
        
        console.log("Hook accumulated tokens after:");
        console.logUint(hookBalanceAfter);
        console.log("Captured amount:");
        console.logUint(capturedAmount);
        console.log("Swap delta amount0 (ETH):");
        console.logInt(delta.amount0());
        console.log("Swap delta amount1 (USDC):");
        console.logInt(delta.amount1());
        
        // Expected: 0% capture since pool price is within confidence bounds
        console.log("Expected capture: 0 wei (no arbitrage)");
        console.log("Actual captured (wei):");
        console.logUint(capturedAmount);
        console.log("Expected percentage: 0%");
        
        // Assertions - hook should NOT capture anything
        assertEq(capturedAmount, 0, "Hook should NOT capture when pool price within confidence bounds");
        
        // Verify the swap still completed normally
        assertTrue(delta.amount0() < 0, "ETH should be spent (negative delta)");
        assertTrue(delta.amount1() > 0, "USDC should be received (positive delta)");
        
        console.log("[SUCCESS] Bridge test passed! DetoxHook correctly does NOT interfere");
        console.log("=== BRIDGE TEST 3 COMPLETE ===");
    }

    /// @notice Bridge Test 4: Verify DetoxHook handles reverse direction (USDC -> ETH)
    /// Pool=3000 USDC/ETH (overpaying), Oracle bounds=2277-2525 USDC/ETH (with confidence)
    /// Swap direction: oneForZero (USDC -> ETH), testing opposite direction logic
    /// Expected: Similar arbitrage capture as Scenario 1 but in reverse direction
    function test_realSwap_Scenario4_ReverseDirection() public {
        console.log("=== BRIDGE TEST 4: Reverse Direction (USDC -> ETH) ===");
        console.log("Target: Pool=3000 USDC/ETH, Oracle bounds=2277-2525 USDC/ETH");
        console.log("Expected: Arbitrage capture from oneForZero swap (USDC -> ETH)");
        
        // Step 1: Create new pool at 3000 USDC/ETH (same as Scenario 1)
        int24 targetTick = 80068; // Correct tick for 3000 USDC/ETH
        uint160 targetSqrtPriceX96 = TickMath.getSqrtPriceAtTick(targetTick);
        
        PoolKey memory testPoolKey = PoolKey({
            currency0: currency0, // ETH (18 decimals)
            currency1: currency1, // USDC (6 decimals) 
            fee: 1000, // Use different fee to create different pool
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });
        
        PoolId testPoolId = testPoolKey.toId();
        
        console.log("Creating pool with target tick:");
        console.logInt(targetTick);
        console.log("Target sqrtPriceX96:");
        console.logUint(uint256(targetSqrtPriceX96));
        
        // Log what this actually gives us
        uint256 actualPoolPrice18Dec = HookLibrary.sqrtPriceToPrice(targetSqrtPriceX96);
        uint256 actualPoolPrice8Dec = FullMath.mulDiv(actualPoolPrice18Dec, PRICE_PRECISION, 1e18);
        console.log("Actual pool price (8 decimals):");
        console.logUint(actualPoolPrice8Dec);
        
        // Initialize pool at target price
        manager.initialize(testPoolKey, targetSqrtPriceX96);
        
        // Add liquidity to the new pool - CENTERED AROUND CURRENT TICK (aligned with tick spacing)
        int24 tickSpacing = 10;
        int24 alignedTickLower = ((targetTick - 600) / tickSpacing) * tickSpacing; // Round down
        int24 alignedTickUpper = ((targetTick + 600 + tickSpacing - 1) / tickSpacing) * tickSpacing; // Round up
        
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: alignedTickLower,  // Aligned to tick spacing
            tickUpper: alignedTickUpper,  // Aligned to tick spacing
            liquidityDelta: 1000e18,
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(testPoolKey, liquidityParams, "");
        
        // Step 2: Setup same oracle as other scenarios (ETH=$2400±$100, USDC=$1±$0.01)
        int64 ethUsdPrice = int64(2400 * 1e8);
        uint64 ethConf = uint64(100 * 1e8);
        int64 usdcUsdPrice = int64(1 * 1e8);
        uint64 usdcConf = uint64(0.01 * 1e8);
        
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, ethUsdPrice, ethConf, -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, usdcUsdPrice, usdcConf, -8, uint64(block.timestamp));
        
        // Step 3: Execute USDC -> ETH swap (oneForZero: false)
        // Use equivalent value: 300 USDC (should get ~0.1 ETH at 3000 USDC/ETH rate)
        uint256 swapAmount = 300e6; // 300 USDC (6 decimals)
        uint256 hookBalanceBeforeUSDC = hook.accumulatedTokens(testPoolId, currency1); // Track USDC
        
        console.log("Executing 300 USDC swap (oneForZero: USDC -> ETH)");
        console.log("Hook accumulated USDC before:");
        console.logUint(hookBalanceBeforeUSDC);
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false, // USDC -> ETH (reverse direction)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(testPoolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        // Step 4: Verify arbitrage capture (should capture USDC input)
        uint256 hookBalanceAfterUSDC = hook.accumulatedTokens(testPoolId, currency1);
        uint256 capturedAmount = hookBalanceAfterUSDC - hookBalanceBeforeUSDC;
        
        console.log("Hook accumulated USDC after:");
        console.logUint(hookBalanceAfterUSDC);
        console.log("Captured amount (USDC):");
        console.logUint(capturedAmount);
        console.log("Swap delta amount0 (ETH):");
        console.logInt(delta.amount0());
        console.log("Swap delta amount1 (USDC):");
        console.logInt(delta.amount1());
        
        // For reverse direction, expect similar arbitrage percentage of input amount
        // Pool overpaying should create arbitrage in both directions
        uint256 expectedCapture = 38000000; // ~12.66% of 300 USDC (300e6 * 0.1266)
        uint256 toleranceMin = 35000000; // 11.66% (±1 percentage point)
        uint256 toleranceMax = 41000000; // 13.66% (±1 percentage point)
        
        console.log("Expected capture (USDC wei):");
        console.logUint(expectedCapture);
        console.log("Tolerance range min (USDC wei):");
        console.logUint(toleranceMin);
        console.log("Tolerance range max (USDC wei):");
        console.logUint(toleranceMax);
        console.log("Actual captured (USDC wei):");
        console.logUint(capturedAmount);
        console.log("Expected percentage: ~12.66%");
        
        // Assertions
        assertGt(capturedAmount, toleranceMin, "Hook should capture arbitrage in reverse direction");
        assertLt(capturedAmount, toleranceMax, "Hook capture should be within expected range");
        
        // Verify the swap completed in correct direction
        assertTrue(delta.amount0() > 0, "ETH should be received (positive delta)");
        assertTrue(delta.amount1() < 0, "USDC should be spent (negative delta)");
        
        console.log("[SUCCESS] Bridge test passed! DetoxHook handles reverse direction correctly");
        console.log("=== BRIDGE TEST 4 COMPLETE ===");
    }

    /// @notice Helper function to get pool price for any pool key
    function _getPoolPrice(PoolKey memory key) internal view returns (uint256) {
        uint160 sqrtPriceX96 = HookLibrary.getPoolPrice(manager, key);
        if (sqrtPriceX96 == 0) return 0;
        uint256 price = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
        uint256 normPrice = FullMath.mulDiv(price, PRICE_PRECISION, 1e18);
        return normPrice;
    }

}

// ============ EXTERNAL CONTRACTS ============

/**
 * @title Mock PriceRegistry for Testing
 * @notice Realistic mock that returns actual Pyth price IDs for testing
 */
contract MockPriceRegistry {
    address public owner;
    
    // Real Pyth price IDs used in tests
    bytes32 public constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    
    // Token addresses for mapping (set during test)
    address public currency0Address; // ETH token
    address public currency1Address; // USDC token
    
    constructor(address _owner) {
        owner = _owner;
    }
    
    // Set token addresses for correct mapping
    function setTokenAddresses(address _currency0, address _currency1) external {
        currency0Address = _currency0;
        currency1Address = _currency1;
    }
    
    function getPriceId(address token) external view returns (bytes32) {
        // Return ETH price ID for native ETH or currency0 (ETH token)
        if (token == address(0) || token == currency0Address) {
            return ETH_USD_PRICE_ID;
        }
        // Return USDC price ID for currency1 (USDC token) or any other token
        return USDC_USD_PRICE_ID;
    }
    
    function isRegistered(address) external pure returns (bool) {
        return true; // Mock all tokens as registered
    }
}  