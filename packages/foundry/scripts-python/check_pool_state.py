#!/usr/bin/env python3
"""
Uniswap V4 Pool State Checker for DetoxHook
===========================================

This script queries and displays the state of Uniswap V4 pools on Arbitrum Sepolia.
It can check individual pools by ID or automatically query all DetoxHook pools.

Usage:
    python check_pool_state.py <pool_id>                    # Check specific pool
    python check_pool_state.py --detox-pools               # Check all DetoxHook pools
    python check_pool_state.py --list-pools                # List available pools
    
Examples:
    python check_pool_state.py 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f
    python check_pool_state.py --detox-pools --verbose
    python check_pool_state.py --detox-pools --json
    python check_pool_state.py --list-pools
"""

import os
import sys
import argparse
import json
from typing import Dict, Optional, Tuple, Any
from pathlib import Path

# Try to import web3 and related dependencies
try:
    from web3 import Web3
    from web3.contract import Contract
    # Try both old and new POA middleware imports
    try:
        from web3.middleware import ExtraDataToPOAMiddleware as poa_middleware
    except ImportError:
        from web3.middleware import geth_poa_middleware as poa_middleware
except ImportError:
    print("❌ web3.py not found. Install with:")
    print("   pip install web3")
    print("   or: pip3 install web3")
    sys.exit(1)

# Import our environment loader
try:
    from load_env import EnvLoader
except ImportError:
    print("⚠️  Environment loader not found. Some features may be limited.")
    EnvLoader = None


