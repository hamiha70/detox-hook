#!/usr/bin/env python3
"""
Test script for pool_view.py
============================

This script demonstrates how to use the pool_view.py script
with example pool IDs and different options.
"""

import subprocess
import sys
from pathlib import Path

def test_pool_view():
    """Test the pool_view.py script with different scenarios."""
    
    # Example pool ID (you can replace with actual pool IDs)
    example_pool_id = "0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f"
    
    print("🧪 Testing Pool State Viewer Script")
    print("=" * 50)
    
    # Test 1: Basic pool state query
    print("\n📋 Test 1: Basic pool state query")
    print("-" * 30)
    cmd1 = [
        "python3", "pool_view.py",
        "--pool-id", example_pool_id,
        "--verbose"
    ]
    
    try:
        result1 = subprocess.run(cmd1, capture_output=True, text=True, timeout=30)
        print("Command:", " ".join(cmd1))
        print("Return code:", result1.returncode)
        if result1.stdout:
            print("STDOUT:")
            print(result1.stdout)
        if result1.stderr:
            print("STDERR:")
            print(result1.stderr)
    except subprocess.TimeoutExpired:
        print("❌ Command timed out")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    # Test 2: Pool state with specific tick
    print("\n📋 Test 2: Pool state with specific tick")
    print("-" * 30)
    cmd2 = [
        "python3", "pool_view.py",
        "--pool-id", example_pool_id,
        "--tick", "100",
        "--verbose"
    ]
    
    try:
        result2 = subprocess.run(cmd2, capture_output=True, text=True, timeout=30)
        print("Command:", " ".join(cmd2))
        print("Return code:", result2.returncode)
        if result2.stdout:
            print("STDOUT:")
            print(result2.stdout)
        if result2.stderr:
            print("STDERR:")
            print(result2.stderr)
    except subprocess.TimeoutExpired:
        print("❌ Command timed out")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    # Test 3: Help command
    print("\n📋 Test 3: Help command")
    print("-" * 30)
    cmd3 = ["python3", "pool_view.py", "--help"]
    
    try:
        result3 = subprocess.run(cmd3, capture_output=True, text=True, timeout=10)
        print("Command:", " ".join(cmd3))
        print("Return code:", result3.returncode)
        if result3.stdout:
            print("STDOUT (first 200 chars):")
            print(result3.stdout[:200] + "..." if len(result3.stdout) > 200 else result3.stdout)
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
            "description": "Query pool state with environment RPC URL",
            "command": "python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f"
        },
        {
            "description": "Query pool state with explicit RPC URL",
            "command": "python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --rpc-url https://sepolia-rollup.arbitrum.io/rpc"
        },
        {
            "description": "Query specific tick information",
            "command": "python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --tick 100"
        },
        {
            "description": "Enable verbose output",
            "command": "python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --verbose"
        },
        {
            "description": "Show help",
            "command": "python3 pool_view.py --help"
        }
    ]
    
    for i, example in enumerate(examples, 1):
        print(f"\n{i}. {example['description']}")
        print(f"   {example['command']}")

def main():
    """Main function."""
    print("🔧 Pool State Viewer Test Script")
    print("=" * 50)
    
    # Check if pool_view.py exists
    pool_view_script = Path("pool_view.py")
    if not pool_view_script.exists():
        print("❌ pool_view.py not found in current directory")
        print("💡 Make sure you're in the scripts-python directory")
        return
    
    # Show usage examples
    show_usage_examples()
    
    # Run tests
    test_pool_view()
    
    print("\n✅ Test script completed!")

if __name__ == '__main__':
    main() 