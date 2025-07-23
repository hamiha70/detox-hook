# DetoxHook Python Scripts

This directory contains Python utilities for the DetoxHook project.

## 📦 Scripts Overview

### `load_env.py` - Environment Variable Loader

A secure utility that loads environment variables from `.env` files and exports them to the current environment.

### `check_balances.py` - Wallet Balance Checker

A comprehensive tool that checks ETH and USDC balances for wallet addresses on Arbitrum Sepolia. Integrates with DetoxHook environment configuration for seamless development workflow.

### `verify_contract.py` - Contract Address Verifier

A powerful utility that verifies if addresses belong to deployed smart contracts. Includes automatic detection of known DetoxHook contracts and detailed contract information.

### `provide_liquidity.py` - Uniswap V4 Liquidity Provider

A comprehensive tool for providing liquidity to Uniswap V4 pools on Arbitrum Sepolia. Supports both ETH and USDC amounts, dry-run simulation, and integrates with DetoxHook pool configurations.

## 🚀 Quick Start

### Basic Usage

```bash
# Load default .env file
python load_env.py

# Load specific .env file
python load_env.py --env-file .env.local

# Show what would be loaded (dry run)
python load_env.py --dry-run

# Verbose output (sensitive values hidden)
python load_env.py --verbose

# Create shell export script
python load_env.py --export-shell
```

### Balance Checker Usage

```bash
# Check specific wallet address
python check_balances.py 0x00cA5716A51f8E48055d03fCadE8CFE0A463Bab6

# Check all wallet addresses from .env file
python check_balances.py --env-wallets

# Check with verbose output (shows contract addresses)
python check_balances.py --env-wallets --verbose

# Output results in JSON format
python check_balances.py --env-wallets --json

# Check multiple specific addresses
python check_balances.py 0xABC... 0xDEF... 0x123...

# Show balances even when they are zero
python check_balances.py --env-wallets --show-empty
```

### Contract Verification Usage

```bash
# Verify specific contract address
python verify_contract.py 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317

# Verify all known DetoxHook contracts
python verify_contract.py --all

# Check contracts from environment variables
python verify_contract.py --env-contracts --verbose

# Multiple addresses with detailed info
python verify_contract.py 0xAddr1 0xAddr2 --show-details

# JSON output for automation
python verify_contract.py --all --json
```

### Liquidity Provision Usage

```bash
# List available pools
python provide_liquidity.py --list-pools

# Provide 1 USDC worth of liquidity (calculates ETH automatically)
python provide_liquidity.py 0xYourWallet 0x5e6967b5... --usdc-amount 1

# Provide 0.001 ETH worth of liquidity (calculates USDC automatically)  
python provide_liquidity.py 0xYourWallet 0x5e6967b5... --eth-amount 0.001

# Dry-run simulation with environment wallet
python provide_liquidity.py 0x5e6967b5... --env-wallet --usdc-amount 10 --dry-run

# Custom tick range for concentrated liquidity
python provide_liquidity.py 0xYourWallet 0x5e6967b5... --usdc-amount 1 --tick-lower -300 --tick-upper 300
```

### Integration with DetoxHook

```bash
# From project root
cd /path/to/detox-hook

# Load environment variables
python packages/foundry/scripts-python/load_env.py --verbose

# Or run from any directory (script searches up the directory tree)
cd packages/foundry/scripts-python
python load_env.py
```

## 🔧 Features

### ✅ Security First
- **Never exposes sensitive data** in logs or output
- **Automatically detects sensitive variables** (keys, secrets, tokens)
- **Safe parsing** of .env files with proper escaping

### 🎯 Smart Detection
- **Automatically finds .env files** in project structure
- **Supports various .env formats** (quoted, unquoted, comments)
- **Handles malformed lines** gracefully

### 🛠️ Multiple Output Modes
- **Direct export** to current environment
- **Shell script generation** for sourcing
- **Dry run mode** for testing
- **Verbose logging** with security-aware output

