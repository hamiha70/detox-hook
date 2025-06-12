#!/usr/bin/env python3
"""
Oracle Fix Script for Uniswap V4 Pyth Integration
Diagnoses and fixes the 0x14aebe68 (PriceFeedNotFound) error

This script:
1. Diagnoses the exact error cause
2. Fetches fresh Hermes API data with proper fee calculation  
3. Updates the price feed with required fees
4. Verifies the fix by testing price reading
"""

import os
import json
import requests
from web3 import Web3
from eth_account import Account
import time
import sys

# Configuration
ARBITRUM_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc"
PYTH_HERMES_API = "https://hermes.pyth.network"
ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"
PYTH_ORACLE_ADDRESS = "0x8D254a21b3C86D32F7179855531CE99164721933"

# Web3 setup
w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC))

# Load wallet address and private key from environment
deployment_wallet = os.getenv('DEPLOYMENT_WALLET')
deployment_key = os.getenv('DEPLOYMENT_KEY')

if not deployment_key:
    print("❌ Error: DEPLOYMENT_KEY environment variable not set")
    print("💡 Set it with: export DEPLOYMENT_KEY='your-private-key-here'")
    sys.exit(1)

if not deployment_wallet:
    print("❌ Error: DEPLOYMENT_WALLET environment variable not set")
    print("💡 Set it with: export DEPLOYMENT_WALLET='your-wallet-address-here'")
    sys.exit(1)

try:
    # Clean the private key - remove 0x prefix and whitespace
    clean_key = deployment_key.strip()
    if clean_key.startswith('0x'):
        clean_key = clean_key[2:]
    
    print(f"🔍 Debug info:")
    print(f"   Key length: {len(clean_key)}")
    print(f"   Key starts with: {clean_key[:10]}...")
    
    # Validate key format
    if len(clean_key) != 64:
        print(f"❌ Error: Private key should be 64 hex characters (got {len(clean_key)})")
        sys.exit(1)
    
    if not all(c in '0123456789abcdefABCDEF' for c in clean_key):
        print(f"❌ Error: Private key contains non-hex characters")
        sys.exit(1)
    
    # Load account from cleaned private key
    account = Account.from_key('0x' + clean_key)
    
    # Verify the wallet address matches
    if account.address.lower() != deployment_wallet.lower():
        print(f"❌ Error: Wallet address mismatch!")
        print(f"   DEPLOYMENT_WALLET: {deployment_wallet}")
        print(f"   Private key address: {account.address}")
        sys.exit(1)
    
    print(f"📍 Using deployment wallet: {account.address}")
    print(f"✅ Wallet address verification passed")
    
except Exception as e:
    print(f"❌ Error loading deployment account: {e}")
    print(f"❌ Exception type: {type(e).__name__}")
    sys.exit(1)

# Store for use throughout the script
private_key = deployment_key

# Pyth Oracle ABI (minimal)
PYTH_ABI = [
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
    }
]

def diagnose_error():
    print("\n🔍 DIAGNOSING ORACLE ERROR")
    print("=" * 50)
    print("Error signature: 0x14aebe68")
    print("📋 Error analysis:")
    print("   - Error: PriceFeedNotFound()")
    print("   - Cause: Price feed ID not initialized in Pyth contract")
    print("   - Solution: Update price feed first, then read")
    print()

