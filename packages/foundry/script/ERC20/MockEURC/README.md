# MockEURC - Euro Coin Mock Token

## 📋 **Overview**

MockEURC is a mock implementation of EURC (Euro Coin) token for testing and development purposes. This package provides a complete deployment and management toolkit for MockEURC, mimicking the structure and functionality of the MockUSDC implementation.

**Key Features:**
- **ERC20 compliant** with minting capabilities
- **6 decimals** (standard for EURC)
- **Ownable** with deployer as initial owner
- **Comprehensive deployment scripts** and utilities
- **Safety checks** and validation throughout
- **Multi-environment support** (local, testnet, mainnet)
- **Full Arbitrum support** (One and Sepolia)

## 🗂️ **Package Structure**

```
MockEURC/
├── MockEURC.sol           # Main token contract
├── TokenHelpers.sol       # Deployment and management utilities
├── Deploy.s.sol          # Complete deployment script
├── MintMockEURC.s.sol    # Minting script
└── README.md             # This documentation
```

## 🚀 **Quick Start**

### **1. Local Development (Anvil)**

```bash
# Start local blockchain
yarn chain

# Deploy MockEURC locally
forge script script/ERC20/MockEURC/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Mint tokens to an address
RECIPIENT_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
MINT_AMOUNT=100000000000 \
PRIVATE_KEY=your_private_key \
forge script script/ERC20/MockEURC/MintMockEURC.s.sol --rpc-url http://localhost:8545 --broadcast
```

### **2. Arbitrum Sepolia (Testnet)**

```bash
# Deploy to Arbitrum Sepolia
forge script script/ERC20/MockEURC/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  --verifier-url https://api-sepolia.arbiscan.io/api

# Mint tokens
RECIPIENT_ADDRESS=0x1234... \
MINT_AMOUNT=100000000000 \
PRIVATE_KEY=$PRIVATE_KEY \
forge script script/ERC20/MockEURC/MintMockEURC.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast
```

### **3. Arbitrum One (Mainnet)**

```bash
# Deploy to Arbitrum One (MAINNET - USE WITH CAUTION)
forge script script/ERC20/MockEURC/Deploy.s.sol \
  --rpc-url $ARBITRUM_ONE_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  --verifier-url https://api.arbiscan.io/api

# Mint tokens
RECIPIENT_ADDRESS=0x1234... \
MINT_AMOUNT=100000000000 \
PRIVATE_KEY=$PRIVATE_KEY \
forge script script/ERC20/MockEURC/MintMockEURC.s.sol \
  --rpc-url $ARBITRUM_ONE_RPC_URL \
  --broadcast
```

## 📋 **Detailed Deployment Guide**

### **Step 1: Environment Setup**

Create or update your `.env` file:

```bash
# Required for deployment
DEPLOYMENT_KEY=0x1234567890abcdef...
PRIVATE_KEY=0x1234567890abcdef...  # Same as DEPLOYMENT_KEY for minting

# Arbitrum Sepolia (Testnet)
ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
ARBISCAN_API_KEY=your_arbiscan_api_key_here

# Arbitrum One (Mainnet) - USE WITH CAUTION
ARBITRUM_ONE_RPC_URL=https://arb1.arbitrum.io/rpc
ARBISCAN_API_KEY=your_arbiscan_api_key_here

# Required for minting
RECIPIENT_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
MINT_AMOUNT=100000000000  # 100,000 EURC (6 decimals)

# Optional deployment settings
FUND_DEMO_ACCOUNTS=true
ADDITIONAL_ACCOUNTS=
```

### **Step 2: Network-Specific Configuration**

#### **Arbitrum Sepolia (Recommended for Testing)**
```bash
export ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
export ARBISCAN_API_KEY=your_sepolia_arbiscan_key
export DEPLOYMENT_KEY=your_private_key
```

#### **Arbitrum One (Mainnet - Production)**
```bash
export ARBITRUM_ONE_RPC_URL=https://arb1.arbitrum.io/rpc
export ARBISCAN_API_KEY=your_mainnet_arbiscan_key
export DEPLOYMENT_KEY=your_private_key
```

