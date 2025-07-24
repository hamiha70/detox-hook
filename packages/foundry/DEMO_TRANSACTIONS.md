# DetoxHook Demo Transactions

## 📋 Overview

This document defines the standard demo transactions used for DetoxHook testing and validation. These transactions are extracted from the passing unit tests in `DetoxHookV2.t.sol` and represent realistic usage scenarios.

## 🎯 Demo Transaction Scenarios

### **Scenario 1: Realistic ETH/USDC Arbitrage Detection**
*Source: `test_RealisticETHUSDCScenario()` in DetoxHookV2.t.sol*

#### **Pool Configuration**
- **Currency0**: Native ETH (`address(0)`)
- **Currency1**: MockUSDC (6 decimals)
- **Pool Price**: 1 ETH = 2500 USDC (for test baseline)
- **Fee**: 3000 (0.3%)
- **Tick Spacing**: 60

#### **Liquidity Provision**
```solidity
// Massive liquidity for realistic testing
uint256 LIQUIDITY_USDC_AMOUNT = 1000000 * 1e6; // 1M USDC
uint256 ethAmount = (LIQUIDITY_USDC_AMOUNT * 1e18) / (2500 * 1e6); // 400 ETH

// Tick range calculation
int24 tickSpacing = 60;
int24 tickLower = ((actualTick - 12000) / tickSpacing) * tickSpacing;
int24 tickUpper = ((actualTick + 12000) / tickSpacing) * tickSpacing;
```

#### **Oracle Setup (Arbitrage Opportunity)**
```solidity
// Create arbitrage opportunity: ETH underpriced in pool
mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, int64(3000 * 1e8), uint64(30 * 1e8), -8, uint64(block.timestamp));
mockOracle.updatePriceFeeds(USDC_USD_PRICE_ID, int64(1000 * 1e8), uint64(10 * 1e8), -8, uint64(block.timestamp));

// Pool price: 1 ETH = 2500 USDC
// Oracle price: 1 ETH = 3000 USDC  
// Result: ETH is underpriced in pool → arbitrage opportunity
```

#### **Demo Swap Transaction**
```solidity
// Small swap to test arbitrage capture
uint256 swapAmount = 1 * 1e6; // 1 USDC
bool zeroForOne = false; // USDC -> ETH (buy underpriced ETH)

SwapParams memory swapParams = SwapParams({
    zeroForOne: zeroForOne,
    amountSpecified: -int256(swapAmount), // Exact input
    sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
});

PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
    takeClaims: false,
    settleUsingBurn: false
});

BalanceDelta delta = swapRouter.swap(realisticPoolKey, swapParams, testSettings, "");
```

#### **Expected Results**
- **Arbitrage Detection**: Hook should detect price discrepancy
- **Fee Extraction**: Hook captures portion of arbitrage value
- **Event Emission**: `ArbitrageCaptured` event should be emitted
- **Balance Changes**: Hook balance should increase

## 🔧 Resource Requirements

### **For Demo Scenario 1**

#### **ETH Requirements**
- **Liquidity Provision**: ~400 ETH (calculated from 1M USDC at 2500 USDC/ETH)
- **Gas Costs**: ~0.1 ETH (pool initialization, liquidity, swaps)
- **Demo Account Funding**: 0.01 ETH per test account
- **Safety Buffer**: 500% (5x multiplier)
- **Total Estimated**: ~2000 ETH + buffer

#### **USDC Requirements (Minted)**
- **Pool Liquidity**: 1,000,000 USDC
- **Demo Account Funding**: 10,000 USDC per test account  
- **Test Swaps**: 1,000 USDC reserve
- **Total Estimated**: ~1,021,000 USDC

#### **Validation Rules**
1. **Liquidity-Swap Ratio**: Swap amounts should be ≤ 1/1000th of pool liquidity
   - Pool liquidity: 1M USDC
   - Max recommended swap: 1,000 USDC
   - Demo swap: 1 USDC ✅

2. **Price Reasonableness**: Pool prices should be within ±20% of market
   - Market ETH: ~3600 USDC  
   - Test pool: 2500 USDC (for arbitrage demo)
   - Acceptable for testing scenario ✅

## 🚀 Deployment Integration

### **Resource Estimation Usage**
The `EstimateDeploymentResources.s.sol` script uses these demo scenarios to:
1. Calculate realistic funding requirements
2. Validate liquidity-swap consistency
3. Ensure sufficient resources for demo execution

### **Frontend Integration**
The `SwapRouterFrontend.cjs` will implement these scenarios with:
1. Real Pyth price feeds via Hermes API
2. Live blockchain integration
3. User-friendly demo interface

## 📊 Transaction Templates

### **Template 1: Basic Arbitrage Test**
```javascript
// For frontend implementation
const demoTransaction = {
    poolPrice: 2500, // USDC per ETH
    oraclePrice: 3000, // USDC per ETH (20% higher)
    swapAmount: 1e6, // 1 USDC
    direction: "USDC_TO_ETH", // Buy underpriced ETH
    expectedArbitrage: true
};
```

### **Template 2: No Arbitrage Control**
```javascript
const controlTransaction = {
    poolPrice: 2500, // USDC per ETH  
    oraclePrice: 2500, // USDC per ETH (same)
    swapAmount: 1e6, // 1 USDC
    direction: "USDC_TO_ETH",
    expectedArbitrage: false
};
```

## 🔍 Testing Checklist

### **Before Deployment**
- [ ] Sufficient ETH balance for liquidity provision
- [ ] MockUSDC deployment and minting capability
- [ ] Hook deployment with correct permissions
- [ ] Pool initialization at target prices
- [ ] Oracle setup with price feeds

### **During Demo Execution**
- [ ] Monitor `ArbitrageCaptured` events
- [ ] Verify hook balance increases
- [ ] Check swap execution success
- [ ] Validate gas usage within limits

### **Post-Demo Validation**
- [ ] Compare actual vs. expected arbitrage capture
- [ ] Verify LP value distribution
- [ ] Check system remains operational
- [ ] Document any edge cases encountered

---

**💡 Note**: These demo transactions are designed for testnet environments with sufficient funding. Production usage will require careful consideration of gas costs and market conditions. 