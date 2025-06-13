# SwapRouter Script Suite - Complete Documentation

## 🎯 **Overview**

The DetoxHook project includes a comprehensive suite of SwapRouter scripts for testing, validation, and interaction with the Uniswap V4 DetoxHook system. Each script serves a specific purpose and provides different levels of functionality.

## 📋 **Script Summary**

| Script | Purpose | Complexity | Best For |
|--------|---------|------------|----------|
| `SwapRouterFrontend.cjs` | Original full-featured script | High | Production testing |
| `SwapRouterOptimized.cjs` | Performance-optimized version | Medium | Fast operations |
| `SwapRouterAdvanced.cjs` | Multi-currency, multi-type support | High | Advanced configurations |
| `SwapRouterValidator.cjs` | System state validation | Medium | Health checks |

---

## 🔧 **1. SwapRouterFrontend.cjs - Original Full-Featured Script**

### **Purpose**
The original comprehensive script with all features including Pyth integration, systematic testing, and complete swap functionality.

### **Key Features**
- ✅ Complete Pyth Hermes API integration
- ✅ ETH ↔ USDC swaps with MEV detection
- ✅ Token approval management
- ✅ Systematic testing suite
- ✅ Pool configuration management
- ✅ Comprehensive error handling

### **Usage**
```bash
# Basic swaps
yarn swap-router --swap 0.01 true          # 0.01 ETH → USDC
yarn swap-router --swap 50 false           # 50 USDC → ETH

# Pool management
yarn swap-router --getpool                 # Get current pool config
yarn swap-router --updatepool <params>     # Update pool configuration

# Token management
yarn swap-router --approve                 # Approve USDC for SwapRouter
yarn swap-router --wallet 0x123...         # Set funding wallet

# Testing
yarn swap-router --test                    # Run systematic tests
```

### **When to Use**
- Production testing and validation
- Complete system integration testing
- When you need all features in one script
- For comprehensive MEV detection analysis

---

## 🚀 **2. SwapRouterOptimized.cjs - Performance-Optimized Version**

### **Purpose**
Streamlined version focused on performance with caching, parallel operations, and enhanced error handling.

### **Key Features**
- ✅ 30-second caching for frequently accessed data
- ✅ Parallel API calls for better performance
- ✅ Enhanced retry mechanisms with exponential backoff
- ✅ Multiple price feed support (ETH/USD, USDC/USD)
- ✅ Price staleness and confidence validation
- ✅ Modular code structure

### **Usage**
```bash
# Fast swaps with caching
yarn swap-router-opt --swap 0.01 true      # Optimized ETH → USDC
yarn swap-router-opt --getpool             # Cached pool configuration
yarn swap-router-opt --test                # Fast systematic testing
```

### **When to Use**
- High-frequency testing scenarios
- When performance is critical
- For automated testing pipelines
- When you need reliable retry mechanisms

---

## 🎛️ **3. SwapRouterAdvanced.cjs - Multi-Currency & Multi-Type Support**

### **Purpose**
Advanced script with comprehensive command-line parameter management, preset configurations, and support for multiple swap types.

### **Key Features**
- ✅ **Preset Configurations**: Pre-defined swap scenarios
- ✅ **Multiple Currencies**: ETH, USDC, extensible to more
- ✅ **Swap Types**: Exact input and exact output
- ✅ **Directions**: zeroForOne and oneForZero
- ✅ **Configuration Files**: JSON-based configuration
- ✅ **Advanced CLI**: Comprehensive parameter management

### **Available Presets**
```bash
# List all available presets
yarn swap-advanced --list-presets

# Available presets:
# - eth-to-usdc: ETH → USDC (exact input)
# - usdc-to-eth: USDC → ETH (exact input)  
# - eth-to-usdc-exact-out: ETH → USDC (exact output)
# - usdc-to-eth-exact-out: USDC → ETH (exact output)
# - small-test: Small test swap (0.001 ETH)
```

