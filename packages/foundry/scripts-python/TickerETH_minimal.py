#!/usr/bin/env python3
"""
ETH/USDC Price Ticker (Minimal Version)
======================================

Minimal script that outputs ETH/USDC price and tick.
Uses sample data for demonstration.

Usage:
    python3 TickerETH_minimal.py
    python3 TickerETH_minimal.py --verbose
"""

import math
import sys


def price_to_tick(price: float) -> int:
    """Convert price to Uniswap V4 tick."""
    if price <= 0:
        return 0
    tick = math.log(price) / math.log(1.0001)
    return int(tick)


def tick_to_price(tick: int) -> float:
    """Convert Uniswap V4 tick to price."""
    return 1.0001 ** tick


def main():
    """Main function."""
    verbose = "--verbose" in sys.argv
    
    # Sample ETH/USDC price (you can modify this)
    eth_usdc_price = 2500.0
    
    # Convert to tick
    tick = price_to_tick(eth_usdc_price)
    
    if verbose:
        print("📊 ETH/USDC Price Ticker (Minimal)")
        print("=" * 40)
        print(f"💰 Price: {eth_usdc_price:.6f} USDC per ETH")
        print(f"🎯 Tick: {tick:,}")
        print(f"🔄 Tick Price: {tick_to_price(tick):.6f}")
        print(f"📈 Difference: {abs(eth_usdc_price - tick_to_price(tick)):.6f}")
        print("⚠️  Using sample data")
    else:
        # One-line output as requested
        print(f"{eth_usdc_price:.6f} {tick}")


if __name__ == '__main__':
    main() 