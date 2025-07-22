# DetoxHook Production Deployment Guide

*Complete deployment guide for DetoxHookV2 and related components*

## 🎯 **Overview**

This guide provides comprehensive instructions for deploying DetoxHook components to production. The deployment has been thoroughly tested and validated on Arbitrum Sepolia.

**Current Production Components**:
- **DetoxHookV2.sol** - Main MEV protection hook
- **PriceRegistry.sol** - Oracle registry for token/price ID mappings  
- **SwapRouterFixed.sol** - Router with proper error handling
- **Real USDC Integration** - Uses actual USDC token on Arbitrum Sepolia
- **Complete Pool Setup** - ETH/USDC pools with liquidity provision

## ✅ **Prerequisites**

### **Required Software**
- Foundry (latest version)
- Node.js 18+
- Git

### **Required Accounts**
- Ethereum wallet with private key
- Sufficient ETH on Arbitrum Sepolia:
  - **Basic deployment**: 0.001 ETH (DetoxHookV2 + PriceRegistry only)
  - **Complete deployment**: 0.003 ETH (includes pools, liquidity, funding)
  - **Recommended**: 0.01 ETH (with buffer for testing and multiple deployments)

### **Environment Setup**
Create a `.env` file in `packages/foundry/`:

```bash
# Required for deployment
DEPLOYMENT_KEY=0x... # Your private key (64 characters)

# Optional (uses defaults if not set)
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
ARBISCAN_API_KEY=your_api_key_here # For contract verification
```

## 🌐 **Supported Networks**

### **Arbitrum Sepolia (Primary Target)**
- **Chain ID**: 421614
- **RPC URL**: https://sepolia-rollup.arbitrum.io/rpc
- **Block Explorer**: https://arbitrum-sepolia.blockscout.com/
- **Pool Manager**: `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`
- **Pyth Oracle**: `0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF`
- **USDC**: `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d`

### **Price Feed IDs**
- **ETH/USD**: `0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace`
- **USDC/USD**: `0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a`

## 🚀 **Deployment Options**

### **Option 1: Production DetoxHookV2 (Recommended)**

**Quick Deploy**:
```bash
# Test configuration
make test-detox-hook-v2-deployment

# Deploy to production
make deploy-detox-hook-v2-arbitrum-sepolia
```

**Manual Deploy**:
```bash
forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast \
    --verify \
    --verifier blockscout \
    --verifier-url https://arbitrum-sepolia.blockscout.com/api \
    -vvvv
```

**Expected Results**:
- **Gas Cost**: ~3.88M gas (~0.000776 ETH at 0.2 gwei)
- **DetoxHookV2**: `0x07Fae0457E31b0047363d63ac3Dc3e446abf0088`
- **PriceRegistry**: `0xeC43D2EDEC0FdCAF5a1d3ADdE116609644D6fbd6`

### **Option 2: SwapRouter Deployment**

**Quick Deploy**:
```bash
# Test configuration
make test-swap-router-deployment

# Deploy SwapRouter
DEPLOYMENT_KEY=$DEPLOYMENT_KEY make deploy-swap-router-arbitrum-sepolia
```

**Manual Deploy**:
```bash
forge script script/DeploySwapRouterFixed.s.sol:DeploySwapRouterFixed \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast \
    --verify \
    --verifier blockscout \
    --verifier-url https://arbitrum-sepolia.blockscout.com/api \
    -vvv
```

### **Option 3: Complete All-in-One Deployment**

**Deploy Everything in Single Transaction**:
```bash
# Complete deployment (hook, registry, pools, liquidity, funding)
forge script script/DeployDetoxHookComplete.s.sol:DeployDetoxHookComplete \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast \
    --verify \
    --verifier blockscout \
    --verifier-url https://arbitrum-sepolia.blockscout.com/api \
    -vvvv
```

**What This Includes**:
- ✅ **DetoxHookV2** deployment with address mining
- ✅ **PriceRegistry** deployment and token registration
- ✅ **SwapRouterFixed** deployment  
- ✅ **Pool initialization** (2 ETH/USDC pools with different prices)
- ✅ **Liquidity provision** (proper ETH/USDC ratios)
- ✅ **Hook funding** (0.001 ETH)
- ✅ **Token approvals** for all routers
- ✅ **Price ID registration** (ETH/USD, USDC/USD)
- ✅ **Comprehensive validation** throughout

**Expected Gas Cost**: ~8-12M gas (~0.0016-0.0024 ETH at 0.2 gwei)

### **Option 4: Modular Step-by-Step Deployment**

**For Maximum Control**:
```bash
# Step 1: Deploy core components
make deploy-detox-hook-v2-arbitrum-sepolia
export HOOK_ADDRESS=0x07Fae0457E31b0047363d63ac3Dc3e446abf0088
export PRICE_REGISTRY=0xeC43D2EDEC0FdCAF5a1d3ADdE116609644D6fbd6

# Step 2: Deploy SwapRouter
make deploy-swap-router-arbitrum-sepolia

# Step 3: Initialize pools and add liquidity
forge script script/InitializePools.s.sol:InitializePools \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast -vvv

# Step 4: Fund hook for operations
forge script script/FundDetoxHook.s.sol:FundDetoxHook \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast -vvv
```

