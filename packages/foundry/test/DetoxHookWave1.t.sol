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
import { MockPyth } from "../src/libraries/PythMock.sol";
import { PythStructs } from "../src/libraries/PythLibrary.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";

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

        // Set correct price IDs for the hook
        vm.prank(owner);
        hook.setPriceId(currency0, ETH_USD_PRICE_ID);
        vm.prank(owner);
        hook.setPriceId(currency1, USDC_USD_PRICE_ID);
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
            uint64(block.timestamp)
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

        // Ensure fresh oracle data before swap
        mockOracle.updatePriceFeeds(0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace, int64(2000 * 1e6), uint64(1e4), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a, int64(1 * 1e6), uint64(1e4), -8, uint64(block.timestamp));

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

    function testEvent_ParametersUpdated() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit DetoxHook.ParametersUpdated(8000, 0, 60, 0);
        hook.updateParameters(7000, 120);
    }

    function testEvent_PriceIdUpdated() public {
        bytes32 newPriceId = bytes32(uint256(0x123456));
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit DetoxHook.PriceIdUpdated(currency0, 0, 0);
        hook.setPriceId(currency0, newPriceId);
    }

    function testEvent_ETHWithdrawn() public {
        // Use correct price IDs
        bytes32 ethPriceId = ETH_USD_PRICE_ID;
        bytes32 usdcPriceId = USDC_USD_PRICE_ID;
        int64 ethPrice = int64(120 * 1e6); // $120
        int64 usdcPrice = int64(100 * 1e6); // $100
        uint64 conf = uint64(1 * 1e6); // $1 confidence
        int32 expo = -8;
        uint64 nowTs = uint64(block.timestamp);
        mockOracle.updatePriceFeeds(ethPriceId, ethPrice, conf, expo, nowTs);
        mockOracle.updatePriceFeeds(usdcPriceId, usdcPrice, conf, expo, nowTs);

        // If your hook accumulates ETH via swap, simulate that here. Otherwise, skip this test.
        // For now, just fund the contract with ETH for withdrawal test.
        payable(address(hook)).transfer(1 ether);

        // Step 2: Withdraw ETH and check event
        uint256 before = hook.getAccumulatedTokens(poolId, Currency.wrap(address(0)));
        console.log("accumulatedTokens before withdraw:", before);
        vm.prank(owner);
        vm.expectEmit(true, false, true, false);
        emit DetoxHook.ETHWithdrawn(poolId, 1 ether, owner);
        hook.withdrawAccumulatedETH(poolId, 1 ether, payable(owner));
        uint256 afterVal = hook.getAccumulatedTokens(poolId, Currency.wrap(address(0)));
        console.log("accumulatedTokens after withdraw:", afterVal);
    }

    function testEvent_ERC20Withdrawn() public {
        // Step 1: Accumulate ERC20 via a real arbitrage event (swap)
        // Use correct price IDs
        bytes32 ethPriceId = ETH_USD_PRICE_ID;
        bytes32 usdcPriceId = USDC_USD_PRICE_ID;
        int64 ethPrice = int64(120 * 1e6); // $120
        int64 usdcPrice = int64(100 * 1e6); // $100
        uint64 conf = uint64(1 * 1e6); // $1 confidence
        int32 expo = -8;
        uint64 nowTs = uint64(block.timestamp);
        mockOracle.updatePriceFeeds(ethPriceId, ethPrice, conf, expo, nowTs);
        mockOracle.updatePriceFeeds(usdcPriceId, usdcPrice, conf, expo, nowTs);

        uint256 swapAmount = 0.05e18;
        bytes memory hookData = _generateMockHookData();
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);
        SwapParams memory swapParams = SwapParams({ zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });

        // Record initial accumulated tokens
        uint256 before = hook.getAccumulatedTokens(poolId, currency0);
        console.log("accumulatedTokens before swap:", before);

        // Execute swap to trigger arbitrage capture
        swapRouter.swap(poolKey, swapParams, testSettings, hookData);

        // Check accumulatedTokens increased
        uint256 afterSwap = hook.getAccumulatedTokens(poolId, currency0);
        console.log("accumulatedTokens after swap:", afterSwap);
        assertGt(afterSwap, before, "Arbitrage should be captured");

        // Step 2: Withdraw part of the accumulated tokens and check event
        uint256 withdrawAmount = afterSwap / 2;
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit DetoxHook.ERC20Withdrawn(poolId, currency0, withdrawAmount, owner);
        hook.withdrawAccumulatedERC20(poolId, currency0, withdrawAmount, owner);
        uint256 afterWithdraw = hook.getAccumulatedTokens(poolId, currency0);
        console.log("accumulatedTokens after withdraw:", afterWithdraw);
        assertEq(afterWithdraw, afterSwap - withdrawAmount, "Withdraw should reduce accumulatedTokens");
    }

    function test_ArbitrageCaptureAndWithdraw() public {
        // Set up the oracle prices to guarantee an arbitrage opportunity
        bytes32 ethPriceId = ETH_USD_PRICE_ID;
        bytes32 usdcPriceId = USDC_USD_PRICE_ID;
        int64 ethPrice = int64(120 * 1e6); // $120
        int64 usdcPrice = int64(100 * 1e6); // $100
        uint64 conf = uint64(1 * 1e6); // $1 confidence
        int32 expo = -8;
        uint64 nowTs = uint64(block.timestamp);
        mockOracle.updatePriceFeeds(ethPriceId, ethPrice, conf, expo, nowTs);
        mockOracle.updatePriceFeeds(usdcPriceId, usdcPrice, conf, expo, nowTs);

        // Prepare swap
        uint256 swapAmount = 0.05e18;
        bytes memory hookData = _generateMockHookData();
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);
        SwapParams memory swapParams = SwapParams({ zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });

        // Record initial accumulated tokens
        uint256 before = hook.getAccumulatedTokens(poolId, currency0);
        console.log("accumulatedTokens before swap:", before);

        // Expect ArbitrageCaptured event
        vm.expectEmit(true, true, false, false);
        emit DetoxHook.ArbitrageCaptured(poolId, currency0, 0, 0, true); // Only indexed fields checked

        // Execute swap to trigger arbitrage capture
        swapRouter.swap(poolKey, swapParams, testSettings, hookData);

        // Check accumulatedTokens increased
        uint256 afterSwap = hook.getAccumulatedTokens(poolId, currency0);
        console.log("accumulatedTokens after swap:", afterSwap);
        assertGt(afterSwap, before, "Arbitrage should be captured");

        // Withdraw part of the accumulated tokens
        uint256 withdrawAmount = afterSwap / 2;
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit DetoxHook.ERC20Withdrawn(poolId, currency0, withdrawAmount, owner);
        hook.withdrawAccumulatedERC20(poolId, currency0, withdrawAmount, owner);

        // Check accumulatedTokens reduced
        uint256 afterWithdraw = hook.getAccumulatedTokens(poolId, currency0);
        console.log("accumulatedTokens after withdraw:", afterWithdraw);
        assertEq(afterWithdraw, afterSwap - withdrawAmount, "Withdraw should reduce accumulatedTokens");
    }

    function testEvent_ETHArbitrageAndWithdraw_NewPool() public {
        // Create a new pool with different tickSpacing to avoid clashing with the main pool
        int24 tickSpacing = 120;
        // Set tick for ~3000 USDC/ETH (ETH 18 decimals, USDC 6)
        // Uniswap tick formula: price = 1.0001^tick, so tick = log(price) / log(1.0001)
        // log(3000) / log(1.0001) ≈ 26214
        int24 highTick = 26280; // ~3000 USDC/ETH
        int24 tickLower = highTick - tickSpacing; 
        int24 tickUpper = highTick + tickSpacing; 
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(highTick);
        PoolKey memory newPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        PoolId newPoolId = newPoolKey.toId();
        manager.initialize(newPoolKey, sqrtPriceX96);

        // Set correct Pyth price IDs and update oracle
        int64 ethPrice = int64(2000 * 1e6); // $2000
        int64 usdcPrice = int64(1 * 1e6);   // $1
        uint64 conf = uint64(1 * 1e6);      // $1 confidence
        int32 expo = -8;
        uint64 nowTs = uint64(block.timestamp);
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, ethPrice, conf, expo, nowTs);
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, usdcPrice, conf, expo, nowTs);
        // --- DIRECTIONALITY EXPLANATION ---
        // For zeroForOne (ETH->USDC):
        //   - poolPrice: USDC/ETH (how many USDC per 1 ETH)
        //   - inputPrice: USDC/ETH (from oracle, ETH price in USDC)
        //   - outputPrice: USDC/USDC (=1, for USDC)
        // For oneForZero (USDC->ETH):
        //   - poolPrice: ETH/USDC (how many ETH per 1 USDC)
        //   - inputPrice: ETH/USDC (from oracle, USDC price in ETH)
        //   - outputPrice: ETH/ETH (=1, for ETH)
        // ... existing code ...

        // Mint tokens to this contract for liquidity provision
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 10000e18);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 10000e18);
        // Approve the router to spend both tokens
        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);
        // Add liquidity to the new pool
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 10000e18,
            salt: bytes32(uint256(2))
        });
        modifyLiquidityRouter.modifyLiquidity(newPoolKey, liquidityParams, "");

        // Fund the hook contract with ETH to pay for Pyth oracle calls
        payable(address(hook)).transfer(1 ether);

        // Perform zeroForOne exact input swap (ETH -> USDC)
        uint256 swapAmount = 0.0001e18; // much smaller swap to avoid overflow/underflow
        bytes memory hookData = _generateMockHookData();
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), swapAmount);
        SwapParams memory swapParams = SwapParams({ zeroForOne: true, amountSpecified: -int256(swapAmount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false });

        // Record initial accumulated ETH
        uint256 before = hook.getAccumulatedTokens(newPoolId, Currency.wrap(address(0)));
        console.log("accumulatedTokens (ETH) before swap:", before);

        // Execute swap to trigger ETH arbitrage capture
        swapRouter.swap(newPoolKey, swapParams, testSettings, hookData);

        // Check accumulatedTokens (ETH) increased
        uint256 afterSwap = hook.getAccumulatedTokens(newPoolId, Currency.wrap(address(0)));
        console.log("accumulatedTokens (ETH) after swap:", afterSwap);
        assertGt(afterSwap, before, "ETH arbitrage should be captured");

        // Withdraw the accumulated ETH and check event
        uint256 withdrawAmount = afterSwap;
        vm.prank(owner);
        vm.expectEmit(true, false, true, false);
        emit DetoxHook.ETHWithdrawn(newPoolId, withdrawAmount, owner);
        hook.withdrawAccumulatedETH(newPoolId, withdrawAmount, payable(owner));
        uint256 afterWithdraw = hook.getAccumulatedTokens(newPoolId, Currency.wrap(address(0)));
        console.log("accumulatedTokens (ETH) after withdraw:", afterWithdraw);
        assertEq(afterWithdraw, 0, "Withdraw should reduce accumulated ETH to zero");
    }

    function _encodeMockPythUpdate(bytes32 priceId, uint64 timestamp, int64 price, uint64 conf, int32 expo) internal pure returns (bytes memory) {
        return abi.encode(priceId, timestamp, price, conf, expo);
    }

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
} 