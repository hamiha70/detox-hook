# SwapRouter Deployment Guide

This guide covers deploying the SwapRouter contract to Arbitrum Sepolia.

## Prerequisites

### 1. Environment Variables

Set the required environment variables:

```bash
# Required for deployment
export DEPLOYMENT_KEY=0x[your-private-key-here]
export ARBISCAN_API_KEY=[your-arbiscan-api-key-here]

# Optional - for custom configurations
export DEPLOYMENT_WALLET=[wallet-address]  # Used for reference/validation
```

⚠️ **Security Note**: Keep your `DEPLOYMENT_KEY` secure and never commit it to version control.

### 2. Network Configuration

The deployment is configured for **Arbitrum Sepolia**:
- Chain ID: 421614
- RPC URL: Uses the `arbitrum-sepolia` network from foundry.toml
- Block Explorer: https://arbitrum-sepolia.blockscout.com

## Deployment Steps

### Step 1: Verify Configuration

Test the deployment configuration without broadcasting:

```bash
make test-swap-router-deployment
```

This validates (without requiring any environment variables):
- Network connectivity to Arbitrum Sepolia
- Contract compilation
- Constructor parameters
- PoolSwapTest contract availability and verification
- Default pool configuration (ETH/USDC 0.3% fee)

### Step 2: Deploy Contract

Deploy to Arbitrum Sepolia:

```bash
make deploy-swap-router-arbitrum-sepolia
```

This will:
1. Deploy the SwapRouter contract
2. Verify the contract on Arbiscan
3. Display deployment information
4. Save deployment details for tracking

### Step 3: Update Deployment Records

After successful deployment, update the deployment tracking:

```bash
# The deployment script will provide these values
node scripts-js/updateDeploymentInfo.js \
  <contract-address> \
  <deployment-hash> \
  <block-number> \
  <deployer-address>
```

## Deployment Configuration

### Constructor Parameters

The SwapRouter is deployed with:

```solidity
SwapRouter(
  poolSwapTest: 0xf3A39C86dbd13C45365E57FB90fe413371F65AF8,
  poolKey: {
    currency0: 0x0000000000000000000000000000000000000000, // ETH
    currency1: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d,   // USDC
    fee: 3000,        // 0.3%
    tickSpacing: 60,
    hooks: 0x0000000000000000000000000000000000000000
  }
)
```

### Network Details

- **Network**: Arbitrum Sepolia
- **Chain ID**: 421614
- **Default Pool**: ETH/USDC (0.3% fee)
- **PoolSwapTest**: 0xf3A39C86dbd13C45365E57FB90fe413371F65AF8

## Verification

After deployment, verify the contract is working:

### 1. Check Contract on Block Explorer

Visit: `https://arbitrum-sepolia.blockscout.com/address/[contract-address]`

### 2. Test Basic Functions

```bash
# Test deployment (read-only)
cast call [contract-address] "poolSwapTest()" --rpc-url arbitrum-sepolia

# Test pool configuration
cast call [contract-address] "defaultPoolKey()" --rpc-url arbitrum-sepolia
```

## Usage Examples

After deployment, you can interact with the SwapRouter:

### Basic Swap (Sell ETH for USDC)

```bash
# Sell 0.1 ETH for USDC
cast send [contract-address] \
  "swap(int256,bytes)" \
  -- \
  -100000000000000000 \
  0x \
  --value 0.1ether \
  --private-key $DEPLOYMENT_KEY \
  --rpc-url arbitrum-sepolia
```

### Configuration Updates

```bash
# Update pool configuration (if needed)
cast send [contract-address] \
  "updatePoolConfiguration((address,address,uint24,int24,address))" \
  "([new-pool-config])" \
  --private-key $DEPLOYMENT_KEY \
  --rpc-url arbitrum-sepolia
```

## Troubleshooting

### Common Issues

1. **DEPLOYMENT_KEY not set**
   ```
   Error: DEPLOYMENT_KEY environment variable is not set
   ```
   Solution: `export DEPLOYMENT_KEY=0x[your-private-key]`

2. **Insufficient balance**
   ```
   Error: insufficient funds for gas * price + value
   ```
   Solution: Add ETH to your deployment wallet on Arbitrum Sepolia

3. **Verification failed**
   ```
   Error: verification failed
   ```
   Solution: Check ARBISCAN_API_KEY is set correctly

4. **Network connection issues**
   ```
   Error: could not connect to RPC
   ```
   Solution: Check network connectivity and RPC endpoint

### Getting Help

- Check the deployment logs for detailed error messages
- Verify all environment variables are set correctly
- Ensure sufficient ETH balance in deployment wallet
- Test with the dry-run command first: `make test-swap-router-deployment`

## Security Considerations

- ✅ Never commit private keys to version control
- ✅ Use a dedicated deployment wallet with minimal funds
- ✅ Verify contract addresses match expected values
- ✅ Test on testnets before mainnet deployment
- ✅ Double-check constructor parameters before deployment

## File Locations

- **Contract**: `packages/foundry/src/SwapRouter.sol`
- **Deployment Script**: `packages/foundry/script/DeploySwapRouter.s.sol`
- **Tests**: `packages/foundry/test/SwapRouter.t.sol`
- **Deployment Tracking**: `packages/foundry/deployments/arbitrum-sepolia.json`
- **Update Script**: `packages/foundry/scripts-js/updateDeploymentInfo.js` 