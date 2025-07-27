#!/bin/bash

# DetoxHook Deployment Verification Script
# Usage: ./verify-deployment.sh [CHAIN_ID] [RPC_URL]

set -e

# Default to Arbitrum Sepolia if no arguments provided
CHAIN_ID=${1:-421614}
RPC_URL=${2:-$RPC_URL_421614}

# Check if RPC_URL is set
if [ -z "$RPC_URL" ]; then
    echo "❌ Error: RPC_URL is not set"
    echo "   Please provide RPC_URL as second argument or set RPC_URL_421614 environment variable"
    echo "   Usage: ./verify-deployment.sh 421614 https://sepolia-rollup.arbitrum.io/rpc"
    exit 1
fi

# Deployment addresses from your successful deployment
DETOX_HOOK="0xB7d53527Fd072ea45e15FC09101Eb379D3778088"
PRICE_REGISTRY="0x927a871865B739ae9844EA83fC4163a487DB17Fe"
SWAP_ROUTER="0xAaFd63797e2Eaedc2b59386B21ed30e2501A78F1"
MOCK_USDC="0x6c00492dF8fcaE1309C7A60CcdeB2E4ECe587Aba"

echo "=== DETOXHOOK DEPLOYMENT VERIFICATION ==="
echo "Chain ID: $CHAIN_ID"
echo "RPC URL: $RPC_URL"
echo ""

echo "=== CHECKING CONTRACT CODE SIZES ==="

# Function to check contract code size
check_contract() {
    local name=$1
    local address=$2
    
    echo -n "Checking $name ($address)... "
    
    # Get code size using cast (fixed command)
    local code_size=$(cast codesize $address --rpc-url $RPC_URL 2>/dev/null)
    
    if [ -n "$code_size" ] && [ "$code_size" -gt 0 ]; then
        echo "[PASS] Code size: $code_size bytes"
        return 0
    else
        echo "[FAIL] No code found"
        return 1
    fi
}

# Check all contracts
check_contract "DetoxHook" $DETOX_HOOK
check_contract "PriceRegistry" $PRICE_REGISTRY  
check_contract "SwapRouterFixed" $SWAP_ROUTER
check_contract "MockUSDC" $MOCK_USDC

echo ""
echo "=== CHECKING CONTRACT FUNCTIONALITY ==="

# Check DetoxHook functions
echo -n "Checking DetoxHook.poolManager()... "
POOL_MANAGER=$(cast call $DETOX_HOOK "poolManager()" --rpc-url $RPC_URL 2>/dev/null)
if [ -n "$POOL_MANAGER" ] && [ "$POOL_MANAGER" != "0x" ]; then
    echo "[PASS] PoolManager: $POOL_MANAGER"
else
    echo "[FAIL] Cannot read poolManager"
fi

# Check PriceRegistry owner
echo -n "Checking PriceRegistry.owner()... "
OWNER=$(cast call $PRICE_REGISTRY "owner()" --rpc-url $RPC_URL 2>/dev/null)
if [ -n "$OWNER" ] && [ "$OWNER" != "0x" ]; then
    echo "[PASS] Owner: $OWNER"
else
    echo "[FAIL] Cannot read owner"
fi

# Check MockUSDC symbol
echo -n "Checking MockUSDC.symbol()... "
SYMBOL=$(cast call $MOCK_USDC "symbol()" --rpc-url $RPC_URL 2>/dev/null)
if [ -n "$SYMBOL" ] && [ "$SYMBOL" != "0x" ]; then
    # Convert hex to string
    SYMBOL_STR=$(cast --to-ascii $SYMBOL 2>/dev/null || echo "USDC")
    echo "[PASS] Symbol: $SYMBOL_STR"
else
    echo "[FAIL] Cannot read symbol"
fi

echo ""
echo "=== CHECKING HOOK FLAGS ==="

# Extract address flags (last 20 bits)
HOOK_ADDRESS_INT=$(cast --to-dec $DETOX_HOOK 2>/dev/null)
if [ -n "$HOOK_ADDRESS_INT" ]; then
    HOOK_FLAGS=$((HOOK_ADDRESS_INT & 1048575)) # 0xFFFFF = 1048575
    EXPECTED_FLAGS=136

    echo "Hook address flags: $HOOK_FLAGS"
    echo "Expected flags: $EXPECTED_FLAGS"

    if [ "$HOOK_FLAGS" -eq "$EXPECTED_FLAGS" ]; then
        echo "[PASS] Hook flags match expected values"
    else
        echo "[FAIL] Hook flags do not match"
    fi
else
    echo "[ERROR] Could not convert hook address to integer"
fi

echo ""
echo "=== BLOCK EXPLORER LINKS ==="
case $CHAIN_ID in
    421614)
        EXPLORER="https://arbitrum-sepolia.blockscout.com"
        ;;
    1301)
        EXPLORER="https://unichain-sepolia.blockscout.com"
        ;;
    *)
        EXPLORER="https://etherscan.io"
        ;;
esac

echo "DetoxHook: $EXPLORER/address/$DETOX_HOOK"
echo "PriceRegistry: $EXPLORER/address/$PRICE_REGISTRY"
echo "SwapRouterFixed: $EXPLORER/address/$SWAP_ROUTER"
echo "MockUSDC: $EXPLORER/address/$MOCK_USDC"

echo ""
echo "=== BROADCAST FILE CHECK ==="
BROADCAST_FILE="broadcast/DeployDetoxHookComplete.s.sol/$CHAIN_ID/run-latest.json"

if [ -f "$BROADCAST_FILE" ]; then
    echo "[PASS] Broadcast file exists: $BROADCAST_FILE"
    
    # Extract transaction count
    TX_COUNT=$(jq '.transactions | length' $BROADCAST_FILE 2>/dev/null || echo "0")
    echo "Transactions in broadcast: $TX_COUNT"
    
    # Check for successful transactions
    if [ "$TX_COUNT" -gt 0 ]; then
        echo "[PASS] Deployment transactions recorded"
    else
        echo "[WARNING] No transactions found in broadcast file"
    fi
else
    echo "[WARNING] Broadcast file not found: $BROADCAST_FILE"
fi

echo ""
echo "=== VERIFICATION COMPLETE ==="
echo "If all checks show [PASS], your DetoxHook deployment is successful!"
echo ""
echo "Next steps:"
echo "1. Test swaps using the SwapRouterFixed"
echo "2. Monitor hook arbitrage capture"
echo "3. Verify contracts on block explorer if needed" 