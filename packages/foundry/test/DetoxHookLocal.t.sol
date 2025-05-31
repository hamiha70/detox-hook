// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DetoxHook} from "../contracts/DetoxHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";

/**
 * @title DetoxHookLocal
 * @notice Test suite for DetoxHook on local Anvil network
 * @dev Tests the actual deployed contract at the known address
 */
contract DetoxHookLocal is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // Local deployment addresses (from localhost:3001 explorer)
    address constant LOCAL_DETOX_HOOK = 0x700b6A60ce7EaaEA56F065753d8dcB9653dbAD35;
    
    DetoxHook hook;
    PoolKey poolKey;
    PoolId poolId;
    
    // Test users
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    
    function setUp() public {
        // Deploy the V4 ecosystem locally
        deployFreshManagerAndRouters();
        
        // Connect to the deployed hook
        hook = DetoxHook(LOCAL_DETOX_HOOK);
        
        // Create test currencies
        MockERC20 tokenA = new MockERC20("TokenA", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("TokenB", "TKNB", 18);
        
        // Ensure proper currency ordering
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        
        // Create pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: hook
        });
        
        poolId = poolKey.toId();
        
        // Initialize the pool
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        
        // Mint tokens to test users
        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenB.mint(bob, 1000 ether);
        
        // Approve tokens for pool operations
        vm.startPrank(alice);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(bob);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();
        
        // Add initial liquidity
        vm.prank(alice);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }
    
    function test_LocalHookExists() public {
        // Verify the hook contract exists and has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(LOCAL_DETOX_HOOK)
        }
        
        assertGt(codeSize, 0, "Hook contract should have code");
        console.log("Local DetoxHook code size:", codeSize);
        console.log("Hook address:", LOCAL_DETOX_HOOK);
    }
    
    function test_HookPoolManagerConnection() public {
        // Verify the hook is connected to the correct pool manager
        address hookPoolManager = address(hook.poolManager());
        assertEq(hookPoolManager, address(manager), "Hook should be connected to local PoolManager");
        console.log("Hook PoolManager:", hookPoolManager);
        console.log("Expected PoolManager:", address(manager));
    }
    
    function test_HookPermissions() public {
        // Test hook permissions from address
        uint160 permissions = uint160(LOCAL_DETOX_HOOK);
        
        // Check beforeSwap permission (bit 7)
        bool hasBeforeSwap = (permissions & Hooks.BEFORE_SWAP_FLAG) != 0;
        assertTrue(hasBeforeSwap, "Hook should have beforeSwap permission");
        
        // Check beforeSwapReturnDelta permission (bit 3)
        bool hasBeforeSwapReturnDelta = (permissions & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) != 0;
        assertTrue(hasBeforeSwapReturnDelta, "Hook should have beforeSwapReturnDelta permission");
        
        console.log("Hook address permissions:", permissions);
        console.log("Has beforeSwap:", hasBeforeSwap);
        console.log("Has beforeSwapReturnDelta:", hasBeforeSwapReturnDelta);
    }
    
    function test_HookGetPermissions() public {
        // Test the getHookPermissions function
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeSwap, "beforeSwap should be true");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be true");
        assertFalse(permissions.afterSwap, "afterSwap should be false");
        assertFalse(permissions.beforeAddLiquidity, "beforeAddLiquidity should be false");
        
        console.log("Hook permissions from getHookPermissions():");
        console.log("  beforeSwap:", permissions.beforeSwap);
        console.log("  beforeSwapReturnDelta:", permissions.beforeSwapReturnDelta);
        console.log("  afterSwap:", permissions.afterSwap);
    }
    
    function test_PoolInitialization() public {
        // Verify pool was initialized correctly with the hook
        (uint160 sqrtPriceX96, int24 tick, , ) = manager.getSlot0(poolId);
        
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "Pool should be initialized at 1:1 price");
        console.log("Pool initialized with sqrtPrice:", sqrtPriceX96);
        console.log("Current tick:", tick);
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
    }
    
    function test_BasicSwap() public {
        // Get initial balances
        uint256 aliceToken0Before = poolKey.currency0.balanceOf(alice);
        uint256 aliceToken1Before = poolKey.currency1.balanceOf(alice);
        
        console.log("Alice Token0 before swap:", aliceToken0Before);
        console.log("Alice Token1 before swap:", aliceToken1Before);
        
        // Perform a swap
        vm.prank(alice);
        BalanceDelta delta = swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether, // Exact input of 1 token0
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
        
        // Get final balances
        uint256 aliceToken0After = poolKey.currency0.balanceOf(alice);
        uint256 aliceToken1After = poolKey.currency1.balanceOf(alice);
        
        console.log("Alice Token0 after swap:", aliceToken0After);
        console.log("Alice Token1 after swap:", aliceToken1After);
        console.log("Swap delta amount0:", delta.amount0());
        console.log("Swap delta amount1:", delta.amount1());
        
        // Verify swap occurred
        assertLt(aliceToken0After, aliceToken0Before, "Token0 balance should decrease");
        assertGt(aliceToken1After, aliceToken1Before, "Token1 balance should increase");
    }
    
    function test_MultipleSwaps() public {
        // Perform multiple swaps to test hook consistency
        for (uint i = 0; i < 3; i++) {
            vm.prank(bob);
            swapRouter.swap(
                poolKey,
                SwapParams({
                    zeroForOne: i % 2 == 0,
                    amountSpecified: -0.1 ether,
                    sqrtPriceLimitX96: i % 2 == 0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                }),
                PoolSwapTest.TestSettings({
                    takeClaims: false,
                    settleUsingBurn: false
                }),
                ZERO_BYTES
            );
            
            console.log("Completed swap", i + 1);
        }
        
        // Verify pool is still functional
        (uint160 sqrtPriceX96, , , ) = manager.getSlot0(poolId);
        assertGt(sqrtPriceX96, 0, "Pool should still have valid price");
        console.log("Final pool price:", sqrtPriceX96);
    }
    
    function test_HookDoesNotInterferWithLiquidity() public {
        // Test that the hook doesn't interfere with liquidity operations
        uint256 liquidityBefore = manager.getLiquidity(poolId);
        
        vm.prank(bob);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -300,
                tickUpper: 300,
                liquidityDelta: 50 ether,
                salt: bytes32(uint256(1))
            }),
            ZERO_BYTES
        );
        
        uint256 liquidityAfter = manager.getLiquidity(poolId);
        assertGt(liquidityAfter, liquidityBefore, "Liquidity should increase");
        
        console.log("Liquidity before:", liquidityBefore);
        console.log("Liquidity after:", liquidityAfter);
    }
    
    function test_DeploymentInfo() public {
        console.log("=== Local Deployment Information ===");
        console.log("Network: Local Anvil");
        console.log("DetoxHook Address:", LOCAL_DETOX_HOOK);
        console.log("PoolManager Address:", address(manager));
        console.log("SwapRouter Address:", address(swapRouter));
        console.log("ModifyLiquidityRouter Address:", address(modifyLiquidityRouter));
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Currency0:", Currency.unwrap(poolKey.currency0));
        console.log("Currency1:", Currency.unwrap(poolKey.currency1));
    }
} 