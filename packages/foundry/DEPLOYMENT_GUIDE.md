# DetoxHook Deployment Guide & Multi-Network Testing

## 🎯 **CURRENT DEPLOYMENT STATUS**

### ✅ **LIVE PRODUCTION DEPLOYMENT - ARBITRUM SEPOLIA**

**🚀 DetoxHook V2**: `0x35fb76a3AF902Ac31470654e2BeE942De3164088`
- ✅ CREATE2 deployment successful with proper constructor arguments
- ✅ Hook permissions verified (beforeSwap: true, beforeSwapReturnDelta: true)
- ✅ Funded with 0.001 ETH
- ✅ Connected to PoolManager: `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`
- ✅ Block Explorer: https://arbitrum-sepolia.blockscout.com/address/0x35fb76a3AF902Ac31470654e2BeE942De3164088

**PriceRegistry**: Deployed and configured
- ✅ Deployed with correct owner parameter
- ✅ Connected to DetoxHook V2

**MockUSDC Strategy**: Fully operational
- ✅ Deployed with proper ownership (deployer as owner)
- ✅ Minting permissions working correctly
- ✅ Demo accounts funded automatically
- ✅ Consistent behavior across all environments

**Pool Initialization**: Both pools operational
- ✅ **Pool 1**: ETH/MockUSDC at 2500 price (tick 78244, spacing 10)
- ✅ **Pool 2**: ETH/MockUSDC at 2600 price (tick 78644, spacing 60)
- ✅ Both pools have active liquidity (1 USDC + corresponding ETH each)
- ✅ Token approvals and allowances working correctly

## 🔗 **MULTI-NETWORK FORK TESTING ARCHITECTURE**

### ✅ **NEW TESTING INFRASTRUCTURE**

**🏗️ Architecture Components**:
- **DetoxHookForkTestBase.t.sol** - Reusable abstract base class for all network tests
- **PublicRPCURL.sol** - RPC failover system with environment variable support
- **Enhanced ChainAddresses.sol** - Dynamic address resolution for all supported networks
- **Network-specific tests** - Arbitrum Sepolia ✅, Unichain Sepolia ✅, ready for expansion

**🌐 Supported Networks**:
- **Arbitrum Sepolia (421614)** - Production deployment + fork testing ✅
- **Unichain Sepolia (1301)** - Fork testing ready ✅
- **Ethereum Sepolia (11155111)** - Architecture ready 🔄
- **Base Sepolia (84532)** - Architecture ready 🔄

### ✅ **RPC CONFIGURATION SYSTEM**

**Environment Variable Priority**:
1. **Primary**: `RPC_URL_<chainid>` (e.g., `RPC_URL_421614`)
2. **Backup**: `RPC_URL_<chainid>_BACKUP` (e.g., `RPC_URL_421614_BACKUP`)
3. **Fallback**: Hardcoded public RPCs in `PublicRPCURL.sol`

**Example Configuration** (add to your `.env`):
```bash
# ============================================================================
# ⚠️  FORK TESTING RPC CONFIGURATION
# ============================================================================
# WARNING: Public RPC URLs may be rate-limited and cause fork test failures
# Consider using private RPC providers (Alchemy, Infura, etc.) for reliable testing

# Arbitrum Sepolia (chainid 421614)
RPC_URL_421614=https://sepolia-rollup.arbitrum.io/rpc
RPC_URL_421614_BACKUP=https://arbitrum-sepolia.public.blastapi.io

# Unichain Sepolia (chainid 1301)
RPC_URL_1301=https://sepolia.unichain.org
RPC_URL_1301_BACKUP=https://rpc-sepolia.unichain.org

# Ethereum Sepolia (chainid 11155111)
RPC_URL_11155111=https://ethereum-sepolia-rpc.publicnode.com
RPC_URL_11155111_BACKUP=https://rpc.sepolia.org

# Base Sepolia (chainid 84532)
RPC_URL_84532=https://sepolia.base.org
RPC_URL_84532_BACKUP=https://base-sepolia.public.blastapi.io
```

### ✅ **FORK TESTING CAPABILITIES**

