#!/usr/bin/env python3
"""
Minimal test to identify crash cause
"""

import sys
import os
from pathlib import Path

def test_basic():
    """Test basic functionality."""
    print("🔍 Testing basic functionality...")
    
    try:
        # Test imports
        import os
        import sys
        import subprocess
        import argparse
        import time
        from pathlib import Path
        from typing import Dict, Any, Optional, List
        print("✅ All imports successful")
        
        # Test Path
        script_dir = Path(__file__).parent
        print(f"✅ Script directory: {script_dir}")
        
        # Test environment variables
        test_var = os.getenv("TEST_VAR", "not_set")
        print(f"✅ Environment test: {test_var}")
        
        return True
        
    except Exception as e:
        print(f"❌ Basic test failed: {e}")
        return False

def test_script_import():
    """Test if move_circular_simple.py can be imported."""
    print("\n🔍 Testing move_circular_simple.py import...")
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        
        import move_circular_simple
        print("✅ move_circular_simple.py imported successfully")
        
        # Test class creation
        transfer = move_circular_simple.SimpleCircularTransfer(verbose=True, dry_run=True)
        print("✅ SimpleCircularTransfer instance created")
        
        return True
        
    except Exception as e:
        print(f"❌ move_circular_simple.py import failed: {e}")
        return False

def test_script_execution():
    """Test if move_circular_simple.py can be executed."""
    print("\n🔍 Testing move_circular_simple.py execution...")
    
    try:
        script_dir = Path(__file__).parent
        script_path = script_dir / "move_circular_simple.py"
        
        # Test help command
        result = subprocess.run(
            ["python3", str(script_path), "--help"],
            cwd=script_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            print("✅ move_circular_simple.py help command successful")
            return True
        else:
            print(f"❌ move_circular_simple.py help command failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        print("❌ move_circular_simple.py execution timed out")
        return False
    except Exception as e:
        print(f"❌ move_circular_simple.py execution failed: {e}")
        return False

def main():
    """Run all tests."""
    print("🔧 Crash Investigation Test")
    print("=" * 50)
    
    # Test basic functionality
    if not test_basic():
        print("\n❌ Basic functionality failed")
        return 1
    
    # Test script import
    if not test_script_import():
        print("\n❌ Script import failed")
        return 1
    
    # Test script execution
    if not test_script_execution():
        print("\n❌ Script execution failed")
        return 1
    
    print("\n🎉 All tests passed! Script should work.")
    return 0

if __name__ == '__main__':
    sys.exit(main()) 