// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { DetoxHook } from "../src/DetoxHook.sol";
import { DeployDetoxHook } from "../script/DeployDetoxHook.s.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";
import { ChainAddresses } from "../script/ChainAddresses.sol";

/**
 * @title DeployDetoxHookScript Test
 * @notice Tests the DeployDetoxHook.s.sol script functionality
 * @dev Verifies deployment script works on both forked Arbitrum Sepolia and local Anvil
 * 
 * ## Purpose
 * This test file specifically validates that the DeployDetoxHook.s.sol deployment script
 * works correctly across different environments and scenarios.
 * 
 * ## Test Coverage
 * - ✅ Local Anvil deployment with automatic CREATE2 deployer setup
 * - ✅ Arbitrum Sepolia fork deployment (requires DEPLOYMENT_KEY)
 * - ✅ Salt mining functionality and address validation
 * - ✅ CREATE2 deployer functionality verification
 * - ✅ Full end-to-end deployment workflow
 * - ✅ Error handling and edge cases
 * 
 * ## Usage
 * 
 * ### Run All Tests
 * ```bash
 * forge test --match-contract DeployDetoxHookScriptTest -vv
 * ```
 * 
 * ### Run Specific Tests
 * ```bash
 * # Test local deployment (always works)
 * forge test --match-test test_DeployScriptOnLocalAnvil -vv
 * 
 * # Test fork deployment (requires DEPLOYMENT_KEY)
 * forge test --match-test test_DeployScriptOnArbitrumSepoliaFork -vv
 * 
 * # Debug deployment issues
 * forge test --match-test test_DebugDetoxHookDeployment -vv
 * ```
 * 
 * ## Environment Requirements
 * - Local Anvil: No special requirements (CREATE2 deployer auto-deployed)
 * - Fork Tests: Requires DEPLOYMENT_KEY environment variable and funded account
 * 
 * ## Key Features
 * - Automatic CREATE2 deployer setup for local testing
 * - Comprehensive deployment validation
 * - Environment-specific test handling
 * - Detailed logging and debugging capabilities
 * 
 * ## Critical Fixes Validated
 * - ✅ Constructor argument fix (3 args instead of 1)
 * - ✅ CREATE2 deployer availability on local Anvil
 * - ✅ Address mining with correct permission flags
 * - ✅ Deployment validation and error handling
 */
