#!/usr/bin/env python3
"""
Script to check ETH balance of LiquidityRouter contract
"""

import os
import sys
from web3 import Web3
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def check_contract_balance():
    """Check ETH balance of LiquidityRouter contract"""
    
    # Contract address
    LIQUIDITY_ROUTER_ADDRESS = "0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a"
    
    # Get RPC URL from environment
    rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
    if not rpc_url:
        print("❌ ARBITRUM_SEPOLIA_RPC_URL not found in environment")
        return
    
    try:
        # Connect to Web3
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        if not w3.is_connected():
            print("❌ Failed to connect to RPC")
            return
        
        print("✅ Connected to Arbitrum Sepolia")
        
        # Check ETH balance
        balance_wei = w3.eth.get_balance(LIQUIDITY_ROUTER_ADDRESS)
        balance_eth = w3.from_wei(balance_wei, 'ether')
        
        print(f"\n📊 Contract Balance Check")
        print(f"Contract: {LIQUIDITY_ROUTER_ADDRESS}")
        print(f"ETH Balance: {balance_eth:.6f} ETH")
        print(f"Wei Balance: {balance_wei:,} wei")
        
        # Check if balance is significant
        if balance_eth > 0.001:
            print(f"✅ Contract has sufficient ETH for operations")
        else:
            print(f"⚠️  Contract has low ETH balance")
            
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    check_contract_balance() 