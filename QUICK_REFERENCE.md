# 🚀 DetoxHook Quick Reference

## ⚡ Essential Commands (run from ROOT)

```bash
# Development
yarn dev                 # Start frontend
yarn test:detox         # Test DetoxHook
yarn test:fork          # Test on Arbitrum Sepolia fork
yarn deploy:arbitrum    # Deploy to testnet
yarn generate:contracts # Update frontend ABIs

# Full cycle after changes
yarn compile && yarn test:detox && yarn test:fork
```

## 🔧 Common Issues & Fixes

### ❌ "command not found"
```bash
# ✅ Fix: Add 'yarn' prefix
yarn test:fork          # ✅ Correct
test:fork              # ❌ Wrong
```

### ❌ "Couldn't find a script named 'dev'"
```bash
# ✅ Fix: Run from project ROOT, not packages/foundry
cd /path/to/detox-hook  # Go to root
yarn dev               # ✅ Works
```

### ❌ "Keystore file does not exist"
```bash
# ✅ Fix: Set up .env with private key
cd packages/foundry
cp env.example .env
# Edit .env: DEPLOYMENT_PRIVATE_KEY=0x...
```

### ❌ "No contracts found" in frontend
```bash
# ✅ Fix: Generate contracts
yarn generate:contracts
```

### ❌ Fork tests failing
```bash
# ✅ Expected: RPC issues are normal
# Focus on local tests: yarn test:detox
```

## 📁 Directory Context

```
detox-hook/                 ← ROOT (run most commands here)
├── packages/
│   ├── foundry/           ← Smart contracts
│   └── nextjs/            ← Frontend
└── package.json           ← Main scripts
```

## 🎯 Test Results Summary

- ✅ **25/25 local tests** passing
- ✅ **8/8 fork tests** passing (when RPC works)
- ✅ **4/4 HookMiner tests** passing
- ✅ **Total: 37/37 tests** when all working

## 🌐 Deployed Contract

- **Network**: Arbitrum Sepolia (421614)
- **Address**: `0xadc387b56f58d9f5b486bb7575bf3b5ea5898088`
- **Explorer**: [Blockscout](https://arbitrum-sepolia.blockscout.com/address/0xadc387b56f58d9f5b486bb7575bf3b5ea5898088)

## 📖 Full Documentation

- [DEVELOPMENT.md](./DEVELOPMENT.md) - Complete guide
- [README.md](./README.md) - Project overview
- [HOOKMINER_INTEGRATION.md](./packages/foundry/HOOKMINER_INTEGRATION.md) - Technical details 