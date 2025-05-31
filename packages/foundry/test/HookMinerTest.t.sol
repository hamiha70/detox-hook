// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DetoxHook} from "../src/DetoxHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@v4-periphery/src/utils/HookMiner.sol";

/**
 * @title HookMinerTest
 * @notice Test to verify HookMiner functionality and integration
 */
contract HookMinerTest is Test {
    // CREATE2 Deployer Proxy (universal across all chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Hook permission flags
    uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
    
    // Mock pool manager for testing
    address constant MOCK_POOL_MANAGER = 0x1234567890123456789012345678901234567890;
    
    function test_HookMinerFindsSalt() public view {
        console.log("=== Testing HookMiner.find() ===");
        console.log("Required flags:", HOOK_FLAGS);
        console.log("CREATE2 Deployer:", CREATE2_DEPLOYER);
        
        // Prepare creation code and constructor arguments
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(MOCK_POOL_MANAGER));
        
        console.log("Creation code length:", creationCode.length);
        console.log("Constructor args length:", constructorArgs.length);
        
        // Mine the salt using HookMiner
        (address expectedAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, 
            HOOK_FLAGS, 
            creationCode, 
            constructorArgs
        );
        
        console.log("=== HookMiner Results ===");
        console.log("Salt found:", uint256(salt));
        console.log("Expected hook address:", expectedAddress);
        console.log("Address flags:", uint160(expectedAddress) & HookMiner.FLAG_MASK);
        console.log("Required flags:", HOOK_FLAGS);
        console.log("Flags match:", (uint160(expectedAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS);
        
        // Verify the address has correct flags
        assertTrue((uint160(expectedAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS, "Address flags should match required flags");
        
        // Verify salt is reasonable (not too high)
        assertTrue(uint256(salt) < HookMiner.MAX_LOOP, "Salt should be within reasonable range");
        
        console.log("HookMiner test passed!");
    }
    
    function test_HookMinerComputeAddress() public pure {
        console.log("=== Testing HookMiner.computeAddress() ===");
        
        // Use a known salt for testing
        uint256 testSalt = 12345;
        
        // Prepare creation code with constructor arguments
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(MOCK_POOL_MANAGER));
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);
        
        // Compute address
        address computedAddress = HookMiner.computeAddress(
            CREATE2_DEPLOYER,
            testSalt,
            creationCodeWithArgs
        );
        
        console.log("Test salt:", testSalt);
        console.log("Computed address:", computedAddress);
        console.log("Address flags:", uint160(computedAddress) & HookMiner.FLAG_MASK);
        
        // Verify address is not zero
        assertTrue(computedAddress != address(0), "Computed address should not be zero");
        
        console.log("HookMiner.computeAddress() test passed!");
    }
    
    function test_HookMinerConsistency() public view {
        console.log("=== Testing HookMiner Consistency ===");
        
        // Prepare creation code and constructor arguments
        bytes memory creationCode = type(DetoxHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(MOCK_POOL_MANAGER));
        
        // Find salt using HookMiner
        (address expectedAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, 
            HOOK_FLAGS, 
            creationCode, 
            constructorArgs
        );
        
        // Compute address using the found salt
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);
        address computedAddress = HookMiner.computeAddress(
            CREATE2_DEPLOYER,
            uint256(salt),
            creationCodeWithArgs
        );
        
        console.log("Expected address (from find):", expectedAddress);
        console.log("Computed address (from computeAddress):", computedAddress);
        console.log("Addresses match:", expectedAddress == computedAddress);
        
        // Verify consistency
        assertEq(expectedAddress, computedAddress, "find() and computeAddress() should return same address");
        
        console.log("HookMiner consistency test passed!");
    }
    
    function test_HookMinerFlagMask() public pure {
        console.log("=== Testing HookMiner FLAG_MASK ===");
        console.log("HookMiner.FLAG_MASK:", HookMiner.FLAG_MASK);
        console.log("Hooks.ALL_HOOK_MASK:", Hooks.ALL_HOOK_MASK);
        console.log("BEFORE_SWAP_FLAG:", Hooks.BEFORE_SWAP_FLAG);
        console.log("BEFORE_SWAP_RETURNS_DELTA_FLAG:", Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        console.log("Combined flags:", HOOK_FLAGS);
        
        // Verify FLAG_MASK matches ALL_HOOK_MASK
        assertEq(HookMiner.FLAG_MASK, Hooks.ALL_HOOK_MASK, "FLAG_MASK should match ALL_HOOK_MASK");
        
        // Verify our flags are within the mask
        assertTrue((HOOK_FLAGS & HookMiner.FLAG_MASK) == HOOK_FLAGS, "Our flags should be within FLAG_MASK");
        
        console.log("HookMiner FLAG_MASK test passed!");
    }
} 