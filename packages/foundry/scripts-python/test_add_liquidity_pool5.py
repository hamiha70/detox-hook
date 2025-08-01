#!/usr/bin/env python3
"""
Test script to identify why add_liquidity_pool5.py is crashing
"""

import sys
import os
from pathlib import Path

def test_basic_imports():
    """Test basic imports."""
    print("🔍 Testing basic imports...")
    
    try:
        import os
        import sys
        import json
        import subprocess
        import argparse
        from pathlib import Path
        from typing import Optional
        print("✅ Basic imports successful")
        return True
    except Exception as e:
        print(f"❌ Basic imports failed: {e}")
        return False

def test_load_env_import():
    """Test load_env import."""
    print("\n🔍 Testing load_env import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        from load_env import EnvLoader
        print("✅ EnvLoader imported successfully")
        
        # Test creating an instance
        loader = EnvLoader(verbose=False, dry_run=True)
        print("✅ EnvLoader instance created")
        
        return True
    except Exception as e:
        print(f"❌ load_env import failed: {e}")
        return False

def test_web3_import():
    """Test web3 import."""
    print("\n🔍 Testing web3 import...")
    
    try:
        from web3 import Web3
        print("✅ Web3 imported successfully")
        
        # Test Web3.is_address
        test_address = "0x1234567890123456789012345678901234567890"
        is_valid = Web3.is_address(test_address)
        print(f"✅ Web3.is_address test: {is_valid}")
        
        return True
    except ImportError:
        print("⚠️  Web3 not available (this is optional)")
        return True
    except Exception as e:
        print(f"❌ Web3 import failed: {e}")
        return False

def test_provide_liquidity_script():
    """Test if provide_liquidity.py exists."""
    print("\n🔍 Testing provide_liquidity.py...")
    
    script_dir = Path(__file__).parent
    provide_liquidity_script = script_dir / "provide_liquidity.py"
    
    if not provide_liquidity_script.exists():
        print(f"❌ provide_liquidity.py not found at {provide_liquidity_script}")
        return False
    
    print(f"✅ provide_liquidity.py found at {provide_liquidity_script}")
    
    # Test if it can be imported
    try:
        sys.path.insert(0, str(script_dir))
        import provide_liquidity
        print("✅ provide_liquidity.py imported successfully")
        return True
    except Exception as e:
        print(f"❌ provide_liquidity.py import failed: {e}")
        return False

def test_add_liquidity_pool5_import():
    """Test if add_liquidity_pool5.py can be imported."""
    print("\n🔍 Testing add_liquidity_pool5.py import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        import add_liquidity_pool5
        print("✅ add_liquidity_pool5.py imported successfully")
        
        # Test class creation
        provider = add_liquidity_pool5.Pool1LiquidityProvider(verbose=True)
        print("✅ Pool1LiquidityProvider instance created")
        
        return True
    except Exception as e:
        print(f"❌ add_liquidity_pool5.py import failed: {e}")
        return False

def test_add_liquidity_pool5_execution():
    """Test if add_liquidity_pool5.py can be executed."""
    print("\n🔍 Testing add_liquidity_pool5.py execution...")
    
    try:
        script_dir = Path(__file__).parent
        script_path = script_dir / "add_liquidity_pool5.py"
        
        # Test help command
        result = subprocess.run(
            ["python3", str(script_path), "--help"],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            print("✅ add_liquidity_pool5.py help command successful")
            return True
        else:
            print(f"❌ add_liquidity_pool5.py help command failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ add_liquidity_pool5.py execution timed out")
        return False
    except Exception as e:
        print(f"❌ add_liquidity_pool5.py execution failed: {e}")
        return False

def test_environment_variables():
    """Test environment variable loading."""
    print("\n🔍 Testing environment variables...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        from add_liquidity_pool5 import Pool1LiquidityProvider
        provider = Pool1LiquidityProvider(verbose=True)
        
        wallet = provider.get_env_wallet()
        if wallet:
            print(f"✅ Found wallet in environment: {wallet}")
        else:
            print("⚠️  No wallet found in environment (this is expected)")
        
        return True
    except Exception as e:
        print(f"❌ Environment variable test failed: {e}")
        return False

def main():
    """Run all tests."""
    print("🔧 add_liquidity_pool5.py Crash Investigation")
    print("=" * 50)
    
    # Test basic imports
    if not test_basic_imports():
        print("\n❌ Basic imports failed")
        return 1
    
    # Test load_env import
    if not test_load_env_import():
        print("\n❌ load_env import failed")
        return 1
    
    # Test web3 import
    if not test_web3_import():
        print("\n❌ web3 import failed")
        return 1
    
    # Test provide_liquidity.py
    if not test_provide_liquidity_script():
        print("\n❌ provide_liquidity.py test failed")
        return 1
    
    # Test add_liquidity_pool5.py import
    if not test_add_liquidity_pool5_import():
        print("\n❌ add_liquidity_pool5.py import failed")
        return 1
    
    # Test add_liquidity_pool5.py execution
    if not test_add_liquidity_pool5_execution():
        print("\n❌ add_liquidity_pool5.py execution failed")
        return 1
    
    # Test environment variables
    if not test_environment_variables():
        print("\n❌ Environment variables test failed")
        return 1
    
    print("\n🎉 All tests passed! add_liquidity_pool5.py should work.")
    print("\n💡 Try running:")
    print("   python3 add_liquidity_pool5.py --help")
    print("   python3 add_liquidity_pool5.py --info")
    print("   python3 add_liquidity_pool5.py --dry-run --verbose")
    
    return 0

if __name__ == '__main__':
    sys.exit(main()) 