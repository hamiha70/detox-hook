#!/usr/bin/env python3
"""
Pool ID Generator Script
=======================

This script uses the PoolStateViewer contract to convert a pool key object
to a pool ID using the getIdByKey function.

Usage:
    python3 pool_id.py --pool-key '{"currency0":"0x...","currency1":"0x...","fee":500,"tickSpacing":10,"hooks":"0x..."}'
    python3 pool_id.py --pool-key '{"currency0":"0x0000000000000000000000000000000000000000","currency1":"0x9D5A68fDFEcc14683324640D5e835936422a47b1","fee":500,"tickSpacing":10,"hooks":"0x0000000000000000000000000000000000000000"}' --verbose
"""

import argparse
import json
import sys
import os
from pathlib import Path
from typing import Dict, Any

# Add parent directory to path for imports
sys.path.append(str(Path(__file__).parent))

try:
    from web3 import Web3
    from web3.contract import Contract
    WEB3_AVAILABLE = True
except ImportError:
    WEB3_AVAILABLE = False
    print("❌ Web3 not available. Install with: pip install web3")
    sys.exit(1)

try:
    from load_env import EnvLoader
    ENV_LOADER_AVAILABLE = True
except ImportError:
    ENV_LOADER_AVAILABLE = False
    print("⚠️  Environment loader not available")

# PoolStateViewer contract address
POOL_STATE_VIEWER_ADDRESS = "0xA0386BBB0d8F176D4EdCFfAD6Aa1CDa833f11380"

# ABI for PoolStateViewer contract (minimal for getIdByKey function)
POOL_STATE_VIEWER_ABI = [
    {
        "inputs": [
            {
                "internalType": "tuple",
                "name": "poolKey",
                "type": "tuple",
                "components": [
                    {"internalType": "address", "name": "currency0", "type": "address"},
                    {"internalType": "address", "name": "currency1", "type": "address"},
                    {"internalType": "uint24", "name": "fee", "type": "uint24"},
                    {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                    {"internalType": "address", "name": "hooks", "type": "address"}
                ]
            }
        ],
        "name": "getIdByKey",
        "outputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
        "stateMutability": "view",
        "type": "function"
    }
]

class PoolIdGenerator:
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
            print(f"❌ Connection Error: {e}")
            sys.exit(1)
    
    def validate_pool_key(self, pool_key: Dict[str, Any]) -> bool:
        """Validate the pool key object."""
        required_fields = ["currency0", "currency1", "fee", "tickSpacing", "hooks"]
        
        for field in required_fields:
            if field not in pool_key:
                print(f"❌ Missing required field: {field}")
                return False
        
        # Validate addresses
        for field in ["currency0", "currency1", "hooks"]:
            if not self.w3.is_address(pool_key[field]):
                print(f"❌ Invalid address for {field}: {pool_key[field]}")
                return False
        
        # Validate numeric fields
        if not isinstance(pool_key["fee"], int) or pool_key["fee"] < 0:
            print(f"❌ Invalid fee: {pool_key['fee']}")
            return False
        
        if not isinstance(pool_key["tickSpacing"], int) or pool_key["tickSpacing"] < 0:
            print(f"❌ Invalid tickSpacing: {pool_key['tickSpacing']}")
            return False
        
        return True
    
    def convert_pool_key_to_id(self, pool_key: Dict[str, Any]) -> str:
        """Convert a pool key object to a pool ID."""
        if not self.validate_pool_key(pool_key):
            raise ValueError("Invalid pool key")
        
        # Prepare the pool key tuple for the contract call
        pool_key_tuple = (
            pool_key["currency0"],
            pool_key["currency1"],
            pool_key["fee"],
            pool_key["tickSpacing"],
            pool_key["hooks"]
        )
        
        if self.verbose:
            print(f"\n📋 Pool Key:")
            print(f"   Currency0: {pool_key['currency0']}")
            print(f"   Currency1: {pool_key['currency1']}")
            print(f"   Fee: {pool_key['fee']}")
            print(f"   TickSpacing: {pool_key['tickSpacing']}")
            print(f"   Hooks: {pool_key['hooks']}")
        
        try:
            # Call the contract function
            pool_id = self.contract.functions.getIdByKey(pool_key_tuple).call()
            
            if self.verbose:
                print(f"\n✅ Pool ID generated successfully!")
                print(f"   Pool ID: {pool_id.hex()}")
            
            return pool_id.hex()
            
        except Exception as e:
            print(f"❌ Error generating pool ID: {e}")
            raise
    
    def display_pool_key_info(self, pool_key: Dict[str, Any], pool_id: str):
        """Display detailed information about the pool key and generated ID."""
        if not self.verbose:
            return
        
        print(f"\n📊 Pool Information:")
        print(f"=" * 50)
        print(f"Currency0: {pool_key['currency0']}")
        print(f"Currency1: {pool_key['currency1']}")
        print(f"Fee: {pool_key['fee']} ({(pool_key['fee'] / 10000):.4f}%)")
        print(f"TickSpacing: {pool_key['tickSpacing']}")
        print(f"Hooks: {pool_key['hooks']}")
        print(f"Pool ID: {pool_id}")
        print(f"=" * 50)

def load_environment() -> str:
    """Load RPC URL from environment variables."""
    rpc_url = os.getenv("ARBITRUM_SEPOLIA_RPC_URL")
    if not rpc_url and ENV_LOADER_AVAILABLE:
        loader = EnvLoader(verbose=False)
        loader.load_environment()
        rpc_url = os.getenv("ARBITRUM_SEPOLIA_RPC_URL")
    return rpc_url

def main():
    parser = argparse.ArgumentParser(
        description="Convert a pool key object to a pool ID using PoolStateViewer contract."
    )
    parser.add_argument(
        "--pool-key",
        type=str,
        required=True,
        help="Pool key object in JSON format"
    )
    parser.add_argument(
        "--rpc-url",
        type=str,
        help="Optional: RPC URL for the Arbitrum Sepolia network. Defaults to ARBITRUM_SEPOLIA_RPC_URL env var."
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose output."
    )
    
    args = parser.parse_args()
    
    # Parse pool key JSON
    try:
        pool_key = json.loads(args.pool_key)
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON format: {e}")
        sys.exit(1)
    
    # Get RPC URL
    rpc_url = args.rpc_url
    if not rpc_url:
        rpc_url = load_environment()
    
    if not rpc_url:
        print("❌ Error: RPC URL not provided and ARBITRUM_SEPOLIA_RPC_URL environment variable not set.")
        sys.exit(1)
    
    try:
        # Initialize the pool ID generator
        generator = PoolIdGenerator(rpc_url, args.verbose)
        
        # Convert pool key to pool ID
        pool_id = generator.convert_pool_key_to_id(pool_key)
        
        # Display information
        generator.display_pool_key_info(pool_key, pool_id)
        
        # Output the pool ID (for scripting)
        if not args.verbose:
            print(pool_id)
        
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main() 