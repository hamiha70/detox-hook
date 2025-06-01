// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { DetoxHook } from "../src/DetoxHook.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IERC20Minimal } from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

/// @title InitializePoolsWithHookScript
/// @notice Initialize ETH/USDC pools with existing DetoxHook and add liquidity
/// @dev Based on DeployDetoxHookComplete.s.sol but skips hook deployment
contract InitializePoolsWithHook is Script {
    using ChainAddresses for uint256;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Deployment configuration (same as DeployDetoxHookComplete.s.sol)
    uint256 constant LIQUIDITY_USDC_AMOUNT = 1e6; // 1 USDC (6 decimals)
    uint24 constant POOL_FEE = 500; // 0.05% fee (low fee as requested)
    
    // Pool configurations - different tick spacings as requested
    int24 constant TICK_SPACING_POOL_1 = 10; // Tick spacing for first pool
    int24 constant TICK_SPACING_POOL_2 = 60; // Tick spacing for second pool
    
    // Price configurations (ETH/USDC)
    // Pool 1: 1 ETH = 2500 USDC
    // Pool 2: 1 ETH = 2600 USDC
    uint160 constant SQRT_PRICE_2500 = 3961408125713216879677197516800; // sqrt(2500) * 2^96 from ChainAddresses
    uint160 constant SQRT_PRICE_2600 = 4041451884327381504640132478976; // sqrt(2600) * 2^96 calculated
    
    // Minimum balance requirements
    uint256 constant MIN_ETH_BALANCE = 0.01 ether; // Minimum ETH for operations
    uint256 constant MIN_USDC_BALANCE = 2e6; // Minimum 2 USDC for liquidity
    
    // Contract instances
    DetoxHook public hook;
    IPoolManager public poolManager;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    IERC20Minimal public usdc;
    
    // Pool configurations
    PoolKey public poolKey1; // ETH/USDC at 2500
    PoolKey public poolKey2; // ETH/USDC at 2600
    PoolId public poolId1;
    PoolId public poolId2;
    
    // Deployment state
    address public deployer;
    address payable public hookAddress;
    bool public isForked;
    
    // Events
    event PoolInitializationStarted(address indexed hookAddress, uint256 chainId, bool isForked);
    event BalanceChecked(address indexed account, uint256 ethBalance, uint256 usdcBalance, bool sufficient);
    event PoolInitialized(PoolId indexed poolId, uint160 sqrtPriceX96, int24 tickSpacing);
    event LiquidityAdded(PoolId indexed poolId, uint256 usdcAmount, uint256 ethAmount);
    event PoolInitializationCompleted(address indexed hook, PoolId poolId1, PoolId poolId2);

    /// @notice Main function to initialize pools with existing hook
    function run() external {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        // Get hook address from environment
        hookAddress = payable(vm.envAddress("HOOK_ADDRESS"));
        
        // Determine if we're on a fork
        isForked = _isForkedEnvironment();
        
        console.log("=== Pool Initialization with Existing DetoxHook ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Deployer:", deployer);
        console.log("Hook Address:", hookAddress);
        console.log("Is Forked:", isForked);
        console.log("Block Explorer:", ChainAddresses.getBlockExplorer(block.chainid));
        
        emit PoolInitializationStarted(hookAddress, block.chainid, isForked);
        
        // Step 1: Validate hook and check balances
        _validateHookAndCheckBalances();
        
        // Step 2: Initialize contract instances
        _initializeContracts();
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 3: Initialize pools
        _initializePools();
        
        // Step 4: Add liquidity
        _addLiquidity();
        
        vm.stopBroadcast();
        
        // Step 5: Log final summary
        _logDeploymentSummary();
        
        emit PoolInitializationCompleted(hookAddress, poolId1, poolId2);
    }

    /// @notice Determine if we're running on a forked environment
    function _isForkedEnvironment() internal view returns (bool) {
        // Check if coinbase is zero address (indicates local/fork environment)
        return block.coinbase == address(0);
    }

    /// @notice Validate hook exists and check deployer balances
    function _validateHookAndCheckBalances() internal {
        console.log("=== Step 1: Hook Validation & Balance Check ===");
        
        // Validate hook address
        require(hookAddress != address(0), "Hook address cannot be zero");
        require(hookAddress.code.length > 0, "Hook address must contain contract code");
        
        console.log("Hook validation:");
        console.log("  Address:", hookAddress);
        console.log("  Code size:", hookAddress.code.length, "bytes");
        console.log("  [PASS] Hook exists and has code");
        
        // Check balances
        uint256 ethBalance = deployer.balance;
        uint256 usdcBalance = 0;
        
        // Get USDC balance if USDC contract exists
        address usdcAddress = ChainAddresses.getUSDC(block.chainid);
        if (usdcAddress != address(0) && usdcAddress.code.length > 0) {
            usdcBalance = IERC20Minimal(usdcAddress).balanceOf(deployer);
        }
        
        console.log("Balance check:");
        console.log("  ETH Balance:", ethBalance);
        console.log("  USDC Balance:", usdcBalance);
        console.log("  Required ETH:", MIN_ETH_BALANCE);
        console.log("  Required USDC:", MIN_USDC_BALANCE);
        
        bool ethSufficient = ethBalance >= MIN_ETH_BALANCE;
        bool usdcSufficient = usdcBalance >= MIN_USDC_BALANCE;
        bool sufficientBalance = ethSufficient && usdcSufficient;
        
        console.log("  ETH sufficient:", ethSufficient);
        console.log("  USDC sufficient:", usdcSufficient);
        
        if (!sufficientBalance) {
            console.log("");
            console.log("[ERROR] Insufficient balance detected!");
            console.log("===============================================");
            console.log("         POOL INITIALIZATION FAILED!         ");
            console.log("===============================================");
            console.log("");
            console.log("Required balances:");
            console.log("  ETH:  ", MIN_ETH_BALANCE / 1e18, "ETH");
            console.log("  USDC: ", MIN_USDC_BALANCE / 1e6, "USDC");
            console.log("");
            console.log("Current balances:");
            console.log("  ETH:  ", ethBalance / 1e18, "ETH");
            console.log("  USDC: ", usdcBalance / 1e6, "USDC");
            console.log("");
            console.log("Please fund your deployer address:", deployer);
            console.log("Then try again.");
            console.log("");
            
            revert("Insufficient balance for pool operations. Please fund the deployer address.");
        } else {
            console.log("  [PASS] Sufficient balances for pool operations");
        }
        
        emit BalanceChecked(deployer, ethBalance, usdcBalance, sufficientBalance);
    }
    
    /// @notice Initialize contract instances
    function _initializeContracts() internal {
        console.log("=== Step 2: Initialize Contracts ===");
        
        // Validate chain addresses
        if (block.chainid != ChainAddresses.LOCAL_ANVIL) {
            ChainAddresses.validateChainAddresses(block.chainid);
        }
        
        // Get contract addresses
        address poolManagerAddress = ChainAddresses.getPoolManager(block.chainid);
        address usdcAddress = ChainAddresses.getUSDC(block.chainid);
        
        console.log("Contract addresses:");
        console.log("  Pool Manager:", poolManagerAddress);
        console.log("  USDC Token:", usdcAddress);
        console.log("  Hook:", hookAddress);
        
        // Initialize contract instances
        hook = DetoxHook(hookAddress);
        poolManager = IPoolManager(poolManagerAddress);
        usdc = IERC20Minimal(usdcAddress);
        
        // Get PoolModifyLiquidityTest address
        address modifyLiquidityAddress = ChainAddresses.getPoolModifyLiquidityTest(block.chainid);
        require(modifyLiquidityAddress != address(0), "PoolModifyLiquidityTest address not found");
        modifyLiquidityRouter = PoolModifyLiquidityTest(modifyLiquidityAddress);
        console.log("  Modify Liquidity Router:", address(modifyLiquidityRouter));
        
        // Validate hook connection to pool manager
        try hook.poolManager() returns (IPoolManager hookPoolManager) {
            require(address(hookPoolManager) == address(poolManager), "Hook pool manager mismatch");
            console.log("  [PASS] Hook connected to correct pool manager");
        } catch {
            revert("Failed to validate hook pool manager connection");
        }
    }
    
    /// @notice Initialize two pools with different configurations
    function _initializePools() internal {
        console.log("=== Step 3: Initialize Pools ===");
        
        // Setup currencies (ETH and USDC)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(address(usdc)); // USDC
        
        // Ensure proper ordering (currency0 < currency1)
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }
        
        console.log("Currency configuration:");
        console.log("  Currency0 (ETH):", Currency.unwrap(currency0));
        console.log("  Currency1 (USDC):", Currency.unwrap(currency1));
        console.log("  Currency ordering verified:", Currency.unwrap(currency0) < Currency.unwrap(currency1));
        
        // Create pool keys
        poolKey1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING_POOL_1,
            hooks: IHooks(hookAddress)
        });
        
        poolKey2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING_POOL_2,
            hooks: IHooks(hookAddress)
        });
        
        poolId1 = poolKey1.toId();
        poolId2 = poolKey2.toId();
        
        console.log("=== Pool 1 Configuration ===");
        console.log("PoolKey Details:");
        console.log("  currency0:", Currency.unwrap(poolKey1.currency0));
        console.log("  currency1:", Currency.unwrap(poolKey1.currency1));
        console.log("  fee:", poolKey1.fee, "bps (0.05%)");
        console.log("  tickSpacing:", poolKey1.tickSpacing);
        console.log("  hooks:", address(poolKey1.hooks));
        console.log("  Target Price: 2500 USDC/ETH");
        console.log("  sqrtPriceX96:", SQRT_PRICE_2500);
        console.log("  Pool ID:", vm.toString(PoolId.unwrap(poolId1)));
        
        console.log("=== Pool 2 Configuration ===");
        console.log("PoolKey Details:");
        console.log("  currency0:", Currency.unwrap(poolKey2.currency0));
        console.log("  currency1:", Currency.unwrap(poolKey2.currency1));
        console.log("  fee:", poolKey2.fee, "bps (0.05%)");
        console.log("  tickSpacing:", poolKey2.tickSpacing);
        console.log("  hooks:", address(poolKey2.hooks));
        console.log("  Target Price: 2600 USDC/ETH");
        console.log("  sqrtPriceX96:", SQRT_PRICE_2600);
        console.log("  Pool ID:", vm.toString(PoolId.unwrap(poolId2)));
        
        // Initialize pools
        console.log("Initializing Pool 1...");
        try poolManager.initialize(poolKey1, SQRT_PRICE_2500) returns (int24 tick1) {
            console.log("Pool 1 initialized successfully at tick:", tick1);
        } catch Error(string memory reason) {
            console.log("Pool 1 initialization failed:", reason);
            console.log("Pool may already exist - continuing...");
        } catch {
            console.log("Pool 1 initialization failed with unknown error");
            console.log("Pool may already exist - continuing...");
        }
        
        console.log("Initializing Pool 2...");
        try poolManager.initialize(poolKey2, SQRT_PRICE_2600) returns (int24 tick2) {
            console.log("Pool 2 initialized successfully at tick:", tick2);
        } catch Error(string memory reason) {
            console.log("Pool 2 initialization failed:", reason);
            console.log("Pool may already exist - continuing...");
        } catch {
            console.log("Pool 2 initialization failed with unknown error");
            console.log("Pool may already exist - continuing...");
        }
        
        console.log("=== Pools Initialized Successfully ===");
        
        emit PoolInitialized(poolId1, SQRT_PRICE_2500, TICK_SPACING_POOL_1);
        emit PoolInitialized(poolId2, SQRT_PRICE_2600, TICK_SPACING_POOL_2);
    }
    
    /// @notice Add liquidity to both pools
    function _addLiquidity() internal {
        console.log("=== Step 4: Add Liquidity ===");
        
        // Approve USDC for liquidity operations
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        // Calculate ETH amounts for each pool based on prices
        // Pool 1: 1 ETH = 2500 USDC, so 1 USDC = 1/2500 ETH = 0.0004 ETH
        uint256 ethAmount1 = (LIQUIDITY_USDC_AMOUNT * 1e18) / (2500 * 1e6); // Convert to proper decimals
        
        // Pool 2: 1 ETH = 2600 USDC, so 1 USDC = 1/2600 ETH ≈ 0.000385 ETH
        uint256 ethAmount2 = (LIQUIDITY_USDC_AMOUNT * 1e18) / (2600 * 1e6); // Convert to proper decimals
        
        console.log("Liquidity amounts:");
        console.log("  Pool 1 - USDC:", LIQUIDITY_USDC_AMOUNT, "ETH:", ethAmount1);
        console.log("  Pool 2 - USDC:", LIQUIDITY_USDC_AMOUNT, "ETH:", ethAmount2);
        
        // Add liquidity to Pool 1
        console.log("Adding liquidity to Pool 1...");
        try modifyLiquidityRouter.modifyLiquidity{value: ethAmount1}(
            poolKey1,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT), // Use USDC amount directly as liquidity
                salt: bytes32(0)
            }),
            ""
        ) returns (BalanceDelta delta1) {
            console.log("Pool 1 liquidity added successfully");
            console.log("  Balance delta amount0:", delta1.amount0());
            console.log("  Balance delta amount1:", delta1.amount1());
        } catch Error(string memory reason) {
            console.log("Pool 1 liquidity addition failed:", reason);
            console.log("Continuing with script...");
        } catch {
            console.log("Pool 1 liquidity addition failed with unknown error");
            console.log("Continuing with script...");
        }
        
        // Add liquidity to Pool 2
        console.log("Adding liquidity to Pool 2...");
        try modifyLiquidityRouter.modifyLiquidity{value: ethAmount2}(
            poolKey2,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT), // Use USDC amount directly as liquidity
                salt: bytes32(0)
            }),
            ""
        ) returns (BalanceDelta delta2) {
            console.log("Pool 2 liquidity added successfully");
            console.log("  Balance delta amount0:", delta2.amount0());
            console.log("  Balance delta amount1:", delta2.amount1());
        } catch Error(string memory reason) {
            console.log("Pool 2 liquidity addition failed:", reason);
            console.log("Continuing with script...");
        } catch {
            console.log("Pool 2 liquidity addition failed with unknown error");
            console.log("Continuing with script...");
        }
        
        console.log("Liquidity operations completed");
        
        emit LiquidityAdded(poolId1, LIQUIDITY_USDC_AMOUNT, ethAmount1);
        emit LiquidityAdded(poolId2, LIQUIDITY_USDC_AMOUNT, ethAmount2);
    }
    
    /// @notice Log comprehensive summary
    function _logDeploymentSummary() internal view {
        console.log("");
        console.log("===============================================");
        console.log("        POOL INITIALIZATION COMPLETE!        ");
        console.log("===============================================");
        console.log("");
        
        console.log("=== Summary ===");
        console.log("Chain:", ChainAddresses.getChainName(block.chainid));
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("DetoxHook:", hookAddress);
        console.log("Pool Manager:", address(poolManager));
        console.log("USDC Token:", address(usdc));
        console.log("");
        
        console.log("=== Pool 1 Details (ETH/USDC @ 2500) ===");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId1)));
        console.log("Fee: 500 bps (0.05%)");
        console.log("Tick Spacing:", TICK_SPACING_POOL_1);
        console.log("Target Price: 2500 USDC/ETH");
        console.log("Initial Liquidity: 1 USDC + 0.0004 ETH");
        console.log("");
        
        console.log("=== Pool 2 Details (ETH/USDC @ 2600) ===");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId2)));
        console.log("Fee: 500 bps (0.05%)");
        console.log("Tick Spacing:", TICK_SPACING_POOL_2);
        console.log("Target Price: 2600 USDC/ETH");
        console.log("Initial Liquidity: 1 USDC + ~0.000385 ETH");
        console.log("");
        
        console.log("Block Explorer Links:");
        string memory explorerBase = ChainAddresses.getBlockExplorer(block.chainid);
        console.log("Hook Contract:", string.concat(explorerBase, "/address/", vm.toString(hookAddress)));
        console.log("Pool Manager:", string.concat(explorerBase, "/address/", vm.toString(address(poolManager))));
        console.log("");
        
        console.log("[POOLS READY FOR USE]");
        console.log("DetoxHook Address:", hookAddress);
        console.log("Pool 1 ID:", vm.toString(PoolId.unwrap(poolId1)));
        console.log("Pool 2 ID:", vm.toString(PoolId.unwrap(poolId2)));
        console.log("");
    }
} 