// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

/**
 * @title DeployPriceRegistry
 * @notice Deployment script for PriceRegistry with chain-specific token mappings
 * @dev Supports Arbitrum, Unichain, and Ethereum (both mainnet and testnet)
 */
contract DeployPriceRegistry is Script {
    using ChainAddresses for uint256;

    // Pyth price feed IDs (consistent across all chains)
    bytes32 public constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    
    // Future price IDs for additional tokens
    bytes32 public constant BTC_USD_PRICE_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
    bytes32 public constant WETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // Same as ETH
    
    PriceRegistry public priceRegistry;

    struct TokenMapping {
        address token;
        bytes32 priceId;
        string symbol;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== DEPLOYING PRICE REGISTRY ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PriceRegistry
        priceRegistry = new PriceRegistry(deployer);
        console.log("PriceRegistry deployed at:", address(priceRegistry));

        // Setup token mappings for current chain
        _setupTokenMappings();

        vm.stopBroadcast();

        // Verify deployment
        _verifyDeployment();

        console.log("=== PRICE REGISTRY DEPLOYMENT COMPLETE ===");
    }

    /**
     * @notice Setup token mappings for the current chain
     */
    function _setupTokenMappings() internal {
        TokenMapping[] memory mappings = _getTokenMappingsForChain(block.chainid);
        
        if (mappings.length == 0) {
            console.log("No token mappings configured for chain:", block.chainid);
            return;
        }

        // Prepare batch arrays
        address[] memory tokens = new address[](mappings.length);
        bytes32[] memory priceIds = new bytes32[](mappings.length);
        string[] memory symbols = new string[](mappings.length);

        for (uint256 i = 0; i < mappings.length; i++) {
            tokens[i] = mappings[i].token;
            priceIds[i] = mappings[i].priceId;
            symbols[i] = mappings[i].symbol;
            
            console.log("Mapping:", symbols[i]);
            console.log("  Token:", tokens[i]);
            console.log("  Price ID:", vm.toString(priceIds[i]));
        }

        // Set batch mappings
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        console.log("Batch token mappings set successfully");
    }

    /**
     * @notice Get token mappings for a specific chain
     * @param chainId The chain ID to get mappings for
     * @return mappings Array of token mappings for the chain
     */
    function _getTokenMappingsForChain(uint256 chainId) internal pure returns (TokenMapping[] memory mappings) {
        if (chainId == 1) {
            // Ethereum Mainnet
            mappings = new TokenMapping[](2);
            mappings[0] = TokenMapping(address(0), ETH_USD_PRICE_ID, "ETH");
            mappings[1] = TokenMapping(0xa0b86a33E6441B8DB71B6E42C09E84c3A9a3f5e1, USDC_USD_PRICE_ID, "USDC"); // USDC mainnet
        } else if (chainId == 11155111) {
            // Ethereum Sepolia
            mappings = new TokenMapping[](2);
            mappings[0] = TokenMapping(address(0), ETH_USD_PRICE_ID, "ETH");
            mappings[1] = TokenMapping(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, USDC_USD_PRICE_ID, "USDC"); // USDC Sepolia
        } else if (chainId == 42161) {
            // Arbitrum One
            mappings = new TokenMapping[](2);
            mappings[0] = TokenMapping(address(0), ETH_USD_PRICE_ID, "ETH");
            mappings[1] = TokenMapping(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, USDC_USD_PRICE_ID, "USDC"); // USDC Arbitrum
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            mappings = new TokenMapping[](2);
            mappings[0] = TokenMapping(address(0), ETH_USD_PRICE_ID, "ETH");
            mappings[1] = TokenMapping(0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d, USDC_USD_PRICE_ID, "USDC"); // USDC Arbitrum Sepolia
        } else if (chainId == 1301) {
            // Unichain Sepolia
            mappings = new TokenMapping[](2);
            mappings[0] = TokenMapping(address(0), ETH_USD_PRICE_ID, "ETH");
            mappings[1] = TokenMapping(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, USDC_USD_PRICE_ID, "USDC"); // USDC Unichain Sepolia (assuming same as Sepolia)
        } else if (chainId == 31337) {
            // Anvil (Local)
            mappings = new TokenMapping[](2);
            mappings[0] = TokenMapping(address(0), ETH_USD_PRICE_ID, "ETH");
            mappings[1] = TokenMapping(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, USDC_USD_PRICE_ID, "USDC"); // Mock USDC for testing
        } else {
            // Unsupported chain
            mappings = new TokenMapping[](0);
        }
    }

    /**
     * @notice Verify deployment was successful
     */
    function _verifyDeployment() internal view {
        console.log("=== VERIFYING DEPLOYMENT ===");
        
        // Check owner
        address owner = priceRegistry.owner();
        console.log("Registry owner:", owner);
        require(owner != address(0), "Invalid owner");

        // Check token mappings
        uint256 tokenCount = priceRegistry.getRegisteredTokenCount();
        console.log("Registered tokens:", tokenCount);

        if (tokenCount > 0) {
            address[] memory tokens = priceRegistry.getAllRegisteredTokens();
            
            for (uint256 i = 0; i < tokens.length; i++) {
                (bytes32 priceId, string memory symbol, bool registered) = priceRegistry.getTokenDetails(tokens[i]);
                console.log("Token", i + 1, ":");
                console.log("  Address:", tokens[i]);
                console.log("  Symbol:", symbol);
                console.log("  Price ID:", vm.toString(priceId));
                console.log("  Registered:", registered);
                
                require(registered, "Token should be registered");
                require(priceId != bytes32(0), "Price ID should not be zero");
            }
        }

        console.log("Deployment verification successful!");
    }

    /**
     * @notice Add additional token mapping after deployment
     * @param token Token address
     * @param priceId Pyth price feed ID
     * @param symbol Token symbol
     * @dev Can only be called by the registry owner
     */
    function addTokenMapping(address token, bytes32 priceId, string memory symbol) external {
        require(address(priceRegistry) != address(0), "Registry not deployed");
        
        priceRegistry.setPriceMapping(token, priceId, symbol);
        console.log("Added token mapping:", symbol);
        console.log("  Token:", token);
        console.log("  Price ID:", vm.toString(priceId));
    }

    /**
     * @notice Add multiple token mappings after deployment
     * @param tokens Array of token addresses
     * @param priceIds Array of Pyth price feed IDs
     * @param symbols Array of token symbols
     * @dev Can only be called by the registry owner
     */
    function addTokenMappingsBatch(
        address[] memory tokens,
        bytes32[] memory priceIds,
        string[] memory symbols
    ) external {
        require(address(priceRegistry) != address(0), "Registry not deployed");
        
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        console.log("Added batch token mappings. Count:", tokens.length);
    }

    /**
     * @notice Get supported chains
     * @return Array of supported chain IDs
     */
    function getSupportedChains() external pure returns (uint256[] memory) {
        uint256[] memory chains = new uint256[](6);
        chains[0] = 1;        // Ethereum Mainnet
        chains[1] = 11155111; // Ethereum Sepolia
        chains[2] = 42161;    // Arbitrum One
        chains[3] = 421614;   // Arbitrum Sepolia
        chains[4] = 1301;     // Unichain Sepolia
        chains[5] = 31337;    // Anvil (Local)
        return chains;
    }

    /**
     * @notice Get registry address (for use in other scripts)
     * @return Address of deployed PriceRegistry
     */
    function getRegistryAddress() external view returns (address) {
        return address(priceRegistry);
    }
} 