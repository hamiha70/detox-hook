# Blockscout Integration for Arbitrum Sepolia

This document explains how Blockscout has been configured as the custom block explorer for Arbitrum Sepolia in this Scaffold-ETH 2 project.

## Configuration

### 1. Scaffold Configuration (`scaffold.config.ts`)

The main configuration has been updated to:

- **Add Arbitrum Sepolia** to target networks
- **Configure Blockscout** as the custom block explorer

```typescript
const scaffoldConfig = {
  // Target networks now include Arbitrum Sepolia
  targetNetworks: [chains.foundry, chains.arbitrumSepolia],
  
  // Custom block explorers configuration
  blockExplorers: {
    [chains.arbitrumSepolia.id]: {
      name: "Blockscout",
      url: "https://arbitrum-sepolia.blockscout.com",
    },
  },
  // ... other config
};
```

### 2. Network Utilities (`utils/scaffold-eth/networks.ts`)

The network utilities have been enhanced to:

- **Check custom block explorers first** before falling back to default chain explorers
- **Support both transaction and address links** with custom explorers

```typescript
// Custom block explorer takes precedence
const customBlockExplorer = scaffoldConfig.blockExplorers?.[chainId];
const blockExplorerURL = customBlockExplorer?.url || defaultURL;
```

## Usage

### Automatic Integration

Once configured, the custom block explorer is automatically used throughout the application:

1. **Transaction Links**: All transaction hashes will link to Blockscout
2. **Address Links**: All address links will use Blockscout
3. **Block Explorer Page**: The built-in block explorer page will reference Blockscout

### Manual Usage

You can also use the utility functions directly:

```typescript
import { getBlockExplorerTxLink, getBlockExplorerAddressLink } from "~~/utils/scaffold-eth/networks";
import { arbitrumSepolia } from "viem/chains";

// Get transaction link
const txLink = getBlockExplorerTxLink(arbitrumSepolia.id, "0x123...");
// Returns: "https://arbitrum-sepolia.blockscout.com/tx/0x123..."

// Get address link  
const addressLink = getBlockExplorerAddressLink(arbitrumSepolia, "0xabc...");
// Returns: "https://arbitrum-sepolia.blockscout.com/address/0xabc..."
```

## Network Information

### Arbitrum Sepolia Details

- **Chain ID**: 421614
- **Name**: Arbitrum Sepolia
- **Block Explorer**: Blockscout
- **URL**: https://arbitrum-sepolia.blockscout.com
- **RPC**: https://sepolia-rollup.arbitrum.io/rpc

### Supported Features

Blockscout on Arbitrum Sepolia provides:

- ✅ **Transaction Details**: Full transaction information and traces
- ✅ **Address Information**: Balance, transaction history, contract details
- ✅ **Contract Verification**: Source code verification and interaction
- ✅ **Token Information**: ERC-20, ERC-721, ERC-1155 token details
- ✅ **API Access**: REST API for programmatic access

## Adding More Networks

To add custom block explorers for additional networks:

1. **Add the network** to `targetNetworks` in `scaffold.config.ts`
2. **Add block explorer config** to the `blockExplorers` object:

```typescript
blockExplorers: {
  [chains.arbitrumSepolia.id]: {
    name: "Blockscout",
    url: "https://arbitrum-sepolia.blockscout.com",
  },
  [chains.optimismSepolia.id]: {
    name: "Blockscout",
    url: "https://optimism-sepolia.blockscout.com",
  },
  // Add more networks as needed
},
```

## Verification

To verify the configuration is working:

1. **Start the development server**: `yarn dev`
2. **Connect to Arbitrum Sepolia** using your wallet
3. **Perform a transaction** (like deploying a contract)
4. **Click on transaction links** - they should open Blockscout
5. **Check address links** - they should also use Blockscout

## Troubleshooting

### Common Issues

1. **Links still use default explorer**
   - Check that Arbitrum Sepolia is in `targetNetworks`
   - Verify the chain ID (421614) matches in `blockExplorers`

2. **TypeScript errors**
   - Ensure the type definition allows number indexing
   - Check that viem/chains is properly imported

3. **Network not showing**
   - Verify your wallet is connected to Arbitrum Sepolia
   - Check that the network is properly configured in your wallet

### Testing

You can test the configuration by:

```bash
# Run type checking
yarn check-types

# Start development server
yarn dev

# Build the application
yarn build
```

## Related Files

- `scaffold.config.ts` - Main configuration
- `utils/scaffold-eth/networks.ts` - Network utilities
- `app/blockexplorer/page.tsx` - Block explorer page
- `components/` - Various components that use block explorer links

## Benefits of Blockscout

- **Open Source**: Fully open-source block explorer
- **Feature Rich**: Comprehensive blockchain data and analytics
- **API Access**: RESTful API for developers
- **Contract Interaction**: Built-in contract interaction tools
- **Multi-chain**: Supports many EVM-compatible chains
- **Real-time**: Live updates and real-time data 