### **Usage Examples**

#### **Preset-Based Usage**
```bash
# Use presets for common scenarios
yarn swap-advanced --preset eth-to-usdc --amount 0.01
yarn swap-advanced --preset usdc-to-eth --amount 50
yarn swap-advanced --preset small-test
```

#### **Advanced Configuration**
```bash
# Exact input swaps
yarn swap-advanced --currency0 ETH --currency1 USDC --amount 0.01 --exact-input --zero-for-one

# Exact output swaps  
yarn swap-advanced --currency0 USDC --currency1 ETH --amount 0.01 --exact-output --one-for-zero

# Custom price feeds
yarn swap-advanced --preset eth-to-usdc --amount 0.01 --price-feeds ETH_USD,USDC_USD
```

#### **Configuration Management**
```bash
# Validate configuration without executing
yarn swap-advanced --preset eth-to-usdc --amount 0.01 --validate-config

# Use custom configuration file
yarn swap-advanced --config custom-swap.json --amount 0.01
```

### **Configuration File Format**
```json
{
  "currency0": "ETH",
  "currency1": "USDC", 
  "swapType": "exact-input",
  "direction": "zero-for-one",
  "priceFeeds": ["ETH_USD", "USDC_USD"],
  "description": "Custom ETH to USDC swap"
}
```

### **When to Use**
- When you need specific swap configurations
- For testing different swap types and directions
- When working with multiple currencies
- For automated testing with various parameters
- When you want preset configurations for common scenarios

---

## 🔍 **4. SwapRouterValidator.cjs - System State Validation**

### **Purpose**
Comprehensive system health checker that validates all components of the DetoxHook ecosystem.

### **Key Features**
- ✅ **Network Connectivity**: RPC connection and chain validation
- ✅ **Contract Deployments**: Verify all contracts are deployed
- ✅ **Pool Configuration**: Validate pool setup and parameters
- ✅ **Token States**: Check balances, approvals, and token properties
- ✅ **Pyth Integration**: Test oracle connectivity and data quality
- ✅ **Integration Tests**: Gas estimation and system integration

### **Validation Categories**

#### **Network Validation**
- RPC connectivity to Arbitrum Sepolia
- Chain ID verification
- Wallet configuration and balance checks

#### **Contract Validation**
- SwapRouterFixed deployment verification
- DetoxHook contract accessibility
- USDC token contract validation
- PoolManager and PoolSwapTest integration

#### **Pool Validation**
- Currency pair configuration (ETH/USDC)
- Fee tier and tick spacing validation
- DetoxHook integration verification

#### **Token Validation**
- USDC token properties (symbol, decimals)
- Wallet balances (ETH and USDC)
- Token approvals for SwapRouter

#### **Pyth Validation**
- Hermes API connectivity
- Price data freshness and confidence
- Update data format validation

#### **Integration Validation**
- Gas estimation for sample swaps
- PoolSwapTest integration
- DetoxHook accessibility

### **Usage**
```bash
# Basic validation
yarn validate-system

# Detailed validation with additional checks
yarn validate-system --detailed

# Help and usage information
yarn validate-system --help
```

