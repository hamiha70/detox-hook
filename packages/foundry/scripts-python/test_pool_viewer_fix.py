#!/usr/bin/env python3
"""
Test script to verify PoolStateViewer fix
=========================================

This script tests if the PoolStateViewer contract works correctly
after the fix to use StateLibrary functions.
"""

import sys
import os
from pathlib import Path

# Add parent directory to path for imports
sys.path.append(str(Path(__file__).parent))

try:
    from web3 import Web3
    from web3.contract import Contract
    WEB3_AVAILABLE = True
except ImportError:
    WEB3_AVAILABLE = False
    print("❌ Web3 not available. Install with: pip install web3")
    sys.exit(1)

def test_pool_state_viewer():
    """Test the PoolStateViewer contract with known pool IDs."""
    
    # Get RPC URL
    rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
    if not rpc_url:
        print("❌ ARBITRUM_SEPOLIA_RPC_URL not set")
        return
    
    # Contract address (old deployment - will need to be redeployed)
    contract_address = "0xD87870729fe0efB97be17FD5735513782c33Db56"
    
    # ABI for testing
    abi = [
        {
            "inputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
            "name": "getPoolStateById",
            "outputs": [
                {"internalType": "uint160", "name": "sqrtPriceX96", "type": "uint160"},
                {"internalType": "int24", "name": "tick", "type": "int24"},
                {"internalType": "uint24", "name": "protocolFee", "type": "uint24"},
                {"internalType": "uint24", "name": "lpFee", "type": "uint24"},
                {"internalType": "uint128", "name": "liquidity", "type": "uint128"},
                {"internalType": "bool", "name": "success", "type": "bool"}
            ],
            "stateMutability": "view",
            "type": "function"
        }
    ]
    
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        contract = w3.eth.contract(address=contract_address, abi=abi)
        
        # Test with known pool IDs
        test_pools = [
            "0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f",  # Pool 1
            "0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa",  # Your test pool
        ]
        
        print("🧪 Testing PoolStateViewer contract...")
        print("=" * 50)
        
        for pool_id in test_pools:
            print(f"\n📋 Testing pool: {pool_id}")
            
            try:
                result = contract.functions.getPoolStateById(pool_id).call()
                sqrt_price_x96, tick, protocol_fee, lp_fee, liquidity, success = result
                
                if success:
                    print(f"✅ Pool state retrieved successfully!")
                    print(f"   SqrtPriceX96: {sqrt_price_x96}")
                    print(f"   Tick: {tick}")
                    print(f"   Protocol Fee: {protocol_fee}")
                    print(f"   LP Fee: {lp_fee}")
                    print(f"   Liquidity: {liquidity}")
                    
                    # Calculate price
                    sqrt_price_decimal = float(sqrt_price_x96) / (2**96)
                    price = sqrt_price_decimal ** 2
                    print(f"   Calculated Price: {price:.8f}")
                else:
                    print(f"❌ Pool state retrieval failed (success = false)")
                    
            except Exception as e:
                print(f"❌ Function call failed: {e}")
                print(f"   This indicates the contract needs to be redeployed with the fix")
        
        print(f"\n💡 Solution: Redeploy the PoolStateViewer contract with the fixed code")
        print(f"   Command: forge script script/DeployPoolStateViewer.s.sol:DeployPoolStateViewer --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --private-key $DEPLOYMENT_PRIVATE_KEY --broadcast --chain 421614")
        
    except Exception as e:
        print(f"❌ Error: {e}")

def main():
    """Main function."""
    print("🔧 PoolStateViewer Fix Test")
    print("=" * 50)
    
    if not WEB3_AVAILABLE:
        print("❌ Web3 library is required")
        return
    
    test_pool_state_viewer()

if __name__ == '__main__':
    main() 