// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DetoxHook} from "../src/DetoxHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title DetoxHookLocalSimple
 * @notice Simple test to verify local deployment exists
 */
contract DetoxHookLocalSimple is Test {
    // Local deployment address (from localhost:3001 explorer)
    address constant LOCAL_DETOX_HOOK = 0x700b6A60ce7EaaEA56F065753d8dcB9653dbAD35;
    
    function test_LocalDeploymentExists() public {
        // Check if contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(LOCAL_DETOX_HOOK)
        }
        
        console.log("=== Local Deployment Analysis ===");
        console.log("Hook Address:", LOCAL_DETOX_HOOK);
        console.log("Code Size:", codeSize);
        
        if (codeSize > 0) {
            console.log("[SUCCESS] Contract exists locally");
            
            // Try to interact with it
            DetoxHook hook = DetoxHook(LOCAL_DETOX_HOOK);
            
            try hook.poolManager() returns (IPoolManager pm) {
                console.log("[SUCCESS] Contract is callable");
                console.log("PoolManager:", address(pm));
            } catch {
                console.log("[ERROR] Contract call failed");
            }
            
            try hook.getHookPermissions() returns (Hooks.Permissions memory permissions) {
                console.log("[SUCCESS] getHookPermissions() works");
                console.log("beforeSwap:", permissions.beforeSwap);
                console.log("beforeSwapReturnDelta:", permissions.beforeSwapReturnDelta);
            } catch {
                console.log("[ERROR] getHookPermissions() failed");
            }
            
            // Check address permissions
            uint160 addressPermissions = uint160(LOCAL_DETOX_HOOK);
            bool hasBeforeSwap = (addressPermissions & Hooks.BEFORE_SWAP_FLAG) != 0;
            bool hasBeforeSwapReturnDelta = (addressPermissions & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) != 0;
            
            console.log("=== Address Permission Analysis ===");
            console.log("Address as uint160:", addressPermissions);
            console.log("BEFORE_SWAP_FLAG:", Hooks.BEFORE_SWAP_FLAG);
            console.log("BEFORE_SWAP_RETURNS_DELTA_FLAG:", Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
            console.log("Has beforeSwap flag:", hasBeforeSwap);
            console.log("Has beforeSwapReturnDelta flag:", hasBeforeSwapReturnDelta);
            
            if (!hasBeforeSwap || !hasBeforeSwapReturnDelta) {
                console.log("[ERROR] Address does NOT have required permission flags");
                console.log("This explains why it can't be used as a hook in V4");
            } else {
                console.log("[SUCCESS] Address has required permission flags");
            }
            
        } else {
            console.log("[ERROR] No contract found at address");
        }
    }
} 