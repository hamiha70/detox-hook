# SwapRouter Deployment Guide

This guide provides instructions for deploying the SwapRouter contract to Arbitrum Sepolia testnet.

## Overview

The SwapRouter contract is a simplified interface for interacting with Uniswap V4's PoolSwapTest contract. It organizes swap parameters and provides easy-to-use functions for executing swaps.

## Prerequisites

1. **Private Key**: You need a private key for an Ethereum account with ETH on Arbitrum Sepolia
2. **Arbitrum Sepolia ETH**: Get testnet ETH from [Arbitrum Sepolia Faucet](https://faucet.quicknode.com/arbitrum/sepolia)
3. **Environment Setup**: Ensure you have Foundry installed and configured

## Contract Configuration

The SwapRouter will be deployed with the following default configuration:

- **PoolSwapTest Address**: `0xf3A39C86dbd13C45365E57FB90fe413371F65AF8` (Arbitrum Sepolia)
- **Default Pool**: ETH/USDC pool
- **Fee Tier**: 0.3% (3000 basis points)
- **Tick Spacing**: 60
- **Hooks**: None (address(0))

## Deployment Methods

### Method 1: Using Makefile (Recommended)

#### Step 1: Test Deployment Configuration
```bash
# Test the deployment configuration without broadcasting
make test-swap-router-deployment
```

This will validate:
- Chain compatibility (Arbitrum Sepolia)
- PoolSwapTest address availability
- Default pool configuration
- Contract compilation

#### Step 2: Deploy to Arbitrum Sepolia
```bash
# Deploy SwapRouter to Arbitrum Sepolia
PRIVATE_KEY=your_private_key_here make deploy-swap-router-arbitrum-sepolia
```

**⚠️ Security Note**: Never commit your private key to version control. Use environment variables or external key management.

### Method 2: Using Forge Directly

#### Test Configuration
```bash
forge script script/DeploySwapRouter.s.sol:DeploySwapRouter \
  --sig "testDeployment()" \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc
```

#### Deploy Contract
```bash
PRIVATE_KEY=your_private_key forge script script/DeploySwapRouter.s.sol \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --broadcast \
  --verify \
  --legacy
```

## Advanced Configuration

### Custom Pool Configuration

If you want to deploy SwapRouter for a different token pair:

```solidity
// Example: Deploy for custom token pair
PoolKey memory customPoolKey = PoolKey({
    currency0: Currency.wrap(0xTokenA_Address),
    currency1: Currency.wrap(0xTokenB_Address),
    fee: 10000, // 1%
    tickSpacing: 200,
    hooks: IHooks(address(0))
});

SwapRouter customRouter = new SwapRouter(poolSwapTestAddress, customPoolKey);
```

### Environment Variables

You can set additional environment variables for deployment:

```bash
# Required
export PRIVATE_KEY="your_private_key_here"

# Optional - for verification
export ETHERSCAN_API_KEY="your_etherscan_api_key"

# Run deployment
make deploy-swap-router-arbitrum-sepolia
```

## Post-Deployment

### Verification

The deployment script automatically:
1. ✅ Validates the PoolSwapTest address
2. ✅ Verifies pool configuration
3. ✅ Checks default test settings
4. ✅ Displays deployment summary

### Using the Deployed Contract

After deployment, you can interact with SwapRouter:

```solidity
// Basic swap: sell 1 ETH for USDC
swapRouter.swap(-1e18, ""); // negative for exact input

// Buy exactly 100 USDC with ETH
swapRouter.swap(100e6, ""); // positive for exact output

// Custom direction swap
swapRouter.swapWithDirection(-0.5e18, false, ""); // sell USDC for ETH
```

## Network Information

### Arbitrum Sepolia Testnet
- **Chain ID**: 421614
- **RPC URL**: https://sepolia-rollup.arbitrum.io/rpc
- **Block Explorer**: https://arbitrum-sepolia.blockscout.com
- **Faucet**: https://faucet.quicknode.com/arbitrum/sepolia

### Key Addresses on Arbitrum Sepolia
- **PoolManager**: `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`
- **PoolSwapTest**: `0xf3A39C86dbd13C45365E57FB90fe413371F65AF8`
- **USDC**: `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d`

## Troubleshooting

### Common Issues

1. **"PoolSwapTest address not found"**
   - Ensure you're deploying to Arbitrum Sepolia (Chain ID: 421614)
   - Check that the PoolSwapTest address is correct in ChainAddresses.sol

2. **"Insufficient funds"**
   - Get testnet ETH from the Arbitrum Sepolia faucet
   - Ensure your account has enough ETH for gas fees

3. **"Unsupported chain"**
   - The deployment script only supports Arbitrum Sepolia and local development
   - Use the correct RPC URL: https://sepolia-rollup.arbitrum.io/rpc

4. **"PRIVATE_KEY not found"**
   - Set the PRIVATE_KEY environment variable
   - Format: `PRIVATE_KEY=0x123abc...` (include 0x prefix)

### Contract Verification

If automatic verification fails, you can verify manually:

```bash
forge verify-contract <deployed_address> SwapRouter \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --constructor-args $(cast abi-encode "constructor(address,tuple(address,address,uint24,int24,address))" <poolSwapTest> <poolKey>)
```

## Example Deployment Output

```
=== SwapRouter Deployment ===
Chain ID: 421614
Chain Name: Arbitrum Sepolia
Deployer: 0x123...abc

=== Deploying SwapRouter ===
PoolSwapTest address: 0xf3A39C86dbd13C45365E57FB90fe413371F65AF8
Pool currency0: 0x0000000000000000000000000000000000000000
Pool currency1: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
Pool fee: 3000
Pool tick spacing: 60

SwapRouter deployed at: 0x456...def

=== Deployment Validation ===
PoolSwapTest address: VERIFIED
Pool configuration: VERIFIED
Test settings: VERIFIED
=== All Validations Passed ===

=== Deployment Complete ===
SwapRouter deployed at: 0x456...def
Chain ID: 421614
Block Explorer: https://arbitrum-sepolia.blockscout.com
Contract URL: https://arbitrum-sepolia.blockscout.com/address/0x456...def
```

## Security Considerations

1. **Private Key Security**: Never share or commit private keys
2. **Testnet Only**: This guide is for testnet deployment only
3. **Gas Estimation**: Always test on testnet before mainnet deployment
4. **Contract Verification**: Verify contracts for transparency and trust

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the contract source code in `/src/swapRouter.sol`
3. Run tests to verify functionality: `forge test --match-contract SwapRouterTest` 