## 📋 Command Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--env-file` | `-f` | Path to .env file (default: `.env`) |
| `--verbose` | `-v` | Show detailed output (sensitive values hidden) |
| `--dry-run` | `-n` | Show what would be loaded without loading |
| `--export-shell` | `-e` | Create shell script to export variables |
| `--shell-file` | | Output file for shell script (default: `env_exports.sh`) |

## 🔍 Example Outputs

### Standard Load
```bash
$ python load_env.py
🔧 DetoxHook Environment Loader
===================================
📊 Summary: 5 new, 2 updated, 7 total variables loaded
```

### Verbose Mode
```bash
$ python load_env.py --verbose
🔧 DetoxHook Environment Loader
===================================
📂 Found .env file: /path/to/detox-hook/.env
✅ [LOADED] RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
✅ [LOADED] PRIVATE_KEY=***HIDDEN***
✅ [UPDATED] NODE_ENV=development
📊 Summary: 2 new, 1 updated, 3 total variables loaded
```

### Dry Run Mode
```bash
$ python load_env.py --dry-run
🔧 DetoxHook Environment Loader
===================================
📂 Found .env file: /path/to/detox-hook/.env
🔧 [NEW] RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
🔧 [NEW] PRIVATE_KEY=***HIDDEN***
🔧 [UPDATE] NODE_ENV=development
📊 Summary: 3 variables would be processed
```

## 🛡️ Security Features

### Sensitive Variable Detection
The script automatically detects and hides sensitive variables containing:
- `KEY` (PRIVATE_KEY, DEPLOYMENT_KEY, API_KEY)
- `SECRET` (CLIENT_SECRET, DB_SECRET)
- `PASSWORD` (DB_PASSWORD, ADMIN_PASSWORD) 
- `TOKEN` (AUTH_TOKEN, ACCESS_TOKEN)
- `MNEMONIC` (WALLET_MNEMONIC)
- `SEED` (RANDOM_SEED)

### Safe Output
```bash
# Sensitive variables are never shown in full
✅ [LOADED] PRIVATE_KEY=***HIDDEN***
✅ [LOADED] DEPLOYMENT_KEY=***HIDDEN***

# Non-sensitive variables are displayed normally
✅ [LOADED] RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
✅ [LOADED] NODE_ENV=development
```

## 🔄 Integration Examples

### With Foundry Scripts
```bash
# Load environment, then run forge commands
python packages/foundry/scripts-python/load_env.py
forge script DeployDetoxHook --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### With Shell Scripts
```bash
# Generate shell export script
python load_env.py --export-shell

# Source the generated script
source env_exports.sh

# Now all variables are available in the shell
echo $RPC_URL
```

### With CI/CD
```yaml
# GitHub Actions example
- name: Load Environment Variables
  run: |
    python packages/foundry/scripts-python/load_env.py --env-file .env.production
    
- name: Deploy Contracts
  run: |
    forge script DeployDetoxHook --rpc-url $RPC_URL --broadcast
```

## 🚨 Important Notes

### File Search Order
The script searches for `.env` files in this order:
1. Current directory
2. Parent directory
3. Parent's parent (up to 3 levels)

### Environment Variable Priority
- **Existing environment variables are updated** if found in .env
- **New variables are added** to the environment
- **Script does not remove** existing environment variables

### Error Handling
- **Missing .env file**: Script exits with error code 1
- **Malformed lines**: Skipped with warning in verbose mode
- **Permission errors**: Handled gracefully with error message

## 🎯 DetoxHook Specific Usage

### Environment Management
```bash
# Load all environment variables for development
python packages/foundry/scripts-python/load_env.py --verbose

# Test with dry run first
python packages/foundry/scripts-python/load_env.py --dry-run

# Create shell exports for CI/CD
python packages/foundry/scripts-python/load_env.py --export-shell --shell-file deploy_env.sh
```

### Balance Monitoring
```bash
# Check all DetoxHook wallet balances
python packages/foundry/scripts-python/check_balances.py --env-wallets

