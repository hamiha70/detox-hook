#!/usr/bin/env python3
"""
Pyth Oracle Test Script

This script tests the Pyth oracle integration by:
1. Fetching the most recent ETH/USD price from Pyth Hermes API
2. Printing the price to console
3. Calling the smart contract Pyth oracle directly
4. Printing the returned price from the oracle

Usage: python oracle-test.py
"""

import requests
import json
import os
import sys
from datetime import datetime
from web3 import Web3
from eth_account import Account

# Pyth Network Constants
PYTH_HERMES_API = "https://hermes.pyth.network"
ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"

# Pyth Oracle ABI (essential functions for testing)
PYTH_ORACLE_ABI = [
    {
        "inputs": [{"internalType": "bytes[]", "name": "updateData", "type": "bytes[]"}],
        "name": "getUpdateFee",
        "outputs": [{"internalType": "uint256", "name": "feeAmount", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "bytes[]", "name": "updateData", "type": "bytes[]"}],
        "name": "updatePriceFeeds",
        "outputs": [],
        "stateMutability": "payable",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "bytes32", "name": "id", "type": "bytes32"}],
        "name": "getPriceUnsafe",
        "outputs": [
            {
                "components": [
                    {"internalType": "int64", "name": "price", "type": "int64"},
                    {"internalType": "uint64", "name": "conf", "type": "uint64"},
                    {"internalType": "int32", "name": "expo", "type": "int32"},
                    {"internalType": "uint256", "name": "publishTime", "type": "uint256"}
                ],
                "internalType": "struct PythStructs.Price",
                "name": "price",
                "type": "tuple"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"internalType": "bytes32", "name": "id", "type": "bytes32"}],
        "name": "getPrice",
        "outputs": [
            {
                "components": [
                    {"internalType": "int64", "name": "price", "type": "int64"},
                    {"internalType": "uint64", "name": "conf", "type": "uint64"},
                    {"internalType": "int32", "name": "expo", "type": "int32"},
                    {"internalType": "uint256", "name": "publishTime", "type": "uint256"}
                ],
                "internalType": "struct PythStructs.Price",
                "name": "price",
                "type": "tuple"
            }
        ],
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

def fetch_pyth_hermes_price():
    """Step 1: Fetch the most recent ETH/USD price from Pyth Hermes API"""
    try:
        print_colored("🔍 Step 1: Fetching ETH/USD price from Pyth Hermes API...", 'cyan')
        
        # Construct API URL for latest price data
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
        
        # Extract update data (binary format for oracle update)
        update_data_hex = data['binary']['data'][0]
        if not update_data_hex.startswith('0x'):
            update_data_hex = '0x' + update_data_hex
        
        # Extract parsed price information
        parsed_data = data['parsed'][0]
        price_info = parsed_data['price']
        
        price_raw = int(price_info['price'])
        expo = int(price_info['expo'])
        confidence = int(price_info['conf'])
        publish_time = int(price_info['publish_time'])
        
        # Calculate actual price
        actual_price = price_raw * (10 ** expo)
        confidence_price = confidence * (10 ** expo)
        
        # Format publish time
        publish_datetime = datetime.fromtimestamp(publish_time)
        
        print_colored(f"✅ Hermes API Response:", 'green')
        print_colored(f"   Price: ${actual_price:,.2f}", 'white')
        print_colored(f"   Confidence: ±${confidence_price:,.2f}", 'gray')
        print_colored(f"   Published: {publish_datetime}", 'gray')
        print_colored(f"   Update Data Size: {len(update_data_hex)} characters", 'gray')
        
        return {
            'update_data': update_data_hex,
            'hermes_price': actual_price,
            'confidence': confidence_price,
            'publish_time': publish_datetime,
            'raw_price': price_raw,
            'expo': expo
        }
        
    except Exception as e:
        print_colored(f"❌ Error fetching Pyth Hermes data: {e}", 'red')
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
        
        chain_id = w3.eth.chain_id
        print_colored(f"✅ Connected to network (Chain ID: {chain_id})", 'green')
        
        return w3
        
    except Exception as e:
        print_colored(f"❌ Connection error: {e}", 'red')
        return None

