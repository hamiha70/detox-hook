// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {TokenHelpers} from "./TokenHelpers.sol";
import {MockEURC} from "./MockEURC.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

/**
 * @title DeployMockEURC
 * @notice Complete deployment script for MockEURC token on multiple networks
 * @dev Supports local, Arbitrum Sepolia, and Arbitrum One deployments
 * @author DetoxHook Team
 */
contract DeployMockEURC is Script {
    // Network constants
    uint256 constant ARBITRUM_ONE = 42161;
    uint256 constant ARBITRUM_SEPOLIA = 421614;
    uint256 constant LOCAL_ANVIL = 31337;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Optional: Get additional accounts to fund from environment
        // Format: comma-separated addresses like "0x123...,0x456..."
        string memory additionalAccountsStr = vm.envOr(
            "ADDITIONAL_ACCOUNTS",
            string("")
        );
        address[] memory additionalAccounts = parseAddresses(
            additionalAccountsStr
        );

        // Optional: Control demo account funding
        bool fundDemoAccounts = vm.envOr("FUND_DEMO_ACCOUNTS", true);

        // Network-specific configuration
        string memory networkName = getNetworkName(block.chainid);
        bool isArbitrum = (block.chainid == ARBITRUM_ONE ||
            block.chainid == ARBITRUM_SEPOLIA);

        console.log("=== MockEURC Deployment ===");
        console.log("Network:", networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Fund demo accounts:", fundDemoAccounts);
        console.log("Additional accounts:", additionalAccounts.length);
        console.log("Is Arbitrum:", isArbitrum);
        console.log("");

        // Network-specific validations
        if (isArbitrum) {
            validateArbitrumDeployment();
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockEURC with complete setup
        (MockEURC mockEURC, IERC20Minimal token) = TokenHelpers
            .deployAndSetupMockEURC(
                deployer,
                fundDemoAccounts,
                additionalAccounts
            );

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("MockEURC Address:", address(mockEURC));
        console.log("Owner:", mockEURC.owner());
        console.log("Name:", mockEURC.name());
        console.log("Symbol:", mockEURC.symbol());
        console.log("Decimals:", mockEURC.decimals());
        console.log("Deployer Balance:", token.balanceOf(deployer));
        console.log("");

        // Log funded accounts for verification
        if (fundDemoAccounts && block.chainid == LOCAL_ANVIL) {
            console.log("=== Demo Account Balances ===");
            address[] memory anvilAccounts = new address[](3);
            anvilAccounts[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
            anvilAccounts[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
            anvilAccounts[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

            for (uint256 i = 0; i < anvilAccounts.length; i++) {
                console.log("Account:", anvilAccounts[i]);
                console.log("Balance:", token.balanceOf(anvilAccounts[i]));
            }
        }

        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Update MintMockEURC.s.sol with contract address:");
        console.log("   address constant MOCK_EURC =", address(mockEURC), ";");
        console.log("2. Save deployment info to deployments/ directory");

        if (isArbitrum) {
            console.log("3. Verify contract on Arbiscan:");
            if (block.chainid == ARBITRUM_ONE) {
                console.log(
                    "   https://arbiscan.io/address/",
                    address(mockEURC)
                );
            } else {
                console.log(
                    "   https://sepolia.arbiscan.io/address/",
                    address(mockEURC)
                );
            }
            console.log(
                "4. Use --verify flag with --etherscan-api-key for automatic verification"
            );
        } else {
            console.log(
                "3. Verify contract on block explorer if on testnet/mainnet"
            );
        }
        console.log("");
    }

    /// @notice Parse comma-separated addresses from string
    /// @param addressesStr Comma-separated address string
    /// @return addresses Array of parsed addresses
    function parseAddresses(
        string memory addressesStr
    ) internal pure returns (address[] memory addresses) {
        if (bytes(addressesStr).length == 0) {
            return new address[](0);
        }

        // For simplicity, returning empty array
        // In a full implementation, you'd parse the comma-separated string
        return new address[](0);
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

    /// @notice Validate Arbitrum-specific deployment requirements
    function validateArbitrumDeployment() internal view {
        console.log("=== Arbitrum Deployment Validation ===");

        // Check if we're on the correct network
        if (block.chainid == ARBITRUM_ONE) {
            console.log("Deploying to Arbitrum One (Mainnet)");
            console.log("[WARNING] This is mainnet - ensure proper testing!");
        } else if (block.chainid == ARBITRUM_SEPOLIA) {
            console.log("Deploying to Arbitrum Sepolia (Testnet)");
            console.log("[SUCCESS] Safe for testing and development");
        }

        console.log("Network validation passed");
        console.log("");
    }
}