# Monitor balances before/after deployment
python packages/foundry/scripts-python/check_balances.py --env-wallets --verbose

# Export balance data for analysis
python packages/foundry/scripts-python/check_balances.py --env-wallets --json > balances.json

# Check specific deployment wallet
python packages/foundry/scripts-python/check_balances.py $DEPLOYMENT_WALLET

# Monitor liquidity provider funds
python packages/foundry/scripts-python/check_balances.py $LIQUIDITY_PROVIDER_WALLET --verbose
```

### Contract Verification
```bash
# Verify all DetoxHook deployment contracts  
python packages/foundry/scripts-python/verify_contract.py --all

# Verify specific deployment addresses
python packages/foundry/scripts-python/verify_contract.py $SWAP_ROUTER_CONTRACT_ADDRESS

# Check contracts before deployment
python packages/foundry/scripts-python/verify_contract.py --env-contracts --verbose

# Verify hook and oracle contracts
python packages/foundry/scripts-python/verify_contract.py 0x444F320aA27e73e1E293c14B22EfBDCbce0e0088 0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF
```

### Liquidity Provision
```bash
# List all available pools
python packages/foundry/scripts-python/provide_liquidity.py --list-pools

# Simulate providing 1 USDC to the 0.3% fee pool
python packages/foundry/scripts-python/provide_liquidity.py 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --env-wallet --usdc-amount 1 --dry-run

# Actually provide liquidity to the 0.05% fee pool  
python packages/foundry/scripts-python/provide_liquidity.py 0x10fe1bb5300768c6f5986ee70c9ee834ea64ea704f92b0fd2cda0bcbe829ec90 --env-wallet --usdc-amount 10

# Provide ETH-based liquidity with custom tick range
python packages/foundry/scripts-python/provide_liquidity.py 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --env-wallet --eth-amount 0.001 --tick-lower -200 --tick-upper 200
```

### Combined Workflow
```bash
# Complete DetoxHook development workflow
python packages/foundry/scripts-python/load_env.py  # Load environment
python packages/foundry/scripts-python/check_balances.py --env-wallets  # Check funds
forge script DeployDetoxHook --rpc-url $ARBITRUM_SEPOLIA_RPC_URL  # Deploy
python packages/foundry/scripts-python/check_balances.py --env-wallets  # Verify balances after
```

## 🏦 Balance Checker Features

### ✅ Multi-Token Support
- **ETH balances** - Native Ethereum balances
- **USDC balances** - ERC-20 token balances on Arbitrum Sepolia
- **Extensible** - Easy to add more tokens

### 🎯 Smart Address Management
- **Environment integration** - Automatically loads wallet addresses from `.env`
- **Multiple address support** - Check many wallets at once
- **Address validation** - Ensures proper Ethereum address format

### 📊 Flexible Output Formats
- **Human-readable** - Nicely formatted console output
- **JSON export** - Machine-readable format for scripts
- **Verbose mode** - Shows contract addresses and detailed info
- **Empty balance display** - Optional showing of zero balances

### Example Output

```bash
$ python check_balances.py --env-wallets --verbose

🏦 DetoxHook Wallet Balance Report
==================================================
📊 Checked 3 addresses, 3 successful
📈 Latest block: 176,275,360

👛 Address: 0x00cA5716A51f8E48055d03fCadE8CFE0A463Bab6
   💰 ETH: 0.01375871
   💰 USDC: 14
      📄 Contract: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d

👛 Address: 0x6c299c77760Ae4B7C11Ac4632CB18d434F4f960C
   💰 ETH: 0.0049871
   💰 USDC: 16.1
      📄 Contract: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
