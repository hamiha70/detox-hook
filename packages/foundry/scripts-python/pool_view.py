#!/usr/bin/env python3
"""
Pool State Viewer Script
========================

This script uses the deployed PoolStateViewer contract to query
Uniswap V4 pool information including price and liquidity.

Usage:
    python3 pool_view.py --pool-id 0x... --rpc-url https://...
    python3 pool_view.py --pool-id 0x... --verbose
    python3 pool_view.py --help

Example:
    python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f
"""

import argparse
import sys
import os
from pathlib import Path
from typing import Optional, Dict, Any
from decimal import Decimal, getcontext

# Add parent directory to path for imports
sys.path.append(str(Path(__file__).parent))

try:
    from web3 import Web3
    from web3.contract import Contract
    WEB3_AVAILABLE = True
except ImportError:
    WEB3_AVAILABLE = False
    print("⚠️  Web3 not available. Install with: pip install web3")

try:
    from load_env import EnvLoader
    ENV_LOADER_AVAILABLE = True
except ImportError:
    ENV_LOADER_AVAILABLE = False
    print("⚠️  Environment loader not available")

# PoolStateViewer ABI (minimal for our needs)
POOL_STATE_VIEWER_ABI = [
    {
        "inputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
        "name": "getPoolStateById",
        "outputs": [
            {"internalType": "uint160", "name": "sqrtPriceX96", "type": "uint160"},
            {"internalType": "int24", "name": "tick", "type": "int24"},
            {"internalType": "uint24", "name": "protocolFee", "type": "uint24"},
            {"internalType": "uint24", "name": "lpFee", "type": "uint24"},
            {"internalType": "uint128", "name": "liquidity", "type": "uint128"},
            {"internalType": "bool", "name": "success", "type": "bool"}
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "bytes32", "name": "poolId", "type": "bytes32"},
            {"internalType": "int24", "name": "tick", "type": "int24"}
        ],
        "name": "getTickInfo",
        "outputs": [
            {"internalType": "uint128", "name": "liquidity", "type": "uint128"},
            {"internalType": "bool", "name": "success", "type": "bool"}
        ],
        "stateMutability": "view",
        "type": "function"
    }
]

# Deployed contract address
POOL_STATE_VIEWER_ADDRESS = "0xA0386BBB0d8F176D4EdCFfAD6Aa1CDa833f11380"

