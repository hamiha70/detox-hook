#!/usr/bin/env python3
"""
Pool Information Checker

This script checks the current state of the pool before providing liquidity.
"""

import os
import sys
from web3 import Web3

# Configuration
ARBITRUM_SEPOLIA_RPC_URL = "https://sepolia-rollup.arbitrum.io/rpc"
POOL_MANAGER_ADDRESS = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"

# Pool configuration  
POOL_KEY = {
    "currency0": "0x0000000000000000000000000000000000000000",  # ETH
    "currency1": "0x9D5A68fDFEcc14683324640D5e835936422a47b1",  # MockUSDC
    "fee": 500,
    "tickSpacing": 60,
    "hooks": "0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"
}

# Simple PoolManager ABI for checking pool state
POOL_MANAGER_ABI = [
    {
        "inputs": [{"name": "id", "type": "bytes32"}],
        "name": "getSlot0",
        "outputs": [
            {"name": "sqrtPriceX96", "type": "uint160"},
            {"name": "tick", "type": "int24"},
            {"name": "protocolFee", "type": "uint24"},
            {"name": "lpFee", "type": "uint24"}
        ],
        "stateMutability": "view",
        "type": "function"
    }
]

def connect_to_network():
    """Connect to Arbitrum Sepolia"""
    try:
        w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC_URL))
        if not w3.is_connected():
            raise Exception("Failed to connect to RPC")
        print(f"✅ Connected to Arbitrum Sepolia")
        return w3
    except Exception as e:
        print(f"❌ Failed to connect: {e}")
        return None

def get_pool_id():
    """Calculate pool ID from pool key"""
    from eth_utils import keccak
    import struct
    
    # Encode pool key components
    currency0 = bytes.fromhex(POOL_KEY["currency0"][2:])  # Remove 0x
    currency1 = bytes.fromhex(POOL_KEY["currency1"][2:])  # Remove 0x
    fee = struct.pack(">I", POOL_KEY["fee"])[-3:]  # uint24, take last 3 bytes
    tick_spacing = struct.pack(">i", POOL_KEY["tickSpacing"])[-3:]  # int24, take last 3 bytes  
    hooks = bytes.fromhex(POOL_KEY["hooks"][2:])  # Remove 0x
    
    # Concatenate all components
    encoded = currency0 + currency1 + fee + tick_spacing + hooks
    
    # Hash to get pool ID
    pool_id = keccak(encoded)
    return pool_id.hex()

def check_pool_state(w3):
    """Check the current state of the pool"""
    try:
        pool_manager = w3.eth.contract(address=POOL_MANAGER_ADDRESS, abi=POOL_MANAGER_ABI)
        
        # Get pool ID
        pool_id = get_pool_id()
        print(f"🔍 Pool ID: 0x{pool_id}")
        
        # Get pool state
        try:
            slot0 = pool_manager.functions.getSlot0(f"0x{pool_id}").call()
            sqrt_price_x96, current_tick, protocol_fee, lp_fee = slot0
            
            print(f"✅ Pool State:")
            print(f"   sqrt_price_x96: {sqrt_price_x96}")
            print(f"   Current Tick: {current_tick}")
            print(f"   Protocol Fee: {protocol_fee}")
            print(f"   LP Fee: {lp_fee}")
            
            # Calculate suggested tick range
            tick_spacing = POOL_KEY["tickSpacing"]
            lower_tick = ((current_tick // tick_spacing) - 100) * tick_spacing
            upper_tick = ((current_tick // tick_spacing) + 100) * tick_spacing
            
            print(f"💡 Suggested Tick Range:")
            print(f"   Lower Tick: {lower_tick}")
            print(f"   Upper Tick: {upper_tick}")
            print(f"   Current Tick: {current_tick}")
            
            return True
            
        except Exception as e:
            print(f"❌ Pool may not be initialized: {e}")
            print("💡 This pool might not exist or be initialized yet")
            return False
            
    except Exception as e:
        print(f"❌ Failed to check pool state: {e}")
        return False

def main():
    """Main function"""
    print("🔍 Pool Information Checker")
    print("=" * 40)
    
    # Connect to network
    w3 = connect_to_network()
    if not w3:
        return False
    
    # Display pool configuration
    print(f"\n📋 Pool Configuration:")
    print(f"   Currency0 (ETH): {POOL_KEY['currency0']}")
    print(f"   Currency1 (MockUSDC): {POOL_KEY['currency1']}")
    print(f"   Fee: {POOL_KEY['fee']}")
    print(f"   Tick Spacing: {POOL_KEY['tickSpacing']}")
    print(f"   Hooks: {POOL_KEY['hooks']}")
    
    # Check pool state
    print(f"\n🔍 Checking Pool State...")
    success = check_pool_state(w3)
    
    if success:
        print(f"\n✅ Pool is initialized and ready for liquidity provision!")
    else:
        print(f"\n❌ Pool issues detected. Check the pool configuration.")
    
    return success

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1) 