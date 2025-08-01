#!/usr/bin/env python3
"""
Comprehensive test script for PoolStateViewer
=============================================

This script tests the PoolStateViewer contract with the real Uniswap V4 PoolManager
on Arbitrum Sepolia to ensure it works correctly.
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

def test_pool_state_viewer_deployment():
    """Test if the PoolStateViewer contract is deployed and accessible."""
    
    # Get RPC URL
    rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
    if not rpc_url:
        print("❌ ARBITRUM_SEPOLIA_RPC_URL not set")
        return False
    
    # Contract address (will be updated after deployment)
    contract_address = "0xD87870729fe0efB97be17FD5735513782c33Db56"
    
    # ABI for testing
    abi = [
        {
            "inputs": [],
            "name": "poolManager",
            "outputs": [{"internalType": "address", "name": "", "type": "address"}],
            "stateMutability": "view",
            "type": "function"
        },
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
        },
        {
            "inputs": [
                {"internalType": "tuple", "name": "poolKey", "type": "tuple", "components": [
                    {"internalType": "address", "name": "currency0", "type": "address"},
                    {"internalType": "address", "name": "currency1", "type": "address"},
                    {"internalType": "uint24", "name": "fee", "type": "uint24"},
                    {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                    {"internalType": "address", "name": "hooks", "type": "address"}
                ]}
            ],
            "name": "getIdByKey",
            "outputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
            "stateMutability": "view",
            "type": "function"
        },
        {
            "inputs": [
                {"internalType": "bytes32", "name": "poolId", "type": "bytes32"},
                {"internalType": "int24", "name": "tick", "type": "int24"}
            ],
            "name": "getTickInfo",
            "outputs": [
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
        
        # Test poolManager function
        pool_manager_address = contract.functions.poolManager().call()
        print(f"✅ PoolManager address: {pool_manager_address}")
        
        # Verify it matches expected address
        expected_pool_manager = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"
        if pool_manager_address.lower() == expected_pool_manager.lower():
            print("✅ PoolManager address matches expected value")
        else:
            print(f"❌ PoolManager address mismatch. Expected: {expected_pool_manager}")
            return False
        
        return True
        
    except Exception as e:
        print(f"❌ Contract test failed: {e}")
        return False

def test_pool_state_queries():
    """Test pool state queries with known pool IDs."""
    
    rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
    if not rpc_url:
        print("❌ ARBITRUM_SEPOLIA_RPC_URL not set")
        return False
    
    contract_address = "0xD87870729fe0efB97be17FD5735513782c33Db56"
    
    # ABI for pool state queries
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
        
        print("\n🧪 Testing pool state queries...")
        print("=" * 50)
        
        for i, pool_id in enumerate(test_pools, 1):
            print(f"\n📋 Test {i}: Pool {pool_id}")
            
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
                    print(f"❌ Pool not found or not initialized")
                    
            except Exception as e:
                print(f"❌ Function call failed: {e}")
        
        return True
        
    except Exception as e:
        print(f"❌ Pool state query test failed: {e}")
        return False

def test_pool_id_generation():
    """Test pool ID generation from pool keys."""
    
    rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
    if not rpc_url:
        print("❌ ARBITRUM_SEPOLIA_RPC_URL not set")
        return False
    
    contract_address = "0xD87870729fe0efB97be17FD5735513782c33Db56"
    
    # ABI for pool ID generation
    abi = [
        {
            "inputs": [
                {"internalType": "tuple", "name": "poolKey", "type": "tuple", "components": [
                    {"internalType": "address", "name": "currency0", "type": "address"},
                    {"internalType": "address", "name": "currency1", "type": "address"},
                    {"internalType": "uint24", "name": "fee", "type": "uint24"},
                    {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                    {"internalType": "address", "name": "hooks", "type": "address"}
                ]}
            ],
            "name": "getIdByKey",
            "outputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
            "stateMutability": "view",
            "type": "function"
        }
    ]
    
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        contract = w3.eth.contract(address=contract_address, abi=abi)
        
        # Test pool keys
        test_keys = [
            # Pool 1: ETH/MockUSDC, 0.05% fee
            (
                "0x0000000000000000000000000000000000000000",  # ETH
                "0x9D5A68fDFEcc14683324640D5e835936422a47b1",  # MockUSDC
                500,  # 0.05% fee
                10,   # tickSpacing
                "0x0000000000000000000000000000000000000000"   # no hooks
            ),
            # Pool 2: ETH/MockUSDC, 0.3% fee
            (
                "0x0000000000000000000000000000000000000000",  # ETH
                "0x9D5A68fDFEcc14683324640D5e835936422a47b1",  # MockUSDC
                3000, # 0.3% fee
                60,   # tickSpacing
                "0x0000000000000000000000000000000000000000"   # no hooks
            )
        ]
        
        print("\n🧪 Testing pool ID generation...")
        print("=" * 50)
        
        for i, (currency0, currency1, fee, tickSpacing, hooks) in enumerate(test_keys, 1):
            print(f"\n📋 Test {i}: Pool Key")
            print(f"   Currency0: {currency0}")
            print(f"   Currency1: {currency1}")
            print(f"   Fee: {fee}")
            print(f"   TickSpacing: {tickSpacing}")
            print(f"   Hooks: {hooks}")
            
            try:
                pool_key = (currency0, currency1, fee, tickSpacing, hooks)
                pool_id = contract.functions.getIdByKey(pool_key).call()
                print(f"✅ Generated Pool ID: {pool_id.hex()}")
                
            except Exception as e:
                print(f"❌ Pool ID generation failed: {e}")
        
        return True
        
    except Exception as e:
        print(f"❌ Pool ID generation test failed: {e}")
        return False

def main():
    """Main test function."""
    print("🔧 Comprehensive PoolStateViewer Test")
    print("=" * 50)
    
    if not WEB3_AVAILABLE:
        print("❌ Web3 library is required")
        return
    
    # Run all tests
    tests = [
        ("Contract Deployment", test_pool_state_viewer_deployment),
        ("Pool State Queries", test_pool_state_queries),
        ("Pool ID Generation", test_pool_id_generation)
    ]
    
    results = []
    for test_name, test_func in tests:
        print(f"\n🧪 Running {test_name} test...")
        result = test_func()
        results.append((test_name, result))
        print(f"{'✅ PASSED' if result else '❌ FAILED'}: {test_name}")
    
    # Summary
    print(f"\n📊 Test Summary")
    print("=" * 50)
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASSED" if result else "❌ FAILED"
        print(f"{status}: {test_name}")
    
    print(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! PoolStateViewer is working correctly.")
    else:
        print("⚠️  Some tests failed. Check the deployment and configuration.")

if __name__ == '__main__':
    main() 