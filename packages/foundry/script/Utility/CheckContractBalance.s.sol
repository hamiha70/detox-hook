// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckContractBalance is Script {
    address constant LIQUIDITY_ROUTER_ADDRESS =
        0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a;

    function run() external view {
        console.log("=== Contract Balance Check ===");
        console.log("Contract Address:", LIQUIDITY_ROUTER_ADDRESS);

        uint256 balance = LIQUIDITY_ROUTER_ADDRESS.balance;
        console.log("ETH Balance (wei):", balance);
        console.log("ETH Balance (ether):", balance / 1e18);

        if (balance > 0.001 ether) {
            console.log("[SUCCESS] Contract has sufficient ETH for operations");
        } else if (balance > 0) {
            console.log("[WARNING] Contract has low ETH balance");
        } else {
            console.log("[ERROR] Contract has no ETH balance");
        }
    }
}
