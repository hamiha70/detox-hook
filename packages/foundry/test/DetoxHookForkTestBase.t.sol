// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DetoxHookV2} from "../src/DetoxHookV2.sol";
import {PriceRegistry} from "../src/PriceRegistry.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {HookMiner} from "@v4-periphery/src/utils/HookMiner.sol";
import {IPyth, PythStructs} from "../src/libraries/PythLibrary.sol";
import {ChainAddresses} from "../script/Utility/ChainAddresses.sol";
import {PublicRPCURL} from "../script/Utility/PublicRPCURL.sol";

/**
 * @title DetoxHookForkTestBase
 * @notice Abstract base class for DetoxHook fork tests across multiple networks
 * @dev Provides reusable test logic with dynamic address resolution and RPC failover
 */
abstract contract DetoxHookForkTestBase is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using ChainAddresses for uint256;
    using PublicRPCURL for uint256;

    // ============ Abstract Properties ============

    /// @notice Chain ID for this fork test (must be set by derived contracts)
    uint256 public immutable CHAIN_ID;

    /// @notice Human-readable chain name
    string public chainName;

    /// @notice Selected RPC URL for forking
    string public rpcUrl;

    // ============ Constants ============

    // CREATE2 Deployer Proxy (universal across all chains)
    address constant CREATE2_DEPLOYER =
        0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Hook permission flags
    uint160 constant HOOK_FLAGS =
        uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

    // ============ Test Contracts ============

    DetoxHookV2 public hook;
    IPoolManager public manager;
    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public modifyLiquidityRouter;

    // Currencies and pools
    Currency public currency0;
    Currency public currency1;
    PoolKey public poolKey;
    PoolId public poolId;

    // Mock price registry for testing
    MockPriceRegistry public mockRegistry;

    // ============ Constructor ============

    /// @notice Initialize base fork test with chain ID
    /// @param _chainId The chain ID to fork and test on
    constructor(uint256 _chainId) {
        CHAIN_ID = _chainId;
        chainName = PublicRPCURL.getChainName(_chainId);
        rpcUrl = _getRPCWithFailover(_chainId);
    }

    // ============ Setup Functions ============

    /// @notice Base setUp function - derived contracts should call this first
    function setUp() public virtual {
        // Fork the specified network
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);

        console.log("=== Forked Network ===");
        console.log("Chain:", chainName);
        console.log("Chain ID:", CHAIN_ID);
        console.log("Block Number:", block.number);
        console.log("RPC URL:", rpcUrl);

        // Connect to existing contracts using ChainAddresses
        _initializeContracts();

        // Deploy DetoxHook using proper HookMiner
        _deployDetoxHookWithHookMiner();

        // Create test currencies and pool
        _createTestCurrenciesAndPool();

        // Configure price registry
        _configurePriceRegistry();

        console.log("=== Fork Test Setup Complete ===");
    }

    // ============ Contract Initialization ============

    /// @notice Initialize contracts using ChainAddresses library
    function _initializeContracts() internal {
        // Get addresses dynamically from ChainAddresses
        address poolManagerAddr = ChainAddresses.getPoolManager(CHAIN_ID);
        address swapRouterAddr = ChainAddresses.getPoolSwapTest(CHAIN_ID);
        address modifyLiquidityAddr = ChainAddresses.getPoolModifyLiquidityTest(
            CHAIN_ID
        );

        // Verify contracts exist
        require(poolManagerAddr.code.length > 0, "PoolManager not found");
        require(swapRouterAddr.code.length > 0, "SwapRouter not found");
        require(
            modifyLiquidityAddr.code.length > 0,
            "ModifyLiquidityRouter not found"
        );

        // Initialize contract interfaces
        manager = IPoolManager(poolManagerAddr);
        swapRouter = PoolSwapTest(swapRouterAddr);
        modifyLiquidityRouter = PoolModifyLiquidityTest(modifyLiquidityAddr);

        console.log("=== Connected to Network Contracts ===");
        console.log("PoolManager:", address(manager));
        console.log("SwapRouter:", address(swapRouter));
        console.log("ModifyLiquidityRouter:", address(modifyLiquidityRouter));
    }

    // ============ Hook Deployment ============

    /// @notice Deploy DetoxHook using HookMiner with dynamic addresses
    function _deployDetoxHookWithHookMiner() internal {
        console.log("=== Mining Hook Address with HookMiner ===");
        console.log("Required flags:", HOOK_FLAGS);
        console.log("CREATE2 Deployer:", CREATE2_DEPLOYER);

        // Deploy a mock PriceRegistry for testing
        mockRegistry = new MockPriceRegistry(address(this));
        console.log("Mock PriceRegistry deployed at:", address(mockRegistry));

        // Get Pyth oracle address dynamically
        address pythOracle = ChainAddresses.getPythOracle(CHAIN_ID);
        require(
            pythOracle != address(0),
            "Pyth oracle not available on this chain"
        );

        // Prepare creation code and constructor arguments (4 parameters)
        bytes memory creationCode = type(DetoxHookV2).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(manager), // poolManager
            address(this), // owner (test contract)
            pythOracle, // Pyth oracle (dynamic)
            address(mockRegistry) // priceRegistry
        );

        // Mine the salt using HookMiner
        address expectedAddress;
        bytes32 salt;
        (expectedAddress, salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            HOOK_FLAGS,
            creationCode,
            constructorArgs
        );

        console.log("=== HookMiner Results ===");
        console.log("Salt found:", uint256(salt));
        console.log("Expected hook address:", expectedAddress);
        console.log(
            "Address flags:",
            uint160(expectedAddress) & HookMiner.FLAG_MASK
        );
        console.log("Required flags:", HOOK_FLAGS);
        console.log(
            "Flags match:",
            (uint160(expectedAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS
        );

        // Deploy using CREATE2 Deployer Proxy
        bytes memory deploymentData = abi.encodePacked(
            creationCode,
            constructorArgs
        );
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        console.log("=== CREATE2 Deployment ===");
        console.log("Deployment data length:", deploymentData.length);
        console.log("Call data length:", callData.length);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(
            callData
        );
        require(success, "CREATE2 deployment failed");
        require(returnData.length == 20, "Invalid return data length");

        address deployedAddress = address(bytes20(returnData));
        require(
            deployedAddress == expectedAddress,
            "Deployment address mismatch"
        );

        hook = DetoxHookV2(payable(deployedAddress));

        console.log("=== Hook Deployed Successfully ===");
        console.log("Hook address:", address(hook));
        console.log(
            "Hook permissions valid:",
            (uint160(address(hook)) & HookMiner.FLAG_MASK) == HOOK_FLAGS
        );

        // Verify hook functionality
        require(
            address(hook.poolManager()) == address(manager),
            "Hook not connected to manager"
        );

        Hooks.Permissions memory permissions = hook.getHookPermissions();
        require(permissions.beforeSwap, "beforeSwap permission not set");
        require(
            permissions.beforeSwapReturnDelta,
            "beforeSwapReturnDelta permission not set"
        );
    }

    // ============ Test Currencies and Pool ============

    /// @notice Create test currencies and pool key
    function _createTestCurrenciesAndPool() internal {
        // Create test currencies: MockWETH + MockUSDC (to simulate real trading pair)
        MockERC20 mockWETH = new MockERC20("Mock WETH", "WETH", 18); // 18 decimals like real WETH
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "USDC", 6); // 6 decimals like real USDC

        // Ensure proper currency ordering (smaller address first)
        if (address(mockWETH) < address(mockUSDC)) {
            currency0 = Currency.wrap(address(mockWETH)); // WETH
            currency1 = Currency.wrap(address(mockUSDC)); // USDC
        } else {
            currency0 = Currency.wrap(address(mockUSDC)); // USDC
            currency1 = Currency.wrap(address(mockWETH)); // WETH
        }

        // Create pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolId = poolKey.toId();

        console.log("=== Test Currencies Created ===");
        console.log("Currency0:", Currency.unwrap(currency0));
        console.log("Currency1:", Currency.unwrap(currency1));
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
    }

    // ============ Price Registry Configuration ============

    /// @notice Configure MockPriceRegistry with test token mappings
    function _configurePriceRegistry() internal {
        // Configure the registry with the actual token addresses
        // This will be called after currencies are created
        console.log("=== Configuring Price Registry ===");
        console.log("Registry address:", address(mockRegistry));
        console.log("Registry owner:", mockRegistry.owner());

        // Add price mappings for the test currencies
        // Using standard Pyth price IDs for ETH and USDC
        bytes32 ethPriceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // ETH/USD
        bytes32 usdcPriceId = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a; // USDC/USD

        // Determine which currency is which based on ordering
        if (Currency.unwrap(currency0) < Currency.unwrap(currency1)) {
            // currency0 is the smaller address, check if it's WETH or USDC
            MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
            if (token0.decimals() == 18) {
                // currency0 is WETH (18 decimals)
                mockRegistry.setPriceMapping(
                    Currency.unwrap(currency0),
                    ethPriceId,
                    "WETH"
                );
                mockRegistry.setPriceMapping(
                    Currency.unwrap(currency1),
                    usdcPriceId,
                    "USDC"
                );
            } else {
                // currency0 is USDC (6 decimals)
                mockRegistry.setPriceMapping(
                    Currency.unwrap(currency0),
                    usdcPriceId,
                    "USDC"
                );
                mockRegistry.setPriceMapping(
                    Currency.unwrap(currency1),
                    ethPriceId,
                    "WETH"
                );
            }
        }

        console.log("Price registry configured successfully");
    }

    // ============ RPC Failover Logic ============

    /// @notice Get RPC URL with failover support
    /// @param chainId The chain ID to get RPC for
    /// @return The selected RPC URL
    function _getRPCWithFailover(
        uint256 chainId
    ) internal view returns (string memory) {
        // Try environment variable first
        string memory envVarName = PublicRPCURL.getEnvVarName(chainId);
        try vm.envString(envVarName) returns (string memory envRPC) {
            if (bytes(envRPC).length > 0) {
                console.log("Using environment RPC for", chainName);
                return envRPC;
            }
        } catch {
            // Environment variable not set, continue to public RPCs
        }

        // Try backup environment variable
        string memory backupEnvVarName = PublicRPCURL.getBackupEnvVarName(
            chainId
        );
        try vm.envString(backupEnvVarName) returns (
            string memory backupEnvRPC
        ) {
            if (bytes(backupEnvRPC).length > 0) {
                console.log("Using backup environment RPC for", chainName);
                return backupEnvRPC;
            }
        } catch {
            // Backup environment variable not set, continue to public RPCs
        }

        // Fall back to primary public RPC
        console.log("Using primary public RPC for", chainName);
        return PublicRPCURL.getPrimaryRPC(chainId);
    }

    // ============ Utility Functions ============

    /// @notice Check if the current chain is supported
    function _isChainSupported() internal view returns (bool) {
        return PublicRPCURL.isChainSupported(CHAIN_ID);
    }

    /// @notice Get chain information
    function _getChainInfo()
        internal
        view
        returns (PublicRPCURL.ChainInfo memory)
    {
        return PublicRPCURL.getChainInfo(CHAIN_ID);
    }
}

// ============ Mock Price Registry ============

/// @notice Mock PriceRegistry for testing
contract MockPriceRegistry {
    address public owner;
    mapping(address => bytes32) public tokenToPriceId;
    mapping(address => string) public tokenSymbols;

    constructor(address _owner) {
        owner = _owner;
    }

    function setPriceMapping(
        address token,
        bytes32 priceId,
        string memory symbol
    ) external {
        require(msg.sender == owner, "Only owner");
        tokenToPriceId[token] = priceId;
        tokenSymbols[token] = symbol;
    }

    function getPriceId(address token) external view returns (bytes32) {
        return tokenToPriceId[token];
    }
}