contract DeployDetoxHookScriptTest is Test {
    using ChainAddresses for uint256;
    
    DeployDetoxHook public deployScript;
    DetoxHook public deployedHook;
    
    // Expected hook flags
    uint160 constant EXPECTED_HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    
    // Test addresses
    address constant ARBITRUM_SEPOLIA_POOL_MANAGER = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant LOCAL_ANVIL_POOL_MANAGER = 0x5FbDB2315678afecb367f032d93F642f64180aa3; // Common Anvil address
    
    function setUp() public {
        deployScript = new DeployDetoxHook();
    }
    
    // ============ Arbitrum Sepolia Fork Tests ============
    
    function test_DeployScriptOnArbitrumSepoliaFork() public {
        // Fork Arbitrum Sepolia
        uint256 forkId = vm.createFork("https://sepolia-rollup.arbitrum.io/rpc");
        vm.selectFork(forkId);
        
        console.log("=== Testing DeployDetoxHook Script on Arbitrum Sepolia Fork ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        
        // Verify we're on the right network
        assertEq(block.chainid, 421614, "Should be on Arbitrum Sepolia");
        
        // Verify PoolManager exists
        require(ARBITRUM_SEPOLIA_POOL_MANAGER.code.length > 0, "PoolManager should exist on Arbitrum Sepolia");
        
        // Fund the deployer for testing
        address deployer = address(deployScript);
        vm.deal(deployer, 1 ether);
        console.log("Funded deployer with 1 ETH for testing");
        
        // Test the deployment script
        deployedHook = deployScript.deployDetoxHook(ARBITRUM_SEPOLIA_POOL_MANAGER);
        
        // Verify deployment success
        _verifyDeployment(deployedHook, ARBITRUM_SEPOLIA_POOL_MANAGER, "Arbitrum Sepolia Fork");
    }
    
    function test_DeployScriptDeterministicOnArbitrumSepoliaFork() public {
        // Skip if DEPLOYMENT_KEY is not set (common in CI/testing environments)
        try vm.envUint("DEPLOYMENT_KEY") returns (uint256) {
            // DEPLOYMENT_KEY is set, proceed with test
        } catch {
            console.log("DEPLOYMENT_KEY not set, skipping Arbitrum Sepolia deterministic fork test");
            return;
        }
        
        // Fork Arbitrum Sepolia
        uint256 forkId = vm.createFork("https://sepolia-rollup.arbitrum.io/rpc");
        vm.selectFork(forkId);
        
        console.log("=== Testing Deterministic Deployment on Arbitrum Sepolia Fork ===");
        
        // Fund the deployer for testing
        address deployer = address(deployScript);
        vm.deal(deployer, 1 ether);
        console.log("Funded deployer with 1 ETH for testing");
        
        // Mine a salt first
        bytes32 salt = deployScript.mineHookSalt(ARBITRUM_SEPOLIA_POOL_MANAGER);
        
        // Deploy using the deterministic function
        deployedHook = deployScript.deployDetoxHookDeterministic(ARBITRUM_SEPOLIA_POOL_MANAGER, salt);
        
        // Verify deployment success
        _verifyDeployment(deployedHook, ARBITRUM_SEPOLIA_POOL_MANAGER, "Arbitrum Sepolia Fork (Deterministic)");
        
        // Verify the address matches what we computed
        address computedAddress = deployScript.computeHookAddress(ARBITRUM_SEPOLIA_POOL_MANAGER, salt);
        assertEq(address(deployedHook), computedAddress, "Deployed address should match computed address");
    }
    
    // ============ Local Anvil Tests ============
    
    function test_DeployScriptOnLocalAnvil() public {
        console.log("=== Testing DeployDetoxHook Script on Local Anvil ===");
        console.log("Chain ID:", block.chainid);
        
        // Deploy CREATE2 deployer if it doesn't exist on local Anvil
        _ensureCreate2DeployerExists();
        
        // Deploy a mock PoolManager for local testing
        MockPoolManager mockPoolManager = new MockPoolManager();
        address poolManagerAddress = address(mockPoolManager);
        
        console.log("Mock PoolManager deployed at:", poolManagerAddress);
        
        // Test the deployment script
        deployedHook = deployScript.deployDetoxHook(poolManagerAddress);
        
        // Verify deployment success
        _verifyDeployment(deployedHook, poolManagerAddress, "Local Anvil");
    }
    
    function test_DeployScriptWithSaltMiningOnLocalAnvil() public {
        console.log("=== Testing Salt Mining on Local Anvil ===");
        
        // Deploy CREATE2 deployer if it doesn't exist on local Anvil
        _ensureCreate2DeployerExists();
        
        // Deploy a mock PoolManager
        MockPoolManager mockPoolManager = new MockPoolManager();
        address poolManagerAddress = address(mockPoolManager);
        
        // Test salt mining
        bytes32 salt = deployScript.mineHookSalt(poolManagerAddress);
        
        console.log("Mined salt:", vm.toString(salt));
        
        // Verify the salt produces a valid address
        address computedAddress = deployScript.computeHookAddress(poolManagerAddress, salt);
        uint160 addressFlags = uint160(computedAddress) & HookMiner.FLAG_MASK;
        
        assertEq(addressFlags, EXPECTED_HOOK_FLAGS, "Mined salt should produce address with correct flags");
        
        // Deploy using the mined salt
        deployedHook = deployScript.deployDetoxHookWithSalt(poolManagerAddress, salt);
        
        // Verify the deployment matches the computed address
        assertEq(address(deployedHook), computedAddress, "Deployed address should match computed address");
        
        _verifyDeployment(deployedHook, poolManagerAddress, "Local Anvil (Salt Mining)");
    }
    
    // ============ Script Function Tests ============
    
    function test_ScriptHelperFunctions() public {
        console.log("=== Testing Script Helper Functions ===");
        
        // Test salt generation
        bytes32 salt1 = deployScript.generateSalt(address(this), 1);
        bytes32 salt2 = deployScript.generateSalt(address(this), 2);
        
        assertTrue(salt1 != salt2, "Different nonces should produce different salts");
        
        // Test address computation
        MockPoolManager mockPoolManager = new MockPoolManager();
        address poolManagerAddress = address(mockPoolManager);
        
        address computed1 = deployScript.computeHookAddress(poolManagerAddress, salt1);
        address computed2 = deployScript.computeHookAddress(poolManagerAddress, salt2);
        
        assertTrue(computed1 != computed2, "Different salts should produce different addresses");
        
        console.log("Salt 1:", vm.toString(salt1));
        console.log("Salt 2:", vm.toString(salt2));
        console.log("Computed Address 1:", computed1);
        console.log("Computed Address 2:", computed2);
    }
    
    function test_ScriptChainValidation() public {
        console.log("=== Testing Chain Validation ===");
        
        // Test supported chain check
        if (ChainAddresses.isChainSupported(block.chainid)) {
            console.log("Current chain is supported:", block.chainid);
            
            // Should not revert
            deployScript.requireSupportedChain();
            
            // Test getting addresses
            ChainAddresses.V4Addresses memory addresses = deployScript.getAllV4Addresses();
            console.log("PoolManager from addresses:", addresses.poolManager);
        } else {
            console.log("Current chain is not supported:", block.chainid);
            
            // Should revert for unsupported chains
            vm.expectRevert("Unsupported chain");
            deployScript.requireSupportedChain();
        }
    }
    
    // ============ Error Handling Tests ============
    
    function test_DeploymentWithZeroPoolManager() public {
        console.log("=== Testing Deployment with Zero PoolManager ===");
        
        // Should revert with zero address
        vm.expectRevert("Pool Manager address cannot be zero");
        deployScript.deployDetoxHook(address(0));
    }
    
    function test_DeploymentValidationFailure() public {
        console.log("=== Testing Deployment Validation ===");
        
        // Deploy CREATE2 deployer if it doesn't exist on local Anvil
        _ensureCreate2DeployerExists();
        
        MockPoolManager mockPoolManager = new MockPoolManager();
        address poolManagerAddress = address(mockPoolManager);
        
        // Deploy a hook
        DetoxHook hook = deployScript.deployDetoxHook(poolManagerAddress);
        
        // Validation should pass for properly deployed hook
        deployScript.validateDeployment(hook);
        
        console.log("Deployment validation passed for properly deployed hook");
    }
    
    // ============ Integration Tests ============
    
    function test_FullDeploymentWorkflow() public {
        console.log("=== Testing Full Deployment Workflow ===");
        
        // Deploy CREATE2 deployer if it doesn't exist on local Anvil
        _ensureCreate2DeployerExists();
        
        MockPoolManager mockPoolManager = new MockPoolManager();
        address poolManagerAddress = address(mockPoolManager);
        
        // Step 1: Mine salt
        bytes32 salt = deployScript.mineHookSalt(poolManagerAddress);
        console.log("Step 1: Salt mined");
        
        // Step 2: Compute expected address
        address expectedAddress = deployScript.computeHookAddress(poolManagerAddress, salt);
        console.log("Step 2: Expected address computed:", expectedAddress);
        
        // Step 3: Deploy with salt
        DetoxHook hook = deployScript.deployDetoxHookWithSalt(poolManagerAddress, salt);
        console.log("Step 3: Hook deployed at:", address(hook));
        
        // Step 4: Validate deployment
        deployScript.validateDeployment(hook);
        console.log("Step 4: Deployment validated");
        
        // Step 5: Verify everything matches
        assertEq(address(hook), expectedAddress, "Final address should match expected");
        
        _verifyDeployment(hook, poolManagerAddress, "Full Workflow");
        
        console.log("=== Full Deployment Workflow Completed Successfully ===");
    }
    
    function test_Create2DeployerWorks() public {
        console.log("=== Testing CREATE2 Deployer Functionality ===");
        
        // Deploy CREATE2 deployer if it doesn't exist
        _ensureCreate2DeployerExists();
        
        // Test deploying a simple contract using the CREATE2 deployer
        bytes memory simpleContractBytecode = hex"6080604052348015600f57600080fd5b50603f80601d6000396000f3fe6080604052600080fdfea264697066735822122000000000000000000000000000000000000000000000000000000000000000000064736f6c63430008130033";
        bytes32 testSalt = bytes32(uint256(1));
        
        // Prepare call data for CREATE2 deployer
        bytes memory callData = abi.encodePacked(testSalt, simpleContractBytecode);
        
        console.log("Calling CREATE2 deployer with test contract...");
        
        // Call the CREATE2 deployer
        (bool success, bytes memory returnData) = address(0x4e59b44847b379578588920cA78FbF26c0B4956C).call(callData);
        
        if (success) {
            console.log("CREATE2 deployer call succeeded");
            console.log("Return data length:", returnData.length);
            if (returnData.length == 20) {
                address deployedAddress = address(bytes20(returnData));
                console.log("Deployed contract at:", deployedAddress);
                
                // Verify the contract was deployed
                uint256 codeSize;
                assembly {
                    codeSize := extcodesize(deployedAddress)
                }
                console.log("Deployed contract code size:", codeSize);
                assertTrue(codeSize > 0, "Contract should have been deployed");
            }
        } else {
            console.log("CREATE2 deployer call failed");
            console.log("Return data:", vm.toString(returnData));
        }
        
        assertTrue(success, "CREATE2 deployer should work");
    }
    
    function test_DebugDetoxHookDeployment() public {
        console.log("=== Debugging DetoxHook Deployment ===");
        
        // Deploy CREATE2 deployer if it doesn't exist
        _ensureCreate2DeployerExists();
        
        // Deploy a mock PoolManager
        MockPoolManager mockPoolManager = new MockPoolManager();
        address poolManagerAddress = address(mockPoolManager);
        
        console.log("Mock PoolManager deployed at:", poolManagerAddress);
        
        // Get DetoxHook creation code and constructor args
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManagerAddress), address(this), address(0));
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        
        console.log("Creation code length:", creationCode.length);
        console.log("Constructor args length:", constructorArgs.length);
        console.log("Total deployment data length:", deploymentData.length);
        
        // Check if deployment data is too large
        if (deploymentData.length > 24576) { // EIP-170 contract size limit
            console.log("WARNING: Deployment data exceeds EIP-170 limit");
        }
        
        // Try to deploy using CREATE2 deployer
        bytes32 testSalt = bytes32(uint256(1));
        bytes memory callData = abi.encodePacked(testSalt, deploymentData);
        
        console.log("Call data length:", callData.length);
        console.log("Attempting CREATE2 deployment...");
        
        // Call the CREATE2 deployer
        (bool success, bytes memory returnData) = address(0x4e59b44847b379578588920cA78FbF26c0B4956C).call(callData);
        
        console.log("CREATE2 call success:", success);
        console.log("Return data length:", returnData.length);
        
        if (!success) {
            console.log("CREATE2 call failed");
            if (returnData.length > 0) {
                console.log("Error data:", vm.toString(returnData));
                // Try to decode the error
                if (returnData.length >= 4) {
                    bytes4 errorSelector = bytes4(returnData);
                    console.log("Error selector:", vm.toString(errorSelector));
                }
            }
        } else {
            console.log("CREATE2 call succeeded");
            if (returnData.length == 20) {
                address deployedAddress = address(bytes20(returnData));
                console.log("Deployed DetoxHook at:", deployedAddress);
                
                // Verify the contract was deployed
                uint256 codeSize;
                assembly {
                    codeSize := extcodesize(deployedAddress)
                }
                console.log("Deployed contract code size:", codeSize);
                
                if (codeSize > 0) {
                    console.log("DetoxHook deployment successful!");
                    
                    // Try to call a function on the deployed contract
                    DetoxHook localDeployedHook = DetoxHook(payable(deployedAddress));
                    try localDeployedHook.poolManager() returns (IPoolManager pm) {
                        console.log("Contract is functional, poolManager:", address(pm));
                    } catch {
                        console.log("Contract deployed but not functional");
                    }
                }
            }
        }
    }
    
    // ============ Helper Functions ============
    
    function _verifyDeployment(DetoxHook hook, address expectedPoolManager, string memory testName) internal view {
        console.log("=== Verifying Deployment:", testName, "===");
        
        // Verify hook exists
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(hook)
        }
        assertGt(codeSize, 0, "Hook should have code");
        
        // Verify pool manager connection
        assertEq(address(hook.poolManager()), expectedPoolManager, "Hook should be connected to correct PoolManager");
        
        // Verify hook permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap, "beforeSwap should be enabled");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be enabled");
        
        // Verify address flags
        uint160 addressFlags = uint160(address(hook)) & HookMiner.FLAG_MASK;
        assertEq(addressFlags, EXPECTED_HOOK_FLAGS, "Hook address should have correct permission flags");
        
        console.log("[SUCCESS] Hook deployed successfully at:", address(hook));
        console.log("[SUCCESS] Code size:", codeSize);
        console.log("[SUCCESS] PoolManager:", address(hook.poolManager()));
        console.log("[SUCCESS] Address flags:", addressFlags);
        console.log("[SUCCESS] beforeSwap:", permissions.beforeSwap);
        console.log("[SUCCESS] beforeSwapReturnDelta:", permissions.beforeSwapReturnDelta);
        console.log("=== Verification Complete ===");
    }

    /// @notice Ensure CREATE2 deployer exists on local Anvil
    function _ensureCreate2DeployerExists() internal {
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        
        // Check if CREATE2 deployer already exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(create2Deployer)
        }
        
        if (codeSize > 0) {
            console.log("CREATE2 deployer already exists at:", create2Deployer);
            return;
        }
        
        console.log("Deploying CREATE2 deployer to local Anvil...");
        
        // Deploy the CREATE2 deployer using the standard deployment method
        // This is the bytecode for the deterministic deployment proxy
        bytes memory deployerBytecode = hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
        
        // Use vm.etch to deploy the CREATE2 deployer at the expected address
        vm.etch(create2Deployer, deployerBytecode);
        
        console.log("CREATE2 deployer deployed at:", create2Deployer);
        
        // Verify deployment
        assembly {
            codeSize := extcodesize(create2Deployer)
        }
        require(codeSize > 0, "Failed to deploy CREATE2 deployer");
    }
}

/**
 * @title Mock PoolManager for Testing
 * @notice Simple mock to test deployment script locally
 */
contract MockPoolManager {
    // Simple mock that just exists for testing
    function mockFunction() external pure returns (bool) {
        return true;
    }
} 