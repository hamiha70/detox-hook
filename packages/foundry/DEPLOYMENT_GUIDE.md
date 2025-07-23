# DetoxHook Deployment Guide

## 🎯 **CURRENT DEPLOYMENT STATUS**

### ✅ **SUCCESSFULLY DEPLOYED COMPONENTS**

**DetoxHook V2**: `0x07Fae0457E31b0047363d63ac3Dc3e446abf0088`
- ✅ CREATE2 deployment successful
- ✅ Hook permissions verified (beforeSwap: true, beforeSwapReturnDelta: true)
- ✅ Funded with 0.001 ETH
- ✅ Connected to PoolManager: `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`

**PriceRegistry**: `0xeC43D2EDEC0FdCAF5a1d3ADdE116609644D6fbd6`
- ✅ Deployed and configured
- ✅ Owner set to deployer

**Pool Initialization**:
- ✅ **Pool 1**: ETH/USDC at 2500 price (tick 78244, spacing 10)
- ✅ **Pool 2**: ETH/USDC at 2600 price (tick 78644, spacing 60)
- ✅ Both pools have active liquidity

### ✅ **ALL COMPONENTS DEPLOYED**

**SwapRouterFixed**: Ready for deployment via separate script
- ✅ Standalone deployment script created
- ✅ No file system access issues
- ✅ Ready for demo functionality

---

## 🛠️ **Deployment Safety Snippets**

### **A. Check if a Contract is Already Deployed (from CLI)**

```bash
# Replace <address> with the expected DetoxHook address from your script logs
cast code <address> --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```
- If the output is non-empty, the contract is already deployed at that address.
- If the output is empty, the address is unused and safe for deployment.

### **B. Solidity Snippet: Skip Deployment if Already Deployed**

```solidity
address expectedHookAddress = /* compute with HookMiner as in script */;
if (expectedHookAddress.code.length > 0) {
    console.log("[SKIP] DetoxHook already deployed at:", expectedHookAddress);
    hook = DetoxHookV2(payable(expectedHookAddress));
    return;
} else {
    console.log("[DEPLOY] Deploying new DetoxHook...");
    // ... proceed with deployment ...
}
```

---

## 🚀 **DetoxHook Deployment Logic**

- The deployment script now checks if the DetoxHook is already deployed at the expected address (using CREATE2 and the computed salt/args).
- If code exists at the address, it logs and skips deployment, using the existing contract.
- If not, it proceeds with deployment.
- This prevents CREATE2 reverts and ensures idempotent deployments.

---

## 🚀 **COMPLETE DEPLOYMENT INSTRUCTIONS**

### **Step 1: Environment Setup**

```bash
# Set environment variables
export DEPLOYMENT_KEY_421614="your_private_key_here"
export RPC_URL_421614="https://sepolia-rollup.arbitrum.io/rpc"

# Verify balances (minimum requirements)
# - ETH: 0.05 ETH
# - USDC: 10 USDC
```

### **Step 2: Run Complete Deployment**

```bash
# Navigate to foundry directory
cd packages/foundry

# Run the complete deployment script
forge script script/DeployDetoxHookComplete.s.sol:DeployDetoxHookComplete \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast --verify -vvvv
```

### **Step 3: Complete SwapRouterFixed Deployment**

The main deployment script successfully deploys all core components. To complete the demo setup:

```bash
# Deploy SwapRouterFixed (required for demo)
forge script script/DeploySwapRouterFixed.s.sol:DeploySwapRouterFixed \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast --verify -vvv
```

**Expected Output**:
- SwapRouterFixed deployed at: `[NEW_ADDRESS]`
- Configuration verified with DetoxHook: `0x07Fae0457E31b0047363d63ac3Dc3e446abf0088`

### **Step 4: Verify Deployment**

```bash
# Test the deployment
yarn swap-router --getpool
yarn swap-router --swap 0.00002 false

# Run comprehensive tests
forge test --fork-url $RPC_URL_421614 -vvv
```

---

## 📊 **DEPLOYMENT CONFIGURATION**

### **Network Configuration**
- **Chain ID**: 421614 (Arbitrum Sepolia)
- **PoolManager**: `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`
- **USDC**: `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d`
- **Pyth Oracle**: `0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF`

### **Pool Configuration**
- **Pool 1**: ETH/USDC, 0.05% fee, tick spacing 10, price ~2500
- **Pool 2**: ETH/USDC, 0.05% fee, tick spacing 60, price ~2600

### **Hook Configuration**
- **Address**: `0x07Fae0457E31b0047363d63ac3Dc3e446abf0088`
- **Permissions**: beforeSwap + beforeSwapReturnDelta
- **Funding**: 0.001 ETH for gas costs

