# PoolStateViewer Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying and testing the PoolStateViewer contract on Arbitrum Sepolia.

## Prerequisites

1. **Environment Variables Set:**
   ```bash
   export ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
   export DEPLOYMENT_PRIVATE_KEY="your_private_key_here"
   ```

2. **Foundry Installed:**
   ```bash
   forge --version
   ```

3. **Sufficient ETH Balance:**
   - Ensure your deployment wallet has enough ETH for gas fees

## Deployment Steps

### 1. Build the Contract

```bash
cd packages/foundry
forge build
```

### 2. Deploy to Arbitrum Sepolia

```bash
forge script script/DeployPoolStateViewer.s.sol:DeployPoolStateViewer \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $DEPLOYMENT_PRIVATE_KEY \
    --broadcast \
    --chain 421614
```

### 3. Verify Deployment

After deployment, the script will output the contract address. Update the address in the test scripts:

```bash
# Update the contract address in pool_view.py
sed -i '' 's/POOL_STATE_VIEWER_ADDRESS = "0x.*"/POOL_STATE_VIEWER_ADDRESS = "NEW_CONTRACT_ADDRESS"/' scripts-python/pool_view.py
```

### 4. Run Tests

#### Solidity Tests
```bash
forge test --match-contract PoolStateViewerTest -vvv
```

#### Python Tests
```bash
cd scripts-python
python3 test_pool_state_viewer_complete.py
```

## Contract Functions

### Core Functions

1. **`getPoolStateById(bytes32 poolId)`**
   - Returns pool state information
   - Parameters: pool ID (bytes32)
   - Returns: sqrtPriceX96, tick, protocolFee, lpFee, liquidity, success

2. **`getIdByKey(PoolKey memory poolKey)`**
   - Generates pool ID from pool key
   - Parameters: pool key struct
   - Returns: pool ID (bytes32)

3. **`getTickInfo(bytes32 poolId, int24 tick)`**
   - Returns tick information
   - Parameters: pool ID, tick
   - Returns: liquidity, success

4. **`getPoolStateByKey(PoolKey memory poolKey)`**
   - Convenience function to get pool state from pool key
   - Parameters: pool key struct
   - Returns: same as getPoolStateById

### Usage Examples

#### Python Script Usage
```python
# Query pool state
python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --verbose

# Query specific tick
python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --tick 100
```

#### Solidity Usage
```solidity
// Get pool state
(uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee, uint128 liquidity, bool success) = 
    viewer.getPoolStateById(poolId);

// Generate pool ID
bytes32 poolId = viewer.getIdByKey(poolKey);

// Get tick info
(uint128 liquidity, bool success) = viewer.getTickInfo(poolId, tick);
```

## Testing

### Known Pool IDs

- **Pool 1:** `0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f`
- **Pool 2:** `0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa`

### Test Commands

```bash
# Run all tests
forge test --match-contract PoolStateViewerTest

# Run specific test
forge test --match-test testGetPoolStateById_ExistingPool

# Run with verbose output
forge test --match-contract PoolStateViewerTest -vvv

# Run Python tests
cd scripts-python
python3 test_pool_state_viewer_complete.py
```

## Troubleshooting

### Common Issues

1. **"execution reverted" Error**
   - Pool doesn't exist or isn't initialized
   - Check if the pool ID is correct
   - Verify the pool was properly initialized

2. **Contract Not Found**
   - Verify the contract address is correct
   - Check if the contract was deployed successfully
   - Ensure you're on the correct network

3. **RPC Connection Issues**
   - Verify ARBITRUM_SEPOLIA_RPC_URL is set correctly
   - Check network connectivity
   - Try a different RPC endpoint

### Debug Commands

```bash
# Check contract deployment
cast code NEW_CONTRACT_ADDRESS --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Verify pool manager address
cast call NEW_CONTRACT_ADDRESS "poolManager()" --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Test pool state query
cast call NEW_CONTRACT_ADDRESS "getPoolStateById(bytes32)" 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

## Configuration

### PoolManager Address
- **Arbitrum Sepolia:** `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`

### Network Configuration
- **Chain ID:** 421614
- **RPC URL:** https://sepolia-rollup.arbitrum.io/rpc
- **Explorer:** https://sepolia.arbiscan.io

## Security Notes

1. **Private Key Security**
   - Never commit private keys to version control
   - Use environment variables for sensitive data
   - Consider using hardware wallets for production

2. **Contract Verification**
   - Verify the contract on Arbiscan after deployment
   - Share the verified contract address with the team

3. **Testing**
   - Always test on testnet before mainnet
   - Use small amounts for testing
   - Verify all functions work as expected

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Verify all environment variables are set correctly
3. Ensure sufficient ETH balance for gas fees
4. Check network connectivity and RPC endpoint status
5. Review the contract logs for detailed error messages 