# HookMiner Integration for DetoxHook

## Overview

This document explains how we've integrated the official `HookMiner` utility from Uniswap V4 Periphery to ensure proper hook deployment with correct permission flags.

## What is HookMiner?

`HookMiner` is a utility library in `@v4-periphery/src/utils/HookMiner.sol` that helps find the correct salt for CREATE2 deployment to ensure hook addresses have the required permission flags in their bottom 14 bits.

## Why HookMiner is Required

Uniswap V4 hooks must have specific permission flags encoded in the bottom 14 bits of their address. For DetoxHook, we need:
- `BEFORE_SWAP_FLAG` (128)
- `BEFORE_SWAP_RETURNS_DELTA_FLAG` (8)
- Combined: 136

Without proper address mining, the hook deployment would fail during pool initialization.

## Integration Details

### 1. Import and Constants

```solidity
import {HookMiner} from "@v4-periphery/src/utils/HookMiner.sol";

// CREATE2 Deployer Proxy (universal across all chains)
address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

// Hook permission flags
uint160 constant HOOK_FLAGS = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
```

### 2. Salt Mining Process

```solidity
// Prepare creation code and constructor arguments
bytes memory creationCode = type(DetoxHook).creationCode;
bytes memory constructorArgs = abi.encode(IPoolManager(poolManager));

// Mine the salt using HookMiner
(address expectedAddress, bytes32 salt) = HookMiner.find(
    CREATE2_DEPLOYER, 
    HOOK_FLAGS, 
    creationCode, 
    constructorArgs
);
```

### 3. CREATE2 Deployment

```solidity
// Deploy using CREATE2 Deployer Proxy
bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
bytes memory callData = abi.encodePacked(salt, deploymentData);

(bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
require(success, "CREATE2 deployment failed");

address deployedAddress = address(bytes20(returnData));
DetoxHook hook = DetoxHook(deployedAddress);
```

## Implementation Files

### 1. Deployment Script: `DeployDetoxHook.s.sol`
- Uses HookMiner for production deployments
- Supports multiple networks via ChainAddresses
- Comprehensive validation and logging

### 2. Test Suite: `DetoxHookArbitrumSepoliaFork.t.sol`
- Forks Arbitrum Sepolia for realistic testing
- Uses HookMiner for proper hook deployment
- Tests full functionality with real V4 contracts

### 3. HookMiner Tests: `HookMinerTest.t.sol`
- Validates HookMiner functionality
- Tests consistency between `find()` and `computeAddress()`
- Verifies flag mask operations

## Key Benefits

1. **Correct Address Generation**: Ensures hook addresses have required permission flags
2. **Universal Compatibility**: Works across all networks using CREATE2 Deployer Proxy
3. **Deterministic Deployment**: Same salt produces same address across networks
4. **Production Ready**: Follows Uniswap V4 best practices

## Test Results

All test suites pass with HookMiner integration:

- **DetoxHook.t.sol**: 8/8 tests passed (basic hook functionality)
- **DetoxHookArbitrumSepoliaFork.t.sol**: 8/8 tests passed (forked network testing)
- **HookMinerTest.t.sol**: 4/4 tests passed (HookMiner validation)
- **DetoxHookLive.t.sol**: 7/7 tests passed (live network verification)

## Example Output

```
=== HookMiner Results ===
Salt found: 41943
Expected hook address: 0x3Cc3D4de1334eE22892f4E84A5B5955714A38088
Address flags: 136
Required flags: 136
Flags match: true
```

## References

- [HookMiner Source](https://github.com/Uniswap/v4-periphery/blob/main/src/utils/HookMiner.sol)
- [v4-sepolia-deploy Example](https://github.com/haardikk21/v4-sepolia-deploy)
- [CREATE2 Deployer Proxy](https://github.com/Arachnid/deterministic-deployment-proxy)

## Next Steps

With HookMiner properly integrated, the DetoxHook is ready for:
1. Production deployment to Arbitrum Sepolia
2. Integration with frontend applications
3. Extension with arbitrage detection logic
4. MEV capture functionality implementation 