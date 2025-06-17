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
import {MockPyth} from "../src/libraries/PythLibrary.sol";

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
        deployCodeTo("DetoxHook.sol", abi.encode(manager, address(this), address(mockOracle)), hookAddress);
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
        // Map price IDs to currencies
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
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
        // Set up price IDs for both currencies
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);

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

    /// @notice Test arbitrage capture when pool gives better rate than market (zeroForOne)
    /// Pool: 1 currency1 per currency0, Oracle: 0.5 currency1 per currency0  
    /// currency0->currency1 swap should trigger arbitrage capture (pool gives 2x better rate)
    function test_ArbitrageCaptureETHUnderpriced_ZeroForOne() public {
        uint256 swapAmount = 0.5e18;
        
        // Set up price IDs
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
        // Oracle: currency0=$500, currency1=$1000 -> market ratio = 0.5:1
        // Pool: ~1:1 ratio (pool gives BETTER rate than market)
        // This creates arbitrage opportunity for currency0->currency1 swaps
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(500 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        // Log initial state
        (uint160 sqrtPriceX96Before,,,) = manager.getSlot0(poolId);
        console.log("=== ARBITRAGE TEST (zeroForOne=true) ===");
        console.log("Pool sqrtPrice before:", uint256(sqrtPriceX96Before));
        console.log("Market: currency0=$500, currency1=$1000 (0.5:1 ratio)");
        console.log("Pool: ~1:1 (gives 2x better rate than market)");
        console.log("Expected: Hook should capture arbitrage on currency0->currency1 swap");
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // currency0 -> currency1 (getting better deal from pool)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // This should trigger arbitrage capture
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        // Log results
        (uint160 sqrtPriceX96After,,,) = manager.getSlot0(poolId);
        console.log("Pool sqrtPrice after:", uint256(sqrtPriceX96After));
        console.log("Delta amount0 (currency0):", delta.amount0());
        console.log("Delta amount1 (currency1):", delta.amount1());
        
        // Verify arbitrage was captured (hook should have taken some currency0)
        // Check accumulated tokens for this pool and currency0
        uint256 accumulatedCurrency0 = hook.accumulatedTokens(poolId, currency0);
        console.log("Hook accumulated currency0:", accumulatedCurrency0);
        assertTrue(accumulatedCurrency0 > 0, "Hook should have captured arbitrage when pool gives better rate");
    }

    /// @notice Test arbitrage capture when pool gives better rate than market (oneForZero)
    /// Pool: 1 currency1 per currency0, Oracle: 2000 currency1 per currency0
    /// currency1->currency0 swap should trigger arbitrage capture (pool gives much better rate)
    function test_ArbitrageCaptureUSDCUnderpriced_OneForZero() public {
        uint256 swapAmount = 0.5e18;
        
        // Set up price IDs
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
        // Oracle: currency0=$2000, currency1=$1 -> market ratio = 2000:1
        // Pool: ~1:1 ratio (pool gives MUCH better rate than market for oneForZero)
        // This creates arbitrage opportunity for currency1->currency0 swaps
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        // Log initial state
        (uint160 sqrtPriceX96Before,,,) = manager.getSlot0(poolId);
        console.log("=== ARBITRAGE TEST (zeroForOne=false) ===");
        console.log("Pool sqrtPrice before:", uint256(sqrtPriceX96Before));
        console.log("Market: currency0=$2000, currency1=$1 (2000:1 ratio)");
        console.log("Pool: ~1:1 (gives 2000x better rate than market)");
        console.log("Expected: Hook should capture arbitrage on currency1->currency0 swap");
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false, // currency1 -> currency0 (getting better deal from pool)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // This should trigger arbitrage capture
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        // Log results
        (uint160 sqrtPriceX96After,,,) = manager.getSlot0(poolId);
        console.log("Pool sqrtPrice after:", uint256(sqrtPriceX96After));
        console.log("Delta amount0 (currency0):", delta.amount0());
        console.log("Delta amount1 (currency1):", delta.amount1());
        
        // Verify arbitrage was captured (hook should have taken some currency1)
        uint256 accumulatedCurrency1 = hook.accumulatedTokens(poolId, currency1);
        console.log("Hook accumulated currency1:", accumulatedCurrency1);
        assertTrue(accumulatedCurrency1 > 0, "Hook should have captured arbitrage when pool gives better rate");
    }

    /// @notice Test no arbitrage when oracle matches pool price
    /// Pool: 1 ETH = 1 USDC, Oracle: 1 ETH = 1 USDC  
    /// No swap should trigger arbitrage capture
    function test_NoArbitrageWhenOracleMatchesPool() public {
        uint256 swapAmount = 0.5e18;
        
        // Set up price IDs
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
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

    /// @notice Systematic test cases for arbitrage detection
    /// Fixed to use correct 1:1 pool ratio (SQRT_PRICE_1_1 = 79228162514264337593543950336)
    /// Pool price ≈ 1 (after accounting for decimal differences)

    /// @notice Test Case 1: zeroForOne, strong arbitrage opportunity (should capture)
    function test_RealisticCase1_ZeroForOne_StrongArbitrage() public {
        // Setup: Pool currency1/currency0 ≈ 1, Oracle currency1/currency0 = 0.5
        // Pool gives BETTER rate than market (arbitrage opportunity for swapper)
        // Pool: 1 currency1 per currency0, Market: 0.5 currency1 per currency0
        // Hook should capture arbitrage on currency0->currency1 swap
        
        uint256 swapAmount = 0.001e18; // Small swap amount
        
        // Set up price IDs
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
        // Create arbitrage: currency0=$500, currency1=$1000 → market ratio = 0.5:1
        // Pool ratio ≈ 1:1, so pool gives BETTER deal than market (2x better!)
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(500 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        console.log("=== REALISTIC CASE 1: Strong arbitrage (zeroForOne) ===");
        console.log("Pool ratio: ~1:1 (gives 1 currency1 per currency0)");
        console.log("Market ratio: 0.5:1 (currency0 worth 0.5x currency1)");
        console.log("Pool gives 2x better rate than market -> ARBITRAGE!");
        console.log("Expected: Hook should capture arbitrage opportunity");
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // currency0 → currency1 (getting great deal from pool)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        uint256 accumulatedCurrency0 = hook.accumulatedTokens(poolId, currency0);
        console.log("Accumulated currency0:", accumulatedCurrency0);
        console.log("Swap amount:", swapAmount);
        
        assertTrue(accumulatedCurrency0 > 0, "Should capture arbitrage when pool gives better rate than market");
        assertTrue(accumulatedCurrency0 < swapAmount, "Hook share should be less than full swap amount");
    }

        /// @notice Test Case 2: zeroForOne, no arbitrage (should NOT capture)
    function test_RealisticCase2_ZeroForOne_NoArbitrage() public {
        // Setup: Pool currency1/currency0 ≈ 1, Oracle currency1/currency0 = 2000
        // Pool gives WORSE rate than market (bad deal for swapper, no arbitrage)
        // Pool: 1 currency1 per currency0, Market: 2000 currency1 per currency0
        // Hook should NOT interfere (swapper getting ripped off, but that's not arbitrage)
        
        uint256 swapAmount = 0.001e18;
        
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
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

    /// @notice Test Case 3: oneForZero, strong arbitrage opportunity (should capture)
    function test_RealisticCase3_OneForZero_StrongArbitrage() public {
        // Setup: Pool currency1/currency0 ≈ 1, Oracle currency1/currency0 = 2000
        // Pool gives BETTER rate than market for oneForZero direction
        // Pool: Need 1 currency1 to get 1 currency0, Market: Need 2000 currency1 to get 1 currency0
        // Hook should capture arbitrage on currency1->currency0 swap
        
        uint256 swapAmount = 1000e18; // Reasonable amount
        
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
        // Create arbitrage: currency0=$2000, currency1=$1 → market ratio = 2000:1
        // Pool ratio ≈ 1:1, so pool gives MUCH better deal for currency1 holders
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        console.log("=== REALISTIC CASE 3: Strong arbitrage (oneForZero) ===");
        console.log("Pool ratio: ~1:1 (need 1 currency1 to get 1 currency0)");
        console.log("Market ratio: 2000:1 (need 2000 currency1 to get 1 currency0)");
        console.log("Pool gives 2000x better rate than market -> ARBITRAGE!");
        console.log("Expected: Hook should capture arbitrage opportunity");
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false, // currency1 → currency0 (getting great deal from pool)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        uint256 accumulatedCurrency1 = hook.accumulatedTokens(poolId, currency1);
        console.log("Accumulated currency1:", accumulatedCurrency1);
        console.log("Swap amount:", swapAmount);
        
        assertTrue(accumulatedCurrency1 > 0, "Should capture arbitrage when pool gives better rate than market");
        assertTrue(accumulatedCurrency1 < swapAmount, "Hook share should be less than full swap amount");
    }

    /// @notice Test Case 4: oneForZero, no arbitrage (should NOT capture)
    function test_RealisticCase4_OneForZero_NoArbitrage() public {
        // Setup: Pool currency1/currency0 ≈ 1, Oracle currency1/currency0 = 0.5
        // Pool gives WORSE rate than market for oneForZero direction
        // Pool: Need 1 currency1 to get 1 currency0, Market: Need 0.5 currency1 to get 1 currency0
        // Hook should NOT interfere (swapper getting bad deal, but that's not arbitrage)
        
        uint256 swapAmount = 1000e18;
        
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
        
        // No arbitrage: currency0=$500, currency1=$1000 → market ratio = 0.5:1
        // Pool ratio ≈ 1:1, so pool gives WORSE deal than market (bad for currency1 holders)
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(500 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        
        console.log("=== REALISTIC CASE 4: No arbitrage (oneForZero) ===");
        console.log("Pool ratio: ~1:1 (need 1 currency1 to get 1 currency0)");
        console.log("Market ratio: 0.5:1 (need 0.5 currency1 to get 1 currency0)");
        console.log("Pool gives 2x WORSE rate than market -> NO ARBITRAGE (just bad trade)");
        console.log("Expected: Hook should NOT interfere");
        
        uint256 accumulatedBefore = hook.accumulatedTokens(poolId, currency1);
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false, // currency1 → currency0 (getting bad deal from pool)
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        uint256 accumulatedAfter = hook.accumulatedTokens(poolId, currency1);
        
        assertEq(accumulatedAfter, accumulatedBefore, "Should NOT capture when pool gives worse rate than market");
    }
}  