# Uniswap V4 Custom Errors: Complete Guide

## 📋 **Overview**

Uniswap V4 uses custom errors extensively for gas efficiency and better error handling. This guide covers error identification, triggering mechanisms, and practical debugging approaches.

## 🔍 **Error Identification Mechanism**

### **1. Error Selector Format**
```solidity
// Custom errors are identified by their 4-byte selector
error InvalidTickRange(int24 tickLower, int24 tickUpper);
// Selector: 0xe450d38c (first 4 bytes of keccak256("InvalidTickRange(int24,int24)"))
```

### **2. Error Decoding Process**
```javascript
// JavaScript error decoding
function decodeCustomError(errorData) {
    const selector = errorData.slice(0, 10); // 0x + 8 hex chars
    const errorParams = errorData.slice(10);  // Remaining data
    
    const errorMap = {
        '0xe450d38c': 'InvalidTickRange',
        '0x7983c051': 'PoolAlreadyInitialized',
        '0x4e487b71': 'PoolNotInitialized',
        // ... more errors
    };
    
    return {
        selector: selector,
        name: errorMap[selector] || 'Unknown',
        params: errorParams
    };
}
```

### **3. Foundry Error Decoding**
```solidity
// In Foundry tests
try poolManager.initialize(poolKey, sqrtPriceX96) {
    // Success
} catch Error(string memory reason) {
    // String error
} catch (bytes memory lowLevelData) {
    // Custom error - decode selector
    bytes4 selector = bytes4(lowLevelData);
    if (selector == InvalidTickRange.selector) {
        // Handle specific error
    }
}
```

## 🚨 **Common Uniswap V4 Custom Errors**

### **Pool Management Errors**

#### **1. PoolAlreadyInitialized (0x7983c051)**
```solidity
error PoolAlreadyInitialized();
```
**Triggered when:**
- Attempting to initialize a pool that already exists
- Race condition during pool creation
- Duplicate initialization calls

**Example:**
```solidity
// Pool already exists at this key
poolManager.initialize(poolKey, sqrtPriceX96);
// Reverts with 0x7983c051
```

#### **2. PoolNotInitialized (0x4e487b71)**
```solidity
error PoolNotInitialized();
```
**Triggered when:**
- Attempting operations on non-existent pool
- Invalid pool key provided
- Pool was never initialized

**Example:**
```solidity
// Pool doesn't exist
poolManager.modifyLiquidity(nonExistentPoolKey, params);
// Reverts with 0x4e487b71
```

### **Tick and Range Errors**

#### **3. InvalidTickRange (0xe450d38c)**
```solidity
error InvalidTickRange(int24 tickLower, int24 tickUpper);
```
**Triggered when:**
- `tickLower >= tickUpper`
- Ticks outside valid range (-887272 to 887272)
- Ticks not aligned with tickSpacing

**Example:**
```solidity
ModifyLiquidityParams memory params = ModifyLiquidityParams({
    tickLower: 1000,  // Higher than tickUpper
    tickUpper: 500,
    liquidityDelta: 1000,
    salt: salt
});
// Reverts with 0xe450d38c
```

#### **4. TickOutOfBounds (0x4d2301ce)**
```solidity
error TickOutOfBounds(int24 tick);
```
**Triggered when:**
- Tick value exceeds ±887272
- Invalid tick arithmetic
- Tick overflow/underflow

### **Liquidity Errors**

#### **5. InvalidLiquidityAmount (0x4d2301cd)**
```solidity
error InvalidLiquidityAmount(uint256 liquidity);
```
**Triggered when:**
- Zero liquidity delta
- Excessive liquidity amount
- Invalid liquidity calculation

#### **6. InsufficientLiquidity (0x4d2301d4)**
```solidity
error InsufficientLiquidity(uint256 available, uint256 requested);
```
**Triggered when:**
- Removing more liquidity than available
- Liquidity position doesn't exist
- Insufficient balance for operation

