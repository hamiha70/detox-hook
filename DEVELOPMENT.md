# DetoxHook Development Guide

## 🚀 Initial Setup

### 1. Environment Configuration
```bash
# Copy environment template
cd packages/foundry
cp env.example .env

# Edit .env with your private keys
# For testnet deployment, set:
# DEPLOYMENT_PRIVATE_KEY=0x...your_private_key...
# ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
```

### 2. Install Dependencies
```bash
# From project root
yarn install
```

### 3. Verify Setup
```bash
# From project root
yarn compile
yarn test:detox
```

## Quick Start Commands

### 🚀 Most Common Workflows

```bash
# Start development (frontend + hot reload) - FROM ROOT
yarn dev

# Run all tests - FROM ROOT OR packages/foundry
yarn test

# Deploy DetoxHook to Arbitrum Sepolia - FROM ROOT
yarn deploy:arbitrum

# Generate contracts for frontend after deployment - FROM ROOT
yarn generate:contracts

# Test specific components - FROM ROOT
yarn test:detox          # DetoxHook tests
yarn test:fork           # Arbitrum Sepolia fork tests  
yarn test:hookminer      # HookMiner integration tests
```

### 🔧 Development Workflow

1. **Make changes** to DetoxHook contract
2. **Test locally**: `yarn test:detox` (from root)
3. **Test on fork**: `yarn test:fork` (from root)
4. **Deploy**: `yarn deploy:arbitrum` (from root)
5. **Generate contracts**: `yarn generate:contracts` (from root)
6. **Start frontend**: `yarn dev` (from root)

### 📋 All Available Commands

#### Frontend (run from ROOT)
```bash
yarn dev                 # Start NextJS dev server
yarn start              # Alias for dev
yarn next:build         # Build for production
yarn next:lint          # Lint frontend code
yarn next:format        # Format frontend code
```

#### Smart Contracts (run from ROOT)
```bash
yarn compile            # Compile contracts
yarn test               # Run all tests
yarn deploy:detox       # Deploy DetoxHook (generic)
yarn deploy:arbitrum    # Deploy to Arbitrum Sepolia
yarn generate:contracts # Generate TypeScript ABIs
yarn verify             # Verify contracts on block explorer
```

#### Testing (run from ROOT)
```bash
yarn test                    # All tests
yarn test:detox             # DetoxHook basic tests
yarn test:fork              # Arbitrum Sepolia fork tests
yarn test:hookminer         # HookMiner integration tests
yarn foundry:test           # Direct foundry test access
```

#### Utilities (run from ROOT)
```bash
yarn format             # Format all code
yarn lint               # Lint all code
yarn account:generate   # Generate new account
yarn chain              # Start local chain
yarn fork               # Fork mainnet locally
```

### 🎯 DetoxHook Specific

#### After Contract Changes
```bash
# Full development cycle (from ROOT)
yarn compile && yarn test:detox && yarn test:fork
```

#### After Deployment
```bash
# Update frontend with new contracts (from ROOT)
yarn generate:contracts && yarn dev
```

#### Debug Deployment Issues
```bash
# Check deployment on Arbitrum Sepolia (from ROOT)
yarn workspace @se-2/foundry test --match-contract DetoxHookLive -vv
```

### 🌐 Network Configuration

- **Local**: Anvil (default)
- **Testnet**: Arbitrum Sepolia (421614)
- **Frontend**: Auto-detects network and shows contracts

### 📁 Key Files

- `packages/foundry/contracts/DetoxHook.sol` - Main contract
- `packages/foundry/script/DeployToArbitrumSepolia.s.sol` - Deployment script
- `packages/nextjs/contracts/deployedContracts.ts` - Generated contract ABIs
- `packages/foundry/test/DetoxHook*.t.sol` - Test suites

### 🔍 Troubleshooting

#### "No contracts found" in frontend
```bash
# From ROOT
yarn generate:contracts
```

#### Tests failing
```bash
# From ROOT
yarn foundry:clean && yarn compile && yarn test
```

#### Deployment issues
```bash
# Check your .env file has DEPLOYMENT_PRIVATE_KEY set
# Ensure you have ETH on Arbitrum Sepolia
yarn account:reveal-pk  # Show your address

# If keystore errors, make sure you're using private key deployment:
# Edit packages/foundry/.env and set DEPLOYMENT_PRIVATE_KEY=0x...
```

#### Wrong directory errors
```bash
# Most commands should be run from PROJECT ROOT, not packages/foundry
cd /path/to/detox-hook  # Go to project root
yarn dev                # ✅ Correct
# NOT: cd packages/foundry && yarn dev  # ❌ Wrong
```

#### Command typos
```bash
# ✅ Correct
yarn test:fork

# ❌ Wrong (missing yarn)
test:fork
```

## Why Yarn > Make?

- ✅ **Cross-platform** (Windows, Mac, Linux)
- ✅ **Monorepo aware** (workspace orchestration)
- ✅ **Consistent** with Scaffold-ETH patterns
- ✅ **No additional tooling** required
- ✅ **IDE integration** (package.json scripts)
- ✅ **Dependency management** built-in 