**🧪 Test Features**:
- **Infrastructure Verification** - Confirms PoolManager, SwapRouter, Pyth Oracle existence
- **Dynamic Hook Deployment** - CREATE2 deployment with HookMiner salt generation
- **Real Oracle Integration** - Tests Pyth Network oracle connectivity (with graceful failure)
- **Cross-Network Compatibility** - Verifies hook behavior consistency across networks
- **Pool Operations** - Full pool initialization, liquidity, and swap testing

**🔄 Parallel Execution Ready**:
- Fork tests can run simultaneously on different networks
- Each test creates isolated fork environment
- No interference between network-specific tests

### ✅ **RUNNING MULTI-NETWORK TESTS**

**Individual Network Tests**:
```bash
# Test Arbitrum Sepolia fork
forge test --match-contract DetoxHookArbitrumSepoliaFork -vv

# Test Unichain Sepolia fork  
forge test --match-contract DetoxHookUnichainSepoliaFork -vv

# Test all fork tests
forge test --match-path "test/*Fork.t.sol" -vv
```

**Parallel Execution** (when ready):
```bash
# Run multiple networks simultaneously
forge test --match-contract DetoxHookArbitrumSepoliaFork & \
forge test --match-contract DetoxHookUnichainSepoliaFork & \
wait
```

### ✅ **ALL DEPLOYMENT ISSUES RESOLVED**

**Major Fixes Applied**:
1. **CREATE2 Constructor Fix** - All 4 parameters now correctly passed
2. **MockUSDC Minting Fix** - Library context issues resolved
3. **Fork Test Fix** - Same constructor fixes applied to test suite
4. **Script Test Environment** - Added vm.skip() for Anvil compatibility
5. **Token Allowance Fix** - Approval before validation prevents reverts
6. **StateLibrary.getSlot0()** - Corrected usage across all test files
7. **Type Conversion Errors** - Fixed int64→uint64→uint256 casting
8. **Compilation Warnings** - Easy warnings cleaned up for production quality

### ✅ **DEPLOYMENT PIPELINE STATUS**

**Complete End-to-End Flow Working**:
- ✅ Balance checks and MockUSDC deployment
- ✅ Contract initialization and safety validation
- ✅ PriceRegistry deployment before salt mining
- ✅ HookMiner salt generation with correct parameters
- ✅ CREATE2 deployment with address verification
- ✅ Pool initialization with proper configurations
- ✅ Liquidity addition with token approvals
- ✅ Block explorer verification and documentation
- ✅ Multi-network fork testing architecture

---

## 🚀 **PRODUCTION DEPLOYMENT COMMAND**

### **Current Working Deployment**

```bash
forge script script/DeployDetoxHookComplete.s.sol:DeployDetoxHookComplete \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --broadcast --verify -vvvv
```

**This command successfully deploys**:
- MockUSDC with proper ownership
- PriceRegistry with deployer as owner  
- DetoxHook V2 with CREATE2 and correct constructor
- Two pools with different configurations
- Liquidity in both pools with proper token approvals

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

## 🚀 **EXPANDING TO NEW NETWORKS**

### **Adding a New Network (Step-by-Step)**

**1. Update ChainAddresses.sol**
```solidity
// Add chain ID constant
uint256 public constant NEW_NETWORK_SEPOLIA = 12345;

// Add contract addresses for the new network
function getPoolManager(uint256 chainId) internal pure returns (address) {
    // ... existing networks ...
    if (chainId == NEW_NETWORK_SEPOLIA) return 0xNewPoolManagerAddress;
    revert UnsupportedChain(chainId);
}

// Repeat for getPoolSwapTest, getPoolModifyLiquidityTest, getPythOracle, getUSDC
```

**2. Update PublicRPCURL.sol**
```solidity
// Add to constants
uint256 public constant NEW_NETWORK_SEPOLIA = 12345;

// Add to RPC functions
function getPrimaryRPC(uint256 chainId) internal pure returns (string memory) {
    // ... existing networks ...
    if (chainId == NEW_NETWORK_SEPOLIA) return "https://rpc.newnetwork.org";
    revert UnsupportedChain(chainId);
}

// Add to getBackupRPC, getChainName, etc.
```

**3. Update env.example**
```bash
# New Network Sepolia (chainid 12345)
RPC_URL_12345=https://rpc.newnetwork.org
RPC_URL_12345_BACKUP=https://backup-rpc.newnetwork.org
```

