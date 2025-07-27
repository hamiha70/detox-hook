# 🚨 MANDATORY DEPLOYMENT VERIFICATION PROTOCOL

## **CRITICAL RULE: NEVER DECLARE SUCCESS WITHOUT ON-CHAIN CONFIRMATION**

This protocol must be followed for ALL deployments to prevent false success declarations.

## **PHASE 1: IMMEDIATE POST-DEPLOYMENT VERIFICATION**

### **Step 1: Check Broadcast Files (MANDATORY)**
```bash
# Check if transactions were actually broadcast
ls -la broadcast/DeployDetoxHookComplete.s.sol/*/run-latest.json

# Extract actual transaction details
jq '.transactions[] | {contractName, contractAddress, hash, transactionType}' broadcast/DeployDetoxHookComplete.s.sol/421614/run-latest.json
```

### **Step 2: On-Chain Code Verification (MANDATORY)**
```bash
# Test each contract individually
cast codesize [CONTRACT_ADDRESS] --rpc-url [RPC_URL]

# Must return > 0 for successful deployment
# If returns 0 = NO CONTRACT DEPLOYED
```

### **Step 3: Block Explorer Verification (MANDATORY)**
```bash
# Check via API
curl -s "https://arbitrum-sepolia.blockscout.com/api/v2/addresses/[ADDRESS]" | jq '.is_contract'

# Must return true for successful deployment
```

## **PHASE 2: FUNCTIONAL VERIFICATION**

### **Step 4: Contract Function Calls (MANDATORY)**
```bash
# Only after confirming code exists
cast call [CONTRACT] "functionName()" --rpc-url [RPC_URL]
```

### **Step 5: Hook-Specific Verification (MANDATORY)**
```bash
# Check hook flags
cast --to-dec [HOOK_ADDRESS] | awk '{print $1 % 1048576}'

# Must equal 136 for DetoxHook
```

## **FAILURE INDICATORS**

### **🚨 AUTOMATIC FAILURE SIGNALS**
- `cast codesize` returns `0`
- Block explorer shows `"is_contract": false`
- `cast call` fails with "execution reverted"
- Hook address flags ≠ 136

### **⚠️ WARNING SIGNALS**
- Script logs show success but verification fails
- Broadcast file missing or empty
- RPC timeouts or network errors

## **SUCCESS CRITERIA**

### **✅ ONLY DECLARE SUCCESS WHEN ALL TRUE:**
1. Broadcast file contains successful transactions
2. `cast codesize` returns > 0 for all contracts
3. Block explorer confirms `"is_contract": true`
4. Function calls return expected values
5. Hook flags match expected values (136)

## **COMMON FAILURE PATTERNS**

### **Pattern 1: Silent CREATE2 Failure**
- **Symptom**: Script logs success, but `cast codesize` returns 0
- **Cause**: CREATE2 deployment reverted but script didn't catch it
- **Fix**: Check CREATE2 deployer return data

### **Pattern 2: Constructor Validation Failure**
- **Symptom**: Deployment transaction succeeds but no code deployed
- **Cause**: Constructor `require()` or `revert()` statements
- **Fix**: Check constructor parameters and validation logic

### **Pattern 3: Gas Estimation Failure**
- **Symptom**: Transaction submitted but failed due to gas
- **Cause**: Insufficient gas limit or gas price too low
- **Fix**: Check transaction receipt for failure reason

## **DEBUGGING WORKFLOW**

### **When Deployment "Succeeds" But Verification Fails:**

1. **Check transaction receipts:**
   ```bash
   cast receipt [TX_HASH] --rpc-url [RPC_URL]
   ```

2. **Check for revert reasons:**
   ```bash
   cast run [TX_HASH] --rpc-url [RPC_URL]
   ```

3. **Simulate deployment locally:**
   ```bash
   forge script --fork-url [RPC_URL] [SCRIPT] -vvvv
   ```

4. **Check CREATE2 deployer state:**
   ```bash
   cast codesize 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url [RPC_URL]
   ```

## **MANDATORY COMMANDS FOR CURRENT SITUATION**

