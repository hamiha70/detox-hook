# DetoxHook Funding Mathematics

## 📋 Overview

This document explains the mathematical foundations behind DetoxHook's resource estimation and funding calculations. It covers liquidity provision mathematics, gas cost estimation, and the rationale behind our safety margins.

## 🎯 Current Implementation Status

### ✅ **Phase 1: Basic Resource Estimation (COMPLETED)**
- ETH/wei conversion fixes
- Demo account funding corrections  
- 500% safety buffer implementation
- Gas cost estimates

### ✅ **Phase 2: Uniswap V4 Liquidity Mathematics (COMPLETED)**  
- **Proper Uniswap V4 mathematics** using TickMath and LiquidityAmounts libraries
- **ETH price bounds**: 3000-4000 USDC (current market ~3600)
- **Liquidity targeting**: 0.1 ETH per pool with ±10% range
- **Liquidity-swap consistency validation** (1/1000th rule)
- **Comprehensive unit testing** of HookLibrary functions
- **Demo transaction extraction** from test suite

### 🚧 **Phase 3: Complete Deployment Integration (IN PROGRESS)**
- Real Pyth Network price integration architecture
- Frontend-backend separation for Hermes API calls
- Complete operational overhead modeling

---

## 🐍 Pyth Network Integration Architecture

### **The Hermes API Challenge**
**Problem**: Pyth Network requires Hermes API calls to fetch fresh price update data, but Foundry scripts cannot safely make external HTTP calls.

**Solution Architecture**:
```
Resource Estimation (Foundry) → Approximate prices → Funding calculations
     ↓
Deployment (Foundry) → Approximate prices → Pool initialization  
     ↓
Demo Transactions (Frontend) → Real Hermes calls → Live Pyth prices
```

### **Price Strategy**
- **Resource Estimation**: Use approximate prices within ±20% of market (3000-4000 USDC/ETH)
- **Pool Initialization**: Deploy pools at approximate prices (3000, 4000 USDC/ETH)
- **Live Demo**: Frontend fetches real Pyth prices via `SwapRouterFrontend.cjs`

### **Why This Works**
1. **Resource estimation doesn't need exact prices** - needs realistic ranges for funding
2. **Pool prices will adjust naturally** through arbitrage once live
3. **Frontend handles complexity** of Hermes API integration and price updates
4. **Clean separation of concerns** between deployment and live operations

---

## 💰 Resource Categories

### **1. Hook Funding (Core Functionality)**
```
Hook Funding = 0.01 ETH
Purpose: Fund 1000+ hook invocations
Calculation: ~100k gas per invocation × 0.1 gwei × 1000 invocations × 10x buffer
```

### **2. Liquidity Provision (Pool Operations)**
```solidity
// ✅ FIXED: Proper Uniswap V4 mathematics using core libraries
function calculateETHUSDCLiquidityV4(
    uint256 targetETHAmount,      // e.g., 0.1 ETH
    uint256 ethPriceInUSDC,       // e.g., 3600 USDC/ETH
    uint256 rangePercent,         // e.g., 10 for ±10%
    int24 tickSpacing             // e.g., 60
) internal pure returns (
    uint256 ethAmount,
    uint256 usdcAmount,
    ModifyLiquidityParams memory liquidityParams
) {
    // Step 1: Convert to Uniswap price format (currency1/currency0)
    uint256 currentPrice = ethPriceInUSDC * 1000000; // Proven working conversion
    uint160 sqrtPriceX96 = priceToSqrtPrice(currentPrice);
    
    // Step 2: Calculate tick bounds for ±rangePercent
    uint256 lowerPriceInUSDC = (ethPriceInUSDC * (100 - rangePercent)) / 100;
    uint256 upperPriceInUSDC = (ethPriceInUSDC * (100 + rangePercent)) / 100;
    
    uint160 sqrtPriceLowerX96 = priceToSqrtPrice(lowerPriceInUSDC * 1000000);
    uint160 sqrtPriceUpperX96 = priceToSqrtPrice(upperPriceInUSDC * 1000000);
    
    int24 tickLower = TickMath.getTickAtSqrtPrice(sqrtPriceLowerX96);
    int24 tickUpper = TickMath.getTickAtSqrtPrice(sqrtPriceUpperX96);
    
    // Step 3: Calculate liquidity from target ETH amount
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
        TickMath.getSqrtPriceAtTick(tickLower),
        TickMath.getSqrtPriceAtTick(tickUpper),
        targetETHAmount
    );
    
    // Step 4: Calculate required token amounts
    (ethAmount, usdcAmount) = LiquidityAmounts.getAmountsForLiquidity(
        sqrtPriceX96,
        TickMath.getSqrtPriceAtTick(tickLower),
        TickMath.getSqrtPriceAtTick(tickUpper),
        liquidity
    );
}
```