### **Step 3: Deploy MockEURC**

#### **Local Network**
```bash
forge script script/ERC20/MockEURC/Deploy.s.sol \
  --rpc-url http://localhost:8545 \
  --private-key $DEPLOYMENT_KEY \
  --broadcast
```

#### **Arbitrum Sepolia (Testnet)**
```bash
forge script script/ERC20/MockEURC/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $DEPLOYMENT_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  --verifier-url https://api-sepolia.arbiscan.io/api
```

#### **Arbitrum One (Mainnet)**
```bash
forge script script/ERC20/MockEURC/Deploy.s.sol \
  --rpc-url $ARBITRUM_ONE_RPC_URL \
  --private-key $DEPLOYMENT_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  --verifier-url https://api.arbiscan.io/api
```

### **Step 4: Update Minting Script**

After deployment, update the contract address in `MintMockEURC.s.sol`:

```solidity
// Replace this line with your deployed address
address constant MOCK_EURC = 0xYourDeployedMockEURCAddress;
```

### **Step 5: Mint Tokens**

#### **Local Network**
```bash
export RECIPIENT_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export MINT_AMOUNT=100000000000

forge script script/ERC20/MockEURC/MintMockEURC.s.sol \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast
```

#### **Arbitrum Sepolia**
```bash
export RECIPIENT_ADDRESS=0x1234...
export MINT_AMOUNT=100000000000

forge script script/ERC20/MockEURC/MintMockEURC.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

#### **Arbitrum One**
```bash
export RECIPIENT_ADDRESS=0x1234...
export MINT_AMOUNT=100000000000

forge script script/ERC20/MockEURC/MintMockEURC.s.sol \
  --rpc-url $ARBITRUM_ONE_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## 🔧 **TokenHelpers Library Usage**

The `TokenHelpers.sol` library provides comprehensive utilities for MockEURC management:

### **Core Functions**

```solidity
// Deploy standard MockEURC
MockEURC mockEURC = TokenHelpers.deployStandardMockEURC(deployer);

// Deploy with custom parameters
MockEURC mockEURC = TokenHelpers.deployMockEURC(
    deployer,
    "Custom Euro Coin",
    "CEURC"
);

// Complete deployment with funding
(MockEURC mockEURC, IERC20Minimal token) = TokenHelpers.deployAndSetupMockEURC(
    deployer,
    true, // Fund demo accounts
    additionalAccounts
);
```

### **Funding Operations**

```solidity
// Fund single account
TokenHelpers.fundAccount(mockEURC, recipient, 100_000e6);

// Fund multiple accounts
address[] memory accounts = new address[](2);
accounts[0] = address1;
accounts[1] = address2;
TokenHelpers.fundAccounts(mockEURC, accounts, 50_000e6);

// Fund demo accounts (Anvil accounts on local network)
TokenHelpers.fundDemoAccounts(mockEURC, additionalAccounts);
```

### **Validation and Management**

```solidity
// Validate deployment
TokenHelpers.validateMockEURC(mockEURC, expectedOwner);

// Check if address is MockEURC
bool isValid = TokenHelpers.isValidMockEURC(tokenAddress);

// Get interfaces
IERC20Minimal token = TokenHelpers.getTokenInterface(mockEURC);
MockEURC mockEURC = TokenHelpers.getMockEURC(tokenAddress);
```

## 📊 **Token Properties**

| Property | Value |
|----------|-------|
| **Name** | Euro Coin (Mock) |
| **Symbol** | EURC |
| **Decimals** | 6 |
| **Initial Supply** | 0 (mintable) |
| **Max Supply** | Unlimited |
| **Minting** | Owner only |

## 🛡️ **Safety Features**

### **Built-in Safety Checks**

- **ETH balance validation** before deployment
- **Contract existence verification** after deployment
- **Ownership validation** to prevent unauthorized minting
- **Token properties validation** (decimals, symbol, name)
- **Balance and allowance checks** before operations
- **Network-specific validations** for Arbitrum deployments

### **Error Handling**