### **Currency and Token Errors**

#### **7. CurrencyNotSettled (0x4d2301d5)**
```solidity
error CurrencyNotSettled(Currency currency);
```
**Triggered when:**
- Unsettled currency after operation
- Missing `settle()` call
- Incomplete balance accounting

**Example:**
```solidity
// Missing settlement
poolManager.modifyLiquidity(poolKey, params);
// Should call: poolManager.settle(currency)
```

#### **8. InvalidCurrencyOrder (0x4d2301d0)**
```solidity
error InvalidCurrencyOrder(Currency currency0, Currency currency1);
```
**Triggered when:**
- Currencies not in ascending order
- Duplicate currency addresses
- Invalid currency addresses

### **Hook and Permission Errors**

#### **9. InvalidHookAddress (0x4d2301d1)**
```solidity
error InvalidHookAddress(address hook);
```
**Triggered when:**
- Hook address doesn't implement required interface
- Hook permissions don't match pool key
- Invalid hook deployment

#### **10. HookCallFailed (0x4d2301d6)**
```solidity
error HookCallFailed(address hook, bytes reason);
```
**Triggered when:**
- Hook function reverts
- Hook returns invalid data
- Hook gas limit exceeded

## 🔧 **Error Triggering Mechanisms**

### **1. Pre-Execution Validation**
```solidity
function modifyLiquidity(PoolKey calldata key, ModifyLiquidityParams calldata params) external {
    // Pre-validation triggers errors
    if (params.tickLower >= params.tickUpper) {
        revert InvalidTickRange(params.tickLower, params.tickUpper);
    }
    
    if (params.tickLower < MIN_TICK || params.tickUpper > MAX_TICK) {
        revert TickOutOfBounds(params.tickLower);
    }
    
    // Continue with operation
}
```

### **2. State-Dependent Validation**
```solidity
function swap(PoolKey calldata key, SwapParams calldata params) external {
    // Check pool exists
    if (!_poolExists(key)) {
        revert PoolNotInitialized();
    }
    
    // Check liquidity availability
    if (params.amountSpecified > 0 && liquidity < requiredLiquidity) {
        revert InsufficientLiquidity(liquidity, requiredLiquidity);
    }
}
```

### **3. Post-Execution Validation**
```solidity
function _afterSwap() internal {
    // Validate settlement
    if (balanceDelta.amount0() != 0 || balanceDelta.amount1() != 0) {
        revert CurrencyNotSettled(currency);
    }
}
```

## 🛠️ **Debugging Custom Errors**

### **1. Foundry Trace Analysis**
```bash
# Run with verbose output
forge test --match-test testModifyLiquidity -vvv

# Example output:
# [FAIL] testModifyLiquidity() (gas: 123456)
# Error: InvalidTickRange(1000, 500)
# [0] 0xe450d38c
# [1] 0x00000000000000000000000000000000000000000000000000000000000003e8
# [2] 0x00000000000000000000000000000000000000000000000000000000000001f4
```

### **2. JavaScript Error Decoding**
```javascript
function decodeUniswapV4Error(errorData) {
    const selectors = {
        '0xe450d38c': {
            name: 'InvalidTickRange',
            decode: (data) => {
                const tickLower = parseInt(data.slice(0, 64), 16);
                const tickUpper = parseInt(data.slice(64, 128), 16);
                return { tickLower, tickUpper };
            }
        },
        '0x7983c051': {
            name: 'PoolAlreadyInitialized',
            decode: () => ({})
        }
        // Add more error decoders
    };
    
    const selector = errorData.slice(0, 10);
    const errorInfo = selectors[selector];
    
    if (errorInfo) {
        const params = errorInfo.decode(errorData.slice(10));
        return { name: errorInfo.name, params };
    }
    
    return { name: 'Unknown', selector };
}
```

