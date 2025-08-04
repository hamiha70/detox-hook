#!/usr/bin/env python3
"""
Simple test script to demonstrate correct pool_id.py usage
"""

import subprocess
import sys
import json

def test_pool_id():
    """Test pool_id.py with properly escaped JSON"""
    
    # Pool key as a Python dict
    pool_key = {
        "currency0": "0x0000000000000000000000000000000000000000",
        "currency1": "0x9D5A68fDFEcc14683324640D5e835936422a47b1",
        "fee": 400,
        "tickSpacing": 20,
        "hooks": "0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"
    }
    
    # Convert to JSON string
    pool_key_json = json.dumps(pool_key)
    
    print("=== Pool ID Test ===")
    print(f"Pool Key: {pool_key_json}")
    print()
    
    # Test the command
    cmd = [
        "python3", "pool_id.py",
        "--pool-key", pool_key_json,
        "--verbose"
    ]
    
    print("Running command:")
    print(" ".join(cmd))
    print()
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print("✅ SUCCESS:")
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print("❌ ERROR:")
        print(f"Exit code: {e.returncode}")
        print(f"STDOUT: {e.stdout}")
        print(f"STDERR: {e.stderr}")
    except Exception as e:
        print(f"❌ Unexpected error: {e}")

if __name__ == "__main__":
    test_pool_id() 