# SwapRouter Dashboard

A simple frontend interface for the SwapRouter contract built with ScaffoldETH 2.

## Features

### 🔄 Simple Swap Interface
- **Amount Input**: Enter the amount of ETH to swap using the `EtherInput` component
- **Swap Direction Toggle**: Switch between selling ETH for USDC and buying ETH with USDC
- **Update Data Field**: Optional field for additional price update data or hook data

### 📊 Real-time Information
- **Wallet Connection Status**: Shows connected address and ETH balance
- **Pool Configuration**: Displays current pool settings (currencies, fee, tick spacing)
- **Swap Details**: Preview of swap parameters before execution

### 🎯 Smart Contract Integration
- Uses `useScaffoldReadContract` to read pool configuration
- Uses `useScaffoldWriteContract` to execute swaps
- Automatic handling of exact input vs exact output swaps
- Proper ETH value handling for payable transactions

## Usage

### 1. Access the Dashboard
Navigate to `/swap` or click "SwapRouter" in the navigation menu.

### 2. Connect Your Wallet
Use the RainbowKit connect button to connect your wallet to Arbitrum Sepolia.

### 3. Configure Your Swap
- **Select Direction**: Click the arrow button to toggle between:
  - **Sell ETH**: Exchange your ETH for USDC (exact input)
  - **Buy ETH**: Purchase ETH with USDC (exact output)
- **Enter Amount**: Use the ETH input field to specify the amount
- **Update Data** (Optional): Add hex-encoded data for price feeds or hooks

### 4. Execute the Swap
Click "Swap" to execute the transaction. The interface will:
- Validate inputs and wallet connection
- Calculate the correct swap parameters
- Send the transaction with appropriate ETH value
- Show success/error notifications

## Technical Details

### Contract Functions Used
- `getPoolConfiguration()`: Reads current pool settings
- `getTestSettings()`: Reads test configuration
- `swap(int256 amountToSwap, bytes updateData)`: Executes the swap

### Swap Logic
- **Negative amounts**: Exact input swaps (selling specified amount)
- **Positive amounts**: Exact output swaps (buying specified amount)
- **ETH Value**: Only sent when selling ETH (exact input swaps)

### Error Handling
- Input validation (amount > 0, wallet connected)
- Transaction error display with user-friendly messages
- Loading states during transaction processing

## Configuration

### Contract Address
Update the SwapRouter address in `deployedContracts.ts`:

```bash
# After deploying SwapRouter
CONTRACT_ADDRESS=0x123...abc make update-frontend-address
```

### Network Support
Currently configured for:
- **Arbitrum Sepolia** (Chain ID: 421614)
- **ETH/USDC Pool** with 0.3% fee

## Components Used

### ScaffoldETH 2 Components
- `Address`: Displays wallet addresses
- `Balance`: Shows ETH balance
- `EtherInput`: ETH amount input with USD conversion

### ScaffoldETH 2 Hooks
- `useScaffoldReadContract`: Read contract data
- `useScaffoldWriteContract`: Execute transactions
- `useAccount`: Wallet connection state

### UI Components
- **DaisyUI**: For styling and components
- **Heroicons**: For icons
- **Tailwind CSS**: For responsive design

## Development

### Local Development
```bash
# Start the frontend
cd packages/nextjs
yarn dev
```

### Testing with Local Network
1. Start a local Foundry chain
2. Deploy SwapRouter to local network
3. Update the contract address
4. Connect MetaMask to localhost:8545

### Production Deployment
1. Deploy SwapRouter to Arbitrum Sepolia
2. Update contract address in deployedContracts.ts
3. Deploy frontend to Vercel or IPFS

## Troubleshooting

### Common Issues

1. **"Contract not found"**
   - Ensure SwapRouter is deployed to the correct network
   - Verify the contract address is updated in deployedContracts.ts

2. **"Transaction failed"**
   - Check wallet has sufficient ETH balance
   - Verify connected to Arbitrum Sepolia
   - Ensure pool has liquidity

3. **"Invalid swap amount"**
   - Enter a positive amount greater than 0
   - Check decimal precision (max 18 decimals for ETH)

4. **Network mismatch**
   - Switch MetaMask to Arbitrum Sepolia
   - Check scaffold.config.ts for correct target network

### Support
- Check browser console for detailed error messages
- Verify contract exists on Arbitrum Sepolia block explorer
- Ensure sufficient gas fees for transactions 