# Deployment Examples

This directory contains example deployment scripts that demonstrate how to deploy DetoxHook to specific networks.

## Available Examples

### DeployToArbitrumSepolia.s.sol

A comprehensive example showing how to deploy DetoxHook to Arbitrum Sepolia testnet.

**Features:**
- [x] Network validation
- [x] Complete address logging
- [x] Deployment readiness check
- [x] Post-deployment guidance
- [x] Useful links and next steps

**Usage:**

```bash
# Check if ready for deployment
forge script script/examples/DeployToArbitrumSepolia.s.sol \
    --sig "checkDeploymentReadiness()" \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc

# Deploy to Arbitrum Sepolia
export PRIVATE_KEY="your_private_key_here"
forge script script/examples/DeployToArbitrumSepolia.s.sol \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --broadcast \
    --verify
```

## Creating New Examples

To create a deployment example for a new network:

1. **Add the network to ChainAddresses.sol** first
2. **Create a new script** inheriting from `DeployDetoxHook`
3. **Override the `run()` function** with network-specific logic
4. **Add validation** to ensure correct network
5. **Include helpful logging** and next steps

### Template:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../DeployDetoxHook.s.sol";
import { ChainAddresses } from "../ChainAddresses.sol";

contract DeployToYourNetwork is DeployDetoxHook {
    function run() external override {
        // Validate network
        require(block.chainid == ChainAddresses.YOUR_NETWORK, "Wrong network");
        
        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        address poolManager = ChainAddresses.getPoolManager(block.chainid);
        DetoxHook hook = deployDetoxHook(poolManager);
        
        vm.stopBroadcast();
        
        // Log results
        console.log("Deployed to:", address(hook));
    }
}
```

## Environment Variables

All deployment scripts require:

```bash
export PRIVATE_KEY="your_private_key_here"
```

Optional but recommended:
```bash
export ETHERSCAN_API_KEY="your_etherscan_api_key_for_verification"
```

## Security Notes

- **WARNING:** Never commit private keys to version control
- **RECOMMENDED:** Use hardware wallets for mainnet deployments
- **RECOMMENDED:** Test on testnets first
- **RECOMMENDED:** Verify contracts after deployment
- **RECOMMENDED:** Double-check network and addresses before broadcasting 