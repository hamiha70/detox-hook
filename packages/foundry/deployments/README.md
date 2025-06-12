# DetoxHook Deployment Configurations

This directory contains deployment configuration files and contract addresses for different networks.

## 📁 **Directory Structure**

```
deployments/
├── README.md                    # This file
├── .gitignore                   # Ignores local development files
├── arbitrum-sepolia.json        # Arbitrum Sepolia testnet deployments
└── detox-hook-pools.json        # Live DetoxHook pool configurations
```

## 📋 **File Descriptions**

### **arbitrum-sepolia.json**
- **Purpose**: Tracks SwapRouter deployments on Arbitrum Sepolia testnet
- **Updated by**: `scripts-js/updateDeploymentInfo.js`
- **Contains**: Contract addresses, deployment metadata, constructor args
- **Used by**: Frontend integration, deployment scripts

### **detox-hook-pools.json**
- **Purpose**: Live DetoxHook deployment data and pool configurations
- **Contains**: 
  - DetoxHook contract address (`0x444F320aA27e73e1E293c14B22EfBDCbce0e0088`)
  - Two ETH/USDC pools with different fee tiers
  - Pool IDs, liquidity data, transaction hashes
  - Deployment costs and verification status
- **Used by**: SwapRouter frontend, testing scripts, pool management

### **.gitignore**
- **Purpose**: Excludes local development deployment files
- **Ignores**: `31337.json` (local Anvil network deployments)

## 🔧 **Usage**

### **Updating Deployment Info**
```bash
# Update SwapRouter deployment info
node scripts-js/updateDeploymentInfo.js <address> <txHash> <blockNumber> <deployer>
```

### **Reading Deployment Data**
```javascript
// In JavaScript/Node.js
const deploymentData = require('./deployments/arbitrum-sepolia.json');
const hookPools = require('./deployments/detox-hook-pools.json');
```

### **In Solidity Scripts**
```solidity
// Deployment scripts automatically export to this directory
string memory deploymentInfo = vm.readFile("deployments/arbitrum-sepolia.json");
```

## 🌐 **Network Support**

- **Arbitrum Sepolia** (Chain ID: 421614) - Testnet deployments
- **Local Anvil** (Chain ID: 31337) - Development (gitignored)
- **Future networks** - Add new `{network}.json` files as needed

## 🚀 **Live Deployments**

### **DetoxHook on Arbitrum Sepolia**
- **Contract**: `0x444F320aA27e73e1E293c14B22EfBDCbce0e0088`
- **Explorer**: [Blockscout](https://arbitrum-sepolia.blockscout.com/address/0x444F320aA27e73e1E293c14B22EfBDCbce0e0088)
- **Pools**: 2 ETH/USDC pools (0.3% and 0.05% fees)
- **Status**: ✅ Deployed and initialized

### **Integration with Frontend**
- **ABI Generation**: `generateTsAbis.js` reads deployment data
- **SwapRouter Frontend**: Uses pool configurations for testing
- **Contract Verification**: Addresses used for Blockscout verification

## ⚠️ **Important Notes**

1. **Do not delete** these files - they contain live deployment data
2. **Network-specific** - Each file corresponds to a specific blockchain
3. **Version control** - These files are committed to track deployments
4. **Automated updates** - Scripts update these files during deployment
5. **Frontend dependency** - Required for proper dApp functionality 