// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {SwapRouterFixed} from "../src/SwapRouterFixed.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title Test SwapRouterFixed Swap
/// @notice Simple script to test a tiny swap through SwapRouterFixed
contract TestSwapRouterFixedSwap is Script {
    // SwapRouterFixed address on Arbitrum Sepolia
    address constant SWAP_ROUTER_FIXED =
        0x6cBf35A8fBEc26b5e16c7774B41710e369C97CB7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== SwapRouterFixed Swap Test ===");
        console.log("SwapRouter Address:", SWAP_ROUTER_FIXED);
        console.log("Deployer Address:", deployer);
        console.log("Deployer Balance:", address(deployer).balance);

        SwapRouterFixed swapRouter = SwapRouterFixed(
            payable(SWAP_ROUTER_FIXED)
        );

        // Get current pool configuration
        console.log("\n--- Current Pool Configuration ---");
        try swapRouter.getPoolConfiguration() returns (PoolKey memory poolKey) {
            console.log("Currency0 (ETH):", Currency.unwrap(poolKey.currency0));
            console.log(
                "Currency1 (USDC):",
                Currency.unwrap(poolKey.currency1)
            );
            console.log("Fee:", poolKey.fee);
            console.log("TickSpacing:", poolKey.tickSpacing);
            console.log("Hooks (DetoxHook):", address(poolKey.hooks));
        } catch Error(string memory reason) {
            console.log("Failed to get pool config:", reason);
            return;
        }

        // Test parameters
        int256 swapAmount = -10000000000000; // 0.00001 ETH exact input (negative)
        bool zeroForOne = true; // ETH -> USDC
        bytes memory updateData = "";

        console.log("\n--- Swap Parameters ---");
        console.log("Swap Amount (wei):", vm.toString(swapAmount));
        console.log("Zero for One:", zeroForOne);
        console.log("Update Data Length:", updateData.length);

        vm.startBroadcast(deployerPrivateKey);

        try
            swapRouter.swap{value: 10000000000000}(
                swapAmount,
                zeroForOne,
                updateData
            )
        returns (BalanceDelta delta) {
            console.log("\n--- Swap Successful! ---");
            console.log("Balance Delta Amount0:", delta.amount0());
            console.log("Balance Delta Amount1:", delta.amount1());
            console.log("Gas Used: Check transaction receipt");
        } catch Error(string memory reason) {
            console.log("\n--- Swap Failed ---");
            console.log("Error:", reason);
        } catch (bytes memory lowLevelError) {
            console.log("\n--- Swap Failed (Low Level) ---");
            console.log("Error Length:", lowLevelError.length);
            if (lowLevelError.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelError);
                console.log("Error Selector:", vm.toString(errorSelector));
            }
        }

        vm.stopBroadcast();

        console.log("\n--- Final Deployer Balance ---");
        console.log("ETH Balance:", address(deployer).balance);
    }
}
