# ScaffoldETH 2 + Arbitrum Sepolia Setup Guide

## 🎯 Overview
This project is configured to work with **Arbitrum Sepolia testnet** where the SwapRouter contract is deployed.

## 📋 Configuration Changes Made

### 1. Network Configuration (`packages/nextjs/scaffold.config.ts`)
```typescript
targetNetworks: [chains.arbitrumSepolia]  // Prioritized Arbitrum Sepolia
pollingInterval: 15000                     // Faster polling for testnet
onlyLocalBurnerWallet: false              // Allow burner wallet on testnet
rpcOverrides: {
  [chains.arbitrumSepolia.id]: "https://sepolia-rollup.arbitrum.io/rpc"
}
```

### 2. Contract Deployment
- **Contract**: SwapRouter
- **Address**: `0xAe91123dD0930b3bEa45dB227522839A9e095443`
- **Network**: Arbitrum Sepolia (Chain ID: 421614)
- **Block Explorer**: https://arbitrum-sepolia.blockscout.com

### 3. Frontend Integration
- **Dashboard**: Available at `/swap`
- **Features**: ETH ⇄ USDC swapping with Uniswap v4 integration
- **Pool**: ETH/USDC with 0.3% fee

## 🚀 How to Use

### 1. Start the Development Server
```bash
yarn start
```
The app will be available at `http://localhost:3001`

### 2. Connect Your Wallet
1. Click "Connect Wallet" in the top-right corner
2. **Important**: Switch to Arbitrum Sepolia network in your wallet
3. Get testnet ETH from [Arbitrum Sepolia Faucet](https://faucet.quicknode.com/arbitrum/sepolia)

### 3. Access the SwapRouter Dashboard
- Navigate to: `http://localhost:3001/swap`
- Or click "SwapRouter" in the navigation menu

### 4. Test Swapping
1. Enter amount to swap
2. Choose direction (Sell ETH → USDC or Buy ETH ← USDC)
3. Click "Swap" and confirm transaction in your wallet

## 🔧 Network Details

### Arbitrum Sepolia Testnet
- **Chain ID**: 421614
- **RPC URL**: https://sepolia-rollup.arbitrum.io/rpc
- **Block Explorer**: https://arbitrum-sepolia.blockscout.com
- **Faucet**: https://faucet.quicknode.com/arbitrum/sepolia

### Add to MetaMask
```json
{
  "chainId": "0x66eee",
  "chainName": "Arbitrum Sepolia",
  "rpcUrls": ["https://sepolia-rollup.arbitrum.io/rpc"],
  "nativeCurrency": {
    "name": "ETH",
    "symbol": "ETH",
    "decimals": 18
  },
  "blockExplorerUrls": ["https://arbitrum-sepolia.blockscout.com"]
}
```

## 🏗️ Contract Architecture

### SwapRouter Contract
- **Pool**: ETH/USDC with 0.3% fee
- **Tick Spacing**: 60
- **Integration**: Uniswap v4 PoolSwapTest
- **Functions**:
  - `swap(int256 amountToSwap, bytes updateData)` - Execute swaps
  - `getPoolConfiguration()` - Get pool details
  - `getTestSettings()` - Get test configuration

### Frontend Features
- ✅ Wallet connection status
- ✅ ETH balance display  
- ✅ Pool configuration viewer
- ✅ Swap direction toggle
- ✅ Amount input with ETH/USD conversion
- ✅ Transaction status notifications
- ✅ Real-time contract data reading

## 🐛 Troubleshooting

### Common Issues

1. **"Wrong Network" Error**
   - Switch to Arbitrum Sepolia in your wallet
   - Chain ID should be 421614

2. **"Insufficient Funds" Error**
   - Get testnet ETH from faucet
   - Ensure you have enough ETH for gas + swap amount

3. **Contract Not Found**
   - Verify you're on Arbitrum Sepolia
   - Contract address: `0xAe91123dD0930b3bEa45dB227522839A9e095443`

4. **Lockfile Issues**
   - Current setup bypasses yarn workspace issues
   - Frontend runs independently with npm

### Network Verification
Check your connection:
```bash
curl -X POST https://sepolia-rollup.arbitrum.io/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```
Should return: `{"jsonrpc":"2.0","id":1,"result":"0x66eee"}`

## 📱 Mobile Support
The dashboard is fully responsive and works on mobile devices. Make sure to use a mobile wallet that supports Arbitrum Sepolia.

## 🔐 Security Notes
- This is a **testnet deployment** for testing purposes only
- Never use real funds on testnets
- Private keys for testnets should be separate from mainnet keys
- All transactions are public on the blockchain explorer

## 🎊 Ready to Go!
Your ScaffoldETH 2 app is now fully configured for Arbitrum Sepolia. Visit the `/swap` page to start testing the SwapRouter functionality! 