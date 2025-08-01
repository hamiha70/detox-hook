#!/usr/bin/env python3
"""
Debug script for pool_view.py
=============================

This script helps debug issues with the pool_view.py script
by testing different components step by step.
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

def test_rpc_connection(rpc_url: str):
    """Test RPC connection."""
    print(f"🔍 Testing RPC connection to: {rpc_url}")
    
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        if not w3.is_connected():
            print("❌ Failed to connect to RPC")
            return False
        
        # Get latest block
        latest_block = w3.eth.block_number
        print(f"✅ Connected! Latest block: {latest_block}")
        
        # Get chain ID
        chain_id = w3.eth.chain_id
        print(f"✅ Chain ID: {chain_id}")
        
        return True
        
    except Exception as e:
        print(f"❌ RPC connection failed: {e}")
        return False

def test_contract_deployment(contract_address: str, rpc_url: str):
    """Test if the PoolStateViewer contract is deployed."""
    print(f"\n🔍 Testing contract deployment at: {contract_address}")
    
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        # Check if contract has code
        code = w3.eth.get_code(contract_address)
        
        if code == b'':
            print("❌ No contract code found at address")
            return False
        
        print(f"✅ Contract has code (length: {len(code)} bytes)")
        
        # Get contract balance
        balance = w3.eth.get_balance(contract_address)
        print(f"✅ Contract balance: {w3.from_wei(balance, 'ether')} ETH")
        
        return True
        
    except Exception as e:
        print(f"❌ Contract check failed: {e}")
        return False

def test_pool_manager(pool_manager_address: str, rpc_url: str):
    """Test if the PoolManager contract is accessible."""
    print(f"\n🔍 Testing PoolManager at: {pool_manager_address}")
    
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        # Check if PoolManager has code
        code = w3.eth.get_code(pool_manager_address)
        
        if code == b'':
            print("❌ No PoolManager code found at address")
            return False
        
        print(f"✅ PoolManager has code (length: {len(code)} bytes)")
        
        return True
        
    except Exception as e:
        print(f"❌ PoolManager check failed: {e}")
        return False

def test_pool_state_viewer_call(contract_address: str, rpc_url: str, pool_id: str):
    """Test a direct call to the PoolStateViewer contract."""
    print(f"\n🔍 Testing PoolStateViewer call for pool: {pool_id}")
    
    # Minimal ABI for testing
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
        
        # Call the function
        result = contract.functions.getPoolStateById(pool_id).call()
        
        sqrt_price_x96, tick, protocol_fee, lp_fee, liquidity, success = result
        
        print(f"✅ Function call successful!")
        print(f"   Success: {success}")
        print(f"   SqrtPriceX96: {sqrt_price_x96}")
        print(f"   Tick: {tick}")
        print(f"   Protocol Fee: {protocol_fee}")
        print(f"   LP Fee: {lp_fee}")
        print(f"   Liquidity: {liquidity}")
        
        if success:
            # Calculate price
            sqrt_price_decimal = float(sqrt_price_x96) / (2**96)
            price = sqrt_price_decimal ** 2
            print(f"   Calculated Price: {price:.8f}")
        
        return success
        
    except Exception as e:
        print(f"❌ Function call failed: {e}")
        return False

def test_known_pool_ids():
    """Test with known pool IDs from the project."""
    print(f"\n🔍 Testing with known pool IDs")
    
    # Pool IDs from the project (you can add more)
    known_pools = [
        "0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f",  # Pool 1
        "0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa",  # Your test pool
    ]
    
    return known_pools

def main():
    """Main debug function."""
    print("🔧 Pool State Viewer Debug Script")
    print("=" * 50)
    
    # Get RPC URL
    rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
    if not rpc_url:
        print("❌ ARBITRUM_SEPOLIA_RPC_URL not set")
        print("💡 Set it with: export ARBITRUM_SEPOLIA_RPC_URL=https://sepolia-rollup.arbitrum.io/rpc")
        return
    
    print(f"🌐 Using RPC URL: {rpc_url}")
    
    # Contract addresses
    pool_state_viewer_address = "0xD87870729fe0efB97be17FD5735513782c33Db56"
    pool_manager_address = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"
    
    # Test RPC connection
    if not test_rpc_connection(rpc_url):
        print("❌ RPC connection failed. Check your RPC URL.")
        return
    
    # Test contract deployment
    if not test_contract_deployment(pool_state_viewer_address, rpc_url):
        print("❌ PoolStateViewer contract not deployed. Deploy it first.")
        return
    
    # Test PoolManager
    if not test_pool_manager(pool_manager_address, rpc_url):
        print("❌ PoolManager not accessible. Check the address.")
        return
    
    # Test with different pool IDs
    known_pools = test_known_pool_ids()
    
    for pool_id in known_pools:
        print(f"\n🧪 Testing pool ID: {pool_id}")
        success = test_pool_state_viewer_call(pool_state_viewer_address, rpc_url, pool_id)
        
        if success:
            print(f"✅ Pool {pool_id} is working!")
        else:
            print(f"❌ Pool {pool_id} failed")
    
    print(f"\n✅ Debug completed!")

if __name__ == '__main__':
    main() 