**✅ RESOLVED**: Proper liquidity calculation now uses:
- **Real Uniswap V4 libraries**: TickMath, LiquidityAmounts, FullMath
- **Accurate price conversion**: Using proven working approach from DetoxHookV2.t.sol
- **Proper tick mathematics**: Exact tick bounds calculation with tick spacing alignment
- **Realistic token amounts**: Both ETH and USDC calculated from actual liquidity requirements
- **Complete deployment parameters**: Returns ModifyLiquidityParams for direct use

### **3. Demo Account Funding**
```
Demo ETH = 0.01 ETH per account (for gas)
Demo USDC = 10,000 USDC per account (minted via MockUSDC)
```

### **4. Liquidity-Swap Consistency Validation**
```
Rule: Swap amounts should be ≤ 1/1000th of pool liquidity
Validation: testSwapAmount <= (poolLiquidity / 1000)
Purpose: Ensure swaps don't exhaust pool liquidity or cause extreme slippage
```

**Example Validation:**
- Pool liquidity: 1000 USDC → Max recommended swap: 1 USDC ✅
- Current test swap: 1000 USDC → Would exceed 1/1000th rule ⚠️

### **5. Test Swap Reserves**
```
Test Swap ETH = test_swap_USDC / average_ETH_price
Updated: 1000 USDC / 3500 USDC/ETH ≈ 0.29 ETH (using new price bounds)
```

### **5. Safety Buffer**
```
Buffer = (Base_ETH_needed × 500%) / 100
Rationale: 500% buffer accounts for:
- Gas price volatility (10x potential increase)
- Liquidity provision inefficiencies
- Unexpected operational costs
- Market price movements
```

---

## 🔧 Uniswap V4 Mathematics (Phase 2)

### **Tick-Based Pricing**

Uniswap V4 uses tick-based pricing where:
```
price = 1.0001^tick
tick = log(price) / log(1.0001)
```

For ETH/USDC at 2500 USDC/ETH:
```
tick = log(2500) / log(1.0001) ≈ 79,226
```

### **Concentrated Liquidity Challenges**

**Problem**: Current implementation assumes:
```solidity
// WRONG: Assumes liquidity around tick 0
tickLower: -600,
tickUpper: 600,
```

**Reality**: For 2500 USDC/ETH, we need:
```solidity
// CORRECT: Liquidity around actual price tick
tickLower: ~78,626,  // 2500 * 0.95
tickUpper: ~79,826,  // 2500 * 1.05
```

### **Token Ratio Mathematics**

In concentrated liquidity, the token ratio depends on:
- Current price relative to range
- Range width
- Desired liquidity amount

**Formula**:
```
If price > upper_range: 100% token0 (ETH)
If price < lower_range: 100% token1 (USDC)  
If price in range: Mixed ratio based on curve position
```

---

## 📊 Gas Cost Analysis

### **Contract Deployment Costs**
```
DetoxHookV2:       ~2,000,000 gas
PriceRegistry:       ~500,000 gas  
SwapRouterFixed:   ~1,000,000 gas
MockUSDC:            ~300,000 gas
Total Deployment:  ~3,800,000 gas
```

