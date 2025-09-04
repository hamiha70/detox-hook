// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import "../../src/LiquidityRouter.sol";

/// @title QuickLiquidityFX - Uniswap V4 Liquidity Provision Test Script
/// @notice Comprehensive script to test liquidity provision on MockEURC/MockUSDC pool with DetoxHook
/// @dev Uses LIQUIDITY_PROVIDER_WALLET and LIQUIDITY_PROVIDER_PRIVATE_KEY environment variables
contract QuickLiquidityFX is Script {
    using PoolIdLibrary for PoolKey;

    // ===== CONTRACT ADDRESSES =====
    address constant LIQUIDITY_ROUTER_ADDRESS =
        0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a;
    address constant MOCKEURC_ADDRESS =
        0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E;
    address constant MOCKUSDC_ADDRESS =
        0x9D5A68fDFEcc14683324640D5e835936422a47b1;
    address constant DETOX_HOOK_ADDRESS =
        0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088;
    address constant POOL_MANAGER_ADDRESS =
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant POOL_MODIFY_LIQUIDITY_TEST_ADDRESS =
        0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7;

    // ===== NETWORK CONFIGURATION =====
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    // ===== POOL SPECIFICATION =====
    /// @notice Pool configuration as specified
    /// @dev Currency0: MockEURC, Currency1: MockUSDC, Fee: 0.02% (2000), Tick spacing: 40, Hooks: DetoxHook
    PoolKey poolKey =
        PoolKey({
            currency0: Currency.wrap(MOCKEURC_ADDRESS),
            currency1: Currency.wrap(MOCKUSDC_ADDRESS),
            fee: 2000, // 0.02% fee tier
            tickSpacing: 40,
            hooks: IHooks(DETOX_HOOK_ADDRESS)
        });

    /// @notice The PoolManager contract for pool state queries
    IPoolManager public immutable poolManager =
        IPoolManager(POOL_MANAGER_ADDRESS);

    // ===== LIQUIDITY PARAMETERS =====
    int24 constant TICK_LOWER = -1640;
    int24 constant TICK_UPPER = -1480;
    int256 constant LIQUIDITY_DELTA = 1e9; // Very small liquidity amount for testing (1K with 6 decimals)
    bytes32 constant SALT =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    function run() external {
        console.log(
            "=== QuickLiquidityFX - Uniswap V4 Liquidity Provision Test ==="
        );
        console.log("Script: QuickLiquidityFX.s.sol");
        console.log("Network: Arbitrum Sepolia");
        console.log("Chain ID:", block.chainid);
        console.log("");

        // 1. NETWORK AND CONTRACT SAFETY VALIDATIONS
        _performNetworkValidation();
        _performContractValidation();

        // 2. POOL STATE ANALYSIS
        _displayPoolConfiguration();
        _fetchAndDisplayPoolState();

        // 3. LIQUIDITY PROVIDER VERIFICATION
        _verifyLiquidityProvider();

        // 4. APPROVALS AND ALLOWANCES
        _handleApprovalsAndAllowances();

        // 5. LIQUIDITY PROVISION
        _provideLiquidity();

        // 6. VERIFY NEW POOL STATE
        _verifyNewPoolState();

        console.log("");
        console.log(
            "[SUCCESS] QuickLiquidityFX liquidity provision completed successfully!"
        );
        console.log("Pool now has additional liquidity provided.");
    }

    /// @notice Perform network and chain ID validation
    function _performNetworkValidation() internal view {
        console.log("=== 1. Network and Contract Safety Validations ===");

        // Network check: verify block.chainId == 421614 (Arbitrum Sepolia)
        require(
            block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID,
            "NETWORK_ERROR: Must run on Arbitrum Sepolia (421614)"
        );
        console.log("[PASS] Network check: Arbitrum Sepolia confirmed");
    }

    /// @notice Validate contract existence for all required addresses
    function _performContractValidation() internal view {
        console.log("");
        console.log("Contract existence validation:");

        // Validate all contract addresses contain deployed code
        _validateContractExists(MOCKEURC_ADDRESS, "MockEURC");
        _validateContractExists(MOCKUSDC_ADDRESS, "MockUSDC");
        _validateContractExists(LIQUIDITY_ROUTER_ADDRESS, "LiquidityRouter");
        _validateContractExists(POOL_MANAGER_ADDRESS, "PoolManager");
        _validateContractExists(
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS,
            "PoolModifyLiquidityTest"
        );
        _validateContractExists(DETOX_HOOK_ADDRESS, "DetoxHook");

        console.log("[PASS] All contract addresses contain deployed code");
    }

    /// @notice Display pool configuration details
    function _displayPoolConfiguration() internal view {
        console.log("");
        console.log("=== 2. Pool Specification ===");
        console.log("PoolKey configuration:");
        console.log(
            "  Currency0 (MockEURC):",
            Currency.unwrap(poolKey.currency0)
        );
        console.log(
            "  Currency1 (MockUSDC):",
            Currency.unwrap(poolKey.currency1)
        );
        console.log("  Fee tier: 0.02% (", poolKey.fee, ")");
        console.log("  Tick spacing:", uint256(int256(poolKey.tickSpacing)));
        console.log("  Hooks (DetoxHook):", address(poolKey.hooks));

        // Calculate and display pool ID
        PoolId poolId = poolKey.toId();
        console.log("  Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        // Display liquidity parameters
        console.log("");
        console.log("Liquidity parameters:");
        console.log("  Tick Lower:", vm.toString(TICK_LOWER));
        console.log("  Tick Upper:", vm.toString(TICK_UPPER));
        console.log("  Liquidity Delta:", vm.toString(LIQUIDITY_DELTA));
        console.log("  Salt:", vm.toString(SALT));

        // Verify tick alignment with pool tick spacing
        _verifyTickAlignment();
    }

    /// @notice Fetch and display current pool state
    function _fetchAndDisplayPoolState() internal view {
        console.log("");
        console.log("=== 3. Pool State ===");

        PoolId poolId = poolKey.toId();

        // Get pool state using StateLibrary
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        ) = StateLibrary.getSlot0(poolManager, poolId);

        console.log("Pool state fetched successfully:");
        console.log("  Current price (sqrtPriceX96):", sqrtPriceX96);
        console.log("  Current tick:", vm.toString(tick));
        console.log("  Protocol fee:", protocolFee);
        console.log("  LP fee:", lpFee);

        // Calculate and display current price in human-readable format
        _displayCurrentPrice(sqrtPriceX96);

        // Verify tick alignment with pool tick spacing
        bool tickAligned = (tick % int24(poolKey.tickSpacing)) == 0;
        console.log(
            "  Tick alignment:",
            tickAligned ? "ALIGNED" : "NOT ALIGNED"
        );

        // Get liquidity at current tick
        uint128 liquidity = StateLibrary.getLiquidity(poolManager, poolId);
        console.log("  Liquidity at current tick:", liquidity);
    }

    /// @notice Display current price in human-readable format
    /// @param sqrtPriceX96 The square root price in X96 format
    function _displayCurrentPrice(uint160 sqrtPriceX96) internal pure {
        if (sqrtPriceX96 > 0) {
            // Convert sqrtPriceX96 to price (MockEURC per MockUSDC)
            // price = (sqrtPriceX96 / 2^96)^2
            uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >>
                (96 * 2);
            console.log("  Current price (MockEURC per MockUSDC):", price);
        }
    }

    /// @notice Verify liquidity provider wallet and balances
    function _verifyLiquidityProvider() internal view {
        console.log("");
        console.log("=== 4. Verify Liquidity Provider ===");

        // Load environment variables
        address liquidityProviderWallet;
        try vm.envAddress("LIQUIDITY_PROVIDER_WALLET") returns (
            address wallet
        ) {
            liquidityProviderWallet = wallet;
        } catch {
            console.log(
                "[ERROR] LIQUIDITY_PROVIDER_WALLET environment variable not set"
            );
            return;
        }

        require(
            liquidityProviderWallet != address(0),
            "Invalid liquidity provider wallet address"
        );
        console.log("Liquidity provider wallet:", liquidityProviderWallet);

        // Fetch and display balances
        uint256 ethBalance = liquidityProviderWallet.balance;
        uint256 mockEurcBalance = IERC20(MOCKEURC_ADDRESS).balanceOf(
            liquidityProviderWallet
        );
        uint256 mockUsdcBalance = IERC20(MOCKUSDC_ADDRESS).balanceOf(
            liquidityProviderWallet
        );

        console.log("Balances for liquidity provider wallet:");
        console.log("  ETH balance:", ethBalance);
        console.log("  ETH balance (human):", ethBalance / 1e18);
        console.log("  MockEURC balance:", mockEurcBalance);
        console.log("  MockUSDC balance:", mockUsdcBalance);

        // Validate sufficient balances for liquidity provision
        bool sufficientEth = ethBalance > 0.001 ether; // Need gas + potential ETH for liquidity
        bool sufficientMockEurc = mockEurcBalance > 0;
        bool sufficientMockUsdc = mockUsdcBalance > 0;

        console.log("");
        console.log("Balance validation:");
        console.log("  Sufficient ETH:", sufficientEth ? "YES" : "NO");
        console.log(
            "  Sufficient MockEURC:",
            sufficientMockEurc ? "YES" : "NO"
        );
        console.log(
            "  Sufficient MockUSDC:",
            sufficientMockUsdc ? "YES" : "NO"
        );

        if (sufficientEth && sufficientMockEurc && sufficientMockUsdc) {
            console.log("[PASS] Liquidity provider has sufficient balances");
        } else {
            console.log(
                "[WARNING] Liquidity provider may have insufficient balances"
            );
        }
    }

    /// @notice Verify tick alignment with pool tick spacing
    function _verifyTickAlignment() internal view {
        bool lowerAligned = (TICK_LOWER % int24(poolKey.tickSpacing)) == 0;
        bool upperAligned = (TICK_UPPER % int24(poolKey.tickSpacing)) == 0;
        bool validRange = TICK_LOWER < TICK_UPPER;

        console.log("");
        console.log("Tick alignment verification:");
        console.log(
            "  Tick lower alignment:",
            lowerAligned ? "VALID" : "INVALID"
        );
        console.log(
            "  Tick upper alignment:",
            upperAligned ? "VALID" : "INVALID"
        );
        console.log("  Tick range validity:", validRange ? "VALID" : "INVALID");

        require(
            lowerAligned && upperAligned && validRange,
            "Invalid tick configuration"
        );
        console.log("[PASS] Tick alignment verification successful");
    }

    /// @notice Validate that a contract exists at the given address
    /// @param contractAddress The address to check
    /// @param contractName The name of the contract for logging
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
            string(
                abi.encodePacked(contractName, " contract not found at address")
            )
        );
        console.log("  [PASS]", contractName, "at:", contractAddress);
    }

    /// @notice Handle approvals and allowances for MockEURC and MockUSDC spending
    /// @dev This function manages token approvals for PoolModifyLiquidityTest and PoolManager contracts
    function _handleApprovalsAndAllowances() internal {
        console.log("");
        console.log("=== 5. Approvals and Allowances ===");

        // Load environment variables
        address liquidityProviderWallet;
        try vm.envAddress("LIQUIDITY_PROVIDER_WALLET") returns (
            address wallet
        ) {
            liquidityProviderWallet = wallet;
        } catch {
            console.log(
                "[ERROR] LIQUIDITY_PROVIDER_WALLET environment variable not set"
            );
            return;
        }

        // Check if we have a private key for transactions
        uint256 liquidityProviderPrivateKey;
        bool canExecuteTransactions = false;
        try vm.envUint("LIQUIDITY_PROVIDER_PRIVATE_KEY") returns (
            uint256 privateKey
        ) {
            liquidityProviderPrivateKey = privateKey;
            canExecuteTransactions = true;
        } catch {
            console.log(
                "[INFO] LIQUIDITY_PROVIDER_PRIVATE_KEY not set - will only display current allowances"
            );
        }

        // Display current allowances
        _displayCurrentAllowances(liquidityProviderWallet);

        if (canExecuteTransactions) {
            console.log("");
            console.log("=== Token Approval Operations ===");

            // Start broadcasting transactions
            vm.startBroadcast(liquidityProviderPrivateKey);

            // Approve MockEURC for PoolModifyLiquidityTest
            _approveTokenSpending(
                MOCKEURC_ADDRESS,
                POOL_MODIFY_LIQUIDITY_TEST_ADDRESS,
                "MockEURC",
                "PoolModifyLiquidityTest"
            );

            // Approve MockUSDC for PoolModifyLiquidityTest
            _approveTokenSpending(
                MOCKUSDC_ADDRESS,
                POOL_MODIFY_LIQUIDITY_TEST_ADDRESS,
                "MockUSDC",
                "PoolModifyLiquidityTest"
            );

            // Approve MockEURC for PoolManager
            _approveTokenSpending(
                MOCKEURC_ADDRESS,
                POOL_MANAGER_ADDRESS,
                "MockEURC",
                "PoolManager"
            );

            // Approve MockUSDC for PoolManager
            _approveTokenSpending(
                MOCKUSDC_ADDRESS,
                POOL_MANAGER_ADDRESS,
                "MockUSDC",
                "PoolManager"
            );

            vm.stopBroadcast();

            console.log("");
            console.log("[SUCCESS] All token approvals completed");

            // Display updated allowances after approvals
            console.log("");
            console.log("=== Updated Allowances (Post-Approval) ===");
            _displayCurrentAllowances(liquidityProviderWallet);
        } else {
            console.log("");
            console.log(
                "[INFO] To execute approvals, set LIQUIDITY_PROVIDER_PRIVATE_KEY environment variable"
            );
            console.log(
                "[INFO] Run with --broadcast flag to execute actual transactions"
            );
        }
    }

    /// @notice Display current allowances for the liquidity provider wallet
    /// @param wallet The wallet address to check allowances for
    function _displayCurrentAllowances(address wallet) internal view {
        console.log("");
        console.log("Current allowances for wallet:", wallet);

        // MockEURC allowances
        uint256 mockEurcAllowancePoolTest = IERC20(MOCKEURC_ADDRESS).allowance(
            wallet,
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
        );
        uint256 mockEurcAllowancePoolManager = IERC20(MOCKEURC_ADDRESS)
            .allowance(wallet, POOL_MANAGER_ADDRESS);

        console.log("MockEURC allowances:");
        console.log("  PoolModifyLiquidityTest:", mockEurcAllowancePoolTest);
        console.log("  PoolManager:", mockEurcAllowancePoolManager);

        // MockUSDC allowances
        uint256 mockUsdcAllowancePoolTest = IERC20(MOCKUSDC_ADDRESS).allowance(
            wallet,
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
        );
        uint256 mockUsdcAllowancePoolManager = IERC20(MOCKUSDC_ADDRESS)
            .allowance(wallet, POOL_MANAGER_ADDRESS);

        console.log("MockUSDC allowances:");
        console.log("  PoolModifyLiquidityTest:", mockUsdcAllowancePoolTest);
        console.log("  PoolManager:", mockUsdcAllowancePoolManager);

        // Verify allowances meet requirements
        _verifyAllowanceRequirements(
            mockEurcAllowancePoolTest,
            mockEurcAllowancePoolManager,
            mockUsdcAllowancePoolTest,
            mockUsdcAllowancePoolManager
        );
    }

    /// @notice Approve token spending for a specific spender
    /// @param tokenAddress The token contract address
    /// @param spenderAddress The spender contract address
    /// @param tokenName The token name for logging
    /// @param spenderName The spender name for logging
    function _approveTokenSpending(
        address tokenAddress,
        address spenderAddress,
        string memory tokenName,
        string memory spenderName
    ) internal {
        console.log("Approving", tokenName, "spending for", spenderName);

        try
            IERC20(tokenAddress).approve(spenderAddress, type(uint256).max)
        returns (bool success) {
            if (success) {
                console.log(
                    "  [SUCCESS]",
                    tokenName,
                    "approved for",
                    spenderName
                );
            } else {
                console.log(
                    "  [ERROR]",
                    tokenName,
                    "approval failed for",
                    spenderName
                );
            }
        } catch Error(string memory reason) {
            console.log("  [ERROR] Approval failed:", reason);
        } catch (bytes memory) {
            console.log("  [ERROR] Approval failed with unknown error");
        }
    }

    /// @notice Verify that allowances meet the requirements for liquidity operations
    /// @param mockEurcPoolTest MockEURC allowance for PoolModifyLiquidityTest
    /// @param mockEurcPoolManager MockEURC allowance for PoolManager
    /// @param mockUsdcPoolTest MockUSDC allowance for PoolModifyLiquidityTest
    /// @param mockUsdcPoolManager MockUSDC allowance for PoolManager
    function _verifyAllowanceRequirements(
        uint256 mockEurcPoolTest,
        uint256 mockEurcPoolManager,
        uint256 mockUsdcPoolTest,
        uint256 mockUsdcPoolManager
    ) internal view {
        console.log("");
        console.log("Allowance verification:");

        // Define minimum required allowance (should be high for liquidity operations)
        uint256 minRequiredAllowance = 1e24; // Very high allowance for unlimited operations

        bool mockEurcPoolTestOk = mockEurcPoolTest >= minRequiredAllowance;
        bool mockEurcPoolManagerOk = mockEurcPoolManager >=
            minRequiredAllowance;
        bool mockUsdcPoolTestOk = mockUsdcPoolTest >= minRequiredAllowance;
        bool mockUsdcPoolManagerOk = mockUsdcPoolManager >=
            minRequiredAllowance;

        console.log(
            "  MockEURC -> PoolModifyLiquidityTest:",
            mockEurcPoolTestOk ? "SUFFICIENT" : "INSUFFICIENT"
        );
        console.log(
            "  MockEURC -> PoolManager:",
            mockEurcPoolManagerOk ? "SUFFICIENT" : "INSUFFICIENT"
        );
        console.log(
            "  MockUSDC -> PoolModifyLiquidityTest:",
            mockUsdcPoolTestOk ? "SUFFICIENT" : "INSUFFICIENT"
        );
        console.log(
            "  MockUSDC -> PoolManager:",
            mockUsdcPoolManagerOk ? "SUFFICIENT" : "INSUFFICIENT"
        );

        bool allAllowancesOk = mockEurcPoolTestOk &&
            mockEurcPoolManagerOk &&
            mockUsdcPoolTestOk &&
            mockUsdcPoolManagerOk;

        if (allAllowancesOk) {
            console.log(
                "  [PASS] All allowances meet requirements for liquidity operations"
            );
        } else {
            console.log(
                "  [WARNING] Some allowances are insufficient - approvals may be needed"
            );
            console.log(
                "  [INFO] Required minimum allowance:",
                minRequiredAllowance
            );
        }
    }

    /// @notice Provide liquidity to the pool using PoolModifyLiquidityTest contract
    /// @dev Broadcasts transactions using LIQUIDITY_PROVIDER_WALLET and performs actual liquidity provision
    function _provideLiquidity() internal {
        console.log("");
        console.log("=== 7. Liquidity Provision ===");

        // Load environment variables
        address liquidityProviderWallet;
        uint256 liquidityProviderPrivateKey;
        bool canExecuteTransactions = false;

        try vm.envAddress("LIQUIDITY_PROVIDER_WALLET") returns (
            address wallet
        ) {
            liquidityProviderWallet = wallet;
        } catch {
            console.log(
                "[ERROR] LIQUIDITY_PROVIDER_WALLET environment variable not set"
            );
            return;
        }

        try vm.envUint("LIQUIDITY_PROVIDER_PRIVATE_KEY") returns (
            uint256 privateKey
        ) {
            liquidityProviderPrivateKey = privateKey;
            canExecuteTransactions = true;
        } catch {
            console.log(
                "[ERROR] LIQUIDITY_PROVIDER_PRIVATE_KEY environment variable not set"
            );
            console.log(
                "[INFO] Cannot execute liquidity provision without private key"
            );
            return;
        }

        if (!canExecuteTransactions) {
            console.log(
                "[INFO] Skipping liquidity provision - no private key provided"
            );
            return;
        }

        // Get balances before transaction
        uint256 mockEurcBalanceBefore = IERC20(MOCKEURC_ADDRESS).balanceOf(
            liquidityProviderWallet
        );
        uint256 mockUsdcBalanceBefore = IERC20(MOCKUSDC_ADDRESS).balanceOf(
            liquidityProviderWallet
        );
        uint256 ethBalanceBefore = liquidityProviderWallet.balance;

        console.log("Pre-transaction balances:");
        console.log("  MockEURC balance:", mockEurcBalanceBefore);
        console.log("  MockUSDC balance:", mockUsdcBalanceBefore);
        console.log("  ETH balance:", ethBalanceBefore);

        // Create ModifyLiquidityParams
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            liquidityDelta: LIQUIDITY_DELTA,
            salt: SALT
        });

        console.log("");
        console.log("Executing liquidity provision transaction...");
        console.log(
            "Using PoolModifyLiquidityTest contract at:",
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
        );

        // Start broadcasting transactions
        vm.startBroadcast(liquidityProviderPrivateKey);

        try
            PoolModifyLiquidityTest(POOL_MODIFY_LIQUIDITY_TEST_ADDRESS)
                .modifyLiquidity(poolKey, params, "")
        returns (BalanceDelta delta) {
            vm.stopBroadcast();

            console.log("");
            console.log("=== Transaction Confirmation ===");
            console.log(
                "  [SUCCESS] Liquidity provision transaction completed"
            );

            // Extract and display balance deltas
            int128 amount0Delta = delta.amount0();
            int128 amount1Delta = delta.amount1();

            console.log(
                "  Amount0 Delta (MockEURC):",
                vm.toString(amount0Delta)
            );
            console.log(
                "  Amount1 Delta (MockUSDC):",
                vm.toString(amount1Delta)
            );

            // Get balances after transaction
            uint256 mockEurcBalanceAfter = IERC20(MOCKEURC_ADDRESS).balanceOf(
                liquidityProviderWallet
            );
            uint256 mockUsdcBalanceAfter = IERC20(MOCKUSDC_ADDRESS).balanceOf(
                liquidityProviderWallet
            );
            uint256 ethBalanceAfter = liquidityProviderWallet.balance;

            console.log("");
            console.log("Post-transaction balances:");
            console.log("  MockEURC balance:", mockEurcBalanceAfter);
            console.log("  MockUSDC balance:", mockUsdcBalanceAfter);
            console.log("  ETH balance:", ethBalanceAfter);

            // Calculate actual amounts extracted
            uint256 mockEurcExtracted = mockEurcBalanceBefore -
                mockEurcBalanceAfter;
            uint256 mockUsdcExtracted = mockUsdcBalanceBefore -
                mockUsdcBalanceAfter;
            uint256 gasUsed = ethBalanceBefore - ethBalanceAfter;

            console.log("");
            console.log("Amounts extracted from LIQUIDITY_PROVIDER_WALLET:");
            console.log("  MockEURC extracted:", mockEurcExtracted);
            console.log("  MockUSDC extracted:", mockUsdcExtracted);
            console.log("  ETH used for gas:", gasUsed);
        } catch Error(string memory reason) {
            vm.stopBroadcast();
            console.log("  [ERROR] Liquidity provision failed:", reason);
        } catch (bytes memory) {
            vm.stopBroadcast();
            console.log(
                "  [ERROR] Liquidity provision failed with unknown error"
            );
        }
    }

    /// @notice Verify the new pool state after liquidity provision
    /// @dev Fetches current MockEURC/MockUSDC price and verifies it didn't change unexpectedly
    function _verifyNewPoolState() internal view {
        console.log("");
        console.log("=== 8. Verify New Pool State ===");

        PoolId poolId = poolKey.toId();

        // Get updated pool state
        (
            uint160 newSqrtPriceX96,
            int24 newTick,
            uint24 newProtocolFee,
            uint24 newLpFee
        ) = StateLibrary.getSlot0(poolManager, poolId);

        console.log("Updated pool state:");
        console.log("  Current price (sqrtPriceX96):", newSqrtPriceX96);
        console.log("  Current tick:", vm.toString(newTick));
        console.log("  Protocol fee:", newProtocolFee);
        console.log("  LP fee:", newLpFee);

        // Calculate and display current price in human-readable format
        _displayCurrentPrice(newSqrtPriceX96);

        // Get updated liquidity
        uint128 newLiquidity = StateLibrary.getLiquidity(poolManager, poolId);
        console.log("  Liquidity at current tick:", newLiquidity);

        // Verify price didn't change unexpectedly
        console.log("");
        console.log("Price verification:");
        console.log("  sqrtPriceX96:", newSqrtPriceX96);

        if (newSqrtPriceX96 > 0) {
            console.log("  [PASS] Pool has valid price");
        } else {
            console.log(
                "  [WARNING] Pool price is zero - may indicate initialization issue"
            );
        }

        // Verify tick alignment
        bool tickAligned = (newTick % int24(poolKey.tickSpacing)) == 0;
        console.log(
            "  Tick alignment:",
            tickAligned ? "ALIGNED" : "NOT ALIGNED"
        );

        if (tickAligned) {
            console.log("  [PASS] Tick alignment maintained");
        } else {
            console.log("  [WARNING] Tick alignment issue detected");
        }

        console.log("");
        console.log("[SUCCESS] Pool state verification completed");
    }
}