```solidity
// Custom errors for better debugging
error ContractNotDeployed(address contractAddress, string contractName);
error InsufficientETHBalance(address account, uint256 required, uint256 actual, string operation);
error InsufficientTokenBalance(address token, address account, uint256 required, uint256 actual, string operation);
```

## 🎯 **Common Use Cases**

### **1. Uniswap V4 Pool Creation**

```solidity
import {TokenHelpers} from "./script/ERC20/MockEURC/TokenHelpers.sol";

// Deploy MockEURC for pool
(MockEURC mockEURC, IERC20Minimal eurcToken) = TokenHelpers.deployAndSetupMockEURC(
    deployer,
    true,
    new address[](0)
);

// Use in pool initialization
PoolKey memory poolKey = PoolKey({
    currency0: Currency.wrap(address(mockEURC)),
    currency1: Currency.wrap(address(weth)),
    fee: 3000,
    tickSpacing: 60,
    hooks: IHooks(hookAddress)
});
```

### **2. Testing and Development**

```solidity
// Fund test accounts
address[] memory testAccounts = new address[](3);
testAccounts[0] = testUser1;
testAccounts[1] = testUser2;
testAccounts[2] = testUser3;

TokenHelpers.fundAccounts(mockEURC, testAccounts, 10_000e6);
```

### **3. Demo Environment Setup**

```solidity
// Complete demo setup
(MockEURC mockEURC,) = TokenHelpers.deployAndSetupMockEURC(
    deployer,
    true, // Fund Anvil accounts
    new address[](0)
);

// Log status for verification
address[] memory accounts = new address[](1);
accounts[0] = deployer;
TokenHelpers.logTokenStatus(mockEURC, accounts);
```

## 🔍 **Verification and Debugging**

### **Check Deployment Status**

```bash
# Check if contract is deployed
cast code $MOCK_EURC_ADDRESS --rpc-url $RPC_URL

# Check token properties
cast call $MOCK_EURC_ADDRESS "name()" --rpc-url $RPC_URL
cast call $MOCK_EURC_ADDRESS "symbol()" --rpc-url $RPC_URL
cast call $MOCK_EURC_ADDRESS "decimals()" --rpc-url $RPC_URL
cast call $MOCK_EURC_ADDRESS "owner()" --rpc-url $RPC_URL
```

### **Check Balances**

```bash
# Check balance of an account
cast call $MOCK_EURC_ADDRESS "balanceOf(address)" $ACCOUNT_ADDRESS --rpc-url $RPC_URL

# Check total supply
cast call $MOCK_EURC_ADDRESS "totalSupply()" --rpc-url $RPC_URL
```

### **Debug Minting Issues**

```bash
# Verify owner can mint
cast call $MOCK_EURC_ADDRESS "owner()" --rpc-url $RPC_URL

# Check if account has minting rights
cast send $MOCK_EURC_ADDRESS "mint(address,uint256)" $RECIPIENT $AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

## 📝 **Environment Variables Reference**

| Variable | Description | Example |
|----------|-------------|---------|
| `DEPLOYMENT_KEY` | Deployer private key | `0x123...` |
| `PRIVATE_KEY` | Private key for minting | `0x123...` |
| `ARBITRUM_SEPOLIA_RPC_URL` | Arbitrum Sepolia RPC | `https://sepolia-rollup.arbitrum.io/rpc` |
| `ARBITRUM_ONE_RPC_URL` | Arbitrum One RPC | `https://arb1.arbitrum.io/rpc` |
| `ARBISCAN_API_KEY` | Arbiscan API key | `ABC123...` |
| `RECIPIENT_ADDRESS` | Address to mint tokens to | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| `MINT_AMOUNT` | Amount to mint (in token units) | `100000000000` (100k EURC) |
| `FUND_DEMO_ACCOUNTS` | Whether to fund demo accounts | `true` or `false` |
| `ADDITIONAL_ACCOUNTS` | Comma-separated additional accounts | `0x123...,0x456...` |

## 🌐 **Network-Specific Information**