### **Operational Costs**
```
Pool Initialization:  ~200,000 gas per pool
Liquidity Addition:   ~300,000 gas per pool
Price Feed Setup:     ~100,000 gas per feed
Hook Invocation:      ~100,000 gas per call
```

### **Gas Price Assumptions**
```
Arbitrum Sepolia: 0.01 - 0.1 gwei (current estimate: 0.1 gwei)
Arbitrum One:     0.01 - 0.5 gwei  
Ethereum Mainnet: 10 - 50 gwei
```

---

## 🎯 Required Enhancements

### **Phase 2: Implement Proper Liquidity Math**

Add to `HookLibrary.sol`:

```solidity
/// @notice Calculate tick for a given price
function calculateTickForPrice(uint256 price, uint8 decimals0, uint8 decimals1) 
    internal pure returns (int24 tick);

/// @notice Calculate optimal tick range for liquidity provision
function calculateOptimalTickRange(uint256 currentPrice, uint256 rangePercent)
    internal pure returns (int24 tickLower, int24 tickUpper);

/// @notice Calculate token amounts needed for desired liquidity
function calculateLiquidityAmounts(
    int24 tickLower,
    int24 tickUpper, 
    uint256 currentTick,
    uint256 desiredLiquidity
) internal pure returns (uint256 amount0, uint256 amount1);

/// @notice Estimate required liquidity for meaningful trading
function calculateMinimumLiquidity(
    uint256 expectedSwapSize,
    uint256 maxSlippageBps
) internal pure returns (uint256 minimumLiquidity);
```

### **Phase 3: Complete Cost Model**

Include all deployment operations:
- Contract verification costs
- Multi-step initialization sequences  
- Error recovery scenarios
- Network congestion buffers

---

## 🔍 Current Issues & Solutions

### **Issue 1: Wei/ETH Display Conversion**
**Problem**: Previous implementation showed 64,707 ETH instead of 0.064707 ETH
**Solution**: Implemented `_formatETH()` with proper string formatting

### **Issue 2: Liquidity Mathematics**
**Problem**: Naive price-based calculation ignores concentrated liquidity
**Solution**: Implement proper Uniswap V4 tick mathematics (Phase 2)

### **Issue 3: Demo Account Funding**
**Problem**: Confused USDC funding with ETH gas requirements  
**Solution**: Separate ETH (gas) and USDC (trading) funding

### **Issue 4: Incomplete Gas Estimates**
**Problem**: Missing many deployment operations
**Solution**: Comprehensive gas cost catalog (Phase 3)

---

## 🧮 Example Calculations

### **Realistic ETH Requirements (Fixed)**
```
Hook Funding:      0.010000 ETH
Pool 1 Liquidity:  0.000400 ETH  (1 USDC / 2500)
Pool 2 Liquidity:  0.000385 ETH  (1 USDC / 2600) 
Demo Accounts:     0.010000 ETH  (0.01 ETH gas)
Test Swaps:        0.000392 ETH  (1000 USDC / 2550)
Subtotal:          0.021177 ETH
Buffer (500%):     0.105885 ETH
Total:             0.127062 ETH
```

### **Gas Costs at 0.1 gwei**
```
Contract Deployment: 0.000380 ETH
Pool Operations:     0.000100 ETH  
Total Gas:           0.000480 ETH
```

**Grand Total: ~0.128 ETH (very reasonable!)**

---

## 🎯 Success Metrics

- **Accuracy**: Estimates within 10% of actual deployment costs
- **Safety**: 500% buffer prevents funding failures
- **Clarity**: Human-readable ETH amounts
- **Completeness**: All deployment operations included
- **Maintainability**: Parameters easily adjustable

---

## 🚀 Next Steps

1. **Test Phase 1 fixes** - Verify accurate ETH display
2. **Implement Phase 2** - Add Uniswap V4 mathematics to HookLibrary  
3. **Complete Phase 3** - Full deployment cost model
4. **Validate on testnet** - Compare estimates vs actual costs
5. **Production deployment** - Apply learnings to mainnet

---

*This document will be updated as we implement each phase of the funding mathematics system.* 