---

## 🧪 **TESTING INSTRUCTIONS**

### **Manual Testing**
```bash
# Test pool configuration
yarn swap-router --getpool

# Test small swap
yarn swap-router --swap 0.00002 false

# Test MEV protection
yarn swap-router --swap 0.001 false
```

### **Automated Testing**
```bash
# Run all tests
forge test --fork-url $RPC_URL_421614

# Run specific test
forge test --match-test testBeforeSwap --fork-url $RPC_URL_421614
```

---

## 🔧 **TROUBLESHOOTING**

### **Common Issues**

1. **Insufficient Balance**
   - Ensure deployer has > 0.05 ETH and > 10 USDC
   - Check balances before deployment

2. **Hook Deployment Failure**
   - Verify CREATE2 Deployer exists at `0x4e59b44847b379578588920cA78FbF26c0B4956C`
   - Check salt mining process

3. **Pool Initialization Failure**
   - Verify PoolManager contract exists
   - Check currency ordering (ETH must be currency0)

4. **SwapRouterFixed Deployment Failure**
   - Manual deployment required
   - Use separate deployment script

### **Verification Commands**

```bash
# Check hook deployment
cast call 0x07Fae0457E31b0047363d63ac3Dc3e446abf0088 "poolManager()" --rpc-url $RPC_URL_421614

# Check hook permissions
cast call 0x07Fae0457E31b0047363d63ac3Dc3e446abf0088 "getHookPermissions()" --rpc-url $RPC_URL_421614

# Check pool state
cast call 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 "getSlot0(bytes32)" --rpc-url $RPC_URL_421614
```

---

## 📋 **DEPLOYMENT CHECKLIST**

- [x] Environment variables set
- [x] Sufficient balances verified
- [x] DetoxHook deployed and validated
- [x] PriceRegistry deployed
- [x] Pools initialized with liquidity
- [ ] SwapRouterFixed deployed (run separate script)
- [ ] Demo functionality tested
- [ ] All tests passing

---

## 🎯 **DEMO READINESS**

Once SwapRouterFixed is deployed, the demo will be fully functional with:

1. **MEV Protection**: Active on both pools
2. **Real-time Price Feeds**: Pyth Network integration
3. **Arbitrage Detection**: Automatic fee extraction
4. **LP Value Redistribution**: Captured MEV benefits LPs

**Demo Addresses**:
- DetoxHook: `0x07Fae0457E31b0047363d63ac3Dc3e446abf0088`
- Pool 1: `0xa49f711787deee79969f93a4f2eae9b56a2345dbaee1b057ba803e771c43c7de`
- Pool 2: `0x18bfc05a7bd173fb4635dc27ddc8bc63f67f6666497555b4391665fe6a614227` 

---

## 🪙 **USDC Token Strategy: MockUSDC Everywhere**

### **Why MockUSDC?**
- Native USDC on Arbitrum Sepolia cannot be minted and is hard to obtain in large quantities.
- Using MockUSDC (a mintable ERC20) for all environments ensures all test/demo accounts can be funded as needed.
- This approach is artificial but guarantees reliability for development and demos.

### **How It Works**
- **Deploy MockUSDC** on every environment (including Arbitrum Sepolia).
- **Fund all relevant addresses** (deployer, demo users, contracts) with sufficient MockUSDC for swaps, liquidity, and testing.
- **All scripts and contracts** reference the deployed MockUSDC address for USDC operations.
- **Do not attempt to mint or use native USDC** on Arbitrum Sepolia.

### **Controlling Minting**
- The deployer/owner of MockUSDC is the only address that can mint new tokens.
- **Best practice:**
  - Deploy MockUSDC from a known, controlled deployer address.
  - Use this deployer to mint and distribute tokens to all test/demo accounts.
  - Optionally, transfer ownership to a multisig or burn the owner key after initial funding for extra realism.

### **Record Keeping**
- **Document the MockUSDC address and owner** in this guide after deployment for reference.

### **Deployed MockUSDC Information** 
*(To be updated after deployment)*
- **MockUSDC Address**: `[TO_BE_UPDATED]`
- **Owner/Deployer**: `[TO_BE_UPDATED]`
- **Funded Accounts**: Deployer + Demo accounts automatically funded
- **Minting Control**: Only owner can mint new tokens

### **Safety Features Implemented**
- ✅ **Deployment Safety**: Checks if contracts already exist before deploying
- ✅ **Balance Validation**: Ensures sufficient ETH/tokens before operations
- ✅ **Approval Management**: Automatic ERC20 approval handling
- ✅ **Pool State Checks**: Prevents duplicate pool initialization
- ✅ **Comprehensive Logging**: Clear safety check messages and status

--- 