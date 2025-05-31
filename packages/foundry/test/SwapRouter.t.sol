// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {SwapRouter, IPoolSwapTest} from "../src/SwapRouter.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title SwapRouterTest
/// @notice Comprehensive tests for the SwapRouter contract
contract SwapRouterTest is Test {

    SwapRouter public swapRouterContract;
    
    address public mockPoolSwapTest = makeAddr("mockPoolSwapTest");
    Currency public currency0 = Currency.wrap(makeAddr("token0"));
    Currency public currency1 = Currency.wrap(makeAddr("token1"));
    
    PoolKey public testKey;
    
    uint24 constant FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;
    
    // Events for testing
    event SwapExecuted(
        address indexed sender,
        int256 amountSpecified,
        bool zeroForOne,
        BalanceDelta delta
    );
    
    event PoolConfigurationUpdated(
        Currency currency0,
        Currency currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );
    
    function setUp() public {
        // Create pool key
        testKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
        
        // Deploy SwapRouter
        swapRouterContract = new SwapRouter(mockPoolSwapTest, testKey);
    }
    
    /// @notice Test contract deployment and initialization
    function test_Deployment() public {
        assertEq(address(swapRouterContract.poolSwapTest()), mockPoolSwapTest);
        
        PoolKey memory retrievedKey = swapRouterContract.getPoolConfiguration();
        assertEq(Currency.unwrap(retrievedKey.currency0), Currency.unwrap(testKey.currency0));
        assertEq(Currency.unwrap(retrievedKey.currency1), Currency.unwrap(testKey.currency1));
        assertEq(retrievedKey.fee, testKey.fee);
        assertEq(retrievedKey.tickSpacing, testKey.tickSpacing);
        
        // Test default settings
        IPoolSwapTest.TestSettings memory settings = swapRouterContract.getTestSettings();
        assertFalse(settings.takeClaims);
        assertFalse(settings.settleUsingBurn);
        
        console.log("[SUCCESS] SwapRouter deployed successfully");
    }
    
    /// @notice Test constructor reverts with zero address
    function test_DeploymentRevertsWithZeroAddress() public {
        vm.expectRevert(SwapRouter.PoolSwapTestNotSet.selector);
        new SwapRouter(address(0), testKey);
        
        console.log("[SUCCESS] Zero address validation working correctly");
    }
    
    /// @notice Test updating pool configuration
    function test_UpdatePoolConfiguration() public {
        // Create new pool key
        PoolKey memory newKey = PoolKey({
            currency0: currency1, // Swap order
            currency1: currency0,
            fee: 10000, // 1%
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });
        
        // Expect the event to be emitted
        vm.expectEmit(true, true, true, true);
        emit PoolConfigurationUpdated(
            newKey.currency0,
            newKey.currency1,
            newKey.fee,
            newKey.tickSpacing,
            newKey.hooks
        );
        
        // Update configuration
        swapRouterContract.updatePoolConfiguration(newKey);
        
        // Verify update
        PoolKey memory retrievedKey = swapRouterContract.getPoolConfiguration();
        assertEq(Currency.unwrap(retrievedKey.currency0), Currency.unwrap(newKey.currency0));
        assertEq(Currency.unwrap(retrievedKey.currency1), Currency.unwrap(newKey.currency1));
        assertEq(retrievedKey.fee, newKey.fee);
        assertEq(retrievedKey.tickSpacing, newKey.tickSpacing);
        
        console.log("[SUCCESS] Pool configuration updated successfully");
    }
    
    /// @notice Test updating test settings
    function test_UpdateTestSettings() public {
        // Update settings
        swapRouterContract.updateTestSettings(true, true);
        
        // Verify update
        IPoolSwapTest.TestSettings memory settings = swapRouterContract.getTestSettings();
        assertTrue(settings.takeClaims);
        assertTrue(settings.settleUsingBurn);
        
        // Update back to false
        swapRouterContract.updateTestSettings(false, false);
        settings = swapRouterContract.getTestSettings();
        assertFalse(settings.takeClaims);
        assertFalse(settings.settleUsingBurn);
        
        console.log("[SUCCESS] Test settings updated successfully");
    }
    
    /// @notice Test that swap function rejects zero amounts
    function test_SwapRevertsWithZeroAmount() public {
        bytes memory updateData = "";
        
        vm.expectRevert(SwapRouter.InvalidSwapAmount.selector);
        swapRouterContract.swap(0, true, updateData);
        
        vm.expectRevert(SwapRouter.InvalidSwapAmount.selector);
        swapRouterContract.swap(0, false, updateData);
        
        console.log("[SUCCESS] Zero amount validation working correctly");
    }
    
    /// @notice Test swap function parameters and interface
    function test_SwapFunctionInterface() public {
        // Mock the PoolSwapTest contract to return a delta
        BalanceDelta mockDelta = BalanceDelta.wrap(int256(1000000)); // Mock positive delta
        
        vm.mockCall(
            mockPoolSwapTest,
            abi.encodeWithSelector(IPoolSwapTest.swap.selector),
            abi.encode(mockDelta)
        );
        
        int256 swapAmount = -1000000; // Negative for exact input
        bool zeroForOne = true;
        bytes memory updateData = "";
        
        // Expect the SwapExecuted event
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(address(this), swapAmount, zeroForOne, mockDelta);
        
        // Execute swap
        BalanceDelta result = swapRouterContract.swap(swapAmount, zeroForOne, updateData);
        
        // Verify result
        assertEq(BalanceDelta.unwrap(result), BalanceDelta.unwrap(mockDelta));
        
        console.log("[SUCCESS] Swap function interface working correctly");
    }
    
    /// @notice Test swap with different directions (zeroForOne true/false)
    function test_SwapDirections() public {
        BalanceDelta mockDelta = BalanceDelta.wrap(int256(1000000));
        
        // Mock the PoolSwapTest contract
        vm.mockCall(
            mockPoolSwapTest,
            abi.encodeWithSelector(IPoolSwapTest.swap.selector),
            abi.encode(mockDelta)
        );
        
        bytes memory updateData = "";
        
        // Test zeroForOne = true (ETH -> USDC)
        BalanceDelta result1 = swapRouterContract.swap(-1000000, true, updateData);
        assertEq(BalanceDelta.unwrap(result1), BalanceDelta.unwrap(mockDelta));
        
        // Test zeroForOne = false (USDC -> ETH) 
        BalanceDelta result2 = swapRouterContract.swap(-500000, false, updateData);
        assertEq(BalanceDelta.unwrap(result2), BalanceDelta.unwrap(mockDelta));
        
        console.log("[SUCCESS] Both swap directions working correctly");
    }
    
    /// @notice Test swap with exact input (negative amounts)
    function test_SwapExactInput() public {
        BalanceDelta mockDelta = BalanceDelta.wrap(int256(1000000));
        
        vm.mockCall(
            mockPoolSwapTest,
            abi.encodeWithSelector(IPoolSwapTest.swap.selector),
            abi.encode(mockDelta)
        );
        
        // Test exact input swaps (negative amounts)
        int256[] memory exactInputAmounts = new int256[](3);
        exactInputAmounts[0] = -1000000;  // 1 token
        exactInputAmounts[1] = -500000;   // 0.5 token
        exactInputAmounts[2] = -2000000;  // 2 tokens
        
        for (uint i = 0; i < exactInputAmounts.length; i++) {
            BalanceDelta result = swapRouterContract.swap(
                exactInputAmounts[i], 
                true, 
                ""
            );
            assertEq(BalanceDelta.unwrap(result), BalanceDelta.unwrap(mockDelta));
        }
        
        console.log("[SUCCESS] Exact input swaps working correctly");
    }
    
    /// @notice Test swap with exact output (positive amounts)
    function test_SwapExactOutput() public {
        BalanceDelta mockDelta = BalanceDelta.wrap(int256(-1000000)); // Negative for exact output
        
        vm.mockCall(
            mockPoolSwapTest,
            abi.encodeWithSelector(IPoolSwapTest.swap.selector),
            abi.encode(mockDelta)
        );
        
        // Test exact output swaps (positive amounts)
        int256[] memory exactOutputAmounts = new int256[](3);
        exactOutputAmounts[0] = 1000000;  // Want exactly 1 token out
        exactOutputAmounts[1] = 500000;   // Want exactly 0.5 token out
        exactOutputAmounts[2] = 2000000;  // Want exactly 2 tokens out
        
        for (uint i = 0; i < exactOutputAmounts.length; i++) {
            BalanceDelta result = swapRouterContract.swap(
                exactOutputAmounts[i], 
                false, 
                ""
            );
            assertEq(BalanceDelta.unwrap(result), BalanceDelta.unwrap(mockDelta));
        }
        
        console.log("[SUCCESS] Exact output swaps working correctly");
    }
    
    /// @notice Test swap with update data
    function test_SwapWithUpdateData() public {
        BalanceDelta mockDelta = BalanceDelta.wrap(int256(1000000));
        
        vm.mockCall(
            mockPoolSwapTest,
            abi.encodeWithSelector(IPoolSwapTest.swap.selector),
            abi.encode(mockDelta)
        );
        
        // Test with various update data
        bytes memory updateData1 = "";
        bytes memory updateData2 = "0x1234";
        bytes memory updateData3 = hex"deadbeef";
        
        // All should work fine
        swapRouterContract.swap(-1000000, true, updateData1);
        swapRouterContract.swap(-1000000, true, updateData2);
        swapRouterContract.swap(-1000000, true, updateData3);
        
        console.log("[SUCCESS] Swap with update data working correctly");
    }
    
    /// @notice Test payable swap functionality
    function test_SwapPayable() public {
        BalanceDelta mockDelta = BalanceDelta.wrap(int256(1000000));
        
        vm.mockCall(
            mockPoolSwapTest,
            abi.encodeWithSelector(IPoolSwapTest.swap.selector),
            abi.encode(mockDelta)
        );
        
        // Give this contract some ETH
        vm.deal(address(this), 10 ether);
        
        // Execute payable swap
        uint256 ethAmount = 1 ether;
        BalanceDelta result = swapRouterContract.swap{value: ethAmount}(
            -int256(ethAmount), 
            true, 
            ""
        );
        
        assertEq(BalanceDelta.unwrap(result), BalanceDelta.unwrap(mockDelta));
        
        console.log("[SUCCESS] Payable swap functionality working correctly");
    }
    
    /// @notice Test getters return correct values
    function test_Getters() public {
        PoolKey memory retrievedKey = swapRouterContract.getPoolConfiguration();
        IPoolSwapTest.TestSettings memory settings = swapRouterContract.getTestSettings();
        
        assertTrue(Currency.unwrap(retrievedKey.currency0) == Currency.unwrap(testKey.currency0));
        assertTrue(Currency.unwrap(retrievedKey.currency1) == Currency.unwrap(testKey.currency1));
        assertEq(retrievedKey.fee, FEE);
        assertEq(retrievedKey.tickSpacing, TICK_SPACING);
        assertFalse(settings.takeClaims);
        assertFalse(settings.settleUsingBurn);
        
        console.log("[SUCCESS] All getter functions working correctly");
    }
    
    /// @notice Test the contract interface matches expected functionality
    function test_ContractInterface() public {
        // Test that the contract has all expected public functions
        assertTrue(address(swapRouterContract.poolSwapTest()) != address(0));
        
        // Test that default pool configuration is stored correctly
        PoolKey memory config = swapRouterContract.getPoolConfiguration();
        assertTrue(config.fee == FEE);
        assertTrue(config.tickSpacing == TICK_SPACING);
        
        // Test immutable values
        assertEq(address(swapRouterContract.poolSwapTest()), mockPoolSwapTest);
        
        console.log("[SUCCESS] Contract interface validation passed");
    }
    
    /// @notice Test fuzz testing with various swap amounts and directions
    function testFuzz_SwapAmounts(int256 amount, bool zeroForOne) public {
        vm.assume(amount != 0); // Cannot be zero
        vm.assume(amount > -type(int128).max && amount < type(int128).max); // Reasonable bounds
        
        BalanceDelta mockDelta = BalanceDelta.wrap(amount > 0 ? -amount : amount);
        
        vm.mockCall(
            mockPoolSwapTest,
            abi.encodeWithSelector(IPoolSwapTest.swap.selector),
            abi.encode(mockDelta)
        );
        
        // Should not revert for any valid amount
        BalanceDelta result = swapRouterContract.swap(amount, zeroForOne, "");
        assertEq(BalanceDelta.unwrap(result), BalanceDelta.unwrap(mockDelta));
    }
} 