### **Sample Output**
```
🔍 DetoxHook System Validator - Comprehensive State Check
================================================================================
🌐 Network: Arbitrum Sepolia (421614)
📅 Validation Time: 2024-01-15T10:30:00.000Z
================================================================================

✅ [NETWORK] RPC Connection: Connected to Arbitrum Sepolia
✅ [NETWORK] Wallet Balance: Sufficient balance: 0.050000 ETH
✅ [CONTRACTS] SwapRouterFixed Deployment: Contract deployed
✅ [CONTRACTS] DetoxHook Deployment: Contract deployed
✅ [POOL] Currency0 (ETH): ETH (native currency)
✅ [POOL] Currency1 (USDC): Correct USDC address
✅ [TOKENS] USDC Symbol: Correct symbol: USDC
✅ [PYTH] Hermes API Connectivity: Successfully connected to Pyth Hermes API
✅ [PYTH] ETH/USD Price Data: $2,345.67 (±0.045%)

📊 VALIDATION SUMMARY
================================================================================
NETWORK      | ✅  3 | ❌  0 | ⚠️   1 | 75.0%
CONTRACTS    | ✅  5 | ❌  0 | ⚠️   0 | 100.0%
POOL         | ✅  4 | ❌  0 | ⚠️   1 | 80.0%
TOKENS       | ✅  3 | ❌  0 | ⚠️   2 | 60.0%
PYTH         | ✅  4 | ❌  0 | ⚠️   0 | 100.0%
INTEGRATION  | ✅  2 | ❌  0 | ⚠️   1 | 66.7%
================================================================================
OVERALL      | ✅ 21 | ❌  0 | ⚠️   5 | 80.8%
================================================================================

⚠️  System is operational with minor warnings. Review recommended.
```

### **When to Use**
- Before running important tests or deployments
- To diagnose system issues
- For health checks in CI/CD pipelines
- When troubleshooting swap failures
- To verify system state after deployments

---

## 🎯 **Choosing the Right Script**

### **For Quick Testing**
```bash
yarn swap-router-opt --swap 0.001 true     # Fast, cached operations
```

### **For Production Validation**
```bash
yarn validate-system                       # Check system health first
yarn swap-router --test                    # Comprehensive testing
```

### **For Specific Configurations**
```bash
yarn swap-advanced --preset small-test     # Predefined scenarios
yarn swap-advanced --list-presets          # See all options
```

### **For System Debugging**
```bash
yarn validate-system --detailed            # Comprehensive diagnostics
yarn swap-router --getpool                 # Check pool configuration
```

---

## 🔧 **Common Configuration**

All scripts share the same core configuration:

### **Environment Variables**
```bash
# Required
DEPLOYMENT_WALLET=0x...                    # Your wallet address
DEPLOYMENT_KEY=0x...                       # Your private key

# Optional
ARBITRUM_SEPOLIA_RPC_URL=https://...       # Custom RPC URL
```

### **Contract Addresses (Arbitrum Sepolia)**
- **SwapRouterFixed**: `0x7dD454F098f74eD0464c3896BAe8412C8b844E7e`
- **DetoxHook**: `0x444F320aA27e73e1E293c14B22EfBDCbce0e0088`
- **USDC Token**: `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d`
- **PoolManager**: `0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829`

### **Pyth Price Feeds**
- **ETH/USD**: `0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace`
- **USDC/USD**: `0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a`

---

## 🚨 **Important Notes**

### **Safety Rules**
- ✅ All scripts are **read-only by default** for validation
- ✅ **Never deploy to real networks** without explicit user approval
- ✅ **Never modify .env files** - user manages credentials
- ✅ All transactions require explicit confirmation

### **Testing Best Practices**
1. **Always validate first**: `yarn validate-system`
2. **Start small**: Use small amounts for initial testing
3. **Check approvals**: Ensure USDC is approved before swaps
4. **Monitor gas**: Check gas estimates before execution
5. **Verify results**: Check transaction receipts and balances

### **Troubleshooting**
- **Gas estimation failures**: Usually indicates the swap would revert
- **Oracle connectivity issues**: Check network connection to Pyth Hermes
- **Approval failures**: Ensure sufficient USDC balance and gas
- **Hook integration issues**: Verify DetoxHook is properly deployed

---

## 📚 **Additional Resources**

- **Pyth Network Documentation**: https://docs.pyth.network/
- **Uniswap V4 Documentation**: https://docs.uniswap.org/
- **DetoxHook Architecture**: See project documentation
- **Arbitrum Sepolia Explorer**: https://sepolia.arbiscan.io/

---

**🛡️ The SwapRouter Script Suite provides comprehensive tools for testing and validating the DetoxHook ecosystem, ensuring reliable and safe operation of the MEV protection system.** 