# Contract Verification Guide

This guide explains how to verify DetoxHook contracts on various blockchain explorers using Blockscout APIs.

## 🎯 **Quick Start**

### **Verify All Contracts (Arbitrum Sepolia)**
```bash
make verify-contracts-arbitrum-sepolia
```

### **Verify Individual Contracts**
```bash
make verify-detoxhook-arbitrum-sepolia
make verify-priceregistry-arbitrum-sepolia  
make verify-swaprouter-arbitrum-sepolia
```

## 🔧 **Setup Requirements**

### **1. Environment Configuration**
Copy `env.example` to `.env` and update:

```bash
# Contract addresses (update with your deployments)
DETOXHOOK_ADDRESS_421614=0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088
PRICEREGISTRY_ADDRESS_421614=0x1b72E21325175EF6a40d3883dF8789E43534e1e6
SWAPROUTER_ADDRESS_421614=0x5F731e22FE0bE0235C8f47EeecA75b513d8F74c9

# Verification URLs
VERIFIER_URL_421614=https://arbitrum-sepolia.blockscout.com/api
VERIFIER_URL_11155111=https://eth-sepolia.blockscout.com/api
VERIFIER_URL_1301=https://unichain-sepolia.blockscout.com/api
```

### **2. Supported Networks**

| Network | Chain ID | Blockscout URL | Status |
|---------|----------|----------------|--------|
| Arbitrum Sepolia | 421614 | https://arbitrum-sepolia.blockscout.com | ✅ Implemented |
| Ethereum Sepolia | 11155111 | https://eth-sepolia.blockscout.com | 🔄 Template Ready |
| Unichain Sepolia | 1301 | https://unichain-sepolia.blockscout.com | 🔄 Template Ready |

## 📋 **Manual Verification Commands**

### **DetoxHook Contract**
```bash
forge verify-contract 0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088 \
    src/DetoxHookV2.sol:DetoxHookV2 \
    --chain-id 421614 \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address)" \
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 \
        0xFDc61d52721c5eBA3e2fc39190fd9a603256E5a2 \
        0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF \
        0x1b72E21325175EF6a40d3883dF8789E43534e1e6) \
    --verifier blockscout \
    --verifier-url https://arbitrum-sepolia.blockscout.com/api
```

### **PriceRegistry Contract**
```bash
forge verify-contract 0x1b72E21325175EF6a40d3883dF8789E43534e1e6 \
    src/PriceRegistry.sol:PriceRegistry \
    --chain-id 421614 \
    --constructor-args $(cast abi-encode "constructor(address)" \
        0xFDc61d52721c5eBA3e2fc39190fd9a603256E5a2) \
    --verifier blockscout \
    --verifier-url https://arbitrum-sepolia.blockscout.com/api
```

### **SwapRouterFixed Contract**
```bash
forge verify-contract 0x5F731e22FE0bE0235C8f47EeecA75b513d8F74c9 \
    src/SwapRouterFixed.sol:SwapRouterFixed \
    --chain-id 421614 \
    --constructor-args $(cast abi-encode "constructor(address,(address,address,uint24,int24,address))" \
        0xf3A39C86dbd13C45365E57FB90fe413371F65AF8 \
        "(0x0000000000000000000000000000000000000000,0x9D5A68fDFEcc14683324640D5e835936422a47b1,500,10,0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088)") \
    --verifier blockscout \
    --verifier-url https://arbitrum-sepolia.blockscout.com/api
```

## 🚨 **Troubleshooting**

### **Common Issues**

1. **"The address is not a smart contract"**
   - **Cause**: Blockscout hasn't indexed the contract yet
   - **Solution**: Wait 5-10 minutes and retry

2. **"Failed to get standard json input"**
   - **Cause**: Contract uses external libraries (like Solmate)
   - **Solution**: Use full import path or skip verification

3. **Constructor args encoding errors**
   - **Cause**: Incorrect parameter types or formatting
   - **Solution**: Check constructor signature and use proper tuple syntax

### **Verification Status Check**
```bash
# Check if contract has code
cast codesize 0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088 --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Check Blockscout API
curl -s "https://arbitrum-sepolia.blockscout.com/api/v2/addresses/0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088" | jq '.is_verified'
```

## 🔗 **Verified Contract Links**

### **Arbitrum Sepolia**
- **DetoxHook**: https://sepolia.arbiscan.io/address/0x25b9b40a53c9fab2d7b2190eb406a22e2d738088
- **PriceRegistry**: https://sepolia.arbiscan.io/address/0x1b72e21325175ef6a40d3883df8789e43534e1e6
- **SwapRouterFixed**: https://sepolia.arbiscan.io/address/0x5f731e22fe0be0235c8f47eeeca75b513d8f74c9

## 🚀 **Adding New Networks**

To add verification for a new network:

1. **Add to env.example**:
```bash
VERIFIER_URL_[CHAIN_ID]=https://[network].blockscout.com/api
DETOXHOOK_ADDRESS_[CHAIN_ID]=
```

2. **Add Makefile target**:
```makefile
verify-contracts-[network]:
	@echo "🔍 Verifying all contracts on [Network]..."
	# Add verification commands
```

3. **Update generic verification**:
```makefile
verify-contracts:
	@if [ "$(CHAIN_ID)" = "[CHAIN_ID]" ]; then \
		make verify-contracts-[network]; \
```

## 📊 **Verification Results**

| Contract | Arbitrum Sepolia | Ethereum Sepolia | Unichain Sepolia |
|----------|------------------|------------------|------------------|
| DetoxHook | ✅ Verified | ⏳ Pending | ⏳ Pending |
| PriceRegistry | ✅ Verified | ⏳ Pending | ⏳ Pending |
| SwapRouterFixed | ✅ Verified | ⏳ Pending | ⏳ Pending |

---

**🔍 Always verify contracts after deployment to ensure transparency and enable block explorer interaction!** 