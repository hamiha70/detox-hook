// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/LiquidityRouter.sol";

/// @title ProvideLiquidity
/// @notice Script to provide liquidity using LiquidityRouter
/// @dev Uses LIQUIDITY_PROVIDER_WALLET and LIQUIDITY_PROVIDER_PRIVATE_KEY environment variables
contract ProvideLiquidity is Script {
    using PoolIdLibrary for PoolKey;

    // Contract addresses
    address constant LIQUIDITY_ROUTER_ADDRESS =
        0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a;
    address constant MOCKUSDC_ADDRESS =
        0x9D5A68fDFEcc14683324640D5e835936422a47b1;
    address constant DETOX_HOOK_ADDRESS =
        0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088;

    // Chain ID for Arbitrum Sepolia
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    // Pool configuration - EXACTLY as specified
    PoolKey poolKey =
        PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(MOCKUSDC_ADDRESS),
            fee: 300,
            tickSpacing: 40,
            hooks: IHooks(DETOX_HOOK_ADDRESS)
        });

    // Liquidity parameters
    int24 constant TICK_LOWER = -85160;
    int24 constant TICK_UPPER = -77160;
    int256 constant LIQUIDITY_DELTA = 10;
    bytes32 constant SALT =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    function run() external {
        console.log("=== LiquidityRouter Liquidity Provision ===");
        console.log("Script: ProvideLiquidity.s.sol");
        console.log("Network: Arbitrum Sepolia");
        console.log("Chain ID:", block.chainid);

        // Validate we're on the correct network
        require(
            block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID,
            "Must run on Arbitrum Sepolia (421614)"
        );

        // Load environment variables
        address liquidityProviderWallet = vm.envAddress(
            "LIQUIDITY_PROVIDER_WALLET"
        );
        uint256 liquidityProviderPrivateKey = vm.envUint(
            "LIQUIDITY_PROVIDER_PRIVATE_KEY"
        );

        // Validate environment
        require(
            liquidityProviderWallet != address(0),
            "LIQUIDITY_PROVIDER_WALLET not set"
        );
        require(
            liquidityProviderPrivateKey != 0,
            "LIQUIDITY_PROVIDER_PRIVATE_KEY not set"
        );

        console.log("Liquidity Provider Wallet:", liquidityProviderWallet);
        console.log("LiquidityRouter:", LIQUIDITY_ROUTER_ADDRESS);
        console.log("MockUSDC:", MOCKUSDC_ADDRESS);
        console.log("DetoxHook:", DETOX_HOOK_ADDRESS);
        console.log("");

        // Validate contract addresses exist
        _validateContractExists(LIQUIDITY_ROUTER_ADDRESS, "LiquidityRouter");
        _validateContractExists(MOCKUSDC_ADDRESS, "MockUSDC");
        _validateContractExists(DETOX_HOOK_ADDRESS, "DetoxHook");

        // Display pool configuration
        console.log("=== Pool Configuration ===");
        console.log("Currency0 (ETH):", Currency.unwrap(poolKey.currency0));
        console.log(
            "Currency1 (MockUSDC):",
            Currency.unwrap(poolKey.currency1)
        );
        console.log("Fee (0.03%):", poolKey.fee);
        console.log("Tick Spacing:", uint256(int256(poolKey.tickSpacing)));
        console.log("Hooks (DetoxHook):", address(poolKey.hooks));

        // Calculate and display pool ID
        PoolId poolId = poolKey.toId();
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("");

        // Display liquidity parameters
        console.log("=== Liquidity Parameters ===");
        console.log("Tick Lower:", vm.toString(TICK_LOWER));
        console.log("Tick Upper:", vm.toString(TICK_UPPER));
        console.log("Liquidity Delta:", vm.toString(LIQUIDITY_DELTA));
        console.log("Salt:", vm.toString(SALT));

        // Verify tick alignment
        require(
            TICK_LOWER % poolKey.tickSpacing == 0,
            "Tick lower not aligned with tick spacing"
        );
        require(
            TICK_UPPER % poolKey.tickSpacing == 0,
            "Tick upper not aligned with tick spacing"
        );
        require(TICK_LOWER < TICK_UPPER, "Invalid tick range");
        console.log("Tick alignment: VALID");
        console.log("");

        // Check deployer balance
        uint256 providerEthBalance = liquidityProviderWallet.balance;
        uint256 providerUsdcBalance = IERC20(MOCKUSDC_ADDRESS).balanceOf(
            liquidityProviderWallet
        );
        console.log("Provider ETH balance:", providerEthBalance);
        console.log("Provider MockUSDC balance:", providerUsdcBalance);
        require(
            providerEthBalance > 0.001 ether,
            "Insufficient ETH balance for transaction"
        );
        require(providerUsdcBalance > 0, "Insufficient MockUSDC balance");

        // Create LiquidityRouter contract instance
        LiquidityRouter liquidityRouter = LiquidityRouter(
            payable(LIQUIDITY_ROUTER_ADDRESS)
        );

        // Check allowances
        console.log("=== Checking Token Approvals ===");
        uint256 allowance = IERC20(MOCKUSDC_ADDRESS).allowance(
            liquidityProviderWallet,
            LIQUIDITY_ROUTER_ADDRESS
        );
        console.log("Current MockUSDC allowance:", allowance);

        // Start broadcasting transactions
        vm.startBroadcast(liquidityProviderPrivateKey);

        // Approve MockUSDC if needed
        if (allowance < type(uint256).max / 2) {
            console.log("Approving MockUSDC for LiquidityRouter...");
            IERC20(MOCKUSDC_ADDRESS).approve(
                LIQUIDITY_ROUTER_ADDRESS,
                type(uint256).max
            );
            console.log("[SUCCESS] MockUSDC approved for LiquidityRouter");
        }

        // Approve pool tokens for PoolModifyLiquidityTest
        console.log("Approving pool tokens for PoolModifyLiquidityTest...");
        liquidityRouter.approvePoolTokens(poolKey);
        console.log("[SUCCESS] Pool tokens approved");

        console.log("=== Adding Liquidity ===");
        console.log("Calling addLiquidity...");

        try
            liquidityRouter.addLiquidity{value: 0.001 ether}(
                poolKey,
                TICK_LOWER,
                TICK_UPPER,
                LIQUIDITY_DELTA,
                SALT,
                "" // updateData (empty for now)
            )
        returns (BalanceDelta delta) {
            console.log("[SUCCESS] Liquidity added successfully!");
            console.log(
                "Balance Delta:",
                vm.toString(BalanceDelta.unwrap(delta))
            );
        } catch Error(string memory reason) {
            console.log("[ERROR] Liquidity addition failed:");
            console.log("Reason:", reason);
            revert("Liquidity addition failed");
        } catch (bytes memory lowLevelData) {
            console.log(
                "[ERROR] Liquidity addition failed with low-level error"
            );
            console.log("Error data length:", lowLevelData.length);
            if (lowLevelData.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelData);
                console.log("Error selector:", vm.toString(errorSelector));
            }
            revert("Liquidity addition failed with low-level error");
        }

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("=== Final Balances ===");
        uint256 finalEthBalance = liquidityProviderWallet.balance;
        uint256 finalUsdcBalance = IERC20(MOCKUSDC_ADDRESS).balanceOf(
            liquidityProviderWallet
        );
        console.log("Final ETH balance:", finalEthBalance);
        console.log("Final MockUSDC balance:", finalUsdcBalance);
        console.log("ETH used:", providerEthBalance - finalEthBalance);
        console.log("MockUSDC used:", providerUsdcBalance - finalUsdcBalance);

        console.log("");
        console.log("[SUCCESS] Liquidity provision completed successfully!");
        console.log("Pool ready for swaps with added liquidity!");
    }

    function _validateContractExists(
        address contractAddress,
        string memory contractName
    ) internal view {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(contractAddress)
        }
        require(
            codeSize > 0,
            string(abi.encodePacked(contractName, " contract not found"))
        );
        console.log("Validated", contractName, "at:", contractAddress);
    }
}
