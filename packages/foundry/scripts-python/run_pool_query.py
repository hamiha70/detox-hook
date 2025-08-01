#!/usr/bin/env python3
"""
Run Pool Query - Simple Demonstration
====================================

This script demonstrates how to call query_pool_details.py with the specified parameters.
It shows the exact command needed and can optionally execute it.

Pool: ETH/MockUSDC (0.05%) DetoxHook Pool 3
Ticker: 600
"""

import json

def main():
    """Display the command to run query_pool_details.py with specified parameters."""
    
    # Define the pool key for DetoxHook Pool 3 (ETH/MockUSDC)
    POOL_KEY = {
        "currency0": "0x0000000000000000000000000000000000000000",  # ETH
        "currency1": "0x9D5A68fDFEcc14683324640D5e835936422a47b1",  # MockUSDC
        "fee": 500,                                                # 0.05%
        "tickSpacing": 60,
        "hooks": "0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"     # DetoxHook
    }
    
    # Define the ticker
    TICKER = {
        "tick": 600
    }
    
    # Convert to JSON strings
    pool_key_json = json.dumps(POOL_KEY)
    ticker_json = json.dumps(TICKER)
    
    print("🔍 Pool Query Command")
    print("=" * 50)
    print()
    print("📊 Pool Details:")
    print(f"   • Currency0 (ETH): {POOL_KEY['currency0']}")
    print(f"   • Currency1 (MockUSDC): {POOL_KEY['currency1']}")
    print(f"   • Fee: {POOL_KEY['fee']} (0.05%)")
    print(f"   • Tick Spacing: {POOL_KEY['tickSpacing']}")
    print(f"   • Hook (DetoxHook): {POOL_KEY['hooks']}")
    print(f"   • Target Tick: {TICKER['tick']}")
    print()
    
    print("🚀 Command to Execute:")
    print("─" * 50)
    print("cd /packages/foundry/scripts-python")
    print()
    command = f"python3 query_pool_details.py --pool-key '{pool_key_json}' --ticker '{ticker_json}' --verbose"
    print(command)
    print()
    
    print("🔄 Alternative (JSON output):")
    print("─" * 50)
    json_command = f"python3 query_pool_details.py --pool-key '{pool_key_json}' --ticker '{ticker_json}' --json"
    print(json_command)
    print()
    
    print("📋 Copy-Paste Ready Commands:")
    print("─" * 50)
    print("# Basic query:")
    print(f'python3 query_pool_details.py --pool-key \'{pool_key_json}\' --ticker \'{ticker_json}\'')
    print()
    print("# Verbose output:")
    print(f'python3 query_pool_details.py --pool-key \'{pool_key_json}\' --ticker \'{ticker_json}\' --verbose')
    print()
    print("# JSON output:")
    print(f'python3 query_pool_details.py --pool-key \'{pool_key_json}\' --ticker \'{ticker_json}\' --json')
    print()
    
    print("💡 Pool Key JSON (formatted):")
    print("─" * 50)
    print(json.dumps(POOL_KEY, indent=2))
    print()
    
    print("🎯 Ticker JSON (formatted):")
    print("─" * 50)
    print(json.dumps(TICKER, indent=2))
    print()
    
    print("ℹ️  This queries DetoxHook Pool 3 (ETH/MockUSDC 0.05%) at tick 600")
    print("   Run the commands above from the scripts-python directory!")

if __name__ == '__main__':
    main() 