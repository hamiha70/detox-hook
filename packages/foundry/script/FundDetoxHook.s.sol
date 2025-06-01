// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

/// @title FundDetoxHookScript
/// @notice Simple script to fund DetoxHook with ETH
contract FundDetoxHook is Script {
    using ChainAddresses for uint256;

    // Funding configuration (same as DeployDetoxHookComplete.s.sol)
    uint256 constant HOOK_FUNDING_AMOUNT = 0.001 ether; // 0.001 ETH
    uint256 constant MIN_ETH_BALANCE = 0.01 ether; // Minimum ETH for operations

    /// @notice Main function to fund the hook
    function run() external {
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get hook address from environment
        address payable hookAddress = payable(vm.envAddress("HOOK_ADDRESS"));
        
        console.log("=== Fund DetoxHook ===");
        console.log("Chain ID:", block.chainid);
        console.log("Chain Name:", ChainAddresses.getChainName(block.chainid));
        console.log("Deployer:", deployer);
        console.log("Hook Address:", hookAddress);
        console.log("Funding Amount:", HOOK_FUNDING_AMOUNT);
        console.log("");
        
        // Validate inputs
        _validateInputs(deployer, hookAddress);
        
        // Check current balances
        _checkBalances(deployer, hookAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Fund the hook
        _fundHook(hookAddress);
        
        vm.stopBroadcast();
        
        // Log final summary
        _logSummary(hookAddress);
    }

    /// @notice Validate deployer and hook addresses
    function _validateInputs(address deployer, address hookAddress) internal view {
        console.log("=== Validation ===");
        
        // Validate hook address
        require(hookAddress != address(0), "Hook address cannot be zero");
        require(hookAddress.code.length > 0, "Hook address must contain contract code");
        
        console.log("Hook validation:");
        console.log("  Address:", hookAddress);
        console.log("  Code size:", hookAddress.code.length, "bytes");
        console.log("  [PASS] Hook exists and has code");
        
        // Validate deployer
        require(deployer != address(0), "Deployer address cannot be zero");
        console.log("  [PASS] Deployer address valid");
    }

    /// @notice Check current balances
    function _checkBalances(address deployer, address hookAddress) internal view {
        console.log("=== Balance Check ===");
        
        uint256 deployerEthBalance = deployer.balance;
        uint256 hookEthBalance = hookAddress.balance;
        
        console.log("Current balances:");
        console.log("  Deployer ETH:", deployerEthBalance);
        console.log("  Hook ETH:", hookEthBalance);
        console.log("  Required ETH:", MIN_ETH_BALANCE);
        console.log("  Funding Amount:", HOOK_FUNDING_AMOUNT);
        
        bool deployerSufficient = deployerEthBalance >= MIN_ETH_BALANCE;
        console.log("  Deployer sufficient:", deployerSufficient);
        
        if (!deployerSufficient) {
            console.log("");
            console.log("[ERROR] Insufficient deployer balance!");
            console.log("===============================================");
            console.log("            FUNDING FAILED!                  ");
            console.log("===============================================");
            console.log("");
            console.log("Required balance:");
            console.log("  ETH: ", MIN_ETH_BALANCE / 1e18, "ETH");
            console.log("");
            console.log("Current balance:");
            console.log("  ETH: ", deployerEthBalance / 1e18, "ETH");
            console.log("");
            console.log("Please fund your deployer address:", deployer);
            console.log("Then try again.");
            console.log("");
            
            revert("Insufficient deployer balance for hook funding");
        } else {
            console.log("  [PASS] Sufficient deployer balance for funding");
        }
        
        if (hookEthBalance >= HOOK_FUNDING_AMOUNT) {
            console.log("  [INFO] Hook already has sufficient ETH");
            console.log("  Current hook balance:", hookEthBalance);
            console.log("  Will still add the funding amount");
        }
    }

    /// @notice Fund the DetoxHook with ETH
    function _fundHook(address payable hookAddress) internal {
        console.log("=== Funding Hook ===");
        
        uint256 hookBalanceBefore = hookAddress.balance;
        console.log("Hook balance before:", hookBalanceBefore);
        console.log("Funding hook with", HOOK_FUNDING_AMOUNT, "ETH...");
        
        (bool success,) = hookAddress.call{value: HOOK_FUNDING_AMOUNT}("");
        require(success, "Failed to fund hook");
        
        uint256 hookBalanceAfter = hookAddress.balance;
        console.log("Hook balance after:", hookBalanceAfter);
        console.log("Balance increase:", hookBalanceAfter - hookBalanceBefore);
        console.log("[SUCCESS] Hook funded successfully");
    }

    /// @notice Log final summary
    function _logSummary(address hookAddress) internal view {
        console.log("");
        console.log("===============================================");
        console.log("           HOOK FUNDING COMPLETE!            ");
        console.log("===============================================");
        console.log("");
        
        console.log("=== Summary ===");
        console.log("Chain:", ChainAddresses.getChainName(block.chainid));
        console.log("Hook Address:", hookAddress);
        console.log("Hook ETH Balance:", hookAddress.balance);
        console.log("Funding Amount:", HOOK_FUNDING_AMOUNT);
        console.log("");
        
        console.log("Block Explorer Link:");
        string memory explorerBase = ChainAddresses.getBlockExplorer(block.chainid);
        console.log("Hook Contract:", string.concat(explorerBase, "/address/", vm.toString(hookAddress)));
        console.log("");
        
        console.log("[HOOK READY]");
        console.log("DetoxHook Address:", hookAddress);
        console.log("ETH Balance:", hookAddress.balance);
        console.log("");
    }
} 