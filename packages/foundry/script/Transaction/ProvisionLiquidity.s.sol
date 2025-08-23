// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LiquidityRouter} from "../src/LiquidityRouter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @title ProvisionLiquidity
/// @notice Script to provision liquidity using the deployed LiquidityRouter contract
/// @dev Uses LIQUIDITY_PROVIDER_WALLET and LIQUIDITY_PROVIDER_PRIVATE_KEY environment variables
contract ProvisionLiquidity is Script {
    // Contract addresses
    address constant LIQUIDITY_ROUTER_ADDRESS =
        0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a;
    address constant MOCK_USDC_ADDRESS =
        0x9D5A68fDFEcc14683324640D5e835936422a47b1;
    address constant DETOX_HOOK_ADDRESS =
        0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088;

    // Pool configuration
    PoolKey poolKey =
        PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(MOCK_USDC_ADDRESS), // MockUSDC
            fee: 500,
            tickSpacing: 60,
            hooks: IHooks(DETOX_HOOK_ADDRESS)
        });

    // Liquidity parameters
    int24 constant TICK_LOWER = 70020; // Aligned with tick spacing (70020 / 60 = 1167)
    int24 constant TICK_UPPER = 89940; // Aligned with tick spacing (89940 / 60 = 1499)
    int256 constant LIQUIDITY_DELTA = 1000; // Amount of liquidity to add
    bytes32 constant SALT =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    // Chain ID for Arbitrum Sepolia
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    // ETH amount to send with transaction (for gas and ETH portion of liquidity)
    uint256 constant ETH_AMOUNT = 0.01 ether;

    function run() external {
        console.log("=== LiquidityRouter Liquidity Provision ===");
        console.log("Script: ProvisionLiquidity.s.sol");
        console.log("Network: Arbitrum Sepolia");
        console.log("Chain ID:", block.chainid);

        // Validate we're on the correct network
        require(
            block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID,
            "Must run on Arbitrum Sepolia (421614)"
        );

        // Load environment variables
        address liquidityProvider = vm.envAddress("LIQUIDITY_PROVIDER_WALLET");
        uint256 liquidityProviderKey = vm.envUint(
            "LIQUIDITY_PROVIDER_PRIVATE_KEY"
        );

        // Validate environment
        require(
            liquidityProvider != address(0),
            "LIQUIDITY_PROVIDER_WALLET not set"
        );
        require(
            liquidityProviderKey != 0,
            "LIQUIDITY_PROVIDER_PRIVATE_KEY not set"
        );

        console.log("Liquidity Provider:", liquidityProvider);
        console.log("LiquidityRouter:", LIQUIDITY_ROUTER_ADDRESS);
        console.log("MockUSDC:", MOCK_USDC_ADDRESS);
        console.log("DetoxHook:", DETOX_HOOK_ADDRESS);
        console.log("");

        // Validate contract addresses exist
        _validateContractExists(LIQUIDITY_ROUTER_ADDRESS, "LiquidityRouter");
        _validateContractExists(MOCK_USDC_ADDRESS, "MockUSDC");
        _validateContractExists(DETOX_HOOK_ADDRESS, "DetoxHook");

        // Display pool configuration
        console.log("=== Pool Configuration ===");
        console.log("Currency0 (ETH):", Currency.unwrap(poolKey.currency0));
        console.log(
            "Currency1 (MockUSDC):",
            Currency.unwrap(poolKey.currency1)
        );
        console.log("Fee:", poolKey.fee);
        console.log("Tick Spacing:", uint256(int256(poolKey.tickSpacing)));
        console.log("Hooks:", address(poolKey.hooks));
        console.log("");

        // Display liquidity parameters
        console.log("=== Liquidity Parameters ===");
        console.log("Tick Lower:", vm.toString(TICK_LOWER));
        console.log("Tick Upper:", vm.toString(TICK_UPPER));
        console.log("Liquidity Delta:", vm.toString(LIQUIDITY_DELTA));
        console.log("Salt:", vm.toString(SALT));
        console.log("ETH Amount:", ETH_AMOUNT);
        console.log("");

        // Check initial balances
        _checkBalances(liquidityProvider, "BEFORE");

        // Create contract instances
        LiquidityRouter liquidityRouter = LiquidityRouter(
            payable(LIQUIDITY_ROUTER_ADDRESS)
        );
        IERC20 mockUSDC = IERC20(MOCK_USDC_ADDRESS);

        // Start broadcasting transactions
        vm.startBroadcast(liquidityProviderKey);

        // Step 1: Approve MockUSDC for LiquidityRouter (if needed)
        console.log("=== Step 1: Token Approval ===");
        _approveTokenIfNeeded(
            mockUSDC,
            liquidityProvider,
            LIQUIDITY_ROUTER_ADDRESS
        );

        // Step 2: Approve pool tokens for PoolModifyLiquidityTest (via LiquidityRouter)
        console.log("=== Step 2: Pool Token Approval ===");
        try liquidityRouter.approvePoolTokens(poolKey) {
            console.log("[SUCCESS] Pool tokens approved via LiquidityRouter");
        } catch Error(string memory reason) {
            console.log("[WARNING] Pool token approval failed:", reason);
        }

        // Step 3: Add liquidity
        console.log("=== Step 3: Adding Liquidity ===");
        try
            liquidityRouter.addLiquidity{value: ETH_AMOUNT}(
                poolKey,
                TICK_LOWER,
                TICK_UPPER,
                LIQUIDITY_DELTA,
                SALT,
                "" // Empty update data
            )
        returns (BalanceDelta delta) {
            console.log("[SUCCESS] Liquidity added successfully!");
            console.log(
                "Balance Delta:",
                vm.toString(BalanceDelta.unwrap(delta))
            );

            // Decode the delta for better understanding
            int128 amount0Delta = delta.amount0();
            int128 amount1Delta = delta.amount1();
            console.log("Amount0 Delta (ETH):", vm.toString(amount0Delta));
            console.log("Amount1 Delta (MockUSDC):", vm.toString(amount1Delta));
        } catch Error(string memory reason) {
            console.log("[ERROR] Liquidity addition failed:", reason);
            vm.stopBroadcast();
            revert(string.concat("Liquidity provision failed: ", reason));
        } catch (bytes memory lowLevelData) {
            console.log(
                "[ERROR] Liquidity addition failed with low-level error"
            );
            console.log("Error data length:", lowLevelData.length);
            if (lowLevelData.length >= 4) {
                console.log(
                    "Error selector:",
                    vm.toString(bytes4(lowLevelData))
                );
            }
            vm.stopBroadcast();
            revert("Liquidity provision failed with low-level error");
        }

        // Stop broadcasting
        vm.stopBroadcast();

        // Check final balances
        _checkBalances(liquidityProvider, "AFTER");

        console.log("=== Liquidity Provision Completed Successfully ===");
        console.log("Pool: ETH/MockUSDC (0.05% fee)");
        console.log(
            "Position: Ticks",
            vm.toString(TICK_LOWER),
            "to",
            vm.toString(TICK_UPPER)
        );
        console.log("Liquidity Added:", vm.toString(LIQUIDITY_DELTA));
        console.log("DetoxHook: Active for MEV protection");
        console.log("");
        console.log("[SUCCESS] Liquidity provision script completed!");
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

        console.log("Validated", contractName, "at:", contractAddress);
    }

    /// @notice Check and display wallet balances
    /// @param wallet The wallet address to check
    /// @param stage The stage identifier (BEFORE/AFTER)
    function _checkBalances(address wallet, string memory stage) internal view {
        console.log("=== Balances", stage, "===");

        // ETH balance
        uint256 ethBalance = wallet.balance;
        console.log("ETH Balance:", ethBalance);

        // MockUSDC balance
        try IERC20(MOCK_USDC_ADDRESS).balanceOf(wallet) returns (
            uint256 usdcBalance
        ) {
            console.log("MockUSDC Balance:", usdcBalance);
        } catch {
            console.log("MockUSDC Balance: [Could not query]");
        }

        console.log("");
    }

    /// @notice Approve token for spender if allowance is insufficient
    /// @param token The ERC20 token contract
    /// @param owner The token owner
    /// @param spender The spender address
    function _approveTokenIfNeeded(
        IERC20 token,
        address owner,
        address spender
    ) internal {
        // Check current allowance
        uint256 currentAllowance = token.allowance(owner, spender);
        console.log("Current MockUSDC allowance:", currentAllowance);

        // If allowance is less than a reasonable amount, approve max
        if (currentAllowance < type(uint256).max / 2) {
            console.log("Approving MockUSDC for LiquidityRouter...");

            // Reset to 0 first (some tokens require this)
            token.approve(spender, 0);

            // Approve maximum amount
            bool success = token.approve(spender, type(uint256).max);
            require(success, "MockUSDC approval failed");

            console.log("[SUCCESS] MockUSDC approved for maximum amount");
        } else {
            console.log("[INFO] MockUSDC already has sufficient allowance");
        }
    }

    /// @notice Get estimated gas cost for the operation
    function getEstimatedGasCost()
        external
        pure
        returns (uint256 gasEstimate, uint256 costEstimate)
    {
        gasEstimate = 800000; // Estimated gas for complete operation
        costEstimate = 0.0002 ether; // Estimated cost at typical gas prices
        return (gasEstimate, costEstimate);
    }
}
