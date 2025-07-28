// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "./MockUSDC.sol";

/**
 * @title MintMockUSDC
 * @notice Script to mint MockUSDC to a single address
 * @dev Only the original deployer can mint tokens
 * @author DetoxHook Team
 */
contract MintMockUSDC is Script {
    // MockUSDC contract address (deployed on Arbitrum Sepolia)
    address constant MOCK_USDC = 0x9D5A68fDFEcc14683324640D5e835936422a47b1;

    function run() external {
        // Get parameters from command line
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");
        uint256 amount = vm.envUint("MINT_AMOUNT");
        
        // Get the deployer from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== MintMockUSDC ===");
        console.log("Deployer:", deployer);
        console.log("MockUSDC Contract:", MOCK_USDC);
        console.log("Recipient Address:", recipient);
        console.log("Mint Amount:", amount, "USDC");
        console.log("");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Create MockUSDC instance
        MockUSDC mockUSDC = MockUSDC(MOCK_USDC);
        
        console.log("Minting MockUSDC...");
        mockUSDC.mint(recipient, amount);
        console.log("[SUCCESS] Minted", amount, "USDC to", recipient);
        console.log("");
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        console.log("=== Minting Complete ===");
        console.log("New balance for", recipient, ":", mockUSDC.balanceOf(recipient));
    }
} 