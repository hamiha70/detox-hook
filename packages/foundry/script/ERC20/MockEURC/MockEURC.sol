// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockEURC
/// @notice Mock EUR Coin token for testing and development
/// @dev ERC20 token with minting capabilities, mimicking EURC (Euro Coin) properties
contract MockEURC is ERC20, Ownable {
    uint8 private immutable _decimals;

    /// @notice Deploy MockEURC token
    /// @param name Token name (e.g., "Euro Coin")
    /// @param symbol Token symbol (e.g., "EURC")
    /// @param decimals_ Number of decimals (typically 6 for EURC)
    /// @param owner_ Initial owner who can mint tokens
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address owner_
    ) ERC20(name, symbol) Ownable(owner_) {
        _decimals = decimals_;
    }

    /// @notice Mint tokens to specified address
    /// @param to Address to receive minted tokens
    /// @param amount Amount of tokens to mint (in token units, not wei)
    /// @dev Only owner can mint tokens
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Get token decimals
    /// @return Number of decimals for this token
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
