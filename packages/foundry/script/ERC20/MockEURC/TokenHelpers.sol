// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {MockEURC} from "./MockEURC.sol";
import {SafetyChecks} from "../../Utility/SafetyChecks.sol";

/// @title TokenHelpers
/// @notice Utility library for MockEURC-only token strategy across all environments
/// @dev Deploys and manages MockEURC for consistent testing and demo experience
library TokenHelpers {
    // ============ Events ============

    event MockEURCDeployed(
        address indexed mockEURC,
        address indexed owner,
        uint256 chainId
    );
    event AccountFunded(
        address indexed account,
        address indexed token,
        uint256 amount
    );

    // ============ Constants ============

    uint256 public constant DEFAULT_MINT_AMOUNT = 1_000_000e6; // 1M EURC (6 decimals)
    uint256 public constant DEMO_ACCOUNT_FUNDING = 100_000e6; // 100K EURC per demo account

    // ============ Deployment & Setup ============

    /// @notice Deploy MockEURC for any environment
    /// @param deployer The deployer/owner address (will have minting rights)
    /// @param name Token name (e.g., "Euro Coin")
    /// @param symbol Token symbol (e.g., "EURC")
    /// @return mockEURC The deployed MockEURC contract
    function deployMockEURC(
        address deployer,
        string memory name,
        string memory symbol
    ) internal returns (MockEURC mockEURC) {
        console.log("=== Deploying MockEURC ===");
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Deployer/Owner:", deployer);

        // Validate deployer has sufficient ETH for deployment
        SafetyChecks.validateETHBalance(
            deployer,
            0.001 ether,
            "MockEURC deployment"
        );

        // Deploy MockEURC with 6 decimals (standard EURC decimals)
        mockEURC = new MockEURC(name, symbol, 6, deployer);

        console.log("MockEURC deployed at:", address(mockEURC));
        console.log("Owner:", mockEURC.owner());
        console.log("Decimals:", mockEURC.decimals());

        emit MockEURCDeployed(address(mockEURC), deployer, block.chainid);
    }

    /// @notice Deploy MockEURC with standard parameters
    /// @param deployer The deployer/owner address
    /// @return mockEURC The deployed MockEURC contract
    function deployStandardMockEURC(
        address deployer
    ) internal returns (MockEURC mockEURC) {
        return deployMockEURC(deployer, "Euro Coin (Mock)", "EURC");
    }

    // ============ Funding Operations ============

    /// @notice Fund a single account with MockEURC
    /// @param mockEURC The MockEURC contract
    /// @param account Account to fund
    /// @param amount Amount to mint and transfer
    function fundAccount(
        MockEURC mockEURC,
        address account,
        uint256 amount
    ) internal {
        console.log("[FUNDING] Funding account with MockEURC");
        console.log("[FUNDING] Account:", account);
        console.log("[FUNDING] Amount:", amount);
        console.log("[FUNDING] Token:", address(mockEURC));

        // Note: MockEURC.mint() has onlyOwner modifier, so it will revert if not called by owner
        // In Foundry scripts, this requires vm.startBroadcast(deployerPrivateKey) context
        mockEURC.mint(account, amount);

        // Verify funding was successful
        uint256 balance = mockEURC.balanceOf(account);
        console.log("[FUNDING] Account funded successfully");
        console.log("[FUNDING] New balance:", balance);

        emit AccountFunded(account, address(mockEURC), amount);
    }

    /// @notice Fund multiple accounts with MockEURC
    /// @param mockEURC The MockEURC contract
    /// @param accounts Array of accounts to fund
    /// @param amount Amount to mint for each account
    function fundAccounts(
        MockEURC mockEURC,
        address[] memory accounts,
        uint256 amount
    ) internal {
        console.log("[FUNDING] Funding accounts with MockEURC");
        console.log("[FUNDING] Number of accounts:", accounts.length);
        console.log("[FUNDING] Amount per account:", amount);

        for (uint256 i = 0; i < accounts.length; i++) {
            fundAccount(mockEURC, accounts[i], amount);
        }

        console.log("[FUNDING] All accounts funded successfully");
    }

    /// @notice Fund deployer with initial MockEURC supply
    /// @param mockEURC The MockEURC contract
    /// @param deployer Deployer account to fund
    function fundDeployer(MockEURC mockEURC, address deployer) internal {
        fundAccount(mockEURC, deployer, DEFAULT_MINT_AMOUNT);
    }

    /// @notice Fund common demo/test accounts
    /// @param mockEURC The MockEURC contract
    /// @param additionalAccounts Additional accounts to fund beyond standard ones
    function fundDemoAccounts(
        MockEURC mockEURC,
        address[] memory additionalAccounts
    ) internal {
        console.log("=== Funding Demo Accounts ===");

        // Standard Anvil test accounts (if on local network)
        if (block.chainid == 31337) {
            address[] memory anvilAccounts = new address[](3);
            anvilAccounts[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil account 0
            anvilAccounts[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1
            anvilAccounts[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account 2

            fundAccounts(mockEURC, anvilAccounts, DEMO_ACCOUNT_FUNDING);
        }

        // Fund any additional accounts provided
        if (additionalAccounts.length > 0) {
            fundAccounts(mockEURC, additionalAccounts, DEMO_ACCOUNT_FUNDING);
        }

        console.log("Demo accounts funding completed");
    }

    // ============ Token Management ============

    /// @notice Get MockEURC interface from address
    /// @param mockEURCAddress Address of deployed MockEURC
    /// @return mockEURC MockEURC contract interface
    function getMockEURC(
        address mockEURCAddress
    ) internal pure returns (MockEURC mockEURC) {
        return MockEURC(mockEURCAddress);
    }

    /// @notice Get IERC20Minimal interface from MockEURC
    /// @param mockEURC MockEURC contract
    /// @return token IERC20Minimal interface
    function getTokenInterface(
        MockEURC mockEURC
    ) internal pure returns (IERC20Minimal token) {
        return IERC20Minimal(address(mockEURC));
    }

    /// @notice Validate MockEURC deployment and ownership
    /// @param mockEURC MockEURC contract to validate
    /// @param expectedOwner Expected owner address
    function validateMockEURC(
        MockEURC mockEURC,
        address expectedOwner
    ) internal view {
        console.log("=== Validating MockEURC ===");

        // Check contract exists
        SafetyChecks.checkContractExists(address(mockEURC), "MockEURC");

        // Check ownership
        address actualOwner = mockEURC.owner();
        require(actualOwner == expectedOwner, "MockEURC owner mismatch");

        // Check basic properties
        require(mockEURC.decimals() == 6, "MockEURC should have 6 decimals");
        require(
            bytes(mockEURC.symbol()).length > 0,
            "MockEURC should have a symbol"
        );
        require(
            bytes(mockEURC.name()).length > 0,
            "MockEURC should have a name"
        );

        console.log("MockEURC validation passed");
        console.log("Address:", address(mockEURC));
        console.log("Owner:", actualOwner);
        console.log("Name:", mockEURC.name());
        console.log("Symbol:", mockEURC.symbol());
        console.log("Decimals:", mockEURC.decimals());
    }

    // ============ Deployment Strategy ============

    /// @notice Complete MockEURC deployment and setup for any environment
    /// @param deployer Deployer/owner address
    /// @param fundDemoAccountsFlag Whether to fund demo accounts
    /// @param additionalAccounts Additional accounts to fund
    /// @return mockEURC Deployed and configured MockEURC
    /// @return token IERC20Minimal interface for the MockEURC
    function deployAndSetupMockEURC(
        address deployer,
        bool fundDemoAccountsFlag,
        address[] memory additionalAccounts
    ) internal returns (MockEURC mockEURC, IERC20Minimal token) {
        console.log("=== Complete MockEURC Setup ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Fund demo accounts:", fundDemoAccountsFlag);
        console.log("Additional accounts:", additionalAccounts.length);

        // Deploy MockEURC
        mockEURC = deployStandardMockEURC(deployer);
        token = getTokenInterface(mockEURC);

        // Fund deployer with initial supply
        fundDeployer(mockEURC, deployer);

        // Fund demo accounts if requested
        if (fundDemoAccountsFlag) {
            fundDemoAccounts(mockEURC, additionalAccounts);
        }

        // Validate deployment
        validateMockEURC(mockEURC, deployer);

        console.log("=== MockEURC Setup Complete ===");
        console.log("MockEURC Address:", address(mockEURC));
        console.log("Owner:", mockEURC.owner());
        console.log("Deployer Balance:", token.balanceOf(deployer));

        return (mockEURC, token);
    }

    // ============ Utility Functions ============

    /// @notice Log comprehensive token status
    /// @param mockEURC MockEURC contract
    /// @param accounts Accounts to check balances for
    function logTokenStatus(
        MockEURC mockEURC,
        address[] memory accounts
    ) internal view {
        console.log("=== MockEURC Status ===");
        console.log("Address:", address(mockEURC));
        console.log("Name:", mockEURC.name());
        console.log("Symbol:", mockEURC.symbol());
        console.log("Decimals:", mockEURC.decimals());
        console.log("Owner:", mockEURC.owner());
        console.log("Total Supply:", mockEURC.totalSupply());

        console.log("Account Balances:");
        for (uint256 i = 0; i < accounts.length; i++) {
            console.log("  Account:", accounts[i]);
            console.log("  Balance:", mockEURC.balanceOf(accounts[i]));
        }
        console.log("======================");
    }

    /// @notice Check if address is a valid MockEURC contract
    /// @param tokenAddress Address to check
    /// @return isValid True if address is a valid MockEURC
    function isValidMockEURC(
        address tokenAddress
    ) internal view returns (bool isValid) {
        if (tokenAddress.code.length == 0) return false;

        try MockEURC(tokenAddress).decimals() returns (uint8 decimals) {
            if (decimals != 6) return false;

            try MockEURC(tokenAddress).owner() returns (address) {
                return true; // Has owner() function, likely MockEURC
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }
}
