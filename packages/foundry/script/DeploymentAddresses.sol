// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

/// @title DeploymentAddresses
/// @notice Stores and retrieves versioned deployment addresses for DetoxHook and related contracts
/// @dev Uses JSON files to store arrays of addresses per contract key, supporting versioning
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

    /// @notice Store a deployment address (appends to the array for the key)
    /// @param key The key for the address (e.g., DETOX_HOOK_KEY)
    /// @param addr The deployed contract address
    function storeAddress(bytes32 key, address addr) internal {
        require(addr != address(0), "Cannot store zero address");
        string memory filePath = _getAddressFilePath();
        string memory keyStr = vm.toString(key);
        string memory addrStr = vm.toString(addr);
        // Read existing array or initialize
        string memory json = "";
        try vm.readFile(filePath) returns (string memory fileJson) {
            json = fileJson;
        } catch {}
        // Append to array
        string memory arrayPath = string.concat(".", keyStr);
        vm.writeJson(addrStr, filePath, arrayPath); // This will append if array exists, or create new array
        console.log("Stored address for", keyStr, "at version", getAllAddresses(key).length - 1);
        console.log("Address:", addr);
        console.log("Chain:", block.chainid);
    }

    /// @notice Retrieve the latest deployment address for a key
    /// @param key The key for the address
    /// @return addr The latest stored contract address
    function getLatestAddress(bytes32 key) internal view returns (address addr) {
        address[] memory all = getAllAddresses(key);
        require(all.length > 0, "No address stored for key");
        return all[all.length - 1];
    }

    /// @notice Retrieve a deployment address by version (index)
    /// @param key The key for the address
    /// @param version The version index (0 = first, N = latest)
    /// @return addr The stored contract address at the given version
    function getAddressByVersion(bytes32 key, uint256 version) internal view returns (address addr) {
        address[] memory all = getAllAddresses(key);
        require(version < all.length, "Version out of range");
        return all[version];
    }

    /// @notice Retrieve all deployment addresses for a key
    /// @param key The key for the address
    /// @return addrs Array of all stored addresses for the key
    function getAllAddresses(bytes32 key) internal view returns (address[] memory addrs) {
        string memory filePath = _getAddressFilePath();
        string memory keyStr = vm.toString(key);
        string memory arrayPath = string.concat(".", keyStr);
        try vm.readFile(filePath) returns (string memory json) {
            bytes memory parsed = vm.parseJson(json, arrayPath);
            addrs = abi.decode(parsed, (address[]));
        } catch {
            addrs = new address[](0);
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

    /// @notice Check if all required addresses are set (latest version)
    /// @return allSet True if all required addresses are set
    function checkRequiredAddresses() internal view returns (bool allSet) {
        bool hookSet = getAllAddresses(DETOX_HOOK_KEY).length > 0;
        bool routerSet = getAllAddresses(SWAP_ROUTER_FIXED_KEY).length > 0;
        bool pool1Set = getAllAddresses(POOL_1_KEY).length > 0;
        bool pool2Set = getAllAddresses(POOL_2_KEY).length > 0;
        allSet = hookSet && routerSet && pool1Set && pool2Set;
    }

    /// @notice Store a PoolId (as hex string) for versioning
    /// @param key The key for the PoolId (e.g., POOL_1_KEY)
    /// @param poolId The PoolId (bytes32)
    function storePoolId(bytes32 key, bytes32 poolId) internal {
        string memory filePath = _getAddressFilePath();
        string memory keyStr = vm.toString(key);
        string memory poolIdStr = vm.toString(poolId);
        string memory arrayPath = string.concat(".", keyStr);
        vm.writeJson(poolIdStr, filePath, arrayPath);
        console.log("Stored PoolId for", keyStr, "at version", getAllPoolIds(key).length - 1);
        console.log("PoolId:", poolIdStr);
        console.log("Chain:", block.chainid);
    }

    /// @notice Retrieve the latest PoolId (as bytes32) for a key
    function getLatestPoolId(bytes32 key) internal view returns (bytes32 poolId) {
        bytes32[] memory all = getAllPoolIds(key);
        require(all.length > 0, "No PoolId stored for key");
        return all[all.length - 1];
    }

    /// @notice Retrieve all PoolIds (as bytes32) for a key
    function getAllPoolIds(bytes32 key) internal view returns (bytes32[] memory poolIds) {
        string memory filePath = _getAddressFilePath();
        string memory keyStr = vm.toString(key);
        string memory arrayPath = string.concat(".", keyStr);
        try vm.readFile(filePath) returns (string memory json) {
            bytes memory parsed = vm.parseJson(json, arrayPath);
            string[] memory hexStrings = abi.decode(parsed, (string[]));
            poolIds = new bytes32[](hexStrings.length);
            for (uint i = 0; i < hexStrings.length; i++) {
                poolIds[i] = _hexStringToBytes32(hexStrings[i]);
            }
        } catch {
            poolIds = new bytes32[](0);
        }
    }

    /// @notice Convert a hex string (0x...) to bytes32
    function _hexStringToBytes32(string memory s) internal pure returns (bytes32 result) {
        bytes memory ss = bytes(s);
        require(ss.length == 66, "hex string must be 32 bytes (0x...)");
        for (uint i = 2; i < 66; i += 2) {
            result |= bytes32(uint256(uint8(_fromHexChar(uint8(ss[i]))) * 16 + uint8(_fromHexChar(uint8(ss[i + 1])))) << (8 * (31 - (i - 2) / 2)));
        }
    }
    function _fromHexChar(uint8 c) private pure returns (uint8) {
        if (bytes1(c) >= "0" && bytes1(c) <= "9") {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= "a" && bytes1(c) <= "f") {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= "A" && bytes1(c) <= "F") {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("Invalid hex char");
    }

    /// --- PoolKey versioned storage ---
    /// @notice Store a PoolKey (as ABI-encoded bytes) for versioning
    /// @param key The key for the PoolKey (e.g., POOL_1_KEY)
    /// @param poolKeyEncoded The ABI-encoded PoolKey struct
    function storePoolKey(bytes32 key, bytes memory poolKeyEncoded) internal {
        string memory filePath = _getAddressFilePath();
        string memory keyStr = vm.toString(key);
        string memory encodedStr = vm.toString(poolKeyEncoded);
        string memory arrayPath = string.concat(".", keyStr, "_POOLKEY");
        vm.writeJson(encodedStr, filePath, arrayPath);
        console.log("Stored PoolKey for", keyStr, "at version", getAllPoolKeys(key).length - 1);
        console.log("PoolKey (ABI-encoded):", encodedStr);
        console.log("Chain:", block.chainid);
    }

    /// @notice Retrieve the latest PoolKey (as bytes) for a key
    /// @param key The key for the PoolKey
    /// @return poolKeyEncoded The latest ABI-encoded PoolKey
    function getLatestPoolKey(bytes32 key) internal view returns (bytes memory poolKeyEncoded) {
        bytes[] memory all = getAllPoolKeys(key);
        require(all.length > 0, "No PoolKey stored for key");
        return all[all.length - 1];
    }

    /// @notice Retrieve all PoolKeys (as bytes) for a key
    /// @param key The key for the PoolKey
    /// @return poolKeys Array of all ABI-encoded PoolKeys
    function getAllPoolKeys(bytes32 key) internal view returns (bytes[] memory poolKeys) {
        string memory filePath = _getAddressFilePath();
        string memory keyStr = vm.toString(key);
        string memory arrayPath = string.concat(".", keyStr, "_POOLKEY");
        try vm.readFile(filePath) returns (string memory json) {
            bytes memory parsed = vm.parseJson(json, arrayPath);
            string[] memory encodedStrings = abi.decode(parsed, (string[]));
            poolKeys = new bytes[](encodedStrings.length);
            for (uint i = 0; i < encodedStrings.length; i++) {
                poolKeys[i] = bytes(encodedStrings[i]);
            }
        } catch {
            poolKeys = new bytes[](0);
        }
    }
} 