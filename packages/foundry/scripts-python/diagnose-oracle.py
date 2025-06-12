#!/usr/bin/env python3
"""
Pyth Oracle Diagnostic Script
Analyzes the oracle error and checks price feed availability
"""

from web3 import Web3
import requests

# Configuration
PYTH_CONTRACT = "0x8D254a21b3C86D32F7179855531CE99164721933"
ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"
RPC_URL = "https://sepolia-rollup.arbitrum.io/rpc"
HERMES_API = "https://hermes.pyth.network"

def check_pyth_contract():
    """Check if Pyth contract exists and what functions it has"""
    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    
    if not w3.is_connected():
        print("❌ Failed to connect to RPC")
        return
    
    print(f"✅ Connected to Arbitrum Sepolia (Chain ID: {w3.eth.chain_id})")
    
    # Check contract
    contract_checksum = w3.to_checksum_address(PYTH_CONTRACT)
    code = w3.eth.get_code(contract_checksum)
    
    if code == '0x':
        print(f"❌ No contract at {contract_checksum}")
        return False
    
    print(f"✅ Contract exists: {len(code)} bytes at {contract_checksum}")
    
    # Check for common Pyth function selectors
    code_hex = code.hex()
    pyth_selectors = {
        "84b0196e": "eip712Domain()",
        "45884127": "getPrice(bytes32)",
        "83589c95": "getPriceUnsafe(bytes32)", 
        "eb52640b": "getUpdateFee(bytes[])",
        "a8b161e8": "updatePriceFeeds(bytes[])",
        "6af1de80": "parsePriceFeedUpdates(bytes[],bytes32[],uint64,uint64)"
    }
    
    found_functions = []
    for selector, func_name in pyth_selectors.items():
        if selector in code_hex:
            found_functions.append(f"✅ {selector} ({func_name})")
    
    if found_functions:
        print("📋 Pyth functions found:")
        for func in found_functions:
            print(f"   {func}")
    else:
        print("❌ No standard Pyth functions found")
        return False
    
    return True

def check_price_feed_availability():
    """Check if the ETH/USD price feed is available in Hermes"""
    try:
        url = f"{HERMES_API}/v2/updates/price/latest"
        params = {
            'ids[]': ETH_USD_PRICE_ID,
            'encoding': 'hex'
        }
        
        print(f"\n🔍 Checking Hermes API for price feed: {ETH_USD_PRICE_ID}")
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        
        if data.get('parsed') and len(data['parsed']) > 0:
            price_data = data['parsed'][0]
            price_obj = price_data['price']
            price_raw = int(price_obj['price'])
            expo = int(price_obj['expo'])
            actual_price = price_raw * (10 ** expo)
            
            print(f"✅ Price feed available in Hermes:")
            print(f"   Price: ${actual_price:.2f}")
            print(f"   Publish Time: {price_data['price']['publish_time']}")
            print(f"   Update Data: {len(data['binary']['data'][0])} chars")
            return True
        else:
            print(f"❌ Price feed not found in Hermes response")
            return False
            
    except Exception as e:
        print(f"❌ Hermes API error: {e}")
        return False

def analyze_error_code():
    """Analyze the specific error code 0x14aebe68"""
    error_code = "0x14aebe68"
    print(f"\n🔬 Analyzing error code: {error_code}")
    
    # Common Pyth error patterns
    pyth_errors = {
        "0x14aebe68": "PriceFeedNotFound or InvalidPriceId",
        "0x025dbccd": "InsufficientFee", 
        "0x0bd4f4b2": "InvalidUpdateData",
        "0x559e2d98": "InvalidWormholeVaa"
    }
    
    if error_code in pyth_errors:
        print(f"🎯 Likely meaning: {pyth_errors[error_code]}")
        
        if "PriceFeedNotFound" in pyth_errors[error_code]:
            print(f"💡 This suggests:")
            print(f"   - Price feed {ETH_USD_PRICE_ID} not registered in contract")
            print(f"   - Wrong price feed ID being used")
            print(f"   - Contract needs price feed to be initialized first")
    else:
        print(f"❓ Unknown error code")

def main():
    print("🔧 Pyth Oracle Diagnostic")
    print("=" * 50)
    
    # Step 1: Check contract
    if not check_pyth_contract():
        print("❌ Contract check failed")
        return
    
    # Step 2: Check Hermes API
    if not check_price_feed_availability():
        print("❌ Hermes API check failed")
        return
    
    # Step 3: Analyze error
    analyze_error_code()
    
    print("\n🏁 DIAGNOSIS COMPLETE")
    print("Recommended next steps:")
    print("1. Verify the price feed ID is correct for this Pyth contract")
    print("2. Check if price feed needs to be registered/initialized")
    print("3. Try updating price feed first before reading")

if __name__ == "__main__":
    main() 