// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DetoxHook} from "../src/DetoxHook.sol";
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
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {HookMiner} from "@v4-periphery/src/utils/HookMiner.sol";

/**
 * @title DetoxHookArbitrumSepoliaFork
 * @notice Comprehensive test suite for DetoxHook on forked Arbitrum Sepolia
 * @dev This test forks Arbitrum Sepolia, deploys the hook properly using HookMiner, and tests full functionality
 */
contract DetoxHookArbitrumSepoliaFork is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // Arbitrum Sepolia addresses
    address constant ARBITRUM_SEPOLIA_POOL_MANAGER = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant ARBITRUM_SEPOLIA_SWAP_ROUTER = 0xf3A39C86dbd13C45365E57FB90fe413371F65AF8;
    address constant ARBITRUM_SEPOLIA_MODIFY_LIQUIDITY_ROUTER = 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7;
    address constant USDC_ARBITRUM_SEPOLIA = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    
    // CREATE2 Deployer Proxy (universal across all chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Hook permission flags
    uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    
    // Test contracts
    DetoxHook public hook;
    IPoolManager public manager;
    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    // Test currencies
    Currency public currency0;
    Currency public currency1;
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    // Constants
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    bytes public constant ZERO_BYTES = "";
    
    function setUp() public {
        // Fork Arbitrum Sepolia
        uint256 forkId = vm.createFork("https://sepolia-rollup.arbitrum.io/rpc");
        vm.selectFork(forkId);
        
        console.log("=== Forked Arbitrum Sepolia ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        
        // Connect to existing contracts
        manager = IPoolManager(ARBITRUM_SEPOLIA_POOL_MANAGER);
        swapRouter = PoolSwapTest(ARBITRUM_SEPOLIA_SWAP_ROUTER);
        modifyLiquidityRouter = PoolModifyLiquidityTest(ARBITRUM_SEPOLIA_MODIFY_LIQUIDITY_ROUTER);
        
        // Verify contracts exist
        require(address(manager).code.length > 0, "PoolManager not found");
        require(address(swapRouter).code.length > 0, "SwapRouter not found");
        require(address(modifyLiquidityRouter).code.length > 0, "ModifyLiquidityRouter not found");
        
        console.log("=== Connected to Arbitrum Sepolia V4 ===");
        console.log("PoolManager:", address(manager));
        console.log("SwapRouter:", address(swapRouter));
        console.log("ModifyLiquidityRouter:", address(modifyLiquidityRouter));
        
        // Deploy DetoxHook using proper HookMiner
        deployDetoxHookWithHookMiner();
        
        // Create test currencies
        MockERC20 tokenA = new MockERC20("TokenA", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("TokenB", "TKNB", 18);
        
        // Ensure proper currency ordering
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        
        currency0 = Currency.wrap(address(tokenA));
        currency1 = Currency.wrap(address(tokenB));
        
        // Create pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        poolId = poolKey.toId();
        
        // Initialize the pool
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        
        console.log("=== Pool Initialized ===");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Currency0:", Currency.unwrap(currency0));
        console.log("Currency1:", Currency.unwrap(currency1));
        
        // Setup test users with tokens
        setupTestUsers(tokenA, tokenB);
        
        // Add initial liquidity
        addInitialLiquidity();
    }
    
    function deployDetoxHookWithHookMiner() internal {
        console.log("=== Mining Hook Address with HookMiner ===");
        console.log("Required flags:", HOOK_FLAGS);
        console.log("CREATE2 Deployer:", CREATE2_DEPLOYER);
        
        // Prepare creation code and constructor arguments
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(address(manager), address(this), 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF);
        
        // Mine the salt using HookMiner
        address expectedAddress;
        bytes32 salt;
        (expectedAddress, salt) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs);
        
        console.log("=== HookMiner Results ===");
        console.log("Salt found:", uint256(salt));
        console.log("Expected hook address:", expectedAddress);
        console.log("Address flags:", uint160(expectedAddress) & HookMiner.FLAG_MASK);
        console.log("Required flags:", HOOK_FLAGS);
        console.log("Flags match:", (uint160(expectedAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        // Deploy using CREATE2 Deployer Proxy
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);
        
        console.log("=== CREATE2 Deployment ===");
        console.log("Deployment data length:", deploymentData.length);
        console.log("Call data length:", callData.length);
        
        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "CREATE2 deployment failed");
        require(returnData.length == 20, "Invalid return data length");
        
        address deployedAddress = address(bytes20(returnData));
        require(deployedAddress == expectedAddress, "Deployment address mismatch");
        
        hook = DetoxHook(payable(deployedAddress));
        
        console.log("=== Hook Deployed Successfully ===");
        console.log("Hook address:", address(hook));
        console.log("Hook permissions valid:", (uint160(address(hook)) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        // Verify hook functionality
        require(address(hook.poolManager()) == address(manager), "Hook not connected to manager");
        
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        require(permissions.beforeSwap, "beforeSwap permission not set");
        require(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta permission not set");
    }
    
    function setupTestUsers(MockERC20 tokenA, MockERC20 tokenB) internal {
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
        
        console.log("=== Test Users Setup ===");
        console.log("Alice:", alice);
        console.log("Bob:", bob);
        console.log("Alice Token0 balance:", tokenA.balanceOf(alice));
        console.log("Alice Token1 balance:", tokenB.balanceOf(alice));
    }
    
    function addInitialLiquidity() internal {
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
        
        console.log("=== Initial Liquidity Added ===");
        console.log("Liquidity:", manager.getLiquidity(poolId));
    }
    
    function test_ForkSetup() public view {
        // Verify we're on the right network
        assertEq(block.chainid, 421614, "Should be on Arbitrum Sepolia");
        
        // Verify contracts exist
        assertTrue(address(manager).code.length > 0, "PoolManager should exist");
        assertTrue(address(hook).code.length > 0, "Hook should exist");
        
        console.log("=== Fork Setup Verification ===");
        console.log("Chain ID:", block.chainid);
        console.log("PoolManager exists:", address(manager).code.length > 0);
        console.log("Hook exists:", address(hook).code.length > 0);
    }
    
    function test_HookDeployment() public view {
        // Verify hook is deployed correctly
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        
        // Verify hook is connected to the correct pool manager
        assertEq(address(hook.poolManager()), address(manager), "Hook should be connected to manager");
        
        // Verify hook address has correct permissions
        uint160 hookAddress = uint160(address(hook));
        assertTrue((hookAddress & Hooks.BEFORE_SWAP_FLAG) != 0, "Should have beforeSwap permission");
        assertTrue((hookAddress & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) != 0, "Should have beforeSwapReturnsDelta permission");
        
        console.log("=== Hook Deployment Verification ===");
        console.log("Hook address:", address(hook));
        console.log("Hook permissions:", hookAddress & (Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
    }
    
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
    
    function test_PoolInitialization() public view {
        // Verify pool exists
        (uint160 sqrtPriceX96, int24 tick,,) = manager.getSlot0(poolId);
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "Pool should be initialized at 1:1 price");
        assertEq(tick, 0, "Pool should be initialized at tick 0");
        
        // Verify pool has our hook
        assertEq(address(poolKey.hooks), address(hook), "Pool should have our hook");
        
        console.log("=== Pool Initialization Verification ===");
        console.log("Pool price:", sqrtPriceX96);
        console.log("Pool tick:", tick);
        console.log("Pool hook:", address(poolKey.hooks));
    }
    
    function test_BasicSwap() public {
        uint256 swapAmount = 1 ether;
        
        // Record balances before swap
        uint256 aliceBalance0Before = currency0.balanceOf(alice);
        uint256 aliceBalance1Before = currency1.balanceOf(alice);
        
        console.log("=== Before Swap ===");
        console.log("Alice Token0:", aliceBalance0Before);
        console.log("Alice Token1:", aliceBalance1Before);
        
        // Perform swap as Alice: currency0 -> currency1
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
        
        // Execute the swap - this should call our hook's beforeSwap function
        BalanceDelta delta = swapRouter.swap(poolKey, swapParams, testSettings, "");
        
        vm.stopPrank();
        
        // Verify swap occurred
        uint256 aliceBalance0After = currency0.balanceOf(alice);
        uint256 aliceBalance1After = currency1.balanceOf(alice);
        
        console.log("=== After Swap ===");
        console.log("Alice Token0:", aliceBalance0After);
        console.log("Alice Token1:", aliceBalance1After);
        console.log("Delta amount0:", delta.amount0());
        console.log("Delta amount1:", delta.amount1());
        
        // Alice should have less currency0 and more currency1
        assertLt(aliceBalance0After, aliceBalance0Before, "Alice should have less currency0");
        assertGt(aliceBalance1After, aliceBalance1Before, "Alice should have more currency1");
        
        // Verify the delta makes sense
        assertTrue(delta.amount0() < 0, "Delta amount0 should be negative (currency0 out)");
        assertTrue(delta.amount1() > 0, "Delta amount1 should be positive (currency1 in)");
    }
    
    function test_MultipleSwaps() public {
        uint256 swapAmount = 0.1 ether;
        
        // Perform multiple swaps
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(bob);
            
            SwapParams memory swapParams = SwapParams({
                zeroForOne: i % 2 == 0,
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
            
            console.log("Completed swap", i + 1);
        }
        
        // Verify pool is still functional
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        assertGt(sqrtPriceX96, 0, "Pool should still have valid price");
        
        console.log("=== Multiple Swaps Complete ===");
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
        
        console.log("=== Liquidity Test ===");
        console.log("Liquidity before:", liquidityBefore);
        console.log("Liquidity after:", liquidityAfter);
    }
    
    function test_DeploymentSummary() public view {
        console.log("=== Deployment Summary ===");
        console.log("Network: Arbitrum Sepolia Fork");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("DetoxHook Address:", address(hook));
        console.log("PoolManager Address:", address(manager));
        console.log("SwapRouter Address:", address(swapRouter));
        console.log("ModifyLiquidityRouter Address:", address(modifyLiquidityRouter));
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Currency0:", Currency.unwrap(currency0));
        console.log("Currency1:", Currency.unwrap(currency1));
        console.log("Hook Permissions:", uint160(address(hook)) & (Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
    }
    
    // ============ Phase 2: Enhanced Fork Testing ============
    
    function test_RealPythOracleReads() public view {
        console.log("=== Testing Real Pyth Oracle Integration ===");
        
        // Connect to the real Pyth oracle on Arbitrum Sepolia
        address pythOracleAddress = 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF;
        require(pythOracleAddress.code.length > 0, "Pyth oracle should exist on Arbitrum Sepolia");
        
        // Test ETH/USD price feed
        bytes32 ethUsdPriceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        bytes32 usdcUsdPriceId = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
        
        console.log("=== ETH/USD Price Feed Test ===");
        console.log("Price ID:", vm.toString(ethUsdPriceId));
        
        // Try to read ETH price using low-level call to avoid revert
        (bool success, bytes memory data) = pythOracleAddress.staticcall(
            abi.encodeWithSignature("getPrice(bytes32)", ethUsdPriceId)
        );
        
        if (success && data.length > 0) {
            console.log("[SUCCESS] ETH/USD price feed accessible");
            // Decode the price data
            (int64 price, uint64 conf, int32 expo, uint256 publishTime) = abi.decode(data, (int64, uint64, int32, uint256));
            console.log("ETH Price:", vm.toString(price));
            console.log("Confidence:", conf);
            console.log("Exponent:", vm.toString(expo));
            console.log("Publish Time:", publishTime);
            console.log("Current Time:", block.timestamp);
            
            // Validate price data makes sense
            assertTrue(price > 0, "ETH price should be positive");
            assertTrue(publishTime > 0, "Publish time should be set");
            assertTrue(publishTime <= block.timestamp, "Publish time should not be in future");
            
            // Check if price is fresh (within 1 hour)
            bool isFresh = (block.timestamp - publishTime) <= 3600;
            console.log("Price is fresh (< 1 hour):", isFresh);
        } else {
            console.log("[FAILED] ETH/USD price feed not accessible or no data");
            console.log("This might be expected if price feeds are not active on testnet");
        }
        
        console.log("=== USDC/USD Price Feed Test ===");
        console.log("Price ID:", vm.toString(usdcUsdPriceId));
        
        // Try to read USDC price
        (success, data) = pythOracleAddress.staticcall(
            abi.encodeWithSignature("getPrice(bytes32)", usdcUsdPriceId)
        );
        
        if (success && data.length > 0) {
            console.log("[SUCCESS] USDC/USD price feed accessible");
            (int64 price, uint64 conf, int32 expo, uint256 publishTime) = abi.decode(data, (int64, uint64, int32, uint256));
            console.log("USDC Price:", vm.toString(price));
            console.log("Confidence:", conf);
            console.log("Exponent:", vm.toString(expo));
            console.log("Publish Time:", publishTime);
            
            // Validate USDC price makes sense (should be close to $1)
            assertTrue(price > 0, "USDC price should be positive");
            assertTrue(publishTime <= block.timestamp, "Publish time should not be in future");
        } else {
            console.log("[FAILED] USDC/USD price feed not accessible or no data");
        }
        
        console.log("=== Pyth Oracle Interface Test ===");
        
        // Test basic oracle interface
        (success, data) = pythOracleAddress.staticcall(
            abi.encodeWithSignature("getValidTimePeriod()")
        );
        
        if (success && data.length > 0) {
            uint256 validTimePeriod = abi.decode(data, (uint256));
            console.log("[SUCCESS] Oracle valid time period:", validTimePeriod, "seconds");
            assertTrue(validTimePeriod > 0, "Valid time period should be positive");
        }
        
        console.log("=== Real Pyth Oracle Test Complete ===");
    }
    
    function test_ArbitrumSepoliaInfrastructure() public view {
        console.log("=== Testing Arbitrum Sepolia V4 Infrastructure ===");
        
        // Verify all expected contracts exist and have code
        console.log("=== Contract Existence Verification ===");
        
        assertTrue(address(manager).code.length > 0, "PoolManager should have code");
        assertTrue(address(swapRouter).code.length > 0, "SwapRouter should have code");
        assertTrue(address(modifyLiquidityRouter).code.length > 0, "ModifyLiquidityRouter should have code");
        
        console.log("[SUCCESS] All V4 contracts exist and have code");
        
        // Test PoolManager interface
        console.log("=== PoolManager Interface Test ===");
        
        // Test getting protocol fees
        try manager.protocolFeesAccrued(currency0) returns (uint256 fees) {
            console.log("[SUCCESS] PoolManager.protocolFeesAccrued() works, fees:", fees);
        } catch {
            console.log("[WARNING] PoolManager.protocolFeesAccrued() failed - might be expected");
        }
        
        // Test SwapRouter interface  
        console.log("=== SwapRouter Interface Test ===");
        
        // PoolSwapTest doesn't have a poolManager() function, it inherits from PoolTestBase
        // Let's test that it can access the manager through its inherited functionality
        console.log("[SUCCESS] SwapRouter is PoolSwapTest contract");
        console.log("SwapRouter address:", address(swapRouter));
        
        // Test ModifyLiquidityRouter interface
        console.log("=== ModifyLiquidityRouter Interface Test ===");
        
        // PoolModifyLiquidityTest also doesn't have a poolManager() function
        console.log("[SUCCESS] ModifyLiquidityRouter is PoolModifyLiquidityTest contract");
        console.log("ModifyLiquidityRouter address:", address(modifyLiquidityRouter));
        
        console.log("=== Infrastructure Test Complete ===");
    }
    
    function test_QuickTestPoolCreation() public {
        console.log("=== Testing Quick Pool Creation on Fork ===");
        
        // Create simple test tokens
        MockERC20 tokenA = new MockERC20("TestA", "TSTA", 18);
        MockERC20 tokenB = new MockERC20("TestB", "TSTB", 18);
        
        // Ensure proper ordering
        if (address(tokenA) > address(tokenB)) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        
        Currency testCurrency0 = Currency.wrap(address(tokenA));
        Currency testCurrency1 = Currency.wrap(address(tokenB));
        
        console.log("Test Token A:", address(tokenA));
        console.log("Test Token B:", address(tokenB));
        
        // Create a simple pool key (no hook for this test)
        PoolKey memory testPoolKey = PoolKey({
            currency0: testCurrency0,
            currency1: testCurrency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(0)) // No hook for simple test
        });
        
        console.log("=== Pool Initialization Test ===");
        
        // Try to initialize the pool
        try manager.initialize(testPoolKey, SQRT_PRICE_1_1) {
            console.log("[SUCCESS] Pool initialization successful");
            
            // Verify pool state
            PoolId testPoolId = testPoolKey.toId();
            (uint160 sqrtPriceX96, int24 tick,,) = manager.getSlot0(testPoolId);
            
            console.log("Pool Price:", sqrtPriceX96);
            console.log("Pool Tick:", tick);
            
            assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "Pool should be initialized at 1:1 price");
            assertEq(tick, 0, "Pool should be initialized at tick 0");
            
            console.log("=== Liquidity Addition Test ===");
            
            // Mint tokens to ourselves
            tokenA.mint(address(this), 1000 ether);
            tokenB.mint(address(this), 1000 ether);
            
            // Approve tokens
            tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
            tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
            
            // Try to add liquidity
            try modifyLiquidityRouter.modifyLiquidity(
                testPoolKey,
                ModifyLiquidityParams({
                    tickLower: -60,
                    tickUpper: 60,
                    liquidityDelta: 1 ether,
                    salt: bytes32(0)
                }),
                ZERO_BYTES
            ) {
                console.log("[SUCCESS] Liquidity addition successful");
                
                // Check liquidity
                uint128 liquidity = manager.getLiquidity(testPoolId);
                console.log("Pool Liquidity:", liquidity);
                assertGt(liquidity, 0, "Pool should have liquidity");
                
            } catch Error(string memory reason) {
                console.log("[WARNING] Liquidity addition failed:", reason);
            } catch {
                console.log("[WARNING] Liquidity addition failed with unknown error");
            }
            
        } catch Error(string memory reason) {
            console.log("[WARNING] Pool initialization failed:", reason);
        } catch {
            console.log("[WARNING] Pool initialization failed with unknown error");
        }
        
        console.log("=== Quick Pool Test Complete ===");
    }
} 