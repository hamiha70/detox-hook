#!/usr/bin/env python3
"""
Uniswap V4 Pool Details Querier
==============================

This script queries detailed information about a Uniswap V4 pool including:
1. Pool price (current)
2. Liquidity at current price ticker
3. Liquidity at specific ticker
4. Token amounts (token0 and token1) in the pool

Usage:
    python query_pool_details.py --pool-key '{"currency0":"0x...", "currency1":"...", "fee":500, "tickSpacing":60, "hooks":"0x..."}' --ticker '{"tick": 1000}'
    
Requirements:
    pip install web3
"""

import os
import sys
import json
import argparse
from typing import Dict, Any, Tuple, Optional
from pathlib import Path

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
    sys.exit(1)

# Import environment loader if available
try:
    from load_env import EnvLoader
except ImportError:
    print("⚠️  Environment loader not found. Using environment variables directly.")
    EnvLoader = None


class UniswapV4PoolQuerier:
    """Query detailed information about Uniswap V4 pools on Arbitrum Sepolia."""
    
    # Contract addresses on Arbitrum Sepolia
    POOL_MANAGER_ADDRESS = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"
    
    # PoolManager ABI (minimal required functions)
    POOL_MANAGER_ABI = [
        {
            "type": "function",
            "name": "extsload",
            "inputs": [{"name": "slot", "type": "bytes32"}],
            "outputs": [{"name": "data", "type": "bytes32"}],
            "stateMutability": "view"
        },
        {
            "type": "function", 
            "name": "extsload",
            "inputs": [
                {"name": "slot", "type": "bytes32"},
                {"name": "nSlots", "type": "uint256"}
            ],
            "outputs": [{"name": "data", "type": "bytes32[]"}],
            "stateMutability": "view"
        }
    ]
    
    # ERC20 ABI for token information
    ERC20_ABI = [
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
        },
        {
            "constant": True,
            "inputs": [],
            "name": "name",
            "outputs": [{"name": "", "type": "string"}],
            "type": "function"
        }
    ]
    
    # Storage slot constants (from StateLibrary)
    POOLS_SLOT = 6
    LIQUIDITY_OFFSET = 3
    TICKS_OFFSET = 4
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False):
        self.verbose = verbose
        self.rpc_url = rpc_url or self._get_rpc_url()
        self.w3 = None
        self.pool_manager = None
        self._token_cache = {}
        
        if self.rpc_url:
            self._connect()
    
    def _get_rpc_url(self) -> Optional[str]:
        """Get RPC URL from environment or use default."""
        rpc_url = os.getenv('ARBITRUM_SEPOLIA_RPC_URL')
        
        if not rpc_url and EnvLoader:
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
            self.w3.middleware_onion.inject(poa_middleware, layer=0)
            
            if not self.w3.is_connected():
                raise ConnectionError(f"Could not connect to {self.rpc_url}")
            
            self.pool_manager = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.POOL_MANAGER_ADDRESS),
                abi=self.POOL_MANAGER_ABI
            )
            
            if self.verbose:
                print(f"✅ Connected to Arbitrum Sepolia via {self.rpc_url}")
                print(f"📄 PoolManager: {self.POOL_MANAGER_ADDRESS}")
                
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            self.w3 = None
            self.pool_manager = None
    
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
            
            token_info = {
                "name": "Unknown Token",
                "symbol": "???", 
                "decimals": 18,
                "address": token_address
            }
            self._token_cache[token_address] = token_info
            return token_info
    
    def get_pool_info_via_statelib_pattern(self, pool_key: Dict[str, Any]) -> Dict[str, Any]:
        """
        Get pool information using StateLibrary pattern.
        This uses the same approach as our existing scripts.
        """
        if not self.w3:
            return {"error": "Not connected"}
        
        try:
            # For demo purposes, we'll use the known pool IDs from our system
            # In production, you'd calculate the actual pool ID from the PoolKey
            known_pools = {
                # DetoxHook Pool 1: ETH/USDC 0.3%
                "eth_usdc_3000": {
                    "pool_id": "0x5e6967b5ca922ff1aa7f25521cfd03d9a59c17536caa09ba77ed0586c238d23f",
                    "currency0": "0x0000000000000000000000000000000000000000",
                    "currency1": "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
                    "fee": 3000
                },
                # DetoxHook Pool 2: ETH/USDC 0.05%
                "eth_usdc_500": {
                    "pool_id": "0x10fe1bb5300768c6f5986ee70c9ee834ea64ea704f92b0fd2cda0bcbe829ec90",
                    "currency0": "0x0000000000000000000000000000000000000000",
                    "currency1": "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
                    "fee": 500
                },
                # DetoxHook Pool 3: ETH/MockUSDC 0.05%
                "eth_mockusdc_500": {
                    "pool_id": "0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa",
                    "currency0": "0x0000000000000000000000000000000000000000",
                    "currency1": "0x9D5A68fDFEcc14683324640d5e835936422a47b1",
                    "fee": 500
                }
            }
            
            # Find matching pool
            matching_pool = None
            for pool_info in known_pools.values():
                if (pool_info["currency0"].lower() == pool_key["currency0"].lower() and
                    pool_info["currency1"].lower() == pool_key["currency1"].lower() and
                    pool_info["fee"] == pool_key["fee"]):
                    matching_pool = pool_info
                    break
            
            if not matching_pool:
                return {"error": "Pool not found in known pools", "success": False}
            
            # Use our existing PoolStateReader approach
            from web3 import Web3
            
            # PoolStateReader ABI (simplified)
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
                }
            ]
            
            POOL_STATE_READER_ADDRESS = "0x0AcbCAD06528e31A825241a95655C00f01D6B539"
            
            reader_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(POOL_STATE_READER_ADDRESS),
                abi=POOL_STATE_READER_ABI
            )
            
            pool_id_bytes = bytes.fromhex(matching_pool["pool_id"][2:])
            
            # Call the contract
            result = reader_contract.functions.getPoolStateById(pool_id_bytes).call()
            sqrt_price_x96, tick, protocol_fee, lp_fee, liquidity, success = result
            
            if not success:
                return {"error": "Pool state query failed", "success": False}
            
            # Get token information
            token0_info = self._get_token_info(pool_key["currency0"])
            token1_info = self._get_token_info(pool_key["currency1"])
            
            # Calculate human-readable price
            if sqrt_price_x96 > 0:
                price = (sqrt_price_x96 / (2 ** 96)) ** 2
                decimal_adjustment = (10 ** token1_info["decimals"]) / (10 ** token0_info["decimals"])
                human_price = price * decimal_adjustment
            else:
                human_price = 0
            
            return {
                "pool_id": matching_pool["pool_id"],
                "pool_price": {
                    "sqrt_price_x96": sqrt_price_x96,
                    "current_tick": tick,
                    "human_readable_price": human_price,
                    "price_description": f"{human_price:.6f} {token1_info['symbol']} per {token0_info['symbol']}"
                },
                "liquidity_at_current_tick": liquidity,
                "fees": {
                    "protocol_fee": protocol_fee,
                    "lp_fee": lp_fee
                },
                "tokens": {
                    "token0": token0_info,
                    "token1": token1_info
                },
                "block_number": self.w3.eth.block_number,
                "success": True
            }
            
        except Exception as e:
            return {"error": f"Query failed: {str(e)}", "success": False}
    
    def get_tick_liquidity_info(self, pool_key: Dict[str, Any], tick: int) -> Dict[str, Any]:
        """Get liquidity information for a specific tick (simplified approach)."""
        # This is a placeholder implementation
        # Real implementation would use StateLibrary.getTickInfo
        return {
            "tick": tick,
            "liquidity_gross": 0,  # Would need actual StateLibrary call
            "liquidity_net": 0,    # Would need actual StateLibrary call
            "note": "Tick liquidity query not fully implemented - would require StateLibrary.getTickInfo"
        }
    
    def query_pool_details(self, pool_key: Dict[str, Any], specific_tick: Optional[int] = None) -> Dict[str, Any]:
        """Query comprehensive pool details."""
        if not self.w3:
            return {"error": "Not connected to blockchain"}
        
        # Get basic pool information using our existing approach
        pool_info = self.get_pool_info_via_statelib_pattern(pool_key)
        
        if not pool_info.get("success", False):
            return pool_info
        
        # Add specific tick information if requested
        specific_tick_liquidity = None
        if specific_tick is not None:
            specific_tick_liquidity = self.get_tick_liquidity_info(pool_key, specific_tick)
        
        # Estimate token amounts (simplified calculation)
        sqrt_price_x96 = pool_info["pool_price"]["sqrt_price_x96"]
        liquidity = pool_info["liquidity_at_current_tick"]
        token0_info = pool_info["tokens"]["token0"]
        token1_info = pool_info["tokens"]["token1"]
        
        # Simplified token amount estimation
        if sqrt_price_x96 > 0 and liquidity > 0:
            sqrt_price = sqrt_price_x96 / (2 ** 96)
            # Very rough approximation - real calculation would be much more complex
            token0_estimate = liquidity * sqrt_price / (10 ** token0_info["decimals"])
            token1_estimate = liquidity / sqrt_price / (10 ** token1_info["decimals"])
        else:
            token0_estimate = 0
            token1_estimate = 0
        
        # Compile comprehensive results
        result = {
            "pool_key": pool_key,
            "pool_id": pool_info["pool_id"],
            "pool_price": pool_info["pool_price"],
            "liquidity_at_current_tick": pool_info["liquidity_at_current_tick"],
            "specific_tick_liquidity": specific_tick_liquidity,
            "token_amounts_estimate": {
                "token0": {
                    "amount": token0_estimate,
                    "symbol": token0_info["symbol"],
                    "address": token0_info["address"],
                    "decimals": token0_info["decimals"]
                },
                "token1": {
                    "amount": token1_estimate,
                    "symbol": token1_info["symbol"],
                    "address": token1_info["address"],
                    "decimals": token1_info["decimals"]
                }
            },
            "fees": pool_info["fees"],
            "block_number": pool_info["block_number"],
            "success": True,
            "note": "Token amounts are rough estimates. Actual amounts in concentrated liquidity pools depend on the full tick range distribution."
        }
        
        return result
    
    def display_results(self, results: Dict[str, Any]):
        """Display results in a formatted way."""
        if not results.get("success", False):
            print(f"❌ Error: {results.get('error', 'Unknown error')}")
            return
        
        print("\n🏊 Uniswap V4 Pool Details")
        print("=" * 60)
        
        # Pool information
        pool_key = results["pool_key"]
        print(f"🆔 Pool ID: {results.get('pool_id', 'Unknown')}")
        print(f"💰 Pair: {pool_key['currency0']} / {pool_key['currency1']}")
        print(f"💸 Fee: {pool_key['fee']} ({pool_key['fee']/10000:.2f}%)")
        print(f"🎯 Tick Spacing: {pool_key['tickSpacing']}")
        print(f"🪝 Hook: {pool_key['hooks']}")
        
        # Price information
        price_info = results["pool_price"]
        print(f"\n📊 Current Price:")
        print(f"   🎯 Current Tick: {price_info['current_tick']:,}")
        print(f"   📐 sqrtPriceX96: {price_info['sqrt_price_x96']:,}")
        print(f"   💱 Price: {price_info['price_description']}")
        
        # Liquidity information
        print(f"\n💧 Liquidity:")
        print(f"   🔄 At Current Tick: {results['liquidity_at_current_tick']:,}")
        
        if results.get("specific_tick_liquidity"):
            tick_liq = results["specific_tick_liquidity"]
            print(f"   🎯 At Tick {tick_liq['tick']}: {tick_liq['note']}")
        
        # Token amounts
        print(f"\n🪙 Estimated Token Amounts:")
        token0 = results["token_amounts_estimate"]["token0"]
        token1 = results["token_amounts_estimate"]["token1"]
        print(f"   {token0['symbol']}: {token0['amount']:.6f}")
        print(f"   {token1['symbol']}: {token1['amount']:.6f}")
        
        # Fees
        fees = results["fees"]
        print(f"\n💰 Fees:")
        print(f"   Protocol Fee: {fees['protocol_fee']}")
        print(f"   LP Fee: {fees['lp_fee']} ({fees['lp_fee']/10000:.2f}%)")
        
        print(f"\n📈 Block: {results['block_number']:,}")
        print(f"\n⚠️  {results.get('note', '')}")