### **3. Python Error Handling**
```python
def handle_uniswap_error(error_hex):
    """Decode Uniswap V4 custom errors"""
    if not error_hex.startswith('0x'):
        return f"Invalid error format: {error_hex}"
    
    selector = error_hex[:10]
    error_data = error_hex[10:] if len(error_hex) > 10 else ""
    
    error_map = {
        '0xe450d38c': 'InvalidTickRange',
        '0x7983c051': 'PoolAlreadyInitialized',
        '0x4e487b71': 'PoolNotInitialized',
        '0x4d2301cd': 'InvalidLiquidityAmount',
        '0x4d2301ce': 'TickOutOfBounds',
        '0x4d2301d0': 'InvalidCurrencyOrder',
        '0x4d2301d1': 'InvalidHookAddress',
        '0x4d2301d5': 'CurrencyNotSettled'
    }
    
    error_name = error_map.get(selector, 'Unknown')
    
    # Decode parameters for specific errors
    if selector == '0xe450d38c' and len(error_data) >= 128:
        tick_lower = int(error_data[:64], 16)
        tick_upper = int(error_data[64:128], 16)
        return f"{error_name}(tickLower={tick_lower}, tickUpper={tick_upper})"
    
    return f"{error_name} (selector: {selector})"
```

## 📊 **Error Prevention Strategies**

### **1. Input Validation**
```solidity
function validatePoolKey(PoolKey calldata key) internal pure {
    require(key.currency0 < key.currency1, "Invalid currency order");
    require(key.fee > 0, "Invalid fee");
    require(key.tickSpacing > 0, "Invalid tick spacing");
}
```

### **2. Tick Alignment**
```solidity
function alignTicks(int24 tickLower, int24 tickUpper, uint24 tickSpacing) internal pure returns (int24, int24) {
    tickLower = (tickLower / tickSpacing) * tickSpacing;
    tickUpper = (tickUpper / tickSpacing) * tickSpacing;
    return (tickLower, tickUpper);
}
```

### **3. Liquidity Bounds**
```solidity
function validateLiquidityParams(ModifyLiquidityParams calldata params) internal pure {
    require(params.tickLower < params.tickUpper, "Invalid tick range");
    require(params.liquidityDelta != 0, "Zero liquidity delta");
    require(params.tickLower >= MIN_TICK && params.tickUpper <= MAX_TICK, "Ticks out of bounds");
}
```

## 🎯 **Best Practices**

### **1. Error Handling in Tests**
```solidity
function testInvalidTickRange() public {
    vm.expectRevert(abi.encodeWithSelector(InvalidTickRange.selector, 1000, 500));
    poolManager.modifyLiquidity(poolKey, invalidParams);
}
```

### **2. Graceful Error Recovery**
```solidity
function safeModifyLiquidity(PoolKey calldata key, ModifyLiquidityParams calldata params) external {
    try poolManager.modifyLiquidity(key, params) returns (BalanceDelta delta) {
        // Success
        emit LiquidityModified(delta);
    } catch Error(string memory reason) {
        // String error
        emit LiquidityError(reason);
    } catch (bytes memory lowLevelData) {
        // Custom error
        emit CustomError(lowLevelData);
    }
}
```

### **3. Comprehensive Logging**
```solidity
function logError(bytes memory errorData) internal {
    console.log("Error selector:", vm.toString(bytes4(errorData)));
    console.log("Error data:", vm.toString(errorData));
}
```

## 📚 **Resources**

- **Uniswap V4 Documentation**: https://docs.uniswap.org/contracts/v4/overview
- **Custom Errors Guide**: https://docs.soliditylang.org/en/latest/contracts.html#errors
- **Foundry Testing**: https://book.getfoundry.sh/forge/tests
- **Error Decoding Tools**: https://github.com/ethereum-js/ethereum-js

---

**This comprehensive guide covers Uniswap V4 custom error identification, triggering mechanisms, and practical debugging approaches for DetoxHook development.** 🛡️ 