# DetoxHook Deployment Guide

This guide explains how to deploy the DetoxHook contract with proper address mining to ensure the hook address has the correct permission flags.

## Overview

DetoxHook is a Uniswap V4 hook that requires specific address flags to function properly. The hook address must have the `BEFORE_SWAP_FLAG` and `BEFORE_SWAP_RETURNS_DELTA_FLAG` bits set in its address.

## Prerequisites

1. **Foundry installed** - [Installation guide](https://book.getfoundry.sh/getting-started/installation)
2. **Environment variables set**:
   ```bash
   PRIVATE_KEY=your_private_key_here
   RPC_URL=your_rpc_url_here
   ```
3. **Pool Manager deployed** on your target network

## Deployment Methods

### Method 1: Automatic Address Mining (Recommended)

This method automatically mines the correct salt to ensure the hook address has the required flags.

```bash
# Deploy with automatic address mining
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

### Method 2: Deterministic Deployment

If you have a specific salt you want to use:

```bash
# First, compute the expected address
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --sig "computeHookAddress(address,bytes32)" \
    <POOL_MANAGER_ADDRESS> <YOUR_SALT>

# Then deploy with that salt
forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
    --sig "deployDetoxHookDeterministic(address,bytes32)" \
    <POOL_MANAGER_ADDRESS> <YOUR_SALT> \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

## Network Configuration

### Local Development (Anvil)

1. Start Anvil:
   ```bash
   anvil
   ```

2. Deploy PoolManager first (or use existing deployment)

3. Set the Pool Manager address in the deployment script:
   ```bash
   # In the deployment script, update the poolManagers mapping
   # or use setPoolManagerAddress function
   ```

### Testnet Deployment

Update the `poolManagers` mapping in `DeployDetoxHook.s.sol` with the correct Pool Manager addresses for your target networks:

```solidity
constructor() {
    poolManagers[421614] = 0x...; // Arbitrum Sepolia
    poolManagers[11155111] = 0x...; // Ethereum Sepolia
    // Add more networks as needed
}
```

## Deployment Process

The deployment script performs the following steps:

1. **Address Mining**: Finds a salt that produces a hook address with correct permission flags
2. **CREATE2 Deployment**: Uses the CREATE2 Deployer Proxy for deterministic deployment
3. **Validation**: Verifies the deployed hook has correct permissions and address flags
4. **Logging**: Provides comprehensive deployment information

## Verification

After deployment, the script automatically validates:

- ✅ Hook permissions are correctly set
- ✅ Hook address has required flag bits
- ✅ Hook is connected to the correct Pool Manager
- ✅ Contract deployment was successful

## Example Output

```
=== DetoxHook Deployment ===
Chain ID: 421614
Pool Manager: 0x1234...
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
Chain ID: 421614
Pool Manager: 0x1234...
Hook Flags: 16384
=== Deployment Complete ===
```

## Testing

Run the comprehensive test suite to verify the hook works correctly:

```bash
forge test --match-contract DetoxHookTest -vvv
```

## Troubleshooting

### Common Issues

1. **"Pool Manager address cannot be zero"**
   - Solution: Set the correct Pool Manager address for your network

2. **"Hook address flags do not match required flags"**
   - Solution: The address mining failed. Try running the deployment again

3. **"CREATE2 deployment failed"**
   - Solution: Check that the CREATE2 Deployer Proxy is available on your network

### Getting Help

- Check the Foundry documentation: https://book.getfoundry.sh/
- Review Uniswap V4 hook examples: https://github.com/Uniswap/v4-periphery
- Ensure all dependencies are correctly installed and remapped

## Security Considerations

- Always verify contracts on block explorers after deployment
- Test thoroughly on testnets before mainnet deployment
- Keep private keys secure and never commit them to version control
- Consider using hardware wallets for mainnet deployments

## Next Steps

After successful deployment:

1. **Initialize pools** with your hook
2. **Add liquidity** to test pools
3. **Implement additional hook logic** for arbitrage detection
4. **Integrate with frontend** applications
5. **Monitor hook performance** and gas usage 