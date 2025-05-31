// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {DetoxHook} from "../contracts/DetoxHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title DetoxHookLive
 * @notice Live testing for deployed DetoxHook on Arbitrum Sepolia
 * @dev This test connects to the actual deployed contract to verify functionality
 */
contract DetoxHookLive is Test {
    // Arbitrum Sepolia addresses
    address constant POOL_MANAGER = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
    address constant DETOX_HOOK = 0xadC387b56F58D9f5B486bb7575bf3B5EA5898088;
    
    DetoxHook hook;
    IPoolManager poolManager;
    
    function setUp() public {
        // Fork Arbitrum Sepolia
        uint256 forkId = vm.createFork("https://sepolia-rollup.arbitrum.io/rpc");
        vm.selectFork(forkId);
        
        // Connect to deployed contracts
        hook = DetoxHook(DETOX_HOOK);
        poolManager = IPoolManager(POOL_MANAGER);
    }
    
    function test_DeployedHookExists() public {
        // Verify the hook contract exists and has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(DETOX_HOOK)
        }
        
        assertGt(codeSize, 0, "Hook contract should have code");
        console.log("Hook contract code size:", codeSize);
    }
    
    function test_HookPoolManagerConnection() public {
        // Verify the hook is connected to the correct pool manager
        address hookPoolManager = address(hook.poolManager());
        assertEq(hookPoolManager, POOL_MANAGER, "Hook should be connected to correct PoolManager");
        console.log("Hook PoolManager:", hookPoolManager);
        console.log("Expected PoolManager:", POOL_MANAGER);
    }
    
    function test_HookPermissions() public {
        // Test hook permissions
        uint160 permissions = uint160(DETOX_HOOK);
        
        // Check beforeSwap permission (bit 7)
        bool hasBeforeSwap = (permissions & Hooks.BEFORE_SWAP_FLAG) != 0;
        assertTrue(hasBeforeSwap, "Hook should have beforeSwap permission");
        
        // Check beforeSwapReturnDelta permission (bit 3)
        bool hasBeforeSwapReturnDelta = (permissions & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) != 0;
        assertTrue(hasBeforeSwapReturnDelta, "Hook should have beforeSwapReturnDelta permission");
        
        console.log("Hook address permissions:", permissions);
        console.log("Has beforeSwap:", hasBeforeSwap);
        console.log("Has beforeSwapReturnDelta:", hasBeforeSwapReturnDelta);
    }
    
    function test_HookGetPermissions() public {
        // Test the getHookPermissions function
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeSwap, "beforeSwap should be true");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be true");
        assertFalse(permissions.afterSwap, "afterSwap should be false");
        assertFalse(permissions.beforeAddLiquidity, "beforeAddLiquidity should be false");
        
        console.log("Hook permissions from getHookPermissions():");
        console.log("  beforeSwap:", permissions.beforeSwap);
        console.log("  beforeSwapReturnDelta:", permissions.beforeSwapReturnDelta);
        console.log("  afterSwap:", permissions.afterSwap);
    }
    
    function test_PoolManagerExists() public {
        // Verify the PoolManager exists and has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(POOL_MANAGER)
        }
        
        assertGt(codeSize, 0, "PoolManager contract should have code");
        console.log("PoolManager contract code size:", codeSize);
    }
    
    function test_ContractInteraction() public {
        // Test basic contract interaction
        try hook.poolManager() returns (IPoolManager pm) {
            assertEq(address(pm), POOL_MANAGER, "PoolManager should match");
            console.log("[SUCCESS] Hook contract interaction successful");
        } catch {
            assertTrue(false, "Hook contract interaction failed");
        }
    }
    
    function test_DeploymentInfo() public {
        console.log("=== Deployment Information ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("DetoxHook Address:", DETOX_HOOK);
        console.log("PoolManager Address:", POOL_MANAGER);
        console.log("Block Explorer:", "https://arbitrum-sepolia.blockscout.com");
        console.log("Contract URL:", string.concat("https://arbitrum-sepolia.blockscout.com/address/", vm.toString(DETOX_HOOK)));
    }
} 