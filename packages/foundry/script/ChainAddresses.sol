// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ChainAddresses
/// @notice Single source of truth for all chain-specific contract addresses
/// @dev This library provides functions to get contract addresses based on chain ID
// Chain ID reference: https://chainlist.org/
// USDC reference: https://developers.circle.com/stablecoins/usdc-contract-addresses
// Uniswap V4 reference: https://docs.uniswap.org/contracts/v4/deployments
// Pyth Oracle reference: https://docs.pyth.network/price-feeds/contract-addresses/evm 
// Note: In references, Ethereum Sepolia is called Sepolia.
library ChainAddresses {
    // Chain IDs
    uint256 public constant ARBITRUM_SEPOLIA = 421614;
    uint256 public constant UNICHAIN_SEPOLIA = 1301; // Unichain Sepolia (corrected)
    uint256 public constant LOCAL_ANVIL = 31337;
    uint256 public constant ARBITRUM_MAINNET = 42161;
    uint256 public constant UNICHAIN_MAINNET = 130; // Unichain Mainnet (corrected)
    uint256 public constant ETHEREUM_MAINNET = 1;
    uint256 public constant ETHEREUM_SEPOLIA = 11155111;

    // Custom errors
    error UnsupportedChain(uint256 chainId);
    error AddressNotSet(uint256 chainId, string contractName);

    /// @notice Get the Uniswap V4 Pool Manager address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Pool Manager address
    function getPoolManager(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET) return 0x000000000004444c5dc75cB358380D2e3dE08A90; // Mainnet
        if (chainId == ETHEREUM_SEPOLIA) return 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543; // Sepolia
        if (chainId == ARBITRUM_MAINNET) return 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32; // Arbitrum One
        if (chainId == ARBITRUM_SEPOLIA) return 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317; // Arbitrum Sepolia
        if (chainId == UNICHAIN_MAINNET) return 0x1F98400000000000000000000000000000000004; // Unichain
        if (chainId == UNICHAIN_SEPOLIA) return 0x00B036B58a818B1BC34d502D3fE730Db729e62AC; // Unichain Sepolia
        if (chainId == LOCAL_ANVIL) return address(0);
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Pyth Oracle address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Pyth Oracle address
    function getPythOracle(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET) return 0x4305FB66699C3B2702D4d05CF36551390A4c69C6; // Pyth Ethereum Mainnet
        if (chainId == ARBITRUM_MAINNET) return 0xFF1a0F4744e8582dF1ac0Ebd03a41FcFA6b6e8b8; // Pyth Arbitrum Mainnet
        if (chainId == UNICHAIN_MAINNET) return 0x2880aB155794e7179c9eE2e38200202908C17B43; // Pyth Unichain Mainnet
        if (chainId == ARBITRUM_SEPOLIA) return 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF; // Pyth Arbitrum Sepolia
        if (chainId == UNICHAIN_SEPOLIA) return 0x2880aB155794e7179c9eE2e38200202908C17B43; // Pyth Unichain Sepolia
        if (chainId == ETHEREUM_SEPOLIA) return 0xDd24F84d36BF92C65F92307595335bdFab5Bbd21; // Pyth Ethereum Sepolia
        if (chainId == LOCAL_ANVIL) return address(0);
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the USDC token address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The USDC token address
    function getUSDC(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC Ethereum Mainnet
        if (chainId == ARBITRUM_MAINNET) return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC Arbitrum Mainnet
        if (chainId == UNICHAIN_MAINNET) return 0x078D782b760474a361dDA0AF3839290b0EF57AD6; // USDC Unichain Mainnet
        if (chainId == ARBITRUM_SEPOLIA) return 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // USDC Arbitrum Sepolia
        if (chainId == UNICHAIN_SEPOLIA) return 0x31d0220469e10c4E71834a79b1f276d740d3768F; // USDC Unichain Sepolia
        if (chainId == ETHEREUM_SEPOLIA) return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC Ethereum Sepolia
        if (chainId == LOCAL_ANVIL) return address(0);
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
        if (chainId == ETHEREUM_MAINNET) return 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af; // Mainnet
        if (chainId == ETHEREUM_SEPOLIA) return 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b; // Sepolia
        if (chainId == ARBITRUM_MAINNET) return 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3; // Arbitrum One
        if (chainId == ARBITRUM_SEPOLIA) return 0xeFd1D4bD4cf1e86Da286BB4CB1B8BcED9C10BA47; // Arbitrum Sepolia
        if (chainId == UNICHAIN_MAINNET) return 0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3; // Unichain
        if (chainId == UNICHAIN_SEPOLIA) return 0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D; // Unichain Sepolia
        if (chainId == LOCAL_ANVIL) return address(0);
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Position Manager address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Position Manager address
    function getPositionManager(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET) return 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e; // Mainnet
        if (chainId == ETHEREUM_SEPOLIA) return 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4; // Sepolia
        if (chainId == ARBITRUM_MAINNET) return 0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869; // Arbitrum One
        if (chainId == ARBITRUM_SEPOLIA) return 0xAc631556d3d4019C95769033B5E719dD77124BAc; // Arbitrum Sepolia
        if (chainId == UNICHAIN_MAINNET) return 0x4529A01c7A0410167c5740C487A8DE60232617bf; // Unichain
        if (chainId == UNICHAIN_SEPOLIA) return 0xf969Aee60879C54bAAed9F3eD26147Db216Fd664; // Unichain Sepolia
        if (chainId == LOCAL_ANVIL) return address(0);
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the StateView address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The StateView address
    function getStateView(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET) return 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227; // Mainnet
        if (chainId == ETHEREUM_SEPOLIA) return 0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C; // Sepolia
        if (chainId == ARBITRUM_MAINNET) return 0x76Fd297e2D437cd7f76d50F01AfE6160f86e9990; // Arbitrum One
        if (chainId == ARBITRUM_SEPOLIA) return 0x9D467FA9062b6e9B1a46E26007aD82db116c67cB; // Arbitrum Sepolia
        if (chainId == UNICHAIN_MAINNET) return 0x86e8631A016F9068C3f085fAF484Ee3F5fDee8f2; // Unichain
        if (chainId == UNICHAIN_SEPOLIA) return 0xc199F1072a74D4e905ABa1A84d9a45E2546B6222; // Unichain Sepolia
        if (chainId == LOCAL_ANVIL) return address(0);
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the Quoter address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Quoter address
    function getQuoter(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_MAINNET) return 0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203; // Mainnet
        if (chainId == ETHEREUM_SEPOLIA) return 0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227; // Sepolia
        if (chainId == ARBITRUM_MAINNET) return 0x3972C00f7ed4885e145823eb7C655375d275A1C5; // Arbitrum One
        if (chainId == ARBITRUM_SEPOLIA) return 0x7dE51022d70A725b508085468052E25e22b5c4c9; // Arbitrum Sepolia
        if (chainId == UNICHAIN_MAINNET) return 0x333E3C607B141b18fF6de9f258db6e77fE7491E0; // Unichain
        if (chainId == UNICHAIN_SEPOLIA) return 0x56DCD40A3F2d466F48e7F48bDBE5Cc9B92Ae4472; // Unichain Sepolia
        if (chainId == LOCAL_ANVIL) return address(0);
        revert UnsupportedChain(chainId);
    }

    /// @notice Get the PoolSwapTest address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The PoolSwapTest address
    function getPoolSwapTest(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_SEPOLIA) return 0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe; // Sepolia
        if (chainId == ARBITRUM_SEPOLIA) return 0xf3A39C86dbd13C45365E57FB90fe413371F65AF8; // Arbitrum Sepolia
        if (chainId == UNICHAIN_SEPOLIA) return 0x9140a78c1A137c7fF1c151EC8231272aF78a99A4; // Unichain Sepolia
        return address(0);
    }

    /// @notice Get the PoolModifyLiquidityTest address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The PoolModifyLiquidityTest address
    function getPoolModifyLiquidityTest(uint256 chainId) internal pure returns (address) {
        if (chainId == ETHEREUM_SEPOLIA) return 0x0C478023803a644c94c4CE1C1e7b9A087e411B0A; // Sepolia
        if (chainId == ARBITRUM_SEPOLIA) return 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7; // Arbitrum Sepolia
        if (chainId == UNICHAIN_SEPOLIA) return 0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB; // Unichain Sepolia
        return address(0);
    }

    /// @notice Get the Permit2 address for a given chain
    /// @param chainId The chain ID to get the address for
    /// @return The Permit2 address
    function getPermit2(uint256 chainId) internal pure returns (address) {
        return 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Permit2 is the same on all mainnets and testnets
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