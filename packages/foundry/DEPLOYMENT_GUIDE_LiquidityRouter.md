# LiquidityRouter Manual Deployment Guide

## 🚀 **Manual Deployment Instructions**

Follow these steps to manually deploy the LiquidityRouter contract on Arbitrum Sepolia.

### **📋 Prerequisites**

1. **Environment Variables Set**
2. **Foundry Installed**
3. **Arbitrum Sepolia RPC URL**
4. **Sufficient ETH Balance** (~0.001 ETH for gas)

---

## **🔧 Step 1: Set Environment Variables**

Open your terminal and run:

```bash
# Navigate to project root
cd ~/Work/Entrepreneurship/SamexLabs/detox-hook

# Load environment variables
source load_env.sh
```

**Or manually set them:**
```bash
export DEPLOYMENT_WALLET="0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38"
export DEPLOYMENT_PRIVATE_KEY="your_private_key_here"
export ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
```

---

## **🔧 Step 2: Verify Environment**

Check that variables are set:
```bash
echo "Deployment Wallet: $DEPLOYMENT_WALLET"
echo "RPC URL: $ARBITRUM_SEPOLIA_RPC_URL"
echo "Private Key: ${DEPLOYMENT_PRIVATE_KEY:0:10}..."
```

---

## **🔧 Step 3: Navigate to Foundry Directory**

```bash
cd packages/foundry
```

---

## **🔧 Step 4: Build the Contracts**

```bash
forge build
```

**Expected Output:**
```
[⠢] Compiling...
[⠆] Compiling 5 files with Solc 0.8.20
[⠰] Solc 0.8.20 finished in 1.23s
Compiler run successful!
```

---

## **🔧 Step 5: Deploy LiquidityRouter (Method 1 - Using Script)**

```bash
forge script script/DeployLiquidityRouter.s.sol:DeployLiquidityRouter \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

---

## **🔧 Step 5 Alternative: Deploy LiquidityRouter (Method 2 - Direct Command)**

If the script fails, deploy directly:

```bash
forge create src/LiquidityRouter.sol:LiquidityRouter \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $DEPLOYMENT_PRIVATE_KEY \
  --constructor-args \
    "0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7" \
    "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317" \
  --verify
```

**Constructor Arguments:**
- `0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7` = PoolModifyLiquidityTest address
- `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317` = PoolManager address

---

## **🔧 Step 6: Record Deployment Address**

After successful deployment, you'll see output like:
```
Deployer: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
Deployed to: 0x1234567890abcdef1234567890abcdef12345678
Transaction hash: 0xabcdef...
```

**Save the "Deployed to" address** - this is your LiquidityRouter contract address!

---

## **🔧 Step 7: Verify Deployment**

Check the contract on Blockscout:
```
https://arbitrum-sepolia.blockscout.com/address/YOUR_CONTRACT_ADDRESS
```

Or verify programmatically:
```bash
cast call YOUR_CONTRACT_ADDRESS \
  "getPoolManager()" \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

**Expected Result:** `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`

---

## **🔧 Step 8: Update Python Script**

Update the Python script with your deployed address:

```python
# In provide_liquidity_router.py, change line 19:
LIQUIDITY_ROUTER_ADDRESS = "YOUR_DEPLOYED_CONTRACT_ADDRESS"
```

---

## **🚨 Troubleshooting**

### **Problem: "insufficient funds for gas"**
**Solution:** Fund your deployment wallet with ETH:
```bash
# Check balance
cast balance $DEPLOYMENT_WALLET --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Get testnet ETH from faucet:
# https://faucet.quicknode.com/arbitrum/sepolia
```

### **Problem: "nonce too low/high"**
**Solution:** Check current nonce:
```bash
cast nonce $DEPLOYMENT_WALLET --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

### **Problem: "contract creation failed"**
**Solution:** Check if contracts exist:
```bash
# Check PoolManager
cast code 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Check PoolModifyLiquidityTest
cast code 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7 --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

### **Problem: "RPC connection failed"**
**Solution:** Try alternative RPC URLs:
```bash
# Alternative RPC URLs for Arbitrum Sepolia:
export ARBITRUM_SEPOLIA_RPC_URL="https://arbitrum-sepolia.blockpi.network/v1/rpc/public"
# or
export ARBITRUM_SEPOLIA_RPC_URL="https://arbitrum-sepolia.infura.io/v3/YOUR_KEY"
```

---

## **📋 Expected Deployment Cost**

- **Gas Used:** ~800,000 gas
- **Gas Price:** ~0.1 gwei (typical Arbitrum Sepolia)
- **Total Cost:** ~0.0001 ETH

---

## **✅ Success Indicators**

You'll know deployment succeeded when you see:
1. ✅ Transaction hash returned
2. ✅ Contract address displayed
3. ✅ "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL" message
4. ✅ Contract visible on Blockscout
5. ✅ Contract responds to `getPoolManager()` call

---

## **🎯 Next Steps**

After successful deployment:
1. **Update Python script** with the new contract address
2. **Test liquidity provision** with small amounts first
3. **Verify contract** on Blockscout for public transparency
4. **Save deployment info** for future reference

---

## **📞 Need Help?**

If deployment fails, check:
1. Environment variables are set correctly
2. Wallet has sufficient ETH balance
3. RPC URL is working
4. Constructor arguments are correct
5. No network congestion issues 