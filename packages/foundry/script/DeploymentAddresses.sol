// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

/// @title DeploymentAddresses
/// @notice Stores and retrieves deployment addresses for DetoxHook and related contracts
/// @dev Uses JSON files to store addresses per chain
contract DeploymentAddresses is Script {
    using ChainAddresses for uint256;

    // Deployment address keys
    bytes32 constant DETOX_HOOK_KEY = keccak256("DETOX_HOOK");
    bytes32 constant SWAP_ROUTER_FIXED_KEY = keccak256("SWAP_ROUTER_FIXED");
    bytes32 constant POOL_1_KEY = keccak256("POOL_1");
    bytes32 constant POOL_2_KEY = keccak256("POOL_2");

    // JSON file path for each chain
    string constant ADDRESSES_FILE_PREFIX = "deployments/";
    string constant ADDRESSES_FILE_SUFFIX = "_addresses.json";

    /// @notice Store a deployment address
    /// @param key The key for the address (e.g., DETOX_HOOK_KEY)
    /// @param addr The deployed contract address
    function storeAddress(bytes32 key, address addr) internal {
        require(addr != address(0), "Cannot store zero address");
        
        // Get chain-specific file path
        string memory filePath = _getAddressFilePath();
        
        // Load existing addresses
        string memory json = vm.readFile(filePath);
        bytes memory parsed = vm.parseJson(json);
        
        // Update address
        vm.writeJson(vm.toString(addr), filePath, vm.toString(key));
        
        // Log for verification
        console.log("Stored address for", vm.toString(key));
        console.log("Address:", addr);
        console.log("Chain:", block.chainid);
    }

    /// @notice Retrieve a deployment address
    /// @param key The key for the address
    /// @return addr The stored contract address
    function getAddress(bytes32 key) internal view returns (address addr) {
        string memory filePath = _getAddressFilePath();
        
        // Read from JSON file
        try vm.readFile(filePath) returns (string memory json) {
            bytes memory parsed = vm.parseJson(json);
            string memory addrStr = abi.decode(parsed, (string));
            addr = _parseAddress(addrStr);
        } catch {
            return address(0);
        }
    }

    /// @notice Get the file path for the current chain's addresses
    function _getAddressFilePath() internal view returns (string memory) {
        return string.concat(
            ADDRESSES_FILE_PREFIX,
            vm.toString(block.chainid),
            ADDRESSES_FILE_SUFFIX
        );
    }

    /// @notice Parse address from string
    function _parseAddress(string memory addrStr) internal pure returns (address) {
        bytes memory strBytes = bytes(addrStr);
        bytes memory addr = new bytes(20);
        
        for (uint i = 0; i < 20; i++) {
            addr[i] = strBytes[i + 2]; // Skip "0x" prefix
        }
        
        return address(uint160(uint256(bytes32(addr))));
    }

    /// @notice Check if all required addresses are set
    /// @return allSet True if all required addresses are set
    function checkRequiredAddresses() internal view returns (bool allSet) {
        address hook = getAddress(DETOX_HOOK_KEY);
        address router = getAddress(SWAP_ROUTER_FIXED_KEY);
        address pool1 = getAddress(POOL_1_KEY);
        address pool2 = getAddress(POOL_2_KEY);

        allSet = hook != address(0) && 
                 router != address(0) && 
                 pool1 != address(0) && 
                 pool2 != address(0);
    }
} 