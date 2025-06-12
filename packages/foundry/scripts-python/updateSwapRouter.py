#!/usr/bin/env python3
"""
Python Update Script for SwapRouter Contract with Pyth Integration

This script fetches the latest ETH/USD price and update data from Pyth Hermes API
and calls the SwapRouter updateBytes() function to update the integrated PriceRegister.

Usage: 
    python updateSwapRouter.py --help
    python updateSwapRouter.py --update
    python updateSwapRouter.py --read
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

# SwapRouter ABI (only the functions we need)
SWAP_ROUTER_ABI = [
    {
        "inputs": [{"internalType": "bytes[]", "name": "updateData", "type": "bytes[]"}],
        "name": "updateBytes",
        "outputs": [],
        "stateMutability": "payable",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "int256", "name": "amountToSwap", "type": "int256"},
            {"internalType": "bool", "name": "zeroForOne", "type": "bool"},
            {"internalType": "bytes", "name": "updateData", "type": "bytes"}
        ],
        "name": "swap",
        "outputs": [{"internalType": "int256", "name": "delta", "type": "int256"}],
        "stateMutability": "payable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "getPriceRegister",
        "outputs": [{"internalType": "address", "name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "pythOracle",
        "outputs": [{"internalType": "address", "name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function"
    }
]

# PriceRegister ABI (for reading the updated price)
PRICE_REGISTER_ABI = [
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
    }
]

# Pyth Oracle ABI (for getting update fee)
PYTH_ORACLE_ABI = [
    {
        "inputs": [{"internalType": "bytes[]", "name": "updateData", "type": "bytes[]"}],
        "name": "getUpdateFee",
        "outputs": [{"internalType": "uint256", "name": "feeAmount", "type": "uint256"}],
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

def fetch_pyth_data():
    """Fetch latest ETH/USD price and update data from Pyth Hermes API"""
    try:
        print_colored("Fetching latest ETH/USD data from Pyth Hermes...", 'cyan')
        
        # Construct API URL for update data
        url = f"{PYTH_HERMES_API}/v2/updates/price/latest"
        params = {
            'ids[]': ETH_USD_PRICE_ID,
            'encoding': 'hex'
        }
        
        # Make API request
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        
        if not data.get('binary') or not data.get('parsed'):
            raise ValueError("Invalid response format from Hermes API")
        
        # Extract update data (binary format for updateBytes)
        update_data_hex = data['binary']['data'][0]
        if not update_data_hex.startswith('0x'):
            update_data_hex = '0x' + update_data_hex
        
        # Extract parsed price information for display
        parsed_data = data['parsed'][0]
        price_info = parsed_data['price']
        
        price_raw = int(price_info['price'])
        expo = int(price_info['expo'])
        publish_time = int(price_info['publish_time'])
        
        # Calculate actual price
        actual_price = price_raw * (10 ** expo)
        
        # Format publish time
        publish_datetime = datetime.fromtimestamp(publish_time)
        
        print_colored(f"Successfully fetched ETH/USD price: ${actual_price:,.2f}", 'green')
        print_colored(f"Published at: {publish_datetime}", 'gray')
        
        return {
            'update_data': update_data_hex,
            'price_formatted': actual_price,
            'publish_time': publish_datetime
        }
        
    except Exception as e:
        print_colored(f"Error fetching Pyth data: {e}", 'red')
        return None

def get_web3_connection():
    """Initialize Web3 connection"""
    try:
        # Get RPC URL from environment (default to Arbitrum Sepolia)
        rpc_url = os.getenv('RPC_URL', 'https://sepolia-rollup.arbitrum.io/rpc')
        
        print_colored(f"Connecting to blockchain: {rpc_url}", 'cyan')
        
        # Initialize Web3
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        # Check connection
        if not w3.is_connected():
            raise ConnectionError("Failed to connect to blockchain")
        
        chain_id = w3.eth.chain_id
        print_colored(f"Connected to network (Chain ID: {chain_id})", 'green')
        
        return w3
        
    except Exception as e:
        print_colored(f"Connection error: {e}", 'red')
        return None

def read_swap_router_state():
    """Read current state from SwapRouter and connected PriceRegister"""
    try:
        contract_address = os.getenv('SWAP_ROUTER_ADDRESS')
        
        if not contract_address:
            print_colored("SWAP_ROUTER_ADDRESS environment variable not set", 'red')
            return False
        
        w3 = get_web3_connection()
        if not w3:
            return False
        
        # Initialize SwapRouter contract
        swap_router = w3.eth.contract(
            address=Web3.to_checksum_address(contract_address),
            abi=SWAP_ROUTER_ABI
        )
        
        print_colored("Reading SwapRouter state...", 'cyan')
        
        # Get connected contracts
        price_register_addr = swap_router.functions.getPriceRegister().call()
        
        try:
            pyth_oracle_addr = swap_router.functions.pythOracle().call()
            print_colored(f"Connected Pyth Oracle: {pyth_oracle_addr}", 'gray')
        except Exception as e:
            print_colored(f"Warning: Could not get Pyth Oracle address: {e}", 'yellow')
            pyth_oracle_addr = "0x0000000000000000000000000000000000000000"
        
        if price_register_addr != "0x0000000000000000000000000000000000000000":
            price_register = w3.eth.contract(
                address=Web3.to_checksum_address(price_register_addr),
                abi=PRICE_REGISTER_ABI
            )
            
            current_price = price_register.functions.getPrice().call()
            current_source = price_register.functions.getSource().call()
            
            print_colored("Current PriceRegister state:", 'green')
            print_colored(f"Price (raw): {current_price}", 'white')
            print_colored(f"Price (formatted): ${current_price/100:,.2f}", 'white')
            print_colored(f"Source: {current_source}", 'white')
            print_colored(f"PriceRegister Address: {price_register_addr}", 'gray')
        else:
            print_colored("No PriceRegister connected", 'yellow')
        
        # Check if Pyth oracle is configured
        if pyth_oracle_addr == "0x0000000000000000000000000000000000000000":
            print_colored("WARNING: No Pyth Oracle configured in SwapRouter", 'yellow')
            print_colored("This may cause updateBytes() to fail")
        
        return True
        
    except Exception as e:
        print_colored(f"Read error: {e}", 'red')
        return False

def update_swap_router(pyth_data):
    """Update SwapRouter using Pyth update data"""
    try:
        private_key = os.getenv('DEPLOYMENT_KEY')
        contract_address = os.getenv('SWAP_ROUTER_ADDRESS')
        
        if not private_key or not contract_address:
            print_colored("Missing environment variables", 'red')
            return False
        
        w3 = get_web3_connection()
        if not w3:
            return False
        
        # Initialize account
        if private_key.startswith('0x'):
            private_key = private_key[2:]
        
        account = Account.from_key(private_key)
        wallet_address = account.address
        
        print_colored(f"Using wallet: {wallet_address}", 'cyan')
        
        # Check balance
        balance = w3.eth.get_balance(wallet_address)
        balance_eth = w3.from_wei(balance, 'ether')
        
        print_colored(f"Wallet balance: {balance_eth:.6f} ETH", 'green')
        
        if balance == 0:
            print_colored("Insufficient ETH balance", 'red')
            return False
        
        # Initialize contract
        contract = w3.eth.contract(
            address=Web3.to_checksum_address(contract_address),
            abi=SWAP_ROUTER_ABI
        )
        
        # Prepare update data
        update_data_array = [pyth_data['update_data']]
        
        print_colored(f"Calling updateBytes() with price: ${pyth_data['price_formatted']:,.2f}", 'cyan')
        
        # Get Pyth oracle address
        pyth_oracle_addr = contract.functions.pythOracle().call()
        if pyth_oracle_addr == "0x0000000000000000000000000000000000000000":
            print_colored("Error: No Pyth Oracle configured in SwapRouter", 'red')
            return False
        
        # Get required update fee from Pyth oracle
        pyth_oracle = w3.eth.contract(
            address=Web3.to_checksum_address(pyth_oracle_addr),
            abi=PYTH_ORACLE_ABI
        )
        
        try:
            required_fee = pyth_oracle.functions.getUpdateFee(update_data_array).call()
            required_fee_eth = w3.from_wei(required_fee, 'ether')
            print_colored(f"Required Pyth fee: {required_fee_eth:.6f} ETH ({required_fee} wei)", 'gray')
        except Exception as e:
            print_colored(f"Error getting update fee: {e}", 'red')
            return False
        
        # Build transaction
        transaction = contract.functions.updateBytes(update_data_array).build_transaction({
            'from': wallet_address,
            'nonce': w3.eth.get_transaction_count(wallet_address),
            'gas': 0,
            'gasPrice': int(w3.eth.gas_price * 1.2),
            'value': required_fee  # Use exact required fee
        })
        
        # Estimate gas
        try:
            gas_estimate = w3.eth.estimate_gas(transaction)
            transaction['gas'] = int(gas_estimate * 1.2)
            
            print_colored(f"Estimated gas: {transaction['gas']:,}", 'gray')
        except Exception as e:
            print_colored(f"Gas estimation failed: {e}", 'yellow')
            
            # Try to simulate the call first to see if the function would work
            try:
                result = contract.functions.updateBytes(update_data_array).call({
                    'from': wallet_address,
                    'value': required_fee
                })
                print_colored("Call simulation succeeded - using fixed gas limit", 'green')
                # Use a reasonable fixed gas limit based on successful Cast transaction (61,531 gas)
                transaction['gas'] = 100000  # Safe buffer for complex try-catch logic
            except Exception as call_error:
                print_colored(f"Call simulation also failed: {call_error}", 'red')
                
                # Check if it's a specific contract error
                error_str = str(call_error)
                if "no data" in error_str.lower():
                    print_colored("Likely cause: Pyth oracle rejected the update data", 'yellow')
                    print_colored("This could be due to:", 'yellow')
                    print_colored("- Stale price data (too old)", 'yellow')
                    print_colored("- Invalid price feed for this network", 'yellow')
                    print_colored("- Pyth oracle configuration issue", 'yellow')
                elif "insufficient" in error_str.lower():
                    print_colored("Likely cause: Insufficient fee for Pyth update", 'yellow')
                elif "invalid" in error_str.lower():
                    print_colored("Likely cause: Invalid update data format", 'yellow')
                return False
        
        # Sign and send
        signed_txn = w3.eth.account.sign_transaction(transaction, private_key)
        raw_tx = signed_txn.raw_transaction if hasattr(signed_txn, 'raw_transaction') else signed_txn.rawTransaction
        tx_hash = w3.eth.send_raw_transaction(raw_tx)
        
        print_colored(f"Transaction sent: {tx_hash.hex()}", 'yellow')
        print_colored("Waiting for confirmation...", 'cyan')
        
        # Wait for receipt
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
        
        if receipt.status == 1:
            print_colored(f"Transaction confirmed in block {receipt.blockNumber}", 'green')
            
            # Verify update
            print_colored("Verifying update...", 'cyan')
            read_swap_router_state()
            
            return True
        else:
            print_colored("Transaction failed", 'red')
            return False
            
    except Exception as e:
        print_colored(f"Update error: {e}", 'red')
        return False

def test_swap_with_update(pyth_data):
    """Test updating price via SwapRouter swap() function with minimal amount"""
    try:
        private_key = os.getenv('DEPLOYMENT_KEY')
        contract_address = os.getenv('SWAP_ROUTER_ADDRESS')
        
        if not private_key or not contract_address:
            print_colored("Missing environment variables", 'red')
            return False
        
        w3 = get_web3_connection()
        if not w3:
            return False
        
        # Initialize account
        if private_key.startswith('0x'):
            private_key = private_key[2:]
        
        account = Account.from_key(private_key)
        wallet_address = account.address
        
        print_colored(f"Testing swap approach with wallet: {wallet_address}", 'cyan')
        
        # Initialize contract
        contract = w3.eth.contract(
            address=Web3.to_checksum_address(contract_address),
            abi=SWAP_ROUTER_ABI
        )
        
        # Use minimal swap amount (negative for exact input)
        minimal_amount = -1000000000000000  # -0.001 ETH (exact input)
        zero_for_one = True  # ETH to USDC
        
        # Convert update data to bytes format for swap function
        update_data_bytes = bytes.fromhex(pyth_data['update_data'][2:])  # Remove 0x prefix
        
        print_colored(f"Testing minimal swap (-0.001 ETH exact input) with Pyth update data", 'cyan')
        print_colored(f"Update data size: {len(update_data_bytes)} bytes", 'gray')
        
        # Build transaction - need enough ETH for the swap amount plus fees
        transaction = contract.functions.swap(
            minimal_amount,
            zero_for_one,
            update_data_bytes
        ).build_transaction({
            'from': wallet_address,
            'nonce': w3.eth.get_transaction_count(wallet_address),
            'gas': 0,
            'gasPrice': int(w3.eth.gas_price * 1.2),
            'value': w3.to_wei(0.002, 'ether')  # Enough ETH for swap + oracle fees
        })
        
        # Estimate gas
        try:
            gas_estimate = w3.eth.estimate_gas(transaction)
            transaction['gas'] = int(gas_estimate * 1.2)
            
            print_colored(f"Estimated gas: {transaction['gas']:,}", 'gray')
        except Exception as e:
            print_colored(f"Gas estimation failed: {e}", 'red')
            return False
        
        # Sign and send
        signed_txn = w3.eth.account.sign_transaction(transaction, private_key)
        raw_tx = signed_txn.raw_transaction if hasattr(signed_txn, 'raw_transaction') else signed_txn.rawTransaction
        tx_hash = w3.eth.send_raw_transaction(raw_tx)
        
        print_colored(f"Transaction sent: {tx_hash.hex()}", 'yellow')
        print_colored("Waiting for confirmation...", 'cyan')
        
        # Wait for receipt
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
        
        if receipt.status == 1:
            print_colored(f"Swap transaction confirmed in block {receipt.blockNumber}", 'green')
            
            # Verify if PriceRegister was updated
            print_colored("Checking if PriceRegister was updated...", 'cyan')
            read_swap_router_state()
            
            return True
        else:
            print_colored("Swap transaction failed", 'red')
            return False
            
    except Exception as e:
        print_colored(f"Swap test error: {e}", 'red')
        return False

def main():
    """Main function"""
    print_colored("SwapRouter Pyth Integration Script", 'magenta')
    
    if len(sys.argv) != 2:
        print_colored("Usage: python updateSwapRouter.py [--help|--read|--update|--test-swap]", 'red')
        sys.exit(1)
    
    flag = sys.argv[1]
    
    if flag == "--help":
        print_colored("SwapRouter Update Script", 'cyan')
        print_colored("Commands:", 'white')
        print_colored("  --help       Show this help", 'white')
        print_colored("  --read       Read current state", 'white')
        print_colored("  --update     Update via updateBytes() function", 'white')
        print_colored("  --test-swap  Test update via minimal swap()", 'white')
        sys.exit(0)
        
    elif flag == "--read":
        success = read_swap_router_state()
        sys.exit(0 if success else 1)
        
    elif flag == "--update":
        # Fetch Pyth data
        pyth_data = fetch_pyth_data()
        if not pyth_data:
            sys.exit(1)
        
        # Update SwapRouter via updateBytes
        success = update_swap_router(pyth_data)
        sys.exit(0 if success else 1)
    
    elif flag == "--test-swap":
        # Fetch Pyth data
        pyth_data = fetch_pyth_data()
        if not pyth_data:
            sys.exit(1)
        
        # Test update via minimal swap
        success = test_swap_with_update(pyth_data)
        sys.exit(0 if success else 1)
    
    else:
        print_colored(f"Unknown flag: {flag}", 'red')
        sys.exit(1)

if __name__ == "__main__":
    main() 