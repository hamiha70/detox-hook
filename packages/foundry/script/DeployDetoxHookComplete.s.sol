// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { IERC20Minimal } from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import { PoolModifyLiquidityTest } from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import { ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

import { DetoxHook } from "../src/DetoxHook.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

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
    uint256 constant MIN_ETH_BALANCE = 0.1 ether; // Minimum ETH for deployment and operations
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
    
    // Events
    event DeploymentStarted(address indexed deployer, uint256 chainId, bool isForked);
    event BalanceChecked(address indexed account, uint256 ethBalance, uint256 usdcBalance, bool sufficient);
    event DetoxHookDeployed(address indexed hook, bytes32 salt, uint256 chainId);
    event HookFunded(address indexed hook, uint256 amount);
    event PoolInitialized(PoolId indexed poolId, uint160 sqrtPriceX96, int24 tickSpacing);
    event LiquidityAdded(PoolId indexed poolId, uint256 usdcAmount, uint256 ethAmount);
    event DeploymentCompleted(address indexed hook, PoolId poolId1, PoolId poolId2);

    /// @notice Main deployment function
    function run() external {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
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
        
        // Step 4: Fund the hook
        _fundHook();
        
        // Step 5: Initialize pools
        _initializePools();
        
        // Step 6: Add liquidity
        _addLiquidity();
        
        vm.stopBroadcast();
        
        // Step 7: Verify contracts (only on real networks)
        if (!isForked && block.chainid == ChainAddresses.ARBITRUM_SEPOLIA) {
            _verifyContracts();
        }
        
        // Step 8: Log final summary
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
        bool sufficientBalance = ethSufficient && usdcSufficient;
        
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
        address poolManagerAddress = ChainAddresses.getPoolManager(block.chainid);
        address usdcAddress = ChainAddresses.getUSDC(block.chainid);
        
        console.log("Pool Manager:", poolManagerAddress);
        console.log("USDC Token:", usdcAddress);
        
        // Initialize contract instances
        poolManager = IPoolManager(poolManagerAddress);
        usdc = IERC20Minimal(usdcAddress);
        
        // Get PoolModifyLiquidityTest address
        address modifyLiquidityAddress = ChainAddresses.getPoolModifyLiquidityTest(block.chainid);
        if (modifyLiquidityAddress != address(0)) {
            modifyLiquidityRouter = PoolModifyLiquidityTest(modifyLiquidityAddress);
            console.log("Using existing PoolModifyLiquidityTest at:", address(modifyLiquidityRouter));
        } else {
            // Deploy PoolModifyLiquidityTest if needed (for testing)
            modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);
            console.log("PoolModifyLiquidityTest deployed at:", address(modifyLiquidityRouter));
        }
    }
    
    /// @notice Deploy DetoxHook with proper address mining
    function _deployDetoxHook() internal {
        console.log("=== Step 3: Deploy DetoxHook ===");
        
        // Mine the correct salt for hook address
        bytes32 salt = _mineHookSalt();
        
        // Deploy the hook using CREATE2
        hook = _deployDetoxHookWithSalt(salt);
        
        // Validate deployment
        _validateHookDeployment();
        
        console.log("");
        console.log("[SUCCESS] DetoxHook deployed successfully!");
        console.log("[ADDRESS] DetoxHook Address:", address(hook));
        console.log("");
        
        emit DetoxHookDeployed(address(hook), salt, block.chainid);
    }
    
    /// @notice Mine the correct salt for DetoxHook deployment
    function _mineHookSalt() internal view returns (bytes32 salt) {
        console.log("Mining hook address with required flags:", HOOK_FLAGS);
        
        // Prepare creation code with constructor arguments
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            deployer,
            ChainAddresses.getPythOracle(block.chainid)
        );
        
        // Mine the salt using HookMiner
        address expectedAddress;
        (expectedAddress, salt) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs);
        
        console.log("Salt found:", vm.toString(salt));
        console.log("Expected hook address:", expectedAddress);
        console.log("Address flags match:", uint160(expectedAddress) & HookMiner.FLAG_MASK == HOOK_FLAGS);
        
        return salt;
    }
    
    /// @notice Deploy DetoxHook using CREATE2 with the given salt
    function _deployDetoxHookWithSalt(bytes32 salt) internal returns (DetoxHook) {
        console.log("Deploying with CREATE2...");
        
        // Prepare deployment data
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            deployer,
            ChainAddresses.getPythOracle(block.chainid)
        );
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        
        // The CREATE2 Deployer Proxy expects: salt (32 bytes) + creation code
        bytes memory callData = abi.encodePacked(salt, deploymentData);
        
        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "CREATE2 deployment failed");
        require(returnData.length == 20, "Invalid return data length");
        
        // Extract deployed address from return data
        address deployedAddress = address(bytes20(returnData));
        return DetoxHook(payable(deployedAddress));
    }
    
    /// @notice Validate the deployed DetoxHook
    function _validateHookDeployment() internal view {
        console.log("Validating hook deployment...");
        
        // Check hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        require(permissions.beforeSwap, "beforeSwap permission not set");
        require(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta permission not set");
        
        // Validate hook address has correct flags
        uint160 hookAddress = uint160(address(hook));
        require((hookAddress & HOOK_FLAGS) == HOOK_FLAGS, "Hook address flags incorrect");
        
        console.log("Hook validation passed");
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
        
        // Create pool keys
        poolKey1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING_POOL_1,
            hooks: IHooks(address(hook))
        });
        
        poolKey2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING_POOL_2,
            hooks: IHooks(address(hook))
        });
        
        poolId1 = poolKey1.toId();
        poolId2 = poolKey2.toId();
        
        console.log("Pool 1 Configuration:");
        console.log("  Currency0:", Currency.unwrap(currency0));
        console.log("  Currency1:", Currency.unwrap(currency1));
        console.log("  Fee:", POOL_FEE);
        console.log("  Tick Spacing:", TICK_SPACING_POOL_1);
        console.log("  Target Price: 2500 USDC/ETH");
        
        console.log("Pool 2 Configuration:");
        console.log("  Currency0:", Currency.unwrap(currency0));
        console.log("  Currency1:", Currency.unwrap(currency1));
        console.log("  Fee:", POOL_FEE);
        console.log("  Tick Spacing:", TICK_SPACING_POOL_2);
        console.log("  Target Price: 2600 USDC/ETH");
        
        // Initialize pools
        poolManager.initialize(poolKey1, SQRT_PRICE_2500);
        poolManager.initialize(poolKey2, SQRT_PRICE_2600);
        
        console.log("Pools initialized successfully");
        console.log("Pool 1 ID:", uint256(PoolId.unwrap(poolId1)));
        console.log("Pool 2 ID:", uint256(PoolId.unwrap(poolId2)));
        
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
        modifyLiquidityRouter.modifyLiquidity{value: ethAmount1}(
            poolKey1,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT * 1e12), // Convert USDC to 18 decimals for liquidity
                salt: bytes32(0)
            }),
            ""
        );
        
        // Add liquidity to Pool 2
        modifyLiquidityRouter.modifyLiquidity{value: ethAmount2}(
            poolKey2,
            ModifyLiquidityParams({
                tickLower: -600,
                tickUpper: 600,
                liquidityDelta: int256(LIQUIDITY_USDC_AMOUNT * 1e12), // Convert USDC to 18 decimals for liquidity
                salt: bytes32(0)
            }),
            ""
        );
        
        console.log("Liquidity added successfully to both pools");
        
        emit LiquidityAdded(poolId1, LIQUIDITY_USDC_AMOUNT, ethAmount1);
        emit LiquidityAdded(poolId2, LIQUIDITY_USDC_AMOUNT, ethAmount2);
    }
    
    /// @notice Verify contracts on block explorer
    function _verifyContracts() internal view {
        console.log("=== Step 7: Contract Verification ===");
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
        console.log("Deployer:", deployer);
        console.log("DetoxHook:", address(hook));
        console.log("Hook ETH Balance:", address(hook).balance);
        console.log("");
        
        console.log("Pool 1 (ETH/USDC @ 2500):");
        console.log("  Pool ID:", uint256(PoolId.unwrap(poolId1)));
        console.log("  Tick Spacing:", TICK_SPACING_POOL_1);
        console.log("  Fee:", POOL_FEE);
        
        console.log("Pool 2 (ETH/USDC @ 2600):");
        console.log("  Pool ID:", uint256(PoolId.unwrap(poolId2)));
        console.log("  Tick Spacing:", TICK_SPACING_POOL_2);
        console.log("  Fee:", POOL_FEE);
        console.log("");
        
        console.log("Block Explorer Links:");
        string memory explorerBase = ChainAddresses.getBlockExplorer(block.chainid);
        console.log("Hook Contract:", string.concat(explorerBase, "/address/", vm.toString(address(hook))));
        console.log("");
        
        console.log("[COPY THIS ADDRESS FOR YOUR RECORDS]:");
        console.log("DetoxHook:", address(hook));
        console.log("");
        
        console.log("Next Steps:");
        console.log("1. Verify the contract on block explorer");
        console.log("2. Test swaps on both pools");
        console.log("3. Monitor hook arbitrage capture");
        console.log("4. Add more liquidity as needed");
    }
    
    /// @notice Check if we're running on a forked environment
    function _isForkedEnvironment() internal view returns (bool) {
        // Simple heuristic: if we're on a known testnet but block number is very high,
        // we're likely on a fork
        if (block.chainid == ChainAddresses.ARBITRUM_SEPOLIA) {
            return block.number > 50000000; // Arbitrum Sepolia unlikely to have this many blocks
        }
        return false;
    }
    
    /// @notice Emergency function to recover ETH (only for testing)
    function emergencyWithdraw() external {
        require(msg.sender == deployer, "Only deployer");
        require(isForked || block.chainid == ChainAddresses.LOCAL_ANVIL, "Only on test networks");
        
        payable(deployer).transfer(address(this).balance);
    }
    
    /// @notice Receive function to accept ETH
    receive() external payable {}
} 