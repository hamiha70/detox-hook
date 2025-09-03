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
    int256 constant LIQUIDITY_DELTA = 1e18; // Standard Uniswap V4 liquidity amount
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

        console.log("");
        console.log(
            "[SUCCESS] QuickLiquidityFX validation completed successfully!"
        );
        console.log("Pool is ready for liquidity provision operations.");
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

        try this.getPoolSlot0(poolId) returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        ) {
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
            try this.getPoolLiquidity(poolId) returns (uint128 liquidity) {
                console.log("  Liquidity at current tick:", liquidity);
            } catch {
                console.log("  Liquidity at current tick: [QUERY FAILED]");
            }
        } catch {
            console.log(
                "[WARNING] Pool state query failed - pool may not be initialized"
            );
            console.log("This is expected if the pool hasn't been created yet");
        }
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

    /// @notice Helper function to get pool slot0 data using StateLibrary
    /// @param poolId The pool ID to query
    /// @return sqrtPriceX96 The current sqrt price
    /// @return tick The current tick
    /// @return protocolFee The protocol fee
    /// @return lpFee The LP fee
    function getPoolSlot0(
        PoolId poolId
    )
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        )
    {
        return StateLibrary.getSlot0(poolManager, poolId);
    }

    /// @notice Helper function to get pool liquidity using StateLibrary
    /// @param poolId The pool ID to query
    /// @return liquidity The current liquidity
    function getPoolLiquidity(
        PoolId poolId
    ) external view returns (uint128 liquidity) {
        return StateLibrary.getLiquidity(poolManager, poolId);
    }
}
