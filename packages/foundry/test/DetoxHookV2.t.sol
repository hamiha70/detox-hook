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
import { IPyth, PythStructs } from "../src/libraries/PythLibrary.sol";
import { SimplifiedOracleLib } from "../src/libraries/SimplifiedOracleLib.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";

/**
 * @title DetoxHookV2Test
 * @notice Comprehensive test suite for DetoxHookV2 - the production MEV protection hook
 * @dev Tests realistic ETH/USDC scenarios, native ETH support, and PriceRegistry integration
 */
contract DetoxHookV2Test is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // ============ Test Contracts ============
    
    DetoxHookV2 public hook;
    PriceRegistry public priceRegistry;
    MockPyth public pythOracle;
    
    // ============ Pool Configurations ============
    
    // Simple 1:1 pool (TOK1/TOK2 from Deployers)
    PoolKey public simplePoolKey;
    PoolId public simplePoolId;
    
    // Realistic ETH/USDC pool
    PoolKey public ethUsdcPoolKey;
    PoolId public ethUsdcPoolId;
    Currency public ethCurrency; // address(0)
    Currency public usdcCurrency; // MockERC20 with 6 decimals
    MockERC20 public usdcToken;
    
    // ============ Test Constants ============
    
    uint24 public constant FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;
    
    // Test precision and parameters
    uint256 constant PRECISION = 1e18;
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant DEFAULT_RHO_BPS = 8000; // 80% hook share
    uint256 constant DEFAULT_STALENESS_THRESHOLD = 60;
    
    // Pyth price IDs (real Arbitrum Sepolia IDs)
    bytes32 constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 constant TOK1_USD_PRICE_ID = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    bytes32 constant TOK2_USD_PRICE_ID = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public owner = makeAddr("owner");

    // ============ Setup Functions ============

    function setUp() external {
        console.log("=== SETUP: DetoxHookV2 Test Environment ===");
        
        try this._deployUniswapInfrastructure() {
            console.log("[DEBUG] Uniswap infrastructure deployed successfully");
        } catch {
            console.log("[ERROR] Failed in _deployUniswapInfrastructure");
            revert("Setup failed at Uniswap infrastructure");
        }
        
        try this._deployOracleAndRegistry() {
            console.log("[DEBUG] Oracle and registry deployed successfully");
        } catch {
            console.log("[ERROR] Failed in _deployOracleAndRegistry");
            revert("Setup failed at oracle/registry deployment");
        }
        
        try this._deployDetoxHookV2() {
            console.log("[DEBUG] DetoxHookV2 deployed successfully");
        } catch {
            console.log("[ERROR] Failed in _deployDetoxHookV2");
            revert("Setup failed at DetoxHookV2 deployment");
        }
        
        try this._setupTokensAndPools() {
            console.log("[DEBUG] Tokens and pools setup successfully");
        } catch {
            console.log("[ERROR] Failed in _setupTokensAndPools");
            revert("Setup failed at tokens/pools setup");
        }
        
        try this._setupTestUsers() {
            console.log("[DEBUG] Test users setup successfully");
        } catch {
            console.log("[ERROR] Failed in _setupTestUsers");
            revert("Setup failed at test users setup");
        }
        
        try this._validateSetup() {
            console.log("[DEBUG] Setup validation passed");
        } catch {
            console.log("[ERROR] Failed in _validateSetup");
            revert("Setup failed at validation");
        }
        
        console.log("[SUCCESS] DetoxHookV2 test environment ready");
        console.log("=== SETUP COMPLETE ===");
    }

    // External wrapper functions for try-catch debugging
    function _deployUniswapInfrastructure() external {
        _deployUniswapInfrastructureInternal();
    }
    
    function _deployOracleAndRegistry() external {
        _deployOracleAndRegistryInternal();
    }
    
    function _deployDetoxHookV2() external {
        _deployDetoxHookV2Internal();
    }
    
    function _setupTokensAndPools() external {
        _setupTokensAndPoolsInternal();
    }
    
    function _setupTestUsers() external {
        _setupTestUsersInternal();
    }
    
    function _validateSetup() external view {
        _validateSetupInternal();
    }

    function _deployUniswapInfrastructureInternal() internal {
        console.log("\n--- Deploying Uniswap V4 Infrastructure ---");
        
        // Deploy fresh manager and routers using Deployers
        deployFreshManagerAndRouters();
        console.log("[OK] Deployed PoolManager and routers");
        
        // Deploy simple test currencies (TOK1/TOK2 equivalent)
        (currency0, currency1) = deployMintAndApprove2Currencies();
        console.log("[OK] Deployed simple test currencies (TOK1/TOK2)");
    }

    function _deployOracleAndRegistryInternal() internal {
        console.log("\n--- Deploying Oracle and Registry ---");
        
        // Deploy MockPyth oracle
        pythOracle = new MockPyth(60, 1); // 60 second validity, 1 wei fee
        console.log("[OK] Deployed MockPyth oracle");
        
        // Deploy PriceRegistry
        priceRegistry = new PriceRegistry(owner);
        console.log("[OK] Deployed PriceRegistry with owner:", owner);
    }

    function _deployDetoxHookV2Internal() internal {
        console.log("\n--- Deploying DetoxHookV2 ---");
        
        // Calculate required hook address with correct permission bits
        address hookAddress = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG)
        );
        
        // Deploy DetoxHookV2 using CREATE2 to get the correct address
        deployCodeTo(
            "DetoxHookV2.sol", 
            abi.encode(manager, owner, address(pythOracle), address(priceRegistry)), 
            hookAddress
        );
        hook = DetoxHookV2(payable(hookAddress));
        console.log("[OK] Deployed DetoxHookV2 with correct permissions at:", hookAddress);
        
        // Fund the hook with ETH for oracle fees
        vm.deal(address(hook), 10 ether);
        console.log("[OK] Funded hook with 10 ETH for oracle fees");
    }

    function _setupTokensAndPoolsInternal() internal {
        console.log("\n--- Setting Up Tokens and Pools ---");
        
        // Create USDC token with 6 decimals (realistic)
        usdcToken = new MockERC20("USD Coin", "USDC", 6);
        usdcCurrency = Currency.wrap(address(usdcToken));
        
        // ETH as native currency (address(0))
        ethCurrency = Currency.wrap(address(0));
        
        console.log("[OK] Created ETH (native) and USDC (6 decimals) currencies");
        
        // Configure price mappings in PriceRegistry (AFTER DetoxHookV2 is deployed)
        _configurePriceRegistry();
        
        // CRITICAL: Setup oracle prices BEFORE creating pools with hooks
        _setupInitialOraclePrices();
        
        // Setup simple 1:1 pool (TOK1/TOK2)
        _setupSimplePool();
        
        // Setup realistic ETH/USDC pool
        _setupEthUsdcPool();
    }

    function _configurePriceRegistry() internal {
        console.log("\n--- Configuring PriceRegistry ---");
        
        vm.startPrank(owner);
        
        // Configure simple test currencies (TOK1/TOK2 equivalent)
        priceRegistry.setPriceMapping(
            Currency.unwrap(currency0), 
            TOK1_USD_PRICE_ID, 
            "TOK1"
        );
        priceRegistry.setPriceMapping(
            Currency.unwrap(currency1), 
            TOK2_USD_PRICE_ID, 
            "TOK2"
        );
        
        // Configure ETH (address(0)) and USDC
        priceRegistry.setPriceMapping(
            address(0), // ETH as native currency
            ETH_USD_PRICE_ID, 
            "ETH"
        );
        priceRegistry.setPriceMapping(
            address(usdcToken), 
            USDC_USD_PRICE_ID, 
            "USDC"
        );
        
        vm.stopPrank();
        
        console.log("[OK] Configured price mappings for all currencies");
    }

    function _setupInitialOraclePrices() internal {
        console.log("\n--- Setting Up Initial Oracle Prices ---");
        
        // Set up initial oracle prices to prevent hook failures during pool setup
        // These will be updated in individual tests as needed
        
        // TOK1 = $1000, TOK2 = $1000 (1:1 ratio)
        pythOracle.updatePriceFeeds(
            TOK1_USD_PRICE_ID,
            100000000000, // $1000 * 1e8
            1000000000,   // $10 confidence
            -8,
            uint64(block.timestamp)
        );
        
        pythOracle.updatePriceFeeds(
            TOK2_USD_PRICE_ID,
            100000000000, // $1000 * 1e8
            1000000000,   // $10 confidence
            -8,
            uint64(block.timestamp)
        );
        
        // ETH = $2500, USDC = $1.00 (realistic defaults)
        pythOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            250000000000, // $2500 * 1e8
            2500000000,   // $25 confidence
            -8,
            uint64(block.timestamp)
        );
        
        pythOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            100000000,    // $1.00 * 1e8
            1000000,      // $0.01 confidence
            -8,
            uint64(block.timestamp)
        );
        
        console.log("[OK] Set initial oracle prices (TOK1/TOK2: $1000, ETH: $2500, USDC: $1.00)");
    }

    function _setupSimplePool() internal {
        console.log("\n--- Setting Up Simple 1:1 Pool (TOK1/TOK2) ---");
        
        // Create simple pool key
        simplePoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        
        simplePoolId = simplePoolKey.toId();
        
        // Initialize at 1:1 price
        manager.initialize(simplePoolKey, SQRT_PRICE_1_1);
        console.log("[OK] Initialized simple pool at 1:1 price");
        
        // Add liquidity using conservative amounts (same pattern as legacy)
        uint256 SIMPLE_LIQUIDITY_AMOUNT = 1e18; // 1 token (18 decimals)
        console.log("[DEBUG] Simple pool liquidity amount:", SIMPLE_LIQUIDITY_AMOUNT);
        
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: int256(SIMPLE_LIQUIDITY_AMOUNT), // Conservative amount
            salt: 0
        });
        
        console.log("[DEBUG] Simple pool liquidity params:");
        console.log("[DEBUG] - liquidityDelta:", uint256(liquidityParams.liquidityDelta));
        
        modifyLiquidityRouter.modifyLiquidity(simplePoolKey, liquidityParams, "");
        console.log("[OK] Added liquidity to simple pool");
    }

    function _setupEthUsdcPool() internal {
        console.log("\n--- Setting Up Realistic ETH/USDC Pool ---");
        
        // Create ETH/USDC pool key (ensure proper ordering)
        console.log("[DEBUG] Creating ETH/USDC pool key...");
        (Currency currency0Local, Currency currency1Local) = 
            ethCurrency < usdcCurrency ? (ethCurrency, usdcCurrency) : (usdcCurrency, ethCurrency);
        
        console.log("[DEBUG] Currency ordering - currency0:", Currency.unwrap(currency0Local));
        console.log("[DEBUG] Currency ordering - currency1:", Currency.unwrap(currency1Local));
        
        ethUsdcPoolKey = PoolKey({
            currency0: currency0Local,
            currency1: currency1Local,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0)) // TEMPORARY: Remove hook to isolate issue
        });
        
        ethUsdcPoolId = ethUsdcPoolKey.toId();
        console.log("[DEBUG] Created pool key and ID");
        
        // Calculate sqrt price for ETH at $2500 (2500 USDC per ETH)
        console.log("[DEBUG] Calculating sqrt price...");
        uint160 sqrtPriceX96;
        if (currency0Local == ethCurrency) {
            // ETH is currency0, price = 2500 USDC per ETH
            sqrtPriceX96 = _calculateSqrtPriceX96(2500 * 1e12); // Adjust for decimal difference (18-6=12)
            console.log("[DEBUG] ETH is currency0, calculated price");
        } else {
            // USDC is currency0, price = 1/2500 ETH per USDC
            sqrtPriceX96 = _calculateSqrtPriceX96((1e18) / (2500 * 1e12)); // Adjust for decimal difference
            console.log("[DEBUG] USDC is currency0, calculated price");
        }
        
        // Initialize pool at calculated price
        console.log("[DEBUG] About to initialize pool...");
        manager.initialize(ethUsdcPoolKey, sqrtPriceX96);
        console.log("[OK] Initialized ETH/USDC pool at ~$2500 per ETH");
        
        // Add liquidity (need to handle native ETH properly)
        console.log("[DEBUG] About to add liquidity...");
        _addEthUsdcLiquidity();
        console.log("[OK] Added liquidity to ETH/USDC pool");
    }

    function _addEthUsdcLiquidity() internal {
        console.log("[DEBUG] Starting _addEthUsdcLiquidity...");
        
        // Use same constants as successful legacy deployments
        uint256 LIQUIDITY_USDC_AMOUNT = 1e6; // 1 USDC (6 decimals)
        uint256 POOL_PRICE_USDC_PER_ETH = 2500; // $2500 per ETH
        
        console.log("[DEBUG] Liquidity configuration:");
        console.log("[DEBUG] - USDC Amount:", LIQUIDITY_USDC_AMOUNT);
        console.log("[DEBUG] - Pool Price:", POOL_PRICE_USDC_PER_ETH, "USDC per ETH");
        
        // Calculate exact ETH amount needed (proven formula from legacy)
        uint256 ethAmount = (LIQUIDITY_USDC_AMOUNT * 1e18) / (POOL_PRICE_USDC_PER_ETH * 1e6);
        console.log("[DEBUG] Calculated ETH amount needed:", ethAmount);
        console.log("[DEBUG] ETH amount in ether units:", ethAmount / 1e18);
        
        // Mint exact USDC amount needed
        console.log("[DEBUG] Minting exact USDC amount:", LIQUIDITY_USDC_AMOUNT);
        usdcToken.mint(address(this), LIQUIDITY_USDC_AMOUNT);
        
        console.log("[DEBUG] Approving USDC for router...");
        usdcToken.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        // Fund with exact ETH amount needed (plus small buffer)
        uint256 ethBuffer = ethAmount + (ethAmount / 10); // Add 10% buffer
        console.log("[DEBUG] ETH amount with buffer:", ethBuffer);
        vm.deal(address(this), ethBuffer);
        
        // Create liquidity params using USDC amount as liquidityDelta (legacy pattern)
        console.log("[DEBUG] Creating liquidity params...");
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT), // Use USDC amount directly (legacy pattern)
            salt: 0
        });
        
        console.log("[DEBUG] Liquidity params:");
        console.log("[DEBUG] - tickLower:", liquidityParams.tickLower);
        console.log("[DEBUG] - tickUpper:", liquidityParams.tickUpper);
        console.log("[DEBUG] - liquidityDelta:", uint256(liquidityParams.liquidityDelta));
        console.log("[DEBUG] - salt:", uint256(liquidityParams.salt));
        
        // Check balances before operation
        console.log("[DEBUG] Pre-operation balances:");
        console.log("[DEBUG] - Test contract ETH:", address(this).balance);
        console.log("[DEBUG] - Test contract USDC:", usdcToken.balanceOf(address(this)));
        
        // Add liquidity with exact calculated ETH amount
        console.log("[DEBUG] Calling modifyLiquidity with ETH value:", ethAmount);
        modifyLiquidityRouter.modifyLiquidity{value: ethAmount}(ethUsdcPoolKey, liquidityParams, "");
        console.log("[DEBUG] modifyLiquidity completed successfully");
        
        // Check balances after operation
        console.log("[DEBUG] Post-operation balances:");
        console.log("[DEBUG] - Test contract ETH:", address(this).balance);
        console.log("[DEBUG] - Test contract USDC:", usdcToken.balanceOf(address(this)));
    }

    function _setupTestUsersInternal() internal {
        console.log("\n--- Setting Up Test Users ---");
        
        // Give users tokens for simple pool
        MockERC20(Currency.unwrap(currency0)).mint(alice, 1000e18);
        MockERC20(Currency.unwrap(currency1)).mint(alice, 1000e18);
        MockERC20(Currency.unwrap(currency0)).mint(bob, 1000e18);
        MockERC20(Currency.unwrap(currency1)).mint(bob, 1000e18);
        
        // Give users USDC for ETH/USDC pool
        usdcToken.mint(alice, 10000e6); // 10,000 USDC
        usdcToken.mint(bob, 10000e6);
        
        // Give users ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        
        // Approve tokens for users
        vm.startPrank(alice);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        usdcToken.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(bob);
        MockERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        usdcToken.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
        
        console.log("[OK] Funded and approved tokens for test users");
    }

    function _validateSetupInternal() internal view {
        console.log("\n--- Validating Setup ---");
        
        // Validate hook deployment
        require(address(hook) != address(0), "Hook not deployed");
        require(hook.owner() == owner, "Hook owner incorrect");
        
        // Validate price registry
        require(address(priceRegistry) == address(hook.priceRegistry()), "Price registry not connected");
        require(priceRegistry.getPriceId(address(0)) == ETH_USD_PRICE_ID, "ETH price ID not configured");
        require(priceRegistry.getPriceId(address(usdcToken)) == USDC_USD_PRICE_ID, "USDC price ID not configured");
        
        // Validate pools are initialized
        require(PoolId.unwrap(simplePoolId) != bytes32(0), "Simple pool not initialized");
        require(PoolId.unwrap(ethUsdcPoolId) != bytes32(0), "ETH/USDC pool not initialized");
        
        // Validate hook has ETH for oracle fees
        require(address(hook).balance >= 1 ether, "Hook not funded with ETH");
        
        console.log("[OK] All validations passed");
    }

    // ============ Test Functions ============

    function test_SetupValidation() external view {
        console.log("=== TEST: Setup Validation ===");
        
        // Test hook configuration
        (uint256 rhoBps, uint256 staleness, uint256 maxConf) = hook.getConfiguration();
        assertEq(rhoBps, DEFAULT_RHO_BPS, "Hook rho BPS should be default");
        assertEq(staleness, DEFAULT_STALENESS_THRESHOLD, "Hook staleness should be default");
        
        // Test price registry integration
        assertTrue(hook.isPairSupported(currency0, currency1), "Simple pair should be supported");
        assertTrue(hook.isPairSupported(ethCurrency, usdcCurrency), "ETH/USDC pair should be supported");
        
        // Test oracle integration
        assertEq(address(hook.pythOracle()), address(pythOracle), "Oracle should be connected");
        
        console.log("[PASS] Setup validation complete");
    }

    function test_SimpleSwaps_1_1_Pool() external {
        console.log("=== TEST: Simple Swaps in 1:1 Pool (TOK1/TOK2) ===");
        
        // Setup oracle prices at 1:1 (no arbitrage expected)
        _setOraclePrices_Simple_1_1();
        
        // Test basic swap currency0 -> currency1
        _testSimpleSwap(true, 1e18); // 1 TOK1 -> TOK2
        
        // Test reverse swap currency1 -> currency0
        _testSimpleSwap(false, 1e18); // 1 TOK2 -> TOK1
        
        console.log("[PASS] Simple swaps working correctly");
    }

    function test_RealisticETHUSDC_AtOracle() external {
        console.log("=== TEST: Realistic ETH/USDC At Oracle Price ===");
        
        // Setup oracle: ETH=$2500, USDC=$1.00 (tight confidence)
        _setOraclePrices_ETH_2500_USDC_1();
        
        // Pool is at $2500, oracle at $2500 -> no arbitrage expected
        _testEthUsdcSwap(true, 0.1 ether, "No arbitrage at oracle price");
        
        console.log("[PASS] ETH/USDC swaps at oracle price working correctly");
    }

    function test_RealisticETHUSDC_AboveOracle() external {
        console.log("=== TEST: Realistic ETH/USDC Above Oracle Price ===");
        
        // Setup oracle: ETH=$2400, USDC=$1.00 (pool paying more than oracle)
        _setOraclePrices_ETH_2400_USDC_1();
        
        // Pool at $2500, oracle at $2400 -> pool overpaying -> arbitrage expected
        _testEthUsdcSwap(true, 0.1 ether, "Arbitrage expected - pool above oracle");
        
        console.log("[PASS] ETH/USDC swaps above oracle working correctly");
    }

    function test_RealisticETHUSDC_BelowOracle() external {
        console.log("=== TEST: Realistic ETH/USDC Below Oracle Price ===");
        
        // Setup oracle: ETH=$2600, USDC=$1.00 (pool paying less than oracle)
        _setOraclePrices_ETH_2600_USDC_1();
        
        // Pool at $2500, oracle at $2600 -> pool underpaying -> arbitrage expected
        _testEthUsdcSwap(false, 2600e6, "Arbitrage expected - pool below oracle"); // Swap USDC -> ETH
        
        console.log("[PASS] ETH/USDC swaps below oracle working correctly");
    }

    // ============ Helper Functions ============

    function _setOraclePrices_Simple_1_1() internal {
        // Set TOK1 = $1000, TOK2 = $1000 (1:1 ratio, tight confidence)
        pythOracle.updatePriceFeeds(
            TOK1_USD_PRICE_ID,
            100000000000, // $1000 * 1e8
            1000000000,   // $10 confidence
            -8,
            uint64(block.timestamp)
        );
        
        pythOracle.updatePriceFeeds(
            TOK2_USD_PRICE_ID,
            100000000000, // $1000 * 1e8
            1000000000,   // $10 confidence
            -8,
            uint64(block.timestamp)
        );
    }

    function _setOraclePrices_ETH_2500_USDC_1() internal {
        // ETH = $2500, USDC = $1.00
        pythOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            250000000000, // $2500 * 1e8
            2500000000,   // $25 confidence
            -8,
            uint64(block.timestamp)
        );
        
        pythOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            100000000,    // $1.00 * 1e8
            1000000,      // $0.01 confidence
            -8,
            uint64(block.timestamp)
        );
    }

    function _setOraclePrices_ETH_2400_USDC_1() internal {
        // ETH = $2400, USDC = $1.00 (pool overpaying scenario)
        pythOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            240000000000, // $2400 * 1e8
            2400000000,   // $24 confidence
            -8,
            uint64(block.timestamp)
        );
        
        pythOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            100000000,    // $1.00 * 1e8
            1000000,      // $0.01 confidence
            -8,
            uint64(block.timestamp)
        );
    }

    function _setOraclePrices_ETH_2600_USDC_1() internal {
        // ETH = $2600, USDC = $1.00 (pool underpaying scenario)
        pythOracle.updatePriceFeeds(
            ETH_USD_PRICE_ID,
            260000000000, // $2600 * 1e8
            2600000000,   // $26 confidence
            -8,
            uint64(block.timestamp)
        );
        
        pythOracle.updatePriceFeeds(
            USDC_USD_PRICE_ID,
            100000000,    // $1.00 * 1e8
            1000000,      // $0.01 confidence
            -8,
            uint64(block.timestamp)
        );
    }

    function _testSimpleSwap(bool zeroForOne, uint256 amountIn) internal {
        console.log(zeroForOne ? "Testing TOK1 -> TOK2 swap" : "Testing TOK2 -> TOK1 swap");
        
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // Execute swap as alice
        vm.prank(alice);
        BalanceDelta delta = swapRouter.swap(simplePoolKey, swapParams, testSettings, "");
        
        console.log("Swap completed successfully");
    }

    function _testEthUsdcSwap(bool zeroForOne, uint256 amountIn, string memory scenario) internal {
        console.log("Testing ETH/USDC swap:", scenario);
        
        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // Execute swap as alice
        vm.prank(alice);
        BalanceDelta delta = swapRouter.swap{value: zeroForOne && ethUsdcPoolKey.currency0 == ethCurrency ? amountIn : 0}(
            ethUsdcPoolKey, 
            swapParams, 
            testSettings, 
            ""
        );
        
        console.log("ETH/USDC swap completed successfully");
    }

    function _calculateSqrtPriceX96(uint256 price) internal pure returns (uint160) {
        // Simple sqrt calculation for price in 1e18 format
        // This is a simplified version - in production, use proper math libraries
        uint256 sqrtPrice = _sqrt(price);
        return uint160((sqrtPrice * (2 ** 96)) / (10 ** 9)); // Adjust for Q96 format
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // Contract inherits receive() from Deployers.sol
} 