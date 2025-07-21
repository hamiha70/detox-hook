// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { DetoxHookV2 } from "../src/DetoxHookV2.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";
import { ChainAddresses } from "./ChainAddresses.sol";
import { Create2Deployer } from "../src/test-helpers/Create2Deployer.sol";

/**
 * @title DeployDetoxHookV2
 * @notice Production deployment script for DetoxHookV2 using proven patterns
 * @dev Uses CREATE2 deployment with HookMiner for deterministic addresses
 */
contract DeployDetoxHookV2 is Script {
    using ChainAddresses for uint256;
    
    // Hook flags for DetoxHookV2 (beforeSwap + beforeSwapReturnDelta)
    uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    
    // CREATE2 Deployer Proxy address (same across all chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Events for deployment tracking
    event DetoxHookV2Deployed(
        address indexed hook, 
        address indexed poolManager, 
        address indexed priceRegistry, 
        address oracle,
        uint256 chainId, 
        bytes32 salt
    );
    event PriceRegistryDeployed(address indexed priceRegistry, uint256 chainId);
    event DeploymentValidated(address indexed hook, bool beforeSwap, bool beforeSwapReturnDelta);
    event SaltMined(bytes32 salt, address expectedAddress, uint160 flags);

    // Deployment configuration
    struct DeploymentConfig {
        address poolManager;
        address priceRegistry;
        address pythOracle;
        address owner;
        bool deployNewRegistry;
        bool validateOnly;
    }

    /// @notice Main deployment function
    function run() external virtual {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== DETOX HOOK V2 DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Get deployment configuration
        DeploymentConfig memory config = getDeploymentConfig(deployer);
        
        // Deploy or get existing PriceRegistry
        if (config.deployNewRegistry) {
            config.priceRegistry = address(deployPriceRegistry(config.owner));
        }
        
        // Deploy DetoxHookV2
        DetoxHookV2 hook = deployDetoxHookV2(config);
        
        // Validate deployment
        validateDeployment(hook, config);
        
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("DetoxHookV2:", address(hook));
        console.log("PoolManager:", config.poolManager);
        console.log("PriceRegistry:", config.priceRegistry);
        console.log("Oracle:", config.pythOracle);
        console.log("Owner:", config.owner);
        console.log("Chain ID:", block.chainid);
        
        vm.stopBroadcast();
    }

    /// @notice Get deployment configuration for the current chain
    /// @param deployer The deployer address
    /// @return config The deployment configuration
    function getDeploymentConfig(address deployer) public view returns (DeploymentConfig memory config) {
        config.poolManager = ChainAddresses.getPoolManager(block.chainid);
        config.pythOracle = ChainAddresses.getPythOracle(block.chainid);
        config.owner = deployer;
        config.deployNewRegistry = true; // Always deploy new registry for V2
        config.validateOnly = false;
        
        // Check for existing PriceRegistry deployment
        try vm.envAddress("PRICE_REGISTRY_ADDRESS") returns (address existingRegistry) {
            config.priceRegistry = existingRegistry;
            config.deployNewRegistry = false;
            console.log("Using existing PriceRegistry:", existingRegistry);
        } catch {
            console.log("Will deploy new PriceRegistry");
        }
        
        require(config.poolManager != address(0), "PoolManager not found for chain");
        require(config.pythOracle != address(0), "Pyth Oracle not found for chain");
    }

    /// @notice Deploy PriceRegistry
    /// @param owner The owner of the PriceRegistry
    /// @return priceRegistry The deployed PriceRegistry instance
    function deployPriceRegistry(address owner) public returns (PriceRegistry priceRegistry) {
        console.log("=== Deploying PriceRegistry ===");
        
        priceRegistry = new PriceRegistry(owner);
        
        console.log("PriceRegistry deployed at:", address(priceRegistry));
        console.log("PriceRegistry owner:", priceRegistry.owner());
        
        emit PriceRegistryDeployed(address(priceRegistry), block.chainid);
        
        return priceRegistry;
    }

    /// @notice Deploy DetoxHookV2 using CREATE2
    /// @param config The deployment configuration
    /// @return hook The deployed DetoxHookV2 instance
    function deployDetoxHookV2(DeploymentConfig memory config) public returns (DetoxHookV2 hook) {
        console.log("=== Deploying DetoxHookV2 with CREATE2 ===");
        console.log("Required flags:", HOOK_FLAGS);
        
        // Check if CREATE2 deployer exists, deploy if needed (for local testing)
        if (CREATE2_DEPLOYER.code.length == 0) {
            console.log("CREATE2 deployer not found, deploying for testing...");
            Create2Deployer testDeployer = new Create2Deployer();
            return deployDetoxHookV2WithDeployer(config, address(testDeployer));
        } else {
            return deployDetoxHookV2WithDeployer(config, CREATE2_DEPLOYER);
        }
    }

    /// @notice Deploy DetoxHookV2 using specific CREATE2 deployer
    /// @param config The deployment configuration
    /// @param deployer The CREATE2 deployer address
    /// @return hook The deployed DetoxHookV2 instance
    function deployDetoxHookV2WithDeployer(DeploymentConfig memory config, address deployer) internal returns (DetoxHookV2 hook) {
        // Prepare creation code and constructor arguments
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            IPoolManager(config.poolManager),
            config.owner,
            config.pythOracle,
            config.priceRegistry
        );
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        console.log("Constructor arguments:");
        console.log("  Pool Manager:", config.poolManager);
        console.log("  Owner:", config.owner);
        console.log("  Oracle:", config.pythOracle);
        console.log("  Price Registry:", config.priceRegistry);
        
        // Mine the salt using HookMiner
        address expectedAddress;
        bytes32 salt;
        (expectedAddress, salt) = HookMiner.find(deployer, HOOK_FLAGS, creationCode, constructorArgs);
        
        console.log("=== HookMiner Results ===");
        console.log("Salt found:", uint256(salt));
        console.log("Expected hook address:", expectedAddress);
        console.log("Address flags:", uint160(expectedAddress) & HookMiner.FLAG_MASK);
        console.log("Required flags:", HOOK_FLAGS);
        console.log("Flags match:", (uint160(expectedAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        emit SaltMined(salt, expectedAddress, HOOK_FLAGS);
        
        // Deploy using CREATE2
        console.log("=== Deploying with CREATE2 ===");
        address deployedAddress;
        
        if (deployer == CREATE2_DEPLOYER) {
            // Use the standard CREATE2 deployer
            (bool success,) = deployer.call(
                abi.encodePacked(salt, bytecode)
            );
            require(success, "CREATE2 deployment failed");
            deployedAddress = expectedAddress;
        } else {
            // Use our test Create2Deployer
            Create2Deployer testDeployer = Create2Deployer(deployer);
            deployedAddress = testDeployer.deploy(salt, bytecode);
        }
        
        // Create the hook instance
        hook = DetoxHookV2(payable(deployedAddress));
        
        console.log("=== DetoxHookV2 Deployed Successfully ===");
        console.log("Hook address:", address(hook));
        console.log("Hook permissions valid:", (uint160(address(hook)) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        emit DetoxHookV2Deployed(
            address(hook), 
            config.poolManager, 
            config.priceRegistry,
            config.pythOracle,
            block.chainid, 
            salt
        );
        
        return hook;
    }

    /// @notice Validate the deployed hook
    /// @param hook The deployed hook
    /// @param config The deployment configuration
    function validateDeployment(DetoxHookV2 hook, DeploymentConfig memory config) public {
        console.log("=== Validating Deployment ===");
        
        // Verify hook functionality
        require(address(hook.poolManager()) == config.poolManager, "Hook not connected to manager");
        require(address(hook.priceRegistry()) == config.priceRegistry, "Hook not connected to price registry");
        require(address(hook.pythOracle()) == config.pythOracle, "Hook not connected to oracle");
        require(hook.owner() == config.owner, "Hook owner not set correctly");
        
        // Verify hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        require(permissions.beforeSwap, "beforeSwap permission not set");
        require(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta permission not set");
        
        // Verify address has correct flags
        require((uint160(address(hook)) & HookMiner.FLAG_MASK) == HOOK_FLAGS, "Hook address flags invalid");
        
        emit DeploymentValidated(address(hook), permissions.beforeSwap, permissions.beforeSwapReturnDelta);
        
        console.log("[SUCCESS] All deployment validations passed");
    }

    /// @notice Test function to validate deployment configuration
    function testDeploymentConfig() external view {
        console.log("=== Testing Deployment Configuration ===");
        
        address testDeployer = address(0x1234567890123456789012345678901234567890);
        DeploymentConfig memory config = getDeploymentConfig(testDeployer);
        
        console.log("Pool Manager:", config.poolManager);
        console.log("Oracle:", config.pythOracle);
        console.log("Owner:", config.owner);
        console.log("Deploy new registry:", config.deployNewRegistry);
        
        require(config.poolManager != address(0), "PoolManager configuration invalid");
        require(config.pythOracle != address(0), "Oracle configuration invalid");
        require(config.owner == testDeployer, "Owner configuration invalid");
        
        console.log("[SUCCESS] Deployment configuration valid");
    }
} 