## 🔧 **Deployment Validation**

### **Pre-Deployment Checks**

```bash
# Test deployment configuration
forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
    --sig "testDeploymentConfig()" \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc -vvv

# Dry run (no broadcast)
forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc -vvv
```

### **Post-Deployment Verification**

```bash
# Check contract on block explorer
open https://arbitrum-sepolia.blockscout.com/address/0x07Fae0457E31b0047363d63ac3Dc3e446abf0088

# Verify hook permissions
cast call 0x07Fae0457E31b0047363d63ac3Dc3e446abf0088 \
    "getHookPermissions()" \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Verify price registry connection
cast call 0x07Fae0457E31b0047363d63ac3Dc3e446abf0088 \
    "priceRegistry()" \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

## 🧪 **Testing Deployed Contracts**

### **Using SwapRouter Frontend**
```bash
# Test with real deployment
yarn swap-router --getpool

# Execute test swap
yarn swap-router --swap 0.00002 false

# Test with specific pool
make swap-router ARGS="--getpool"
make swap-router ARGS="--swap 0.00002 false"
```

### **Manual Contract Testing**
```bash
# Check hook is responding
cast call $HOOK_ADDRESS "poolManager()" \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Test price registry
cast call $PRICE_REGISTRY_ADDRESS "getRegisteredTokenCount()" \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

## 📊 **Deployment Patterns & Architecture**

### **Hook Address Requirements**
DetoxHook requires specific address flags for proper operation:
- **Required Flags**: `136` (BEFORE_SWAP_FLAG | BEFORE_SWAP_RETURNS_DELTA_FLAG)
- **Deployment Method**: CREATE2 with salt mining via HookMiner
- **Address Validation**: Automatic during deployment

### **Constructor Arguments**
- **DetoxHookV2**: `(IPoolManager poolManager, address priceRegistry)`
- **PriceRegistry**: `(address owner)`
- **SwapRouterFixed**: `(address poolSwapTest, PoolKey memory poolKey)`

### **Gas Estimates**
| Component | Gas Cost | ETH Cost (0.2 gwei) |
|-----------|----------|---------------------|
| DetoxHookV2 + PriceRegistry | ~3.88M | ~0.000776 ETH |
| SwapRouterFixed | ~1.2M | ~0.000240 ETH |
| Pool Initialization | ~500K | ~0.000100 ETH |
| Liquidity Provision | ~400K | ~0.000080 ETH |
| Hook Funding | ~21K | ~0.000004 ETH |
| **Complete All-in-One** | **~8-12M** | **~0.0016-0.0024 ETH** |

## ❌ **Troubleshooting**

### **Common Issues**

1. **"DEPLOYMENT_KEY not set"**
   ```bash
   echo $DEPLOYMENT_KEY  # Should show your private key
   ```

2. **"insufficient funds for gas"**
   ```bash
   cast balance $DEPLOYER_ADDRESS --rpc-url https://sepolia-rollup.arbitrum.io/rpc
   ```

3. **"Hook address mismatch"**
   ```bash
   forge clean && forge build  # Clean and rebuild
   ```

4. **"PoolManager not found"**
   - Check you're on Arbitrum Sepolia (chain ID 421614)
   - Verify RPC connectivity

### **Recovery Procedures**

1. **Failed Deployment**:
   ```bash
   # Resume deployment
   forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
       --rpc-url https://sepolia-rollup.arbitrum.io/rpc --resume
   ```

2. **Check Deployment Status**:
   ```bash
   # Check broadcast folder
   ls -la broadcast/DeployDetoxHookV2.s.sol/421614/
   
   # Review transaction hashes
   cat broadcast/DeployDetoxHookV2.s.sol/421614/run-latest.json
   ```

## 📋 **Deployment Checklist**

### **Pre-Deployment**
- [ ] Environment variables configured
- [ ] Sufficient ETH balance (> 0.001 ETH)
- [ ] RPC connectivity tested
- [ ] Dry run completed successfully
- [ ] Contract compilation successful

### **Deployment**
- [ ] Production deployment executed
- [ ] Transaction confirmed on block explorer
- [ ] Contract verification completed
- [ ] Hook permissions validated
- [ ] Price registry connection verified

### **Post-Deployment**
- [ ] Contract addresses documented
- [ ] Basic functionality tested
- [ ] Pool initialization (if needed)
- [ ] Integration testing completed
- [ ] SwapRouter frontend testing

## 🔗 **Useful Resources**

- **Arbitrum Sepolia Faucet**: https://faucet.quicknode.com/arbitrum/sepolia
- **Block Explorer**: https://arbitrum-sepolia.blockscout.com/
- **Uniswap V4 Docs**: https://docs.uniswap.org/contracts/v4/overview
- **Pyth Network Docs**: https://docs.pyth.network/
- **Foundry Book**: https://book.getfoundry.sh/

## 📞 **Support**

For deployment issues:
1. Check troubleshooting section above
2. Review deployment logs in `broadcast/` folder
3. Verify all prerequisites are met
4. Test with dry run before production deployment

---

**🎉 Your DetoxHook deployment is ready to protect against MEV exploitation!** 