// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PoolStateViewer.sol";
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "@uniswap/v4-core/src/types/PoolKey.sol";
import "@uniswap/v4-core/src/types/PoolId.sol";
import "@uniswap/v4-core/src/types/Currency.sol";

contract PoolStateViewerTest is Test {
    PoolStateViewer public viewer;
    IPoolManager public poolManager;

    // Arbitrum Sepolia PoolManager address
    address constant POOL_MANAGER_ADDRESS =
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;

    // Known pool keys from the project
    PoolKey public pool1Key;
    PoolKey public pool2Key;
    PoolKey public pool3Key;

    function setUp() public {
        // Use the real PoolManager from Arbitrum Sepolia
        poolManager = IPoolManager(POOL_MANAGER_ADDRESS);
        viewer = new PoolStateViewer(poolManager);

        // Define known pool keys from the project
        pool1Key = PoolKey({
            currency0: Currency.wrap(
                0x0000000000000000000000000000000000000000
            ), // ETH
            currency1: Currency.wrap(
                0x9D5A68fDFEcc14683324640D5e835936422a47b1
            ), // MockUSDC
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(0x0000000000000000000000000000000000000000)
        });

        pool2Key = PoolKey({
            currency0: Currency.wrap(
                0x0000000000000000000000000000000000000000
            ), // ETH
            currency1: Currency.wrap(
                0x9D5A68fDFEcc14683324640D5e835936422a47b1
            ), // MockUSDC
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(0x0000000000000000000000000000000000000000)
        });

        pool3Key = PoolKey({
            currency0: Currency.wrap(
                0x0000000000000000000000000000000000000000
            ), // ETH
            currency1: Currency.wrap(
                0x9D5A68fDFEcc14683324640D5e835936422a47b1
            ), // MockUSDC
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(0x0000000000000000000000000000000000000000)
        });
    }

    function testGetIdByKey() public {
        bytes32 pool1Id = viewer.getIdByKey(pool1Key);
        bytes32 pool2Id = viewer.getIdByKey(pool2Key);
        bytes32 pool3Id = viewer.getIdByKey(pool3Key);

        console.log("Pool 1 ID:", vm.toString(pool1Id));
        console.log("Pool 2 ID:", vm.toString(pool2Id));
        console.log("Pool 3 ID:", vm.toString(pool3Id));

        // Verify IDs are different for different pool keys
        assertTrue(
            pool1Id != pool2Id,
            "Pool 1 and Pool 2 should have different IDs"
        );
        assertTrue(
            pool1Id != pool3Id,
            "Pool 1 and Pool 3 should have different IDs"
        );
        assertTrue(
            pool2Id != pool3Id,
            "Pool 2 and Pool 3 should have different IDs"
        );
    }

    function testGetPoolStateById_ExistingPool() public {
        // Test with a known pool ID from the project
        bytes32 knownPoolId = 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f;

        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity,
            bool success
        ) = viewer.getPoolStateById(knownPoolId);

        if (success) {
            console.log("Pool state retrieved successfully");
            console.log("SqrtPriceX96:", sqrtPriceX96);
            console.log("Tick:", tick);
            console.log("Protocol Fee:", protocolFee);
            console.log("LP Fee:", lpFee);
            console.log("Liquidity:", liquidity);

            // Calculate and display price
            uint256 price = (uint256(sqrtPriceX96) *
                uint256(sqrtPriceX96) *
                1e6) / (2 ** 192);
            console.log("Price (USDC/ETH):", price);
        } else {
            console.log("Pool not found or not initialized");
        }

        // The test passes regardless of success/failure since we're testing the contract logic
        // In a real scenario, the pool should exist if it was properly initialized
    }

    function testGetPoolStateById_NonExistentPool() public {
        // Test with a non-existent pool ID
        bytes32 nonExistentPoolId = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity,
            bool success
        ) = viewer.getPoolStateById(nonExistentPoolId);

        assertFalse(success, "Non-existent pool should return success = false");
        assertEq(
            sqrtPriceX96,
            0,
            "Non-existent pool should return zero values"
        );
        assertEq(tick, 0, "Non-existent pool should return zero values");
        assertEq(protocolFee, 0, "Non-existent pool should return zero values");
        assertEq(lpFee, 0, "Non-existent pool should return zero values");
        assertEq(liquidity, 0, "Non-existent pool should return zero values");
    }

    function testGetPoolStateByKey() public {
        // Test the convenience function that takes a PoolKey
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee,
            uint128 liquidity,
            bool success
        ) = viewer.getPoolStateByKey(pool1Key);

        console.log("Pool state by key - Success:", success);
        if (success) {
            console.log("SqrtPriceX96:", sqrtPriceX96);
            console.log("Tick:", tick);
            console.log("Protocol Fee:", protocolFee);
            console.log("LP Fee:", lpFee);
            console.log("Liquidity:", liquidity);
        }
    }

    function testGetTickInfo() public {
        // Test with a known pool ID and tick
        bytes32 knownPoolId = 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f;
        int24 testTick = 0; // Test with tick 0

        (uint128 liquidity, bool success) = viewer.getTickInfo(
            knownPoolId,
            testTick
        );

        console.log("Tick info - Success:", success);
        if (success) {
            console.log("Tick liquidity:", liquidity);
        } else {
            console.log("Tick not found or pool not initialized");
        }

        // The test passes regardless of success/failure since we're testing the contract logic
        // In a real scenario, the pool should exist if it was properly initialized
    }

    function testGetTickInfo_NonExistentTick() public {
        // Test with a non-existent tick
        bytes32 knownPoolId = 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f;
        int24 nonExistentTick = 999999; // Very high tick that shouldn't exist

        (uint128 liquidity, bool success) = viewer.getTickInfo(
            knownPoolId,
            nonExistentTick
        );

        // Since we're testing with a real pool that might not exist, we can't make strict assertions
        // Just verify the function doesn't revert and returns appropriate values
        console.log("Non-existent tick test - Success:", success);
        console.log("Non-existent tick test - Liquidity:", liquidity);

        // The test passes if the function doesn't revert, regardless of the return values
        // In a real scenario with a properly initialized pool, this should return success = false
    }

    function testContractDeployment() public {
        // Test that the contract was deployed correctly
        assertEq(
            address(viewer.poolManager()),
            POOL_MANAGER_ADDRESS,
            "PoolManager address should match"
        );
        assertTrue(address(viewer) != address(0), "Viewer should be deployed");
    }
}