class PoolStateChecker:
    """Checks Uniswap V4 pool state on Arbitrum Sepolia."""
    
    # Known contract addresses on Arbitrum Sepolia
    POOL_MANAGER_ADDRESS = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"  # Correct Arbitrum Sepolia PoolManager
    POOL_STATE_READER_ADDRESS = "0x0AcbCAD06528e31A825241a95655C00f01D6B539"  # Our deployed PoolStateReader
    
    # DetoxHook pool configuration file path
    POOLS_CONFIG_PATH = "../deployments/detox-hook-pools.json"
    
    # PoolStateReader ABI - Our deployed contract that works with StateLibrary
    POOL_STATE_READER_ABI = [
        {
            "type": "function",
            "name": "getPoolStateById",
            "inputs": [{"name": "poolId", "type": "bytes32"}],
            "outputs": [
                {"name": "sqrtPriceX96", "type": "uint160"},
                {"name": "tick", "type": "int24"},
                {"name": "protocolFee", "type": "uint24"},
                {"name": "lpFee", "type": "uint24"},
                {"name": "liquidity", "type": "uint128"},
                {"name": "success", "type": "bool"}
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getDetoxPool1State",
            "inputs": [],
            "outputs": [
                {"name": "sqrtPriceX96", "type": "uint160"},
                {"name": "tick", "type": "int24"},
                {"name": "protocolFee", "type": "uint24"},
                {"name": "lpFee", "type": "uint24"},
                {"name": "liquidity", "type": "uint128"},
                {"name": "success", "type": "bool"}
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getDetoxPool2State",
            "inputs": [],
            "outputs": [
                {"name": "sqrtPriceX96", "type": "uint160"},
                {"name": "tick", "type": "int24"},
                {"name": "protocolFee", "type": "uint24"},
                {"name": "lpFee", "type": "uint24"},
                {"name": "liquidity", "type": "uint128"},
                {"name": "success", "type": "bool"}
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getDetoxPoolIds",
            "inputs": [],
            "outputs": [
                {"name": "pool1Id", "type": "bytes32"},
                {"name": "pool2Id", "type": "bytes32"}
            ],
            "stateMutability": "view"
        }
    ]
    
    # ERC-20 ABI for token info
    ERC20_ABI = [
        {
            "constant": True,
            "inputs": [],
            "name": "name",
            "outputs": [{"name": "", "type": "string"}],
            "type": "function"
        },
        {
            "constant": True,
            "inputs": [],
            "name": "symbol", 
            "outputs": [{"name": "", "type": "string"}],
            "type": "function"
        },
        {
            "constant": True,
            "inputs": [],
            "name": "decimals",
            "outputs": [{"name": "", "type": "uint8"}],
            "type": "function"
        }
    ]
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False):
        self.verbose = verbose
        self.rpc_url = rpc_url or self._get_rpc_url()
        self.w3 = None
        self.pool_state_reader = None
        self._token_cache = {}
        
        if self.rpc_url:
            self._connect()
    
    def _get_rpc_url(self) -> Optional[str]:
        """Get RPC URL from environment or use default."""
        rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
        
        if not rpc_url:
            # Try to load from .env file
            if EnvLoader:
                try:
                    loader = EnvLoader(verbose=False, dry_run=False)
                    if loader.load_environment():
                        rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
                except Exception as e:
                    if self.verbose:
                        print(f"⚠️  Could not load environment: {e}")
        
        return rpc_url or "https://sepolia-rollup.arbitrum.io/rpc"
    
    def _connect(self):
        """Connect to the blockchain RPC."""
        try:
            self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
            
            # Add POA middleware for Arbitrum
            self.w3.middleware_onion.inject(poa_middleware, layer=0)
            
            if not self.w3.is_connected():
                raise ConnectionError(f"Could not connect to {self.rpc_url}")
            
            # Initialize PoolStateReader contract
            self.pool_state_reader = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.POOL_STATE_READER_ADDRESS),
                abi=self.POOL_STATE_READER_ABI
            )
            
            if self.verbose:
                print(f"✅ Connected to Arbitrum Sepolia via {self.rpc_url}")
                print(f"📄 PoolStateReader: {self.POOL_STATE_READER_ADDRESS}")
                
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            self.w3 = None
            self.pool_state_reader = None
    
    def _get_token_info(self, token_address: str) -> Dict[str, Any]:
        """Get token information (name, symbol, decimals)."""
        if token_address in self._token_cache:
            return self._token_cache[token_address]
        
        # Handle ETH (zero address)
        if token_address == "0x0000000000000000000000000000000000000000":
            token_info = {
                "name": "Ethereum",
                "symbol": "ETH", 
                "decimals": 18,
                "address": token_address
            }
            self._token_cache[token_address] = token_info
            return token_info
        
        try:
            token_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(token_address),
                abi=self.ERC20_ABI
            )
            
            token_info = {
                "name": token_contract.functions.name().call(),
                "symbol": token_contract.functions.symbol().call(),
                "decimals": token_contract.functions.decimals().call(),
                "address": token_address
            }
            
            self._token_cache[token_address] = token_info
            return token_info
            
        except Exception as e:
            if self.verbose:
                print(f"⚠️  Could not get token info for {token_address}: {e}")
            
            # Return minimal info
            token_info = {
                "name": "Unknown Token",
                "symbol": "???",
                "decimals": 18,
                "address": token_address
            }
            self._token_cache[token_address] = token_info
            return token_info
    
    def _calculate_price_from_sqrt(self, sqrt_price_x96: int, decimals0: int, decimals1: int) -> float:
        """Calculate human-readable price from sqrtPriceX96."""
        if sqrt_price_x96 == 0:
            return 0.0
        
        # Price = (sqrtPriceX96 / 2^96)^2
        price_raw = (sqrt_price_x96 / (2 ** 96)) ** 2
        
        # Adjust for decimals
        decimal_adjustment = (10 ** decimals1) / (10 ** decimals0)
        price = price_raw * decimal_adjustment
        
        return price
    
    def _format_number(self, number: float, decimals: int = 6) -> str:
        """Format numbers with appropriate precision."""
        if number == 0:
            return "0"
        elif number >= 1000000:
            return f"{number/1000000:.2f}M"
        elif number >= 1000:
            return f"{number/1000:.2f}K"
        elif number >= 1:
            return f"{number:.{decimals}f}".rstrip('0').rstrip('.')
        else:
            # For small numbers, show more precision
            return f"{number:.8f}".rstrip('0').rstrip('.')
    
    def _load_detox_pools_config(self) -> Optional[Dict]:
        """Load DetoxHook pool configurations from JSON file."""
        config_path = Path(__file__).parent / self.POOLS_CONFIG_PATH
        
        if not config_path.exists():
            if self.verbose:
                print(f"⚠️  Pool config not found at {config_path}")
            return None
        
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
            return config
        except Exception as e:
            if self.verbose:
                print(f"⚠️  Could not load pool config: {e}")
            return None
    
    def get_detox_pool_ids(self) -> Dict[str, Dict]:
        """Get all DetoxHook pool IDs and their configurations."""
        config = self._load_detox_pools_config()
        if not config:
            return {}
        
        pools = {}
        for pool_name, pool_info in config.get("pools", {}).items():
            pools[pool_name] = {
                "pool_id": pool_info.get("poolId"),
                "description": pool_info.get("description", "Unknown pool"),
                "config": pool_info
            }
        
        return pools

    def _decode_pool_key_from_id(self, pool_id: str) -> Optional[Dict]:
        """
        Attempt to decode pool key information from pool ID.
        Note: This is challenging without the original PoolKey data.
        In practice, you'd need to know the PoolKey components.
        """
        # Check if this pool ID matches any of our known DetoxHook pools
        detox_pools = self.get_detox_pool_ids()
        for pool_name, pool_info in detox_pools.items():
            if pool_info["pool_id"] == pool_id:
                return {
                    "name": pool_name,
                    "description": pool_info["description"],
                    "config": pool_info["config"]
                }
        
        # For unknown pools, return None
        return None
    
    def get_pool_state(self, pool_id: str) -> Dict[str, Any]:
        """Get comprehensive pool state for a given pool ID using PoolStateReader."""
        if not self.w3 or not self.pool_state_reader:
            return {
                "pool_id": pool_id,
                "error": "Not connected to blockchain",
                "success": False
            }
        
        # Validate pool ID format
        if not pool_id.startswith('0x') or len(pool_id) != 66:
            return {
                "pool_id": pool_id,
                "error": "Invalid pool ID format (should be 32-byte hex string)",
                "success": False
            }
        
        try:
            pool_id_bytes = bytes.fromhex(pool_id[2:])
            
            # Check if this is a known DetoxHook pool and use optimized methods
            detox_pools = self.get_detox_pool_ids()
            pool_info = None
            for pool_name, info in detox_pools.items():
                if info["pool_id"] == pool_id:
                    pool_info = info
                    
                    # Use specialized DetoxHook pool methods
                    if pool_name == "pool1":
                        response = self.pool_state_reader.functions.getDetoxPool1State().call()
                    elif pool_name == "pool2":
                        response = self.pool_state_reader.functions.getDetoxPool2State().call()
                    else:
                        response = self.pool_state_reader.functions.getPoolStateById(pool_id_bytes).call()
                    break
            else:
                # Unknown pool - use generic method
                response = self.pool_state_reader.functions.getPoolStateById(pool_id_bytes).call()
            
            # Unpack the response
            sqrt_price_x96, tick, protocol_fee, lp_fee, liquidity, success = response
            
            if not success:
                return {
                    "pool_id": pool_id,
                    "error": "Pool state query failed (pool may not exist or be initialized)",
                    "success": False
                }
            
            # Build result
            result = {
                "pool_id": pool_id,
                "slot0": {
                    "sqrt_price_x96": sqrt_price_x96,
                    "tick": tick,
                    "protocol_fee": protocol_fee,
                    "lp_fee": lp_fee
                },
                "liquidity": liquidity,
                "block_number": self.w3.eth.block_number,
                "success": True
            }
            
            # Add pool configuration if available
            if pool_info:
                result["pool_config"] = pool_info["config"]
                result["pool_name"] = pool_info.get("name", "Unknown")
                result["pool_description"] = pool_info.get("description", "Unknown pool")
            
            # Calculate human-readable prices for ETH/USDC pools
            if sqrt_price_x96 > 0:
                # Convert sqrtPriceX96 to human-readable price
                # Use the same calculation method as HookLibrary.sqrtPriceToPrice
                # price = (sqrtPriceX96 / 2^96)^2 * 1e18
                price_with_precision = ((sqrt_price_x96 / (2 ** 96)) ** 2) * (10 ** 18)
                
                # For ETH/USDC: Adjust for token decimals
                # This gives us USDC per ETH in proper decimal format
                # The expected range should be around 2500 USDC per ETH
                usdc_per_eth = price_with_precision / (10 ** 12)  # Divide by 1e12 to get reasonable scale
                
                result["calculated_prices"] = {
                    "usdc_per_eth": usdc_per_eth,
                    "eth_per_usdc": 1.0 / usdc_per_eth if usdc_per_eth > 0 else 0,
                    "price_with_precision": price_with_precision,
                    "note": "Calculated price: USDC per ETH (accounting for 18/6 decimals)"
                }
            
            return result
            
        except Exception as e:
            return {
                "pool_id": pool_id,
                "error": f"Failed to query pool state: {str(e)}",
                "success": False
            }
    
    def get_all_detox_pools_state(self) -> Dict[str, Dict[str, Any]]:
        """Get state for all known DetoxHook pools using optimized contract calls."""
        if not self.w3 or not self.pool_state_reader:
            return {"error": "Not connected to blockchain"}
        
        results = {}
        
        try:
            # Get both pool states with specialized methods (more efficient)
            pool1_response = self.pool_state_reader.functions.getDetoxPool1State().call()
            pool2_response = self.pool_state_reader.functions.getDetoxPool2State().call()
            
            # Process Pool 1
            sqrt_price_x96, tick, protocol_fee, lp_fee, liquidity, success = pool1_response
            if success:
                # Calculate price using the same method as main function
                price_with_precision = ((sqrt_price_x96 / (2 ** 96)) ** 2) * (10 ** 18)
                usdc_per_eth = price_with_precision / (10 ** 12)
                
                results["pool1"] = {
                    "pool_id": "0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f",
                    "description": "ETH/USDC 0.3% fee pool (~2500 USDC/ETH)",
                    "sqrt_price_x96": sqrt_price_x96,
                    "tick": tick,
                    "protocol_fee": protocol_fee,
                    "lp_fee": lp_fee,
                    "liquidity": liquidity,
                    "usdc_per_eth": usdc_per_eth,
                    "success": True
                }
            else:
                results["pool1"] = {"success": False, "error": "Pool 1 query failed"}
            
            # Process Pool 2
            sqrt_price_x96, tick, protocol_fee, lp_fee, liquidity, success = pool2_response
            if success:
                # Calculate price using the same method as main function
                price_with_precision = ((sqrt_price_x96 / (2 ** 96)) ** 2) * (10 ** 18)
                usdc_per_eth = price_with_precision / (10 ** 12)
                
                results["pool2"] = {
                    "pool_id": "0x10fe1bb5300768c6f5986ee70c9ee834ea64ea704f92b0fd2cda0bcbe829ec90",
                    "description": "ETH/USDC 0.05% fee pool (~2600 USDC/ETH)",
                    "sqrt_price_x96": sqrt_price_x96,
                    "tick": tick,
                    "protocol_fee": protocol_fee,
                    "lp_fee": lp_fee,
                    "liquidity": liquidity,
                    "usdc_per_eth": usdc_per_eth,
                    "success": True
                }
            else:
                results["pool2"] = {"success": False, "error": "Pool 2 query failed"}
                
        except Exception as e:
            results["error"] = f"Failed to query DetoxHook pools: {str(e)}"
        
        return results
    
    def display_pool_state(self, pool_state: Dict[str, Any], show_raw: bool = False):
        """Display pool state in a nice format."""
        print("\n🏊 Uniswap V4 Pool State Report")
        print("=" * 50)
        
        pool_id = pool_state.get("pool_id", "Unknown")
        print(f"🆔 Pool ID: {pool_id}")
        
        # Check if this is a known DetoxHook pool
        pool_info = self._decode_pool_key_from_id(pool_id)
        if pool_info:
            print(f"🎯 Pool Name: {pool_info['name']}")
            print(f"📄 Description: {pool_info['description']}")
            print(f"🛡️  MEV Protection: DetoxHook Active ✅")
        
        if not pool_state.get("success", False):
            error = pool_state.get("error", "Unknown error")
            print(f"❌ Error: {error}")
            return
        
        print(f"📈 Block Number: {pool_state.get('block_number', 'Unknown'):,}")
        print()
        
        # Slot0 information
        slot0 = pool_state.get("slot0", {})
        if slot0:
            print("📊 Slot0 Data:")
            sqrt_price = slot0.get("sqrt_price_x96", 0)
            tick = slot0.get("tick", 0)
            protocol_fee = slot0.get("protocol_fee", 0)
            lp_fee = slot0.get("lp_fee", 0)
            
            print(f"   🎯 Current Tick: {tick:,}")
            print(f"   💰 LP Fee: {lp_fee} ({lp_fee/10000:.2f}%)")
            print(f"   🏛️  Protocol Fee: {protocol_fee}")
            
            if show_raw:
                print(f"   📐 Sqrt Price X96: {sqrt_price:,}")
            
            # Calculated prices
            calc_prices = pool_state.get("calculated_prices", {})
            if calc_prices:
                print("\n💱 Calculated Prices:")
                usdc_per_eth = calc_prices.get("usdc_per_eth", 0)
                eth_per_usdc = calc_prices.get("eth_per_usdc", 0)
                
                print(f"   💰 USDC per ETH: ${self._format_number(usdc_per_eth)}")
                print(f"   🔗 ETH per USDC: {self._format_number(eth_per_usdc)}")
                print(f"   ℹ️  Note: {calc_prices.get('note', '')}")
                
                # Show comparison to expected price
                if 2400 <= usdc_per_eth <= 2700:
                    print(f"   ✅ Price looks reasonable for ETH/USDC")
                elif usdc_per_eth > 0:
                    print(f"   ⚠️  Price may be outside expected range")
        
        # Liquidity information  
        liquidity = pool_state.get("liquidity", 0)
        print(f"\n💧 Total Liquidity: {liquidity:,}")
        
        if liquidity == 0:
            print("   ⚠️  Pool appears to have no liquidity")
        elif liquidity < 1000:
            print("   ⚠️  Very low liquidity - high slippage expected")
        elif liquidity < 100000:
            print("   🟡 Low liquidity - moderate slippage possible")
        else:
            print("   🟢 Good liquidity level")
        
        # Raw data section
        if show_raw:
            print("\n🔍 Raw Data:")
            print(json.dumps(pool_state, indent=2))
        
        print("\n💡 Note: Without PoolKey data, token information cannot be displayed.")
        print("    To get complete pool info, you would need the original PoolKey components:")
        print("    - currency0 address")
        print("    - currency1 address") 
        print("    - fee tier")
        print("    - tick spacing")
        print("    - hooks address")


