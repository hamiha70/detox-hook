// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title PoolRegistry
/// @notice Registry contract to store and retrieve DetoxHook pool configurations
/// @dev Stores PoolKeys and metadata for easy frontend integration
contract PoolRegistry {
    using PoolIdLibrary for PoolKey;

    struct PoolInfo {
        PoolKey poolKey;
        PoolId poolId;
        string description;
        uint256 targetPrice; // Target price in USDC (e.g., 2500 for 2500 USDC/ETH)
        bool isActive;
        uint256 createdAt;
    }

    // Storage
    mapping(string => PoolInfo) public pools;
    mapping(PoolId => string) public poolIdToName;
    string[] public poolNames;
    
    address public immutable detoxHook;
    address public immutable owner;

    // Events
    event PoolRegistered(string indexed name, PoolId indexed poolId, PoolKey poolKey);
    event PoolStatusUpdated(string indexed name, bool isActive);

    constructor(address _detoxHook, address _owner) {
        detoxHook = _detoxHook;
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /// @notice Register a new pool in the registry
    /// @param name Unique name for the pool (e.g., "pool1", "pool2")
    /// @param poolKey The PoolKey struct for this pool
    /// @param description Human-readable description
    /// @param targetPrice Target price in USDC
    function registerPool(
        string memory name,
        PoolKey memory poolKey,
        string memory description,
        uint256 targetPrice
    ) external onlyOwner {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(address(poolKey.hooks) == detoxHook, "Pool must use DetoxHook");
        require(!pools[name].isActive, "Pool already registered");

        PoolId poolId = poolKey.toId();
        
        pools[name] = PoolInfo({
            poolKey: poolKey,
            poolId: poolId,
            description: description,
            targetPrice: targetPrice,
            isActive: true,
            createdAt: block.timestamp
        });

        poolIdToName[poolId] = name;
        poolNames.push(name);

        emit PoolRegistered(name, poolId, poolKey);
    }

    /// @notice Get pool information by name
    /// @param name Pool name
    /// @return poolInfo Complete pool information
    function getPool(string memory name) external view returns (PoolInfo memory poolInfo) {
        return pools[name];
    }

    /// @notice Get PoolKey by name
    /// @param name Pool name
    /// @return poolKey The PoolKey struct
    function getPoolKey(string memory name) external view returns (PoolKey memory poolKey) {
        return pools[name].poolKey;
    }

    /// @notice Get PoolId by name
    /// @param name Pool name
    /// @return poolId The PoolId
    function getPoolId(string memory name) external view returns (PoolId poolId) {
        return pools[name].poolId;
    }

    /// @notice Get pool name by PoolId
    /// @param poolId The PoolId
    /// @return name Pool name
    function getPoolName(PoolId poolId) external view returns (string memory name) {
        return poolIdToName[poolId];
    }

    /// @notice Get all registered pool names
    /// @return names Array of all pool names
    function getAllPoolNames() external view returns (string[] memory names) {
        return poolNames;
    }

    /// @notice Get all active pools
    /// @return activePoolNames Array of active pool names
    function getActivePools() external view returns (string[] memory activePoolNames) {
        uint256 activeCount = 0;
        
        // Count active pools
        for (uint256 i = 0; i < poolNames.length; i++) {
            if (pools[poolNames[i]].isActive) {
                activeCount++;
            }
        }
        
        // Create array of active pool names
        activePoolNames = new string[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < poolNames.length; i++) {
            if (pools[poolNames[i]].isActive) {
                activePoolNames[index] = poolNames[i];
                index++;
            }
        }
    }

    /// @notice Update pool status
    /// @param name Pool name
    /// @param isActive New status
    function updatePoolStatus(string memory name, bool isActive) external onlyOwner {
        require(bytes(pools[name].description).length > 0, "Pool not found");
        pools[name].isActive = isActive;
        emit PoolStatusUpdated(name, isActive);
    }

    /// @notice Check if a pool exists and is active
    /// @param name Pool name
    /// @return exists Whether the pool exists and is active
    function isPoolActive(string memory name) external view returns (bool exists) {
        return pools[name].isActive;
    }

    /// @notice Get pool count
    /// @return count Total number of registered pools
    function getPoolCount() external view returns (uint256 count) {
        return poolNames.length;
    }

    /// @notice Get DetoxHook address
    /// @return hook DetoxHook address
    function getDetoxHook() external view returns (address hook) {
        return detoxHook;
    }
} 