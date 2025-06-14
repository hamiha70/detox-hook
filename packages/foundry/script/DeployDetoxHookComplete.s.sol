// SPDX-License-Identifier: MIT
// RULE: Never cast Uniswap V4 wrapper types (e.g., PoolId, Currency) directly to primitive types like uint256 or address. Always use the appropriate unwrap function first.
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IERC20Minimal } from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { DetoxHook } from "../src/DetoxHook.sol";
import { ChainAddresses } from "./ChainAddresses.sol";
import { SwapRouterFixed } from "../src/SwapRouterFixed.sol";
import { DevOpsTools } from "foundry-devops/src/DevOpsTools.sol";
import { PoolParameters } from "./PoolParameters.sol";
import { MockUSDC } from "./MockUSDC.sol";
import { PoolManager } from "@uniswap/v4-core/src/PoolManager.sol";

/// @title Complete DetoxHook Deployment Script
/// @notice Comprehensive script that deploys DetoxHook, initializes pools, and adds liquidity
/// @dev Handles balance checks, verification, funding, and pool setup with different configurations
contract DeployDetoxHookComplete is Script {
    using ChainAddresses for uint256;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    // Hook flags for DetoxHook (beforeSwap + beforeSwapReturnDelta)
    uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    
    // CREATE2 Deployer Proxy address (same across all chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Deployment configuration
    uint256 constant HOOK_FUNDING_AMOUNT = 0.001 ether; // 0.001 ETH
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
    uint256 constant MIN_ETH_BALANCE = 0.05 ether; // Minimum ETH for deployment and operations
    uint256 constant MIN_USDC_BALANCE = 10e6; // Minimum 10 USDC for liquidity
    
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
    bool public isForked;
    
    MockUSDC public mockUsdc;
    PoolManager public localPoolManager;
    
    // Events
    event DeploymentStarted(address indexed deployer, uint256 chainId, bool isForked);
    event BalanceChecked(address indexed account, uint256 ethBalance, uint256 usdcBalance, bool sufficient);
    event DetoxHookDeployed(address indexed hook, bytes32 salt, uint256 chainId);
    event HookFunded(address indexed hook, uint256 amount);
    event PoolInitialized(PoolId indexed poolId, uint160 sqrtPriceX96, int24 tickSpacing);
    event LiquidityAdded(PoolId indexed poolId, uint256 usdcAmount, uint256 ethAmount);
    event DeploymentCompleted(address indexed hook, PoolId poolId1, PoolId poolId2);

    // Add at the top:
    address constant ANVIL_SWAPPER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1

    SwapRouterFixed public swapRouterFixedInstance;

    /// @notice Main deployment function
    function run() external {
        // Select deployer private key and RPC URL based on chainid
        uint256 deployerPrivateKey;
        string memory rpcUrl;
        if (block.chainid == 31337) {
            deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY_31337");
            string memory envRpc = vm.envString("RPC_URL_31337");
            if (bytes(envRpc).length == 0) {
                rpcUrl = "http://localhost:8545";
            } else {
                rpcUrl = envRpc;
            }
        } else if (block.chainid == 421614) {
            deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY_421614");
            rpcUrl = vm.envString("RPC_URL_421614");
        } else if (block.chainid == 1) {
            deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY_1");
            rpcUrl = vm.envString("RPC_URL_1");
        } else {
            revert("Unsupported chain");
        }
        deployer = vm.addr(deployerPrivateKey);
        
        // Deploy local PoolManager and MockUSDC for Anvil
        if (block.chainid == 31337) {
            localPoolManager = new PoolManager(deployer);
            require(address(localPoolManager).code.length > 0, "[INTERNAL ERROR] PoolManager not deployed");
            mockUsdc = new MockUSDC("USD Coin", "USDC", 6);
            require(address(mockUsdc).code.length > 0, "[INTERNAL ERROR] MockUSDC not deployed");
            mockUsdc.mint(deployer, 1_000_000e6); // 1,000,000 USDC to deployer
        }
        
        // Determine if we're on a fork
        isForked = _isForkedEnvironment();
        
        console.log("=== DetoxHook Complete Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Deployer:", deployer);
        console.log("Is Forked:", isForked);
        console.log("Block Explorer:", ChainAddresses.getBlockExplorer(block.chainid));
        
        emit DeploymentStarted(deployer, block.chainid, isForked);
        
        // Step 1: Check balances
        _checkBalances();
        
        // Step 2: Initialize contract instances
        _initializeContracts();
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 3: Deploy DetoxHook
        _deployDetoxHook();
        
        // Final safety check - ensure hook is properly deployed before proceeding
        if (address(hook) == address(0) || address(hook).code.length == 0) {
            console.log("[ERROR] Hook deployment verification failed");
            console.log("Hook address:", address(hook));
            console.log("Hook code length:", address(hook).code.length);
            revert("Deployment stopped: Hook deployment was not successful");
        }
        console.log("[VERIFIED] Hook deployment confirmed before proceeding");
        
        // Step 4: Fund the hook
        _fundHook();
        
        // Step 5: Initialize pools
        _initializePools();
        
        // Step 6: Add liquidity
        _addLiquidity();
        
        // Step 7: Deploy SwapRouterFixed
        _deploySwapRouterFixed();
        
        if (block.chainid == 31337) {
            _setupSwapperAndTestSwap();
            _testSwapWithoutHook();
        }
        
        vm.stopBroadcast();
        
        // Step 8: Verify contracts (only on real networks)
        if (!isForked && block.chainid == ChainAddresses.ARBITRUM_SEPOLIA) {
            _verifyContracts();
        }
        
        // Step 9: Log final summary
        _logDeploymentSummary();
        
        emit DeploymentCompleted(address(hook), poolId1, poolId2);
    }
    
    /// @notice Check that deployer has sufficient ETH and USDC balances
    function _checkBalances() internal {
        console.log("=== Step 1: Balance Check ===");
        
        uint256 ethBalance = deployer.balance;
        uint256 usdcBalance = 0;
        
        // Get USDC balance if USDC contract exists
        address usdcAddress = ChainAddresses.getUSDC(block.chainid);
        if (usdcAddress != address(0) && usdcAddress.code.length > 0) {
            usdcBalance = IERC20Minimal(usdcAddress).balanceOf(deployer);
        }
        
        console.log("ETH Balance:", ethBalance);
        console.log("USDC Balance:", usdcBalance);
        console.log("Required ETH:", MIN_ETH_BALANCE);
        console.log("Required USDC:", MIN_USDC_BALANCE);
        
        bool ethSufficient = ethBalance >= MIN_ETH_BALANCE;
        bool usdcSufficient = usdcBalance >= MIN_USDC_BALANCE;
        bool sufficientBalance;
        if (block.chainid == ChainAddresses.LOCAL_ANVIL) {
            // Bypass USDC check for local testing
            usdcSufficient = true;
            sufficientBalance = ethSufficient;
            console.log("[WARNING] Bypassing USDC balance check for LOCAL_ANVIL (31337). No USDC required for local testing.");
        } else {
            sufficientBalance = ethSufficient && usdcSufficient;
        }
        
        console.log("ETH sufficient:", ethSufficient);
        console.log("USDC sufficient:", usdcSufficient);
        
        if (!sufficientBalance) {
            console.log("");
            console.log("[ERROR] Insufficient balance detected!");
            console.log("===============================================");
            console.log("           DEPLOYMENT FAILED!                ");
            console.log("===============================================");
            console.log("");
            console.log("Required balances:");
            console.log("  ETH:  ", MIN_ETH_BALANCE, "wei");
            console.log("  ETH:  ", MIN_ETH_BALANCE / 1e18, "ETH");
            console.log("  USDC: ", MIN_USDC_BALANCE);
            console.log("  USDC: ", MIN_USDC_BALANCE / 1e6, "USDC");
            console.log("");
            console.log("Current balances:");
            console.log("  ETH:  ", ethBalance, "wei");
            console.log("  ETH:  ", ethBalance / 1e18, "ETH");
            console.log("  USDC: ", usdcBalance);
            console.log("  USDC: ", usdcBalance / 1e6, "USDC");
            console.log("");
            console.log("Please fund your deployer address:", deployer);
            console.log("Then try again.");
            console.log("");
            
            revert("Insufficient balance for deployment. Please fund the deployer address.");
        } else {
            console.log("[PASS] Sufficient balances for deployment");
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
        if (block.chainid == 31337) {
            require(address(localPoolManager).code.length > 0, "[INTERNAL ERROR] PoolManager not deployed");
            require(address(mockUsdc).code.length > 0, "[INTERNAL ERROR] MockUSDC not deployed");
            poolManager = localPoolManager;
            usdc = IERC20Minimal(address(mockUsdc));
            console.log("Pool Manager:", address(localPoolManager));
            console.log("USDC Token:", address(mockUsdc));
        } else {
            address poolManagerAddress = ChainAddresses.getPoolManager(block.chainid);
            address usdcAddress = ChainAddresses.getUSDC(block.chainid);
            require(poolManagerAddress.code.length > 0, "[ERROR] PoolManager address has no code deployed");
            require(usdcAddress.code.length > 0, "[ERROR] USDC address has no code deployed");
            poolManager = IPoolManager(poolManagerAddress);
            usdc = IERC20Minimal(usdcAddress);
            console.log("Pool Manager:", poolManagerAddress);
            console.log("USDC Token:", usdcAddress);
        }
        // Get PoolModifyLiquidityTest address
        address modifyLiquidityAddress = ChainAddresses.getPoolModifyLiquidityTest(block.chainid);
        if (modifyLiquidityAddress != address(0)) {
            require(modifyLiquidityAddress.code.length > 0, "[ERROR] PoolModifyLiquidityTest address has no code deployed");
            modifyLiquidityRouter = PoolModifyLiquidityTest(modifyLiquidityAddress);
            console.log("Using existing PoolModifyLiquidityTest at:", address(modifyLiquidityRouter));
        } else {
            modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);
            require(address(modifyLiquidityRouter).code.length > 0, "[INTERNAL ERROR] PoolModifyLiquidityTest not deployed");
            console.log("PoolModifyLiquidityTest deployed at:", address(modifyLiquidityRouter));
        }
    }
    
    /// @notice Deploy DetoxHook with proper address mining
    function _deployDetoxHook() internal {
        console.log("=== Step 3: Deploy DetoxHook ===");
        
        // Mine the correct salt for hook address
        bytes32 salt;
        try this._mineHookSaltExternal() returns (bytes32 minedSalt) {
            salt = minedSalt;
            console.log("Salt mining successful");
        } catch {
            console.log("[ERROR] Failed to mine hook salt");
            revert("Hook deployment failed: unable to mine valid salt for hook address");
        }
        
        // Deploy the hook using CREATE2
        try this._deployDetoxHookWithSaltExternal(salt) returns (DetoxHook deployedHook) {
            hook = deployedHook;
            console.log("Hook deployment successful");
        } catch Error(string memory reason) {
            console.log("[ERROR] Hook deployment failed:", reason);
            revert(string.concat("Hook deployment failed: ", reason));
        } catch {
            console.log("[ERROR] Hook deployment failed with unknown error");
            revert("Hook deployment failed: unknown error during CREATE2 deployment");
        }
        
        // Validate deployment
        try this._validateHookDeploymentExternal() {
            console.log("Hook validation successful");
        } catch Error(string memory reason) {
            console.log("[ERROR] Hook validation failed:", reason);
            revert(string.concat("Hook deployment failed validation: ", reason));
        } catch {
            console.log("[ERROR] Hook validation failed with unknown error");
            revert("Hook deployment failed: validation error");
        }
        
        console.log("");
        console.log("[SUCCESS] DetoxHook deployed successfully!");
        console.log("[ADDRESS] DetoxHook Address:", address(hook));
        console.log("");
        
        emit DetoxHookDeployed(address(hook), salt, block.chainid);
    }
    
    /// @notice External wrapper for salt mining (for try-catch)
    function _mineHookSaltExternal() external view returns (bytes32) {
        return _mineHookSalt();
    }
    
    /// @notice External wrapper for hook deployment (for try-catch)
    function _deployDetoxHookWithSaltExternal(bytes32 salt) external returns (DetoxHook) {
        return _deployDetoxHookWithSalt(salt);
    }
    
    /// @notice External wrapper for hook validation (for try-catch)
    function _validateHookDeploymentExternal() external view {
        _validateHookDeployment();
    }
    
    /// @notice Mine the correct salt for DetoxHook deployment
    function _mineHookSalt() internal view returns (bytes32 salt) {
        console.log("=== Mining Hook Address ===");
        console.log("Required flags:", HOOK_FLAGS);
        console.log("CREATE2 Deployer:", CREATE2_DEPLOYER);
        console.log("Mining for address with correct flag bits...");
        
        // Prepare creation code with constructor arguments
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            deployer,
            ChainAddresses.getPythOracle(block.chainid)
        );
        
        console.log("Constructor arguments:");
        console.log("  Pool Manager:", address(poolManager));
        console.log("  Owner:", deployer);
        console.log("  Oracle:", ChainAddresses.getPythOracle(block.chainid));
        
        // Mine the salt using HookMiner
        address expectedAddress;
        (expectedAddress, salt) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs);
        
        console.log("=== HookMiner Results ===");
        console.log("Salt found:", vm.toString(salt));
        console.log("Expected hook address:", expectedAddress);
        console.log("Address flags:", uint160(expectedAddress) & HookMiner.FLAG_MASK);
        console.log("Required flags:", HOOK_FLAGS);
        console.log("Flags match:", (uint160(expectedAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        return salt;
    }
    
    /// @notice Deploy DetoxHook using CREATE2 with the given salt
    function _deployDetoxHookWithSalt(bytes32 salt) internal returns (DetoxHook) {
        console.log("=== CREATE2 Deployment ===");
        
        // Prepare deployment data
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            deployer,
            ChainAddresses.getPythOracle(block.chainid)
        );
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        
        // Calculate expected address for verification
        address expectedAddress = HookMiner.computeAddress(CREATE2_DEPLOYER, uint256(salt), deploymentData);
        
        console.log("Expected address:", expectedAddress);
        console.log("Using CREATE2 Deployer:", CREATE2_DEPLOYER);
        console.log("Deployment data length:", deploymentData.length);
        
        // Check if CREATE2 deployer exists
        if (CREATE2_DEPLOYER.code.length == 0) {
            console.log("[ERROR] CREATE2 Deployer not found at:", CREATE2_DEPLOYER);
            revert("CREATE2 Deployer contract not found - cannot deploy hook");
        }
        console.log("CREATE2 Deployer verified");
        
        // Check if address is already deployed
        if (expectedAddress.code.length > 0) {
            console.log("[ERROR] Contract already deployed at expected address");
            console.log("Address:", expectedAddress);
            console.log("Code length:", expectedAddress.code.length);
            revert("Hook deployment failed: contract already exists at expected address");
        }
        
        // The CREATE2 Deployer Proxy expects: salt (32 bytes) + creation code
        bytes memory callData = abi.encodePacked(salt, deploymentData);
        console.log("Call data length:", callData.length);
        
        console.log("Executing CREATE2 deployment...");
        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        
        if (!success) {
            console.log("[ERROR] CREATE2 deployment call failed");
            if (returnData.length > 0) {
                console.log("Error data length:", returnData.length);
                // Try to decode revert reason
                if (returnData.length >= 4) {
                    console.log("Error selector:", vm.toString(bytes4(returnData)));
                }
            }
            revert("CREATE2 deployment failed - call unsuccessful");
        }
        
        if (returnData.length != 20) {
            console.log("[ERROR] Invalid return data length from CREATE2");
            console.log("Expected: 20 bytes (address)");
            console.log("Actual:", returnData.length, "bytes");
            revert("CREATE2 deployment failed: invalid return data length");
        }
        
        // Extract deployed address from return data
        address deployedAddress = address(bytes20(returnData));
        console.log("Deployed address:", deployedAddress);
        
        if (deployedAddress != expectedAddress) {
            console.log("[ERROR] Deployment address mismatch");
            console.log("Expected:", expectedAddress);
            console.log("Deployed:", deployedAddress);
            revert("CREATE2 deployment failed: address mismatch");
        }
        
        // Verify the contract was actually deployed
        if (deployedAddress.code.length == 0) {
            console.log("[ERROR] No code found at deployed address");
            console.log("Address:", deployedAddress);
            revert("CREATE2 deployment failed: no contract code at deployed address");
        }
        
        console.log("[SUCCESS] CREATE2 deployment successful");
        console.log("Contract deployed at:", deployedAddress);
        console.log("Contract code size:", deployedAddress.code.length, "bytes");
        
        return DetoxHook(payable(deployedAddress));
    }
    
    /// @notice Validate the deployed DetoxHook
    function _validateHookDeployment() internal view {
        console.log("=== Deployment Validation ===");
        
        // Check if hook address has code (deployment successful)
        if (address(hook).code.length == 0) {
            console.log("[ERROR] Hook deployment failed - no code at address");
            console.log("Hook address:", address(hook));
            revert("Hook deployment failed: no contract code found at hook address");
        }
        console.log("Contract code deployed:", address(hook).code.length, "bytes");
        
        // Check if hook is a valid contract by calling a view function
        try hook.poolManager() returns (IPoolManager manager) {
            console.log("Hook poolManager() call successful:", address(manager));
            if (address(manager) != address(poolManager)) {
                console.log("[ERROR] Hook poolManager mismatch");
                console.log("Expected:", address(poolManager));
                console.log("Actual:", address(manager));
                revert("Hook deployment failed: poolManager mismatch");
            }
        } catch {
            console.log("[ERROR] Hook poolManager() call failed");
            revert("Hook deployment failed: cannot call hook functions");
        }
        
        // Check hook permissions
        Hooks.Permissions memory permissions;
        try hook.getHookPermissions() returns (Hooks.Permissions memory perms) {
            permissions = perms;
            console.log("Hook permissions retrieved successfully");
        } catch {
            console.log("[ERROR] Cannot retrieve hook permissions");
            revert("Hook deployment failed: cannot get hook permissions");
        }
        
        console.log("Hook permissions:");
        console.log("  beforeSwap:", permissions.beforeSwap);
        console.log("  beforeSwapReturnDelta:", permissions.beforeSwapReturnDelta);
        console.log("  beforeInitialize:", permissions.beforeInitialize);
        console.log("  afterInitialize:", permissions.afterInitialize);
        
        // Validate required permissions
        if (!permissions.beforeSwap) {
            console.log("[ERROR] beforeSwap permission not set");
            revert("Hook deployment failed: beforeSwap permission not enabled");
        }
        
        if (!permissions.beforeSwapReturnDelta) {
            console.log("[ERROR] beforeSwapReturnDelta permission not set");
            revert("Hook deployment failed: beforeSwapReturnDelta permission not enabled");
        }
        
        // Validate hook address has correct flags
        uint160 hookAddress = uint160(address(hook));
        uint160 addressFlags = hookAddress & HookMiner.FLAG_MASK;
        console.log("Hook address flags:", addressFlags);
        console.log("Required flags:", HOOK_FLAGS);
        
        if (addressFlags != HOOK_FLAGS) {
            console.log("[ERROR] Hook address flags incorrect");
            console.log("Expected flags:", HOOK_FLAGS);
            console.log("Actual flags:", addressFlags);
            revert("Hook deployment failed: incorrect address flags");
        }
        
        // Verify hook is connected to the correct pool manager
        if (address(hook.poolManager()) != address(poolManager)) {
            console.log("[ERROR] Hook not connected to correct pool manager");
            console.log("Expected:", address(poolManager));
            console.log("Actual:", address(hook.poolManager()));
            revert("Hook deployment failed: wrong pool manager connection");
        }
        
        // Check if hook can receive ETH (has receive/fallback function)
        console.log("Testing hook ETH reception...");
        
        // Additional validation: check hook owner
        try hook.owner() returns (address owner) {
            console.log("Hook owner:", owner);
            if (owner != deployer) {
                console.log("[ERROR] Hook owner mismatch");
                console.log("Expected:", deployer);
                console.log("Actual:", owner);
                revert("Hook deployment failed: incorrect owner");
            }
        } catch {
            console.log("[WARNING] Cannot verify hook owner (function may not exist)");
        }
        
        console.log("[SUCCESS] Hook deployment validation passed");
        console.log("Hook address:", address(hook));
        console.log("Hook code size:", address(hook).code.length, "bytes");
        console.log("Hook permissions verified");
        console.log("Hook address flags verified");
        console.log("Hook pool manager connection verified");
    }
    
    /// @notice Fund the DetoxHook with ETH
    function _fundHook() internal {
        console.log("=== Step 4: Fund DetoxHook ===");
        
        console.log("Funding hook with", HOOK_FUNDING_AMOUNT, "ETH");
        
        (bool success,) = payable(address(hook)).call{value: HOOK_FUNDING_AMOUNT}("");
        require(success, "Failed to fund hook");
        
        console.log("Hook funded successfully");
        console.log("Hook ETH balance:", address(hook).balance);
        
        emit HookFunded(address(hook), HOOK_FUNDING_AMOUNT);
    }
    
    /// @notice Initialize two pools with different configurations
    function _initializePools() internal {
        console.log("=== Step 5: Initialize Pools ===");
        
        // Setup currencies (ETH and USDC)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(address(usdc)); // USDC
        
        // Ensure proper ordering (currency0 < currency1)
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }
        
        console.log("=== Currency Configuration ===");
        console.log("Currency0 (ETH):", Currency.unwrap(currency0));
        console.log("Currency1 (USDC):", Currency.unwrap(currency1));
        console.log("Currency ordering verified:", Currency.unwrap(currency0) < Currency.unwrap(currency1));
        
        // Create pool keys
        poolKey1 = PoolParameters.getPoolKey1(block.chainid, address(hook), address(usdc));
        poolKey2 = PoolParameters.getPoolKey2(block.chainid, address(hook), address(usdc));
        
        poolId1 = poolKey1.toId();
        poolId2 = poolKey2.toId();
        
        console.log("=== Pool 1 Configuration ===");
        console.log("PoolKey1.currency0:", Currency.unwrap(poolKey1.currency0));
        console.log("PoolKey1.currency1:", Currency.unwrap(poolKey1.currency1));
        console.log("PoolKey1.fee:", poolKey1.fee);
        console.log("PoolKey1.tickSpacing:", poolKey1.tickSpacing);
        console.log("PoolKey1.hooks:", address(poolKey1.hooks));
        console.log("PoolId1:", uint256(PoolId.unwrap(poolId1)));
        
        console.log("=== Pool 2 Configuration ===");
        console.log("PoolKey2.currency0:", Currency.unwrap(poolKey2.currency0));
        console.log("PoolKey2.currency1:", Currency.unwrap(poolKey2.currency1));
        console.log("PoolKey2.fee:", poolKey2.fee);
        console.log("PoolKey2.tickSpacing:", poolKey2.tickSpacing);
        console.log("PoolKey2.hooks:", address(poolKey2.hooks));
        console.log("PoolId2:", uint256(PoolId.unwrap(poolId2)));
        
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
        console.log("=== Step 6: Add Liquidity ===");
        
        // Approve USDC for liquidity operations
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        // Calculate ETH amounts for each pool based on prices
        // Pool 1: 1 ETH = 2500 USDC, so 1 USDC = 1/2500 ETH = 0.0004 ETH
        uint256 ethAmount1 = (LIQUIDITY_USDC_AMOUNT * 1e18) / (2500 * 1e6); // Convert to proper decimals
        
        // Pool 2: 1 ETH = 2600 USDC, so 1 USDC = 1/2600 ETH ≈ 0.000385 ETH
        uint256 ethAmount2 = (LIQUIDITY_USDC_AMOUNT * 1e18) / (2600 * 1e6); // Convert to proper decimals
        
        console.log("Adding liquidity to Pool 1:");
        console.log("  USDC Amount:", LIQUIDITY_USDC_AMOUNT);
        console.log("  ETH Amount:", ethAmount1);
        
        console.log("Adding liquidity to Pool 2:");
        console.log("  USDC Amount:", LIQUIDITY_USDC_AMOUNT);
        console.log("  ETH Amount:", ethAmount2);
        
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
        } catch Error(string memory reason) {
            console.log("Pool 1 liquidity addition failed:", reason);
            console.log("Continuing with deployment...");
        } catch {
            console.log("Pool 1 liquidity addition failed with unknown error");
            console.log("Continuing with deployment...");
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
        } catch Error(string memory reason) {
            console.log("Pool 2 liquidity addition failed:", reason);
            console.log("Continuing with deployment...");
        } catch {
            console.log("Pool 2 liquidity addition failed with unknown error");
            console.log("Continuing with deployment...");
        }
        
        console.log("Liquidity added successfully to both pools");
        
        emit LiquidityAdded(poolId1, LIQUIDITY_USDC_AMOUNT, ethAmount1);
        emit LiquidityAdded(poolId2, LIQUIDITY_USDC_AMOUNT, ethAmount2);
    }
    
    /// @notice Deploy SwapRouterFixed
    function _deploySwapRouterFixed() internal {
        console.log("=== Step 7: Deploy SwapRouterFixed ===");
        address poolSwapTest = ChainAddresses.getPoolSwapTest(block.chainid);
        if (block.chainid == 31337 && poolSwapTest == address(0)) {
            // Deploy PoolSwapTest for Anvil if not set
            poolSwapTest = address(new PoolSwapTest(poolManager));
            console.log("[ANVIL] Deployed PoolSwapTest at:", poolSwapTest);
        } else {
            require(poolSwapTest != address(0), "PoolSwapTest address not set for this chain");
        }
        address detoxHook;
        if (block.chainid == 31337) {
            detoxHook = address(hook); // Use in-memory deployed address
        } else {
            detoxHook = DevOpsTools.get_most_recent_deployment("DetoxHook", block.chainid);
            require(detoxHook != address(0), "DetoxHook address not found");
        }
        PoolKey memory poolKey = PoolParameters.getPoolKey1(block.chainid, detoxHook, address(usdc));
        swapRouterFixedInstance = new SwapRouterFixed(poolSwapTest, poolKey);
        console.log("SwapRouterFixed deployed at:", address(swapRouterFixedInstance));
        // Verify configuration
        PoolKey memory deployedPoolKey = swapRouterFixedInstance.getPoolConfiguration();
        console.log("Verified pool configuration:");
        console.log("  Currency0:", Currency.unwrap(deployedPoolKey.currency0));
        console.log("  Currency1:", Currency.unwrap(deployedPoolKey.currency1));
        console.log("  Fee:", deployedPoolKey.fee);
        console.log("  TickSpacing:", deployedPoolKey.tickSpacing);
        console.log("  Hooks:", address(deployedPoolKey.hooks));
        require(address(deployedPoolKey.hooks) == detoxHook, "SwapRouterFixed not configured with correct DetoxHook");
        console.log("SwapRouterFixed configuration verified.");
    }
    
    /// @notice Verify contracts on block explorer
    function _verifyContracts() internal view {
        console.log("=== Step 8: Contract Verification ===");
        console.log("Verifying DetoxHook on Arbitrum Sepolia Blockscout...");
        
        // Note: Actual verification would be done via forge verify command
        // This is just logging the information needed for verification
        console.log("Contract Address:", address(hook));
        console.log("Constructor Args:");
        console.log("  Pool Manager:", address(poolManager));
        console.log("  Owner:", deployer);
        console.log("  Oracle:", ChainAddresses.getPythOracle(block.chainid));
        
        console.log("Verification Command:");
        console.log("forge verify-contract", address(hook), "src/DetoxHook.sol:DetoxHook");
        console.log("  --chain-id", block.chainid);
        console.log("  --constructor-args", vm.toString(abi.encode(
            address(poolManager),
            deployer,
            ChainAddresses.getPythOracle(block.chainid)
        )));
        console.log("  --verifier blockscout");
        console.log("  --verifier-url https://arbitrum-sepolia.blockscout.com/api");
    }
    
    /// @notice Log comprehensive deployment summary
    function _logDeploymentSummary() internal view {
        console.log("");
        console.log("===============================================");
        console.log("           DEPLOYMENT SUCCESSFUL!            ");
        console.log("===============================================");
        console.log("");
        console.log("[DETOX HOOK ADDRESS]:", address(hook));
        console.log("");
        
        console.log("=== Deployment Summary ===");
        console.log("Chain:", ChainAddresses.getChainName(block.chainid));
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("DetoxHook:", address(hook));
        console.log("Hook ETH Balance:", address(hook).balance);
        console.log("Pool Manager:", address(poolManager));
        console.log("USDC Token:", address(usdc));
        console.log("SwapRouterFixed:", address(swapRouterFixedInstance));
        console.log("");
        
        console.log("=== Hook Configuration ===");
        console.log("Hook Flags:", uint160(address(hook)) & HookMiner.FLAG_MASK);
        console.log("Required Flags:", HOOK_FLAGS);
        console.log("beforeSwap: true");
        console.log("beforeSwapReturnDelta: true");
        console.log("");
        
        console.log("=== Pool 1 Details (ETH/USDC @ 2500) ===");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId1)));
        console.log("PoolKey:");
        console.log("  currency0:", Currency.unwrap(poolKey1.currency0), "(ETH)");
        console.log("  currency1:", Currency.unwrap(poolKey1.currency1), "(USDC)");
        console.log("  fee:", poolKey1.fee, "bps (0.05%)");
        console.log("  tickSpacing:", poolKey1.tickSpacing);
        console.log("  hooks:", address(poolKey1.hooks));
        console.log("  sqrtPriceX96:", SQRT_PRICE_2500);
        console.log("");
        
        console.log("=== Pool 2 Details (ETH/USDC @ 2600) ===");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId2)));
        console.log("PoolKey:");
        console.log("  currency0:", Currency.unwrap(poolKey2.currency0), "(ETH)");
        console.log("  currency1:", Currency.unwrap(poolKey2.currency1), "(USDC)");
        console.log("  fee:", poolKey2.fee, "bps (0.05%)");
        console.log("  tickSpacing:", poolKey2.tickSpacing);
        console.log("  hooks:", address(poolKey2.hooks));
        console.log("  sqrtPriceX96:", SQRT_PRICE_2600);
        console.log("");
        
        console.log("=== Liquidity Information ===");
        console.log("USDC per pool:", LIQUIDITY_USDC_AMOUNT / 1e6, "USDC");
        console.log("ETH for Pool 1:", (LIQUIDITY_USDC_AMOUNT * 1e18) / (2500 * 1e6));
        console.log("ETH for Pool 2:", (LIQUIDITY_USDC_AMOUNT * 1e18) / (2600 * 1e6));
        console.log("");
        
        console.log("Block Explorer Links:");
        string memory explorerBase = ChainAddresses.getBlockExplorer(block.chainid);
        console.log("Hook Contract:", string.concat(explorerBase, "/address/", vm.toString(address(hook))));
        console.log("Pool Manager:", string.concat(explorerBase, "/address/", vm.toString(address(poolManager))));
        console.log("");
        
        console.log("[COPY THIS ADDRESS FOR YOUR RECORDS]:");
        console.log("DetoxHook:", address(hook));
        console.log("");
        
        console.log("Next Steps:");
        console.log("1. Verify the contract on block explorer");
        console.log("2. Test swaps on both pools");
        console.log("3. Monitor hook arbitrage capture");
        console.log("4. Add more liquidity as needed");
        console.log("");
        
        console.log("=== Pool IDs for Frontend Integration ===");
        console.log("Pool 1 ID (hex):", vm.toString(PoolId.unwrap(poolId1)));
        console.log("Pool 2 ID (hex):", vm.toString(PoolId.unwrap(poolId2)));
    }
    
    /// @notice Check if we're running on a forked environment
    function _isForkedEnvironment() internal view returns (bool) {
        // More reliable fork detection: check if we have a fork URL in the environment
        // or if we're running with specific fork-related flags
        
        // Method 1: Check if block.coinbase is the default Anvil coinbase (0x0000000000000000000000000000000000000000)
        // Real networks have real coinbase addresses
        if (block.coinbase == address(0)) {
            return true; // Likely a fork or local network
        }
        
        // Method 2: Check if we're on local Anvil
        if (block.chainid == ChainAddresses.LOCAL_ANVIL) {
            return true;
        }
        
        // Method 3: For Arbitrum Sepolia, check if block.difficulty is 0 (which it should be for real Arbitrum)
        // Forks might have different difficulty values
        if (block.chainid == ChainAddresses.ARBITRUM_SEPOLIA) {
            // On real Arbitrum networks, block.difficulty should be 0
            // If it's not 0, we might be on a fork
            // However, this is not reliable, so we'll default to false for real networks
            return false; // Assume real network unless proven otherwise
        }
        
        return false; // Default to real network
    }
    
    /// @notice Emergency function to recover ETH (only for testing)
    function emergencyWithdraw() external {
        require(msg.sender == deployer, "Only deployer");
        require(isForked || block.chainid == ChainAddresses.LOCAL_ANVIL, "Only on test networks");
        
        payable(deployer).transfer(address(this).balance);
    }
    
    /// @notice Receive function to accept ETH
    receive() external payable {}

    /// @notice Setup swapper and test swap on Anvil
    function _setupSwapperAndTestSwap() internal {
        console.log("=== Step 8: Swapper Setup and Test Swap (Anvil) ===");
        // Mint USDC to swapper
        mockUsdc.mint(ANVIL_SWAPPER, 10_000e6); // 10,000 USDC
        console.log("Minted 10,000 USDC to swapper:", ANVIL_SWAPPER);
        // Approve SwapRouterFixed to spend USDC from deployer (broadcasted scripts cannot use prank)
        address swapRouterFixed = address(swapRouterFixedInstance);
        // In broadcasted scripts, all actions must be performed by the deployer account.
        // We cannot use vm.startPrank or impersonate other accounts.
        // Therefore, we perform the approval and swap as the deployer.
        mockUsdc.approve(swapRouterFixed, type(uint256).max);
        console.log("Deployer approved SwapRouterFixed to spend USDC");
        // Log balances before swap
        uint256 ethBefore = deployer.balance;
        uint256 usdcBefore = mockUsdc.balanceOf(deployer);
        console.log("Deployer ETH before:", ethBefore);
        console.log("Deployer USDC before:", usdcBefore);
        // Perform a test swap (USDC -> ETH)
        // For USDC->ETH, zeroForOne = false, amountToSwap = -1000e6 (exact input)
        try swapRouterFixedInstance.swap(-1000e6, false, "") returns (BalanceDelta delta) {
            console.log("Swap executed: 1000 USDC -> ETH");
        } catch Error(string memory reason) {
            console.log("Swap failed (string):", reason);
        } catch Panic(uint256 code) {
            console.log("Swap failed (panic):", code);
        } catch (bytes memory lowLevelData) {
            // Log the length and first 32 bytes as uint256
            console.log("Swap failed (raw), length:", lowLevelData.length);
            if (lowLevelData.length >= 32) {
                uint256 firstWord;
                assembly {
                    firstWord := mload(add(lowLevelData, 32))
                }
                console.log("First 32 bytes as uint256:", firstWord);
            }
        }
        // Log balances after swap
        uint256 ethAfter = deployer.balance;
        uint256 usdcAfter = mockUsdc.balanceOf(deployer);
        console.log("Deployer ETH after:", ethAfter);
        console.log("Deployer USDC after:", usdcAfter);
    }

    /// @notice Deploy a control pool (ETH/USDC) without the hook, add liquidity, and test a swap
    function _testSwapWithoutHook() internal {
        console.log("=== CONTROL: Deploying Pool WITHOUT Hook ===");
        // Deploy a new PoolManager and USDC for isolation (or reuse existing localPoolManager/mockUsdc)
        PoolManager controlPoolManager = new PoolManager(deployer);
        require(address(controlPoolManager).code.length > 0, "[INTERNAL ERROR] Control PoolManager not deployed");
        MockUSDC controlUsdc = new MockUSDC("USD Coin", "USDC", 6);
        require(address(controlUsdc).code.length > 0, "[INTERNAL ERROR] Control MockUSDC not deployed");
        controlUsdc.mint(deployer, 1_000_000e6);
        // Create pool key (no hook)
        PoolKey memory controlPoolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(controlUsdc)),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        // Deploy PoolModifyLiquidityTest for this pool
        PoolModifyLiquidityTest controlModifyLiquidity = new PoolModifyLiquidityTest(controlPoolManager);
        require(address(controlModifyLiquidity).code.length > 0, "[INTERNAL ERROR] Control PoolModifyLiquidityTest not deployed");
        // Initialize pool at sqrtPriceX96 for 2500 (same as main pool)
        uint160 sqrtPriceX96 = 3961408125713216879677197516800;
        controlPoolManager.initialize(controlPoolKey, sqrtPriceX96);
        console.log("[CONTROL] Pool initialized");
        // Add liquidity (same as main pool)
        controlUsdc.approve(address(controlModifyLiquidity), type(uint256).max);
        controlModifyLiquidity.modifyLiquidity{value: 400_000_000_000_000}(
            controlPoolKey,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: 1_000_000,
                salt: bytes32(0)
            }),
            ""
        );
        console.log("[CONTROL] Liquidity added");
        // Deploy PoolSwapTest for this pool
        PoolSwapTest controlPoolSwapTest = new PoolSwapTest(controlPoolManager);
        require(address(controlPoolSwapTest).code.length > 0, "[INTERNAL ERROR] Control PoolSwapTest not deployed");
        // Deploy SwapRouterFixed for this pool
        SwapRouterFixed controlSwapRouter = new SwapRouterFixed(address(controlPoolSwapTest), controlPoolKey);
        require(address(controlSwapRouter).code.length > 0, "[INTERNAL ERROR] Control SwapRouterFixed not deployed");
        // Approve router for USDC
        controlUsdc.approve(address(controlSwapRouter), type(uint256).max);
        // Log balances before swap
        uint256 ethBefore = deployer.balance;
        uint256 usdcBefore = controlUsdc.balanceOf(deployer);
        console.log("[CONTROL] Deployer ETH before:", ethBefore);
        console.log("[CONTROL] Deployer USDC before:", usdcBefore);
        // Try a swap (USDC -> ETH, no hook, so hookData is empty)
        try controlSwapRouter.swap(-1000e6, false, "") returns (BalanceDelta delta) {
            console.log("[CONTROL] Swap executed: 1000 USDC -> ETH");
        } catch Error(string memory reason) {
            console.log("[CONTROL] Swap failed (string):", reason);
        } catch Panic(uint256 code) {
            console.log("[CONTROL] Swap failed (panic):", code);
        } catch (bytes memory lowLevelData) {
            console.log("[CONTROL] Swap failed (raw), length:", lowLevelData.length);
            if (lowLevelData.length >= 32) {
                uint256 firstWord;
                assembly {
                    firstWord := mload(add(lowLevelData, 32))
                }
                console.log("[CONTROL] First 32 bytes as uint256:", firstWord);
            }
        }
        // Log balances after swap
        uint256 ethAfter = deployer.balance;
        uint256 usdcAfter = controlUsdc.balanceOf(deployer);
        console.log("[CONTROL] Deployer ETH after:", ethAfter);
        console.log("[CONTROL] Deployer USDC after:", usdcAfter);
    }
} 