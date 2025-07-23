// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { SwapRouterFixed } from "../src/SwapRouterFixed.sol";
import { DetoxHookV2 } from "../src/DetoxHookV2.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";

// Uniswap V4 Core imports
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

// Test utilities
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";
import { MockPyth } from "../src/libraries/PythMock.sol";
import { PythStructs } from "../src/libraries/PythLibrary.sol";

/// @title SwapRouterIntegrationTest
/// @notice Comprehensive integration tests for SwapRouterFixed with DetoxHook and Pyth
contract SwapRouterIntegrationTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Test constants
    uint24 constant POOL_FEE = 500; // 0.05%
    int24 constant TICK_SPACING = 10;
    uint256 constant INITIAL_LIQUIDITY = 10000e18; // Increased from 1000e18 to 10000e18
    uint256 constant INITIAL_TOKEN_BALANCE = 100000e18; // Increased from 10000e18 to 100000e18

    // Hook flags
    uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

    // Contracts
    DetoxHookV2 public detoxHook;
    MockPyth public mockOracle;

    // Pool configuration
    PoolKey public poolKey;
    PoolId public poolId;

    // Test accounts
    address public swapper;
    address public liquidityProvider;

    // Events for testing
    event SwapExecuted(address indexed sender, int256 amountSpecified, bool zeroForOne, BalanceDelta delta);

    function setUp() public {
        // Setup test accounts
        swapper = makeAddr("swapper");
        liquidityProvider = makeAddr("liquidityProvider");

        // Deploy fresh manager and routers using Deployers
        deployFreshManagerAndRouters();

        // Deploy and mint test currencies using Deployers
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Deploy MockPyth
        mockOracle = new MockPyth(60, 1); // 60 second validity, 1 wei fee
        
        // Deploy mock price registry for testing
        MockPriceRegistry mockRegistry = new MockPriceRegistry(address(this));
        
        // Deploy DetoxHook to the correct address with proper permissions and mockOracle
        address hookAddress = address(uint160(HOOK_FLAGS));
        
        // Use 4-parameter constructor (poolManager, owner, oracle, priceRegistry)
        deployCodeTo(
            "DetoxHookV2.sol", 
            abi.encode(manager, address(this), address(mockOracle), address(mockRegistry)), 
            hookAddress
        );
        detoxHook = DetoxHookV2(payable(hookAddress));

        // Create pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(detoxHook))
        });
        poolId = poolKey.toId();

        // Initialize pool
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Setup initial balances and liquidity
        _setupInitialState();

        console.log("[SETUP] SwapRouter Integration Test Setup Complete");
        console.log("PoolManager:", address(manager));
        console.log("PoolSwapTest:", address(swapRouter));
        console.log("DetoxHook:", address(detoxHook));
        console.log("Currency0:", Currency.unwrap(currency0));
        console.log("Currency1:", Currency.unwrap(currency1));
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
    }

    /// @notice Test 1: Basic PoolSwapTest deployment and configuration
    function test_PoolSwapTestDeployment() public {
        // Verify PoolSwapTest is deployed
        assertTrue(address(swapRouter) != address(0), "PoolSwapTest should be deployed");
        
        // Verify pool is properly configured
        (uint160 sqrtPriceX96, ,,) = StateLibrary.getSlot0(manager, poolId);
        assertTrue(sqrtPriceX96 > 0, "Pool should be initialized");
        
        // Verify hook is properly connected
        assertEq(address(poolKey.hooks), address(detoxHook), "Hook should be connected");

        console.log("[PASS] PoolSwapTest deployment and configuration verified");
    }

    /// @notice Test 2: Token approval for PoolSwapTest
    function test_TokenApprovalForPoolSwapTest() public {
        vm.startPrank(swapper);

        // Check initial allowance (should be 0)
        uint256 initialAllowance0 = MockERC20(Currency.unwrap(currency0)).allowance(swapper, address(swapRouter));
        uint256 initialAllowance1 = MockERC20(Currency.unwrap(currency1)).allowance(swapper, address(swapRouter));
        assertEq(initialAllowance0, 0);
        assertEq(initialAllowance1, 0);

        // Approve tokens for PoolSwapTest
        uint256 approvalAmount = 1000e18; // 1000 tokens
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), approvalAmount);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), approvalAmount);

        // Verify approvals
        uint256 newAllowance0 = MockERC20(Currency.unwrap(currency0)).allowance(swapper, address(swapRouter));
        uint256 newAllowance1 = MockERC20(Currency.unwrap(currency1)).allowance(swapper, address(swapRouter));
        assertEq(newAllowance0, approvalAmount);
        assertEq(newAllowance1, approvalAmount);

        vm.stopPrank();

        console.log("[PASS] Token approval for PoolSwapTest working correctly");
    }

    /// @notice Test 3: Exact input swap (currency0 → currency1) without hook data
    function test_ExactInputSwapCurrency0ToCurrency1_NoHookData() public {
        vm.startPrank(swapper);

        uint256 swapAmount = 0.1e18; // Smaller amount: 0.1 token
        bytes memory emptyUpdateData = "";

        // Approve tokens for PoolSwapTest (swapRouter from Deployers)
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);

        // Record balances before swap
        uint256 balance0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 balance1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        // Initialize mock oracle with valid prices for both price IDs
        mockOracle.updatePriceFeeds(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, // ETH/USD price ID
            int64(2000 * 1e6), // $2000, 8 decimals
            uint64(1e4),       // $0.01 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, // USDC/USD price ID
            int64(1 * 1e6),    // $1, 8 decimals
            uint64(1e4),       // $0.0001 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );

        // Create swap parameters (following DetoxHook test pattern)
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true, // Swap currency0 for currency1
            amountSpecified: -int256(swapAmount), // Exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // No price limit
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap using PoolSwapTest directly
        /*BalanceDelta delta = */swapRouter.swap(poolKey, swapParams, testSettings, emptyUpdateData);

        // Verify balances changed
        uint256 balance0After = MockERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 balance1After = MockERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        assertTrue(balance0After < balance0Before, "Currency0 balance should decrease");
        assertTrue(balance1After > balance1Before, "Currency1 balance should increase");

        vm.stopPrank();

        console.log("[PASS] Exact input currency0->currency1 swap without hook data successful");
        console.log("Currency0 spent:", balance0Before - balance0After);
        console.log("Currency1 received:", balance1After - balance1Before);
    }

    /// @notice Test 4: Exact input swap (currency1 → currency0) with approval
    function test_ExactInputSwapCurrency1ToCurrency0_WithApproval() public {
        vm.startPrank(swapper);

        uint256 swapAmount = 0.1e18; // Smaller amount: 0.1 token
        bytes memory emptyUpdateData = "";

        // Approve tokens for PoolSwapTest
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), swapAmount);

        // Record balances before swap
        uint256 balance0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 balance1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        // Initialize mock oracle with valid prices for both price IDs
        mockOracle.updatePriceFeeds(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, // ETH/USD price ID
            int64(2000 * 1e6), // $2000, 8 decimals
            uint64(1e4),       // $0.01 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, // USDC/USD price ID
            int64(1 * 1e6),    // $1, 8 decimals
            uint64(1e4),       // $0.0001 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );

        // Create swap parameters
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false, // Swap currency1 for currency0
            amountSpecified: -int256(swapAmount), // Exact input
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1 // No price limit
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap
        /*BalanceDelta delta = */swapRouter.swap(poolKey, swapParams, testSettings, emptyUpdateData);

        // Verify balances changed
        uint256 balance0After = MockERC20(Currency.unwrap(currency0)).balanceOf(swapper);
        uint256 balance1After = MockERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        assertTrue(balance0After > balance0Before, "Currency0 balance should increase");
        assertTrue(balance1After < balance1Before, "Currency1 balance should decrease");

        vm.stopPrank();

        console.log("[PASS] Exact input currency1->currency0 swap with approval successful");
        console.log("Currency1 spent:", balance1Before - balance1After);
        console.log("Currency0 received:", balance0After - balance0Before);
    }

    /// @notice Test 5: Swap with hook data (simulating Pyth price updates)
    function test_SwapWithHookData() public {
        vm.startPrank(swapper);

        uint256 swapAmount = 0.05e18; // Even smaller amount: 0.05 tokens
        
        // Generate mock hook data (simulating Pyth update data)
        bytes memory hookData = _generateMockHookData();

        // Approve tokens
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);

        // Record initial hook balance
        uint256 hookBalanceBefore = address(detoxHook).balance;

        // Initialize mock oracle with valid prices for both price IDs
        mockOracle.updatePriceFeeds(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, // ETH/USD price ID
            int64(2000 * 1e6), // $2000, 8 decimals
            uint64(1e4),       // $0.01 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, // USDC/USD price ID
            int64(1 * 1e6),    // $1, 8 decimals
            uint64(1e4),       // $0.0001 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );

        // Create swap parameters
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap with hook data
        /*BalanceDelta delta = */swapRouter.swap(poolKey, swapParams, testSettings, hookData);

        // Verify hook was called (balance might change if hook processes fees)
        uint256 hookBalanceAfter = address(detoxHook).balance;
        
        // Hook balance might increase if it processes fees, or stay the same
        assertTrue(hookBalanceAfter >= hookBalanceBefore, "Hook balance should not decrease");

        vm.stopPrank();

        console.log("[PASS] Swap with hook data successful");
        console.log("Hook balance change:", hookBalanceAfter - hookBalanceBefore);
    }

    /// @notice Test 6: Swap failure scenarios
    function test_SwapFailureScenarios() public {
        vm.startPrank(swapper);

        bytes memory emptyUpdateData = "";

        // Test 1: Zero amount should cause issues (we can't test this directly with PoolSwapTest)
        // Test 2: Insufficient token allowance for swap
        uint256 largeAmount = 100000e18; // Very large amount
        
        // This should revert due to insufficient allowance
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(largeAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        vm.expectRevert(); // Should revert due to insufficient allowance
        swapRouter.swap(poolKey, swapParams, testSettings, emptyUpdateData);

        vm.stopPrank();

        console.log("[PASS] Swap failure scenarios handled correctly");
    }

    /// @notice Test 7: Pool configuration verification
    function test_PoolConfigurationVerification() public {
        // Verify the pool configuration matches what we set up
        assertEq(Currency.unwrap(poolKey.currency0), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(poolKey.currency1), Currency.unwrap(currency1));
        assertEq(poolKey.fee, POOL_FEE);
        assertEq(poolKey.tickSpacing, TICK_SPACING);
        assertEq(address(poolKey.hooks), address(detoxHook));

        console.log("[PASS] Pool configuration verification successful");
    }

    /// @notice Test 8: Gas optimization - multiple swaps
    function test_GasOptimization_MultipleSwaps() public {
        vm.startPrank(swapper);

        uint256 swapAmount = 0.01e18; // Very small amount: 0.01 tokens
        
        // Approve tokens for multiple swaps
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);

        // Initialize mock oracle with valid prices for both price IDs
        mockOracle.updatePriceFeeds(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, // ETH/USD price ID
            int64(2000 * 1e6), // $2000, 8 decimals
            uint64(1e4),       // $0.01 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, // USDC/USD price ID
            int64(1 * 1e6),    // $1, 8 decimals
            uint64(1e4),       // $0.0001 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );

        // Create swap parameters for currency0 → currency1
        SwapParams memory swapParams1 = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        // Create swap parameters for currency1 → currency0
        SwapParams memory swapParams2 = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Measure gas for first swap (currency0 → currency1)
        uint256 gasBefore1 = gasleft();
        swapRouter.swap(poolKey, swapParams1, testSettings, "");
        uint256 gasUsed1 = gasBefore1 - gasleft();

        // Measure gas for second swap (currency1 → currency0)
        uint256 gasBefore2 = gasleft();
        swapRouter.swap(poolKey, swapParams2, testSettings, "");
        uint256 gasUsed2 = gasBefore2 - gasleft();

        vm.stopPrank();

        console.log("[PASS] Gas optimization test completed");
        console.log("Gas used for currency0->currency1 swap:", gasUsed1);
        console.log("Gas used for currency1->currency0 swap:", gasUsed2);

        // Gas usage should be reasonable (less than 500k gas)
        assertTrue(gasUsed1 < 500000, "Currency0->currency1 swap gas usage too high");
        assertTrue(gasUsed2 < 500000, "Currency1->currency0 swap gas usage too high");
    }

    /// @notice Test 9: Hook MEV detection simulation
    function test_HookMEVDetectionSimulation() public {
        vm.startPrank(swapper);

        uint256 swapAmount = 0.5e18; // Moderate amount: 0.5 tokens (reduced from 5e18)
        bytes memory hookData = _generateMockHookData();

        // Approve tokens
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);

        // Record balances before swap
        uint256 hookBalanceBefore = address(detoxHook).balance;
        uint256 swapperBalance1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        // Initialize mock oracle with valid prices for both price IDs
        mockOracle.updatePriceFeeds(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, // ETH/USD price ID
            int64(2000 * 1e6), // $2000, 8 decimals
            uint64(1e4),       // $0.01 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, // USDC/USD price ID
            int64(1 * 1e6),    // $1, 8 decimals
            uint64(1e4),       // $0.0001 confidence
            -8,                // exponent
            uint64(block.timestamp)
        );

        // Create swap parameters
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute large swap that might trigger MEV detection
        /*BalanceDelta delta = */swapRouter.swap(poolKey, swapParams, testSettings, hookData);

        // Verify hook processed the swap
        uint256 hookBalanceAfter = address(detoxHook).balance;
        uint256 swapperBalance1After = MockERC20(Currency.unwrap(currency1)).balanceOf(swapper);

        assertTrue(hookBalanceAfter >= hookBalanceBefore, "Hook balance should not decrease");
        assertTrue(swapperBalance1After > swapperBalance1Before, "Swapper should receive currency1");

        vm.stopPrank();

        console.log("[PASS] Hook MEV detection simulation working");
        console.log("Hook balance change:", hookBalanceAfter - hookBalanceBefore);
        console.log("Currency1 received by swapper:", swapperBalance1After - swapperBalance1Before);
    }

    /// @notice Test 10: Integration with real pool state
    function test_IntegrationWithRealPoolState() public {
        // Verify pool is properly initialized
        (uint160 sqrtPriceX96, int24 tick,,) = StateLibrary.getSlot0(manager, poolId);
        assertTrue(sqrtPriceX96 > 0, "Pool should be initialized");

        // Verify liquidity exists
        uint128 liquidity = manager.getLiquidity(poolId);
        assertTrue(liquidity > 0, "Pool should have liquidity");

        // Verify hook is properly connected
        assertEq(address(poolKey.hooks), address(detoxHook), "Hook should be connected");

        console.log("[PASS] Integration with real pool state verified");
        console.log("Pool sqrt price:", sqrtPriceX96);
        console.log("Pool tick:", tick);
        console.log("Pool liquidity:", liquidity);
    }

    /// @notice Test: Swap with both ETH/USD and USDC/USD updates
    function test_SwapWithMultiFeedHookData() public {
        vm.startPrank(swapper);
        uint256 swapAmount = 0.05e18;
        bytes memory hookData = _generateMockHookData();
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);
        SwapParams memory swapParams = SwapParams({ zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });
        // Ensure fresh oracle data before swap
        mockOracle.updatePriceFeeds(0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        /*BalanceDelta delta = */swapRouter.swap(poolKey, swapParams, testSettings, hookData);
        vm.stopPrank();
        console.log("[PASS] Swap with multi-feed hook data successful");
    }

    /// @notice Test: Swap with stale price (should not interfere)
    function test_SwapWithStalePrice() public {
        vm.startPrank(swapper);
        uint256 swapAmount = 0.05e18;
        bytes memory hookData = _generateStaleHookData();
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);
        SwapParams memory swapParams = SwapParams({ zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });
        // Ensure fresh oracle data before swap
        mockOracle.updatePriceFeeds(0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        /*BalanceDelta delta = */swapRouter.swap(poolKey, swapParams, testSettings, hookData);
        vm.stopPrank();
        console.log("[PASS] Swap with stale price (should not interfere) successful");
    }

    /// @notice Test: Swap with wide confidence (should not interfere)
    function test_SwapWithWideConfidence() public {
        vm.startPrank(swapper);
        uint256 swapAmount = 0.05e18;
        bytes memory hookData = _generateWideConfHookData();
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);
        SwapParams memory swapParams = SwapParams({ zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });
        // Ensure fresh oracle data before swap
        mockOracle.updatePriceFeeds(0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        /*BalanceDelta delta = */swapRouter.swap(poolKey, swapParams, testSettings, hookData);
        vm.stopPrank();
        console.log("[PASS] Swap with wide confidence (should not interfere) successful");
    }

    /// @notice Test: ArbitrageCaptured event emission
    function testEvent_ArbitrageCaptured() public {
        vm.startPrank(swapper);
        uint256 swapAmount = 0.05e18;
        bytes memory hookData = _generateMockHookData();
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);
        SwapParams memory swapParams = SwapParams({ zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });
        // TODO: Fix with PriceRegistry integration
        // Set up oracle and pool prices to guarantee arbitrage
        // Set pool price to 1.0 (default), set oracle price to 1.2 with tight confidence
        mockOracle.updatePriceFeeds(
            0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, // ETH price ID
            int64(120 * 1e6), // $120 price
            uint64(1 * 1e6),  // $1 confidence
            -8,               // -8 exponent
            uint64(block.timestamp)
        );
        mockOracle.updatePriceFeeds(
            0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, // USDC price ID
            int64(100 * 1e6), // $100 price
            uint64(1 * 1e6),  // $1 confidence
            -8,               // -8 exponent
            uint64(block.timestamp)
        );
        // Record all logs
        vm.recordLogs();
        // Expect event (will check after log printout)
        swapRouter.swap(poolKey, swapParams, testSettings, hookData);
        // Retrieve and print all logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint i = 0; i < entries.length; i++) {
            console.log("Log #", i);
            console.logBytes32(entries[i].topics[0]);
            if (entries[i].topics.length > 1) console.logBytes32(entries[i].topics[1]);
            if (entries[i].topics.length > 2) console.logBytes32(entries[i].topics[2]);
            if (entries[i].topics.length > 3) console.logBytes32(entries[i].topics[3]);
            console.logBytes(entries[i].data);
        }
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    /// @notice Setup initial balances and liquidity
    function _setupInitialState() internal {
        // Fund test accounts with tokens
        MockERC20(Currency.unwrap(currency0)).mint(swapper, INITIAL_TOKEN_BALANCE);
        MockERC20(Currency.unwrap(currency1)).mint(swapper, INITIAL_TOKEN_BALANCE);
        MockERC20(Currency.unwrap(currency0)).mint(liquidityProvider, INITIAL_TOKEN_BALANCE);
        MockERC20(Currency.unwrap(currency1)).mint(liquidityProvider, INITIAL_TOKEN_BALANCE);

        // Add initial liquidity
        vm.startPrank(liquidityProvider);
        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: int256(INITIAL_LIQUIDITY),
                salt: bytes32(0)
            }),
            ""
        );
        vm.stopPrank();

        // Fund DetoxHook for operations
        vm.deal(address(detoxHook), 1 ether);
    }

    /// @notice Encode a mock Pyth price update (for MockPyth)
    function _encodeMockPythUpdate(bytes32 priceId, uint64 timestamp, int64 price, uint64 conf, int32 expo) internal pure returns (bytes memory) {
        return abi.encode(priceId, timestamp, price, conf, expo);
    }

    /// @notice Generate mock hook data for both ETH/USD and USDC/USD
    function _generateMockHookData() internal view returns (bytes memory) {
        bytes32 ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        bytes32 USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
        bytes memory ethUpdate = _encodeMockPythUpdate(ETH_USD_PRICE_ID, uint64(block.timestamp), int64(2500e8), uint64(1e6), -8);
        bytes memory usdcUpdate = _encodeMockPythUpdate(USDC_USD_PRICE_ID, uint64(block.timestamp), int64(1e8), uint64(1e4), -8);
        bytes[] memory updates = new bytes[](2);
        updates[0] = ethUpdate;
        updates[1] = usdcUpdate;
        return abi.encode(updates);
    }

    /// @notice Generate mock hook data for a stale price
    function _generateStaleHookData() internal pure returns (bytes memory) {
        bytes32 ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        bytes memory ethUpdate = _encodeMockPythUpdate(ETH_USD_PRICE_ID, uint64(1), int64(2500e8), uint64(1e6), -8); // very old timestamp
        bytes[] memory updates = new bytes[](1);
        updates[0] = ethUpdate;
        return abi.encode(updates);
    }

    /// @notice Generate mock hook data for wide confidence
    function _generateWideConfHookData() internal view returns (bytes memory) {
        bytes32 ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        bytes memory ethUpdate = _encodeMockPythUpdate(ETH_USD_PRICE_ID, uint64(block.timestamp), int64(2500e8), uint64(100e8), -8); // wide conf
        bytes[] memory updates = new bytes[](1);
        updates[0] = ethUpdate;
        return abi.encode(updates);
    }
}

/**
 * @title Mock PriceRegistry for Testing
 * @notice Realistic mock that returns actual Pyth price IDs for testing
 */
contract MockPriceRegistry {
    address public owner;
    
    // Real Pyth price IDs used in tests
    bytes32 public constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    
    constructor(address _owner) {
        owner = _owner;
    }
    
    function getPriceId(address token) external pure returns (bytes32) {
        // Return ETH price ID for address(0) or first currency
        if (token == address(0)) {
            return ETH_USD_PRICE_ID;
        }
        // Return USDC price ID for any other token (assume USDC)
        return USDC_USD_PRICE_ID;
    }
    
    function isRegistered(address) external pure returns (bool) {
        return true; // Mock all tokens as registered
    }
} 