### **Arbitrum Sepolia (Testnet)**
- **Chain ID**: 421614
- **RPC URL**: `https://sepolia-rollup.arbitrum.io/rpc`
- **Block Explorer**: `https://sepolia.arbiscan.io/`
- **API Endpoint**: `https://api-sepolia.arbiscan.io/api`
- **Gas Costs**: Very low (fractions of a cent)
- **Use Case**: Testing and development

### **Arbitrum One (Mainnet)**
- **Chain ID**: 42161
- **RPC URL**: `https://arb1.arbitrum.io/rpc`
- **Block Explorer**: `https://arbiscan.io/`
- **API Endpoint**: `https://api.arbiscan.io/api`
- **Gas Costs**: Very low (fractions of a cent)
- **Use Case**: Production deployment

### **Local Anvil**
- **Chain ID**: 31337
- **RPC URL**: `http://localhost:8545`
- **Block Explorer**: N/A
- **Gas Costs**: Free
- **Use Case**: Local development and testing

## ⚠️ **Important Notes**

### **Security Considerations**

1. **Private Key Safety**: Never commit private keys to version control
2. **Owner Privileges**: Only the owner can mint tokens - secure the owner account
3. **Testnet First**: Always test on Arbitrum Sepolia before mainnet
4. **Mainnet Caution**: Arbitrum One is mainnet - use with extreme caution
5. **Address Updates**: Always update contract addresses in scripts after deployment

### **Gas Optimization**

- **Arbitrum Benefits**: Much lower gas costs than Ethereum
- **Batch Operations**: Use `fundAccounts()` for multiple recipients
- **Approval Patterns**: TokenHelpers includes approval management
- **Deployment Costs**: Typical deployment costs ~50k-100k gas on Arbitrum

### **Network Compatibility**

- ✅ **Local Anvil**: Full support with demo account funding
- ✅ **Arbitrum Sepolia**: Tested and verified, recommended for testing
- ✅ **Arbitrum One**: Compatible but mainnet - use with caution
- ✅ **Other EVM Networks**: Compatible with all EVM networks

## 🆘 **Troubleshooting**

### **Common Issues**

| Issue | Solution |
|-------|----------|
| "Insufficient ETH for deployment" | Fund deployer account with ETH (Arbitrum has very low costs) |
| "Contract already deployed" | Use different deployer or check existing deployment |
| "Only owner can mint" | Ensure correct private key is used |
| "Invalid recipient address" | Verify RECIPIENT_ADDRESS environment variable |
| "Verification failed" | Check ARBISCAN_API_KEY and --verifier-url |

### **Arbitrum-Specific Issues**

| Issue | Solution |
|-------|----------|
| "RPC connection failed" | Check Arbitrum RPC URL and network status |
| "Verification on wrong network" | Use correct --verifier-url for Arbitrum/Arbiscan |
| "Gas estimation failed" | Ensure deployer has sufficient ETH for gas |

### **Error Messages**

```bash
# Contract not deployed
Error: Contract not found at: 0x...
Solution: Deploy contract first or check address

# Insufficient balance
Error: Insufficient ETH balance
Solution: Fund deployer account with ETH (Arbitrum costs are very low)

# Wrong owner
Error: Only owner can mint
Solution: Use deployer's private key for minting

# Verification failed
Error: Verification failed
Solution: Check ARBISCAN_API_KEY and use correct --verifier-url
```

## 📚 **Additional Resources**

- **MockUSDC Implementation**: `script/ERC20/MockUSDC/` for reference
- **SafetyChecks Library**: `script/Utility/SafetyChecks.sol` for safety utilities
- **Foundry Documentation**: [https://book.getfoundry.sh/](https://book.getfoundry.sh/)
- **OpenZeppelin Contracts**: [https://docs.openzeppelin.com/contracts/](https://docs.openzeppelin.com/contracts/)
- **Arbitrum Documentation**: [https://docs.arbitrum.io/](https://docs.arbitrum.io/)
- **Arbiscan**: [https://arbiscan.io/](https://arbiscan.io/)

---

**🪙 MockEURC provides a robust foundation for Euro-denominated testing and development in the DetoxHook ecosystem, with full support for Arbitrum networks!**
