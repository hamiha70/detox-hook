// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { OracleLib } from "../src/libraries/OracleLib.sol";
import { IPyth, PythStructs, MockPyth } from "../src/libraries/PythLibrary.sol";

contract OracleLibTest is Test {
    MockPyth public mockPyth;
    
    // Test constants
    uint256 constant PRICE_PRECISION = 1e8;
    uint256 constant DEFAULT_STALENESS_THRESHOLD = 60; // 60 seconds
    
    // Test price IDs
    bytes32 constant ETH_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant USDC_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    
    function setUp() public {
        // Deploy mock Pyth oracle
        mockPyth = new MockPyth(60, 1);
    }

    // ============ Core Oracle Function Tests ============

    function test_getOraclePriceWithConfidence_Success() public {
        // Set up mock price data directly
        int64 price = 200000000000; // $2000.00 with 8 decimals
        uint64 conf = 1000000000; // $10.00 confidence
        int32 expo = -8;
        uint256 publishTime = block.timestamp;

        // Use direct price setting
        mockPyth.updatePriceFeeds(ETH_PRICE_ID, price, conf, expo, publishTime);

        // Test the function
        (uint256 returnedPrice, uint256 returnedConf, bool valid) = OracleLib.getOraclePriceWithConfidence(
            IPyth(address(mockPyth)),
            ETH_PRICE_ID,
            DEFAULT_STALENESS_THRESHOLD
        );

        assertTrue(valid, "Price should be valid");
        assertEq(returnedPrice, 200000000000, "Price should be normalized correctly");
        assertEq(returnedConf, 1000000000, "Confidence should be normalized correctly");
    }

    function test_getOraclePriceWithConfidence_InvalidOracle() public view {
        (uint256 price, uint256 conf, bool valid) = OracleLib.getOraclePriceWithConfidence(
            IPyth(address(0)),
            ETH_PRICE_ID,
            DEFAULT_STALENESS_THRESHOLD
        );

        assertFalse(valid, "Should be invalid with zero oracle address");
        assertEq(price, 0, "Price should be zero");
        assertEq(conf, 0, "Confidence should be zero");
    }

    function test_getOraclePriceWithConfidence_InvalidPriceId() public view {
        (uint256 price, uint256 conf, bool valid) = OracleLib.getOraclePriceWithConfidence(
            IPyth(address(mockPyth)),
            bytes32(0),
            DEFAULT_STALENESS_THRESHOLD
        );

        assertFalse(valid, "Should be invalid with zero price ID");
        assertEq(price, 0, "Price should be zero");
        assertEq(conf, 0, "Confidence should be zero");
    }

    function test_getOraclePriceWithConfidence_StalePrice() public {
        // Set block timestamp to a realistic value first
        vm.warp(1000000); // Set to a large timestamp
        
        // Set up old price data - use timestamp 0 which will definitely be stale
        int64 price = 200000000000;
        uint64 conf = 1000000000;
        int32 expo = -8;
        uint256 oldPublishTime = 0; // Epoch time - definitely stale

        // Use direct price setting
        mockPyth.updatePriceFeeds(ETH_PRICE_ID, price, conf, expo, oldPublishTime);

        (uint256 returnedPrice, uint256 returnedConf, bool valid) = OracleLib.getOraclePriceWithConfidence(
            IPyth(address(mockPyth)),
            ETH_PRICE_ID,
            DEFAULT_STALENESS_THRESHOLD
        );

        assertFalse(valid, "Should be invalid due to staleness");
        assertEq(returnedPrice, 0, "Price should be zero for stale data");
        assertEq(returnedConf, 0, "Confidence should be zero for stale data");
    }

    function test_getOraclePrice_Success() public {
        // Set up mock price data
        int64 price = 100000000; // $1.00 with 8 decimals
        uint64 conf = 500000; // $0.005 confidence
        int32 expo = -8;
        uint256 publishTime = block.timestamp;

        // Use direct price setting
        mockPyth.updatePriceFeeds(USDC_PRICE_ID, price, conf, expo, publishTime);

        (uint256 returnedPrice, bool valid) = OracleLib.getOraclePrice(
            IPyth(address(mockPyth)),
            USDC_PRICE_ID,
            DEFAULT_STALENESS_THRESHOLD
        );

        assertTrue(valid, "Price should be valid");
        assertEq(returnedPrice, 100000000, "Price should be normalized correctly");
    }

    // ============ Normalization Function Tests ============

    function test_normalizePythPrice_NegativeExponent() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 200000000000, // Raw price
            conf: 1000000000,
            expo: -8, // 8 decimal places
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythPrice(pythPrice);
        assertEq(normalized, 200000000000, "Should normalize -8 exponent correctly");
    }

    function test_normalizePythPrice_PositiveExponent() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 2000, // Raw price
            conf: 10,
            expo: 5, // Multiply by 10^5
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythPrice(pythPrice);
        // expo = 5, targetExpo = -8
        // Since expo > targetExpo, we multiply by 10^(expo - targetExpo) = 10^(5 - (-8)) = 10^13
        // 2000 * 10^13 = 20,000,000,000,000,000
        assertEq(normalized, 2000 * 1e13, "Should normalize positive exponent correctly");
    }

    function test_normalizePythPrice_ZeroPrice() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 0,
            conf: 1000000000,
            expo: -8,
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythPrice(pythPrice);
        assertEq(normalized, 0, "Should return zero for zero price");
    }

    function test_normalizePythConfidence_Success() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 200000000000,
            conf: 1000000000, // Raw confidence
            expo: -8,
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythConfidence(pythPrice);
        assertEq(normalized, 1000000000, "Should normalize confidence correctly");
    }

    function test_normalizePythConfidence_ZeroConfidence() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 200000000000,
            conf: 0,
            expo: -8,
            publishTime: block.timestamp
        });

        uint256 normalized = OracleLib.normalizePythConfidence(pythPrice);
        assertEq(normalized, 0, "Should return zero for zero confidence");
    }

    // ============ Validation Function Tests ============

    function test_isPriceValid_ValidPrice() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 200000000000,
            conf: 1000000000,
            expo: -8,
            publishTime: block.timestamp
        });

        bool valid = OracleLib.isPriceValid(pythPrice, DEFAULT_STALENESS_THRESHOLD);
        assertTrue(valid, "Should be valid for fresh positive price");
    }

    function test_isPriceValid_ZeroPrice() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 0,
            conf: 1000000000,
            expo: -8,
            publishTime: block.timestamp
        });

        bool valid = OracleLib.isPriceValid(pythPrice, DEFAULT_STALENESS_THRESHOLD);
        assertFalse(valid, "Should be invalid for zero price");
    }

    function test_isPriceValid_NegativePrice() public view {
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: -200000000000,
            conf: 1000000000,
            expo: -8,
            publishTime: block.timestamp
        });

        bool valid = OracleLib.isPriceValid(pythPrice, DEFAULT_STALENESS_THRESHOLD);
        assertFalse(valid, "Should be invalid for negative price");
    }

    function test_isPriceValid_StalePrice() public {
        // Set block timestamp to a realistic value first
        vm.warp(1000000); // Set to a large timestamp
        
        PythStructs.Price memory pythPrice = PythStructs.Price({
            price: 200000000000,
            conf: 1000000000,
            expo: -8,
            publishTime: 0 // Epoch time - definitely stale
        });

        bool valid = OracleLib.isPriceValid(pythPrice, DEFAULT_STALENESS_THRESHOLD);
        assertFalse(valid, "Should be invalid for stale price");
    }

    // ============ Helper Function Tests ============

    function test_getPublishTime_Success() public {
        // Set up mock price data with a safe timestamp
        uint256 expectedPublishTime = 1000; // Use a fixed timestamp instead of block.timestamp - 30
        
        // Use direct price setting
        mockPyth.updatePriceFeeds(ETH_PRICE_ID, 200000000000, 1000000000, -8, expectedPublishTime);

        uint256 publishTime = OracleLib.getPublishTime(
            IPyth(address(mockPyth)),
            ETH_PRICE_ID
        );

        assertEq(publishTime, expectedPublishTime, "Should return correct publish time");
    }

    function test_getPublishTime_InvalidPriceId() public view {
        uint256 publishTime = OracleLib.getPublishTime(
            IPyth(address(mockPyth)),
            bytes32(uint256(0x1234)) // Non-existent price ID
        );

        assertEq(publishTime, 0, "Should return zero for invalid price ID");
    }

    function test_isOracleConfigured_Valid() public view {
        bool configured = OracleLib.isOracleConfigured(
            IPyth(address(mockPyth)),
            ETH_PRICE_ID
        );

        assertTrue(configured, "Should be configured with valid oracle and price ID");
    }

    function test_isOracleConfigured_InvalidOracle() public pure {
        bool configured = OracleLib.isOracleConfigured(
            IPyth(address(0)),
            ETH_PRICE_ID
        );

        assertFalse(configured, "Should not be configured with zero oracle address");
    }

    function test_isOracleConfigured_InvalidPriceId() public view {
        bool configured = OracleLib.isOracleConfigured(
            IPyth(address(mockPyth)),
            bytes32(0)
        );

        assertFalse(configured, "Should not be configured with zero price ID");
    }

    // ============ Edge Case Tests ============

    function test_safePythCall_Success() public {
        // Set up mock price data
        mockPyth.updatePriceFeeds(ETH_PRICE_ID, 200000000000, 1000000000, -8, block.timestamp);

        (PythStructs.Price memory pythPrice, bool success) = OracleLib.safePythCall(
            IPyth(address(mockPyth)),
            ETH_PRICE_ID
        );

        assertTrue(success, "Call should succeed");
        assertEq(pythPrice.price, 200000000000, "Should return correct price");
        assertEq(pythPrice.conf, 1000000000, "Should return correct confidence");
    }

    function test_safePythCall_Failure() public view {
        (PythStructs.Price memory pythPrice, bool success) = OracleLib.safePythCall(
            IPyth(address(mockPyth)),
            bytes32(uint256(0x1234)) // Non-existent price ID
        );

        // MockPyth returns zero data for non-existent price IDs but doesn't revert
        // So the call succeeds but returns zero data
        assertTrue(success, "Call succeeds but returns zero data for non-existent price ID");
        assertEq(pythPrice.price, 0, "Should return zero price for non-existent price ID");
        assertEq(pythPrice.conf, 0, "Should return zero confidence for non-existent price ID");
        assertEq(pythPrice.expo, 0, "Should return zero exponent for non-existent price ID");
        assertEq(pythPrice.publishTime, 0, "Should return zero publish time for non-existent price ID");
    }

    // ============ Integration Tests ============

    function test_fullWorkflow_ETHPrice() public {
        // Set up ETH price: $2000.00 with $10.00 confidence
        int64 price = 200000000000;
        uint64 conf = 1000000000;
        int32 expo = -8;
        uint256 publishTime = block.timestamp;

        // Use direct price setting
        mockPyth.updatePriceFeeds(ETH_PRICE_ID, price, conf, expo, publishTime);

        // Test full workflow
        (uint256 returnedPrice, uint256 returnedConf, bool valid) = OracleLib.getOraclePriceWithConfidence(
            IPyth(address(mockPyth)),
            ETH_PRICE_ID,
            DEFAULT_STALENESS_THRESHOLD
        );

        assertTrue(valid, "ETH price should be valid");
        assertEq(returnedPrice, 200000000000, "ETH price should be $2000.00");
        assertEq(returnedConf, 1000000000, "ETH confidence should be $10.00");

        // Test publish time
        uint256 retrievedPublishTime = OracleLib.getPublishTime(
            IPyth(address(mockPyth)),
            ETH_PRICE_ID
        );
        assertEq(retrievedPublishTime, publishTime, "Should return correct publish time");
    }

    function test_fullWorkflow_USDCPrice() public {
        // Set up USDC price: $1.00 with $0.005 confidence
        int64 price = 100000000;
        uint64 conf = 500000;
        int32 expo = -8;
        uint256 publishTime = block.timestamp;

        // Use direct price setting
        mockPyth.updatePriceFeeds(USDC_PRICE_ID, price, conf, expo, publishTime);

        // Test full workflow
        (uint256 returnedPrice, uint256 returnedConf, bool valid) = OracleLib.getOraclePriceWithConfidence(
            IPyth(address(mockPyth)),
            USDC_PRICE_ID,
            DEFAULT_STALENESS_THRESHOLD
        );

        assertTrue(valid, "USDC price should be valid");
        assertEq(returnedPrice, 100000000, "USDC price should be $1.00");
        assertEq(returnedConf, 500000, "USDC confidence should be $0.005");
    }
} 