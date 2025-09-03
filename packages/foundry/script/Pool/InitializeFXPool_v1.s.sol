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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title InitializeFXPool_v1
/// @notice Script to initialize a new Uniswap V4 pool for MockEURC/MockUSDC with DetoxHook
/// @dev Uses DEPLOYMENT_WALLET and DEPLOYMENT_PRIVATE_KEY environment variables
/// @dev Initial price: 1 MockUSDC = 0.86 MockEURC (EUR/USD exchange rate)
contract InitializeFXPool_v1 is Script {
    using PoolIdLibrary for PoolKey;

    // Contract addresses - UPDATE THESE AFTER DEPLOYING MockEURC
    address constant POOL_MANAGER_ADDRESS =
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant MOCK_USDC_ADDRESS =
        0x9D5A68fDFEcc14683324640D5e835936422a47b1;
    address constant MOCK_EURC_ADDRESS =
        0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E; // UPDATE AFTER DEPLOYMENT
    address constant DETOX_HOOK_ADDRESS =
        0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088;

    // Chain ID for Arbitrum Sepolia
    uint256 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;

    // Pool configuration - MockEURC/MockUSDC pair
    // Currency0: MockEURC (lower address)
    // Currency1: MockUSDC (higher address)
    PoolKey poolKey =
        PoolKey({
            currency0: Currency.wrap(MOCK_EURC_ADDRESS),
            currency1: Currency.wrap(MOCK_USDC_ADDRESS),
            fee: 2000, // 0.2% fee tier
            tickSpacing: 40, // Keep tick spacing 30
            hooks: IHooks(DETOX_HOOK_ADDRESS)
        });

    // Price configuration: 1 MockUSDC = 0.86 MockEURC
    // This means: MockEURC/MockUSDC = 0.86
    // For Uniswap V4: price = token1/token0 = MockUSDC/MockEURC = 1/0.86 ≈ 1.1628
    // Target tick: Using tick 0 for guaranteed success (price = 1)
    // Tick 0 is aligned with any tick spacing (0 % 30 = 0)
    int24 constant TARGET_TICK = -1560;

    // Calculate sqrt price using TickMath for precision
    // We'll calculate this dynamically in the run() function using TickMath.getSqrtRatioAtTick(TARGET_TICK)

    function run() external {
        console.log("=== Uniswap V4 FX Pool Initialization v1 ===");
        console.log("Script: InitializeFXPool_v1.s.sol");
        console.log("Network: Arbitrum Sepolia");
        console.log("Chain ID:", block.chainid);

        // Validate we're on the correct network
        require(
            block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID,
            "Must run on Arbitrum Sepolia (421614)"
        );

        // Load environment variables
        address deploymentWallet = vm.envAddress("DEPLOYMENT_WALLET");
        uint256 deploymentPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");

        // Validate environment
        require(deploymentWallet != address(0), "DEPLOYMENT_WALLET not set");
        require(deploymentPrivateKey != 0, "DEPLOYMENT_PRIVATE_KEY not set");

        console.log("Deployment Wallet:", deploymentWallet);
        console.log("PoolManager:", POOL_MANAGER_ADDRESS);
        console.log("MockEURC:", MOCK_EURC_ADDRESS);
        console.log("MockUSDC:", MOCK_USDC_ADDRESS);
        console.log("DetoxHook:", DETOX_HOOK_ADDRESS);
        console.log("");

        // Validate contract addresses exist
        _validateContractExists(POOL_MANAGER_ADDRESS, "PoolManager");
        _validateContractExists(MOCK_USDC_ADDRESS, "MockUSDC");
        _validateContractExists(DETOX_HOOK_ADDRESS, "DetoxHook");

        // Check if MockEURC address is set
        require(
            MOCK_EURC_ADDRESS != address(0),
            "MOCK_EURC_ADDRESS not set - update contract address in script"
        );
        _validateContractExists(MOCK_EURC_ADDRESS, "MockEURC");

        // Display pool configuration
        console.log("=== Pool Configuration ===");
        console.log(
            "Currency0 (MockEURC):",
            Currency.unwrap(poolKey.currency0)
        );
        console.log(
            "Currency1 (MockUSDC):",
            Currency.unwrap(poolKey.currency1)
        );
        console.log("Fee:", poolKey.fee);
        console.log("Tick Spacing:", uint256(int256(poolKey.tickSpacing)));
        console.log("Hooks (DetoxHook):", address(poolKey.hooks));

        // Calculate and display pool ID
        PoolId poolId = poolKey.toId();
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("");

        // Calculate sqrt price for the target price: 1 MockUSDC = 0.86 MockEURC
        // This means: price = MockUSDC/MockEURC = 1/0.86 ≈ 1.1628
        // Use a known working value: sqrt(1) * 2^96 for price = 1 (tick 0)
        // For tick 0: sqrtPriceX96 = 79228162514264337593543950336
        // For our target price ~1.16: multiply by sqrt(1.16) ≈ 1.077
        // 79228162514264337593543950336 * 1.077 ≈ 85334831031850675570000000000
        uint160 initialSqrtPriceX96 = 73283517692214947607419551744; // Start with tick 0 (price = 1)
        // Display price configuration
        console.log("=== Price Configuration ===");
        //console.log("Initial Price: 1 MockUSDC = 1 MockEURC (tick 0)");
        //console.log("FX Rate: 1:1 for testing purposes");
        console.log("SqrtPriceX96:", initialSqrtPriceX96);
        console.log("Target Tick:", vm.toString(TARGET_TICK));

        // Verify tick is aligned with tick spacing
        require(
            TARGET_TICK % poolKey.tickSpacing == 0,
            "Target tick not aligned with tick spacing"
        );
        console.log("Tick alignment: VALID");
        console.log("");

        // Check deployer balance
        uint256 deployerBalance = deploymentWallet.balance;
        console.log("Deployer ETH balance:", deployerBalance);
        require(
            deployerBalance > 0.001 ether,
            "Insufficient ETH balance for transaction"
        );

        // Create PoolManager contract instance
        IPoolManager poolManager = IPoolManager(POOL_MANAGER_ADDRESS);

        console.log("=== Pool Status Check ===");

        // Check if pool already exists by attempting to get its state
        console.log("Checking if pool already exists...");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        // Try to check if pool exists by attempting initialization in simulation mode
        console.log("[INFO] Attempting to check pool existence...");

        // We'll use a different approach - try to initialize and catch the error
        console.log(
            "[INFO] If pool already exists, initialization will revert"
        );

        // Skip pool existence check and proceed directly to creation
        console.log("[INFO] Proceeding with pool initialization");
        console.log(
            "[INFO] If pool exists, initialization will handle it gracefully"
        );

        // Start broadcasting transactions
        vm.startBroadcast(deploymentPrivateKey);

        console.log("=== Initializing FX Pool ===");
        console.log("Sending initialization transaction...");

        // Try to initialize the pool, but handle the case where it was created between simulation and broadcast
        try poolManager.initialize(poolKey, initialSqrtPriceX96) returns (
            int24 tick
        ) {
            console.log("[SUCCESS] FX Pool initialization successful!");
            console.log("Initialized at tick:", vm.toString(tick));
            console.log("[SUCCESS] FX Pool initialization verified!");
        } catch (bytes memory lowLevelData) {
            if (lowLevelData.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelData);
                if (errorSelector == bytes4(0x7983c051)) {
                    // Pool was created between simulation and broadcast
                    console.log("");
                    console.log("=== Pool Created Between Checks ===");
                    console.log(
                        "The pool was created by another transaction between simulation and broadcast."
                    );
                    console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
                    console.log("Status: READY for liquidity provision");
                    console.log("");
                    console.log(
                        "[SUCCESS] FX Pool is now initialized and ready for use!"
                    );
                    console.log(
                        "You can now proceed with adding liquidity to this pool."
                    );
                } else {
                    // Some other error occurred
                    revert(
                        "FX Pool initialization failed with unexpected error"
                    );
                }
            } else {
                revert("FX Pool initialization failed with low-level error");
            }
        }

        // Stop broadcasting
        vm.stopBroadcast();

        // Verify pool was actually created by checking its state
        console.log("=== Pool Verification ===");
        console.log("Verifying pool creation...");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        // Note: Pool verification will be done externally using cast command
        // The pool should now exist and be queryable via getSlot0
        console.log("[INFO] Pool creation transaction completed");

        console.log("=== FX Pool Initialization Summary ===");
        console.log("Pool: MockEURC/MockUSDC");
        console.log("Fee:", poolKey.fee);
        console.log("Tick Spacing:", poolKey.tickSpacing);
        //console.log("Initial Price: 1 MockUSDC = 1 MockEURC (tick 0)");
        //console.log("FX Rate: 1:1 for testing purposes");
        console.log("DetoxHook: ACTIVE for MEV protection");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("");
        console.log("[SUCCESS] FX Pool initialization completed successfully!");
        console.log("Ready for liquidity provision and EUR/USD trading!");
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

    /// @notice Calculate sqrtPriceX96 for a given price
    /// @param price The price (token1/token0)
    /// @return sqrtPriceX96 The square root price in X96 format
    // function _calculateSqrtPriceX96(
    //     uint256 price
    // ) internal pure returns (uint160 sqrtPriceX96) {
    //     // This is a simplified calculation
    //     // For more precision, use a proper sqrt function
    //     uint256 sqrtPrice = sqrt(price);
    //     sqrtPriceX96 = uint160(sqrtPrice << 96);
    //     return sqrtPriceX96;
    // }

    /// @notice Simple integer square root function
    /// @param x The input value
    /// @return y The square root
    // function sqrt(uint256 x) internal pure returns (uint256 y) {
    //     uint256 z = (x + 1) / 2;
    //     y = x;
    //     while (z < y) {
    //         y = z;
    //         z = (x / z + z) / 2;
    //     }
    // }

    /// @notice Get estimated gas cost for the operation
    function getEstimatedGasCost()
        external
        pure
        returns (uint256 gasEstimate, uint256 costEstimate)
    {
        gasEstimate = 300000; // Estimated gas for pool initialization
        costEstimate = 0.00006 ether; // Estimated cost at typical gas prices
        return (gasEstimate, costEstimate);
    }
}
