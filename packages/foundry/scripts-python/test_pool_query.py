#!/usr/bin/env python3
"""
Test Pool Query Script
=====================

This script calls query_pool_details.py with predefined parameters for testing.
It queries DetoxHook Pool 3 (ETH/MockUSDC 0.05%) at tick 600.

Usage:
    python3 test_pool_query.py [--json] [--verbose]
"""

import os
import sys
import json
import subprocess
import argparse
from pathlib import Path


def main():
    """Main function to call query_pool_details.py with predefined parameters."""
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description="Test the pool query script with predefined parameters",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output including errors'
    )
    
    args = parser.parse_args()
    
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
    
    # Get the directory of this script
    script_dir = Path(__file__).parent
    query_script = script_dir / "query_pool_details.py"
    
    # Check if the query script exists
    if not query_script.exists():
        print(f"❌ Error: query_pool_details.py not found at {query_script}")
        return 1
    
    # Build the command
    cmd = [
        "python3", 
        str(query_script),
        "--pool-key", pool_key_json,
        "--ticker", ticker_json
    ]
    
    # Add optional flags
    if args.json:
        cmd.append("--json")
    
    if args.verbose:
        cmd.append("--verbose")
    
    # Display what we're doing
    print("🔍 Testing Pool Query Script")
    print("=" * 40)
    print(f"📊 Pool: ETH/MockUSDC (0.05%)")
    print(f"🎯 Ticker: 600")
    print(f"🪝 Hook: DetoxHook")
    print(f"📄 Command: {' '.join(cmd)}")
    print()
    
    # Execute the command
    try:
        result = subprocess.run(
            cmd,
            cwd=script_dir,
            capture_output=False,  # Let output go directly to terminal
            text=True
        )
        
        print(f"\n📈 Query completed with exit code: {result.returncode}")
        return result.returncode
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Command failed with exit code {e.returncode}")
        if e.stdout:
            print("STDOUT:", e.stdout)
        if e.stderr:
            print("STDERR:", e.stderr)
        return e.returncode
    
    except FileNotFoundError:
        print("❌ Error: python3 command not found")
        return 1
    
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return 1


if __name__ == '__main__':
    sys.exit(main()) 