// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title PriceRegistry
 * @notice Registry for mapping tokens to Pyth Network price feed IDs
 * @dev Provides a centralized, upgradeable mapping between token addresses and Pyth price IDs
 * @dev Pyth price IDs are consistent across all chains, but token addresses vary by chain
 */
contract PriceRegistry {
    /// @notice Owner of the registry (can update mappings)
    address public immutable owner;

    /// @notice Maps token addresses to Pyth price feed IDs
    mapping(address => bytes32) public tokenToPriceId;
    
    /// @notice Maps Pyth price feed IDs to token addresses (reverse lookup)
    mapping(bytes32 => address) public priceIdToToken;
    
    /// @notice Maps token addresses to their symbols for easy identification
    mapping(address => string) public tokenSymbols;
    
    /// @notice Array of all registered token addresses for enumeration
    address[] public registeredTokens;
    
    /// @notice Mapping to check if a token is already registered
    mapping(address => bool) public isTokenRegistered;

    // ============ Events ============

    /// @notice Emitted when a price mapping is set
    event PriceMappingSet(address indexed token, bytes32 indexed priceId, string symbol);
    
    /// @notice Emitted when a price mapping is removed
    event PriceMappingRemoved(address indexed token, bytes32 indexed priceId, string symbol);
    
    /// @notice Emitted when multiple price mappings are set in batch
    event BatchPriceMappingsSet(uint256 count);

    // ============ Errors ============

    error OnlyOwner();
    error InvalidToken();
    error InvalidPriceId(); 
    error TokenAlreadyRegistered(address token);
    error TokenNotRegistered(address token);
    error PriceIdAlreadyUsed(bytes32 priceId, address existingToken);
    error ArrayLengthMismatch();
    error EmptyArrays();

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initialize the price registry
     * @param _owner Address that will own the registry and can update mappings
     */
    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidToken();
        owner = _owner;
    }

    // ============ Core Functions ============

    /**
     * @notice Set price mapping for a single token
     * @param token Token address (use address(0) for native ETH)
     * @param priceId Pyth Network price feed ID
     * @param symbol Token symbol for identification (e.g., "ETH", "USDC")
     */
    function setPriceMapping(address token, bytes32 priceId, string calldata symbol) external onlyOwner {
        if (priceId == bytes32(0)) revert InvalidPriceId();
        
        // Check if price ID is already used by a different token
        address existingToken = priceIdToToken[priceId];
        if (existingToken != address(0) && existingToken != token) {
            revert PriceIdAlreadyUsed(priceId, existingToken);
        }
        
        // Remove old mapping if token was previously registered
        if (isTokenRegistered[token]) {
            bytes32 oldPriceId = tokenToPriceId[token];
            if (oldPriceId != bytes32(0)) {
                delete priceIdToToken[oldPriceId];
            }
        } else {
            // Add to registered tokens array
            registeredTokens.push(token);
            isTokenRegistered[token] = true;
        }
        
        // Set new mappings
        tokenToPriceId[token] = priceId;
        priceIdToToken[priceId] = token;
        tokenSymbols[token] = symbol;
        
        emit PriceMappingSet(token, priceId, symbol);
    }

    /**
     * @notice Set price mappings for multiple tokens in a single transaction
     * @param tokens Array of token addresses
     * @param priceIds Array of corresponding Pyth price feed IDs
     * @param symbols Array of corresponding token symbols
     * @dev All arrays must have the same length
     */
    function setBatchPriceMappings(
        address[] calldata tokens,
        bytes32[] calldata priceIds,
        string[] calldata symbols
    ) external onlyOwner {
        uint256 length = tokens.length;
        if (length == 0) revert EmptyArrays();
        if (length != priceIds.length || length != symbols.length) revert ArrayLengthMismatch();
        
        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            bytes32 priceId = priceIds[i];
            string calldata symbol = symbols[i];
            
            if (priceId == bytes32(0)) revert InvalidPriceId();
            
            // Check if price ID is already used by a different token
            address existingToken = priceIdToToken[priceId];
            if (existingToken != address(0) && existingToken != token) {
                revert PriceIdAlreadyUsed(priceId, existingToken);
            }
            
            // Remove old mapping if token was previously registered
            if (isTokenRegistered[token]) {
                bytes32 oldPriceId = tokenToPriceId[token];
                if (oldPriceId != bytes32(0)) {
                    delete priceIdToToken[oldPriceId];
                }
            } else {
                // Add to registered tokens array
                registeredTokens.push(token);
                isTokenRegistered[token] = true;
            }
            
            // Set new mappings
            tokenToPriceId[token] = priceId;
            priceIdToToken[priceId] = token;
            tokenSymbols[token] = symbol;
            
            emit PriceMappingSet(token, priceId, symbol);
        }
        
        emit BatchPriceMappingsSet(length);
    }

    /**
     * @notice Remove price mapping for a token
     * @param token Token address to remove mapping for
     */
    function removePriceMapping(address token) external onlyOwner {
        if (!isTokenRegistered[token]) revert TokenNotRegistered(token);
        
        bytes32 priceId = tokenToPriceId[token];
        string memory symbol = tokenSymbols[token];
        
        // Clear mappings
        delete tokenToPriceId[token];
        delete priceIdToToken[priceId];
        delete tokenSymbols[token];
        delete isTokenRegistered[token];
        
        // Remove from registered tokens array
        _removeFromRegisteredTokens(token);
        
        emit PriceMappingRemoved(token, priceId, symbol);
    }

    // ============ View Functions ============

    /**
     * @notice Get Pyth price feed ID for a token
     * @param token Token address (use address(0) for native ETH)
     * @return priceId Pyth price feed ID, or bytes32(0) if not registered
     */
    function getPriceId(address token) external view returns (bytes32) {
        return tokenToPriceId[token];
    }



    /**
     * @notice Get token address for a Pyth price feed ID
     * @param priceId Pyth price feed ID
     * @return token Token address, or address(0) if not registered
     */
    function getToken(bytes32 priceId) external view returns (address) {
        return priceIdToToken[priceId];
    }

    /**
     * @notice Get token symbol for a token address
     * @param token Token address
     * @return symbol Token symbol string
     */
    function getTokenSymbol(address token) external view returns (string memory) {
        return tokenSymbols[token];
    }

    /**
     * @notice Check if a token is registered in the registry
     * @param token Token address to check
     * @return registered True if token is registered
     */
    function isRegistered(address token) external view returns (bool) {
        return isTokenRegistered[token];
    }



    /**
     * @notice Get the total number of registered tokens
     * @return count Number of registered tokens
     */
    function getRegisteredTokenCount() external view returns (uint256) {
        return registeredTokens.length;
    }

    /**
     * @notice Get all registered token addresses
     * @return tokens Array of all registered token addresses
     */
    function getAllRegisteredTokens() external view returns (address[] memory) {
        return registeredTokens;
    }

    /**
     * @notice Get registration details for a token
     * @param token Token address
     * @return priceId Pyth price feed ID
     * @return symbol Token symbol
     * @return registered Whether the token is registered
     */
    function getTokenDetails(address token) external view returns (
        bytes32 priceId,
        string memory symbol,
        bool registered
    ) {
        priceId = tokenToPriceId[token];
        symbol = tokenSymbols[token];
        registered = isTokenRegistered[token];
    }

    /**
     * @notice Get multiple token details in a single call
     * @param tokens Array of token addresses
     * @return priceIds Array of corresponding Pyth price feed IDs
     * @return symbols Array of corresponding token symbols
     * @return registered Array of registration status for each token
     */
    function getBatchTokenDetails(address[] calldata tokens) external view returns (
        bytes32[] memory priceIds,
        string[] memory symbols,
        bool[] memory registered
    ) {
        uint256 length = tokens.length;
        priceIds = new bytes32[](length);
        symbols = new string[](length);
        registered = new bool[](length);
        
        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            priceIds[i] = tokenToPriceId[token];
            symbols[i] = tokenSymbols[token];
            registered[i] = isTokenRegistered[token];
        }
    }

    // ============ Internal Functions ============

    /**
     * @notice Remove a token from the registered tokens array
     * @param token Token address to remove
     */
    function _removeFromRegisteredTokens(address token) internal {
        uint256 length = registeredTokens.length;
        for (uint256 i = 0; i < length; i++) {
            if (registeredTokens[i] == token) {
                // Move last element to this position and pop
                registeredTokens[i] = registeredTokens[length - 1];
                registeredTokens.pop();
                break;
            }
        }
    }
} 