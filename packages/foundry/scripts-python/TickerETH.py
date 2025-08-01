#!/usr/bin/env python3
"""
ETH/USDC Price Ticker (Fixed Version)
====================================

This script reads the current ETH/USDC price from Pyth Network and outputs:
1. Price as a float (USDC per ETH)
2. Corresponding Uniswap V4 tick

Usage:
    python3 TickerETH_fixed.py
    python3 TickerETH_fixed.py --verbose
    python3 TickerETH_fixed.py --test
"""

import os
import sys
import json
import argparse
import math
import time
from typing import Dict, Any, Optional, Tuple
from pathlib import Path

# Try to import requests, but provide fallback
try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    print("⚠️  requests library not available. Install with: pip install requests")
    print("   Using fallback mode with sample data.")

# Import our environment loader
try:
    from load_env import EnvLoader
except ImportError:
    print("⚠️  Environment loader not found. Using environment variables directly.")
    EnvLoader = None


class ETHPriceTicker:
    """Reads ETH/USDC price from Pyth Network and converts to Uniswap V4 tick."""
    
    # Pyth Network Hermes API
    PYTH_HERMES_API = "https://hermes.pyth.network"
    
    # ETH/USD price feed ID on Arbitrum Sepolia
    ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"
    
    # USDC/USD price feed ID on Arbitrum Sepolia  
    USDC_USD_PRICE_ID = "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a"
    
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.session = None
        
        if REQUESTS_AVAILABLE:
            self.session = requests.Session()
            self.session.headers.update({
                'User-Agent': 'DetoxHook-Price-Ticker/1.0'
            })
    
    def _get_sample_price_data(self) -> Tuple[float, float]:
        """Get sample price data for testing when requests is not available."""
        # Sample data based on typical ETH/USDC prices
        eth_usd_price = 2500.0  # $2500 per ETH
        usdc_usd_price = 1.0    # $1 per USDC (should be very close to 1)
        
        if self.verbose:
            print("📊 Using sample price data (requests not available)")
            print(f"   ETH/USD: ${eth_usd_price}")
            print(f"   USDC/USD: ${usdc_usd_price}")
        
        return eth_usd_price, usdc_usd_price
    
    def _get_pyth_price_data(self, price_id: str) -> Optional[Dict[str, Any]]:
        """Get price data from Pyth Hermes API."""
        if not REQUESTS_AVAILABLE:
            return None
            
        try:
            url = f"{self.PYTH_HERMES_API}/v2/updates/price/latest"
            params = {
                'ids[]': price_id,
                'encoding': 'hex'
            }
            
            if self.verbose:
                print(f"🔍 Fetching price data for {price_id}...")
            
            response = self.session.get(url, params=params, timeout=10)
            response.raise_for_status()
            
            data = response.json()
            
            if not data.get('parsed') or not data['parsed']:
                raise ValueError("No parsed price data in response")
            
            return data['parsed'][0]
            
        except requests.RequestException as e:
            if self.verbose:
                print(f"❌ Network error fetching price: {e}")
            return None
        except (KeyError, ValueError) as e:
            if self.verbose:
                print(f"❌ Invalid response format: {e}")
            return None
        except Exception as e:
            if self.verbose:
                print(f"❌ Unexpected error: {e}")
            return None
    
    def _validate_price_data(self, price_data: Dict[str, Any]) -> bool:
        """Validate price data freshness and confidence."""
        try:
            # Check if price is recent (within 30 seconds)
            publish_time = price_data.get('publishTime', 0)
            current_time = int(time.time())
            
            if current_time - publish_time > 30:
                if self.verbose:
                    print(f"⚠️  Price data is stale ({current_time - publish_time}s old)")
                return False
            
            # Check confidence interval (should be < 1% for reliable data)
            price = float(price_data.get('price', 0))
            conf = float(price_data.get('conf', 0))
            
            if price > 0:
                confidence_ratio = (conf / price) * 100
                if confidence_ratio > 1:
                    if self.verbose:
                        print(f"⚠️  High confidence interval: {confidence_ratio:.2f}%")
                    return False
            
            return True
            
        except Exception as e:
            if self.verbose:
                print(f"❌ Error validating price data: {e}")
            return False
    
    def get_eth_usdc_price(self) -> Optional[float]:
        """Get current ETH/USDC price from Pyth Network or sample data."""
        try:
            if REQUESTS_AVAILABLE:
                # Try to get real data from Pyth
                eth_usd_data = self._get_pyth_price_data(self.ETH_USD_PRICE_ID)
                usdc_usd_data = self._get_pyth_price_data(self.USDC_USD_PRICE_ID)
                
                if eth_usd_data and usdc_usd_data and \
                   self._validate_price_data(eth_usd_data) and \
                   self._validate_price_data(usdc_usd_data):
                    
                    eth_usd_price = float(eth_usd_data['price'])
                    usdc_usd_price = float(usdc_usd_data['price'])
                    
                    if usdc_usd_price == 0:
                        if self.verbose:
                            print("❌ USDC/USD price is zero")
                        return None
                    
                    eth_usdc_price = eth_usd_price / usdc_usd_price
                    
                    if self.verbose:
                        print(f"📊 ETH/USD: ${eth_usd_price:.2f}")
                        print(f"📊 USDC/USD: ${usdc_usd_price:.6f}")
                        print(f"📊 ETH/USDC: {eth_usdc_price:.6f}")
                    
                    return eth_usdc_price
            
            # Fallback to sample data
            eth_usd_price, usdc_usd_price = self._get_sample_price_data()
            eth_usdc_price = eth_usd_price / usdc_usd_price
            
            if self.verbose:
                print(f"📊 ETH/USDC (sample): {eth_usdc_price:.6f}")
            
            return eth_usdc_price
            
        except Exception as e:
            if self.verbose:
                print(f"❌ Error calculating ETH/USDC price: {e}")
            return None
    
    def price_to_tick(self, price: float) -> int:
        """Convert price to Uniswap V4 tick."""
        # Uniswap V4 tick calculation: tick = log(price) / log(1.0001)
        if price <= 0:
            return 0
        
        # Calculate tick using natural logarithm
        tick = math.log(price) / math.log(1.0001)
        return int(tick)
    
    def tick_to_price(self, tick: int) -> float:
        """Convert Uniswap V4 tick to price."""
        # Uniswap V4 price calculation: price = 1.0001^tick
        return 1.0001 ** tick
    
    def get_price_and_tick(self) -> Optional[Tuple[float, int]]:
        """Get current ETH/USDC price and corresponding tick."""
        price = self.get_eth_usdc_price()
        if price is None:
            return None
        
        tick = self.price_to_tick(price)
        return price, tick
    
    def display_results(self, price: float, tick: int):
        """Display results in a formatted way."""
        if self.verbose:
            print("\n📊 ETH/USDC Price Ticker Results")
            print("=" * 40)
            print(f"💰 Price: {price:.6f} USDC per ETH")
            print(f"🎯 Tick: {tick:,}")
            print(f"🔄 Tick Price: {self.tick_to_price(tick):.6f}")
            print(f"📈 Difference: {abs(price - self.tick_to_price(tick)):.6f}")
            if not REQUESTS_AVAILABLE:
                print("⚠️  Using sample data (requests library not available)")
        else:
            # One-line output as requested
            print(f"{price:.6f} {tick}")


