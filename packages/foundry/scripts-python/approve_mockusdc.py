#!/usr/bin/env python3
"""
Approve MockUSDC for LiquidityRouter Script

This script approves MockUSDC tokens for the LiquidityRouter contract
so that liquidity provision operations can work properly.
"""

import os
import sys
from web3 import Web3
from eth_account import Account

# Configuration
LIQUIDITY_ROUTER_ADDRESS = "0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a"
MOCK_USDC_ADDRESS = "0x9D5A68fDFEcc14683324640D5e835936422a47b1"
ARBITRUM_SEPOLIA_RPC_URL = "https://sepolia-rollup.arbitrum.io/rpc"

# ERC20 ABI for approval
ERC20_ABI = [
    {
        "inputs": [
            {"name": "spender", "type": "address"},
            {"name": "amount", "type": "uint256"}
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"name": "owner", "type": "address"},
            {"name": "spender", "type": "address"}
        ],
        "name": "allowance",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    }
]

def load_environment():
    """Load environment variables"""
    try:
        wallet_address = os.environ["LIQUIDITY_PROVIDER_WALLET"]
        private_key = os.environ["LIQUIDITY_PROVIDER_PRIVATE_KEY"]
        return wallet_address, private_key
    except KeyError as e:
        print(f"❌ Environment variable not set: {e}")
        print("Please set LIQUIDITY_PROVIDER_WALLET and LIQUIDITY_PROVIDER_PRIVATE_KEY")
        sys.exit(1)

def main():
    """Main function"""
    print("🔐 MockUSDC Approval Script for LiquidityRouter")
    print("=" * 50)
    
    # Load environment
    wallet_address, private_key = load_environment()
    print(f"✅ Wallet: {wallet_address}")
    
    # Connect to network
    print("🌐 Connecting to Arbitrum Sepolia...")
    w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC_URL))
    if not w3.is_connected():
        print("❌ Failed to connect to network")
        sys.exit(1)
    print("✅ Connected!")
    
    # Create contract instance
    token_contract = w3.eth.contract(address=MOCK_USDC_ADDRESS, abi=ERC20_ABI)
    
    # Check current balance
    balance = token_contract.functions.balanceOf(wallet_address).call()
    print(f"💰 MockUSDC balance: {balance}")
    
    # Check current allowance
    current_allowance = token_contract.functions.allowance(
        wallet_address, 
        LIQUIDITY_ROUTER_ADDRESS
    ).call()
    print(f"🔍 Current allowance: {current_allowance}")
    
    if current_allowance >= 2**200:  # Already has very high approval
        print("✅ MockUSDC already has sufficient approval!")
        return
    
    # Approve max amount
    print("🔐 Approving MockUSDC for LiquidityRouter...")
    
    approval_tx = token_contract.functions.approve(
        LIQUIDITY_ROUTER_ADDRESS,
        2**256 - 1  # Max approval
    ).build_transaction({
        'from': wallet_address,
        'gas': 100000,
        'gasPrice': w3.eth.gas_price,
        'nonce': w3.eth.get_transaction_count(wallet_address)
    })
    
    # Sign and send
    signed_tx = w3.eth.account.sign_transaction(approval_tx, private_key)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
    
    print(f"📝 Transaction sent: {tx_hash.hex()}")
    print("⏳ Waiting for confirmation...")
    
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
    
    if receipt.status == 1:
        print("✅ Approval successful!")
        
        # Verify new allowance
        new_allowance = token_contract.functions.allowance(
            wallet_address, 
            LIQUIDITY_ROUTER_ADDRESS
        ).call()
        print(f"🎉 New allowance: {new_allowance}")
        print("✅ Ready for liquidity provision!")
    else:
        print("❌ Approval failed!")
        sys.exit(1)

if __name__ == "__main__":
    main() 