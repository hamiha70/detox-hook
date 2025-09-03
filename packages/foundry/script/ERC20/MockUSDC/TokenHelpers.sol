// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {SafetyChecks} from "../../Utility/SafetyChecks.sol";

/// @title TokenHelpers
/// @notice Utility library for MockUSDC-only token strategy across all environments
/// @dev Deploys and manages MockUSDC for consistent testing and demo experience
library TokenHelpers {
    // ============ Events ============

    event MockUSDCDeployed(
        address indexed mockUSDC,
        address indexed owner,
        uint256 chainId
    );
    event AccountFunded(
        address indexed account,
        address indexed token,
        uint256 amount
    );

    // ============ Constants ============

    uint256 public constant DEFAULT_MINT_AMOUNT = 1_000_000e6; // 1M USDC (6 decimals)
    uint256 public constant DEMO_ACCOUNT_FUNDING = 100_000e6; // 100K USDC per demo account

    // ============ Deployment & Setup ============

    /// @notice Deploy MockUSDC for any environment
    /// @param deployer The deployer/owner address (will have minting rights)
    /// @param name Token name (e.g., "USD Coin")
    /// @param symbol Token symbol (e.g., "USDC")
    /// @return mockUSDC The deployed MockUSDC contract
    function deployMockUSDC(
        address deployer,
        string memory name,
        string memory symbol
    ) internal returns (MockUSDC mockUSDC) {
        console.log("=== Deploying MockUSDC ===");
        console.log("Name:", name);
        console.log("Symbol:", symbol);
        console.log("Deployer/Owner:", deployer);

        // Validate deployer has sufficient ETH for deployment
        SafetyChecks.validateETHBalance(
            deployer,
            0.001 ether,
            "MockUSDC deployment"
        );

        // Deploy MockUSDC with 6 decimals (standard USDC decimals)
        mockUSDC = new MockUSDC(name, symbol, 6, deployer);

        console.log("MockUSDC deployed at:", address(mockUSDC));
        console.log("Owner:", mockUSDC.owner());
        console.log("Decimals:", mockUSDC.decimals());

        emit MockUSDCDeployed(address(mockUSDC), deployer, block.chainid);
    }

    /// @notice Deploy MockUSDC with standard parameters
    /// @param deployer The deployer/owner address
    /// @return mockUSDC The deployed MockUSDC contract
    function deployStandardMockUSDC(
        address deployer
    ) internal returns (MockUSDC mockUSDC) {
        return deployMockUSDC(deployer, "USD Coin (Mock)", "USDC");
    }

    // ============ Funding Operations ============

    /// @notice Fund a single account with MockUSDC
    /// @param mockUSDC The MockUSDC contract
    /// @param account Account to fund
    /// @param amount Amount to mint and transfer
    function fundAccount(
        MockUSDC mockUSDC,
        address account,
        uint256 amount
    ) internal {
        console.log("[FUNDING] Funding account with MockUSDC");
        console.log("[FUNDING] Account:", account);
        console.log("[FUNDING] Amount:", amount);
        console.log("[FUNDING] Token:", address(mockUSDC));

        // Note: MockUSDC.mint() has onlyOwner modifier, so it will revert if not called by owner
        // In Foundry scripts, this requires vm.startBroadcast(deployerPrivateKey) context
        mockUSDC.mint(account, amount);

        // Verify funding was successful
        uint256 balance = mockUSDC.balanceOf(account);
        console.log("[FUNDING] Account funded successfully");
        console.log("[FUNDING] New balance:", balance);

        emit AccountFunded(account, address(mockUSDC), amount);
    }

    /// @notice Fund multiple accounts with MockUSDC
    /// @param mockUSDC The MockUSDC contract
    /// @param accounts Array of accounts to fund
    /// @param amount Amount to mint for each account
    function fundAccounts(
        MockUSDC mockUSDC,
        address[] memory accounts,
        uint256 amount
    ) internal {
        console.log("[FUNDING] Funding accounts with MockUSDC");
        console.log("[FUNDING] Number of accounts:", accounts.length);
        console.log("[FUNDING] Amount per account:", amount);

        for (uint256 i = 0; i < accounts.length; i++) {
            fundAccount(mockUSDC, accounts[i], amount);
        }

        console.log("[FUNDING] All accounts funded successfully");
    }

    /// @notice Fund deployer with initial MockUSDC supply
    /// @param mockUSDC The MockUSDC contract
    /// @param deployer Deployer account to fund
    function fundDeployer(MockUSDC mockUSDC, address deployer) internal {
        fundAccount(mockUSDC, deployer, DEFAULT_MINT_AMOUNT);
    }

    /// @notice Fund common demo/test accounts
    /// @param mockUSDC The MockUSDC contract
    /// @param additionalAccounts Additional accounts to fund beyond standard ones
    function fundDemoAccounts(
        MockUSDC mockUSDC,
        address[] memory additionalAccounts
    ) internal {
        console.log("=== Funding Demo Accounts ===");

        // Standard Anvil test accounts (if on local network)
        if (block.chainid == 31337) {
            address[] memory anvilAccounts = new address[](3);
            anvilAccounts[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil account 0
            anvilAccounts[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1
            anvilAccounts[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account 2

            fundAccounts(mockUSDC, anvilAccounts, DEMO_ACCOUNT_FUNDING);
        }

        // Fund any additional accounts provided
        if (additionalAccounts.length > 0) {
            fundAccounts(mockUSDC, additionalAccounts, DEMO_ACCOUNT_FUNDING);
        }

        console.log("Demo accounts funding completed");
    }

    // ============ Token Management ============

    /// @notice Get MockUSDC interface from address
    /// @param mockUSDCAddress Address of deployed MockUSDC
    /// @return mockUSDC MockUSDC contract interface
    function getMockUSDC(
        address mockUSDCAddress
    ) internal pure returns (MockUSDC mockUSDC) {
        return MockUSDC(mockUSDCAddress);
    }

    /// @notice Get IERC20Minimal interface from MockUSDC
    /// @param mockUSDC MockUSDC contract
    /// @return token IERC20Minimal interface
    function getTokenInterface(
        MockUSDC mockUSDC
    ) internal pure returns (IERC20Minimal token) {
        return IERC20Minimal(address(mockUSDC));
    }

    /// @notice Validate MockUSDC deployment and ownership
    /// @param mockUSDC MockUSDC contract to validate
    /// @param expectedOwner Expected owner address
    function validateMockUSDC(
        MockUSDC mockUSDC,
        address expectedOwner
    ) internal view {
        console.log("=== Validating MockUSDC ===");

        // Check contract exists
        SafetyChecks.checkContractExists(address(mockUSDC), "MockUSDC");

        // Check ownership
        address actualOwner = mockUSDC.owner();
        require(actualOwner == expectedOwner, "MockUSDC owner mismatch");

        // Check basic properties
        require(mockUSDC.decimals() == 6, "MockUSDC should have 6 decimals");
        require(
            bytes(mockUSDC.symbol()).length > 0,
            "MockUSDC should have a symbol"
        );
        require(
            bytes(mockUSDC.name()).length > 0,
            "MockUSDC should have a name"
        );

        console.log("MockUSDC validation passed");
        console.log("Address:", address(mockUSDC));
        console.log("Owner:", actualOwner);
        console.log("Name:", mockUSDC.name());
        console.log("Symbol:", mockUSDC.symbol());
        console.log("Decimals:", mockUSDC.decimals());
    }

    // ============ Deployment Strategy ============

    /// @notice Complete MockUSDC deployment and setup for any environment
    /// @param deployer Deployer/owner address
    /// @param fundDemoAccountsFlag Whether to fund demo accounts
    /// @param additionalAccounts Additional accounts to fund
    /// @return mockUSDC Deployed and configured MockUSDC
    /// @return token IERC20Minimal interface for the MockUSDC
    function deployAndSetupMockUSDC(
        address deployer,
        bool fundDemoAccountsFlag,
        address[] memory additionalAccounts
    ) internal returns (MockUSDC mockUSDC, IERC20Minimal token) {
        console.log("=== Complete MockUSDC Setup ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Fund demo accounts:", fundDemoAccountsFlag);
        console.log("Additional accounts:", additionalAccounts.length);

        // Deploy MockUSDC
        mockUSDC = deployStandardMockUSDC(deployer);
        token = getTokenInterface(mockUSDC);

        // Fund deployer with initial supply
        fundDeployer(mockUSDC, deployer);

        // Fund demo accounts if requested
        if (fundDemoAccountsFlag) {
            fundDemoAccounts(mockUSDC, additionalAccounts);
        }

        // Validate deployment
        validateMockUSDC(mockUSDC, deployer);

        console.log("=== MockUSDC Setup Complete ===");
        console.log("MockUSDC Address:", address(mockUSDC));
        console.log("Owner:", mockUSDC.owner());
        console.log("Deployer Balance:", token.balanceOf(deployer));

        return (mockUSDC, token);
    }

    // ============ Utility Functions ============

    /// @notice Log comprehensive token status
    /// @param mockUSDC MockUSDC contract
    /// @param accounts Accounts to check balances for
    function logTokenStatus(
        MockUSDC mockUSDC,
        address[] memory accounts
    ) internal view {
        console.log("=== MockUSDC Status ===");
        console.log("Address:", address(mockUSDC));
        console.log("Name:", mockUSDC.name());
        console.log("Symbol:", mockUSDC.symbol());
        console.log("Decimals:", mockUSDC.decimals());
        console.log("Owner:", mockUSDC.owner());
        console.log("Total Supply:", mockUSDC.totalSupply());

        console.log("Account Balances:");
        for (uint256 i = 0; i < accounts.length; i++) {
            console.log("  Account:", accounts[i]);
            console.log("  Balance:", mockUSDC.balanceOf(accounts[i]));
        }
        console.log("======================");
    }

    /// @notice Check if address is a valid MockUSDC contract
    /// @param tokenAddress Address to check
    /// @return isValid True if address is a valid MockUSDC
    function isValidMockUSDC(
        address tokenAddress
    ) internal view returns (bool isValid) {
        if (tokenAddress.code.length == 0) return false;

        try MockUSDC(tokenAddress).decimals() returns (uint8 decimals) {
            if (decimals != 6) return false;

            try MockUSDC(tokenAddress).owner() returns (address) {
                return true; // Has owner() function, likely MockUSDC
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }
}
