#!/usr/bin/env python3
"""
Test script to identify why provide_liquidity.py is crashing
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
        import argparse
        import json
        from typing import List, Dict, Optional, Any, Tuple
        from pathlib import Path
        from decimal import Decimal, getcontext
        print("✅ Basic imports successful")
        return True
    except Exception as e:
        print(f"❌ Basic imports failed: {e}")
        return False

def test_web3_import():
    """Test web3 import."""
    print("\n🔍 Testing web3 import...")
    
    try:
        from web3 import Web3
        from web3.contract import Contract
        print("✅ Web3 imported successfully")
        
        # Test Web3.is_address
        test_address = "0x1234567890123456789012345678901234567890"
        is_valid = Web3.is_address(test_address)
        print(f"✅ Web3.is_address test: {is_valid}")
        
        return True
    except ImportError:
        print("❌ Web3 not available - this will cause the script to crash")
        print("💡 Install with: pip install web3")
        return False
    except Exception as e:
        print(f"❌ Web3 import failed: {e}")
        return False

def test_load_env_import():
    """Test load_env import."""
    print("\n🔍 Testing load_env import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        from load_env import EnvLoader
        print("✅ EnvLoader imported successfully")
        
        return True
    except ImportError:
        print("⚠️  load_env not available (this is optional)")
        return True
    except Exception as e:
        print(f"❌ load_env import failed: {e}")
        return False

def test_provide_liquidity_import():
    """Test if provide_liquidity.py can be imported."""
    print("\n🔍 Testing provide_liquidity.py import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        import provide_liquidity
        print("✅ provide_liquidity.py imported successfully")
        
        # Test class creation
        provider = provide_liquidity.LiquidityProvider(verbose=True, dry_run=True)
        print("✅ LiquidityProvider instance created")
        
        return True
    except Exception as e:
        print(f"❌ provide_liquidity.py import failed: {e}")
        return False

def test_provide_liquidity_execution():
    """Test if provide_liquidity.py can be executed."""
    print("\n🔍 Testing provide_liquidity.py execution...")
    
    try:
        script_dir = Path(__file__).parent
        script_path = script_dir / "provide_liquidity.py"
        
        # Test help command
        result = subprocess.run(
            ["python3", str(script_path), "--help"],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            print("✅ provide_liquidity.py help command successful")
            return True
        else:
            print(f"❌ provide_liquidity.py help command failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ provide_liquidity.py execution timed out")
        return False
    except Exception as e:
        print(f"❌ provide_liquidity.py execution failed: {e}")
        return False

def test_specific_command():
    """Test the specific command that's crashing."""
    print("\n🔍 Testing specific command...")
    
    try:
        script_dir = Path(__file__).parent
        script_path = script_dir / "provide_liquidity.py"
        
        # Test the exact command that's crashing
        cmd = [
            "python3", str(script_path),
            "0x00cA5716A51f8E48055d03fCadE8CFE0A463Bab6",
            "0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa",
            "--eth-amount", "0.04"
        ]
        
        print(f"📄 Testing command: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        print(f"📈 Exit code: {result.returncode}")
        if result.stdout:
            print(f"📤 STDOUT: {result.stdout[:500]}...")
        if result.stderr:
            print(f"📥 STDERR: {result.stderr}")
        
        if result.returncode == 0:
            print("✅ Specific command successful")
            return True
        else:
            print("❌ Specific command failed")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ Specific command timed out")
        return False
    except Exception as e:
        print(f"❌ Specific command failed: {e}")
        return False

def test_pools_config():
    """Test if pools configuration file exists."""
    print("\n🔍 Testing pools configuration...")
    
    try:
        script_dir = Path(__file__).parent
        pools_config_path = script_dir.parent / "deployments" / "detox-hook-pools.json"
        
        if pools_config_path.exists():
            print(f"✅ Pools config found: {pools_config_path}")
            
            # Try to read the file
            with open(pools_config_path, 'r') as f:
                pools_data = json.load(f)
                print(f"✅ Pools config loaded successfully ({len(pools_data)} pools)")
                
                # Check if the specific pool ID exists
                target_pool_id = "0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa"
                pool_found = any(pool.get('pool_id') == target_pool_id for pool in pools_data)
                
                if pool_found:
                    print(f"✅ Target pool ID found: {target_pool_id}")
                else:
                    print(f"⚠️  Target pool ID not found: {target_pool_id}")
                
            return True
        else:
            print(f"❌ Pools config not found: {pools_config_path}")
            return False
            
    except Exception as e:
        print(f"❌ Pools config test failed: {e}")
        return False

def main():
    """Run all tests."""
    print("🔧 provide_liquidity.py Crash Investigation")
    print("=" * 50)
    
    # Test basic imports
    if not test_basic_imports():
        print("\n❌ Basic imports failed")
        return 1
    
    # Test web3 import
    if not test_web3_import():
        print("\n❌ Web3 import failed - this is likely the main issue")
        return 1
    
    # Test load_env import
    if not test_load_env_import():
        print("\n❌ load_env import failed")
        return 1
    
    # Test provide_liquidity.py import
    if not test_provide_liquidity_import():
        print("\n❌ provide_liquidity.py import failed")
        return 1
    
    # Test provide_liquidity.py execution
    if not test_provide_liquidity_execution():
        print("\n❌ provide_liquidity.py execution failed")
        return 1
    
    # Test pools configuration
    if not test_pools_config():
        print("\n❌ Pools configuration test failed")
        return 1
    
    # Test specific command
    if not test_specific_command():
        print("\n❌ Specific command test failed")
        return 1
    
    print("\n🎉 All tests passed! provide_liquidity.py should work.")
    print("\n💡 Try running:")
    print("   python3 provide_liquidity.py --help")
    print("   python3 provide_liquidity.py --list-pools")
    
    return 0

if __name__ == '__main__':
    sys.exit(main()) 