// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PublicRPCURL
/// @notice Single source of truth for public RPC URLs with failover support
/// @dev This library provides functions to get RPC URLs based on chain ID
/// @dev WARNING: Public RPCs may be rate-limited and cause fork test failures
/// @dev Consider using private RPC providers for reliable testing
library PublicRPCURL {
    // Chain IDs (matching ChainAddresses.sol)
    uint256 public constant ARBITRUM_SEPOLIA = 421614;
    uint256 public constant UNICHAIN_SEPOLIA = 1301;
    uint256 public constant LOCAL_ANVIL = 31337;
    uint256 public constant ARBITRUM_MAINNET = 42161;
    uint256 public constant UNICHAIN_MAINNET = 130;
    uint256 public constant ETHEREUM_MAINNET = 1;
    uint256 public constant ETHEREUM_SEPOLIA = 11155111;

    // Custom errors
    error UnsupportedChain(uint256 chainId);
    error NoRPCAvailable(uint256 chainId);

    /// @notice Get the primary RPC URL for a given chain
    /// @param chainId The chain ID to get the RPC URL for
    /// @return The primary RPC URL
    function getPrimaryRPC(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "https://eth.llamarpc.com";
        if (chainId == ETHEREUM_SEPOLIA) return "https://ethereum-sepolia-rpc.publicnode.com";
        if (chainId == ARBITRUM_MAINNET) return "https://arbitrum.llamarpc.com";
        if (chainId == ARBITRUM_SEPOLIA) return "https://sepolia-rollup.arbitrum.io/rpc";
        if (chainId == UNICHAIN_MAINNET) return "https://rpc.unichain.org";
        if (chainId == UNICHAIN_SEPOLIA) return "https://sepolia.unichain.org";
        if (chainId == LOCAL_ANVIL) return "http://localhost:8545";
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the backup RPC URL for a given chain
    /// @param chainId The chain ID to get the backup RPC URL for
    /// @return The backup RPC URL
    function getBackupRPC(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "https://ethereum.publicnode.com";
        if (chainId == ETHEREUM_SEPOLIA) return "https://rpc.sepolia.org";
        if (chainId == ARBITRUM_MAINNET) return "https://arbitrum.publicnode.com";
        if (chainId == ARBITRUM_SEPOLIA) return "https://arbitrum-sepolia.public.blastapi.io";
        if (chainId == UNICHAIN_MAINNET) return "https://rpc-mainnet.unichain.org";
        if (chainId == UNICHAIN_SEPOLIA) return "https://rpc-sepolia.unichain.org";
        if (chainId == LOCAL_ANVIL) return "http://127.0.0.1:8545";
        revert UnsupportedChain(chainId);
    }

    /// @notice Get all available RPC URLs for a given chain (primary first)
    /// @param chainId The chain ID to get RPC URLs for
    /// @return Array of RPC URLs in priority order
    function getAllRPCs(uint256 chainId) internal pure returns (string[] memory) {
        string[] memory rpcs = new string[](2);
        rpcs[0] = getPrimaryRPC(chainId);
        rpcs[1] = getBackupRPC(chainId);
        return rpcs;
    }

    /// @notice Get the chain name for display purposes
    /// @param chainId The chain ID to get the name for
    /// @return The human-readable chain name
    function getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "Ethereum Mainnet";
        if (chainId == ETHEREUM_SEPOLIA) return "Ethereum Sepolia";
        if (chainId == ARBITRUM_MAINNET) return "Arbitrum One";
        if (chainId == ARBITRUM_SEPOLIA) return "Arbitrum Sepolia";
        if (chainId == UNICHAIN_MAINNET) return "Unichain Mainnet";
        if (chainId == UNICHAIN_SEPOLIA) return "Unichain Sepolia";
        if (chainId == LOCAL_ANVIL) return "Local Anvil";
        revert UnsupportedChain(chainId);
    }

    /// @notice Check if a chain is supported for fork testing
    /// @param chainId The chain ID to check
    /// @return True if the chain is supported
    function isChainSupported(uint256 chainId) internal pure returns (bool) {
        return chainId == ETHEREUM_MAINNET ||
               chainId == ETHEREUM_SEPOLIA ||
               chainId == ARBITRUM_MAINNET ||
               chainId == ARBITRUM_SEPOLIA ||
               chainId == UNICHAIN_MAINNET ||
               chainId == UNICHAIN_SEPOLIA ||
               chainId == LOCAL_ANVIL;
    }

    /// @notice Get environment variable name for custom RPC URL
    /// @param chainId The chain ID to get the env var name for
    /// @return The environment variable name (e.g., "RPC_URL_421614")
    function getEnvVarName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "RPC_URL_1";
        if (chainId == ETHEREUM_SEPOLIA) return "RPC_URL_11155111";
        if (chainId == ARBITRUM_MAINNET) return "RPC_URL_42161";
        if (chainId == ARBITRUM_SEPOLIA) return "RPC_URL_421614";
        if (chainId == UNICHAIN_MAINNET) return "RPC_URL_130";
        if (chainId == UNICHAIN_SEPOLIA) return "RPC_URL_1301";
        if (chainId == LOCAL_ANVIL) return "RPC_URL_31337";
        revert UnsupportedChain(chainId);
    }

    /// @notice Get backup environment variable name for custom RPC URL
    /// @param chainId The chain ID to get the backup env var name for
    /// @return The backup environment variable name (e.g., "RPC_URL_421614_BACKUP")
    function getBackupEnvVarName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_MAINNET) return "RPC_URL_1_BACKUP";
        if (chainId == ETHEREUM_SEPOLIA) return "RPC_URL_11155111_BACKUP";
        if (chainId == ARBITRUM_MAINNET) return "RPC_URL_42161_BACKUP";
        if (chainId == ARBITRUM_SEPOLIA) return "RPC_URL_421614_BACKUP";
        if (chainId == UNICHAIN_MAINNET) return "RPC_URL_130_BACKUP";
        if (chainId == UNICHAIN_SEPOLIA) return "RPC_URL_1301_BACKUP";
        if (chainId == LOCAL_ANVIL) return "RPC_URL_31337_BACKUP";
        revert UnsupportedChain(chainId);
    }

    /// @notice Get comprehensive chain information
    /// @param chainId The chain ID to get information for
    /// @return ChainInfo struct with all relevant details
    function getChainInfo(uint256 chainId) internal pure returns (ChainInfo memory) {
        return ChainInfo({
            chainId: chainId,
            name: getChainName(chainId),
            primaryRPC: getPrimaryRPC(chainId),
            backupRPC: getBackupRPC(chainId),
            envVarName: getEnvVarName(chainId),
            backupEnvVarName: getBackupEnvVarName(chainId),
            isSupported: isChainSupported(chainId)
        });
    }

    /// @notice Struct containing comprehensive chain information
    struct ChainInfo {
        uint256 chainId;
        string name;
        string primaryRPC;
        string backupRPC;
        string envVarName;
        string backupEnvVarName;
        bool isSupported;
    }
} 