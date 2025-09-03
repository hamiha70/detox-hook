// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./MockEURC.sol";

/**
 * @title MintMockEURC
 * @notice Script to mint MockEURC to a single address on multiple networks
 * @dev Only the original deployer can mint tokens
 * @author DetoxHook Team
 */
contract MintMockEURC is Script {
    // Network constants
    uint256 constant ARBITRUM_ONE = 42161;
    uint256 constant ARBITRUM_SEPOLIA = 421614;
    uint256 constant LOCAL_ANVIL = 31337;

    // MockEURC contract address (will be set after deployment)
    // Update this address after deploying MockEURC to your target network
    address constant MOCK_EURC = 0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E; // UPDATE AFTER DEPLOYMENT

    function run() external {
        // Get parameters from command line
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");
        uint256 amount = vm.envUint("MINT_AMOUNT");

        // Get the deployer from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Network detection
        string memory networkName = getNetworkName(block.chainid);
        bool isArbitrum = (block.chainid == ARBITRUM_ONE ||
            block.chainid == ARBITRUM_SEPOLIA);

        console.log("=== MintMockEURC ===");
        console.log("Network:", networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("MockEURC Contract:", MOCK_EURC);
        console.log("Recipient Address:", recipient);
        console.log("Mint Amount:", amount, "EURC");
        console.log("Is Arbitrum:", isArbitrum);
        console.log("");

        // Validate MockEURC address is set
        require(
            MOCK_EURC != address(0),
            "MOCK_EURC address not set - update contract address"
        );

        // Network-specific validations
        if (isArbitrum) {
            validateArbitrumMinting();
        }

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Create MockEURC instance
        MockEURC mockEURC = MockEURC(MOCK_EURC);

        console.log("Minting MockEURC...");
        mockEURC.mint(recipient, amount);
        console.log("[SUCCESS] Minted", amount, "EURC to", recipient);
        console.log("");

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("=== Minting Complete ===");
        console.log(
            "New balance for",
            recipient,
            ":",
            mockEURC.balanceOf(recipient)
        );

        if (isArbitrum) {
            console.log("");
            console.log("=== Arbitrum Information ===");
            if (block.chainid == ARBITRUM_ONE) {
                console.log(
                    "View on Arbiscan: https://arbiscan.io/address/",
                    MOCK_EURC
                );
            } else {
                console.log(
                    "View on Arbiscan: https://sepolia.arbiscan.io/address/",
                    MOCK_EURC
                );
            }
            console.log("Transaction hash will be displayed above");
        }
    }

    /// @notice Get human-readable network name
    /// @param chainId The chain ID
    /// @return networkName Human-readable network name
    function getNetworkName(
        uint256 chainId
    ) internal pure returns (string memory networkName) {
        if (chainId == ARBITRUM_ONE) return "Arbitrum One (Mainnet)";
        if (chainId == ARBITRUM_SEPOLIA) return "Arbitrum Sepolia (Testnet)";
        if (chainId == LOCAL_ANVIL) return "Local Anvil";
        return "Unknown Network";
    }

    /// @notice Validate Arbitrum-specific minting requirements
    function validateArbitrumMinting() internal view {
        console.log("=== Arbitrum Minting Validation ===");

        // Check if we're on the correct network
        if (block.chainid == ARBITRUM_ONE) {
            console.log("Minting on Arbitrum One (Mainnet)");
            console.log("[WARNING] This is mainnet - ensure proper testing!");
        } else if (block.chainid == ARBITRUM_SEPOLIA) {
            console.log("Minting on Arbitrum Sepolia (Testnet)");
            console.log("[SUCCESS] Safe for testing and development");
        }

        console.log("Network validation passed");
        console.log("");
    }
}