### **Immediate Verification Commands:**
```bash
# 1. Check what was actually deployed
jq '.transactions[] | {contractName, contractAddress, hash}' broadcast/DeployDetoxHookComplete.s.sol/421614/run-latest.json

# 2. Test each contract
cast codesize 0x6c00492dF8fcaE1309C7A60CcdeB2E4ECe587Aba --rpc-url https://sepolia-rollup.arbitrum.io/rpc  # MockUSDC
cast codesize 0x927a871865B739ae9844EA83fC4163a487DB17Fe --rpc-url https://sepolia-rollup.arbitrum.io/rpc  # PriceRegistry  
cast codesize 0xAaFd63797e2Eaedc2b59386B21ed30e2501A78F1 --rpc-url https://sepolia-rollup.arbitrum.io/rpc  # SwapRouterFixed
cast codesize 0xB7d53527Fd072ea45e15FC09101Eb379D3778088 --rpc-url https://sepolia-rollup.arbitrum.io/rpc  # DetoxHook

# 3. Check transaction receipts for failures
# Extract hashes from broadcast file and check each one
```

## **COMMITMENT**

**I WILL NOT DECLARE DEPLOYMENT SUCCESS WITHOUT:**
1. ✅ Confirming `cast codesize > 0` for all contracts
2. ✅ Confirming block explorer shows contracts exist
3. ✅ Confirming function calls work as expected
4. ✅ Confirming hook flags are correct

**NO MORE FALSE POSITIVES.** 

---

## **🚨 CASE STUDY: SILENT CREATE2 DEPLOYMENT FAILURE**
*Date: July 26, 2025*

### **The Incident**
- **Symptom**: Script reported "DEPLOYMENT SUCCESSFUL" with DetoxHook address `0xb86bffB4e7d1f330980cc11Be4a4Dd7f6EDE8088`
- **Reality**: `cast codesize` returned `0` - no contract deployed
- **False Positive**: Script logs were completely misleading

### **Debugging Methodology Applied**

#### **Step 1: Verify Other Contracts**
```bash
cast codesize 0x08A7eB7f3b7AdF1f809C14c7F85bFBd6Faf78699 --rpc-url https://sepolia-rollup.arbitrum.io/rpc  # USDC: 2026 ✅
cast codesize 0x982fe0435264005D49ddD90f3a4350DB821Bba0d --rpc-url https://sepolia-rollup.arbitrum.io/rpc  # Router: 1748 ✅  
cast codesize 0xb86bffB4e7d1f330980cc11Be4a4Dd7f6EDE8088 --rpc-url https://sepolia-rollup.arbitrum.io/rpc  # Hook: 0 ❌
```
**Finding**: Only DetoxHook failed - isolated the problem.

#### **Step 2: Check Broadcast File**
```bash
jq '.transactions[] | select(.transactionType == "CREATE") | {contractName, contractAddress}' \
   broadcast/DeployDetoxHookComplete.s.sol/421614/run-latest.json
```
**Finding**: No DetoxHook CREATE transaction - script never attempted deployment.

#### **Step 3: Analyze Script Logic**
Found the culprit in `DeployDetoxHookComplete.s.sol`:
```solidity
if (expectedHookAddress.code.length > 0) {
    console.log("[SKIP] DetoxHook already deployed at:", expectedHookAddress);
    hook = DetoxHookV2(payable(expectedHookAddress));
    return;  // ← EXITS WITHOUT DEPLOYING
}
```

#### **Step 4: Verify Constructor Parameters**
- ✅ PoolManager: 24009 bytes (valid)
- ✅ Owner: Non-zero address  
- ✅ Pyth Oracle: 680 bytes (valid)
- ✅ PriceRegistry: 4991 bytes (valid)
- ✅ CREATE2 Deployer: 69 bytes (valid)

**Finding**: All parameters valid - confirmed script logic issue.

### **Root Cause** ✅ **IDENTIFIED AND FIXED**
**External function wrapper pattern prevented CREATE2 transactions from being broadcast:**

```solidity
// ❌ BROKEN: External wrapper prevented broadcast
hook = this._deployDetoxHookWithSaltExternalWithRegistry(salt, address(priceRegistry));

// ✅ FIXED: Direct internal call properly broadcasts  
hook = _deployDetoxHookWithSaltWithRegistry(salt, address(priceRegistry));
```

### **Solution Applied**
1. **Removed external wrapper**: Changed to direct internal function call
2. **Verified broadcast files**: CREATE2 transaction now appears correctly
3. **Confirmed on-chain**: All contracts deployed with correct code sizes
4. **Updated verification**: Enhanced protocol prevents future issues

### **Prevention Measures**
1. **Always check broadcast files** for actual CREATE/CREATE2 transactions
2. **Always verify on-chain code size** before declaring success  
3. **Never trust script logs alone** - they show simulation, not reality
4. **Avoid external wrappers** for deployment functions in Foundry scripts
5. **Implement mandatory verification** in deployment scripts

### **Lesson Learned**
**Foundry external function calls in scripts can prevent proper transaction broadcasting while still showing "success" in simulation.** Direct internal calls are required for reliable deployment. 