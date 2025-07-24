// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Uniswap V4 Core imports
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams, ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Deployers } from "@uniswap/v4-core/test/utils/Deployers.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

// Test utilities
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";

// Our contracts
import { DetoxHookV2 } from "../src/DetoxHookV2.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";
import { MockPyth } from "../src/libraries/PythMock.sol";
import { PythStructs } from "../src/libraries/PythLibrary.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";
import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";
import { Create2Deployer } from "../src/test-helpers/Create2Deployer.sol";

/**
 * @title DetoxHookV2Test
 * @notice Comprehensive test suite for DetoxHookV2 with proven arbitrage detection patterns
 * @dev Based on successful legacy test patterns from SimplifiedDetoxHook
 */
contract DetoxHookV2Test is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // Test contracts
    DetoxHookV2 public hook;
    PriceRegistry public priceRegistry;
    MockPyth public mockOracle;
    Create2Deployer public create2Deployer;
    
    // Pool configurations
    PoolKey public simplePoolKey;    // 1:1 TOK1/TOK2 pool
    PoolKey public realisticPoolKey; // ETH/USDC pool at $2500
    PoolId public simplePoolId;
    PoolId public realisticPoolId;
    
    // Test parameters
    uint24 public constant FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;
    
    // Hook deployment constants
    uint160 public constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    
    // Pyth price IDs
    bytes32 constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    
    // Test token price IDs (different from real ETH/USDC)
    bytes32 constant TOK1_PRICE_ID = 0x1111111111111111111111111111111111111111111111111111111111111111;
    bytes32 constant TOK2_PRICE_ID = 0x2222222222222222222222222222222222222222222222222222222222222222;
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    // Realistic pool tokens
    MockERC20 public realUSDC;

    /// @notice Format ETH amount for display (18 decimals)
    function formatETH(uint256 amount) internal pure returns (string memory) {
        if (amount == 0) return "0.0 ETH";
        
        uint256 ethAmount = amount / 1e18;
        uint256 decimals = (amount % 1e18) / 1e15; // 3 decimal places
        
        if (decimals == 0) {
            return string(abi.encodePacked(_uintToString(ethAmount), ".0 ETH"));
        } else {
            return string(abi.encodePacked(_uintToString(ethAmount), ".", _uintToString(decimals), " ETH"));
        }
    }

    /// @notice Format USDC amount for display (6 decimals)
    function formatUSDC(uint256 amount) internal pure returns (string memory) {
        if (amount == 0) return "0.0 USDC";
        
        uint256 usdcAmount = amount / 1e6;
        uint256 decimals = (amount % 1e6) / 1e3; // 3 decimal places
        
        if (decimals == 0) {
            return string(abi.encodePacked(_uintToString(usdcAmount), ".0 USDC"));
        } else {
            return string(abi.encodePacked(_uintToString(usdcAmount), ".", _uintToString(decimals), " USDC"));
        }
    }

    /// @notice Convert uint to string helper
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }

    function setUp() external {
        console.log("--- SETUP: DetoxHookV2 Test Environment ---");
        
        // Deploy fresh manager and routers using Deployers
        deployFreshManagerAndRouters();
        console.log("[OK] Deployed PoolManager and routers");
        
        // Deploy CREATE2 deployer for proper hook deployment
        create2Deployer = new Create2Deployer();
        console.log("[OK] Deployed CREATE2 deployer");
        
        // Deploy mock oracle
        mockOracle = new MockPyth(60, 1); // 60 second validity, 1 wei fee
        console.log("[OK] Deployed MockPyth oracle");
        
        // Deploy PriceRegistry
        priceRegistry = new PriceRegistry(address(this));
        console.log("[OK] Deployed PriceRegistry");
        
        // Deploy DetoxHookV2 using proper CREATE2 deployment
        _deployDetoxHookV2WithCreate2();
        console.log("[OK] Deployed DetoxHookV2 with correct permissions");
        
        // Fund the hook with ETH for Pyth oracle fees
        vm.deal(address(hook), 10 ether);
        console.log("[OK] Funded hook with 10 ETH for oracle fees");
        
        // Setup simple 1:1 pool (TOK1/TOK2)
        _setupSimplePool();
        
        // Setup realistic ETH/USDC pool
        _setupRealisticPool();
        
        console.log("--- SETUP COMPLETE ---");
    }

    /// @notice Deploy DetoxHookV2 using proper CREATE2 deployment
    function _deployDetoxHookV2WithCreate2() internal {
        console.log("=== Deploying DetoxHookV2 with CREATE2 ===");
        console.log("Required flags:", HOOK_FLAGS);
        
        // Prepare creation code and constructor arguments
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(manager),
            address(this), // owner
            address(mockOracle),
            address(priceRegistry)
        );
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        // Mine the salt using HookMiner to find correct address
        address expectedAddress;
        bytes32 salt;
        (expectedAddress, salt) = HookMiner.find(address(create2Deployer), HOOK_FLAGS, creationCode, constructorArgs);
        
        console.log("=== HookMiner Results ===");
        console.log("Salt found:", uint256(salt));
        console.log("Expected hook address:", expectedAddress);
        console.log("Address flags:", uint160(expectedAddress) & HookMiner.FLAG_MASK);
        console.log("Required flags:", HOOK_FLAGS);
        console.log("Flags match:", (uint160(expectedAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        // Deploy using CREATE2
        console.log("=== Deploying with CREATE2 ===");
        address deployedAddress = create2Deployer.deploy(salt, bytecode);
        
        // Create the hook instance
        hook = DetoxHookV2(payable(deployedAddress));
        
        console.log("=== Hook Deployed Successfully ===");
        console.log("Hook address:", address(hook));
        console.log("Hook permissions valid:", (uint160(address(hook)) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        // Verify hook functionality
        require(address(hook.poolManager()) == address(manager), "Hook not connected to manager");
        require(address(hook.priceRegistry()) == address(priceRegistry), "Hook not connected to price registry");
        require(address(hook.pythOracle()) == address(mockOracle), "Hook not connected to oracle");
        require(hook.owner() == address(this), "Hook owner not set correctly");
        
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        require(permissions.beforeSwap, "beforeSwap permission not set");
        require(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta permission not set");
        
        console.log("Hook deployment verification complete");
    }

    /// @notice Setup simple 1:1 pool using Deployers currencies
    function _setupSimplePool() internal {
        console.log("Setting up simple 1:1 pool...");
        
        // Deploy and mint test currencies using Deployers
        (currency0, currency1) = deployMintAndApprove2Currencies();
        
        // Configure PriceRegistry for simple pool
        address[] memory tokens = new address[](2);
        bytes32[] memory priceIds = new bytes32[](2);
        string[] memory symbols = new string[](2);
        
        tokens[0] = Currency.unwrap(currency0);
        tokens[1] = Currency.unwrap(currency1);
        priceIds[0] = TOK1_PRICE_ID;   // TOK1 -> ETH price feed
        priceIds[1] = TOK2_PRICE_ID; // TOK2 -> USDC price feed
        symbols[0] = "TOK1";
        symbols[1] = "TOK2";
        
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        console.log("[OK] Configured PriceRegistry for simple pool");
        
        // Create simple pool key
        simplePoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        simplePoolId = simplePoolKey.toId();
        
        // Initialize pool at 1:1 price
        manager.initialize(simplePoolKey, SQRT_PRICE_1_1);
        console.log("[OK] Initialized simple pool at 1:1 price");
        
        // Add liquidity
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: 1000e18,
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(simplePoolKey, liquidityParams, "");
        console.log("[OK] Added liquidity to simple pool");
        
        // Mint tokens to test users
        MockERC20(Currency.unwrap(currency0)).mint(alice, 1000e18);
        MockERC20(Currency.unwrap(currency1)).mint(alice, 1000e18);
        
        // Approve tokens for alice
        vm.startPrank(alice);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        console.log("[OK] Simple pool setup complete");
    }

    /// @notice Setup realistic ETH/USDC pool using native ETH and MockUSDC
    /// @dev Uses address(0) for native ETH and MockERC20 for USDC (since we can't mint real USDC)
    function _setupRealisticPool() internal {
        console.log("Setting up realistic ETH/USDC pool...");
        
        // Use native ETH (address(0)) and create MockUSDC only
        Currency ethCurrency = Currency.wrap(address(0)); // Native ETH
        realUSDC = new MockERC20("USD Coin", "USDC", 6);
        Currency usdcCurrency = Currency.wrap(address(realUSDC));
        
        // Currency ordering: address(0) < any_other_address, so ETH is always currency0
        Currency realisticCurrency0 = ethCurrency;  // ETH (address(0))
        Currency realisticCurrency1 = usdcCurrency; // USDC (MockERC20)
        console.log("[OK] Currency ordering: ETH (currency0), USDC (currency1)");
        console.log("[OK] ETH address:", Currency.unwrap(ethCurrency));
        console.log("[OK] USDC address:", Currency.unwrap(usdcCurrency));
        
        // Configure PriceRegistry for realistic pool
        priceRegistry.setPriceMapping(address(0), ETH_USD_PRICE_ID, "ETH"); // Native ETH
        priceRegistry.setPriceMapping(address(realUSDC), USDC_USD_PRICE_ID, "USDC");
        console.log("[OK] Configured PriceRegistry for realistic pool");
        
        // Create realistic pool key
        realisticPoolKey = PoolKey({
            currency0: realisticCurrency0,
            currency1: realisticCurrency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        realisticPoolId = realisticPoolKey.toId();
        
        // Calculate proper sqrtPrice for 1 ETH = 2500 USDC with correct precision
        // ETH (18 decimals) is currency0, USDC (6 decimals) is currency1
        // Price = currency1/currency0 = USDC/ETH in 1e18 precision
        // For 1 ETH = 2500 USDC: (2500 * 1e6) / (1 * 1e18) = 2500 / 1e12 = 2.5e-9
        // To get 1e18 precision: 2.5e-9 * 1e18 = 2.5e9
        uint256 poolPriceTarget = 2500000000; // 2.5e9 = 2500 USDC per ETH in correct precision
        uint160 sqrtPriceX96 = HookLibrary.priceToSqrtPrice(poolPriceTarget);
        console.log("[OK] Pool setup: 1 ETH = 2500 USDC");
        console.log("[OK] Target price value:", poolPriceTarget);
        
        // Initialize pool
        int24 actualTick = manager.initialize(realisticPoolKey, sqrtPriceX96);
        console.log("[OK] Initialized realistic pool at 1 ETH = 2500 USDC");
        console.log("[DEBUG] Actual pool tick:", uint256(int256(actualTick)));
        
        // Provide ETH and USDC for liquidity
        uint256 ethLiquidityAmount = 1000 * 1e18;      // 1000 ETH (increased from 100)
        uint256 usdcLiquidityAmount = 2500000 * 1e6;   // 2.5M USDC (increased from 250k)
        
        // For native ETH: use vm.deal() in tests (this contract gets ETH)
        vm.deal(address(this), ethLiquidityAmount);
        
        // For USDC: mint MockERC20 tokens
        realUSDC.mint(address(this), usdcLiquidityAmount);
        
        // Approve USDC for liquidity provision (ETH doesn't need approval)
        realUSDC.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        // Add liquidity with sufficient amounts for realistic testing
        // Use a much larger liquidity delta to ensure sufficient pool liquidity
        uint256 LIQUIDITY_USDC_AMOUNT = 1000000 * 1e6; // 1M USDC for massive liquidity (increased from 100k)
        uint256 ethAmount = (LIQUIDITY_USDC_AMOUNT * 1e18) / (2500 * 1e6); // 400 ETH for reference
        
        // Calculate proper tick range around the ACTUAL pool tick
        int24 tickSpacing = 60;      // From pool configuration
        
        // Use safe tick bounds - Uniswap V4 typically has bounds around ±887272
        int24 MAX_TICK = 887220;     // Slightly under max, rounded to tick spacing
        int24 MIN_TICK = -887220;    // Slightly over min, rounded to tick spacing
        
        // Use wider tick range to ensure more liquidity in range
        int24 tickLower = ((actualTick - 12000) / tickSpacing) * tickSpacing; // Wider range (was 6000)
        int24 tickUpper = ((actualTick + 12000) / tickSpacing) * tickSpacing;  // Wider range (was 6000)
        
        // Clamp to valid bounds
        if (tickLower < MIN_TICK) tickLower = MIN_TICK;
        if (tickUpper > MAX_TICK) tickUpper = MAX_TICK;
        
        // Ensure the range includes the actual tick
        if (actualTick < tickLower || actualTick > tickUpper) {
            console.log("[ERROR] Tick range doesn't include actual tick!");
            console.log("[ERROR] Actual tick:", uint256(int256(actualTick)));
            console.log("[ERROR] Range:", uint256(int256(tickLower)), "to", uint256(int256(tickUpper)));
        }
        
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: tickLower,    // Wider range around actual price
            tickUpper: tickUpper,    // Wider range around actual price  
            liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT), // Use 1M USDC amount for massive liquidity
            salt: 0
        });
        
        // Fix debug logging for negative ticks
        if (actualTick >= 0) {
            console.log("[DEBUG] Actual tick:", uint256(int256(actualTick)));
        } else {
            console.log("[DEBUG] Actual tick: -", uint256(int256(-actualTick)));
        }
        
        // Safe debug logging for tick range
        console.log("[DEBUG] Tick range calculated");
        if (tickLower >= 0) {
            console.log("[DEBUG] tickLower: +", uint256(int256(tickLower)));
        } else {
            console.log("[DEBUG] tickLower: -", uint256(int256(-tickLower)));
        }
        if (tickUpper >= 0) {
            console.log("[DEBUG] tickUpper: +", uint256(int256(tickUpper)));
        } else {
            console.log("[DEBUG] tickUpper: -", uint256(int256(-tickUpper)));
        }
        
        // Check balances before liquidity provision
        console.log("[DEBUG] Contract ETH balance:", address(this).balance);
        console.log("[DEBUG] Contract USDC balance:", realUSDC.balanceOf(address(this)));
        console.log("[DEBUG] Attempting to add liquidity");
        console.log("[DEBUG] Liquidity delta:", uint256(int256(liquidityParams.liquidityDelta)));
        
        // For native ETH pools, we need to send ETH value with the call
        uint256 ethValueNeeded = ethLiquidityAmount / 10; // Use portion of available ETH
        modifyLiquidityRouter.modifyLiquidity{value: ethValueNeeded}(realisticPoolKey, liquidityParams, "");
        console.log("[OK] Added liquidity - ETH:", ethAmount);
        console.log("[OK] Added liquidity - USDC:", LIQUIDITY_USDC_AMOUNT / 1e6);
        
        // Check pool balances after liquidity addition
        console.log("[DEBUG] PoolManager ETH balance:", address(manager).balance);
        console.log("[DEBUG] PoolManager USDC balance:", realUSDC.balanceOf(address(manager)));
        
        // Provide tokens to test users
        // For ETH: give alice native ETH using vm.deal()
        vm.deal(alice, 1000 * 1e18);      // 1000 ETH
        
        // For USDC: mint MockERC20 tokens - give alice much more USDC
        realUSDC.mint(alice, 10000000 * 1e6);   // 10M USDC (increased from 2.5M)
        
        // Approve USDC for alice (ETH doesn't need approval)
        vm.startPrank(alice);
        realUSDC.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        console.log("[OK] Realistic pool setup complete");
    }

    /// @notice Test basic setup validation
    function test_SetupValidation() public view {
        console.log("=== TEST: Setup Validation ===");
        
        // Verify hook deployment
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        assertTrue(address(priceRegistry) != address(0), "PriceRegistry should be deployed");
        assertTrue(address(mockOracle) != address(0), "MockOracle should be deployed");
        
        // Verify pool initialization
        assertTrue(PoolId.unwrap(simplePoolId) != bytes32(0), "Simple pool should be initialized");
        assertTrue(PoolId.unwrap(realisticPoolId) != bytes32(0), "Realistic pool should be initialized");
        
        // Verify PriceRegistry configuration for realistic pool
        address realisticCurrency0Token = Currency.unwrap(realisticPoolKey.currency0);
        bytes32 priceId = priceRegistry.tokenToPriceId(realisticCurrency0Token);
        assertTrue(priceId == ETH_USD_PRICE_ID, "Realistic pool currency0 (ETH) should map to ETH price ID");
        
        console.log("[PASS] Setup validation complete");
    }

    /// @notice Test no arbitrage when oracle matches pool (legacy pattern)
    function test_NoArbitrageWhenOracleMatchesPool() public {
        console.log("=== TEST: No Arbitrage When Oracle Matches Pool ===");
        console.log("Pool: 1:1 ratio, Oracle: 1:1 ratio -> No arbitrage expected");
        
        // Set oracle to match pool (both tokens at $1)
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(1 * 1e8), uint64(1e6), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e8), uint64(1e6), -8, uint64(block.timestamp));
        
        // Test both swap directions
        uint256 swapAmount = 1e18; // 1 token
        
        for (uint i = 0; i < 2; i++) {
            bool zeroForOne = (i == 0);
            console.log("Testing direction:", zeroForOne ? "currency0->currency1" : "currency1->currency0");
            
            // Record balances before
            uint256 hookBalance0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(address(hook));
            uint256 hookBalance1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook));
            
            // Execute swap
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
            
            swapRouter.swap(simplePoolKey, swapParams, testSettings, "");
            vm.stopPrank();
            
            // Verify no arbitrage capture
            uint256 hookBalance0After = MockERC20(Currency.unwrap(currency0)).balanceOf(address(hook));
            uint256 hookBalance1After = MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook));
            
            assertEq(hookBalance0After, hookBalance0Before, "Hook should not capture currency0 when no arbitrage");
            assertEq(hookBalance1After, hookBalance1Before, "Hook should not capture currency1 when no arbitrage");
        }
        
        console.log("[PASS] No arbitrage captured when oracle matches pool");
    }

    /// @notice Test arbitrage detection when pool overpays (legacy pattern)
    function test_ArbitrageWhenPoolOverpays() public {
        console.log("=== TEST: Arbitrage When Pool Overpays ===");
        console.log("Pool: 1:1 ratio, Oracle: currency0=$3000, currency1=$1000 -> Pool overpaying");
        
        // Set oracle so pool overpays for currency0
        // Pool gives 1:1, but oracle says currency0 is worth 3x currency1
        mockOracle.updatePriceFeeds(TOK1_PRICE_ID, int64(3000 * 1e8), uint64(100 * 1e8), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(TOK2_PRICE_ID, int64(1000 * 1e8), uint64(10 * 1e8), -8, uint64(block.timestamp));
        
        uint256 swapAmount = 1e18; // 1 token
        
        // Debug pool balances before testing
        console.log("=== PRE-TEST BALANCES ===");
        console.log("PoolManager currency0 balance:", MockERC20(Currency.unwrap(currency0)).balanceOf(address(manager)));
        console.log("PoolManager currency1 balance:", MockERC20(Currency.unwrap(currency1)).balanceOf(address(manager)));
        console.log("Alice currency0 balance:", MockERC20(Currency.unwrap(currency0)).balanceOf(alice));
        console.log("Alice currency1 balance:", MockERC20(Currency.unwrap(currency1)).balanceOf(alice));
        console.log("Swap amount:", swapAmount);
        
        // Test zeroForOne (currency0 -> currency1) - should capture arbitrage
        console.log("Testing zeroForOne: currency0->currency1 (should capture arbitrage)");
        
        uint256 hookBalance0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(address(hook));
        
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
        
        // Record events
        vm.recordLogs();
        swapRouter.swap(simplePoolKey, swapParams, testSettings, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();
        
        // Check for ArbitrageCaptured events
        bool arbitrageCaptured = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("ArbitrageCaptured(bytes32,address,uint256,uint256,bool)")) {
                arbitrageCaptured = true;
                console.log("ArbitrageCaptured event found at index:", i);
                break;
            }
        }
        
        assertTrue(arbitrageCaptured, "ArbitrageCaptured event should be emitted");
        
        // Verify hook captured tokens
        uint256 hookBalance0After = MockERC20(Currency.unwrap(currency0)).balanceOf(address(hook));
        uint256 captured = hookBalance0After - hookBalance0Before;
        
        assertGt(captured, 0, "Hook should capture currency0 when pool overpays");
        console.log("Captured amount:", captured);
        
        // Test oneForZero (currency1 -> currency0) - should NOT capture arbitrage
        console.log("Testing oneForZero: currency1->currency0 (should NOT capture arbitrage)");
        
        uint256 hookBalance1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook));
        
        vm.startPrank(alice);
        swapParams.zeroForOne = false;
        swapParams.sqrtPriceLimitX96 = TickMath.MAX_SQRT_PRICE - 1;
        
        vm.recordLogs();
        swapRouter.swap(simplePoolKey, swapParams, testSettings, "");
        logs = vm.getRecordedLogs();
        vm.stopPrank();
        
        // Should NOT find ArbitrageCaptured events
        arbitrageCaptured = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("ArbitrageCaptured(bytes32,address,uint256,uint256,bool)")) {
                arbitrageCaptured = true;
                break;
            }
        }
        
        assertFalse(arbitrageCaptured, "ArbitrageCaptured event should NOT be emitted for oneForZero");
        
        uint256 hookBalance1After = MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook));
        assertEq(hookBalance1After, hookBalance1Before, "Hook should not capture currency1 when no arbitrage");
        
        console.log("[PASS] Arbitrage detection working correctly");
    }

    /// @notice Test realistic ETH/USDC scenario with proven legacy patterns
    function test_RealisticETHUSDCScenario() public {
        console.log("=== TEST: Realistic ETH/USDC Scenario ===");
        console.log("Pool: 1 ETH = 2500 USDC, Oracle: ETH slightly underpaid scenario");
        
        // Set oracle to create smaller arbitrage opportunity
        // Pool: 1 ETH = 2500 USDC
        // Oracle: ETH=$2600, USDC=$1 -> Pool slightly underpaying for ETH
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2600 * 1e8), uint64(100 * 1e8), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e8), uint64(0.01 * 1e8), -8, uint64(block.timestamp));
        
        console.log("Oracle: ETH=$2600, USDC=$1 (ETH worth 2600 USDC)");
        console.log("Pool: 1 ETH = 2500 USDC (Pool underpaying for ETH)");
        console.log("Expected: oneForZero arbitrage (USDC->ETH)");
        
        // Add detailed price verification logging
        console.log("=== PRICE VERIFICATION ===");
        console.log("Expected oracle ratio (USDC/ETH): 1/2600");
        console.log("Oracle ratio value: ~384615384615384"); // 1e18 / 2600
        console.log("Expected pool price (USDC/ETH): 1/2500");
        console.log("Pool price value: 400000000000000"); // 1e18 / 2500
        
        // Currency ordering is now fixed: ETH (currency0), USDC (currency1)
        console.log("Currency0 (ETH) address:", Currency.unwrap(realisticPoolKey.currency0));
        console.log("Currency1 (USDC) address:", Currency.unwrap(realisticPoolKey.currency1));
        console.log("ETH is currency0: true (always with address(0))");
        
        // For this scenario: ETH underpriced in pool, so we want to buy ETH (USDC->ETH)
        // Since ETH is currency0 and USDC is currency1, we want oneForZero=false (USDC->ETH)
        bool zeroForOne = false; // USDC -> ETH (buying underpriced ETH)
        
        // Swap amount should match INPUT currency decimals
        // zeroForOne=false means input=currency1 (USDC, 6 decimals)
        uint256 swapAmount = 1 * 1e6; // 1 USDC (very small amount to test with limited pool liquidity)
        
        console.log("Testing direction with expected arbitrage");
        console.log("Swap amount:", swapAmount);
        
        // Debug balances before swap
        console.log("=== PRE-SWAP BALANCES ===");
        console.log("PoolManager ETH balance:", address(manager).balance);
        console.log("PoolManager USDC balance:", realUSDC.balanceOf(address(manager)));
        console.log("Alice ETH balance:", alice.balance);
        console.log("Alice USDC balance:", realUSDC.balanceOf(alice));
        console.log("Hook ETH balance:", address(hook).balance);
        console.log("Hook USDC balance:", realUSDC.balanceOf(address(hook)));
        
        // Record balances before
        uint256 hookBalance0Before = address(hook).balance; // ETH balance
        uint256 hookBalance1Before = realUSDC.balanceOf(address(hook)); // USDC balance
        
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
        
        // Record events
        vm.recordLogs();
        BalanceDelta delta = swapRouter.swap(realisticPoolKey, swapParams, testSettings, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();
        
        console.log("=== POST-SWAP ANALYSIS ===");
        console.log("Swap delta amount0 (ETH):", delta.amount0());
        console.log("Swap delta amount1 (USDC):", delta.amount1());
        
        console.log("Swap executed - Delta amount0:", delta.amount0());
        console.log("Swap executed - Delta amount1:", delta.amount1());
        
        // Check for ArbitrageCaptured events
        bool arbitrageCaptured = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("ArbitrageCaptured(bytes32,address,uint256,uint256,bool)")) {
                arbitrageCaptured = true;
                console.log("ArbitrageCaptured event found at index:", i);
                break;
            }
        }
        
        // Verify arbitrage capture
        uint256 hookBalance0After = address(hook).balance; // ETH balance
        uint256 hookBalance1After = realUSDC.balanceOf(address(hook)); // USDC balance
        
        uint256 captured0 = hookBalance0After - hookBalance0Before; // ETH captured
        uint256 captured1 = hookBalance1After - hookBalance1Before; // USDC captured
        
        console.log("Hook captured currency0 (ETH):", captured0);
        console.log("Hook captured currency1 (USDC):", captured1);
        console.log("Hook captured ETH:", formatETH(captured0));
        console.log("Hook captured USDC:", formatUSDC(captured1));
        
        // Should capture some arbitrage
        assertTrue(arbitrageCaptured, "Should detect arbitrage in realistic scenario");
        assertTrue(captured0 > 0 || captured1 > 0, "Should capture some tokens");
        
        console.log("[PASS] Realistic ETH/USDC scenario working");
    }

    /// @notice Test edge case: very small swap amounts
    function test_SmallSwapAmounts() public {
        console.log("=== TEST: Small Swap Amounts ===");
        
        // Set up arbitrage opportunity
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(2000 * 1e8), uint64(100 * 1e8), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1000 * 1e8), uint64(10 * 1e8), -8, uint64(block.timestamp));
        
        // Test very small swap
        uint256 smallSwapAmount = 1000; // 0.000000000000001 tokens
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(smallSwapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // Should not revert
        swapRouter.swap(simplePoolKey, swapParams, testSettings, "");
        vm.stopPrank();
        
        console.log("[PASS] Small swap amounts handled correctly");
    }

    /// @notice Test that hook doesn't interfere with liquidity operations
    function test_HookDoesNotInterferWithLiquidity() public {
        console.log("=== TEST: Hook Does Not Interfere With Liquidity ===");
        
        // Add more liquidity to the pool
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -300,
            tickUpper: 300,
            liquidityDelta: 500e18,
            salt: 0
        });
        
        // Should work normally since our hook doesn't implement liquidity hooks
        modifyLiquidityRouter.modifyLiquidity(simplePoolKey, liquidityParams, "");
        
        // Remove some liquidity
        liquidityParams.liquidityDelta = -250e18;
        modifyLiquidityRouter.modifyLiquidity(simplePoolKey, liquidityParams, "");
        
        console.log("[PASS] Liquidity operations work normally");
    }
} 