#!/usr/bin/env python3
"""
Test script to check if imports are working correctly
"""

import sys
import os
from pathlib import Path

def test_basic_imports():
    """Test basic Python imports."""
    print("🔍 Testing basic imports...")
    
    try:
        import os
        print("✅ os imported")
    except ImportError as e:
        print(f"❌ os import failed: {e}")
        return False
    
    try:
        import sys
        print("✅ sys imported")
    except ImportError as e:
        print(f"❌ sys import failed: {e}")
        return False
    
    try:
        import subprocess
        print("✅ subprocess imported")
    except ImportError as e:
        print(f"❌ subprocess import failed: {e}")
        return False
    
    try:
        import argparse
        print("✅ argparse imported")
    except ImportError as e:
        print(f"❌ argparse import failed: {e}")
        return False
    
    try:
        import time
        print("✅ time imported")
    except ImportError as e:
        print(f"❌ time import failed: {e}")
        return False
    
    try:
        from pathlib import Path
        print("✅ pathlib.Path imported")
    except ImportError as e:
        print(f"❌ pathlib.Path import failed: {e}")
        return False
    
    try:
        from typing import Dict, Any, Optional, List
        print("✅ typing imported")
    except ImportError as e:
        print(f"❌ typing import failed: {e}")
        return False
    
    return True

def test_load_env_import():
    """Test if load_env.py can be imported."""
    print("\n🔍 Testing load_env.py import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        from load_env import EnvLoader
        print("✅ EnvLoader imported successfully")
        
        # Test creating an instance
        loader = EnvLoader(verbose=True, dry_run=True)
        print("✅ EnvLoader instance created")
        
        return True
        
    except Exception as e:
        print(f"❌ load_env.py import failed: {e}")
        return False

def test_move_mock_import():
    """Test if move_mock.py can be imported."""
    print("\n🔍 Testing move_mock.py import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        import move_mock
        print("✅ move_mock.py imported successfully")
        
        return True
        
    except Exception as e:
        print(f"❌ move_mock.py import failed: {e}")
        return False

def test_check_balances_import():
    """Test if check_balances.py can be imported."""
    print("\n🔍 Testing check_balances.py import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        import check_balances
        print("✅ check_balances.py imported successfully")
        
        return True
        
    except Exception as e:
        print(f"❌ check_balances.py import failed: {e}")
        return False

def test_script_syntax():
    """Test if the scripts have valid syntax."""
    print("\n🔍 Testing script syntax...")
    
    script_dir = Path(__file__).parent
    scripts_to_test = [
        "move_circular.py",
        "move_circular_simple.py",
        "load_env.py",
        "move_mock.py",
        "check_balances.py"
    ]
    
    all_valid = True
    
    for script_name in scripts_to_test:
        script_path = script_dir / script_name
        if script_path.exists():
            try:
                # Try to compile the script
                with open(script_path, 'r') as f:
                    compile(f.read(), script_name, 'exec')
                print(f"✅ {script_name} syntax is valid")
            except SyntaxError as e:
                print(f"❌ {script_name} has syntax error: {e}")
                all_valid = False
            except Exception as e:
                print(f"❌ {script_name} has error: {e}")
                all_valid = False
        else:
            print(f"⚠️  {script_name} not found")
    
    return all_valid

def main():
    """Run all tests."""
    print("🔧 Script Import and Syntax Test")
    print("=" * 50)
    
    # Test basic imports
    if not test_basic_imports():
        print("\n❌ Basic imports failed")
        return 1
    
    # Test load_env.py import
    if not test_load_env_import():
        print("\n❌ load_env.py import failed")
        return 1
    
    # Test move_mock.py import
    if not test_move_mock_import():
        print("\n❌ move_mock.py import failed")
        return 1
    
    # Test check_balances.py import
    if not test_check_balances_import():
        print("\n❌ check_balances.py import failed")
        return 1
    
    # Test script syntax
    if not test_script_syntax():
        print("\n❌ Script syntax test failed")
        return 1
    
    print("\n🎉 All tests passed! Scripts should work correctly.")
    print("\n💡 Try running:")
    print("   python3 move_circular_simple.py --help")
    print("   python3 move_circular_simple.py --dry-run --verbose")
    
    return 0

if __name__ == '__main__':
    sys.exit(main()) 