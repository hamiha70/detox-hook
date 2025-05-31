# DetoxHook Complete Deployment Guide

This guide explains how to use the comprehensive DetoxHook deployment script that handles all aspects of deployment, pool initialization, and liquidity provision.

## Overview

The `DeployDetoxHookComplete.s.sol` script performs the following operations in sequence:

1. **Balance Check**: Verifies deployer has sufficient ETH and USDC
2. **DetoxHook Deployment**: Deploys DetoxHook with proper address mining
3. **Contract Verification**: Verifies on Arbitrum Sepolia Blockscout (real networks only)
4. **Hook Funding**: Funds the hook with 0.001 ETH
5. **Pool Initialization**: Creates two ETH/USDC pools with different configurations
6. **Liquidity Provision**: Adds initial liquidity to both pools

## Pool Configurations

The script creates two pools with different tick spacings and prices:

### Pool 1: ETH/USDC @ 2500
- **Price**: 1 ETH = 2500 USDC
- **Tick Spacing**: 10
- **Fee**: 0.05% (500 basis points)

### Pool 2: ETH/USDC @ 2600
- **Price**: 1 ETH = 2600 USDC
- **Tick Spacing**: 60
- **Fee**: 0.05% (500 basis points)

## Prerequisites

### Environment Setup

1. **Set your deployment key**:
   ```bash
   export DEPLOYMENT_KEY=0x...your_private_key_here
   ```

2. **Ensure sufficient balances**:
   - **Minimum ETH**: 0.1 ETH (for gas and hook funding)
   - **Minimum USDC**: 10 USDC (for liquidity provision)

### Required Balances Breakdown

- **Gas costs**: ~0.05-0.08 ETH (deployment, pool init, liquidity)
- **Hook funding**: 0.001 ETH
- **Liquidity provision**: 2 USDC + corresponding ETH (~0.0008 ETH total for both pools)
- **Buffer**: Additional ETH for safety

**Total recommended**: 0.1 ETH + 10 USDC for safe deployment

## Deployment Options

### 1. Real Arbitrum Sepolia Deployment

Deploy to the actual Arbitrum Sepolia testnet with verification:

```bash
cd packages/foundry
make deploy-detox-complete-arbitrum-sepolia
```

This will:
- Deploy to real Arbitrum Sepolia
- Verify contracts on Blockscout
- Use real USDC and ETH
- Create permanent pools

### 2. Fork Testing

Test the deployment on a forked Arbitrum Sepolia environment:

```bash
cd packages/foundry
make test-detox-complete-fork
```

This will:
- Fork Arbitrum Sepolia state
- Deploy in isolated environment
- Allow testing without real funds
- Reset after completion

### 3. Dry Run (Simulation)

Simulate the deployment without broadcasting transactions:

```bash
cd packages/foundry
make dry-run-detox-complete
```

This will:
- Validate all parameters
- Check balances
- Simulate all operations
- Show expected results without execution

### 4. Custom RPC Deployment

Deploy using a custom RPC URL:

```bash
cd packages/foundry
RPC_URL=https://your-custom-rpc.com make deploy-detox-complete
```

## Script Features

### Automatic Detection

The script automatically detects:
- **Fork vs Real Network**: Adjusts behavior accordingly
- **Existing Contracts**: Uses deployed infrastructure when available
- **Balance Sufficiency**: Warns or fails if balances are insufficient

### Comprehensive Logging

The script provides detailed logging for:
- Balance checks and requirements
- Contract addresses and deployment status
- Pool configurations and IDs
- Liquidity amounts and calculations
- Verification commands and explorer links

### Error Handling

The script handles:
- **Insufficient balances**: Fails immediately with detailed error message and funding instructions
- Missing environment variables
- Contract deployment failures
- Pool initialization errors

**Important**: The script will stop execution if the deployer address doesn't have sufficient ETH and USDC. This prevents failed deployments and wasted gas fees.

## Output Information

After successful deployment, the script outputs:

### Contract Addresses
- DetoxHook contract address
- Pool Manager address
- USDC token address
- PoolModifyLiquidityTest router address

### Pool Information
- Pool 1 ID and configuration
- Pool 2 ID and configuration
- Liquidity amounts added
- Current pool prices

### Verification Information
- Blockscout verification command
- Constructor arguments
- Explorer links for easy access

## Verification

### Automatic Verification (Real Networks)