def fetch_hermes_data():
    print("🐍 FETCHING FRESH PYTH DATA")
    print("=" * 50)
    print("🔍 Debug - Starting fetch_hermes_data function")
    
    url = f"{PYTH_HERMES_API}/v2/updates/price/latest"
    params = {
        'ids[]': ETH_USD_PRICE_ID,
        'encoding': 'hex'
    }
    
    try:
        print(f"📡 Fetching from: {url}")
        response = requests.get(url, params=params, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        print(f"✅ Response received: {len(data.get('binary', {}).get('data', []))} updates")
        
        if not data.get('binary') or not data.get('binary').get('data'):
            raise ValueError("No binary data in response")
            
        update_data = data['binary']['data'][0]
        parsed_data = data.get('parsed', [{}])[0]
        
        price_info = parsed_data.get('price', {})
        if price_info:
            try:
                # Pyth returns prices as strings, need to convert to int/float
                price_val = int(price_info.get('price', '0'))
                conf_val = int(price_info.get('conf', '0'))
                expo = int(price_info.get('expo', -8))
                publish_time = price_info.get('publish_time', 0)
                
                # Calculate actual price using expo
                actual_price = price_val * (10 ** expo)
                actual_conf = conf_val * (10 ** expo)
                    
                print(f"📊 Current ETH/USD Price: ${actual_price:.2f}")
                print(f"📊 Confidence: ±${actual_conf:.2f}")
                print(f"📊 Publish time: {publish_time}")
            except Exception as price_error:
                print(f"❌ Error parsing price data: {price_error}")
                print(f"📊 Raw price info: {price_info}")
        else:
            print("📊 Price data not available in parsed response")
        
        # Convert hex string to bytes for smart contract
        print(f"🔍 Debug - Raw update_data type: {type(update_data)}")
        print(f"🔍 Debug - Raw update_data length: {len(update_data)}")
        print(f"🔍 Debug - Raw update_data starts with: {update_data[:20]}...")
        
        if update_data.startswith('0x'):
            update_data_bytes = bytes.fromhex(update_data[2:])
        else:
            update_data_bytes = bytes.fromhex(update_data)
        
        print(f"🔍 Debug - Converted bytes type: {type(update_data_bytes)}")
        print(f"🔍 Debug - Converted bytes length: {len(update_data_bytes)}")
        
        result = [update_data_bytes]
        print(f"🔍 Debug - Final return type: {type(result)}")
        print(f"🔍 Debug - Final return length: {len(result)}")
        print(f"🔍 Debug - Final return element type: {type(result[0])}")
        return result
        
    except Exception as e:
        print(f"❌ Error fetching Hermes data: {e}")
        import traceback
        print("Full traceback:")
        traceback.print_exc()
        return None

def test_price_reading():
    print("\n🧪 TESTING PRICE READING")
    print("=" * 50)
    
    try:
        pyth_contract = w3.eth.contract(
            address=w3.to_checksum_address(PYTH_ORACLE_ADDRESS),
            abi=PYTH_ABI
        )
        
        print("📖 Attempting to read ETH/USD price...")
        price_data = pyth_contract.functions.getPriceUnsafe(ETH_USD_PRICE_ID).call()
        
        price = price_data[0]
        conf = price_data[1]
        expo = price_data[2]
        publish_time = price_data[3]
        
        actual_price = price * (10 ** expo)
        actual_conf = conf * (10 ** expo)
        
        print(f"✅ SUCCESS! Price reading works!")
        print(f"📊 ETH/USD Price: ${actual_price:.2f}")
        print(f"📊 Confidence: ±${actual_conf:.2f}")
        print(f"📊 Publish time: {publish_time}")
        print(f"📊 Age: {int(time.time()) - publish_time} seconds")
        
        return True
        
    except Exception as e:
        error_str = str(e)
        print(f"❌ Price reading failed: {e}")
        
        if "0x14aebe68" in error_str:
            print("📋 Error code: 0x14aebe68 (PriceFeedNotFound)")
        
        return False

def update_price_feed(update_data):
    print("\n💰 UPDATING PRICE FEED")
    print("=" * 50)
    
    try:
        pyth_contract = w3.eth.contract(
            address=w3.to_checksum_address(PYTH_ORACLE_ADDRESS),
            abi=PYTH_ABI
        )
        
        # Debug: Check the type and format of update_data
        print(f"🔍 Debug - Update data type: {type(update_data)}")
        print(f"🔍 Debug - Update data length: {len(update_data)}")
        if len(update_data) > 0:
            print(f"🔍 Debug - First element type: {type(update_data[0])}")
            if isinstance(update_data[0], bytes):
                print(f"🔍 Debug - First element length: {len(update_data[0])} bytes")
            else:
                print(f"🔍 Debug - First element value: {str(update_data[0])[:100]}...")
        
        # Calculate update fee
        print("🔢 Calculating update fee...")
        fee = pyth_contract.functions.getUpdateFee(update_data).call()
        fee_eth = w3.from_wei(fee, 'ether')
        print(f"📊 Update fee: {fee_eth} ETH ({fee} wei)")
        
        if fee == 0:
            print("⚠️  Warning: Update fee is 0, this might be correct for Arbitrum Sepolia")
        
        # Build transaction
        print("🏗️  Building update transaction...")
        nonce = w3.eth.get_transaction_count(account.address)
        
        # Estimate gas for the update transaction
        try:
            gas_estimate = pyth_contract.functions.updatePriceFeeds(update_data).estimate_gas({
                'from': account.address,
                'value': fee
            })
            print(f"📊 Gas estimate: {gas_estimate:,}")
        except Exception as e:
            print(f"⚠️  Gas estimation failed: {e}")
            gas_estimate = 150000  # Default fallback
        
        # Get current gas price
        gas_price = w3.eth.gas_price
        print(f"📊 Gas price: {w3.from_wei(gas_price, 'gwei')} gwei")
        
        # Build transaction
        transaction = pyth_contract.functions.updatePriceFeeds(update_data).build_transaction({
            'from': account.address,
            'value': fee,
            'gas': gas_estimate + 50000,  # Add buffer
            'gasPrice': gas_price,
            'nonce': nonce
        })
        
        print(f"📊 Transaction value: {w3.from_wei(transaction['value'], 'ether')} ETH")
        print(f"📊 Max transaction cost: {w3.from_wei(transaction['gas'] * transaction['gasPrice'] + transaction['value'], 'ether')} ETH")
        
        # Check balance
        balance = w3.eth.get_balance(account.address)
        required = transaction['gas'] * transaction['gasPrice'] + transaction['value']
        
        print(f"📊 Account balance: {w3.from_wei(balance, 'ether')} ETH")
        print(f"📊 Required for tx: {w3.from_wei(required, 'ether')} ETH")
        
        if balance < required:
            print(f"❌ Insufficient balance! Need {w3.from_wei(required - balance, 'ether')} more ETH")
            return False
        
        # Sign and send transaction
        print("✍️  Signing transaction...")
        signed_txn = w3.eth.account.sign_transaction(transaction, private_key=private_key)
        
        print("📤 Sending update transaction...")
        tx_hash = w3.eth.send_raw_transaction(signed_txn.raw_transaction)
        print(f"📋 Transaction hash: {tx_hash.hex()}")
        
        # Wait for confirmation
        print("⏳ Waiting for confirmation...")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
        
        if receipt.status == 1:
            print(f"✅ Price feed updated successfully!")
            print(f"📋 Block: {receipt.blockNumber}")
            print(f"📋 Gas used: {receipt.gasUsed:,}")
            return True
        else:
            print(f"❌ Transaction failed")
            print(f"📋 Block: {receipt.blockNumber}")
            print(f"📋 Gas used: {receipt.gasUsed:,}")
            print(f"📋 Transaction hash: {tx_hash.hex()}")
            print(f"📋 Check transaction on Arbitrum Sepolia explorer:")
            print(f"📋 https://sepolia.arbiscan.io/tx/{tx_hash.hex()}")
            return False
            
    except Exception as e:
        print(f"❌ Error updating price feed: {e}")
        return False

def main():
    print("🔧 PYTH ORACLE FIX TOOL")
    print("=" * 50)
    print(f"🌐 Network: Arbitrum Sepolia")
    print(f"🏛️  Oracle: {PYTH_ORACLE_ADDRESS}")
    print(f"📊 Price Feed: ETH/USD")
    print(f"🔑 Account: {account.address}")
    print()
    
    # Step 1: Diagnose error
    diagnose_error()
    
    # Step 2: Test current state
    print("🧪 TESTING CURRENT STATE")
    print("=" * 50)
    if test_price_reading():
        print("✅ Oracle is already working! No fix needed.")
        return
    else:
        print("📋 Confirmed: Price feed needs updating")
    print()
    
    # Step 3: Fetch fresh data
    update_data = fetch_hermes_data()
    if not update_data:
        print("❌ Failed to fetch update data")
        return
    print()
    
    # Step 4: Update price feed
    if update_price_feed(update_data):
        print()
        # Step 5: Verify fix
        print("🔄 VERIFYING FIX")
        print("=" * 50)
        time.sleep(2)  # Give network time to propagate
        
        if test_price_reading():
            print("\n🎉 SUCCESS! Oracle fix completed successfully!")
            print("✅ Price feed is now working correctly")
            print("✅ Ready for Uniswap V4 integration")
        else:
            print("\n⚠️  Fix may need more time to propagate")
            print("🔄 Try testing again in a few minutes")
    else:
        print("\n❌ Fix failed - please try again")

if __name__ == "__main__":
    main() 