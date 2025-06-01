# Pyth Network Integration Rules for DetoxHook

## 🐍 **CRITICAL PYTH NETWORK DOCUMENTATION**

**ALWAYS REFERENCE THESE PYTH DOCUMENTATION LINKS:**
- **Pyth Price Feeds Overview**: https://ethglob.al/22syi
- **Pyth Oracle Integration Guide**: https://ethglob.al/942q7  
- **Pyth Pull Model Documentation**: https://ethglob.al/3b9in
- **Pyth Confidence Intervals**: https://ethglob.al/4zupm
- **Pyth Hermes API Reference**: https://ethglob.al/nt1x6
- **Pyth Network Best Practices**: https://ethglob.al/52e6b

These are **ESSENTIAL REFERENCES** for any Pyth-related development in DetoxHook.

## 🔧 **PYTH INTEGRATION REQUIREMENTS**

### **1. Pull Oracle Model (CRITICAL)**
- **ALWAYS use Pyth's pull model** - fetch data exactly when needed in transactions
- **NEVER assume continuous price updates** - Pyth provides data on-demand
- Reference: https://ethglob.al/3b9in for pull model implementation

### **2. Price Feed Validation**
```solidity
// ALWAYS validate Pyth price data
PythStructs.Price memory price = pyth.getPriceUnsafe(priceId);
require(block.timestamp - price.publishTime < MAX_PRICE_AGE, "Price too stale");
require(price.conf < MAX_CONFIDENCE_INTERVAL, "Price confidence too wide");
```

### **3. Confidence Intervals (ESSENTIAL)**
- **ALWAYS check confidence intervals** before using price data
- **NEVER use prices with wide confidence bands** for MEV detection
- Reference: https://ethglob.al/4zupm for confidence interval handling

### **4. Hermes API Integration**
- Use **Hermes API** for off-chain price data fetching: https://ethglob.al/nt1x6
- Implement proper error handling for network requests
- Cache update data appropriately for gas optimization

## 🛡️ **DETOXHOOK PYTH INTEGRATION POINTS**

### **Smart Contract Integration**
1. **beforeSwap()** - Real-time price validation during swaps
2. **Price feed IDs** - ETH/USD and USDC/USD feeds
3. **Update data** - Proper encoding for on-chain consumption
4. **Gas optimization** - Minimize oracle calls, use getPriceUnsafe()

### **Frontend Integration**
- **SwapRouter frontend**: `packages/foundry/scripts-js/SwapRouterFrontend.cjs`
- **Hermes API integration** for testing and price fetching
- **Real-time price display** with confidence intervals

## 📋 **DEVELOPMENT GUIDELINES**

### **When Working with Pyth:**
1. **ALWAYS reference the documentation links above**
2. **Validate price freshness** (< 30 seconds for DetoxHook)
3. **Check confidence intervals** (< 1% for arbitrage detection)
4. **Handle oracle failures gracefully** - don't break swaps
5. **Test with real Hermes data** using SwapRouter frontend

### **Code Patterns to Follow:**
```solidity
// ✅ CORRECT: Proper Pyth integration
function validatePrice(bytes32 priceId) internal view returns (uint256) {
    PythStructs.Price memory price = pyth.getPriceUnsafe(priceId);
    
    // Validate freshness
    require(block.timestamp - price.publishTime < 30, "Price stale");
    
    // Validate confidence
    uint256 confidenceRatio = (price.conf * 10000) / uint256(price.price);
    require(confidenceRatio < 100, "Confidence too wide");
    
    return uint256(price.price);
}
```

### **JavaScript/TypeScript Patterns:**
```javascript
// ✅ CORRECT: Hermes API integration
async function fetchPythPriceData() {
    const url = `${PYTH_HERMES_API}/v2/updates/price/latest`;
    const params = {
        'ids[]': ETH_USD_PRICE_ID,
        'encoding': 'hex'
    };
    
    const response = await axios.get(url, { params, timeout: 30000 });
    
    // Validate response
    if (!response.data.binary || !response.data.parsed) {
        throw new Error("Invalid response format from Hermes API");
    }
    
    return response.data;
}
```

## 🚀 **DEPLOYMENT CONSIDERATIONS**

### **Environment Variables:**
```bash
# Pyth-specific configuration
PYTH_ENDPOINT=https://hermes.pyth.network
ETH_USD_PRICE_ID=0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
USDC_USD_PRICE_ID=0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a
```

### **Price Feed IDs (Arbitrum Sepolia)**
- **ETH/USD**: `0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace`
- **USDC/USD**: `0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a`

## 🔍 **DEBUGGING PYTH ISSUES**

### **Common Problems:**
1. **Stale prices** - Check publishTime vs block.timestamp
2. **Wide confidence** - Price feed may be volatile or illiquid
3. **Network errors** - Hermes API connectivity issues
4. **Gas failures** - Oracle calls can be expensive

### **Debugging Tools:**
- **SwapRouter frontend** - Test Pyth integration with `yarn swap-router --getpool`
- **Forge tests** - Fork testing with real Pyth data
- **Hermes API** - Direct API testing for price validation

### **Testing Commands:**
```bash
# Test Pyth integration
yarn swap-router --getpool                    # Get current pool configuration
yarn swap-router --swap 0.00002 false        # Execute small test swap

# Fork testing with real Pyth data
forge test --fork-url $ARBITRUM_SEPOLIA_RPC_URL -vvv
```

## 📚 **PYTH PULL MODEL ARCHITECTURE**

DetoxHook implements Pyth's revolutionary pull oracle model:

1. **On-demand data fetching** - Prices fetched exactly when needed
2. **Real-time arbitrage detection** using fresh Pyth prices
3. **Confidence-based validation** preventing false positives
4. **Gas-optimized oracle calls** with proper error handling

### **Why Pull Model is Essential:**
- **Traditional push oracles**: Continuously update on-chain (expensive, often stale)
- **Pyth's pull model**: Provides fresh data exactly when needed for each transaction
- **Sub-second latency**: 400ms updates for real-time MEV detection
- **Cost efficiency**: Only pay for oracle data when actually needed

## 🎯 **SUCCESS METRICS**

- **Oracle latency**: < 500ms for price updates
- **Confidence intervals**: < 1% for arbitrage detection
- **Gas efficiency**: < 50k gas per oracle call
- **Uptime**: > 99.9% oracle availability
- **Price freshness**: < 30 seconds for DetoxHook validation

## ⚠️ **CRITICAL REQUIREMENTS**

1. **NEVER deploy without Pyth integration testing**
2. **ALWAYS validate confidence intervals before using prices**
3. **NEVER assume oracle data is always available**
4. **ALWAYS handle oracle failures gracefully**
5. **NEVER use stale price data for MEV detection**

---

**🐍 Remember: Pyth Network's pull oracle model is ESSENTIAL to DetoxHook's success. Always reference the documentation links above for the latest best practices and implementation details.** 