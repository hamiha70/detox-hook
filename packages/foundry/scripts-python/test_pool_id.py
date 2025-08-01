#!/usr/bin/env python3
"""
Test script for pool_id.py
==========================

This script demonstrates how to use the pool_id.py script
with example pool keys.
"""

import subprocess
import sys
from pathlib import Path

def test_pool_id_generation():
    """Test the pool_id.py script with different pool keys."""
    
    # Example pool keys from the project
    test_cases = [
        {
            "name": "Pool 1 - ETH/MockUSDC, 0.05% fee",
            "pool_key": {
                "currency0": "0x0000000000000000000000000000000000000000",  # ETH
                "currency1": "0x9D5A68fDFEcc14683324640D5e835936422a47b1",  # MockUSDC
                "fee": 500,  # 0.05%
                "tickSpacing": 10,
                "hooks": "0x0000000000000000000000000000000000000000"  # no hooks
            }
        },
        {
            "name": "Pool 2 - ETH/MockUSDC, 0.3% fee",
            "pool_key": {
                "currency0": "0x0000000000000000000000000000000000000000",  # ETH
                "currency1": "0x9D5A68fDFEcc14683324640D5e835936422a47b1",  # MockUSDC
                "fee": 3000,  # 0.3%
                "tickSpacing": 60,
                "hooks": "0x0000000000000000000000000000000000000000"  # no hooks
            }
        },
        {
            "name": "Pool 3 - ETH/MockUSDC, 1% fee",
            "pool_key": {
                "currency0": "0x0000000000000000000000000000000000000000",
                "currency1": "0x9D5A68fDFEcc14683324640D5e835936422a47b1",
                "fee": 500,
                "tickSpacing": 60,
                "hooks": "0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"
            }
        }
    ]
    
    print("🧪 Testing Pool ID Generation")
    print("=" * 50)
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\n📋 Test {i}: {test_case['name']}")
        print("-" * 30)
        
        # Convert pool key to JSON string
        import json
        pool_key_json = json.dumps(test_case['pool_key'])
        
        # Run the pool_id.py script
        cmd = [
            "python3", "pool_id.py",
            "--pool-key", pool_key_json,
            "--verbose"
        ]
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                print("✅ Success!")
                if result.stdout:
                    print("Output:")
                    print(result.stdout)
            else:
                print("❌ Failed!")
                if result.stderr:
                    print("Error:")
                    print(result.stderr)
                    
        except subprocess.TimeoutExpired:
            print("❌ Command timed out")
        except Exception as e:
            print(f"❌ Error: {e}")

def show_usage_examples():
    """Show usage examples for the script."""
    
    print("\n📚 Usage Examples")
    print("=" * 50)
    
    examples = [
        {
            "description": "Basic pool key to ID conversion",
            "command": 'python3 pool_id.py --pool-key \'{"currency0":"0x0000000000000000000000000000000000000000","currency1":"0x9D5A68fDFEcc14683324640D5e835936422a47b1","fee":500,"tickSpacing":10,"hooks":"0x0000000000000000000000000000000000000000"}\''
        },
        {
            "description": "With verbose output",
            "command": 'python3 pool_id.py --pool-key \'{"currency0":"0x0000000000000000000000000000000000000000","currency1":"0x9D5A68fDFEcc14683324640D5e835936422a47b1","fee":3000,"tickSpacing":60,"hooks":"0x0000000000000000000000000000000000000000"}\' --verbose'
        },
        {
            "description": "With custom RPC URL",
            "command": 'python3 pool_id.py --pool-key \'{"currency0":"0x0000000000000000000000000000000000000000","currency1":"0x9D5A68fDFEcc14683324640D5e835936422a47b1","fee":500,"tickSpacing":60,"hooks":"0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"}\' --rpc-url https://sepolia-rollup.arbitrum.io/rpc'
        },
        {
            "description": "Show help",
            "command": "python3 pool_id.py --help"
        }
    ]
    
    for i, example in enumerate(examples, 1):
        print(f"\n{i}. {example['description']}")
        print(f"   {example['command']}")

def main():
    """Main function."""
    print("🔧 Pool ID Generator Test Script")
    print("=" * 50)
    
    # Check if pool_id.py exists
    pool_id_script = Path("pool_id.py")
    if not pool_id_script.exists():
        print("❌ pool_id.py not found in current directory")
        print("💡 Make sure you're in the scripts-python directory")
        return
    
    # Show usage examples
    show_usage_examples()
    
    # Run tests
    test_pool_id_generation()
    
    print("\n✅ Test script completed!")

if __name__ == '__main__':
    main() 