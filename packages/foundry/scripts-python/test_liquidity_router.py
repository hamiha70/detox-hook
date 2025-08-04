#!/usr/bin/env python3
"""
Test script for LiquidityRouter setup verification
"""

import os
import sys
from web3 import Web3

# Configuration
LIQUIDITY_ROUTER_ADDRESS = "0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a"
ARBITRUM_SEPOLIA_RPC_URL = "https://sepolia-rollup.arbitrum.io/rpc"

def test_environment():
    """Test environment variables"""
    print("🔍 Testing environment variables...")
    
    required_vars = ["LIQUIDITY_PROVIDER_WALLET", "LIQUIDITY_PROVIDER_PRIVATE_KEY"]
    
    for var in required_vars:
        if var not in os.environ:
            print(f"❌ Missing environment variable: {var}")
            return False
        else:
            value = os.environ[var]
            if var.endswith("_WALLET"):
                print(f"✅ {var}: {value}")
            else:
                print(f"✅ {var}: {'*' * 10}{value[-4:]}")
    
    return True

def test_network_connection():
    """Test network connection"""
    print("\n🌐 Testing network connection...")
    
    try:
        w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC_URL))
        if not w3.is_connected():
            print("❌ Failed to connect to Arbitrum Sepolia")
            return False
        
        chain_id = w3.eth.chain_id
        print(f"✅ Connected to network with Chain ID: {chain_id}")
        
        if chain_id != 421614:
            print("❌ Wrong network! Expected Arbitrum Sepolia (421614)")
            return False
        
        return True
    except Exception as e:
        print(f"❌ Network connection failed: {e}")
        return False

def test_contract_exists():
    """Test if LiquidityRouter contract exists"""
    print(f"\n🔍 Testing LiquidityRouter contract...")
    
    try:
        w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC_URL))
        code = w3.eth.get_code(LIQUIDITY_ROUTER_ADDRESS)
        
        if code == b'':
            print(f"❌ No contract found at {LIQUIDITY_ROUTER_ADDRESS}")
            return False
        
        print(f"✅ LiquidityRouter contract exists at: {LIQUIDITY_ROUTER_ADDRESS}")
        return True
    except Exception as e:
        print(f"❌ Contract check failed: {e}")
        return False

def test_wallet_balance():
    """Test wallet balance"""
    print(f"\n💰 Testing wallet balance...")
    
    try:
        wallet_address = os.environ["LIQUIDITY_PROVIDER_WALLET"]
        w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC_URL))
        balance = w3.eth.get_balance(wallet_address)
        balance_eth = w3.from_wei(balance, 'ether')
        
        print(f"✅ Wallet balance: {balance_eth} ETH")
        
        if balance < w3.to_wei(0.001, 'ether'):
            print("⚠️ Low balance - may not be sufficient for transaction")
            return False
        
        return True
    except Exception as e:
        print(f"❌ Balance check failed: {e}")
        return False

def main():
    """Main test function"""
    print("🧪 LiquidityRouter Setup Test")
    print("=" * 40)
    
    tests = [
        ("Environment Variables", test_environment),
        ("Network Connection", test_network_connection),
        ("Contract Existence", test_contract_exists),
        ("Wallet Balance", test_wallet_balance)
    ]
    
    passed = 0
    total = len(tests)
    
    for test_name, test_func in tests:
        print(f"\n📋 Running: {test_name}")
        if test_func():
            print(f"✅ {test_name} - PASSED")
            passed += 1
        else:
            print(f"❌ {test_name} - FAILED")
    
    print(f"\n📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Ready to provide liquidity.")
        return True
    else:
        print("❌ Some tests failed. Please fix issues before proceeding.")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1) 