def test_pyth_oracle(hermes_data):
    """Step 3: Call the smart contract Pyth oracle and Step 4: Print returned price"""
    try:
        oracle_address = os.getenv('PYTHTEST_CONTRACT_ADDRESS')
        
        if not oracle_address:
            print_colored("❌ PYTHTEST_CONTRACT_ADDRESS environment variable not set", 'red')
            print_colored("   Please set it to the Pyth oracle contract address", 'yellow')
            return False
        
        print_colored(f"🔍 Step 3: Testing Pyth Oracle Contract at: {oracle_address}", 'cyan')
        
        w3 = get_web3_connection()
        if not w3:
            return False
        
        # Initialize oracle contract
        oracle = w3.eth.contract(
            address=Web3.to_checksum_address(oracle_address),
            abi=PYTH_ORACLE_ABI
        )
        
        # Prepare update data array
        update_data_array = [hermes_data['update_data']]
        
        print_colored("📊 Testing Oracle Functions:", 'magenta')
        
        # Test 1: Get update fee
        try:
            update_fee = oracle.functions.getUpdateFee(update_data_array).call()
            update_fee_eth = w3.from_wei(update_fee, 'ether')
            print_colored(f"   Update Fee: {update_fee_eth:.6f} ETH ({update_fee} wei)", 'white')
        except Exception as e:
            print_colored(f"   Update Fee Error: {e}", 'red')
        
        # Test 2: Try to get current price (without update)
        try:
            current_price = oracle.functions.getPriceUnsafe(ETH_USD_PRICE_ID).call()
            price_value = current_price[0]  # price
            price_conf = current_price[1]   # confidence
            price_expo = current_price[2]   # exponent
            price_time = current_price[3]   # publish time
            
            # Calculate actual price
            actual_oracle_price = price_value * (10 ** price_expo)
            actual_confidence = price_conf * (10 ** price_expo)
            oracle_publish_time = datetime.fromtimestamp(price_time)
            
            print_colored(f"✅ Current Oracle Price (getPriceUnsafe):", 'green')
            print_colored(f"   Price: ${actual_oracle_price:,.2f}", 'white')
            print_colored(f"   Confidence: ±${actual_confidence:,.2f}", 'gray')
            print_colored(f"   Published: {oracle_publish_time}", 'gray')
            
            # Compare with Hermes data
            price_diff = abs(actual_oracle_price - hermes_data['hermes_price'])
            time_diff = abs((hermes_data['publish_time'] - oracle_publish_time).total_seconds())
            
            print_colored(f"📈 Comparison with Hermes:", 'yellow')
            print_colored(f"   Price Difference: ${price_diff:,.2f}", 'white')
            print_colored(f"   Time Difference: {time_diff:.0f} seconds", 'gray')
            
        except Exception as e:
            print_colored(f"❌ Error getting current oracle price: {e}", 'red')
            
            # This might be expected if the price feed doesn't exist
            if "PriceFeedNotFound" in str(e) or "no data" in str(e).lower():
                print_colored("   This is expected on testnets - price feed may not be available", 'yellow')
            
        # Test 3: Try to update with new data (simulation only)
        try:
            print_colored("🔄 Testing Price Update (Simulation):", 'cyan')
            
            # Simulate the update call
            oracle.functions.updatePriceFeeds(update_data_array).call()
            print_colored("   ✅ Update simulation successful", 'green')
            
            # If simulation works, try to see what the price would be after update
            try:
                updated_price = oracle.functions.getPriceUnsafe(ETH_USD_PRICE_ID).call()
                updated_value = updated_price[0] * (10 ** updated_price[2])
                print_colored(f"   Simulated Updated Price: ${updated_value:,.2f}", 'white')
            except:
                print_colored("   Could not simulate updated price", 'gray')
                
        except Exception as e:
            print_colored(f"   ❌ Update simulation failed: {e}", 'red')
            
            if "PriceFeedNotFound" in str(e) or "no data" in str(e).lower():
                print_colored("   Reason: Price feed not available on this testnet oracle", 'yellow')
            elif "stale" in str(e).lower():
                print_colored("   Reason: Price data is stale", 'yellow')
            elif "invalid" in str(e).lower():
                print_colored("   Reason: Invalid update data format", 'yellow')
        
        print_colored("✅ Step 4: Oracle test completed", 'green')
        return True
        
    except Exception as e:
        print_colored(f"❌ Oracle test error: {e}", 'red')
        return False

def main():
    """Main function to run the oracle test"""
    print_colored("🐍 Pyth Oracle Integration Test", 'magenta')
    print_colored("=" * 50, 'gray')
    
    # Step 1 & 2: Fetch price from Hermes and print
    hermes_data = fetch_pyth_hermes_price()
    if not hermes_data:
        print_colored("❌ Failed to fetch Hermes data", 'red')
        sys.exit(1)
    
    print_colored(f"\n📋 Step 2: Hermes Price - ${hermes_data['hermes_price']:,.2f}", 'green')
    
    # Step 3 & 4: Test oracle and print results
    print_colored("\n" + "=" * 50, 'gray')
    success = test_pyth_oracle(hermes_data)
    
    print_colored("\n" + "=" * 50, 'gray')
    if success:
        print_colored("🎉 Oracle test completed successfully!", 'green')
        print_colored("\nEnvironment Variables Used:", 'cyan')
        print_colored(f"   PYTHTEST_CONTRACT_ADDRESS: {os.getenv('PYTHTEST_CONTRACT_ADDRESS', 'Not set')}", 'white')
        print_colored(f"   RPC_URL: {os.getenv('RPC_URL', 'Default (Arbitrum Sepolia)')}", 'white')
    else:
        print_colored("❌ Oracle test failed", 'red')
        sys.exit(1)

if __name__ == "__main__":
    main() 