On real Arbitrum Sepolia, the script automatically attempts verification using:
- **Verifier**: Blockscout
- **URL**: https://arbitrum-sepolia.blockscout.com/api
- **Constructor Args**: Automatically encoded

### Manual Verification

If automatic verification fails, use the logged command:

```bash
forge verify-contract <CONTRACT_ADDRESS> src/DetoxHook.sol:DetoxHook \
  --chain-id 421614 \
  --constructor-args <ENCODED_ARGS> \
  --verifier blockscout \
  --verifier-url https://arbitrum-sepolia.blockscout.com/api
```

## Post-Deployment Testing

### 1. Verify Hook Functionality

Check that the hook is properly deployed:
- Hook address has correct permission flags
- Hook is connected to Pool Manager
- Hook has received funding (0.001 ETH)

### 2. Test Pool Operations

Verify pools are working:
- Pools are initialized at correct prices
- Liquidity is properly added
- Swaps can be executed

### 3. Monitor Hook Behavior

Test the arbitrage capture:
- Execute swaps on both pools
- Monitor hook's arbitrage capture
- Check accumulated tokens in hook

## Troubleshooting

### Common Issues

1. **Insufficient Balance Error**
   ```
   [ERROR] Insufficient balance detected!
   ===============================================
              DEPLOYMENT FAILED!                
   ===============================================
   ```
   **Solution**: 
   - Check the detailed balance breakdown in the error message
   - Fund your deployer address with the required amounts:
     - **ETH**: At least 0.1 ETH for gas costs, hook funding, and liquidity
     - **USDC**: At least 10 USDC for liquidity provision
   - Verify your deployer address matches the one shown in the error
   - Try again after funding

2. **Hook Address Mining Timeout**
   ```
   Error: Could not find valid hook address
   ```
   **Solution**: This is rare; try running again or check HookMiner configuration

3. **Pool Initialization Failure**
   ```
   Error: Pool already initialized
   ```
   **Solution**: Pools may already exist; check if this is expected

4. **Verification Failure**
   ```
   Error: Verification failed
   ```
   **Solution**: Use manual verification command from script output

### Debug Mode

For detailed debugging, add `-vvvv` flag:

```bash
forge script script/DeployDetoxHookComplete.s.sol:DeployDetoxHookComplete \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --broadcast \
  -vvvv
```

**Note**: Make sure `DEPLOYMENT_KEY` is set in your `.env` file in the foundry directory.

## Security Considerations

### Private Key Safety
- Never commit private keys to version control
- Use environment variables for sensitive data (set `DEPLOYMENT_KEY` in `.env`)
- Consider using hardware wallets for mainnet

### Network Validation
- Script validates chain ID before deployment
- Confirms you're on expected network
- Prevents accidental mainnet deployment

### Balance Protection
- Checks minimum balances before proceeding
- Warns about insufficient funds
- Prevents failed deployments due to gas issues

## Advanced Usage

### Custom Pool Parameters

To modify pool configurations, edit the constants in `DeployDetoxHookComplete.s.sol`:

```solidity
uint24 constant POOL_FEE = 500; // 0.05% fee
int24 constant TICK_SPACING_POOL_1 = 10;
int24 constant TICK_SPACING_POOL_2 = 60;
uint160 constant SQRT_PRICE_2500 = 3961408125713216879677197516800;
uint160 constant SQRT_PRICE_2600 = 4041451884327381504640132478976;
```

### Custom Liquidity Amounts

Modify liquidity provision amounts:

```solidity
uint256 constant LIQUIDITY_USDC_AMOUNT = 1e6; // 1 USDC
uint256 constant HOOK_FUNDING_AMOUNT = 0.001 ether; // 0.001 ETH
```

## Integration with Frontend

After deployment, update your frontend configuration:

1. **Update contract addresses** in `packages/nextjs/contracts/deployedContracts.ts`
2. **Add pool IDs** to your pool configuration
3. **Update hook address** in your application settings

## Next Steps

After successful deployment:

1. **Test Swaps**: Execute test swaps on both pools
2. **Monitor Performance**: Watch hook arbitrage capture
3. **Add More Liquidity**: Increase liquidity as needed
4. **Frontend Integration**: Connect your UI to the deployed contracts
5. **Production Deployment**: When ready, deploy to mainnet

## Support

For issues or questions:
- Check the troubleshooting section above
- Review the script logs for detailed error information
- Ensure all prerequisites are met
- Verify network connectivity and RPC endpoints 