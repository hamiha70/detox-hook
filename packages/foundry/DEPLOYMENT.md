# DetoxHook Deployment Guide

This guide explains how to deploy the DetoxHook contract with proper address mining to ensure the hook address has the correct permission flags.

## Overview

DetoxHook is a Uniswap V4 hook that requires specific address flags to function properly. The hook address must have the `BEFORE_SWAP_FLAG` and `BEFORE_SWAP_RETURNS_DELTA_FLAG` bits set in its address.

## Supported Networks

The deployment script supports the following networks with pre-configured addresses:

### **Arbitrum Sepolia (Chain ID: 421614)**
- **Pool Manager**: `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`
- **Pyth Oracle**: `0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF`
- **USDC**: `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d`
- **Block Explorer**: https://arbitrum-sepolia.blockscout.com
- **RPC URL**: https://sepolia-rollup.arbitrum.io/rpc

### **Local Anvil (Chain ID: 31337)**
- **Pool Manager**: Deploy fresh or configure manually
- **All other addresses**: Deploy fresh or mock as needed

## Prerequisites

1. **Foundry installed** - [Installation guide](https://book.getfoundry.sh/getting-started/installation)
2. **Environment variables set**:
   ```bash
   PRIVATE_KEY=your_private_key_here
   RPC_URL=your_rpc_url_here
   ```
3. **Supported network** - Check `ChainAddresses.sol` for supported chains

## Deployment Methods

### Method 1: Automatic Address Mining (Recommended)

This method automatically mines the correct salt to ensure the hook address has the required flags.

```bash
# Deploy to Arbitrum Sepolia
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify

# Deploy to local Anvil (requires PoolManager to be deployed first)
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --rpc-url http://localhost:8545 \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### Method 2: Deterministic Deployment

If you have a specific salt you want to use:

```bash
# First, compute the expected address
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --sig "computeHookAddress(address,bytes32)" \
    0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 <YOUR_SALT> \
    --rpc-url $RPC_URL

# Then deploy with that salt
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --sig "deployDetoxHookDeterministic(address,bytes32)" \
    0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 <YOUR_SALT> \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

## Network Configuration

### Adding New Networks

To add support for a new network, update `script/ChainAddresses.sol`:

```solidity
// Add new chain ID constant
uint256 public constant NEW_NETWORK = 12345;

// Update each function to include the new network
function getPoolManager(uint256 chainId) internal pure returns (address) {
    if (chainId == NEW_NETWORK) {
        return 0x...; // Pool Manager address
    }
    // ... existing chains
}

// Update other functions similarly
```

### Local Development (Anvil)

1. **Start Anvil**:
   ```bash
   anvil
   ```

2. **Deploy PoolManager first** (or use existing V4 deployment):
   ```bash
   # Deploy V4 core contracts first
   # This is beyond the scope of this guide
   ```

3. **Update ChainAddresses.sol** with the deployed PoolManager address for local testing

### Testnet Deployment

For Arbitrum Sepolia, all addresses are pre-configured. Simply run:

```bash
# Set environment variables
export PRIVATE_KEY="your_private_key_here"
export RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"

# Deploy
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

## Deployment Process

The deployment script performs the following steps:

1. **Chain Validation**: Verifies the chain is supported and addresses are configured
2. **Address Mining**: Finds a salt that produces a hook address with correct permission flags
3. **CREATE2 Deployment**: Uses the CREATE2 Deployer Proxy for deterministic deployment
4. **Validation**: Verifies the deployed hook has correct permissions and address flags
5. **Logging**: Provides comprehensive deployment information with chain-specific details

## Verification

After deployment, the script automatically validates:

- ✅ Chain is supported and addresses are configured
- ✅ Hook permissions are correctly set
- ✅ Hook address has required flag bits
- ✅ Hook is connected to the correct Pool Manager
- ✅ Contract deployment was successful

## Example Output

```
=== DetoxHook Deployment ===
Chain ID: 421614
Chain Name: Arbitrum Sepolia
Pool Manager: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
Deployer: 0x5678...

=== Mining Hook Address ===
Required flags: 16384
Mining for address with correct flag bits...
Salt found: 0xabcd...
Expected hook address: 0x9abc...
Address flags match: true

=== CREATE2 Deployment ===
Expected address: 0x9abc...
Using CREATE2 Deployer: 0x4e59b44847b379578588920cA78FbF26c0B4956C
DetoxHook deployed at: 0x9abc...

=== Deployment Validation ===
Hook permissions:
  beforeSwap: true
  beforeSwapReturnDelta: true
+ Deployment validation passed

=== Deployment Summary ===
Contract Address: 0x9abc...
Chain: Arbitrum Sepolia
Block Explorer: https://arbitrum-sepolia.blockscout.com
Pool Manager: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
Hook Flags: 16384
Pyth Oracle: 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF
USDC Token: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
Universal Router: 0xeFd1D4bD4cf1e86Da286BB4CB1B8BcED9C10BA47
=== Deployment Complete ===

=== Deployment Complete ===
DetoxHook deployed at: 0x9abc...
Chain ID: 421614
Pool Manager: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
Block Explorer: https://arbitrum-sepolia.blockscout.com
```

## Testing

Run the comprehensive test suite to verify the hook works correctly:

```bash
forge test --match-contract DetoxHookTest -vvv
```

## Utility Functions

The deployment script provides several utility functions:

```bash
# Check if current chain is supported
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --sig "requireSupportedChain()" \
    --rpc-url $RPC_URL

# Get all V4 addresses for current chain
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --sig "getAllV4Addresses()" \
    --rpc-url $RPC_URL

# Generate a deterministic salt
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --sig "generateSalt(address,uint256)" \
    <DEPLOYER_ADDRESS> <NONCE> \
    --rpc-url $RPC_URL
```

## Troubleshooting

### Common Issues

1. **"UnsupportedChain" error**
   - Solution: Add the chain to `ChainAddresses.sol` or use a supported network

2. **"Pool Manager address cannot be zero"**
   - Solution: Ensure the Pool Manager is deployed and configured in `ChainAddresses.sol`

3. **"Hook address flags do not match required flags"**
   - Solution: The address mining failed. Try running the deployment again

4. **"CREATE2 deployment failed"**
   - Solution: Check that the CREATE2 Deployer Proxy is available on your network

5. **"AddressNotSet" error**
   - Solution: Update `ChainAddresses.sol` with the correct contract addresses for your network

### Getting Help

- Check the Foundry documentation: https://book.getfoundry.sh/
- Review Uniswap V4 hook examples: https://github.com/Uniswap/v4-periphery
- Ensure all dependencies are correctly installed and remapped
- Verify network addresses in `ChainAddresses.sol`

## Security Considerations

- Always verify contracts on block explorers after deployment
- Test thoroughly on testnets before mainnet deployment
- Keep private keys secure and never commit them to version control
- Consider using hardware wallets for mainnet deployments
- Verify all addresses in `ChainAddresses.sol` before deployment

## Adding New Networks

To add support for a new network:

1. **Add chain ID constant** to `ChainAddresses.sol`
2. **Update all address functions** with the new network's contract addresses
3. **Add chain name and explorer URL** functions
4. **Test deployment** on the new network
5. **Update this documentation** with the new network details

## Next Steps

After successful deployment:

1. **Initialize pools** with your hook using the deployed addresses
2. **Add liquidity** to test pools
3. **Implement additional hook logic** for arbitrage detection and MEV capture
4. **Integrate with frontend** applications using the deployed contract addresses
5. **Monitor hook performance** and gas usage on the target network
6. **Set up monitoring** using the block explorer links provided in deployment output 