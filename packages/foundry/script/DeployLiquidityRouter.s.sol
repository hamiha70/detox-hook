// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LiquidityRouter} from "../src/LiquidityRouter.sol";
import {ChainAddresses} from "./ChainAddresses.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DeployLiquidityRouter
/// @notice Deployment script for LiquidityRouter contract on Arbitrum Sepolia
/// @dev Uses DEPLOYMENT_WALLET environment variable for deployment and includes token approval testing
contract DeployLiquidityRouter is Script {
    // Arbitrum Sepolia addresses
    address constant POOL_MANAGER_ADDRESS =
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant POOL_MODIFY_LIQUIDITY_TEST_ADDRESS =
        0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7;

    // Test token addresses
    address constant MOCK_USDC_ADDRESS =
        0x9D5A68fDFEcc14683324640D5e835936422a47b1;
    address constant ETH_ADDRESS = 0x0000000000000000000000000000000000000000;

    // Chain ID for Arbitrum Sepolia
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    // Deployment configuration
    struct DeploymentConfig {
        address deployer;
        address poolManager;
        address poolModifyLiquidityTest;
        uint256 chainId;
    }

    // Events
    event LiquidityRouterDeployed(
        address indexed liquidityRouter,
        address indexed deployer,
        address poolManager,
        address poolModifyLiquidityTest,
        uint256 chainId
    );

    event TokenApprovalTested(
        address indexed token,
        address indexed spender,
        uint256 allowance,
        bool success
    );

    function run() external {
        // Load environment variables
        address deployerWallet = vm.envAddress("DEPLOYMENT_WALLET");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");

        // Validate environment
        require(deployerWallet != address(0), "DEPLOYMENT_WALLET not set");
        require(deployerPrivateKey != 0, "DEPLOYMENT_PRIVATE_KEY not set");

        // Create deployment configuration
        DeploymentConfig memory config = DeploymentConfig({
            deployer: deployerWallet,
            poolManager: POOL_MANAGER_ADDRESS,
            poolModifyLiquidityTest: POOL_MODIFY_LIQUIDITY_TEST_ADDRESS,
            chainId: block.chainid
        });

        // Validate we're on the correct network
        require(
            config.chainId == ARBITRUM_SEPOLIA_CHAIN_ID,
            "Must deploy on Arbitrum Sepolia (421614)"
        );

        console.log("=== LiquidityRouter Enhanced Deployment ===");
        console.log("Network: Arbitrum Sepolia");
        console.log("Chain ID:", config.chainId);
        console.log("Deployer:", config.deployer);
        console.log("PoolManager:", config.poolManager);
        console.log("PoolModifyLiquidityTest:", config.poolModifyLiquidityTest);
        console.log("MockUSDC:", MOCK_USDC_ADDRESS);
        console.log("");

        // Validate contract addresses exist
        _validateContractExists(config.poolManager, "PoolManager");
        _validateContractExists(
            config.poolModifyLiquidityTest,
            "PoolModifyLiquidityTest"
        );
        _validateContractExists(MOCK_USDC_ADDRESS, "MockUSDC");

        // Check deployer balance
        uint256 deployerBalance = deployerWallet.balance;
        console.log("Deployer ETH balance:", deployerBalance);
        require(
            deployerBalance > 0.001 ether,
            "Insufficient ETH balance for deployment"
        );

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy LiquidityRouter
        LiquidityRouter liquidityRouter = new LiquidityRouter(
            config.poolModifyLiquidityTest,
            config.poolManager
        );

        // Stop broadcasting for post-deployment validation
        vm.stopBroadcast();

        // Validate deployment
        require(
            address(liquidityRouter) != address(0),
            "LiquidityRouter deployment failed"
        );
        require(
            liquidityRouter.getPoolManager() == config.poolManager,
            "PoolManager address mismatch"
        );
        require(
            liquidityRouter.getPoolModifyLiquidityTest() ==
                config.poolModifyLiquidityTest,
            "PoolModifyLiquidityTest address mismatch"
        );

        // Test new functionality
        console.log("=== Testing New Token Approval Functionality ===");
        _testTokenApprovalFunctionality(liquidityRouter);

        // Test receive function
        _testReceiveFunction(
            liquidityRouter,
            deployerWallet,
            deployerPrivateKey
        );

        // Emit deployment event
        emit LiquidityRouterDeployed(
            address(liquidityRouter),
            config.deployer,
            config.poolManager,
            config.poolModifyLiquidityTest,
            config.chainId
        );

        // Log deployment success
        console.log("=== Deployment Successful ===");
        console.log("LiquidityRouter deployed at:", address(liquidityRouter));
        console.log(
            "Gas used estimate: ~1,200,000 gas (increased due to new features)"
        );
        console.log("Deployment cost estimate: ~0.0003 ETH");
        console.log("");

        // Log contract verification info
        console.log("=== Contract Verification ===");
        console.log("Contract Address:", address(liquidityRouter));
        console.log("Constructor Args:");
        console.log(
            "  poolModifyLiquidityTest:",
            config.poolModifyLiquidityTest
        );
        console.log("  poolManager:", config.poolManager);
        console.log("");

        // Log new features
        console.log("=== New Features Available ===");
        console.log(
            "1. approveToken(token, amount) - Approve specific amounts"
        );
        console.log(
            "2. approvePoolTokens(poolKey) - Approve max for pool currencies"
        );
        console.log(
            "3. prepareTokens(poolKey, liquidityDelta) - Transfer tokens to router"
        );
        console.log(
            "4. emergencyWithdraw(token, amount) - Recover stuck tokens"
        );
        console.log("5. Automatic approval management during operations");
        console.log("6. Enhanced ETH handling with receive/fallback");
        console.log("");

        // Log usage instructions
        console.log("=== Enhanced Usage Instructions ===");
        console.log("1. Verify contract on Blockscout:");
        console.log(
            "   https://arbitrum-sepolia.blockscout.com/address/%s",
            address(liquidityRouter)
        );
        console.log("2. Approve tokens before liquidity operations:");
        console.log("   liquidityRouter.approvePoolTokens(poolKey)");
        console.log("3. Test with small liquidity operations");
        console.log("4. Use with DetoxHook pools for MEV protection");
        console.log("5. Monitor token approvals and balances");
        console.log("");

        // Save deployment info to file (for external tooling)
        _saveDeploymentInfo(address(liquidityRouter), config);

        console.log(
            "[SUCCESS] Enhanced LiquidityRouter deployment completed successfully!"
        );
    }

    /// @notice Test token approval functionality
    /// @param liquidityRouter The deployed LiquidityRouter contract
    function _testTokenApprovalFunctionality(
        LiquidityRouter liquidityRouter
    ) internal {
        console.log("Testing token approval functionality...");

        // Create a test pool key
        PoolKey memory testPoolKey = PoolKey({
            currency0: Currency.wrap(ETH_ADDRESS),
            currency1: Currency.wrap(MOCK_USDC_ADDRESS),
            fee: 500,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Test 1: Check initial allowances (should be 0)
        try
            IERC20(MOCK_USDC_ADDRESS).allowance(
                address(liquidityRouter),
                POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
            )
        returns (uint256 initialAllowance) {
            console.log("Initial USDC allowance:", initialAllowance);
            require(initialAllowance == 0, "Initial allowance should be 0");
        } catch {
            console.log(
                "[WARNING] Could not check initial allowance - MockUSDC may not be deployed"
            );
        }

        // Test 2: Test explicit approval function
        try liquidityRouter.approvePoolTokens(testPoolKey) {
            console.log("[SUCCESS] approvePoolTokens executed successfully");

            // Verify approval was set
            try
                IERC20(MOCK_USDC_ADDRESS).allowance(
                    address(liquidityRouter),
                    POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
                )
            returns (uint256 finalAllowance) {
                console.log("Final USDC allowance:", finalAllowance);
                bool approvalSuccess = finalAllowance == type(uint256).max;
                emit TokenApprovalTested(
                    MOCK_USDC_ADDRESS,
                    POOL_MODIFY_LIQUIDITY_TEST_ADDRESS,
                    finalAllowance,
                    approvalSuccess
                );

                if (approvalSuccess) {
                    console.log("[SUCCESS] Token approval set to maximum");
                } else {
                    console.log("[WARNING] Token approval not set to maximum");
                }
            } catch {
                console.log("[WARNING] Could not verify final allowance");
            }
        } catch Error(string memory reason) {
            console.log("[WARNING] approvePoolTokens failed:", reason);
        }

        console.log("Token approval functionality testing completed");
    }

    /// @notice Test receive function
    /// @param liquidityRouter The deployed LiquidityRouter contract
    /// @param deployerWallet The deployer wallet address
    /// @param deployerPrivateKey The deployer private key
    function _testReceiveFunction(
        LiquidityRouter liquidityRouter,
        address deployerWallet,
        uint256 deployerPrivateKey
    ) internal {
        console.log("Testing ETH receive functionality...");

        uint256 testAmount = 0.001 ether;

        // Check if deployer has enough balance
        if (deployerWallet.balance < testAmount) {
            console.log("[SKIP] Insufficient balance to test receive function");
            return;
        }

        uint256 routerBalanceBefore = address(liquidityRouter).balance;

        vm.startBroadcast(deployerPrivateKey);

        // Send ETH to the contract
        (bool success, ) = payable(address(liquidityRouter)).call{
            value: testAmount
        }("");

        if (success) {
            uint256 routerBalanceAfter = address(liquidityRouter).balance;

            if (routerBalanceAfter == routerBalanceBefore + testAmount) {
                console.log("[SUCCESS] ETH receive function works correctly");
                console.log("Router ETH balance:", routerBalanceAfter);
            } else {
                console.log("[WARNING] ETH receive function may have issues");
            }
        } else {
            console.log("[WARNING] ETH transfer test failed");
        }

        vm.stopBroadcast();

        console.log("ETH receive functionality testing completed");
    }

    /// @notice Validate that a contract exists at the given address
    /// @param contractAddress The address to check
    /// @param contractName The name of the contract for error reporting
    function _validateContractExists(
        address contractAddress,
        string memory contractName
    ) internal view {
        require(
            contractAddress != address(0),
            string.concat(contractName, " address is zero")
        );

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(contractAddress)
        }
        require(
            codeSize > 0,
            string.concat("No contract found at ", contractName, " address")
        );

        console.log("Validated %s at: %s", contractName, contractAddress);
    }

    /// @notice Save deployment information for external tooling
    /// @param liquidityRouterAddress The deployed LiquidityRouter address
    /// @param config The deployment configuration
    function _saveDeploymentInfo(
        address liquidityRouterAddress,
        DeploymentConfig memory config
    ) internal {
        // This would typically write to a JSON file, but we'll just log for now
        console.log("=== Enhanced Deployment Info (JSON Format) ===");
        console.log("{");
        console.log('  "contract": "LiquidityRouter",');
        console.log('  "version": "v2.0.0-enhanced",');
        console.log('  "address": "%s",', liquidityRouterAddress);
        console.log('  "deployer": "%s",', config.deployer);
        console.log('  "chainId": %s,', config.chainId);
        console.log('  "network": "arbitrum-sepolia",');
        console.log('  "poolManager": "%s",', config.poolManager);
        console.log(
            '  "poolModifyLiquidityTest": "%s",',
            config.poolModifyLiquidityTest
        );
        console.log('  "mockUSDC": "%s",', MOCK_USDC_ADDRESS);
        console.log('  "features": [');
        console.log('    "token-approval-management",');
        console.log('    "automatic-approvals",');
        console.log('    "eth-receive-support",');
        console.log('    "emergency-withdraw",');
        console.log('    "prepare-tokens"');
        console.log("  ],");
        console.log('  "timestamp": "%s",', block.timestamp);
        console.log('  "blockNumber": %s', block.number);
        console.log("}");
    }

    /// @notice Get deployment estimate (for planning purposes)
    function getDeploymentEstimate()
        external
        pure
        returns (uint256 gasEstimate, uint256 costEstimate)
    {
        gasEstimate = 1200000; // Increased estimate due to new features
        costEstimate = 0.0003 ether; // Increased cost estimate
        return (gasEstimate, costEstimate);
    }
}
