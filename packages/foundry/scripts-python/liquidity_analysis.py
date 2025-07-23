#!/usr/bin/env python3
"""
DetoxHook Liquidity Analysis
============================

This script analyzes the liquidity distribution in DetoxHook pools and explains
why swaps might be failing due to concentrated liquidity positioning.

Usage:
    python liquidity_analysis.py --verbose
"""

import os
import sys
import argparse
from typing import Dict, Any

# Import our existing modules
try:
    from check_pool_state import PoolStateChecker
    from load_env import EnvLoader
except ImportError:
    print("❌ Required modules not found. Make sure you're in the scripts-python directory.")
    sys.exit(1)


class LiquidityAnalyzer:
    """Analyzes DetoxHook pool liquidity and swap feasibility."""
    
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.pool_checker = PoolStateChecker(verbose=verbose)
    
    def analyze_all_pools(self) -> Dict[str, Any]:
        """Analyze liquidity situation for all DetoxHook pools."""
        if not self.pool_checker.w3:
            return {"error": "Could not connect to blockchain"}
        
        # Get pool states
        pool_states = self.pool_checker.get_all_detox_pools_state()
        
        analysis = {
            "pools": {},
            "summary": {},
            "recommendations": []
        }
        
        # Analyze each pool
        for pool_name, pool_data in pool_states.items():
            if "error" in pool_data:
                continue
                
            if not pool_data.get("success"):
                continue
            
            pool_analysis = self._analyze_single_pool(pool_name, pool_data)
            analysis["pools"][pool_name] = pool_analysis
        
        # Generate summary and recommendations
        analysis["summary"] = self._generate_summary(analysis["pools"])
        analysis["recommendations"] = self._generate_recommendations(analysis["pools"])
        
        return analysis
    
    def _analyze_single_pool(self, pool_name: str, pool_data: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze a single pool's liquidity situation."""
        current_tick = pool_data.get("tick", 0)
        liquidity = pool_data.get("liquidity", 0)
        usdc_per_eth = pool_data.get("usdc_per_eth", 0)
        
        # Known liquidity position (from deployment logs)
        position_tick_lower = -600
        position_tick_upper = 600
        
        # Analyze position relative to current price
        tick_distance_from_lower = current_tick - position_tick_lower
        tick_distance_from_upper = current_tick - position_tick_upper
        
        in_range = position_tick_lower <= current_tick <= position_tick_upper
        
        # Calculate how far out of range we are
        if current_tick < position_tick_lower:
            distance_to_range = position_tick_lower - current_tick
            range_direction = "below"
        elif current_tick > position_tick_upper:
            distance_to_range = current_tick - position_tick_upper
            range_direction = "above"
        else:
            distance_to_range = 0
            range_direction = "in_range"
        
        return {
            "pool_name": pool_name,
            "current_tick": current_tick,
            "current_price_usdc": usdc_per_eth,
            "active_liquidity": liquidity,
            "position_range": {
                "tick_lower": position_tick_lower,
                "tick_upper": position_tick_upper,
                "in_range": in_range,
                "range_direction": range_direction,
                "distance_to_range": distance_to_range
            },
            "swap_feasible": liquidity > 0,
            "analysis": self._get_pool_analysis_text(current_tick, liquidity, in_range, range_direction, distance_to_range)
        }
    
    def _get_pool_analysis_text(self, current_tick: int, liquidity: int, in_range: bool, 
                               range_direction: str, distance: int) -> str:
        """Generate human-readable analysis text for a pool."""
        if in_range and liquidity > 0:
            return "✅ Liquidity is active and swaps should work"
        elif in_range and liquidity == 0:
            return "⚠️ Price is in range but no active liquidity detected"
        elif range_direction == "above":
            return f"❌ Current price is {distance} ticks above your liquidity range - no active liquidity"
        elif range_direction == "below":
            return f"❌ Current price is {distance} ticks below your liquidity range - no active liquidity"
        else:
            return "❓ Unknown liquidity situation"
    
    def _generate_summary(self, pools: Dict[str, Any]) -> Dict[str, Any]:
        """Generate overall summary of liquidity situation."""
        total_pools = len(pools)
        swappable_pools = sum(1 for p in pools.values() if p.get("swap_feasible", False))
        out_of_range_pools = sum(1 for p in pools.values() if not p.get("position_range", {}).get("in_range", False))
        
        return {
            "total_pools": total_pools,
            "swappable_pools": swappable_pools,
            "out_of_range_pools": out_of_range_pools,
            "overall_status": "swappable" if swappable_pools > 0 else "no_active_liquidity"
        }
    
    def _generate_recommendations(self, pools: Dict[str, Any]) -> list:
        """Generate recommendations based on analysis."""
        recommendations = []
        
        if all(not p.get("swap_feasible", False) for p in pools.values()):
            recommendations.extend([
                "🎯 Your liquidity positions are out of range for current prices",
                "💡 Option 1: Add liquidity at current price ranges (tick 9000-9600)",
                "💡 Option 2: Wait for prices to move back to your range (-600 to +600)",
                "💡 Option 3: Use a different pool with active liquidity",
                "🔧 For testing: Deploy SwapRouterFixed with a pool that has active liquidity"
            ])
        
        # Check if pools have very different prices
        prices = [p.get("current_price_usdc", 0) for p in pools.values() if p.get("current_price_usdc", 0) > 0]
        if len(prices) > 1:
            price_diff = max(prices) - min(prices)
            if price_diff > 100:  # $100 difference
                recommendations.append(f"💰 Price difference between pools: ${price_diff:.0f} - arbitrage opportunity!")
        
        return recommendations
    
    def display_analysis(self, analysis: Dict[str, Any]):
        """Display the liquidity analysis in a readable format."""
        print("🔬 DetoxHook Liquidity Analysis")
        print("=" * 50)
        
        if "error" in analysis:
            print(f"❌ Error: {analysis['error']}")
            return
        
        # Display individual pool analysis
        for pool_name, pool_data in analysis.get("pools", {}).items():
            print(f"\n🏊 {pool_data['pool_name'].upper()}")
            print(f"   Current Tick: {pool_data['current_tick']:,}")
            print(f"   Current Price: ${pool_data['current_price_usdc']:,.2f} USDC/ETH")
            print(f"   Active Liquidity: {pool_data['active_liquidity']:,}")
            
            position = pool_data['position_range']
            print(f"   Your Position: Tick {position['tick_lower']} to {position['tick_upper']}")
            print(f"   Position Status: {pool_data['analysis']}")
            
            if not position['in_range']:
                print(f"   Distance: {position['distance_to_range']} ticks {position['range_direction']} your range")
        
        # Display summary
        summary = analysis.get("summary", {})
        print(f"\n📊 Summary:")
        print(f"   Total Pools: {summary.get('total_pools', 0)}")
        print(f"   Swappable Pools: {summary.get('swappable_pools', 0)}")
        print(f"   Out of Range: {summary.get('out_of_range_pools', 0)}")
        
        # Display recommendations
        recommendations = analysis.get("recommendations", [])
        if recommendations:
            print(f"\n💡 Recommendations:")
            for i, rec in enumerate(recommendations, 1):
                print(f"   {i}. {rec}")
        
        # Explain concentrated liquidity
        print(f"\n📚 Understanding Concentrated Liquidity:")
        print(f"   • Your liquidity is concentrated in specific price ranges")
        print(f"   • When prices move outside your range, liquidity becomes inactive")
        print(f"   • This is normal behavior for Uniswap V4 concentrated liquidity")
        print(f"   • Your funds are safe, just not available for swapping at current prices")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Analyze DetoxHook pool liquidity distribution",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output'
    )
    
    args = parser.parse_args()
    
    # Create analyzer
    analyzer = LiquidityAnalyzer(verbose=args.verbose)
    
    # Run analysis
    analysis = analyzer.analyze_all_pools()
    
    # Display results
    analyzer.display_analysis(analysis)
    
    # Return appropriate exit code
    summary = analysis.get("summary", {})
    return 0 if summary.get("swappable_pools", 0) > 0 else 1


if __name__ == '__main__':
    sys.exit(main()) 