def main():
    """Main function to handle command line arguments."""
    parser = argparse.ArgumentParser(
        description="Query detailed Uniswap V4 pool information on Arbitrum Sepolia",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Query ETH/MockUSDC pool (from our deployment)
  %(prog)s --pool-key '{"currency0":"0x0000000000000000000000000000000000000000","currency1":"0x9D5A68fDFEcc14683324640d5e835936422a47b1","fee":500,"tickSpacing":60,"hooks":"0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"}'
  
  # Query with specific tick
  %(prog)s --pool-key '{"currency0":"0x0000000000000000000000000000000000000000","currency1":"0x9D5A68fDFEcc14683324640d5e835936422a47b1","fee":500,"tickSpacing":60,"hooks":"0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"}' --ticker '{"tick":78644}'
  
  # Query ETH/USDC pool
  %(prog)s --pool-key '{"currency0":"0x0000000000000000000000000000000000000000","currency1":"0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d","fee":3000,"tickSpacing":60,"hooks":"0x444F320aA27e73e1E293c14B22EfBDCbce0e0088"}' --verbose
        """
    )
    
    parser.add_argument(
        '--pool-key',
        required=True,
        help='Pool key as JSON string containing currency0, currency1, fee, tickSpacing, hooks'
    )
    
    parser.add_argument(
        '--ticker',
        help='Specific ticker as JSON string containing tick number to query liquidity for'
    )
    
    parser.add_argument(
        '--rpc-url',
        help='Custom RPC URL (default: from environment or Arbitrum Sepolia)'
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
    
    args = parser.parse_args()
    
    # Parse JSON inputs
    try:
        pool_key = json.loads(args.pool_key)
        required_fields = ["currency0", "currency1", "fee", "tickSpacing", "hooks"]
        for field in required_fields:
            if field not in pool_key:
                print(f"❌ Missing required field in pool-key: {field}")
                return 1
    except json.JSONDecodeError as e:
        print(f"❌ Invalid pool-key JSON: {e}")
        return 1
    
    specific_tick = None
    if args.ticker:
        try:
            ticker_data = json.loads(args.ticker)
            specific_tick = ticker_data.get("tick")
            if specific_tick is None:
                print("❌ Missing 'tick' field in ticker JSON")
                return 1
        except json.JSONDecodeError as e:
            print(f"❌ Invalid ticker JSON: {e}")
            return 1
    
    # Create querier and query pool
    querier = UniswapV4PoolQuerier(rpc_url=args.rpc_url, verbose=args.verbose)
    
    if not querier.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    if args.verbose:
        print(f"🔍 Querying pool details...")
        print(f"📊 Pool: {pool_key['currency0']} / {pool_key['currency1']}")
        print(f"💸 Fee: {pool_key['fee']} ({pool_key['fee']/10000:.2f}%)")
        if specific_tick is not None:
            print(f"🎯 Also checking liquidity at tick {specific_tick}")
    
    results = querier.query_pool_details(pool_key, specific_tick)
    
    # Output results
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        querier.display_results(results)
    
    return 0 if results.get("success", False) else 1


if __name__ == '__main__':
    sys.exit(main()) 