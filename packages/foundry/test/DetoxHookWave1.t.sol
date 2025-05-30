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

contract DetoxHookWave1Test is Test, Deployers {
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

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Deploy mock oracle for testing
        mockOracle = new MockPyth(60, 1); // 60 second validity, 1 wei fee

        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        deployCodeTo("DetoxHook.sol", abi.encode(manager, owner, address(mockOracle)), hookAddress);
        hook = DetoxHook(payable(hookAddress));

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
    }

    // ============ Wave 1 Tests: Core Infrastructure & Oracle Integration ============

    function testHookDeploymentAndPermissions() public view {
        // Verify the hook is deployed to the expected address
        assertTrue(address(hook) != address(0), "Hook should be deployed");

        // Check that hook permissions are set correctly
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap, "beforeSwap should be enabled");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be enabled");
        assertFalse(permissions.afterSwap, "afterSwap should be disabled");
        assertFalse(permissions.beforeInitialize, "beforeInitialize should be disabled");
    }

    function testOwnershipAndInitialParameters() public view {
        // Test ownership
        assertEq(hook.owner(), owner, "Owner should be set correctly");

        // Test initial parameters
        (uint256 rhoBps, uint256 stalenessThreshold) = hook.getParameters();
        assertEq(rhoBps, 8000, "Initial rho BPS should be 8000 (80%)");
        assertEq(stalenessThreshold, 60, "Initial staleness threshold should be 60 seconds");
    }

    function testParameterUpdates() public {
        // Test parameter updates as owner
        vm.prank(owner);
        hook.updateParameters(7000, 120);

        (uint256 rhoBps, uint256 stalenessThreshold) = hook.getParameters();
        assertEq(rhoBps, 7000, "Rho BPS should be updated to 7000");
        assertEq(stalenessThreshold, 120, "Staleness threshold should be updated to 120");

        // Test parameter updates fail for non-owner
        vm.expectRevert();
        hook.updateParameters(8000, 60);
    }

    function testParameterValidation() public {
        // Test invalid parameters
        vm.startPrank(owner);

        // Rho BPS too high
        vm.expectRevert("Rho BPS too high");
        hook.updateParameters(10001, 60);

        // Staleness threshold zero
        vm.expectRevert("Staleness threshold must be positive");
        hook.updateParameters(8000, 0);

        vm.stopPrank();
    }

    function testOracleInitialization() public view {
        // Test oracle initialization - should now be the mock oracle
        assertEq(address(hook.pythOracle()), address(mockOracle), "Pyth oracle should be set to mock oracle in tests");
    }

    function testPriceIdMappings() public view {
        // Test initial price ID mappings
        Currency ethCurrency = Currency.wrap(address(0));
        Currency usdcCurrency = Currency.wrap(0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d);

        bytes32 ethPriceId = hook.pythPriceIds(ethCurrency);
        bytes32 usdcPriceId = hook.pythPriceIds(usdcCurrency);

        assertEq(ethPriceId, ETH_USD_PRICE_ID, "ETH price ID should be set correctly");
        assertEq(usdcPriceId, USDC_USD_PRICE_ID, "USDC price ID should be set correctly");
    }

    function testPriceIdUpdates() public {
        // Test setting price IDs for different currencies
        bytes32 newPriceId = bytes32(uint256(0x123456));
        
        // Only owner can set price IDs
        vm.prank(owner);
        hook.setPriceId(currency0, newPriceId);
        
        // Verify the price ID was set
        assertEq(hook.pythPriceIds(currency0), newPriceId, "Price ID should be updated");
        
        // Test that non-owner cannot set price IDs
        vm.prank(address(0x999));
        vm.expectRevert("Not owner");
        hook.setPriceId(currency1, newPriceId);
    }

    function testOraclePriceRetrievalWithMockOracle() public {
        // Test oracle price retrieval with mock oracle
        // First set up a price in the mock oracle
        bytes32 testPriceId = bytes32(uint256(0x123456));
        vm.prank(owner);
        hook.setPriceId(currency0, testPriceId);
        
        // Set a price in the mock oracle
        mockOracle.updatePriceFeeds(
            testPriceId,
            int64(200 * 1e6), // $200 price
            uint64(1 * 1e6),  // $1 confidence
            -8,               // -8 exponent
            block.timestamp
        );
        
        (uint256 price, bool valid, uint256 publishTime) = hook.getOraclePrice(currency0);
        
        assertTrue(valid, "Price should be valid with mock oracle");
        assertGt(price, 0, "Price should be greater than 0");
        assertEq(publishTime, block.timestamp, "Publish time should match");
        
        console.log("Mock oracle price:", price);
        console.log("Mock oracle valid:", valid);
        console.log("Mock oracle publish time:", publishTime);
    }

    function testPoolPriceExtraction() public view {
        // Test pool price extraction using HookLibrary
        // Pool is initialized at 1:1, so price should be close to 1e8 (PRICE_PRECISION)
        
        // We can't directly call _getPoolPrice since it's internal, but we can verify
        // the pool was initialized correctly
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "Pool should be initialized at 1:1 price");
        assertTrue(sqrtPriceX96 > 0, "Pool price should be greater than 0");
    }

    function testExactOutputSwapNotModified() public {
        // Test that exact output swaps are not modified (early exit)
        uint256 userBalance0Before = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 userBalance1Before = IERC20Minimal(Currency.unwrap(currency1)).balanceOf(address(this));

        uint256 exactOutputAmount = 0.05 ether;

        // Perform exact output swap (positive amountSpecified)
        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: int256(exactOutputAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ""
        );

        uint256 userBalance0After = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 userBalance1After = IERC20Minimal(Currency.unwrap(currency1)).balanceOf(address(this));

        uint256 token0SpentByUser = userBalance0Before - userBalance0After;
        uint256 token1ReceivedByUser = userBalance1After - userBalance1Before;

        // User should receive exactly the specified output amount
        assertEq(token1ReceivedByUser, exactOutputAmount, "User should receive exact output amount");
        assertGt(token0SpentByUser, 0, "User should spend some input tokens");

        console.log("=== Exact Output Swap Test (Wave 1) ===");
        console.log("Token0 spent by user:", token0SpentByUser);
        console.log("Token1 received by user:", token1ReceivedByUser);
    }

    function testExactInputSwapWithMockOracle() public {
        // Test that exact input swaps work with mock oracle
        uint256 userBalance0Before = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 userBalance1Before = IERC20Minimal(Currency.unwrap(currency1)).balanceOf(address(this));

        uint256 exactInputAmount = 0.1 ether;

        // Perform exact input swap (negative amountSpecified)
        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(exactInputAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ""
        );

        uint256 userBalance0After = IERC20Minimal(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 userBalance1After = IERC20Minimal(Currency.unwrap(currency1)).balanceOf(address(this));

        uint256 token0SpentByUser = userBalance0Before - userBalance0After;
        uint256 token1ReceivedByUser = userBalance1After - userBalance1Before;

        // With mock oracle, hook behavior depends on price setup
        // User should spend some input amount and receive some output
        assertGt(token0SpentByUser, 0, "User should spend some input tokens");
        assertGt(token1ReceivedByUser, 0, "User should receive some output tokens");

        console.log("=== Exact Input Swap With Mock Oracle (Wave 1) ===");
        console.log("Token0 spent by user:", token0SpentByUser);
        console.log("Token1 received by user:", token1ReceivedByUser);
    }

    function testAccumulatedTokensInitialization() public view {
        // Test that accumulated tokens mapping is initialized to zero
        uint256 accumulated0 = hook.accumulatedTokens(poolId, currency0);
        uint256 accumulated1 = hook.accumulatedTokens(poolId, currency1);

        assertEq(accumulated0, 0, "Accumulated currency0 should be zero initially");
        assertEq(accumulated1, 0, "Accumulated currency1 should be zero initially");
    }

    function testTokenWithdrawal() public {
        // Test ETH withdrawal with no accumulated tokens
        vm.prank(owner);
        vm.expectRevert("Insufficient accumulated ETH");
        hook.withdrawAccumulatedETH(poolId, 1 ether, payable(owner));
        
        // Test ERC20 withdrawal with no accumulated tokens
        vm.prank(owner);
        vm.expectRevert("Insufficient accumulated tokens");
        hook.withdrawAccumulatedERC20(poolId, currency0, 1 ether, owner);
        
        // Test withdrawal with invalid recipient
        vm.prank(owner);
        vm.expectRevert("Invalid recipient");
        hook.withdrawAccumulatedETH(poolId, 1 ether, payable(address(0)));
        
        vm.prank(owner);
        vm.expectRevert("Invalid recipient");
        hook.withdrawAccumulatedERC20(poolId, currency0, 1 ether, address(0));
        
        // Test withdrawal with zero amount
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than zero");
        hook.withdrawAccumulatedETH(poolId, 0, payable(owner));
        
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than zero");
        hook.withdrawAccumulatedERC20(poolId, currency0, 0, owner);
        
        // Test that non-owner cannot withdraw
        vm.prank(address(0x999));
        vm.expectRevert("Not owner");
        hook.withdrawAccumulatedETH(poolId, 1 ether, payable(address(0x999)));
        
        vm.prank(address(0x999));
        vm.expectRevert("Not owner");
        hook.withdrawAccumulatedERC20(poolId, currency0, 1 ether, address(0x999));
        
        // Test that ETH currency cannot be withdrawn via ERC20 function
        Currency ethCurrency = Currency.wrap(address(0));
        vm.prank(owner);
        vm.expectRevert("Use withdrawAccumulatedETH for ETH");
        hook.withdrawAccumulatedERC20(poolId, ethCurrency, 1 ether, owner);
        
        // Test getAccumulatedTokens view function
        uint256 accumulatedETH = hook.getAccumulatedTokens(poolId, ethCurrency);
        uint256 accumulatedERC20 = hook.getAccumulatedTokens(poolId, currency0);
        assertEq(accumulatedETH, 0, "Should have no accumulated ETH initially");
        assertEq(accumulatedERC20, 0, "Should have no accumulated ERC20 initially");
        
        // Test that contract can receive ETH
        uint256 balanceBefore = address(hook).balance;
        payable(address(hook)).transfer(1 ether);
        uint256 balanceAfter = address(hook).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether, "Contract should be able to receive ETH");
    }
} 