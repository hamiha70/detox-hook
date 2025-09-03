// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ChainAddresses} from "./Utility/ChainAddresses.sol";
import {DetoxHookV2} from "../src/DetoxHookV2.sol";
import {PriceRegistry} from "../src/PriceRegistry.sol";
import {SwapRouterFixed} from "../src/SwapRouterFixed.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {HookMiner} from "@v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookLibrary} from "../src/libraries/HookLibrary.sol";

/**
 * @title VerifyDeployment
 * @notice Comprehensive script to verify DetoxHook deployment across any EVM chain
 * @dev Checks logs, broadcast files, and on-chain state for complete verification
 */
contract VerifyDeployment is Script {
    using ChainAddresses for uint256;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Hook flags for verification
    uint160 constant EXPECTED_HOOK_FLAGS =
        uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

    struct DeploymentInfo {
        address detoxHook;
        address priceRegistry;
        address swapRouterFixed;
        address mockUsdc;
        address poolManager;
        uint256 chainId;
        string chainName;
    }

    struct VerificationResult {
        bool detoxHookValid;
        bool priceRegistryValid;
        bool swapRouterValid;
        bool mockUsdcValid;
        bool poolManagerValid;
        bool hookFlagsValid;
        bool poolsInitialized;
        bool liquidityPresent;
        string[] errors;
        string[] warnings;
    }

    /// @notice Main verification function - can be called with specific addresses or auto-detect
    function run() external view {
        console.log("=== DETOXHOOK DEPLOYMENT VERIFICATION ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Block Number:", block.number);

        // Try to auto-detect deployment from recent logs/broadcast
        DeploymentInfo memory deployment = _autoDetectDeployment();

        if (deployment.detoxHook == address(0)) {
            console.log("[ERROR] Could not auto-detect deployment");
            console.log("Please provide contract addresses manually");
            return;
        }

        // Perform comprehensive verification
        VerificationResult memory result = _verifyDeployment(deployment);

        // Display results
        _displayVerificationResults(deployment, result);
    }

    /// @notice Verify specific deployment addresses (for manual verification)
    function verifySpecificDeployment(
        address _detoxHook,
        address _priceRegistry,
        address _swapRouterFixed,
        address _mockUsdc
    ) external view {
        console.log("=== MANUAL DEPLOYMENT VERIFICATION ===");

        DeploymentInfo memory deployment = DeploymentInfo({
            detoxHook: _detoxHook,
            priceRegistry: _priceRegistry,
            swapRouterFixed: _swapRouterFixed,
            mockUsdc: _mockUsdc,
            poolManager: ChainAddresses.getPoolManager(block.chainid),
            chainId: block.chainid,
            chainName: ChainAddresses.getChainName(block.chainid)
        });

        VerificationResult memory result = _verifyDeployment(deployment);
        _displayVerificationResults(deployment, result);
    }

    /// @notice Auto-detect deployment from environment or recent transactions
    function _autoDetectDeployment()
        internal
        pure
        returns (DeploymentInfo memory)
    {
        // For now, return empty - in production this could parse broadcast files
        // or use environment variables set during deployment
        return
            DeploymentInfo({
                detoxHook: address(0),
                priceRegistry: address(0),
                swapRouterFixed: address(0),
                mockUsdc: address(0),
                poolManager: address(0),
                chainId: 0,
                chainName: ""
            });
    }

    /// @notice Comprehensive deployment verification
    function _verifyDeployment(
        DeploymentInfo memory deployment
    ) internal view returns (VerificationResult memory) {
        VerificationResult memory result;
        result.errors = new string[](0);
        result.warnings = new string[](0);

        console.log("=== VERIFYING CONTRACT DEPLOYMENTS ===");

        // 1. Verify DetoxHook
        result.detoxHookValid = _verifyDetoxHook(deployment.detoxHook);

        // 2. Verify PriceRegistry
        result.priceRegistryValid = _verifyPriceRegistry(
            deployment.priceRegistry
        );

        // 3. Verify SwapRouterFixed
        result.swapRouterValid = _verifySwapRouterFixed(
            deployment.swapRouterFixed
        );

        // 4. Verify MockUSDC
        result.mockUsdcValid = _verifyMockUsdc(deployment.mockUsdc);

        // 5. Verify PoolManager connection
        result.poolManagerValid = _verifyPoolManager(deployment.poolManager);

        // 6. Verify Hook Flags
        result.hookFlagsValid = _verifyHookFlags(deployment.detoxHook);

        // 7. Verify Pool Initialization
        result.poolsInitialized = _verifyPoolsInitialized(deployment);

        // 8. Verify Liquidity
        result.liquidityPresent = _verifyLiquidity(deployment);

        return result;
    }

    /// @notice Verify DetoxHook contract
    function _verifyDetoxHook(
        address hookAddress
    ) internal view returns (bool) {
        console.log("--- Verifying DetoxHook ---");
        console.log("Address:", hookAddress);

        if (hookAddress.code.length == 0) {
            console.log("[ERROR] No code at DetoxHook address");
            return false;
        }

        console.log("Code size:", hookAddress.code.length, "bytes");

        try DetoxHookV2(payable(hookAddress)).poolManager() returns (
            IPoolManager pm
        ) {
            console.log("PoolManager:", address(pm));
            console.log("[SUCCESS] DetoxHook contract functional");
            return true;
        } catch {
            console.log("[ERROR] DetoxHook contract not functional");
            return false;
        }
    }

    /// @notice Verify PriceRegistry contract
    function _verifyPriceRegistry(
        address registryAddress
    ) internal view returns (bool) {
        console.log("--- Verifying PriceRegistry ---");
        console.log("Address:", registryAddress);

        if (registryAddress.code.length == 0) {
            console.log("[ERROR] No code at PriceRegistry address");
            return false;
        }

        console.log("Code size:", registryAddress.code.length, "bytes");

        try PriceRegistry(registryAddress).owner() returns (address owner) {
            console.log("Owner:", owner);
            console.log("[SUCCESS] PriceRegistry contract functional");
            return true;
        } catch {
            console.log("[ERROR] PriceRegistry contract not functional");
            return false;
        }
    }

    /// @notice Verify SwapRouterFixed contract
    function _verifySwapRouterFixed(
        address routerAddress
    ) internal view returns (bool) {
        console.log("--- Verifying SwapRouterFixed ---");
        console.log("Address:", routerAddress);

        if (routerAddress.code.length == 0) {
            console.log("[ERROR] No code at SwapRouterFixed address");
            return false;
        }

        console.log("Code size:", routerAddress.code.length, "bytes");
        console.log("[SUCCESS] SwapRouterFixed contract deployed");
        return true;
    }

    /// @notice Verify MockUSDC contract
    function _verifyMockUsdc(address usdcAddress) internal view returns (bool) {
        console.log("--- Verifying MockUSDC ---");
        console.log("Address:", usdcAddress);

        if (usdcAddress.code.length == 0) {
            console.log("[ERROR] No code at MockUSDC address");
            return false;
        }

        console.log("Code size:", usdcAddress.code.length, "bytes");

        try MockERC20(usdcAddress).symbol() returns (string memory symbol) {
            console.log("Symbol:", symbol);
            console.log("Decimals:", MockERC20(usdcAddress).decimals());
            console.log("[SUCCESS] MockUSDC contract functional");
            return true;
        } catch {
            console.log("[ERROR] MockUSDC contract not functional");
            return false;
        }
    }

    /// @notice Verify PoolManager connection
    function _verifyPoolManager(
        address pmAddress
    ) internal view returns (bool) {
        console.log("--- Verifying PoolManager ---");
        console.log("Address:", pmAddress);

        if (pmAddress.code.length == 0) {
            console.log("[ERROR] No code at PoolManager address");
            return false;
        }

        console.log("Code size:", pmAddress.code.length, "bytes");
        console.log("[SUCCESS] PoolManager contract exists");
        return true;
    }

    /// @notice Verify Hook Flags
    function _verifyHookFlags(
        address hookAddress
    ) internal pure returns (bool) {
        console.log("--- Verifying Hook Flags ---");

        uint160 addressFlags = uint160(hookAddress) & HookMiner.FLAG_MASK;
        console.log("Address flags:", addressFlags);
        console.log("Expected flags:", EXPECTED_HOOK_FLAGS);

        bool flagsMatch = addressFlags == EXPECTED_HOOK_FLAGS;
        console.log("Flags match:", flagsMatch);

        if (flagsMatch) {
            console.log("[SUCCESS] Hook flags are correct");
        } else {
            console.log("[ERROR] Hook flags do not match expected values");
        }

        return flagsMatch;
    }

    /// @notice Verify pools are initialized
    function _verifyPoolsInitialized(
        DeploymentInfo memory deployment
    ) internal view returns (bool) {
        console.log("--- Verifying Pool Initialization ---");

        // Create test pool keys (ETH/USDC)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(deployment.mockUsdc); // USDC

        PoolKey memory poolKey1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 500,
            tickSpacing: 10,
            hooks: DetoxHookV2(payable(deployment.detoxHook))
        });

        PoolKey memory poolKey2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 500,
            tickSpacing: 60,
            hooks: DetoxHookV2(payable(deployment.detoxHook))
        });

        IPoolManager pm = IPoolManager(deployment.poolManager);

        // Check pool 1
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        ) = StateLibrary.getSlot0(pm, poolKey1.toId());
        if (sqrtPriceX96 != 0) {
            console.log("Pool 1 initialized - Price:", sqrtPriceX96);
            console.log("Pool 1 initialized - Tick:", tick);
        } else {
            console.log("[ERROR] Pool 1 not initialized");
            return false;
        }

        // Check pool 2
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(
            pm,
            poolKey2.toId()
        );
        if (sqrtPriceX96 != 0) {
            console.log("Pool 2 initialized - Price:", sqrtPriceX96);
            console.log("Pool 2 initialized - Tick:", tick);
        } else {
            console.log("[ERROR] Pool 2 not initialized");
            return false;
        }

        console.log("[SUCCESS] Both pools are initialized");
        return true;
    }

    /// @notice Verify liquidity is present
    function _verifyLiquidity(
        DeploymentInfo memory deployment
    ) internal view returns (bool) {
        console.log("--- Verifying Liquidity ---");

        // Check if PoolManager has any ETH or USDC balances (indicating liquidity)
        uint256 ethBalance = deployment.poolManager.balance;
        uint256 usdcBalance = MockERC20(deployment.mockUsdc).balanceOf(
            deployment.poolManager
        );

        console.log("PoolManager ETH balance:", ethBalance);
        console.log("PoolManager USDC balance:", usdcBalance);

        bool hasLiquidity = ethBalance > 0 || usdcBalance > 0;

        if (hasLiquidity) {
            console.log("[SUCCESS] Liquidity is present");
        } else {
            console.log("[WARNING] No liquidity detected in PoolManager");
        }

        return hasLiquidity;
    }

    /// @notice Display comprehensive verification results
    function _displayVerificationResults(
        DeploymentInfo memory deployment,
        VerificationResult memory result
    ) internal pure {
        console.log("");
        console.log("===============================================");
        console.log("         VERIFICATION RESULTS");
        console.log("===============================================");
        console.log("");

        console.log("=== DEPLOYMENT INFO ===");
        console.log("Chain:", deployment.chainName);
        console.log("Chain ID:", deployment.chainId);
        console.log("DetoxHook:", deployment.detoxHook);
        console.log("PriceRegistry:", deployment.priceRegistry);
        console.log("SwapRouterFixed:", deployment.swapRouterFixed);
        console.log("MockUSDC:", deployment.mockUsdc);
        console.log("PoolManager:", deployment.poolManager);
        console.log("");

        console.log("=== VERIFICATION STATUS ===");
        console.log(
            "DetoxHook Valid:",
            result.detoxHookValid ? "[PASS]" : "[FAIL]"
        );
        console.log(
            "PriceRegistry Valid:",
            result.priceRegistryValid ? "[PASS]" : "[FAIL]"
        );
        console.log(
            "SwapRouterFixed Valid:",
            result.swapRouterValid ? "[PASS]" : "[FAIL]"
        );
        console.log(
            "MockUSDC Valid:",
            result.mockUsdcValid ? "[PASS]" : "[FAIL]"
        );
        console.log(
            "PoolManager Valid:",
            result.poolManagerValid ? "[PASS]" : "[FAIL]"
        );
        console.log(
            "Hook Flags Valid:",
            result.hookFlagsValid ? "[PASS]" : "[FAIL]"
        );
        console.log(
            "Pools Initialized:",
            result.poolsInitialized ? "[PASS]" : "[FAIL]"
        );
        console.log(
            "Liquidity Present:",
            result.liquidityPresent ? "[PASS]" : "[WARNING]"
        );
        console.log("");

        bool overallSuccess = result.detoxHookValid &&
            result.priceRegistryValid &&
            result.swapRouterValid &&
            result.mockUsdcValid &&
            result.poolManagerValid &&
            result.hookFlagsValid &&
            result.poolsInitialized;

        if (overallSuccess) {
            console.log("[SUCCESS] DEPLOYMENT VERIFICATION PASSED");
            console.log("DetoxHook is ready for use!");
        } else {
            console.log("[FAIL] DEPLOYMENT VERIFICATION FAILED");
            console.log("Please check the failed components above");
        }

        console.log("");
        console.log("=== BLOCK EXPLORER LINKS ===");
        string memory explorerBase = ChainAddresses.getBlockExplorer(
            deployment.chainId
        );
        console.log(
            "DetoxHook:",
            string(
                abi.encodePacked(
                    explorerBase,
                    "/address/",
                    _addressToString(deployment.detoxHook)
                )
            )
        );
        console.log(
            "PriceRegistry:",
            string(
                abi.encodePacked(
                    explorerBase,
                    "/address/",
                    _addressToString(deployment.priceRegistry)
                )
            )
        );
        console.log(
            "SwapRouterFixed:",
            string(
                abi.encodePacked(
                    explorerBase,
                    "/address/",
                    _addressToString(deployment.swapRouterFixed)
                )
            )
        );
        console.log(
            "MockUSDC:",
            string(
                abi.encodePacked(
                    explorerBase,
                    "/address/",
                    _addressToString(deployment.mockUsdc)
                )
            )
        );
    }

    /// @notice Convert address to string for URL construction
    function _addressToString(
        address addr
    ) internal pure returns (string memory) {
        return vm.toString(addr);
    }
}
