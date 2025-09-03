# InitializeFXPool - MockEURC/MockUSDC Liquidity Pool Initialization

## 📋 **Overview**

The `InitializeFXPool_v1.s.sol` script creates a new Uniswap V4 liquidity pool for trading MockEURC (Euro Coin) against MockUSDC (USD Coin). This pool simulates a real-world EUR/USD foreign exchange trading pair with MEV protection via DetoxHook.

**Key Features:**
- **FX Trading Pair**: MockEURC/MockUSDC (EUR/USD)
- **Initial Price**: 1 MockUSDC = 0.86 MockEURC
- **MEV Protection**: DetoxHook integration for fair trading
- **Network Support**: Arbitrum Sepolia (testnet)
- **Fee Structure**: 0.03% (300 basis points)

## 🎯 **Pool Configuration**

### **Token Pair**
- **Currency0**: MockEURC (Euro Coin)
- **Currency1**: MockUSDC (USD Coin)
- **Trading Direction**: MockEURC → MockUSDC

### **Price Configuration**
```
Initial Price: 1 MockUSDC = 0.86 MockEURC
FX Rate: EUR/USD ~ 0.86 (EUR is weaker than USD)
Target Tick: 1480 (aligned with tick spacing 40)
SqrtPriceX96: 85070591730234615865843651857942052864 (corrected calculation)
```

### **Pool Parameters**
- **Fee Tier**: 300 (0.03%)
- **Tick Spacing**: 40
- **Hooks**: DetoxHook for MEV protection
- **Network**: Arbitrum Sepolia (Chain ID: 421614)

## 🚀 **Prerequisites**

### **1. Required Contracts Deployed**
Before running this script, ensure these contracts are deployed:

- ✅ **PoolManager**: Uniswap V4 pool manager
- ✅ **MockUSDC**: USD Coin mock token
- ✅ **MockEURC**: Euro Coin mock token (deploy using MockEURC scripts)
- ✅ **DetoxHook**: MEV protection hook

### **2. Environment Variables**
Set these environment variables in your `.env` file:

```bash
# Required for pool initialization
DEPLOYMENT_WALLET=0xYourWalletAddress
DEPLOYMENT_PRIVATE_KEY=0xYourPrivateKey

# Optional: Network-specific settings
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
```

### **3. Contract Addresses**
Update the contract addresses in `InitializeFXPool_v1.s.sol`:

```solidity
address constant POOL_MANAGER_ADDRESS = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
address constant MOCK_USDC_ADDRESS = 0x9D5A68fDFEcc14683324640D5e835936422a47b1;
address constant MOCK_EURC_ADDRESS = 0xYourDeployedMockEURCAddress; // UPDATE THIS
address constant DETOX_HOOK_ADDRESS = 0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088;
```

## 📋 **Step-by-Step Deployment Guide**

### **Step 1: Deploy MockEURC Token**

First, deploy the MockEURC token using the MockEURC deployment scripts:

```bash
# Navigate to MockEURC directory
cd packages/foundry/script/ERC20/MockEURC

# Deploy MockEURC to Arbitrum Sepolia
forge script Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  --verifier-url https://api-sepolia.arbiscan.io/api
```

**Save the deployed MockEURC address** - you'll need it for the next step.

### **Step 2: Update Contract Addresses**

Edit `InitializeFXPool_v1.s.sol` and update the MockEURC address:

```solidity
address constant MOCK_EURC_ADDRESS = 0xYourDeployedMockEURCAddress;
```

### **Step 3: Initialize the FX Pool**

Run the pool initialization script:

```bash
# Navigate to Pool directory
cd packages/foundry/script/Pool

# Initialize the MockEURC/MockUSDC pool
forge script InitializeFXPool_v1.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

### **Step 4: Verify Pool Creation**

Check the console output for successful initialization:

```
=== FX Pool Initialization Summary ===
Pool: MockEURC/MockUSDC
Fee: 0.03% (300)
Tick Spacing: 40
Initial Price: 1 MockUSDC = 0.86 MockEURC
FX Rate: EUR/USD ~ 0.86
DetoxHook: ACTIVE for MEV protection
Pool ID: [Pool ID will be displayed here]

[SUCCESS] FX Pool initialization completed successfully!
Ready for liquidity provision and EUR/USD trading!
```

## 🔍 **Understanding the Price Configuration**

### **Price Calculation**

The script sets up a pool where:
- **1 MockUSDC = 0.86 MockEURC**
- This represents EUR/USD ≈ 0.86 (EUR is weaker than USD)

### **Tick Alignment**

- **Target Tick**: 1480
- **Tick Spacing**: 40
- **Validation**: 1480 % 40 = 0 ✓ (properly aligned)

### **SqrtPriceX96 Format**

The `INITIAL_SQRT_PRICE_X96` value is calculated for tick 1480 and represents the square root of the price in X96 format, which is the standard Uniswap V4 price representation.

**Calculation Details:**
- **Formula**: `sqrtPriceX96 = sqrt(price) * 2^96`
- **For tick 1480**: `1.0001^(1480/2) * 2^96`
- **Result**: `85070591730234615865843651857942052864`

**Important**: The script now includes automatic verification to ensure the pool is actually created with the correct price.

## 📊 **Pool State After Initialization**

### **What Gets Created**
- ✅ **Pool Structure**: Uniswap V4 pool with specified parameters
- ✅ **Initial Price**: Set to 1 MockUSDC = 0.86 MockEURC
- ✅ **MEV Protection**: DetoxHook integrated and active
- ✅ **Trading Ready**: Pool can accept liquidity and trades

### **What Does NOT Get Created**
- ❌ **No Liquidity**: Pool is empty and ready for LP provision
- ❌ **No Trading Pairs**: No actual tokens are deposited
- ❌ **No LP Positions**: Liquidity providers need to add positions separately

## 🧪 **Testing the Pool**

### **1. Check Pool Status**

```bash
# Get pool information
cast call $POOL_MANAGER_ADDRESS "getSlot0(bytes32)" $POOL_ID --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