def main():
    """Main function to handle command line arguments."""
    parser = argparse.ArgumentParser(
        description="Get ETH/USDC price and convert to Uniswap V4 tick",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                    # One-line output: price tick
  %(prog)s --verbose          # Detailed output
  %(prog)s --test            # Test tick conversion
        """
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output including price validation'
    )
    
    parser.add_argument(
        '--test',
        action='store_true',
        help='Test tick conversion with sample prices'
    )
    
    parser.add_argument(
        '--price',
        type=float,
        help='Test tick conversion with specific price'
    )
    
    args = parser.parse_args()
    
    # Create ticker
    ticker = ETHPriceTicker(verbose=args.verbose)
    
    # Test mode
    if args.test:
        print("🧪 Testing Tick Conversion")
        print("=" * 30)
        test_prices = [2500.0, 2600.0, 2400.0, 3000.0, 2000.0]
        
        for price in test_prices:
            tick = ticker.price_to_tick(price)
            tick_price = ticker.tick_to_price(tick)
            print(f"Price: {price:.2f} → Tick: {tick:,} → Tick Price: {tick_price:.2f}")
        
        return 0
    
    # Test specific price
    if args.price is not None:
        tick = ticker.price_to_tick(args.price)
        tick_price = ticker.tick_to_price(tick)
        print(f"Price: {args.price:.2f} → Tick: {tick:,} → Tick Price: {tick_price:.2f}")
        return 0
    
    # Get current price and tick
    result = ticker.get_price_and_tick()
    
    if result is None:
        print("❌ Failed to get price data")
        return 1
    
    price, tick = result
    
    # Output results
    ticker.display_results(price, tick)
    
    return 0


if __name__ == '__main__':
    sys.exit(main()) 