**4. Create Network-Specific Fork Test**
```solidity
// test/DetoxHookNewNetworkSepoliaFork.t.sol
contract DetoxHookNewNetworkSepoliaFork is DetoxHookForkTestBase(12345) {
    // Inherits all functionality from base class
    // Add network-specific tests if needed
}
```

### **Network Requirements Checklist**

Before adding a new network, verify:
- ✅ **Uniswap V4 Deployed**: PoolManager, PoolSwapTest, PoolModifyLiquidityTest
- ✅ **Pyth Oracle Available**: Pyth Network oracle contract deployed
- ✅ **Public RPC Access**: At least one reliable public RPC endpoint
- ✅ **USDC Available**: Native USDC or equivalent stablecoin
- ✅ **Block Explorer**: For contract verification and monitoring

### **Multi-Network Testing Troubleshooting**

**1. RPC Connection Issues**
```bash
# Test RPC connectivity
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  https://your-rpc-url-here

# Expected response: {"jsonrpc":"2.0","id":1,"result":"0x66eee"} (for chain 421614)
```

**2. Fork Test Failures**
```bash
# Run with verbose logging to debug
forge test --match-contract DetoxHookNewNetworkFork -vvv

# Common issues:
# - Contract not deployed on network
# - RPC rate limiting
# - Incorrect addresses in ChainAddresses.sol
```

**3. Dynamic Address Resolution Issues**
```bash
# Verify addresses are correct
forge script script/ChainAddresses.sol --sig "getPoolManager(uint256)" 421614

# Check if contracts exist at those addresses
cast code 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 --rpc-url $RPC_URL_421614
```

**4. Pyth Oracle Connectivity**
```bash
# Test Pyth oracle directly
cast call 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF \
  "getPriceUnsafe(bytes32)" \
  0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace \
  --rpc-url $RPC_URL_421614

# If this fails, the oracle may not have recent price updates
```

### **Performance Optimization**

**Parallel Test Execution**:
```bash
# Create a test runner script
#!/bin/bash
echo "Running multi-network fork tests in parallel..."

forge test --match-contract DetoxHookArbitrumSepoliaFork &
PID1=$!

forge test --match-contract DetoxHookUnichainSepoliaFork &
PID2=$!

# Wait for all tests to complete
wait $PID1 $PID2

echo "All fork tests completed"
```

**RPC Rate Limiting Mitigation**:
- Use private RPC providers (Alchemy, Infura, QuickNode) for reliable testing
- Implement delays between test runs if using public RPCs
- Configure backup RPCs for failover

### **Verification Commands**

```bash
# Check hook deployment
cast call $DETOX_HOOK_ADDRESS "getHookPermissions()" --rpc-url $RPC_URL

# Verify pool initialization
cast call $POOL_MANAGER_ADDRESS "getSlot0(bytes32)" $POOL_ID --rpc-url $RPC_URL

# Test oracle connectivity
cast call $PYTH_ORACLE_ADDRESS "getPriceUnsafe(bytes32)" $ETH_PRICE_ID --rpc-url $RPC_URL
```

## 🎯 **MULTI-NETWORK SUCCESS METRICS**

### **Architecture Quality**
- ✅ **Reusable Base Class**: Single source of truth for fork test logic
- ✅ **Dynamic Address Resolution**: No hardcoded addresses to maintain
- ✅ **RPC Failover System**: Multiple fallback options for reliability
- ✅ **Parallel Execution Ready**: Tests can run simultaneously

### **Network Coverage**
- ✅ **Arbitrum Sepolia**: Production deployment + comprehensive testing
- ✅ **Unichain Sepolia**: Full fork testing implementation
- 🔄 **Ethereum Sepolia**: Architecture ready, pending contract addresses
- 🔄 **Base Sepolia**: Architecture ready, pending contract addresses

### **Developer Experience**
- ✅ **Clear Documentation**: Step-by-step expansion guide
- ✅ **Comprehensive Logging**: Network identification and status reporting
- ✅ **Error Handling**: Graceful degradation with actionable error messages
- ✅ **Environment Flexibility**: Easy RPC configuration via environment variables

**🏆 The multi-network fork testing architecture provides a robust, scalable foundation for testing DetoxHook across multiple blockchain networks with reliable failover mechanisms and comprehensive error handling.** 