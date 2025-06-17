// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PythLibrary
 * @notice Minimal Pyth oracle interfaces and structs for DetoxHook
 * @dev This replaces the full Pyth SDK dependency with just what we need
 */

library PythStructs {
    struct Price {
        // Price value with a given precision
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent (power of 10)
        int32 expo;
        // Unix timestamp when the price was published
        uint256 publishTime;
    }
}

/**
 * @title IPyth
 * @notice Minimal Pyth oracle interface
 */
interface IPyth {
    /**
     * @notice Returns the price and confidence interval for the given price feed id.
     * @dev This function returns the price without any safety checks.
     * @param id The price feed id
     * @return price The price data
     */
    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
    function getPriceNoOlderThan(bytes32 id, uint age) external view returns (PythStructs.Price memory);
}

/**
 * @title MockPyth
 * @notice Mock Pyth oracle for testing
 */
contract MockPyth is IPyth {
    mapping(bytes32 => PythStructs.Price) private prices;
    uint256 public validTimePeriod;
    uint256 public singleUpdateFeeInWei;

    constructor(uint256 _validTimePeriod, uint256 _singleUpdateFeeInWei) {
        validTimePeriod = _validTimePeriod;
        singleUpdateFeeInWei = _singleUpdateFeeInWei;
    }

    /**
     * @notice Update price feeds (compatible with existing tests)
     * @param id Price feed id
     * @param price Price value
     * @param conf Confidence interval
     * @param expo Price exponent
     * @param publishTime Publish timestamp
     */
    function updatePriceFeeds(
        bytes32 id,
        int64 price,
        uint64 conf,
        int32 expo,
        uint256 publishTime
    ) external {
        prices[id] = PythStructs.Price({
            price: price,
            conf: conf,
            expo: expo,
            publishTime: publishTime
        });
    }

    /**
     * @notice Get price without safety checks (for testing)
     */
    function getPriceUnsafe(bytes32 id) external view override returns (PythStructs.Price memory) {
        return prices[id];
    }

    /**
     * @notice Set price with current timestamp (convenience function for testing)
     */
    function setPrice(bytes32 id, int64 price, int32 expo) external {
        prices[id] = PythStructs.Price({
            price: price,
            conf: 0,
            expo: expo,
            publishTime: block.timestamp
        });
    }

    // Implement new IPyth interface functions for testing
    function getUpdateFee(bytes[] calldata updates) external view returns (uint256) {
        return singleUpdateFeeInWei * updates.length;
    }
    function updatePriceFeeds(bytes[] calldata updates) external payable {
        uint256 requiredFee = singleUpdateFeeInWei * updates.length;
        require(msg.value >= requiredFee, "MockPyth: insufficient fee");
        for (uint i = 0; i < updates.length; i++) {
            // Try/catch to revert with a clear error if decode fails
            try this._decodeAndUpdate(updates[i]) {
                // success
            } catch {
                revert("MockPyth: invalid update encoding");
            }
        }
    }
    // Internal helper for decoding and updating (for try/catch)
    function _decodeAndUpdate(bytes calldata update) external {
        require(msg.sender == address(this), "MockPyth: only self-call");
        (bytes32 priceId, uint64 timestamp, int64 price, uint64 conf, int32 expo) = abi.decode(update, (bytes32, uint64, int64, uint64, int32));
        prices[priceId] = PythStructs.Price({
            price: price,
            conf: conf,
            expo: expo,
            publishTime: timestamp
        });
    }
    function getPriceNoOlderThan(bytes32 id, uint) external view returns (PythStructs.Price memory) {
        return this.getPriceUnsafe(id);
    }
} 