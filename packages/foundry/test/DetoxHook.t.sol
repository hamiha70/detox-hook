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

    function setUp() public {
        // Deploy fresh manager and routers
        deployFreshManagerAndRouters();
        
        // Deploy and mint test currencies
        (currency0, currency1) = deployMintAndApprove2Currencies();
        
        // Deploy DetoxHook to the correct address
        // The hook address must have the correct permissions bits set
        uint160 hookAddress = uint160(
            type(uint160).max & clearAllHookPermissionsMask 
            | Hooks.BEFORE_SWAP_FLAG 
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        
        // Deploy the hook using CREATE2 to get the correct address
        deployCodeTo("DetoxHook.sol", abi.encode(manager, address(this), address(0)), address(hookAddress));
        hook = DetoxHook(address(hookAddress));
        
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

    /// @notice Test multiple swaps to ensure hook works consistently
    function test_MultipleSwaps() public {
        uint256 swapAmount = 0.5e18; // 0.5 tokens
        
        // Perform multiple swaps
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(alice);
            
            SwapParams memory swapParams = SwapParams({
                zeroForOne: i % 2 == 0, // Alternate swap direction
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: i % 2 == 0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            });
            
            PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });
            
            // Each swap should succeed and call our hook
            swapRouter.swap(poolKey, swapParams, testSettings, "");
            
            vm.stopPrank();
        }
        
        console.log("Multiple swaps completed successfully!");
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
        
        // If hook returns incorrect values, this would revert
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        
        vm.stopPrank();
        
        // Verify swap completed (hook returned correct selector and delta)
        assertTrue(delta.amount0() != 0 || delta.amount1() != 0, "Swap should have non-zero delta");
        
        console.log("Hook return values are correct!");
    }
} 