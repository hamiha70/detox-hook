// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { HookMiner } from "@v4-periphery/src/utils/HookMiner.sol";

/**
 * @title HookMinerWithSeed
 * @notice Wrapper around HookMiner that adds seed functionality for flexible redeployment
 * @dev Allows deterministic address generation with configurable starting points
 * 
 * Use Cases:
 * - Seed 0: First deployment attempt
 * - Seed 1: Redeploy after fixing dependencies  
 * - Seed N: Multiple versions or environments
 * 
 * Benefits:
 * - Deterministic per seed (same inputs + seed = same address)
 * - Flexible redeployment (different seeds = different addresses)
 * - Address prediction (can compute offline for any seed)
 * - Clean recovery (broken deploy? Use seed+1)
 */
library HookMinerWithSeed {
    
    /// @notice Maximum iterations per seed to prevent infinite loops
    uint256 public constant MAX_LOOP_PER_SEED = 100000;
    
    /// @notice Error thrown when no valid salt is found for the given seed
    error NoSaltFoundForSeed(uint256 seed);
    
    /**
     * @notice Find a valid salt starting from a specific seed
     * @param deployer Address of the CREATE2 deployer
     * @param flags Required hook permission flags
     * @param creationCode Contract creation bytecode
     * @param constructorArgs ABI-encoded constructor arguments
     * @param seed Starting seed for salt search (deterministic offset)
     * @return hookAddress The computed hook address with correct flags
     * @return salt The salt that produces the correct address
     * @return actualSeed The seed used (for verification)
     */
    function findWithSeed(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256 seed
    ) external pure returns (address hookAddress, bytes32 salt, uint256 actualSeed) {
        
        // Search for valid salt starting from seed
        for (uint256 i = 0; i < MAX_LOOP_PER_SEED; i++) {
            uint256 candidateSalt = seed + i;
            
            // Compute address for this salt (HookMiner.computeAddress expects uint256)
            hookAddress = HookMiner.computeAddress(
                deployer, 
                candidateSalt, 
                abi.encodePacked(creationCode, constructorArgs)
            );
            
            // Check if this address has the required permission flags
            if (uint160(hookAddress) & HookMiner.FLAG_MASK == flags) {
                return (hookAddress, bytes32(candidateSalt), candidateSalt);
            }
        }
        
        // No valid salt found within the search range
        revert NoSaltFoundForSeed(seed);
    }
    
    /**
     * @notice Compute hook address for a specific seed and salt offset
     * @param deployer Address of the CREATE2 deployer
     * @param creationCode Contract creation bytecode
     * @param constructorArgs ABI-encoded constructor arguments
     * @param seed Base seed value
     * @param offset Offset from seed (actualSalt = seed + offset)
     * @return hookAddress The computed hook address
     * @return salt The actual salt used (seed + offset)
     */
    function computeAddressWithSeed(
        address deployer,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256 seed,
        uint256 offset
    ) external pure returns (address hookAddress, bytes32 salt) {
        uint256 actualSalt = seed + offset;
        
        hookAddress = HookMiner.computeAddress(
            deployer,
            actualSalt,
            abi.encodePacked(creationCode, constructorArgs)
        );
        
        salt = bytes32(actualSalt);
    }
    
    /**
     * @notice Batch find multiple addresses for different seeds
     * @param deployer Address of the CREATE2 deployer
     * @param flags Required hook permission flags
     * @param creationCode Contract creation bytecode
     * @param constructorArgs ABI-encoded constructor arguments
     * @param seeds Array of seeds to search
     * @return results Array of results for each seed
     */
    function batchFindWithSeeds(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256[] memory seeds
    ) external pure returns (SeedResult[] memory results) {
        results = new SeedResult[](seeds.length);
        
        for (uint256 i = 0; i < seeds.length; i++) {
            // Use internal function to avoid "this" call issues
            (bool found, address hookAddress, bytes32 salt, uint256 actualSeed) = 
                _findWithSeedInternal(deployer, flags, creationCode, constructorArgs, seeds[i]);
            
            results[i] = SeedResult({
                seed: seeds[i],
                found: found,
                hookAddress: hookAddress,
                salt: salt,
                actualSeed: actualSeed
            });
        }
    }
    
    /**
     * @notice Internal function to find salt with seed (returns success flag instead of reverting)
     * @param deployer Address of the CREATE2 deployer
     * @param flags Required hook permission flags
     * @param creationCode Contract creation bytecode
     * @param constructorArgs ABI-encoded constructor arguments
     * @param seed Starting seed for salt search
     * @return found Whether a valid salt was found
     * @return hookAddress The computed hook address (if found)
     * @return salt The salt that produces the address (if found)
     * @return actualSeed The actual seed used (if found)
     */
    function _findWithSeedInternal(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs,
        uint256 seed
    ) internal pure returns (bool found, address hookAddress, bytes32 salt, uint256 actualSeed) {
        
        // Search for valid salt starting from seed
        for (uint256 i = 0; i < MAX_LOOP_PER_SEED; i++) {
            uint256 candidateSalt = seed + i;
            
            // Compute address for this salt
            address candidateAddress = HookMiner.computeAddress(
                deployer, 
                candidateSalt, 
                abi.encodePacked(creationCode, constructorArgs)
            );
            
            // Check if this address has the required permission flags
            if (uint160(candidateAddress) & HookMiner.FLAG_MASK == flags) {
                return (true, candidateAddress, bytes32(candidateSalt), candidateSalt);
            }
        }
        
        // No valid salt found within the search range
        return (false, address(0), bytes32(0), 0);
    }
    
    /**
     * @notice Result structure for batch operations
     */
    struct SeedResult {
        uint256 seed;           // Input seed
        bool found;             // Whether a valid salt was found
        address hookAddress;    // Computed hook address (if found)
        bytes32 salt;           // Salt that produces the address (if found)
        uint256 actualSeed;     // Actual seed used (seed + offset)
    }
    
    /**
     * @notice Validate that an address has the required flags
     * @param hookAddress Address to validate
     * @param requiredFlags Required permission flags
     * @return valid Whether the address has the required flags
     */
    function validateFlags(address hookAddress, uint160 requiredFlags) external pure returns (bool valid) {
        return (uint160(hookAddress) & HookMiner.FLAG_MASK) == requiredFlags;
    }
    
    /**
     * @notice Get the flags from a hook address
     * @param hookAddress Hook address to analyze
     * @return flags The permission flags encoded in the address
     */
    function getAddressFlags(address hookAddress) external pure returns (uint160 flags) {
        return uint160(hookAddress) & HookMiner.FLAG_MASK;
    }
} 