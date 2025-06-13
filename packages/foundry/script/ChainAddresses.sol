// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ChainAddresses
/// @notice Single source of truth for all chain-specific contract addresses
/// @dev This library provides functions to get contract addresses based on chain ID
library ChainAddresses {
    // Chain IDs
    uint256 public constant ARBITRUM_SEPOLIA = 421614;
    uint256 public constant UNICHAIN_SEPOLIA = 11155111; // Unichain Sepolia
    uint256 public constant LOCAL_ANVIL = 31337;
    uint256 public constant ARBITRUM_MAINNET = 42161;
    uint256 public constant UNICHAIN_MAINNET = 130;

    // Custom errors
    error UnsupportedChain(uint256 chainId);
    error AddressNotSet(uint256 chainId, string contractName);

    /// @notice Get the Uniswap V4 Pool Manager address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Pool Manager address
    function getPoolManager(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
        }
        if (chainId == UNICHAIN_SEPOLIA) {
            return 0x8f75D7147BEb96c4b29204639D8e8e88D9228909; // Unichain Sepolia PoolManager (checksummed)
        }
        if (chainId == UNICHAIN_MAINNET) {
            return 0x1F98400000000000000000000000000000000004; // Unichain Mainnet PoolManager (checksummed)
        }
        if (chainId == ARBITRUM_MAINNET) {
            return 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3; // Arbitrum Mainnet PoolManager (checksummed)
        }
        if (chainId == LOCAL_ANVIL) {
            // For local testing - will be deployed
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Pyth Oracle address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Pyth Oracle address
    function getPythOracle(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // Pyth Oracle on Arbitrum Sepolia
        }
        if (chainId == UNICHAIN_SEPOLIA) {
            return 0x2880aB155794e7179c9eE2e38200202908C17B43; // Pyth Oracle on Unichain Sepolia (checksummed)
        }
        if (chainId == UNICHAIN_MAINNET) {
            return 0x0000000000000000000000000000000000000000; // TODO: Add Pyth Oracle for Unichain Mainnet
        }
        if (chainId == ARBITRUM_MAINNET) {
            return 0x0000000000000000000000000000000000000000; // TODO: Add Pyth Oracle for Arbitrum Mainnet
        }
        if (chainId == LOCAL_ANVIL) {
            // For local testing - will be mocked
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the USDC token address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The USDC token address
    function getUSDC(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // USDC on Arbitrum Sepolia
        }
        if (chainId == UNICHAIN_SEPOLIA) {
            return 0x0000000000000000000000000000000000000000; // TODO: Add USDC for Unichain Sepolia
        }
        if (chainId == UNICHAIN_MAINNET) {
            return 0x0000000000000000000000000000000000000000; // TODO: Add USDC for Unichain Mainnet
        }
        if (chainId == ARBITRUM_MAINNET) {
            return 0x0000000000000000000000000000000000000000; // TODO: Add USDC for Arbitrum Mainnet
        }
        if (chainId == LOCAL_ANVIL) {
            // For local testing - will be deployed or mocked
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the block explorer URL for a given chain
    /// @param chainId The chain ID to get the explorer URL for
    /// @return The block explorer base URL
    function getBlockExplorer(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return "https://arbitrum-sepolia.blockscout.com";
        }
        if (chainId == LOCAL_ANVIL) {
            return "http://localhost:8545"; // Local node
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the RPC URL for a given chain
    /// @param chainId The chain ID to get the RPC URL for
    /// @return The RPC URL
    function getRPCUrl(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return "https://sepolia-rollup.arbitrum.io/rpc";
        }
        if (chainId == LOCAL_ANVIL) {
            return "http://localhost:8545";
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Check if a chain is supported
    /// @param chainId The chain ID to check
    /// @return True if the chain is supported
    function isChainSupported(uint256 chainId) internal pure returns (bool) {
        return chainId == ARBITRUM_SEPOLIA || chainId == LOCAL_ANVIL;
    }

    /// @notice Get a human-readable chain name
    /// @param chainId The chain ID to get the name for
    /// @return The chain name
    function getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ARBITRUM_SEPOLIA) return "Arbitrum Sepolia";
        if (chainId == LOCAL_ANVIL) return "Local Anvil";

        return "Unknown Chain";
    }

    /// @notice Validate that all required addresses are set for a chain
    /// @param chainId The chain ID to validate
    /// @dev Reverts if any required address is not set (address(0))
    function validateChainAddresses(uint256 chainId) internal pure {
        if (!isChainSupported(chainId)) {
            revert UnsupportedChain(chainId);
        }

        // For non-local chains, validate that critical addresses are set
        if (chainId != LOCAL_ANVIL) {
            address poolManager = getPoolManager(chainId);
            address pythOracle = getPythOracle(chainId);
            address usdc = getUSDC(chainId);

            if (poolManager == address(0)) {
                revert AddressNotSet(chainId, "PoolManager");
            }
            if (pythOracle == address(0)) {
                revert AddressNotSet(chainId, "PythOracle");
            }
            if (usdc == address(0)) {
                revert AddressNotSet(chainId, "USDC");
            }
        }
    }

    /// @notice Get the Universal Router address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Universal Router address
    function getUniversalRouter(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0xeFd1D4bD4cf1e86Da286BB4CB1B8BcED9C10BA47;
        }
        if (chainId == UNICHAIN_SEPOLIA) {
            return 0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3; // Unichain Sepolia UniversalRouter (checksummed)
        }
        if (chainId == UNICHAIN_MAINNET) {
            return 0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3; // Unichain Mainnet UniversalRouter (checksummed)
        }
        if (chainId == ARBITRUM_MAINNET) {
            return 0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3; // Arbitrum Mainnet UniversalRouter (checksummed)
        }
        if (chainId == LOCAL_ANVIL) {
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Position Manager address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Position Manager address
    function getPositionManager(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0xAc631556d3d4019C95769033B5E719dD77124BAc;
        }
        if (chainId == LOCAL_ANVIL) {
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the StateView address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The StateView address
    function getStateView(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x9D467FA9062b6e9B1a46E26007aD82db116c67cB;
        }
        if (chainId == LOCAL_ANVIL) {
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Quoter address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Quoter address
    function getQuoter(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x7dE51022d70A725b508085468052E25e22b5c4c9;
        }
        if (chainId == LOCAL_ANVIL) {
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the PoolSwapTest address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The PoolSwapTest address
    function getPoolSwapTest(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7;
        }
        if (chainId == LOCAL_ANVIL) {
            return address(0);
        }
        // TODO: Add PoolSwapTest addresses for Unichain Sepolia, Unichain Mainnet, Arbitrum Mainnet
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the PoolModifyLiquidityTest address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The PoolModifyLiquidityTest address
    function getPoolModifyLiquidityTest(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7;
        }
        if (chainId == LOCAL_ANVIL) {
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Permit2 address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Permit2 address
    function getPermit2(uint256 chainId) internal pure returns (address) {
        if (chainId == ARBITRUM_SEPOLIA) {
            return 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        }
        if (chainId == LOCAL_ANVIL) {
            return address(0);
        }

        revert UnsupportedChain(chainId);
    }

    /// @notice Get all Uniswap V4 contract addresses for a chain
    /// @param chainId The chain ID to get addresses for
    /// @return A struct containing all contract addresses
    function getAllAddresses(uint256 chainId) internal pure returns (V4Addresses memory) {
        return V4Addresses({
            poolManager: getPoolManager(chainId),
            universalRouter: getUniversalRouter(chainId),
            positionManager: getPositionManager(chainId),
            stateView: getStateView(chainId),
            quoter: getQuoter(chainId),
            poolSwapTest: getPoolSwapTest(chainId),
            poolModifyLiquidityTest: getPoolModifyLiquidityTest(chainId),
            permit2: getPermit2(chainId),
            pythOracle: getPythOracle(chainId),
            usdc: getUSDC(chainId)
        });
    }

    /// @notice Struct containing all V4 contract addresses
    struct V4Addresses {
        address poolManager;
        address universalRouter;
        address positionManager;
        address stateView;
        address quoter;
        address poolSwapTest;
        address poolModifyLiquidityTest;
        address permit2;
        address pythOracle;
        address usdc;
    }

    /**
     * @notice Get realistic ETH/USDC sqrtPriceX96 for pool initialization
     * @param usdcPerEth The USDC price per ETH (e.g., 2500 for $2500/ETH)
     * @return sqrtPriceX96 The calculated sqrtPriceX96 value
     */
    function getEthUsdcSqrtPriceX96(uint256 usdcPerEth) internal pure returns (uint160) {
        // Pre-calculated values for common prices
        if (usdcPerEth == 2000) return 3543191098710758062418075085254;
        if (usdcPerEth == 2500) return 3961408125713216879677197516800;
        if (usdcPerEth == 3000) return 4339505120412727436079675601510;
        if (usdcPerEth == 3500) return 4687201239189402080711122156406;

        // For other prices, use approximation: sqrt(usdcPerEth) * 2^96 / 10^6
        // This is a simplified calculation - for production, use the CalculatePoolPrice script
        uint256 sqrtPrice = sqrt(usdcPerEth * 1e12);
        uint256 Q96 = 2 ** 96;
        return uint160((sqrtPrice * Q96) / 1e6);
    }

    /**
     * @notice Get current market ETH/USDC sqrtPriceX96 (approximately $2500/ETH)
     * @return sqrtPriceX96 The current market rate sqrtPriceX96
     */
    function getCurrentEthUsdcSqrtPriceX96() internal pure returns (uint160) {
        return getEthUsdcSqrtPriceX96(2500); // Current approximate market rate
    }

    // Simple integer square root function
    function sqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
} 