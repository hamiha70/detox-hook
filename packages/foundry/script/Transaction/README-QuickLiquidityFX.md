# QuickLiquidityFX.s.sol - Uniswap V4 Liquidity Provision Test Script

## 📋 Overview

`QuickLiquidityFX.s.sol` is a comprehensive Foundry script designed to test liquidity provision on a Uniswap V4 liquidity pool with **MockEURC** and **MockUSDC** assets, featuring the **DetoxHook** for MEV protection.

## 🎯 Objective

This script validates and tests the complete liquidity provision setup by performing:

1. **Pool Specification** validation
2. **Network and Contract Safety Validations** 
3. **Pool State Analysis**
4. **Liquidity Provider Verification**

## 🔧 Script Requirements

### Environment Variables
```bash
# Required for liquidity provider verification
LIQUIDITY_PROVIDER_WALLET=0x...        # Liquidity provider wallet address
LIQUIDITY_PROVIDER_PRIVATE_KEY=0x...    # Private key (for actual transactions)
```

### Network Requirements
- **Network**: Arbitrum Sepolia (Chain ID: 421614)
- **RPC URL**: Must be connected to Arbitrum Sepolia testnet

## 📊 Pool Specification

The script tests the following pool configuration:

| Parameter | Value | Description |
|-----------|--------|-------------|
| **Currency0** | MockEURC (`0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E`) | First token in the pair |
| **Currency1** | MockUSDC (`0x9D5A68fDFEcc14683324640D5e835936422a47b1`) | Second token in the pair |
| **Fee Tier** | 0.02% (2000) | Pool fee percentage |
| **Tick Spacing** | 40 | Minimum tick spacing for positions |
| **Hooks** | DetoxHook (`0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088`) | MEV protection hook |

### Liquidity Parameters
| Parameter | Value | Description |
|-----------|--------|-------------|
| **Tick Lower** | -1640 | Lower bound of liquidity position |
| **Tick Upper** | -1480 | Upper bound of liquidity position |
| **Liquidity Delta** | 1e18 | Amount of liquidity to add (1,000,000,000,000,000,000) |
| **Salt** | 0x00...01 | Unique position identifier |

## 🚀 Usage

### Basic Execution (Validation Only)
```bash
# Run validation and pool state analysis
forge script script/Transaction/QuickLiquidityFX.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $LIQUIDITY_PROVIDER_PRIVATE_KEY \
    -vvv
```

### With Broadcasting (Actual Liquidity Provision)
```bash
# Add --broadcast flag for actual transactions
forge script script/Transaction/QuickLiquidityFX.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $LIQUIDITY_PROVIDER_PRIVATE_KEY \
    --broadcast \
    -vvv
```

### Using Environment File
```bash
# Load environment variables from .env file
source .env
forge script script/Transaction/QuickLiquidityFX.s.sol \
    --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
    --private-key $LIQUIDITY_PROVIDER_PRIVATE_KEY \
    -vvv
```

## 📋 Validation Checklist

### ✅ 1. Network and Contract Safety Validations

**Network Check:**
- ✅ Verify `block.chainId == 421614` (Arbitrum Sepolia)

**Contract Existence:**
- ✅ MockEURC contract deployed and verified
- ✅ MockUSDC contract deployed and verified  
- ✅ LiquidityRouter contract deployed and verified
- ✅ PoolManager contract deployed and verified
- ✅ PoolModifyLiquidityTest contract deployed and verified
- ✅ DetoxHook contract deployed and verified

### ✅ 2. Pool Specification

**PoolKey Configuration:**
- ✅ Currency0: MockEURC address correct
- ✅ Currency1: MockUSDC address correct
- ✅ Fee: 0.02% (2000) configured
- ✅ Tick Spacing: 40 set correctly
- ✅ Hooks: DetoxHook address correct
- ✅ Pool ID calculated and displayed

**Tick Alignment:**
- ✅ Tick Lower (-1640) aligned with tick spacing (40)
- ✅ Tick Upper (-1480) aligned with tick spacing (40)
- ✅ Valid tick range (Lower < Upper)

### ✅ 3. Pool State

**Current State Analysis:**
- ✅ Fetch current price (sqrtPriceX96)
- ✅ Display current tick
- ✅ Show protocol and LP fees
- ✅ Verify tick alignment with pool tick spacing
- ✅ Get liquidity at current tick
- ✅ Handle uninitialized pool gracefully

### ✅ 4. Liquidity Provider Verification

**Wallet Validation:**
- ✅ Verify `LIQUIDITY_PROVIDER_WALLET` environment variable set
- ✅ Validate wallet address is not zero address

**Balance Verification:**
- ✅ Fetch ETH balance (for gas and potential liquidity)
- ✅ Fetch MockEURC balance
- ✅ Fetch MockUSDC balance
- ✅ Validate sufficient balances for liquidity provision

## 📊 Expected Output

