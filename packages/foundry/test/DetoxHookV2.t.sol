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

    /// @notice Setup realistic ETH/USDC pool at $2500 using proven legacy patterns
    function _setupRealisticPool() internal {
        console.log("Setting up realistic ETH/USDC pool...");
        
        // Create ETH (address(0)) and USDC (6 decimals) tokens
        MockERC20 realETH = new MockERC20("Ethereum", "ETH", 18);
        MockERC20 realUSDC = new MockERC20("USD Coin", "USDC", 6);
        
        // Wrap as currencies and ensure proper ordering
        Currency ethCurrency = Currency.wrap(address(realETH));
        Currency usdcCurrency = Currency.wrap(address(realUSDC));
        
        // Order currencies properly (smaller address first)
        Currency realisticCurrency0;
        Currency realisticCurrency1;
        
        if (address(realETH) < address(realUSDC)) {
            realisticCurrency0 = ethCurrency;  // ETH
            realisticCurrency1 = usdcCurrency; // USDC
            console.log("[OK] Currency ordering: ETH (currency0), USDC (currency1)");
        } else {
            realisticCurrency0 = usdcCurrency; // USDC
            realisticCurrency1 = ethCurrency;  // ETH
            console.log("[OK] Currency ordering: USDC (currency0), ETH (currency1)");
        }
        
        // Configure PriceRegistry for realistic pool
        priceRegistry.setPriceMapping(address(realETH), ETH_USD_PRICE_ID, "ETH");
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
        
        // Calculate proper sqrtPrice for 1 ETH = 2500 USDC using safer calculations
        uint160 sqrtPriceX96;
        bool ethIsCurrency0 = (realisticCurrency0 == ethCurrency);
        
        if (ethIsCurrency0) {
            // ETH is currency0, USDC is currency1: price = USDC/ETH = 2500
            // With 6 decimals for USDC: 2500 * 1e6 = 2500000000
            sqrtPriceX96 = HookLibrary.priceToSqrtPrice(2500 * 1e6);
            console.log("[OK] Pool setup: ETH->USDC ratio, price = 2500 * 1e6");
        } else {
            // USDC is currency0, ETH is currency1: price = ETH/USDC = 1/2500
            // With 18 decimals for ETH and 6 for USDC: (1e18) / (2500 * 1e6) = 1e12 / 2500 = 4e8
            sqrtPriceX96 = HookLibrary.priceToSqrtPrice(4e8);
            console.log("[OK] Pool setup: USDC->ETH ratio, price = 4e8");
        }
        
        // Initialize pool
        manager.initialize(realisticPoolKey, sqrtPriceX96);
        console.log("[OK] Initialized realistic pool at 1 ETH = 2500 USDC");
        
        // Mint tokens to test contract for liquidity (using proven legacy amounts)
        uint256 ethLiquidityAmount = 100 * 1e18;      // 100 ETH
        uint256 usdcLiquidityAmount = 250000 * 1e6;   // 250,000 USDC
        
        if (ethIsCurrency0) {
            realETH.mint(address(this), ethLiquidityAmount);
            realUSDC.mint(address(this), usdcLiquidityAmount);
        } else {
            realUSDC.mint(address(this), usdcLiquidityAmount);
            realETH.mint(address(this), ethLiquidityAmount);
        }
        
        // Approve tokens for liquidity provision
        realETH.approve(address(modifyLiquidityRouter), type(uint256).max);
        realUSDC.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        // Add liquidity using tiny amounts (proven legacy pattern)
        uint256 LIQUIDITY_USDC_AMOUNT = 1e6; // 1 USDC
        uint256 ethAmount = (LIQUIDITY_USDC_AMOUNT * 1e18) / (2500 * 1e6); // 0.0004 ETH
        
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -201000,  // Wide range around current price
            tickUpper: -199500,
            liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT), // Use tiny amount
            salt: 0
        });
        
        modifyLiquidityRouter.modifyLiquidity(realisticPoolKey, liquidityParams, "");
        console.log("[OK] Added liquidity - ETH:", ethAmount);
        console.log("[OK] Added liquidity - USDC:", LIQUIDITY_USDC_AMOUNT / 1e6);
        
        // Mint tokens to test users
        if (ethIsCurrency0) {
            realETH.mint(alice, 1000 * 1e18);      // 1000 ETH
            realUSDC.mint(alice, 2500000 * 1e6);   // 2.5M USDC
        } else {
            realUSDC.mint(alice, 2500000 * 1e6);   // 2.5M USDC
            realETH.mint(alice, 1000 * 1e18);      // 1000 ETH
        }
        
        // Approve tokens for alice
        vm.startPrank(alice);
        realETH.approve(address(swapRouter), type(uint256).max);
        realUSDC.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        console.log("[OK] Realistic pool setup complete");
    }

    /// @notice Test basic setup validation
    function test_SetupValidation() public {
        console.log("=== TEST: Setup Validation ===");
        
        // Verify hook deployment
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        assertTrue(address(priceRegistry) != address(0), "PriceRegistry should be deployed");
        assertTrue(address(mockOracle) != address(0), "MockOracle should be deployed");
        
        // Verify pool initialization
        assertTrue(PoolId.unwrap(simplePoolId) != bytes32(0), "Simple pool should be initialized");
        assertTrue(PoolId.unwrap(realisticPoolId) != bytes32(0), "Realistic pool should be initialized");
        
        // Verify PriceRegistry configuration
        address currency0Token = Currency.unwrap(currency0);
        bytes32 priceId = priceRegistry.tokenToPriceId(currency0Token);
        assertTrue(priceId == ETH_USD_PRICE_ID, "Currency0 should map to ETH price ID");
        
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
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(3000 * 1e8), uint64(100 * 1e8), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1000 * 1e8), uint64(10 * 1e8), -8, uint64(block.timestamp));
        
        uint256 swapAmount = 1e18; // 1 token
        
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
        console.log("Pool: 1 ETH = 2500 USDC, Oracle: ETH overpaying scenario");
        
        // Set oracle to create arbitrage opportunity
        // Pool: 1 ETH = 2500 USDC
        // Oracle: ETH=$3000, USDC=$1 -> Pool underpaying for ETH
        mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(3000 * 1e8), uint64(100 * 1e8), -8, uint64(block.timestamp));
        mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1 * 1e8), uint64(0.01 * 1e8), -8, uint64(block.timestamp));
        
        console.log("Oracle: ETH=$3000, USDC=$1 (ETH worth 3000 USDC)");
        console.log("Pool: 1 ETH = 2500 USDC (Pool underpaying for ETH)");
        console.log("Expected: oneForZero arbitrage (USDC->ETH)");
        
        // Determine currency ordering
        MockERC20 token0 = MockERC20(Currency.unwrap(realisticPoolKey.currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(realisticPoolKey.currency1));
        bool ethIsCurrency0 = (token0.decimals() == 18 && token1.decimals() == 6);
        
        console.log("Currency0 decimals:", token0.decimals());
        console.log("Currency1 decimals:", token1.decimals());
        console.log("ETH is currency0:", ethIsCurrency0);
        
        // Test the direction that should have arbitrage
        bool shouldCaptureDirection = !ethIsCurrency0; // oneForZero when ETH is currency0
        uint256 swapAmount = ethIsCurrency0 ? 2500 * 1e6 : 1e18; // 2500 USDC or 1 ETH
        
        console.log("Testing direction with expected arbitrage");
        console.log("Swap amount:", swapAmount);
        
        // Record balances before
        uint256 hookBalance0Before = token0.balanceOf(address(hook));
        uint256 hookBalance1Before = token1.balanceOf(address(hook));
        
        vm.startPrank(alice);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: shouldCaptureDirection,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: shouldCaptureDirection ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
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
        uint256 hookBalance0After = token0.balanceOf(address(hook));
        uint256 hookBalance1After = token1.balanceOf(address(hook));
        
        uint256 captured0 = hookBalance0After - hookBalance0Before;
        uint256 captured1 = hookBalance1After - hookBalance1Before;
        
        console.log("Hook captured currency0:", captured0);
        console.log("Hook captured currency1:", captured1);
        
        if (ethIsCurrency0) {
            console.log("Hook captured ETH:", formatETH(captured0));
            console.log("Hook captured USDC:", formatUSDC(captured1));
        } else {
            console.log("Hook captured USDC:", formatUSDC(captured0));
            console.log("Hook captured ETH:", formatETH(captured1));
        }
        
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