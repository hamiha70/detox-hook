// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { DetoxHook } from "../src/DetoxHook.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

/// @title DetoxHookDeployScript
/// @notice Deployment script for DetoxHook with proper address mining
/// @dev Handles CREATE2 deployment to ensure hook address has correct permission flags
contract DeployDetoxHook is Script {
    using ChainAddresses for uint256;
    
    // Hook flags for DetoxHook (beforeSwap + beforeSwapReturnDelta)
    uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    
    // CREATE2 Deployer Proxy address (same across all chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Events for deployment tracking
    event DetoxHookDeployed(address indexed hook, address indexed poolManager, uint256 chainId, bytes32 salt);
    event DeploymentValidated(address indexed hook, bool beforeSwap, bool beforeSwapReturnDelta);
    event SaltMined(bytes32 salt, address expectedAddress, uint160 flags);

    /// @notice Main deployment function
    function run() external virtual {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        address poolManager = getPoolManagerAddress();
        DetoxHook hook = deployDetoxHook(poolManager);
        
        vm.stopBroadcast();
        
        console.log("=== Deployment Complete ===");
        console.log("DetoxHook deployed at:", address(hook));
        console.log("Chain ID:", block.chainid);
        console.log("Pool Manager:", poolManager);
        console.log("Block Explorer:", ChainAddresses.getBlockExplorer(block.chainid));
    }

    /// @notice Deploy DetoxHook with address mining and comprehensive logging
    /// @param poolManager The Pool Manager address to use
    /// @return hook The deployed DetoxHook instance
    function deployDetoxHook(address poolManager) public returns (DetoxHook hook) {
        require(poolManager != address(0), "Pool Manager address cannot be zero");

        console.log("=== DetoxHook Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Pool Manager:", poolManager);
        console.log("Deployer:", msg.sender);

        // Validate chain addresses before deployment
        if (block.chainid != ChainAddresses.LOCAL_ANVIL) {
            ChainAddresses.validateChainAddresses(block.chainid);
        }

        // Mine the correct salt for hook address
        bytes32 salt = mineHookSalt(poolManager);

        // Deploy the hook using CREATE2
        hook = deployDetoxHookWithSalt(poolManager, salt);

        // Validate deployment
        validateDeployment(hook);

        // Log final details
        logDeploymentSummary(hook);

        return hook;
    }

    /// @notice Deploy DetoxHook using a specific salt (for deterministic deployment)
    /// @param poolManager The Pool Manager address to use
    /// @param salt The salt for CREATE2 deployment
    /// @return hook The deployed DetoxHook instance
    function deployDetoxHookDeterministic(address poolManager, bytes32 salt) public returns (DetoxHook hook) {
        require(poolManager != address(0), "Pool Manager address cannot be zero");

        console.log("=== DetoxHook Deterministic Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Pool Manager:", poolManager);
        console.log("Salt:", vm.toString(salt));
        console.log("Deployer:", msg.sender);

        // Validate chain addresses before deployment
        if (block.chainid != ChainAddresses.LOCAL_ANVIL) {
            ChainAddresses.validateChainAddresses(block.chainid);
        }

        // Deploy the hook using CREATE2
        hook = deployDetoxHookWithSalt(poolManager, salt);

        // Validate deployment
        validateDeployment(hook);

        // Log final details
        logDeploymentSummary(hook);

        return hook;
    }

    /// @notice Mine the correct salt for DetoxHook deployment
    /// @param poolManager The Pool Manager address to use
    /// @return salt The mined salt that produces a valid hook address
    function mineHookSalt(address poolManager) public returns (bytes32 salt) {
        console.log("=== Mining Hook Address ===");
        console.log("Required flags:", HOOK_FLAGS);
        console.log("Mining for address with correct flag bits...");

        // Add randomness to break deterministic pattern
        uint256 nonce = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, block.number))) % 10000;
        console.log("Using random nonce for uniqueness:", nonce);

        // Prepare creation code with constructor arguments
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManager), msg.sender, address(0));
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);

        // Manual mining with randomness
        uint256 attempts = 0;
        uint256 maxAttempts = 100000;
        
        while (attempts < maxAttempts) {
            // Create a unique salt using nonce and attempt number
            bytes32 candidateSalt = keccak256(abi.encodePacked("DetoxHook", nonce, attempts, block.timestamp));
            
            // Compute the address that would be deployed
            address candidateAddress = HookMiner.computeAddress(CREATE2_DEPLOYER, uint256(candidateSalt), deploymentData);
            
            // Check if this address has the correct flags
            uint160 addressFlags = uint160(candidateAddress) & HookMiner.FLAG_MASK;
            
            if (addressFlags == HOOK_FLAGS) {
                salt = candidateSalt;
                console.log("Salt found after", attempts + 1, "attempts");
                console.log("Salt found:", vm.toString(salt));
                console.log("Expected hook address:", candidateAddress);
                console.log("Address flags match:", true);
                
                emit SaltMined(salt, candidateAddress, HOOK_FLAGS);
                return salt;
            }
            
            attempts++;
        }
        
        revert("Failed to find valid salt after maximum attempts");
    }

    /// @notice Deploy DetoxHook using CREATE2 with the given salt
    /// @param poolManager The Pool Manager address to use
    /// @param salt The salt for CREATE2 deployment
    /// @return hook The deployed DetoxHook instance
    function deployDetoxHookWithSalt(address poolManager, bytes32 salt) public returns (DetoxHook hook) {
        console.log("=== CREATE2 Deployment ===");

        // Calculate expected address
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManager), msg.sender, address(0));
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        address expectedAddress = HookMiner.computeAddress(CREATE2_DEPLOYER, uint256(salt), creationCodeWithArgs);

        console.log("Expected address:", expectedAddress);
        console.log("Using CREATE2 Deployer:", CREATE2_DEPLOYER);

        // Deploy using CREATE2 Deployer Proxy
        hook = deployWithCreate2Proxy(poolManager, salt);

        require(address(hook) == expectedAddress, "Deployment address mismatch");
        console.log("DetoxHook deployed at:", address(hook));

        // Emit deployment event
        emit DetoxHookDeployed(address(hook), poolManager, block.chainid, salt);

        return hook;
    }

    /// @notice Deploy contract using CREATE2 Deployer Proxy
    /// @param poolManager The Pool Manager address to use
    /// @param salt The salt for CREATE2 deployment
    /// @return hook The deployed DetoxHook instance
    function deployWithCreate2Proxy(address poolManager, bytes32 salt) public returns (DetoxHook hook) {
        // Prepare deployment data
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManager), msg.sender, address(0));
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);

        // The CREATE2 Deployer Proxy expects: salt (32 bytes) + creation code
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "CREATE2 deployment failed");

        // Extract deployed address from return data
        // The CREATE2 Deployer returns 20 bytes (raw address), not ABI-encoded
        require(returnData.length == 20, "Invalid return data length");
        address deployedAddress = address(bytes20(returnData));
        hook = DetoxHook(payable(deployedAddress));

        return hook;
    }

    /// @notice Validate the deployed DetoxHook
    /// @param hook The deployed DetoxHook instance
    function validateDeployment(DetoxHook hook) public {
        console.log("=== Deployment Validation ===");

        // Check hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        console.log("Hook permissions:");
        console.log("  beforeSwap:", permissions.beforeSwap);
        console.log("  beforeSwapReturnDelta:", permissions.beforeSwapReturnDelta);

        // Validate required permissions
        require(permissions.beforeSwap, "beforeSwap permission not set");
        require(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta permission not set");

        // Validate hook address flags
        uint160 addressFlags = uint160(address(hook)) & HookMiner.FLAG_MASK;
        console.log("Hook address flags:", addressFlags);
        console.log("Required flags:", HOOK_FLAGS);
        require(addressFlags == HOOK_FLAGS, "Hook address flags do not match required flags");

        // Check contract state
        console.log("Contract validation:");
        console.log("  Pool Manager:", address(hook.poolManager()));

        emit DeploymentValidated(address(hook), permissions.beforeSwap, permissions.beforeSwapReturnDelta);
        console.log("+ Deployment validation passed");
    }

    /// @notice Log deployment summary
    /// @param hook The deployed DetoxHook instance
    function logDeploymentSummary(DetoxHook hook) public view {
        console.log("=== Deployment Summary ===");
        console.log("Contract Address:", address(hook));
        console.log("Chain:", ChainAddresses.getChainName(block.chainid));
        console.log("Block Explorer:", ChainAddresses.getBlockExplorer(block.chainid));
        console.log("Pool Manager:", address(hook.poolManager()));
        console.log("Hook Flags:", uint160(address(hook)) & HookMiner.FLAG_MASK);
        
        // Log additional chain info for non-local chains
        if (block.chainid != ChainAddresses.LOCAL_ANVIL) {
            console.log("Pyth Oracle:", ChainAddresses.getPythOracle(block.chainid));
            console.log("USDC Token:", ChainAddresses.getUSDC(block.chainid));
            console.log("Universal Router:", ChainAddresses.getUniversalRouter(block.chainid));
        }
        
        console.log("=== Deployment Complete ===");
    }

    /// @notice Get the Pool Manager address for the current chain
    /// @return The Pool Manager address
    function getPoolManagerAddress() public view returns (address) {
        return ChainAddresses.getPoolManager(block.chainid);
    }

    /// @notice Set Pool Manager address for a specific chain (only for testing)
    /// @param chainId The chain ID
    /// @param poolManager The Pool Manager address
    function setPoolManagerAddress(uint256 chainId, address poolManager) external view {
        require(msg.sender == tx.origin, "Only EOA can set addresses");
        require(chainId == ChainAddresses.LOCAL_ANVIL, "Can only set address for local testing");
        
        // This is a workaround for local testing since we can't modify the library
        console.log("Note: For local testing, deploy PoolManager first and update ChainAddresses.sol");
        console.log("Pool Manager for chain", chainId, "should be:", poolManager);
    }

    /// @notice Generate a deterministic salt for CREATE2 deployment
    /// @param deployer The deployer address
    /// @param nonce Additional nonce for uniqueness
    /// @return The generated salt
    function generateSalt(address deployer, uint256 nonce) public view returns (bytes32) {
        return keccak256(abi.encodePacked(deployer, block.chainid, nonce, "DetoxHook"));
    }

    /// @notice Compute the address that would be deployed with a given salt
    /// @param poolManager The Pool Manager address
    /// @param salt The deployment salt
    /// @return The computed address
    function computeHookAddress(address poolManager, bytes32 salt) public view returns (address) {
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManager), msg.sender, address(0));
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);
        
        return HookMiner.computeAddress(CREATE2_DEPLOYER, uint256(salt), creationCodeWithArgs);
    }

    /// @notice Check if the current chain is supported
    /// @dev Reverts if the chain is not supported
    function requireSupportedChain() public view {
        require(ChainAddresses.isChainSupported(block.chainid), "Unsupported chain");
    }

    /// @notice Get all V4 addresses for the current chain
    /// @return addresses Struct containing all V4 contract addresses
    function getAllV4Addresses() public view returns (ChainAddresses.V4Addresses memory) {
        return ChainAddresses.getAllAddresses(block.chainid);
    }
} 