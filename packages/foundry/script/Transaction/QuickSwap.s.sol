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
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {HookLibrary} from "../../src/libraries/HookLibrary.sol";
import "../../src/SwapRouterFixed.sol";

/// @title QuickSwap
/// @notice Uniswap V4 Swap Test Script for ETH/MockUSDC pool
/// @dev Tests swap functionality on a pool with DetoxHook MEV protection
contract QuickSwap is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Contract addresses - Matching GetPoolState.s.sol (DetoxHook Pool 3)
    address constant SWAP_ROUTER_FIXED_ADDRESS =
        0x6cBf35A8fBEc26b5e16c7774B41710e369C97CB7; // TODO: Update with deployed address
    address constant MOCKUSDC_ADDRESS =
        0x9D5A68fDFEcc14683324640D5e835936422a47b1; // MockUSDC (Pool 3)
    address constant DETOX_HOOK_ADDRESS =
        0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088; // DetoxHook (Pool 3)
    address constant POOL_MANAGER_ADDRESS =
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant POOL_SWAP_TEST_ADDRESS =
        0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7;

    // Chain ID for Arbitrum Sepolia
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    // Pool configuration - EXACTLY matching GetPoolState.s.sol (DetoxHook Pool 3)
    PoolKey poolKey =
        PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(MOCKUSDC_ADDRESS), // MockUSDC
            fee: 300, // 0.03% fee tier (Pool 3)
            tickSpacing: 40, // Tick spacing for 0.03% tier
            hooks: IHooks(DETOX_HOOK_ADDRESS) // DetoxHook for MEV protection
        });

    // Swap parameters
    uint256 constant SWAP_AMOUNT = 100 * 1e6; // 100 MockUSDC (6 decimals)

    /// @notice Main execution function
    function run() external {
        console.log("=== QuickSwap.s.sol - Uniswap V4 Swap Test ===");
        console.log("*** SCRIPT VERSION: FIXED ADDRESS RESOLUTION ***");
        console.log("Script: QuickSwap.s.sol");
        console.log("Network: Arbitrum Sepolia");
        console.log("Chain ID:", block.chainid);

        // 1. Safety Validations
        _performSafetyValidations();

        // Load environment variables
        address swapperWallet = vm.envAddress("SWAPPER_WALLET");
        uint256 swapperPrivateKey = vm.envUint("SWAPPER_PRIVATE_KEY");

        console.log("Swapper Wallet:", swapperWallet);
        console.log("");

        // 2. Pool Configuration Display
        _displayPoolConfiguration();

        // 3. Price and Liquidity Reporting
        _reportPriceAndLiquidity();

        // 4. Balance Checks
        _performBalanceChecks(swapperWallet);

        // 5. Token Management (Approvals)
        _handleTokenApprovals(swapperWallet, swapperPrivateKey);

        // 6. Execute Swap
        _executeSwap(swapperWallet, swapperPrivateKey);

        console.log("[SUCCESS] QuickSwap test completed successfully!");
    }

    /// @notice Perform safety validations before executing swap
    function _performSafetyValidations() internal view {
        console.log("=== Safety Validations ===");

        // Network check
        require(
            block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID,
            "Must run on Arbitrum Sepolia (421614)"
        );
        console.log("Network check: PASSED (Arbitrum Sepolia)");

        // Contract existence checks
        _validateContractExists(MOCKUSDC_ADDRESS, "MockUSDC");
        _validateContractExists(DETOX_HOOK_ADDRESS, "DetoxHook");
        _validateContractExists(POOL_MANAGER_ADDRESS, "PoolManager");
        _validateContractExists(POOL_SWAP_TEST_ADDRESS, "PoolSwapTest");
        _validateContractExists(SWAP_ROUTER_FIXED_ADDRESS, "SwapRouterFixed");

        console.log("Contract existence: ALL PASSED");
        console.log("");
    }

    /// @notice Display pool configuration details
    function _displayPoolConfiguration() internal view {
        console.log("=== Pool Configuration ===");

        console.log("Selected Pool: DetoxHook Pool 3 (ETH/MockUSDC 0.03% fee)");
        console.log("Currency0 (ETH):", Currency.unwrap(poolKey.currency0));
        console.log(
            "Currency1 (MockUSDC):",
            Currency.unwrap(poolKey.currency1)
        );
        console.log("Fee:", poolKey.fee, "bps");
        console.log("Tick Spacing:", uint256(int256(poolKey.tickSpacing)));
        console.log("Hooks (DetoxHook):", address(poolKey.hooks));

        // Calculate and display pool ID
        PoolId poolId = poolKey.toId();
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("");
    }

    /// @notice Report current price and liquidity state using StateLibrary
    function _reportPriceAndLiquidity() internal view {
        console.log("=== Price and Liquidity Reporting ===");

        // First, let's validate our pool configuration

        console.log("Pool Configuration Validation:");
        console.log(
            "- Selected Pool: DetoxHook Pool 3 (ETH/MockUSDC 0.03% fee)"
        );
        console.log("- Currency0 (ETH):", Currency.unwrap(poolKey.currency0));
        console.log(
            "- Currency1 (MockUSDC):",
            Currency.unwrap(poolKey.currency1)
        );
        console.log("- Fee:", poolKey.fee);
        console.log("- Tick Spacing:", uint256(int256(poolKey.tickSpacing)));
        console.log("- Hook Address:", address(poolKey.hooks));

        IPoolManager poolManager = IPoolManager(POOL_MANAGER_ADDRESS);
        PoolId poolId = poolKey.toId();
        console.log(
            "- Calculated Pool ID:",
            vm.toString(PoolId.unwrap(poolId))
        );

        // Use HookLibrary.getPoolState() directly (same as GetPoolState.s.sol)
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity
        ) = HookLibrary.getPoolState(poolManager, poolKey);

        console.log("Pool State Retrieved Successfully:");
        console.log("SqrtPriceX96:", sqrtPriceX96);
        console.log("Current Tick:", vm.toString(tick));
        console.log("Protocol Fee:", protocolFee);
        console.log("LP Fee:", lpFee);
        console.log("Current Liquidity:", liquidity);

        // Calculate human-readable price using HookLibrary (same as GetPoolState.s.sol)
        if (sqrtPriceX96 > 0) {
            uint256 humanPrice = HookLibrary.sqrtPriceToPrice(sqrtPriceX96);
            console.log("Human Pprice (USDC/ETH):", humanPrice);
            console.log("ETH/USDC Rate:", 1e36 / humanPrice);
        } else {
            console.log("Pool not initialized (sqrtPriceX96 = 0)");
        }
        console.log("");
    }

    /// @notice Check balances before swap execution
    function _performBalanceChecks(address swapperWallet) internal view {
        console.log("=== Balance Checks ===");

        uint256 ethBalance = swapperWallet.balance;
        uint256 usdcBalance = IERC20(MOCKUSDC_ADDRESS).balanceOf(swapperWallet);

        console.log("Swapper ETH balance:", ethBalance);
        console.log("Swapper MockUSDC balance:", usdcBalance);

        // Validate sufficient balances
        require(ethBalance > 0.01 ether, "Insufficient ETH for gas");
        require(usdcBalance >= SWAP_AMOUNT, "Insufficient MockUSDC for swap");

        console.log("Balance validation: PASSED");
        console.log("");
    }

    /// @notice Handle token approvals for SwapRouterFixed and PoolSwapTest
    function _handleTokenApprovals(
        address swapperWallet,
        uint256 swapperPrivateKey
    ) internal {
        console.log("=== Token Management ===");

        vm.startBroadcast(swapperPrivateKey);

        // CRITICAL FIX: Get the ACTUAL PoolSwapTest address from SwapRouterFixed
        SwapRouterFixed swapRouterTemp = SwapRouterFixed(
            payable(SWAP_ROUTER_FIXED_ADDRESS)
        );
        address actualPoolSwapTest = address(swapRouterTemp.poolSwapTest());

        console.log("FIXING APPROVAL ISSUE:");
        console.log("  Using ACTUAL PoolSwapTest:", actualPoolSwapTest);
        console.log("  (Not the deployment record address)");

        // Reset allowance to 0 first (some tokens require this)
        IERC20(MOCKUSDC_ADDRESS).approve(actualPoolSwapTest, 0);
        // Set max allowance for the CORRECT PoolSwapTest
        IERC20(MOCKUSDC_ADDRESS).approve(actualPoolSwapTest, type(uint256).max);
        console.log("[SUCCESS] MockUSDC approved for ACTUAL PoolSwapTest");

        // Also approve SwapRouterFixed for good measure (shouldn't be needed but ensures compatibility)
        IERC20(MOCKUSDC_ADDRESS).approve(SWAP_ROUTER_FIXED_ADDRESS, 0);
        IERC20(MOCKUSDC_ADDRESS).approve(
            SWAP_ROUTER_FIXED_ADDRESS,
            type(uint256).max
        );
        console.log("[SUCCESS] MockUSDC approved for SwapRouterFixed");

        // CRITICAL: Also approve PoolManager - this might be the missing piece!
        // In Uniswap V4, PoolManager is the core contract that handles token movements
        IERC20(MOCKUSDC_ADDRESS).approve(POOL_MANAGER_ADDRESS, 0);
        IERC20(MOCKUSDC_ADDRESS).approve(
            POOL_MANAGER_ADDRESS,
            type(uint256).max
        );
        console.log("[SUCCESS] MockUSDC approved for PoolManager");

        // Verify approvals (use ACTUAL PoolSwapTest address)
        uint256 poolSwapTestAllowance = IERC20(MOCKUSDC_ADDRESS).allowance(
            swapperWallet,
            actualPoolSwapTest
        );
        uint256 swapRouterAllowance = IERC20(MOCKUSDC_ADDRESS).allowance(
            swapperWallet,
            SWAP_ROUTER_FIXED_ADDRESS
        );

        uint256 poolManagerAllowance = IERC20(MOCKUSDC_ADDRESS).allowance(
            swapperWallet,
            POOL_MANAGER_ADDRESS
        );

        console.log(
            "Final MockUSDC allowance (ACTUAL PoolSwapTest):",
            poolSwapTestAllowance
        );
        console.log("  ACTUAL PoolSwapTest address:", actualPoolSwapTest);
        console.log(
            "Final MockUSDC allowance (SwapRouterFixed):",
            swapRouterAllowance
        );
        console.log(
            "Final MockUSDC allowance (PoolManager):",
            poolManagerAllowance
        );

        vm.stopBroadcast();
        console.log("");
    }

    /// @notice Execute the swap: 100 MockUSDC -> ETH
    function _executeSwap(
        address swapperWallet,
        uint256 swapperPrivateKey
    ) internal {
        console.log("=== Swap Execution ===");
        console.log("Swapping:", SWAP_AMOUNT, "MockUSDC -> ETH");
        console.log("Through SwapRouterFixed contract");

        // Record pre-swap balances
        uint256 preEthBalance = swapperWallet.balance;
        uint256 preUsdcBalance = IERC20(MOCKUSDC_ADDRESS).balanceOf(
            swapperWallet
        );

        console.log("Pre-swap ETH balance:", preEthBalance);
        console.log("Pre-swap MockUSDC balance:", preUsdcBalance);

        // Get SwapRouterFixed instance
        SwapRouterFixed swapRouter = SwapRouterFixed(
            payable(SWAP_ROUTER_FIXED_ADDRESS)
        );

        // CRITICAL DEBUG: Check what PoolSwapTest address SwapRouterFixed is using
        address actualPoolSwapTest = address(swapRouter.poolSwapTest());
        console.log("CRITICAL DEBUG:");
        console.log("  SwapRouterFixed address:", SWAP_ROUTER_FIXED_ADDRESS);
        console.log("  SwapRouterFixed.poolSwapTest():", actualPoolSwapTest);
        console.log("  Expected PoolSwapTest:", POOL_SWAP_TEST_ADDRESS);
        console.log(
            "  Do they match?",
            actualPoolSwapTest == POOL_SWAP_TEST_ADDRESS
        );

        // Prepare swap parameters
        SwapParams memory swapParams = SwapParams({
            zeroForOne: false, // MockUSDC -> ETH (currency1 -> currency0)
            amountSpecified: -int256(SWAP_AMOUNT), // Exact input (negative)
            sqrtPriceLimitX96: 0 // No price limit
        });

        // Debug: Check allowances right before swap (use ACTUAL PoolSwapTest)
        uint256 debugPoolSwapAllowance = IERC20(MOCKUSDC_ADDRESS).allowance(
            swapperWallet,
            actualPoolSwapTest
        );
        uint256 debugSwapRouterAllowance = IERC20(MOCKUSDC_ADDRESS).allowance(
            swapperWallet,
            SWAP_ROUTER_FIXED_ADDRESS
        );
        uint256 debugPoolManagerAllowance = IERC20(MOCKUSDC_ADDRESS).allowance(
            swapperWallet,
            POOL_MANAGER_ADDRESS
        );
        console.log("DEBUG - Right before swap:");
        console.log("  PoolSwapTest allowance:", debugPoolSwapAllowance);
        console.log("  SwapRouterFixed allowance:", debugSwapRouterAllowance);
        console.log("  PoolManager allowance:", debugPoolManagerAllowance);
        console.log("  Required amount:", SWAP_AMOUNT);

        // CRITICAL DEBUG: Complete allowance audit
        console.log("COMPLETE ALLOWANCE AUDIT:");
        console.log(
            "  Swapper->ACTUAL PoolSwapTest:",
            IERC20(MOCKUSDC_ADDRESS).allowance(
                swapperWallet,
                actualPoolSwapTest
            )
        );
        console.log(
            "  Swapper->SwapRouterFixed:",
            IERC20(MOCKUSDC_ADDRESS).allowance(
                swapperWallet,
                SWAP_ROUTER_FIXED_ADDRESS
            )
        );
        console.log(
            "  Swapper->PoolManager:",
            IERC20(MOCKUSDC_ADDRESS).allowance(
                swapperWallet,
                POOL_MANAGER_ADDRESS
            )
        );

        // Check if SwapRouterFixed needs internal approvals
        console.log(
            "  SwapRouterFixed->ACTUAL PoolSwapTest:",
            IERC20(MOCKUSDC_ADDRESS).allowance(
                SWAP_ROUTER_FIXED_ADDRESS,
                actualPoolSwapTest
            )
        );
        console.log(
            "  SwapRouterFixed->PoolManager:",
            IERC20(MOCKUSDC_ADDRESS).allowance(
                SWAP_ROUTER_FIXED_ADDRESS,
                POOL_MANAGER_ADDRESS
            )
        );

        // Execute swap
        vm.startBroadcast(swapperPrivateKey);

        // BYPASS SWAPROUTERFIXED: Call PoolSwapTest directly (like working tests do)
        console.log(
            "BYPASSING SwapRouterFixed - calling PoolSwapTest directly"
        );

        PoolSwapTest poolSwapTest = PoolSwapTest(actualPoolSwapTest);

        // Create the pool key for this call (use the global poolKey)
        // Note: Using the global poolKey variable defined earlier

        // Create swap parameters for direct PoolSwapTest call
        SwapParams memory directSwapParams = SwapParams({
            zeroForOne: false, // MockUSDC -> ETH (currency1 -> currency0)
            amountSpecified: -int256(SWAP_AMOUNT), // Exact input (negative)
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1 // Proper price limit
        });

        // Create test settings (same as working tests)
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        try
            poolSwapTest.swap(
                poolKey,
                directSwapParams,
                testSettings,
                "" // updateData (empty for now)
            )
        returns (BalanceDelta delta) {
            console.log("[SUCCESS] Swap executed successfully!");
            console.log(
                "Balance Delta:",
                vm.toString(BalanceDelta.unwrap(delta))
            );
        } catch Error(string memory reason) {
            console.log("[ERROR] Swap failed:");
            console.log("Reason:", reason);
            vm.stopBroadcast();
            revert("Swap execution failed");
        } catch (bytes memory lowLevelData) {
            console.log("[ERROR] Swap failed with low-level error");
            console.log("Error data length:", lowLevelData.length);
            if (lowLevelData.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelData);
                console.log("Error selector:", vm.toString(errorSelector));
            }
            vm.stopBroadcast();
            revert("Swap execution failed with low-level error");
        }

        vm.stopBroadcast();

        // Record post-swap balances
        uint256 postEthBalance = swapperWallet.balance;
        uint256 postUsdcBalance = IERC20(MOCKUSDC_ADDRESS).balanceOf(
            swapperWallet
        );

        console.log("=== Swap Results ===");
        console.log("Post-swap ETH balance:", postEthBalance);
        console.log("Post-swap MockUSDC balance:", postUsdcBalance);
        console.log("ETH gained:", postEthBalance - preEthBalance);
        console.log("MockUSDC spent:", preUsdcBalance - postUsdcBalance);
        console.log("");
    }

    /// @notice Validate that a contract exists at the given address
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
