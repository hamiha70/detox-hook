// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";

/**
 * @title PriceRegistryTest
 * @notice Comprehensive test suite for PriceRegistry contract
 * @dev Tests all functionality including error cases, edge cases, and events
 */
contract PriceRegistryTest is Test {
    // Test contract instance
    PriceRegistry public priceRegistry;
    
    // Test accounts
    address public owner;
    address public nonOwner;
    address public newOwner;
    
    // Test tokens
    address public constant ETH_TOKEN = address(0); // Native ETH
    address public constant USDC_TOKEN = 0xa0B86a33E6441e8C8a0890E4182c0c5C32E1F2E6; // Mock USDC
    address public constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mock WETH
    address public constant DAI_TOKEN = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // Mock DAI
    
    // Test price IDs (from Pyth Network)
    bytes32 public constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant USDC_USD_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 public constant WETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // Same as ETH
    bytes32 public constant DAI_USD_PRICE_ID = 0xb0948a5e5313200c632b51bb5ca32f6de0d36e9950a942d19751e833f70dabfd;
    
    // Test symbols
    string public constant ETH_SYMBOL = "ETH";
    string public constant USDC_SYMBOL = "USDC";
    string public constant WETH_SYMBOL = "WETH";
    string public constant DAI_SYMBOL = "DAI";
    
    // Events for testing
    event PriceMappingSet(address indexed token, bytes32 indexed priceId, string symbol);
    event PriceMappingRemoved(address indexed token, bytes32 indexed priceId, string symbol);
    
    function setUp() public {
        // Setup test accounts
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");
        newOwner = makeAddr("newOwner");
        
        // Deploy PriceRegistry
        vm.prank(owner);
        priceRegistry = new PriceRegistry(owner);
        
        // Give accounts some ETH for gas
        vm.deal(owner, 10 ether);
        vm.deal(nonOwner, 10 ether);
        vm.deal(newOwner, 10 ether);
    }
    
    // ============ Constructor Tests ============
    
    function test_Constructor_Success() public {
        PriceRegistry registry = new PriceRegistry(owner);
        assertEq(registry.owner(), owner);
        assertEq(registry.getRegisteredTokenCount(), 0);
    }
    
    function test_Constructor_RevertInvalidOwner() public {
        vm.expectRevert(abi.encodeWithSelector(PriceRegistry.InvalidOwner.selector, address(0)));
        new PriceRegistry(address(0));
    }
    
    // ============ Owner Modifier Tests ============
    
    function test_OnlyOwner_Success() public {
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        // Should not revert
    }
    
    function test_OnlyOwner_RevertNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(PriceRegistry.OnlyOwner.selector, nonOwner, owner));
        vm.prank(nonOwner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
    }
    
    // ============ setPriceMapping Tests ============
    
    function test_SetPriceMapping_Success() public {
        vm.expectEmit(true, true, false, true);
        emit PriceMappingSet(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Verify mappings
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), ETH_USD_PRICE_ID);
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), ETH_TOKEN);
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), ETH_SYMBOL);
        assertTrue(priceRegistry.isRegistered(ETH_TOKEN));
        assertEq(priceRegistry.getRegisteredTokenCount(), 1);
    }
    
    function test_SetPriceMapping_UpdateExisting() public {
        // First mapping
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Update with new price ID
        bytes32 newPriceId = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        string memory newSymbol = "ETH2";
        
        vm.expectEmit(true, true, false, true);
        emit PriceMappingSet(ETH_TOKEN, newPriceId, newSymbol);
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, newPriceId, newSymbol);
        
        // Verify update
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), newPriceId);
        assertEq(priceRegistry.getToken(newPriceId), ETH_TOKEN);
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), newSymbol);
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), address(0)); // Old mapping cleared
        assertEq(priceRegistry.getRegisteredTokenCount(), 1); // Count unchanged
    }
    
    function test_SetPriceMapping_RevertInvalidPriceId() public {
        vm.expectRevert(abi.encodeWithSelector(PriceRegistry.InvalidPriceId.selector, bytes32(0)));
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, bytes32(0), ETH_SYMBOL);
    }
    
    function test_SetPriceMapping_RevertPriceIdAlreadyUsed() public {
        // First set a mapping
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Try to use same price ID for different token - should revert
        vm.expectRevert(abi.encodeWithSelector(
            PriceRegistry.PriceIdAlreadyUsed.selector, 
            ETH_USD_PRICE_ID, 
            ETH_TOKEN,
            USDC_TOKEN
        ));
        vm.prank(owner);
        priceRegistry.setPriceMapping(USDC_TOKEN, ETH_USD_PRICE_ID, USDC_SYMBOL);
    }
    
    function test_SetPriceMapping_AllowSameTokenSamePriceId() public {
        // Set first mapping
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Set same mapping again (should not revert)
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, "ETH_NEW");
        
        // Should update symbol
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), "ETH_NEW");
    }
    
    // ============ setBatchPriceMappings Tests ============
    
    function test_SetBatchPriceMappings_Success() public {
        address[] memory tokens = new address[](3);
        bytes32[] memory priceIds = new bytes32[](3);
        string[] memory symbols = new string[](3);
        
        tokens[0] = ETH_TOKEN;
        tokens[1] = USDC_TOKEN;
        tokens[2] = DAI_TOKEN;
        
        priceIds[0] = ETH_USD_PRICE_ID;
        priceIds[1] = USDC_USD_PRICE_ID;
        priceIds[2] = DAI_USD_PRICE_ID;
        
        symbols[0] = ETH_SYMBOL;
        symbols[1] = USDC_SYMBOL;
        symbols[2] = DAI_SYMBOL;
        
        // Expect events for each mapping
        vm.expectEmit(true, true, false, true);
        emit PriceMappingSet(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        vm.expectEmit(true, true, false, true);
        emit PriceMappingSet(USDC_TOKEN, USDC_USD_PRICE_ID, USDC_SYMBOL);
        vm.expectEmit(true, true, false, true);
        emit PriceMappingSet(DAI_TOKEN, DAI_USD_PRICE_ID, DAI_SYMBOL);
        
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        
        // Verify all mappings
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), ETH_USD_PRICE_ID);
        assertEq(priceRegistry.getPriceId(USDC_TOKEN), USDC_USD_PRICE_ID);
        assertEq(priceRegistry.getPriceId(DAI_TOKEN), DAI_USD_PRICE_ID);
        assertEq(priceRegistry.getRegisteredTokenCount(), 3);
    }
    
    function test_SetBatchPriceMappings_RevertEmptyArrays() public {
        address[] memory tokens = new address[](0);
        bytes32[] memory priceIds = new bytes32[](0);
        string[] memory symbols = new string[](0);
        
        vm.expectRevert(abi.encodeWithSelector(PriceRegistry.EmptyArrays.selector));
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
    }
    
    function test_SetBatchPriceMappings_RevertArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        bytes32[] memory priceIds = new bytes32[](3);
        string[] memory symbols = new string[](2);
        
        vm.expectRevert(abi.encodeWithSelector(
            PriceRegistry.ArrayLengthMismatch.selector, 
            2, 3, 2
        ));
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
    }
    
    function test_SetBatchPriceMappings_RevertInvalidPriceId() public {
        address[] memory tokens = new address[](2);
        bytes32[] memory priceIds = new bytes32[](2);
        string[] memory symbols = new string[](2);
        
        tokens[0] = ETH_TOKEN;
        tokens[1] = USDC_TOKEN;
        priceIds[0] = ETH_USD_PRICE_ID;
        priceIds[1] = bytes32(0); // Invalid
        symbols[0] = ETH_SYMBOL;
        symbols[1] = USDC_SYMBOL;
        
        vm.expectRevert(abi.encodeWithSelector(PriceRegistry.InvalidPriceId.selector, bytes32(0)));
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
    }
    
    function test_SetBatchPriceMappings_RevertPriceIdAlreadyUsed() public {
        address[] memory tokens = new address[](2);
        bytes32[] memory priceIds = new bytes32[](2);
        string[] memory symbols = new string[](2);
        
        tokens[0] = ETH_TOKEN;
        tokens[1] = USDC_TOKEN;
        priceIds[0] = ETH_USD_PRICE_ID;
        priceIds[1] = ETH_USD_PRICE_ID; // Duplicate within batch
        symbols[0] = ETH_SYMBOL;
        symbols[1] = USDC_SYMBOL;
        
        vm.expectRevert(abi.encodeWithSelector(
            PriceRegistry.PriceIdAlreadyUsed.selector,
            ETH_USD_PRICE_ID,
            ETH_TOKEN,
            USDC_TOKEN
        ));
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
    }
    
    function test_SetBatchPriceMappings_RevertPriceIdAlreadyUsedAgainstExisting() public {
        // First set an existing mapping
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Try batch with duplicate against existing mapping
        address[] memory tokens = new address[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        string[] memory symbols = new string[](1);
        
        tokens[0] = USDC_TOKEN;
        priceIds[0] = ETH_USD_PRICE_ID; // Already used by ETH_TOKEN
        symbols[0] = USDC_SYMBOL;
        
        vm.expectRevert(abi.encodeWithSelector(
            PriceRegistry.PriceIdAlreadyUsed.selector,
            ETH_USD_PRICE_ID,
            ETH_TOKEN,
            USDC_TOKEN
        ));
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
    }
    
    // ============ removePriceMapping Tests ============
    
    function test_RemovePriceMapping_Success() public {
        // First add a mapping
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        vm.expectEmit(true, true, false, true);
        emit PriceMappingRemoved(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        vm.prank(owner);
        priceRegistry.removePriceMapping(ETH_TOKEN);
        
        // Verify removal
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), bytes32(0));
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), address(0));
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), "");
        assertFalse(priceRegistry.isRegistered(ETH_TOKEN));
        assertEq(priceRegistry.getRegisteredTokenCount(), 0);
    }
    
    function test_RemovePriceMapping_RevertTokenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(PriceRegistry.TokenNotRegistered.selector, ETH_TOKEN));
        vm.prank(owner);
        priceRegistry.removePriceMapping(ETH_TOKEN);
    }
    
    function test_RemovePriceMapping_MultipleTokens() public {
        // Add multiple mappings
        vm.startPrank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        priceRegistry.setPriceMapping(USDC_TOKEN, USDC_USD_PRICE_ID, USDC_SYMBOL);
        priceRegistry.setPriceMapping(DAI_TOKEN, DAI_USD_PRICE_ID, DAI_SYMBOL);
        vm.stopPrank();
        
        assertEq(priceRegistry.getRegisteredTokenCount(), 3);
        
        // Remove middle token
        vm.prank(owner);
        priceRegistry.removePriceMapping(USDC_TOKEN);
        
        assertEq(priceRegistry.getRegisteredTokenCount(), 2);
        assertFalse(priceRegistry.isRegistered(USDC_TOKEN));
        assertTrue(priceRegistry.isRegistered(ETH_TOKEN));
        assertTrue(priceRegistry.isRegistered(DAI_TOKEN));
    }
    
    // ============ View Function Tests ============
    
    function test_GetPriceId() public {
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), ETH_USD_PRICE_ID);
        assertEq(priceRegistry.getPriceId(USDC_TOKEN), bytes32(0)); // Not registered
    }
    
    function test_GetToken() public {
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), ETH_TOKEN);
        assertEq(priceRegistry.getToken(USDC_USD_PRICE_ID), address(0)); // Not registered
    }
    
    function test_GetTokenSymbol() public {
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), ETH_SYMBOL);
        assertEq(priceRegistry.getTokenSymbol(USDC_TOKEN), ""); // Not registered
    }
    
    function test_IsRegistered() public {
        assertFalse(priceRegistry.isRegistered(ETH_TOKEN));
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        assertTrue(priceRegistry.isRegistered(ETH_TOKEN));
        assertFalse(priceRegistry.isRegistered(USDC_TOKEN));
    }
    
    function test_GetRegisteredTokenCount() public {
        assertEq(priceRegistry.getRegisteredTokenCount(), 0);
        
        vm.startPrank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        assertEq(priceRegistry.getRegisteredTokenCount(), 1);
        
        priceRegistry.setPriceMapping(USDC_TOKEN, USDC_USD_PRICE_ID, USDC_SYMBOL);
        assertEq(priceRegistry.getRegisteredTokenCount(), 2);
        vm.stopPrank();
    }
    
    function test_GetAllRegisteredTokens() public {
        vm.startPrank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        priceRegistry.setPriceMapping(USDC_TOKEN, USDC_USD_PRICE_ID, USDC_SYMBOL);
        vm.stopPrank();
        
        address[] memory tokens = priceRegistry.getAllRegisteredTokens();
        assertEq(tokens.length, 2);
        
        // Check that both tokens are in the array (order may vary)
        bool foundETH = false;
        bool foundUSDC = false;
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == ETH_TOKEN) foundETH = true;
            if (tokens[i] == USDC_TOKEN) foundUSDC = true;
        }
        assertTrue(foundETH);
        assertTrue(foundUSDC);
    }
    
    function test_GetTokenDetails() public {
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        (bytes32 priceId, string memory symbol, bool registered) = priceRegistry.getTokenDetails(ETH_TOKEN);
        
        assertEq(priceId, ETH_USD_PRICE_ID);
        assertEq(symbol, ETH_SYMBOL);
        assertTrue(registered);
        
        // Test unregistered token
        (bytes32 priceId2, string memory symbol2, bool registered2) = priceRegistry.getTokenDetails(USDC_TOKEN);
        
        assertEq(priceId2, bytes32(0));
        assertEq(symbol2, "");
        assertFalse(registered2);
    }
    
    function test_GetBatchTokenDetails() public {
        vm.startPrank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        priceRegistry.setPriceMapping(USDC_TOKEN, USDC_USD_PRICE_ID, USDC_SYMBOL);
        vm.stopPrank();
        
        address[] memory tokens = new address[](3);
        tokens[0] = ETH_TOKEN;
        tokens[1] = USDC_TOKEN;
        tokens[2] = DAI_TOKEN; // Not registered
        
        (bytes32[] memory priceIds, string[] memory symbols, bool[] memory registered) = 
            priceRegistry.getBatchTokenDetails(tokens);
        
        assertEq(priceIds.length, 3);
        assertEq(symbols.length, 3);
        assertEq(registered.length, 3);
        
        // ETH
        assertEq(priceIds[0], ETH_USD_PRICE_ID);
        assertEq(symbols[0], ETH_SYMBOL);
        assertTrue(registered[0]);
        
        // USDC
        assertEq(priceIds[1], USDC_USD_PRICE_ID);
        assertEq(symbols[1], USDC_SYMBOL);
        assertTrue(registered[1]);
        
        // DAI (not registered)
        assertEq(priceIds[2], bytes32(0));
        assertEq(symbols[2], "");
        assertFalse(registered[2]);
    }
    
    // ============ Edge Case Tests ============
    
    function test_EmptySymbol() public {
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, "");
        
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), "");
    }
    
    function test_VeryLongSymbol() public {
        string memory longSymbol = "VERYLONGTOKEN";
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, longSymbol);
        
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), longSymbol);
    }
    
    function test_MaxPriceId() public {
        bytes32 maxPriceId = bytes32(type(uint256).max);
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, maxPriceId, ETH_SYMBOL);
        
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), maxPriceId);
    }
    
    // ============ Gas Optimization Tests ============
    
    function test_GasUsage_SetPriceMapping() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for setPriceMapping:", gasUsed);
        
        // Should be reasonable (under 140k gas, increased due to isPriceIdInUse mapping)
        assertLt(gasUsed, 140000);
    }
    
    function test_GasUsage_BatchSetPriceMapping() public {
        address[] memory tokens = new address[](10);
        bytes32[] memory priceIds = new bytes32[](10);
        string[] memory symbols = new string[](10);
        
        for (uint i = 0; i < 10; i++) {
            tokens[i] = address(uint160(i + 1));
            priceIds[i] = bytes32(uint256(i + 1));
            symbols[i] = string(abi.encodePacked("TOKEN", i));
        }
        
        uint256 gasBefore = gasleft();
        
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for setBatchPriceMappings (10 tokens):", gasUsed);
        
        // Should be more efficient than 10 individual calls (allow up to 2M gas)
        assertLt(gasUsed, 2000000);
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzz_SetPriceMapping(address token, bytes32 priceId, string calldata symbol) public {
        vm.assume(priceId != bytes32(0));
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(token, priceId, symbol);
        
        assertEq(priceRegistry.getPriceId(token), priceId);
        assertEq(priceRegistry.getToken(priceId), token);
        assertEq(priceRegistry.getTokenSymbol(token), symbol);
        assertTrue(priceRegistry.isRegistered(token));
    }
    
    function testFuzz_OnlyOwner(address caller) public {
        vm.assume(caller != owner);
        
        vm.expectRevert(abi.encodeWithSelector(PriceRegistry.OnlyOwner.selector, caller, owner));
        vm.prank(caller);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
    }
    
    // ============ Integration Tests ============
    
    function test_CompleteWorkflow() public {
        // Setup multiple tokens
        vm.startPrank(owner);
        
        // Add tokens one by one
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        priceRegistry.setPriceMapping(USDC_TOKEN, USDC_USD_PRICE_ID, USDC_SYMBOL);
        
        // Add batch - use different price IDs to avoid conflicts
        address[] memory tokens = new address[](2);
        bytes32[] memory priceIds = new bytes32[](2);
        string[] memory symbols = new string[](2);
        
        tokens[0] = WETH_TOKEN;
        tokens[1] = DAI_TOKEN;
        priceIds[0] = DAI_USD_PRICE_ID; // Use DAI price ID for WETH (just for testing)
        priceIds[1] = keccak256("UNIQUE_DAI_PRICE_ID"); // Use unique price ID for DAI
        symbols[0] = WETH_SYMBOL;
        symbols[1] = DAI_SYMBOL;
        
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        
        // Verify state
        assertEq(priceRegistry.getRegisteredTokenCount(), 4);
        
        // Update existing with a NEW price ID (not already used)
        bytes32 newPriceId = keccak256("NEW_ETH_PRICE_ID");
        priceRegistry.setPriceMapping(ETH_TOKEN, newPriceId, "ETH_UPDATED");
        
        // Remove some
        priceRegistry.removePriceMapping(USDC_TOKEN);
        priceRegistry.removePriceMapping(DAI_TOKEN);
        
        vm.stopPrank();
        
        // Final verification
        assertEq(priceRegistry.getRegisteredTokenCount(), 2);
        assertTrue(priceRegistry.isRegistered(ETH_TOKEN));
        assertTrue(priceRegistry.isRegistered(WETH_TOKEN));
        assertFalse(priceRegistry.isRegistered(USDC_TOKEN));
        assertFalse(priceRegistry.isRegistered(DAI_TOKEN));
        
        // Verify ETH token was updated with new price ID
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), newPriceId);
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), "ETH_UPDATED");
    }
    
    // ============ Enhanced Tests for New Requirements ============
    
    function test_ETH_AsAddressZero_SingleMapping() public {
        // Test ETH (address(0)) can be registered
        vm.expectEmit(true, true, false, true);
        emit PriceMappingSet(address(0), ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        vm.prank(owner);
        priceRegistry.setPriceMapping(address(0), ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Verify mappings work with address(0)
        assertEq(priceRegistry.getPriceId(address(0)), ETH_USD_PRICE_ID);
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), address(0));
        assertEq(priceRegistry.getTokenSymbol(address(0)), ETH_SYMBOL);
        assertTrue(priceRegistry.isRegistered(address(0)));
        assertEq(priceRegistry.getRegisteredTokenCount(), 1);
    }
    
    function test_ETH_AsAddressZero_BatchMapping() public {
        address[] memory tokens = new address[](3);
        bytes32[] memory priceIds = new bytes32[](3);
        string[] memory symbols = new string[](3);
        
        tokens[0] = address(0); // ETH
        tokens[1] = USDC_TOKEN;
        tokens[2] = DAI_TOKEN;
        
        priceIds[0] = ETH_USD_PRICE_ID;
        priceIds[1] = USDC_USD_PRICE_ID;
        priceIds[2] = DAI_USD_PRICE_ID;
        
        symbols[0] = ETH_SYMBOL;
        symbols[1] = USDC_SYMBOL;
        symbols[2] = DAI_SYMBOL;
        
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        
        // Verify ETH (address(0)) works in batch
        assertEq(priceRegistry.getPriceId(address(0)), ETH_USD_PRICE_ID);
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), address(0));
        assertTrue(priceRegistry.isRegistered(address(0)));
        assertEq(priceRegistry.getRegisteredTokenCount(), 3);
    }
    
    function test_TokenUpdate_NoStaleReverseLookup() public {
        // Set initial mapping
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Verify initial state
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), ETH_USD_PRICE_ID);
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), ETH_TOKEN);
        
        // Update ETH_TOKEN to use a different price ID
        bytes32 newPriceId = DAI_USD_PRICE_ID; // Use DAI price ID instead of WETH (which is same as ETH)
        vm.prank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, newPriceId, "ETH_UPDATED");
        
        // Verify token was updated
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), newPriceId);
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), "ETH_UPDATED");
        assertEq(priceRegistry.getToken(newPriceId), ETH_TOKEN);
        
        // CRITICAL: Verify old price ID no longer points to ETH_TOKEN (no stale mapping)
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), address(0));
        
        // Token count should remain the same (update, not new registration)
        assertEq(priceRegistry.getRegisteredTokenCount(), 1);
    }
    
    function test_TokenUpdate_InBatch_NoStaleReverseLookup() public {
        // Set initial mappings
        vm.startPrank(owner);
        priceRegistry.setPriceMapping(ETH_TOKEN, ETH_USD_PRICE_ID, ETH_SYMBOL);
        priceRegistry.setPriceMapping(USDC_TOKEN, USDC_USD_PRICE_ID, USDC_SYMBOL);
        vm.stopPrank();
        
        // Verify initial state
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), ETH_TOKEN);
        assertEq(priceRegistry.getToken(USDC_USD_PRICE_ID), USDC_TOKEN);
        
        // Update both tokens with new price IDs in batch
        address[] memory tokens = new address[](2);
        bytes32[] memory priceIds = new bytes32[](2);
        string[] memory symbols = new string[](2);
        
        tokens[0] = ETH_TOKEN;
        tokens[1] = USDC_TOKEN;
        priceIds[0] = keccak256("UNIQUE_ETH_PRICE_ID"); // New unique price ID for ETH
        priceIds[1] = DAI_USD_PRICE_ID;  // New price ID for USDC
        symbols[0] = "ETH_NEW";
        symbols[1] = "USDC_NEW";
        
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        
        // Verify updates
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), keccak256("UNIQUE_ETH_PRICE_ID"));
        assertEq(priceRegistry.getPriceId(USDC_TOKEN), DAI_USD_PRICE_ID);
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), "ETH_NEW");
        assertEq(priceRegistry.getTokenSymbol(USDC_TOKEN), "USDC_NEW");
        
        // CRITICAL: Verify old price IDs no longer point to these tokens (no stale mappings)
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), address(0));
        assertEq(priceRegistry.getToken(USDC_USD_PRICE_ID), address(0));
        
        // Verify new mappings work
        assertEq(priceRegistry.getToken(keccak256("UNIQUE_ETH_PRICE_ID")), ETH_TOKEN);
        assertEq(priceRegistry.getToken(DAI_USD_PRICE_ID), USDC_TOKEN);
        
        // Token count should remain the same (updates, not new registrations)
        assertEq(priceRegistry.getRegisteredTokenCount(), 2);
    }
    
    function test_BatchPriceMappings_AllowSameTokenMultipleUpdates() public {
        // Test that the same token can appear multiple times in a batch (last one wins)
        address[] memory tokens = new address[](3);
        bytes32[] memory priceIds = new bytes32[](3);
        string[] memory symbols = new string[](3);
        
        tokens[0] = ETH_TOKEN;
        tokens[1] = USDC_TOKEN;
        tokens[2] = ETH_TOKEN; // Same token again
        
        priceIds[0] = ETH_USD_PRICE_ID;
        priceIds[1] = USDC_USD_PRICE_ID;
        priceIds[2] = WETH_USD_PRICE_ID; // Different price ID for same token
        
        symbols[0] = "ETH_FIRST";
        symbols[1] = USDC_SYMBOL;
        symbols[2] = "ETH_FINAL";
        
        vm.prank(owner);
        priceRegistry.setBatchPriceMappings(tokens, priceIds, symbols);
        
        // ETH_TOKEN should have the last mapping (WETH_USD_PRICE_ID, "ETH_FINAL")
        assertEq(priceRegistry.getPriceId(ETH_TOKEN), WETH_USD_PRICE_ID);
        assertEq(priceRegistry.getTokenSymbol(ETH_TOKEN), "ETH_FINAL");
        assertEq(priceRegistry.getToken(WETH_USD_PRICE_ID), ETH_TOKEN);
        
        // First ETH mapping should be cleared
        assertEq(priceRegistry.getToken(ETH_USD_PRICE_ID), address(0));
        
        // USDC should be unaffected
        assertEq(priceRegistry.getPriceId(USDC_TOKEN), USDC_USD_PRICE_ID);
        assertEq(priceRegistry.getTokenSymbol(USDC_TOKEN), USDC_SYMBOL);
        
        // Should have 2 unique tokens registered
        assertEq(priceRegistry.getRegisteredTokenCount(), 2);
    }
    
    function test_ETH_AddressZero_CannotUseSamePriceIdAsOtherToken() public {
        // Register ETH (address(0)) first
        vm.prank(owner);
        priceRegistry.setPriceMapping(address(0), ETH_USD_PRICE_ID, ETH_SYMBOL);
        
        // Try to register another token with same price ID - should fail
        vm.expectRevert(abi.encodeWithSelector(
            PriceRegistry.PriceIdAlreadyUsed.selector,
            ETH_USD_PRICE_ID,
            address(0),
            USDC_TOKEN
        ));
        vm.prank(owner);
        priceRegistry.setPriceMapping(USDC_TOKEN, ETH_USD_PRICE_ID, USDC_SYMBOL);
    }
} 