### Successful Validation Output
```
=== QuickLiquidityFX - Uniswap V4 Liquidity Provision Test ===
Script: QuickLiquidityFX.s.sol
Network: Arbitrum Sepolia
Chain ID: 421614

=== 1. Network and Contract Safety Validations ===
[PASS] Network check: Arbitrum Sepolia confirmed

Contract existence validation:
  [PASS] MockEURC at: 0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E
  [PASS] MockUSDC at: 0x9D5A68fDFEcc14683324640D5e835936422a47b1
  [PASS] LiquidityRouter at: 0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a
  [PASS] PoolManager at: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
  [PASS] PoolModifyLiquidityTest at: 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7
  [PASS] DetoxHook at: 0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088
[PASS] All contract addresses contain deployed code

=== 2. Pool Specification ===
PoolKey configuration:
  Currency0 (MockEURC): 0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E
  Currency1 (MockUSDC): 0x9D5A68fDFEcc14683324640D5e835936422a47b1
  Fee tier: 0.02% ( 2000 )
  Tick spacing: 40
  Hooks (DetoxHook): 0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088
  Pool ID: 0x...

Liquidity parameters:
  Tick Lower: -1640
  Tick Upper: -1480
  Liquidity Delta: 1000000000000000000
  Salt: 0x0000000000000000000000000000000000000000000000000000000000000001

Tick alignment verification:
  Tick lower alignment: VALID
  Tick upper alignment: VALID
  Tick range validity: VALID
[PASS] Tick alignment verification successful

=== 3. Pool State ===
Pool state fetched successfully:
  Current price (sqrtPriceX96): 79228162514264337593543950336
  Current tick: 0
  Protocol fee: 0
  LP fee: 2000
  Current price (MockEURC per MockUSDC): 1000000000000000000
  Tick alignment: ALIGNED
  Liquidity at current tick: 1000000000000000000

=== 4. Verify Liquidity Provider ===
Liquidity provider wallet: 0x...
Balances for liquidity provider wallet:
  ETH balance: 50000000000000000
  ETH balance (human): 0
  MockEURC balance: 1000000000000000000000
  MockUSDC balance: 1000000000000000000000

Balance validation:
  Sufficient ETH: YES
  Sufficient MockEURC: YES
  Sufficient MockUSDC: YES
[PASS] Liquidity provider has sufficient balances

[SUCCESS] QuickLiquidityFX validation completed successfully!
Pool is ready for liquidity provision operations.
```

## ⚠️ Common Issues and Troubleshooting

### Network Issues
```
NETWORK_ERROR: Must run on Arbitrum Sepolia (421614)
```
**Solution**: Ensure your RPC URL points to Arbitrum Sepolia testnet.

### Contract Not Found
```
MockEURC contract not found at address
```
**Solution**: Verify contract addresses are correct and deployed on Arbitrum Sepolia.

### Environment Variables
```
[ERROR] LIQUIDITY_PROVIDER_WALLET environment variable not set
```
**Solution**: Set required environment variables in your `.env` file.

### Pool State Query Failed
```
[WARNING] Pool state query failed - pool may not be initialized
```
**Solution**: This is expected if the pool hasn't been created yet. Initialize the pool first.

### Insufficient Balances
```
[WARNING] Liquidity provider may have insufficient balances
```
**Solution**: Ensure the liquidity provider wallet has sufficient MockEURC, MockUSDC, and ETH for gas.

## 🔗 Related Scripts

- **`ProvideLiquidityFX.s.sol`** - Actual liquidity provision script
- **`InitializeFXPool_v2.s.sol`** - Pool initialization script
- **`GetPoolState.s.sol`** - Pool state query script

## 📚 Technical Details

### Contract Addresses (Arbitrum Sepolia)
```solidity
address constant LIQUIDITY_ROUTER_ADDRESS = 0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a;
address constant MOCKEURC_ADDRESS = 0x2E4D60D7e25eDd8A0e28Ef1370A7AD0e4E00525E;
address constant MOCKUSDC_ADDRESS = 0x9D5A68fDFEcc14683324640D5e835936422a47b1;
address constant DETOX_HOOK_ADDRESS = 0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088;
address constant POOL_MANAGER_ADDRESS = 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317;
address constant POOL_MODIFY_LIQUIDITY_TEST_ADDRESS = 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7;
```

### Liquidity Delta Explanation
- **Value**: `1e18` (1,000,000,000,000,000,000)
- **Type**: `int256` (positive = add liquidity, negative = remove liquidity)
- **Purpose**: Specifies the amount of liquidity to add to the position
- **Range**: Typical values are `1e15` (small) to `10e18` (large)

## 🛡️ Safety Features

1. **Network Validation**: Ensures script only runs on Arbitrum Sepolia
2. **Contract Existence**: Validates all required contracts are deployed
3. **Tick Alignment**: Verifies tick parameters align with pool tick spacing
4. **Balance Validation**: Checks liquidity provider has sufficient tokens
5. **Graceful Error Handling**: Handles uninitialized pools and failed queries

---

**✅ This script provides comprehensive validation for DetoxHook liquidity provision testing on Uniswap V4.**
