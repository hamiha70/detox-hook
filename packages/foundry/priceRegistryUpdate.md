# PriceRegistry Token Registration Guide

## Overview

The PriceRegistry contract provides a centralized mapping between token addresses and [Pyth Network](https://docs.pyth.network/price-feeds/price-feeds) price feed IDs. This enables DetoxHook to access real-time price data for MEV detection and protection.

## Contract Information

### Deployed Contracts (Arbitrum Sepolia)

- **PriceRegistry Address:** `0x1b72e21325175ef6a40d3883df8789e43534e1e6`
- **Deployer/Owner Address:** `0xFDc61d52721c5eBA3e2fc39190fd9a603256E5a2`
- **Network:** Arbitrum Sepolia (Chain ID: 421614)

### Function Signature

```solidity
function setPriceMapping(address token, bytes32 priceId, string calldata symbol) external onlyOwner
```

**Parameters:**
- `token`: Token contract address (use `address(0)` for native ETH)
- `priceId`: Pyth Network price feed ID in bytes32 format
- `symbol`: Token symbol for identification (e.g., "EURC", "ETH", "USDC")

## Registration Process

### Prerequisites

1. **Environment Variables:** Ensure your `.env` file contains:
   ```bash
   PRIVATE_KEY=0x...  # Deployer's private key
   ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
   ```

2. **Permissions:** Only the deployer/owner address can register new tokens

3. **Pyth Price Feed ID:** Obtain the correct price feed ID from [Pyth Network documentation](https://docs.pyth.network/price-feeds/price-feeds)

### Generic Command Template

```bash
cast send <PRICE_REGISTRY_ADDRESS> \
  "setPriceMapping(address,bytes32,string)" \
  <TOKEN_ADDRESS> \
  <PYTH_PRICE_FEED_ID> \
  "<TOKEN_SYMBOL>" \
  --private-key $PRIVATE_KEY \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

## Example: EUR/USD (MockEURC) Registration

### Token Details
- **Token:** MockEURC
- **Address:** `0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E`
- **Pyth Price Feed:** EUR/USD
- **Price Feed ID:** `0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b`
- **Symbol:** "EURC"

### Complete Command

```bash
cast send 0x1b72e21325175ef6a40d3883df8789e43534e1e6 \
  "setPriceMapping(address,bytes32,string)" \
  0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E \
  0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b \
  "EURC" \
  --private-key $PRIVATE_KEY \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

### Verification

After registration, verify the mapping:

```bash
# Check if token is registered
cast call 0x1b72e21325175ef6a40d3883df8789e43534e1e6 \
  "isRegistered(address)" \
  0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Get price feed ID for token
cast call 0x1b72e21325175ef6a40d3883df8789e43534e1e6 \
  "getPriceId(address)" \
  0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Get token details
cast call 0x1b72e21325175ef6a40d3883df8789e43534e1e6 \
  "getTokenDetails(address)" \
  0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

## Common Price Feed IDs

| Asset Pair | Price Feed ID | Notes |
|------------|---------------|-------|
| EUR/USD | `0xa995d00bb36a63cef7fd2c287dc105fc8f3d93779f062f09551b0af3e81ec30b` | Used for EURC token |
| ETH/USD | `0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace` | Native ETH pricing |
| USDC/USD | `0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a` | USDC stablecoin |

## Error Handling

### Common Errors

1. **OnlyOwner Error:** Caller is not the contract owner
   ```
   Error: OnlyOwner(caller, expectedOwner)
   ```
   **Solution:** Use the deployer's private key

2. **PriceIdAlreadyUsed Error:** Price feed ID already mapped to another token
   ```
   Error: PriceIdAlreadyUsed(priceId, existingToken, newToken)
   ```
   **Solution:** Use a different price feed ID or update existing mapping

3. **InvalidPriceId Error:** Price feed ID is bytes32(0)
   ```
   Error: InvalidPriceId(priceId)
   ```
   **Solution:** Provide a valid non-zero price feed ID

### Gas Estimation

Typical gas usage for `setPriceMapping`:
- **First registration:** ~80,000 gas
- **Update existing:** ~60,000 gas

## Sources and References

### Deployment Information
- **Contract Source:** [`packages/foundry/src/PriceRegistry.sol`](../src/PriceRegistry.sol)
- **Deployment Transaction:** Found in [`packages/foundry/broadcast/DeployDetoxHookComplete.s.sol/421614/run-latest.json`](../broadcast/DeployDetoxHookComplete.s.sol/421614/run-latest.json)
- **Deployer Address:** Transaction line 80 in deployment file

### Pyth Network Integration
- **Price Feed Documentation:** [Pyth Network Price Feeds](https://docs.pyth.network/price-feeds/price-feeds)
- **Price Feed IDs:** [Pyth Price Feed IDs](https://docs.pyth.network/price-feeds/price-feeds)
- **EUR/USD Price Feed:** Retrieved from official Pyth documentation

### DetoxHook Integration
- **MEV Protection:** PriceRegistry enables real-time arbitrage detection
- **Pull Oracle Model:** Pyth's on-demand price feeds for gas efficiency
- **Confidence Intervals:** Price validation with confidence bounds

## Security Considerations

1. **Private Key Management:** Store deployer private key securely in `.env`
2. **Network Verification:** Always verify you're on the correct network
3. **Price Feed Validation:** Ensure price feed IDs are correct and active
4. **Access Control:** Only owner can modify registry mappings
5. **Gas Limits:** Set appropriate gas limits for complex transactions

---

*Generated for DetoxHook - Uniswap V4 MEV Protection Hook*
*Last Updated: January 2025*