class PoolStateViewer:
    """Client for interacting with the deployed PoolStateViewer contract."""
    
    def __init__(self, rpc_url: str, verbose: bool = False):
        self.rpc_url = rpc_url
        self.verbose = verbose
        self.w3 = None
        self.contract = None
        
        if not WEB3_AVAILABLE:
            raise ImportError("Web3 library is required. Install with: pip install web3")
        
        self._connect()
    
    def _connect(self):
        """Connect to the blockchain and initialize the contract."""
        try:
            self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
            
            if not self.w3.is_connected():
                raise ConnectionError(f"Failed to connect to RPC: {self.rpc_url}")
            
            self.contract = self.w3.eth.contract(
                address=POOL_STATE_VIEWER_ADDRESS,
                abi=POOL_STATE_VIEWER_ABI
            )
            
            if self.verbose:
                print(f"✅ Connected to {self.rpc_url}")
                print(f"✅ PoolStateViewer contract: {POOL_STATE_VIEWER_ADDRESS}")
                
        except Exception as e:
            raise ConnectionError(f"Failed to initialize Web3: {e}")
    
    def get_pool_state(self, pool_id: str) -> Optional[Dict[str, Any]]:
        """Get pool state information."""
        try:
            # Ensure pool_id is properly formatted
            if not pool_id.startswith('0x'):
                pool_id = '0x' + pool_id
            
            # Call the contract
            result = self.contract.functions.getPoolStateById(pool_id).call()
            
            sqrt_price_x96, tick, protocol_fee, lp_fee, liquidity, success = result
            
            if not success:
                if self.verbose:
                    print(f"❌ Failed to get pool state for {pool_id}")
                return None
            
            # Calculate price from sqrtPriceX96
            # price = (sqrtPriceX96 / 2^96) ^ 2
            sqrt_price_decimal = Decimal(sqrt_price_x96) / Decimal(2**96)
            price = float(sqrt_price_decimal ** 2)
            
            # Convert liquidity to a more readable format
            liquidity_formatted = self.w3.from_wei(liquidity, 'ether')
            
            return {
                'pool_id': pool_id,
                'sqrt_price_x96': sqrt_price_x96,
                'price': price,
                'tick': tick,
                'protocol_fee': protocol_fee,
                'lp_fee': lp_fee,
                'liquidity': liquidity,
                'liquidity_formatted': liquidity_formatted,
                'success': success
            }
            
        except Exception as e:
            if self.verbose:
                print(f"❌ Error getting pool state: {e}")
            return None
    
    def get_tick_info(self, pool_id: str, tick: int) -> Optional[Dict[str, Any]]:
        """Get tick information for a specific tick."""
        try:
            # Ensure pool_id is properly formatted
            if not pool_id.startswith('0x'):
                pool_id = '0x' + pool_id
            
            # Call the contract
            result = self.contract.functions.getTickInfo(pool_id, tick).call()
            
            liquidity, success = result
            
            if not success:
                if self.verbose:
                    print(f"❌ Failed to get tick info for {pool_id} at tick {tick}")
                return None
            
            # Convert liquidity to a more readable format
            liquidity_formatted = self.w3.from_wei(liquidity, 'ether')
            
            return {
                'pool_id': pool_id,
                'tick': tick,
                'liquidity': liquidity,
                'liquidity_formatted': liquidity_formatted,
                'success': success
            }
            
        except Exception as e:
            if self.verbose:
                print(f"❌ Error getting tick info: {e}")
            return None
    
    def display_pool_state(self, pool_state: Dict[str, Any]):
        """Display pool state information in a formatted way."""
        if not pool_state:
            print("❌ No pool state data available")
            return
        
        print("\n" + "="*60)
        print("🏊 POOL STATE INFORMATION")
        print("="*60)
        print(f"Pool ID:     {pool_state['pool_id']}")
        print(f"Price:       {pool_state['price']:.8f}")
        print(f"Tick:        {pool_state['tick']}")
        print(f"Protocol Fee: {pool_state['protocol_fee']}")
        print(f"LP Fee:      {pool_state['lp_fee']}")
        print(f"Liquidity:   {pool_state['liquidity_formatted']:.6f} ETH")
        print(f"Success:     {'✅ Yes' if pool_state['success'] else '❌ No'}")
        print("="*60)
    
    def display_tick_info(self, tick_info: Dict[str, Any]):
        """Display tick information in a formatted way."""
        if not tick_info:
            print("❌ No tick info data available")
            return
        
        print("\n" + "="*60)
        print("📍 TICK INFORMATION")
        print("="*60)
        print(f"Pool ID:     {tick_info['pool_id']}")
        print(f"Tick:        {tick_info['tick']}")
        print(f"Liquidity:   {tick_info['liquidity_formatted']:.6f} ETH")
        print(f"Success:     {'✅ Yes' if tick_info['success'] else '❌ No'}")
        print("="*60)

def load_environment() -> Optional[str]:
    """Load environment variables and return RPC URL."""
    # Try to load from environment loader
    if ENV_LOADER_AVAILABLE:
        try:
            loader = EnvLoader(verbose=False)
            loader.load_environment()
            rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
            if rpc_url:
                return rpc_url
        except Exception as e:
            print(f"⚠️  Environment loader failed: {e}")
    
    # Fallback to direct environment variable
    rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
    if rpc_url:
        return rpc_url
    
    return None

def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Query Uniswap V4 pool information using PoolStateViewer contract",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f
  python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --tick 100
  python3 pool_view.py --pool-id 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f --rpc-url https://sepolia-rollup.arbitrum.io/rpc
        """
    )
    
    parser.add_argument(
        '--pool-id',
        required=True,
        help='Pool ID to query (hex string)'
    )
    
    parser.add_argument(
        '--tick',
        type=int,
        help='Specific tick to query (optional)'
    )
    
    parser.add_argument(
        '--rpc-url',
        help='RPC URL (defaults to ARBITRUM_SEPOLIA_RPC_URL environment variable)'
    )
    
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    args = parser.parse_args()
    
    # Get RPC URL
    rpc_url = args.rpc_url or load_environment()
    if not rpc_url:
        print("❌ No RPC URL provided. Use --rpc-url or set ARBITRUM_SEPOLIA_RPC_URL environment variable")
        sys.exit(1)
    
    try:
        # Initialize the viewer
        viewer = PoolStateViewer(rpc_url, verbose=args.verbose)
        
        # Get pool state
        pool_state = viewer.get_pool_state(args.pool_id)
        viewer.display_pool_state(pool_state)
        
        # Get tick info if requested
        if args.tick is not None:
            tick_info = viewer.get_tick_info(args.pool_id, args.tick)
            viewer.display_tick_info(tick_info)
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main() 