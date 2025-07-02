// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { DetoxHookV2 } from "../src/DetoxHookV2.sol";
import { HookMinerWithSeed } from "../src/libraries/HookMinerWithSeed.sol";
import { Create2Deployer } from "../src/test-helpers/Create2Deployer.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";

/**
 * @title HookMinerDeterminismTest
 * @notice Test to verify HookMiner produces deterministic results
 * @dev Critical for ensuring reproducible hook deployments
 */
contract HookMinerDeterminismTest is Test {
    // Test constants
    uint160 public constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    /// @notice CREATE2 deployer instance for testing
    Create2Deployer internal create2Deployer;
    
    /// @notice Test that HookMiner produces the same salt for identical inputs
    function test_HookMinerDeterminism() public {
        console.log("=== Testing HookMiner Determinism ===");
        
        // Prepare identical inputs for multiple runs
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234), // manager
            address(0x5678), // priceRegistry  
            address(0x9ABC)  // oracle
        );
        
        console.log("Creation code length:", creationCode.length);
        console.log("Constructor args length:", constructorArgs.length);
        console.log("Required flags:", HOOK_FLAGS);
        
        // Run HookMiner multiple times with identical inputs
        (address addr1, bytes32 salt1) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs);
        (address addr2, bytes32 salt2) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs);
        (address addr3, bytes32 salt3) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs);
        
        console.log("=== Run 1 Results ===");
        console.log("Address:", addr1);
        console.log("Salt:", uint256(salt1));
        console.log("Address flags:", uint160(addr1) & HookMiner.FLAG_MASK);
        
        console.log("=== Run 2 Results ===");
        console.log("Address:", addr2);
        console.log("Salt:", uint256(salt2));
        console.log("Address flags:", uint160(addr2) & HookMiner.FLAG_MASK);
        
        console.log("=== Run 3 Results ===");
        console.log("Address:", addr3);
        console.log("Salt:", uint256(salt3));
        console.log("Address flags:", uint160(addr3) & HookMiner.FLAG_MASK);
        
        // Verify determinism - all results should be identical
        assertEq(addr1, addr2, "Run 1 and 2 should produce same address");
        assertEq(addr2, addr3, "Run 2 and 3 should produce same address");
        assertEq(salt1, salt2, "Run 1 and 2 should produce same salt");
        assertEq(salt2, salt3, "Run 2 and 3 should produce same salt");
        
        // Verify all addresses have correct flags
        assertEq(uint160(addr1) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 1 should have correct flags");
        assertEq(uint160(addr2) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 2 should have correct flags");
        assertEq(uint160(addr3) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 3 should have correct flags");
        
        console.log("[PASS] HookMiner is deterministic - same inputs produce same results");
    }
    
    /// @notice Test that HookMiner produces different salts for different inputs
    function test_HookMinerInputSensitivity() public {
        console.log("=== Testing HookMiner Input Sensitivity ===");
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        
        // Test with different constructor arguments
        bytes memory constructorArgs1 = abi.encode(
            address(0x1234), // manager
            address(0x5678), // priceRegistry  
            address(0x9ABC)  // oracle
        );
        
        bytes memory constructorArgs2 = abi.encode(
            address(0x1234), // manager (same)
            address(0x5678), // priceRegistry (same)
            address(0x9ABD)  // oracle (different - last byte changed)
        );
        
        (address addr1, bytes32 salt1) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs1);
        (address addr2, bytes32 salt2) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs2);
        
        console.log("=== Input Set 1 ===");
        console.log("Oracle address: 0x9ABC");
        console.log("Address:", addr1);
        console.log("Salt:", uint256(salt1));
        
        console.log("=== Input Set 2 ===");
        console.log("Oracle address: 0x9ABD");
        console.log("Address:", addr2);
        console.log("Salt:", uint256(salt2));
        
        // Different inputs should produce different results
        assertTrue(addr1 != addr2, "Different inputs should produce different addresses");
        assertTrue(salt1 != salt2, "Different inputs should produce different salts");
        
        // But both should still have correct flags
        assertEq(uint160(addr1) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 1 should have correct flags");
        assertEq(uint160(addr2) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 2 should have correct flags");
        
        console.log("[PASS] HookMiner is input-sensitive - different inputs produce different results");
    }
    
    /// @notice Test that HookMiner produces different salts for different flags
    function test_HookMinerFlagSensitivity() public {
        console.log("=== Testing HookMiner Flag Sensitivity ===");
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234), // manager
            address(0x5678), // priceRegistry  
            address(0x9ABC)  // oracle
        );
        
        // Test with different flag combinations
        uint160 flags1 = uint160(Hooks.BEFORE_SWAP_FLAG); // Only beforeSwap
        uint160 flags2 = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG); // Both flags
        
        (address addr1, bytes32 salt1) = HookMiner.find(CREATE2_DEPLOYER, flags1, creationCode, constructorArgs);
        (address addr2, bytes32 salt2) = HookMiner.find(CREATE2_DEPLOYER, flags2, creationCode, constructorArgs);
        
        console.log("=== Flags Set 1 (beforeSwap only) ===");
        console.log("Flags:", flags1);
        console.log("Address:", addr1);
        console.log("Salt:", uint256(salt1));
        console.log("Address flags:", uint160(addr1) & HookMiner.FLAG_MASK);
        
        console.log("=== Flags Set 2 (beforeSwap + returnsDelta) ===");
        console.log("Flags:", flags2);
        console.log("Address:", addr2);
        console.log("Salt:", uint256(salt2));
        console.log("Address flags:", uint160(addr2) & HookMiner.FLAG_MASK);
        
        // Different flags should produce different results
        assertTrue(addr1 != addr2, "Different flags should produce different addresses");
        assertTrue(salt1 != salt2, "Different flags should produce different salts");
        
        // Each should have their respective correct flags
        assertEq(uint160(addr1) & HookMiner.FLAG_MASK, flags1, "Address 1 should have flags1");
        assertEq(uint160(addr2) & HookMiner.FLAG_MASK, flags2, "Address 2 should have flags2");
        
        console.log("[PASS] HookMiner is flag-sensitive - different flags produce different results");
    }
    
    /// @notice Test HookMiner performance and salt range
    function test_HookMinerPerformance() public {
        console.log("=== Testing HookMiner Performance ===");
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234),
            address(0x5678), 
            address(0x9ABC)
        );
        
        uint256 gasBefore = gasleft();
        (address addr, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("=== Performance Results ===");
        console.log("Gas used:", gasUsed);
        console.log("Salt found:", uint256(salt));
        console.log("Iterations needed:", uint256(salt) + 1); // Salt starts from 0
        console.log("Address:", addr);
        console.log("Address flags:", uint160(addr) & HookMiner.FLAG_MASK);
        
        // Verify the result is correct
        assertEq(uint160(addr) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Should find address with correct flags");
        assertTrue(uint256(salt) < HookMiner.MAX_LOOP, "Salt should be within MAX_LOOP");
        
        console.log("[PASS] HookMiner performance test completed");
    }
    
    /// @notice Test that HookMiner fails gracefully when no salt is found
    function test_HookMinerFailure() public {
        console.log("=== Testing HookMiner Failure Handling ===");
        
        // Use impossible flags that can't be satisfied
        uint160 impossibleFlags = type(uint160).max; // All bits set - impossible to achieve
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234),
            address(0x5678), 
            address(0x9ABC)
        );
        
        console.log("Attempting to find salt for impossible flags:", impossibleFlags);
        
        // This should revert with "HookMiner: could not find salt"
        vm.expectRevert();
        HookMiner.find(CREATE2_DEPLOYER, impossibleFlags, creationCode, constructorArgs);
        
        console.log("[PASS] HookMiner correctly fails for impossible flags");
    }
    
    /// @notice Test HookMinerWithSeed determinism for same seed
    function test_HookMinerWithSeedDeterminism() public {
        console.log("=== Testing HookMinerWithSeed Determinism ===");
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234),
            address(0x5678), 
            address(0x9ABC),
            address(0xDEF0)
        );
        
        uint256 seed = 1000; // Test with seed 1000
        
        // Run multiple times with same seed
        (address addr1, bytes32 salt1, uint256 actualSeed1) = HookMinerWithSeed.findWithSeed(
            CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs, seed
        );
        (address addr2, bytes32 salt2, uint256 actualSeed2) = HookMinerWithSeed.findWithSeed(
            CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs, seed
        );
        
        console.log("=== Seed Determinism Results ===");
        console.log("Seed:", seed);
        console.log("Run 1 - Address:", addr1);
        console.log("Run 1 - Salt:", uint256(salt1));
        console.log("Run 1 - Actual seed:", actualSeed1);
        console.log("Run 2 - Address:", addr2);
        console.log("Run 2 - Salt:", uint256(salt2));
        console.log("Run 2 - Actual seed:", actualSeed2);
        
        // Verify determinism
        assertEq(addr1, addr2, "Same seed should produce same address");
        assertEq(salt1, salt2, "Same seed should produce same salt");
        assertEq(actualSeed1, actualSeed2, "Same seed should produce same actual seed");
        
        // Verify flags
        assertEq(uint160(addr1) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address should have correct flags");
        
        console.log("[PASS] HookMinerWithSeed is deterministic for same seed");
    }
    
    /// @notice Test HookMinerWithSeed produces different results for different seeds
    function test_HookMinerWithSeedVariation() public {
        console.log("=== Testing HookMinerWithSeed Seed Variation ===");
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234),
            address(0x5678), 
            address(0x9ABC),
            address(0xDEF0)
        );
        
        // Test different seeds
        uint256 seed1 = 0;
        uint256 seed2 = 1000;
        uint256 seed3 = 50000;
        
        (address addr1, bytes32 salt1, uint256 actualSeed1) = HookMinerWithSeed.findWithSeed(
            CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs, seed1
        );
        (address addr2, bytes32 salt2, uint256 actualSeed2) = HookMinerWithSeed.findWithSeed(
            CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs, seed2
        );
        (address addr3, bytes32 salt3, uint256 actualSeed3) = HookMinerWithSeed.findWithSeed(
            CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs, seed3
        );
        
        console.log("=== Seed Variation Results ===");
        console.log("Seed 0 - Address:", addr1);
        console.log("Seed 0 - Salt:", uint256(salt1));
        console.log("Seed 0 - Actual:", actualSeed1);
        console.log("Seed 1000 - Address:", addr2);
        console.log("Seed 1000 - Salt:", uint256(salt2));
        console.log("Seed 1000 - Actual:", actualSeed2);
        console.log("Seed 50000 - Address:", addr3);
        console.log("Seed 50000 - Salt:", uint256(salt3));
        console.log("Seed 50000 - Actual:", actualSeed3);
        
        // Different seeds should produce different results
        assertTrue(addr1 != addr2, "Seed 0 and 1000 should produce different addresses");
        assertTrue(addr2 != addr3, "Seed 1000 and 50000 should produce different addresses");
        assertTrue(addr1 != addr3, "Seed 0 and 50000 should produce different addresses");
        
        assertTrue(salt1 != salt2, "Seed 0 and 1000 should produce different salts");
        assertTrue(salt2 != salt3, "Seed 1000 and 50000 should produce different salts");
        assertTrue(salt1 != salt3, "Seed 0 and 50000 should produce different salts");
        
        // All should have correct flags
        assertEq(uint160(addr1) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 1 should have correct flags");
        assertEq(uint160(addr2) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 2 should have correct flags");
        assertEq(uint160(addr3) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Address 3 should have correct flags");
        
        console.log("[PASS] HookMinerWithSeed produces different results for different seeds");
    }
    
    /// @notice Test batch seed finding
    function test_HookMinerWithSeedBatch() public {
        console.log("=== Testing HookMinerWithSeed Batch Operations ===");
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234),
            address(0x5678), 
            address(0x9ABC),
            address(0xDEF0)
        );
        
        // Test batch with multiple seeds
        uint256[] memory seeds = new uint256[](3);
        seeds[0] = 0;
        seeds[1] = 1000;
        seeds[2] = 50000;
        
        HookMinerWithSeed.SeedResult[] memory results = HookMinerWithSeed.batchFindWithSeeds(
            CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs, seeds
        );
        
        console.log("=== Batch Results ===");
        for (uint256 i = 0; i < results.length; i++) {
            console.log("Seed:", results[i].seed);
            console.log("Found:", results[i].found);
            console.log("Address:", results[i].hookAddress);
            console.log("Salt:", uint256(results[i].salt));
            console.log("Actual seed:", results[i].actualSeed);
            console.log("---");
        }
        
        // All should be found
        assertTrue(results[0].found, "Seed 0 should be found");
        assertTrue(results[1].found, "Seed 1000 should be found");
        assertTrue(results[2].found, "Seed 50000 should be found");
        
        // All should have correct flags
        assertEq(uint160(results[0].hookAddress) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Result 0 should have correct flags");
        assertEq(uint160(results[1].hookAddress) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Result 1 should have correct flags");
        assertEq(uint160(results[2].hookAddress) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Result 2 should have correct flags");
        
        // All should be different
        assertTrue(results[0].hookAddress != results[1].hookAddress, "Results 0 and 1 should be different");
        assertTrue(results[1].hookAddress != results[2].hookAddress, "Results 1 and 2 should be different");
        assertTrue(results[0].hookAddress != results[2].hookAddress, "Results 0 and 2 should be different");
        
        console.log("[PASS] HookMinerWithSeed batch operations work correctly");
    }
    
    /// @notice Test utility functions
    function test_HookMinerWithSeedUtilities() public {
        console.log("=== Testing HookMinerWithSeed Utility Functions ===");
        
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1234),
            address(0x5678), 
            address(0x9ABC),
            address(0xDEF0)
        );
        
        // Find an address
        (address hookAddress, bytes32 salt, uint256 actualSeed) = HookMinerWithSeed.findWithSeed(
            CREATE2_DEPLOYER, HOOK_FLAGS, creationCode, constructorArgs, 0
        );
        
        // Test validateFlags
        bool valid = HookMinerWithSeed.validateFlags(hookAddress, HOOK_FLAGS);
        assertTrue(valid, "Address should have valid flags");
        
        bool invalid = HookMinerWithSeed.validateFlags(hookAddress, uint160(Hooks.AFTER_SWAP_FLAG));
        assertFalse(invalid, "Address should not have different flags");
        
        // Test getAddressFlags
        uint160 flags = HookMinerWithSeed.getAddressFlags(hookAddress);
        assertEq(flags, HOOK_FLAGS, "Should return correct flags");
        
        // Test computeAddressWithSeed
        uint256 offset = actualSeed; // Use the offset that worked
        (address computedAddress, bytes32 computedSalt) = HookMinerWithSeed.computeAddressWithSeed(
            CREATE2_DEPLOYER, creationCode, constructorArgs, 0, offset
        );
        
        assertEq(computedAddress, hookAddress, "Computed address should match");
        assertEq(computedSalt, salt, "Computed salt should match");
        
        console.log("=== Utility Test Results ===");
        console.log("Hook address:", hookAddress);
        console.log("Flags valid:", valid);
        console.log("Extracted flags:", flags);
        console.log("Computed address matches:", computedAddress == hookAddress);
        
        console.log("[PASS] HookMinerWithSeed utility functions work correctly");
    }
    
    /// @notice Test end-to-end hook deployment using CREATE2
    function test_EndToEndHookDeployment() public {
        console.log("=== Testing End-to-End Hook Deployment ===");
        
        // Deploy our CREATE2 deployer
        create2Deployer = new Create2Deployer();
        console.log("CREATE2 deployer deployed at:", address(create2Deployer));
        
        // Deploy dependencies first
        PriceRegistry priceRegistry = new PriceRegistry(address(this));
        console.log("PriceRegistry deployed at:", address(priceRegistry));
        
        // Mock addresses for manager and oracle
        address mockManager = address(0x1111);
        address mockOracle = address(0x2222);
        
        // Prepare DetoxHookV2 deployment data
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            mockManager,
            address(this), // owner
            mockOracle,
            address(priceRegistry)
        );
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        console.log("=== Finding Hook Address ===");
        console.log("Creation code length:", creationCode.length);
        console.log("Constructor args length:", constructorArgs.length);
        console.log("Total bytecode length:", bytecode.length);
        
        // Find a valid salt using HookMinerWithSeed
        uint256 seed = 0;
        (address predictedAddress, bytes32 salt, uint256 actualSeed) = HookMinerWithSeed.findWithSeed(
            address(create2Deployer), HOOK_FLAGS, creationCode, constructorArgs, seed
        );
        
        console.log("=== Mining Results ===");
        console.log("Predicted address:", predictedAddress);
        console.log("Salt:", uint256(salt));
        console.log("Actual seed used:", actualSeed);
        console.log("Address flags:", uint160(predictedAddress) & HookMiner.FLAG_MASK);
        
        // Verify the predicted address has correct flags
        assertEq(uint160(predictedAddress) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Predicted address should have correct flags");
        
        // Verify no contract exists at predicted address yet
        assertFalse(create2Deployer.contractExists(predictedAddress), "No contract should exist at predicted address yet");
        
        console.log("=== Deploying Hook ===");
        
        // Deploy the hook using our CREATE2 deployer
        address deployedAddress = create2Deployer.deploy(salt, bytecode);
        
        console.log("Hook deployed at:", deployedAddress);
        console.log("Deployment successful:", deployedAddress != address(0));
        
        // Verify deployment
        assertEq(deployedAddress, predictedAddress, "Deployed address should match predicted address");
        assertTrue(create2Deployer.contractExists(deployedAddress), "Contract should exist at deployed address");
        assertTrue(deployedAddress.code.length > 0, "Contract should have code");
        
        // Verify the deployed contract has correct flags
        assertEq(uint160(deployedAddress) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Deployed address should have correct flags");
        
        console.log("=== Testing Hook Functionality ===");
        
        // Cast to DetoxHookV2 and test basic functionality
        DetoxHookV2 deployedHook = DetoxHookV2(payable(deployedAddress));
        
        // Test that we can call view functions
        address hookManager = address(deployedHook.poolManager());
        address hookPriceRegistry = address(deployedHook.priceRegistry());
        address hookOracle = address(deployedHook.pythOracle());
        address hookOwner = deployedHook.owner();
        
        console.log("Hook manager:", hookManager);
        console.log("Hook price registry:", hookPriceRegistry);
        console.log("Hook oracle:", hookOracle);
        console.log("Hook owner:", hookOwner);
        
        // Verify constructor arguments were set correctly
        assertEq(hookManager, mockManager, "Manager should match constructor arg");
        assertEq(hookPriceRegistry, address(priceRegistry), "Price registry should match constructor arg");
        assertEq(hookOracle, mockOracle, "Oracle should match constructor arg");
        assertEq(hookOwner, address(this), "Owner should match constructor arg");
        
        // Test that the hook is functional by checking its permissions
        Hooks.Permissions memory permissions = deployedHook.getHookPermissions();
        assertTrue(permissions.beforeSwap, "Hook should have beforeSwap permission");
        assertTrue(permissions.beforeSwapReturnDelta, "Hook should have beforeSwapReturnDelta permission");
        
        console.log("=== Verification Complete ===");
        console.log("Hook address has correct flags:", uint160(deployedAddress) & HookMiner.FLAG_MASK == HOOK_FLAGS);
        console.log("Hook is callable:", hookManager != address(0));
        console.log("Constructor args verified:", hookPriceRegistry == address(priceRegistry));
        
        console.log("[PASS] End-to-end hook deployment successful");
    }
    
    /// @notice Test that we can redeploy with different seed
    function test_RedeploymentWithDifferentSeed() public {
        console.log("=== Testing Redeployment with Different Seed ===");
        
        // Deploy our CREATE2 deployer
        create2Deployer = new Create2Deployer();
        
        // Deploy dependencies
        PriceRegistry priceRegistry = new PriceRegistry(address(this));
        
        // Mock addresses
        address mockManager = address(0x1111);
        address mockOracle = address(0x2222);
        
        // Prepare deployment data
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            mockManager,
            address(this), // owner
            mockOracle,
            address(priceRegistry)
        );
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        // Deploy first hook with seed 0
        (address addr1, bytes32 salt1,) = HookMinerWithSeed.findWithSeed(
            address(create2Deployer), HOOK_FLAGS, creationCode, constructorArgs, 0
        );
        address deployed1 = create2Deployer.deploy(salt1, bytecode);
        
        console.log("First deployment:");
        console.log("  Address:", deployed1);
        console.log("  Salt:", uint256(salt1));
        
        // Deploy second hook with seed 1000 (simulating redeployment scenario)
        (address addr2, bytes32 salt2,) = HookMinerWithSeed.findWithSeed(
            address(create2Deployer), HOOK_FLAGS, creationCode, constructorArgs, 1000
        );
        address deployed2 = create2Deployer.deploy(salt2, bytecode);
        
        console.log("Second deployment:");
        console.log("  Address:", deployed2);
        console.log("  Salt:", uint256(salt2));
        
        // Verify both deployments
        assertEq(deployed1, addr1, "First deployment should match prediction");
        assertEq(deployed2, addr2, "Second deployment should match prediction");
        assertTrue(deployed1 != deployed2, "Different seeds should produce different addresses");
        assertTrue(salt1 != salt2, "Different seeds should produce different salts");
        
        // Both should have correct flags
        assertEq(uint160(deployed1) & HookMiner.FLAG_MASK, HOOK_FLAGS, "First hook should have correct flags");
        assertEq(uint160(deployed2) & HookMiner.FLAG_MASK, HOOK_FLAGS, "Second hook should have correct flags");
        
        // Both should be functional
        DetoxHookV2 hook1 = DetoxHookV2(payable(deployed1));
        DetoxHookV2 hook2 = DetoxHookV2(payable(deployed2));
        
        assertEq(address(hook1.poolManager()), mockManager, "Hook1 manager should be correct");
        assertEq(address(hook2.poolManager()), mockManager, "Hook2 manager should be correct");
        assertEq(address(hook1.priceRegistry()), address(priceRegistry), "Hook1 price registry should be correct");
        assertEq(address(hook2.priceRegistry()), address(priceRegistry), "Hook2 price registry should be correct");
        
        console.log("[PASS] Redeployment with different seed successful");
    }
    
    /// @notice Test deployment failure when contract already exists
    function test_DeploymentFailureOnDuplicate() public {
        console.log("=== Testing Deployment Failure on Duplicate ===");
        
        // Deploy our CREATE2 deployer
        create2Deployer = new Create2Deployer();
        
        // Deploy dependencies
        PriceRegistry priceRegistry = new PriceRegistry(address(this));
        
        // Prepare deployment data
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(0x1111), // manager
            address(this),    // owner
            address(0x2222),  // oracle
            address(priceRegistry) // price registry
        );
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        // Find salt and deploy first time
        (address predictedAddress, bytes32 salt,) = HookMinerWithSeed.findWithSeed(
            address(create2Deployer), HOOK_FLAGS, creationCode, constructorArgs, 0
        );
        address deployed1 = create2Deployer.deploy(salt, bytecode);
        
        console.log("First deployment successful at:", deployed1);
        assertEq(deployed1, predictedAddress, "First deployment should match prediction");
        
        // Try to deploy again with same salt - should fail
        console.log("Attempting duplicate deployment...");
        vm.expectRevert(
            abi.encodeWithSelector(Create2Deployer.ContractAlreadyExists.selector, predictedAddress)
        );
        create2Deployer.deploy(salt, bytecode);
        
        console.log("[PASS] Duplicate deployment correctly failed");
    }
} 