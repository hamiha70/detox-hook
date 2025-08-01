#!/usr/bin/env python3
"""
Test ETH/USDC Price Ticker
==========================

This script demonstrates the TickerETH.py functionality.
"""

import subprocess
import sys
from pathlib import Path


def main():
    """Demonstrate TickerETH.py functionality."""
    
    script_dir = Path(__file__).parent
    ticker_script = script_dir / "TickerETH.py"
    
    print("📊 ETH/USDC Price Ticker Demo")
    print("=" * 40)
    print()
    
    print("🎯 What TickerETH.py does:")
    print("   1. Fetches ETH/USDC price from Pyth Network")
    print("   2. Converts price to Uniswap V4 tick")
    print("   3. Outputs: price tick (one line)")
    print()
    
    print("🚀 Usage Examples:")
    print("─" * 50)
    print("# Basic usage (one-line output):")
    print("python3 TickerETH.py")
    print("# Output: 2500.123456 78644")
    print()
    
    print("# Verbose output:")
    print("python3 TickerETH.py --verbose")
    print()
    
    print("# JSON output:")
    print("python3 TickerETH.py --json")
    print()
    
    print("# Test tick conversion:")
    print("python3 TickerETH.py --test")
    print()
    
    print("# Test specific price:")
    print("python3 TickerETH.py --price 2500")
    print()
    
    print("💡 Key Features:")
    print("   • Real-time Pyth Network price feeds")
    print("   • Price validation (freshness, confidence)")
    print("   • Accurate Uniswap V4 tick calculation")
    print("   • One-line output for scripting")
    print("   • JSON output for programmatic use")
    print()
    
    print("📋 Price Feed IDs Used:")
    print("   • ETH/USD: 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace")
    print("   • USDC/USD: 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a")
    print()
    
    print("🔧 Tick Calculation:")
    print("   • Formula: tick = log(price) / log(1.0001)")
    print("   • Price = 1.0001^tick")
    print("   • Precision: 1.0001 per tick")
    print()
    
    # Optionally run the test
    if len(sys.argv) > 1 and sys.argv[1] == "--run":
        print("🔄 Running TickerETH.py test...")
        print()
        
        try:
            result = subprocess.run(
                ["python3", str(ticker_script), "--test"],
                cwd=script_dir,
                capture_output=False,
                text=True
            )
            print(f"\n📈 Test completed with exit code: {result.returncode}")
        except Exception as e:
            print(f"❌ Error running test: {e}")
    
    print("✅ TickerETH.py is ready to use!")
    print("   Run: python3 TickerETH.py")


if __name__ == '__main__':
    main() 