### **2. Verify Pool Exists**

```bash
# Check if pool has been initialized
cast call $POOL_MANAGER_ADDRESS "getSlot0(bytes32)" $POOL_ID --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

If the pool exists, you'll get the current sqrt price. If it doesn't exist, the call will revert.

## 🔧 **Troubleshooting**

### **Common Issues**

| Issue | Solution |
|-------|----------|
| "MOCK_EURC_ADDRESS not set" | Update the contract address in the script |
| "Must run on Arbitrum Sepolia" | Ensure you're using the correct RPC URL |
| "Pool already exists" | Pool is already initialized - no action needed |
| "Insufficient ETH balance" | Fund your deployment wallet with ETH |
| "Pool verification failed" | Pool wasn't created due to invalid parameters |
| "Zero initial price" | Script bug - use corrected version with proper sqrtPriceX96 |

### **Error Messages**

```bash
# Contract not found
Error: No contract found at MockEURC address
Solution: Deploy MockEURC first or check the address

# Wrong network
Error: Must run on Arbitrum Sepolia (421614)
Solution: Use Arbitrum Sepolia RPC URL

# Pool already exists
Error: Pool already exists
Solution: Pool is ready - proceed to add liquidity

# Zero price issue (FIXED in v1.1)
Error: execution reverted when querying pool
Cause: Script sent zero initial price instead of calculated value
Solution: Use updated script with corrected INITIAL_SQRT_PRICE_X96 value
```

## 📈 **Next Steps After Pool Initialization**

### **1. Add Liquidity**

Use the `ProvideLiquidity.s.sol` script to add initial liquidity:

```bash
# Add liquidity to the pool
forge script ProvideLiquidity.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

### **2. Test Trading**

Execute small test trades to verify the pool functions correctly:

```bash
# Test small swap
forge script QuickSwap.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

### **3. Monitor Performance**

- Track pool volume and fees
- Monitor MEV protection effectiveness
- Check for any trading anomalies

## 🌐 **Network Information**

### **Arbitrum Sepolia (Testnet)**
- **Chain ID**: 421614
- **RPC URL**: `https://sepolia-rollup.arbitrum.io/rpc`
- **Block Explorer**: `https://sepolia.arbiscan.io/`
- **Gas Costs**: Very low (fractions of a cent)

### **Why Arbitrum Sepolia?**
- **Low Gas Costs**: Perfect for testing and development
- **Fast Transactions**: Sub-second finality
- **MEV Protection**: Test DetoxHook effectiveness
- **Real Network**: Actual blockchain, not local simulation

## ⚠️ **Important Notes**

### **Security Considerations**
1. **Testnet Only**: This is for testing - not production use
2. **Private Key Safety**: Never commit private keys to version control
3. **Contract Verification**: Always verify deployed contracts on Arbiscan
4. **MEV Protection**: DetoxHook provides protection but doesn't eliminate all risks

### **Gas Optimization**
- **Pool Initialization**: ~300k gas (very low cost on Arbitrum)
- **Liquidity Addition**: Additional gas costs for LP operations
- **Trading**: Standard Uniswap V4 gas costs

### **Price Stability**
- **Initial Price**: Set to realistic EUR/USD rate
- **Price Discovery**: Market forces will determine actual trading price
- **Arbitrage**: MEV bots may attempt arbitrage (protected by DetoxHook)

## 📚 **Additional Resources**

- **MockEURC Deployment**: `packages/foundry/script/ERC20/MockEURC/`
- **Pool Liquidity**: `packages/foundry/script/Pool/ProvideLiquidity.s.sol`
- **Trading Scripts**: `packages/foundry/script/Transaction/`
- **Uniswap V4 Docs**: [https://docs.uniswap.org/](https://docs.uniswap.org/)
- **Arbitrum Documentation**: [https://docs.arbitrum.io/](https://docs.arbitrum.io/)

## 🎯 **Success Metrics**

After successful pool initialization, you should see:

- ✅ **Pool ID generated** and displayed
- ✅ **Initial price set** to 1 MockUSDC = 0.86 MockEURC
- ✅ **DetoxHook integrated** and active
- ✅ **Pool ready** for liquidity provision
- ✅ **Trading enabled** with MEV protection

---

## 🔄 **Script Version History**

### **Version 1.1 (Current) - FIXED**
- ✅ **Corrected SqrtPriceX96**: Fixed calculation from `79228162514264337593543950336` to `85070591730234615865843651857942052864`
- ✅ **Pool Verification**: Added automatic verification after pool creation
- ✅ **Better Error Handling**: Improved error messages and validation
- ✅ **Verification Commands**: Script now outputs commands to verify pool creation

### **Version 1.0 (Deprecated)**
- ❌ **Zero Price Bug**: Sent zero initial price causing pool creation to fail
- ❌ **No Verification**: No validation that pool was actually created
- ❌ **Misleading Success**: Reported success even when pool wasn't created

---

**🪙 The MockEURC/MockUSDC FX pool provides a realistic environment for testing EUR/USD trading with MEV protection in the DetoxHook ecosystem!**