```

## 🔍 Contract Verification Features

### ✅ Smart Contract Detection
- **Bytecode verification** - Checks if address has deployed code
- **Contract vs EOA detection** - Distinguishes smart contracts from wallets  
- **Known contract identification** - Auto-detects DetoxHook ecosystem contracts

### 🎯 Comprehensive Analysis
- **Bytecode size reporting** - Shows contract complexity
- **Balance checking** - ETH balance for both contracts and EOAs
- **Metadata detection** - Identifies contracts with IPFS metadata
- **Multi-address support** - Verify many addresses at once

### 📊 Flexible Output Formats
- **Human-readable reports** - Nicely formatted console output
- **JSON export** - Machine-readable format for automation
- **Detailed analysis** - Additional contract information on demand
- **Batch processing** - Environment and known contract verification

### Example Output

```bash
$ python verify_contract.py --all

📋 Contract Address Verification Report
=======================================================
📊 Checked 8 addresses:
   🏗️  8 Smart Contracts
   👤 0 EOA/Non-contracts

📍 Address: 0x444F320aA27e73e1E293c14B22EfBDCbce0e0088
   ✅ STATUS: Smart Contract Deployed
   📄 Bytecode size: 7,991 bytes
   🏷️  Known contract: DetoxHook
   💰 Balance: 0.001000 ETH
```

## 💧 Liquidity Provision Features

### ✅ Pool Discovery & Configuration
- **Pool listing** - View all available DetoxHook pools with descriptions and fees
- **Auto-configuration** - Loads pool parameters from deployment configuration
- **Price calculation** - Automatic ETH/USDC amount calculation based on pool prices

### 🎯 Flexible Amount Input
- **ETH-based provision** - Specify ETH amount, calculates USDC automatically
- **USDC-based provision** - Specify USDC amount, calculates ETH automatically  
- **Price-aware calculations** - Uses actual pool prices (2500 USDC/ETH, 2600 USDC/ETH)
- **Tick range customization** - Configurable liquidity concentration ranges

### 📊 Smart Validation & Safety
- **Balance checking** - Validates sufficient ETH and USDC before transaction
- **Allowance verification** - Checks USDC approval status for liquidity contract
- **Dry-run simulation** - Test transactions without spending gas or tokens
- **Environment integration** - Seamless wallet management via .env variables

### 🔧 Advanced Features
- **Real transaction execution** - Full liquidity provision with private key signing
- **Gas optimization** - Conservative gas limits for reliable execution
- **Error handling** - Comprehensive error messages and troubleshooting
- **Multi-pool support** - Works with all DetoxHook pools (0.3% and 0.05% fee tiers)

### Example Output

```bash
$ python provide_liquidity.py 0x5e6967b5... --env-wallet --usdc-amount 1 --dry-run

💧 Liquidity Provision Report
==================================================
🎯 SIMULATION MODE - No transaction sent

🏊 Pool: 0x5e6967b5ca922f...
📄 Description: ETH/USDC 0.3% fee pool (~2500 USDC/ETH)
👤 Wallet: 0x00cA5716A51f8E48055d03fCadE8CFE0A463Bab6
💎 ETH Amount: 0.000400 ETH
💵 USDC Amount: 1.000000 USDC
📏 Tick Range: -600 to 600

💰 Current Balances:
   ETH: 0.513759 ETH
   USDC: 14.000000 USDC

✅ Validation:
   Sufficient ETH: ✅
   Sufficient USDC: ✅
   USDC Approved: ❌
```

## 📝 Requirements

### For Environment Loader (`load_env.py`)
- **Python 3.6+** (uses pathlib and type hints)
- **No external dependencies** (uses only standard library)
- **Compatible with all platforms** (Windows, macOS, Linux)

### For Balance Checker (`check_balances.py`)
- **Python 3.6+** (uses pathlib and type hints)
- **web3.py** - Install with `pip install web3`
- **Internet connection** - For Arbitrum Sepolia RPC access

### Installation
```bash
# Install dependencies
pip install -r requirements.txt

# Or install web3 directly
pip install web3
```

---

**🛡️ Security First**: This script is designed with security in mind and will never expose your private keys or sensitive data in logs or output. 