def main():
    """Main function to handle command line arguments and execute pool state check."""
    parser = argparse.ArgumentParser(
        description="Check Uniswap V4 pool state on Arbitrum Sepolia",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f
  %(prog)s --detox-pools --verbose
  %(prog)s --detox-pools --json
  %(prog)s --list-pools
        """
    )
    
    parser.add_argument(
        'pool_id',
        nargs='?',
        help='Pool ID (32-byte hex string starting with 0x)'
    )
    
    parser.add_argument(
        '--pool-id', '-p',
        help='Pool ID (alternative to positional argument)'
    )
    
    parser.add_argument(
        '--rpc-url',
        help='Custom RPC URL (default: from .env or Arbitrum Sepolia)'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output including errors'
    )
    
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    
    parser.add_argument(
        '--show-raw',
        action='store_true',
        help='Show raw blockchain data'
    )
    
    parser.add_argument(
        '--detox-pools',
        action='store_true',
        help='Query all DetoxHook pools automatically'
    )
    
    parser.add_argument(
        '--list-pools',
        action='store_true', 
        help='List available DetoxHook pool IDs and exit'
    )
    
    args = parser.parse_args()
    
    # Create pool state checker early for list-pools
    checker = PoolStateChecker(rpc_url=args.rpc_url, verbose=args.verbose)
    
    # Handle list pools option
    if args.list_pools:
        detox_pools = checker.get_detox_pool_ids()
        if not detox_pools:
            print("❌ No DetoxHook pools found in configuration")
            return 1
        
        print("🏊 Available DetoxHook Pools:")
        print("=" * 50)
        for pool_name, pool_info in detox_pools.items():
            print(f"🎯 {pool_name}")
            print(f"   📄 {pool_info['description']}")
            print(f"   🆔 {pool_info['pool_id']}")
            print()
        return 0
    
    # Handle detox pools option
    if args.detox_pools:
        detox_pools = checker.get_detox_pool_ids()
        if not detox_pools:
            print("❌ No DetoxHook pools found in configuration")
            return 1
        
        if not checker.w3:
            print("❌ Could not connect to blockchain")
            return 1
        
        success_count = 0
        for pool_name, pool_info in detox_pools.items():
            pool_id = pool_info['pool_id']
            if args.verbose:
                print(f"🔍 Checking {pool_name}...")
            
            pool_state = checker.get_pool_state(pool_id)
            
            if args.json:
                pool_state['pool_name'] = pool_name
                pool_state['pool_description'] = pool_info['description']
                print(json.dumps(pool_state, indent=2))
            else:
                checker.display_pool_state(pool_state, show_raw=args.show_raw)
            
            if pool_state.get("success", False):
                success_count += 1
        
        return 0 if success_count > 0 else 1
    
    # Get pool ID from arguments
    pool_id = args.pool_id or args.pool_id
    
    if not pool_id:
        print("❌ Pool ID is required (or use --detox-pools to query all DetoxHook pools)")
        print("Usage: python check_pool_state.py <pool_id>")
        print("       python check_pool_state.py --detox-pools")
        print("       python check_pool_state.py --list-pools")
        print("Example: python check_pool_state.py 0xa49f711787deee79969f93a4f2eae9b56a2345dbaee1b057ba803e771c43c7de")
        return 1
    
    if not checker.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    if args.verbose:
        print(f"🔍 Checking pool state for: {pool_id}")
    
    # Get pool state
    pool_state = checker.get_pool_state(pool_id)
    
    # Display results
    if args.json:
        print(json.dumps(pool_state, indent=2))
    else:
        checker.display_pool_state(pool_state, show_raw=args.show_raw)
    
    return 0 if pool_state.get("success", False) else 1


if __name__ == '__main__':
    sys.exit(main()) 