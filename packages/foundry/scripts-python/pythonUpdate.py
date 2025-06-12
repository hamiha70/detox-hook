#!/usr/bin/env python3
"""
Python Update Script for PriceRegister Contract

This script fetches the latest ETH/USD price from Pyth Hermes API
and updates the PriceRegister contract with the new price data.

Usage: 
    python pythonUpdatePython.py --help
    python pythonUpdatePython.py --update
    python pythonUpdatePython.py --read
"""

import requests
import json
import sys
import os
from datetime import datetime
from web3 import Web3
from eth_account import Account

# Pyth Network Constants
PYTH_HERMES_API = "https://hermes.pyth.network"
ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"

# Contract ABI for PriceRegister
PRICE_REGISTER_ABI = [
    {
        "inputs": [{"internalType": "uint256", "name": "newPrice", "type": "uint256"},
                  {"internalType": "string", "name": "newSource", "type": "string"}],
        "name": "update",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getPrice",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getSource",
        "outputs": [{"internalType": "string", "name": "", "type": "string"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getData",
        "outputs": [{"internalType": "uint256", "name": "price", "type": "uint256"},
                   {"internalType": "string", "name": "sourceValue", "type": "string"}],
        "stateMutability": "view",
        "type": "function"
    }
]

def print_colored(message, color='white'):
    """Print colored output to console"""
    colors = {
        'red': '\033[91m',
        'green': '\033[92m',
        'yellow': '\033[93m',
        'blue': '\033[94m',
        'magenta': '\033[95m',
        'cyan': '\033[96m',
        'white': '\033[97m',
        'gray': '\033[90m',
        'reset': '\033[0m'
    }
    
    color_code = colors.get(color, colors['white'])
    reset_code = colors['reset']
    print(f"{color_code}{message}{reset_code}")

def print_help():
    """Display help information"""
    help_text = """
🐍 Python Update Script for PriceRegister Contract

DESCRIPTION:
    This script fetches the latest ETH/USD price from Pyth Hermes API
    and updates the PriceRegister smart contract with the new price data.
    It can also read the current price and source from the contract.

USAGE:
    python pythonUpdatePython.py --help     Show this help message
    python pythonUpdatePython.py --update   Update PriceRegister with latest ETH/USD price
    python pythonUpdatePython.py --read     Read current price and source from PriceRegister

ENVIRONMENT VARIABLES:
    DEPLOYMENT_KEY          Private key for the wallet to fund contract updates (required for --update only)
    PRICE_REGISTER_ADDRESS  Address of the deployed PriceRegister contract
    RPC_URL                 Ethereum RPC endpoint (defaults to Arbitrum Sepolia)

EXAMPLES:
    # Display help
    python pythonUpdatePython.py --help
    
    # Update price from Pyth Hermes
    python pythonUpdatePython.py --update
    
    # Read current contract state
    python pythonUpdatePython.py --read

REQUIREMENTS:
    - Python packages: web3, requests, eth-account
    - Environment variables properly set
    - Sufficient ETH in DEPLOYMENT_KEY for gas fees (--update only)

FEATURES:
    ✅ Fetches real-time ETH/USD price from Pyth Network
    ✅ Updates PriceRegister contract with new price
    ✅ Reads current price and source from contract
    ✅ Sets source to "python" to identify update origin  
    ✅ Comprehensive error handling and validation
    ✅ Gas estimation and transaction confirmation
    
SECURITY:
    🛡️ Uses environment variables for sensitive data
    🛡️ Validates all inputs before contract interaction
    🛡️ Estimates gas before sending transactions
    """
    
    print_colored(help_text, 'cyan')

def fetch_eth_price():
    """Fetch latest ETH/USD price from Pyth Hermes API"""
    try:
        print_colored("📡 Fetching latest ETH/USD price from Pyth Hermes...", 'cyan')
        
        # Construct API URL
        url = f"{PYTH_HERMES_API}/v2/updates/price/latest"
        params = {
            'ids[]': ETH_USD_PRICE_ID,
            'encoding': 'hex'
        }
        
        # Make API request
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        
        if not data.get('parsed'):
            raise ValueError("Invalid response format from Hermes API")
        
        # Extract parsed price information
        parsed_data = data['parsed'][0]
        price_info = parsed_data['price']
        
        price_raw = int(price_info['price'])
        expo = int(price_info['expo'])
        publish_time = int(price_info['publish_time'])
        
        # Calculate actual price
        actual_price = price_raw * (10 ** expo)
        
        # Format publish time
        publish_datetime = datetime.fromtimestamp(publish_time)
        
        print_colored(f"✅ Successfully fetched ETH/USD price: ${actual_price:,.2f}", 'green')
        print_colored(f"📅 Published at: {publish_datetime}", 'gray')
        
        # Convert to integer (removing decimals for contract storage)
        # Store price in cents to maintain precision
        price_in_cents = int(actual_price * 100)
        
        return {
            'price': price_in_cents,
            'price_formatted': actual_price,
            'publish_time': publish_datetime
        }
        
    except requests.exceptions.RequestException as e:
        print_colored(f"❌ Network error fetching price: {e}", 'red')
        return None
    except (KeyError, ValueError, TypeError) as e:
        print_colored(f"❌ Data parsing error: {e}", 'red')
        return None
    except Exception as e:
        print_colored(f"❌ Unexpected error: {e}", 'red')
        return None

def get_web3_connection():
    """Initialize Web3 connection"""
    try:
        # Get RPC URL from environment (default to Arbitrum Sepolia)
        rpc_url = os.getenv('RPC_URL', 'https://sepolia-rollup.arbitrum.io/rpc')
        
        print_colored(f"🔗 Connecting to blockchain: {rpc_url}", 'cyan')
        
        # Initialize Web3
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        # Check connection
        if not w3.is_connected():
            raise ConnectionError("Failed to connect to blockchain")
        
        # Get network info
        chain_id = w3.eth.chain_id
        block_number = w3.eth.block_number
        
        print_colored(f"✅ Connected to network (Chain ID: {chain_id}, Block: {block_number})", 'green')
        
        return w3
        
    except Exception as e:
        print_colored(f"❌ Blockchain connection error: {e}", 'red')
        return None

def read_price_register():
    """Read current price and source from PriceRegister contract"""
    try:
        # Get environment variables
        contract_address = os.getenv('PRICE_REGISTER_ADDRESS')
        
        if not contract_address:
            print_colored("❌ PRICE_REGISTER_ADDRESS environment variable not set", 'red')
            return False
        
        # Initialize Web3
        w3 = get_web3_connection()
        if not w3:
            return False
        
        # Initialize contract
        contract = w3.eth.contract(
            address=Web3.to_checksum_address(contract_address),
            abi=PRICE_REGISTER_ABI
        )
        
        print_colored(f"📋 Contract address: {contract_address}", 'cyan')
        print_colored("📖 Reading current contract state...", 'cyan')
        
        # Read current price and source
        try:
            current_price = contract.functions.getPrice().call()
            current_source = contract.functions.getSource().call()
            
            # Also try to get both values at once using getData
            price_data, source_data = contract.functions.getData().call()
            
            # Verify consistency
            if current_price != price_data or current_source != source_data:
                print_colored("⚠️  Inconsistent data between individual and combined calls", 'yellow')
            
            print_colored("\n✅ Successfully read from PriceRegister contract!", 'green')
            print_colored("=" * 50, 'gray')
            
            # Format price for display (assuming it's stored in cents)
            price_formatted = current_price / 100 if current_price > 1000 else current_price
            
            # Display current state
            print_colored("📊 CURRENT CONTRACT STATE", 'yellow')
            print_colored(f"   Price (raw): {current_price}", 'cyan')
            print_colored(f"   Price (formatted): ${price_formatted:,.2f}", 'green')
            print_colored(f"   Source: {current_source}", 'cyan')
            
            # Additional information
            print_colored("\n📋 CONTRACT INFORMATION", 'yellow')
            print_colored(f"   Contract Address: {contract_address}", 'gray')
            print_colored(f"   Network Chain ID: {w3.eth.chain_id}", 'gray')
            print_colored(f"   Current Block: {w3.eth.block_number}", 'gray')
            
            # Interpret source information
            if current_source == "init":
                print_colored("\n💡 STATUS: Contract in initial state", 'yellow')
            elif current_source == "python":
                print_colored("\n💡 STATUS: Last updated by Python script", 'green')
            else:
                print_colored(f"\n💡 STATUS: Last updated by: {current_source}", 'blue')
            
            # Price analysis
            if current_price == 1:
                print_colored("⚠️  WARNING: Price appears to be in initial state", 'yellow')
            elif current_price > 500000:  # > $5000 (assuming cents)
                print_colored("📈 INFO: ETH price appears high", 'blue')
            elif current_price < 100000:  # < $1000 (assuming cents)
                print_colored("📉 INFO: ETH price appears low", 'blue')
            else:
                print_colored("📊 INFO: ETH price in normal range", 'green')
            
            print_colored("=" * 50, 'gray')
            
            return True
            
        except Exception as e:
            print_colored(f"❌ Failed to read contract data: {e}", 'red')
            return False
            
    except Exception as e:
        print_colored(f"❌ Read error: {e}", 'red')
        return False

def update_price_register(price_data):
    """Update PriceRegister contract with new price"""
    try:
        # Get environment variables
        private_key = os.getenv('DEPLOYMENT_KEY')
        contract_address = os.getenv('PRICE_REGISTER_ADDRESS')
        
        if not private_key:
            print_colored("❌ DEPLOYMENT_KEY environment variable not set", 'red')
            return False
            
        if not contract_address:
            print_colored("❌ PRICE_REGISTER_ADDRESS environment variable not set", 'red')
            return False
        
        # Initialize Web3
        w3 = get_web3_connection()
        if not w3:
            return False
        
        # Initialize account
        # Remove '0x' prefix if present
        if private_key.startswith('0x'):
            private_key = private_key[2:]
        
        account = Account.from_key(private_key)
        wallet_address = account.address
        
        print_colored(f"👛 Using wallet: {wallet_address}", 'cyan')
        
        # Check wallet balance
        balance = w3.eth.get_balance(wallet_address)
        balance_eth = w3.from_wei(balance, 'ether')
        
        if balance == 0:
            print_colored("❌ Insufficient ETH balance for gas fees", 'red')
            return False
            
        print_colored(f"💰 Wallet balance: {balance_eth:.6f} ETH", 'green')
        
        # Initialize contract
        contract = w3.eth.contract(
            address=Web3.to_checksum_address(contract_address),
            abi=PRICE_REGISTER_ABI
        )
        
        print_colored(f"📋 Contract address: {contract_address}", 'cyan')
        
        # Get current price for comparison
        try:
            current_price = contract.functions.getPrice().call()
            current_source = contract.functions.getSource().call()
            print_colored(f"📊 Current price: {current_price} (source: {current_source})", 'gray')
        except Exception:
            print_colored("⚠️  Could not read current contract state", 'yellow')
        
        # Prepare transaction
        print_colored(f"🔄 Updating contract with price: {price_data['price']} (${price_data['price_formatted']:,.2f})", 'cyan')
        
        # Build transaction
        transaction = contract.functions.update(
            price_data['price'],
            "python"
        ).build_transaction({
            'from': wallet_address,
            'nonce': w3.eth.get_transaction_count(wallet_address),
            'gas': 0,  # Will be estimated
            'gasPrice': int(w3.eth.gas_price * 1.2)  # Add 20% buffer for gas price
        })
        
        # Estimate gas
        try:
            gas_estimate = w3.eth.estimate_gas(transaction)
            transaction['gas'] = int(gas_estimate * 1.2)  # Add 20% buffer
            
            gas_cost_wei = transaction['gas'] * transaction['gasPrice']
            gas_cost_eth = w3.from_wei(gas_cost_wei, 'ether')
            
            print_colored(f"⛽ Estimated gas: {transaction['gas']:,} (cost: {gas_cost_eth:.6f} ETH)", 'gray')
            
        except Exception as e:
            print_colored(f"❌ Gas estimation failed: {e}", 'red')
            return False
        
        # Sign and send transaction
        try:
            signed_txn = w3.eth.account.sign_transaction(transaction, private_key)
            # Use raw_transaction instead of rawTransaction for newer web3.py versions
            raw_tx = signed_txn.raw_transaction if hasattr(signed_txn, 'raw_transaction') else signed_txn.rawTransaction
            tx_hash = w3.eth.send_raw_transaction(raw_tx)
            
            print_colored(f"📤 Transaction sent: {tx_hash.hex()}", 'yellow')
            print_colored("⏳ Waiting for confirmation...", 'cyan')
            
            # Wait for transaction receipt
            receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
            
            if receipt.status == 1:
                print_colored(f"✅ Transaction confirmed in block {receipt.blockNumber}", 'green')
                print_colored(f"⛽ Gas used: {receipt.gasUsed:,}", 'gray')
                
                # Verify update
                try:
                    new_price = contract.functions.getPrice().call()
                    new_source = contract.functions.getSource().call()
                    print_colored(f"🎯 Contract updated - Price: {new_price}, Source: {new_source}", 'green')
                except Exception:
                    print_colored("⚠️  Could not verify contract update", 'yellow')
                
                return True
            else:
                print_colored(f"❌ Transaction failed", 'red')
                return False
                
        except Exception as e:
            print_colored(f"❌ Transaction error: {e}", 'red')
            return False
            
    except Exception as e:
        print_colored(f"❌ Update error: {e}", 'red')
        return False

def main():
    """Main function"""
    try:
        print_colored("\n🐍 Python PriceRegister Updater", 'magenta')
        print_colored("=" * 50, 'gray')
        
        # Check command line arguments
        if len(sys.argv) != 2:
            print_colored("❌ Invalid arguments. Use --help for usage information.", 'red')
            sys.exit(1)
        
        flag = sys.argv[1]
        
        if flag == "--help":
            print_help()
            sys.exit(0)
            
        elif flag == "--read":
            print_colored("📖 Reading current price from PriceRegister contract...", 'cyan')
            
            # Read current contract state
            success = read_price_register()
            
            if success:
                print_colored("\n🎉 Read operation completed successfully!", 'green')
                print_colored("=" * 50, 'gray')
                sys.exit(0)
            else:
                print_colored("\n❌ Read operation failed", 'red')
                print_colored("=" * 50, 'gray')
                sys.exit(1)
            
        elif flag == "--update":
            print_colored("🚀 Starting price update process...", 'cyan')
            
            # Fetch price from Pyth
            price_data = fetch_eth_price()
            if not price_data:
                print_colored("❌ Failed to fetch price data", 'red')
                sys.exit(1)
            
            # Update contract
            success = update_price_register(price_data)
            
            if success:
                print_colored("\n🎉 Price update completed successfully!", 'green')
                print_colored("=" * 50, 'gray')
                sys.exit(0)
            else:
                print_colored("\n❌ Price update failed", 'red')
                print_colored("=" * 50, 'gray')
                sys.exit(1)
        
        else:
            print_colored(f"❌ Unknown flag: {flag}. Use --help for usage information.", 'red')
            sys.exit(1)
            
    except KeyboardInterrupt:
        print_colored("\n\n⚠️  Operation cancelled by user", 'yellow')
        sys.exit(1)
    except Exception as e:
        print_colored(f"\n❌ Unexpected error in main(): {e}", 'red')
        sys.exit(1)

if __name__ == "__main__":
    main() 