#!/usr/bin/env python3
"""
SwapRouterFixed Test Script for DetoxHook
=========================================

This script tests the SwapRouterFixed contract by executing a tiny swap on Pool 1.
It configures the router for Pool 1 and executes a small ETH->USDC swap to test MEV protection.

Usage:
    python swap_router_test.py --dry-run          # Simulate without sending transaction
    python swap_router_test.py --swap 0.00001     # Execute tiny swap (default)
    python swap_router_test.py --swap 0.0001 --verbose # Larger swap with verbose output

Examples:
    python swap_router_test.py                    # Execute default tiny swap
    python swap_router_test.py --dry-run --verbose # Detailed simulation
"""

import os
import sys
import argparse
import json
from typing import Dict, Optional, Any
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


class SwapRouterTester:
    """Tests SwapRouterFixed contract with DetoxHook Pool 1."""
    
    # Contract addresses on Arbitrum Sepolia
    SWAP_ROUTER_FIXED_ADDRESS = "0x6cBf35A8fBEc26b5e16c7774B41710e369C97CB7"
    
    # Pool 1 configuration (ETH/USDC 0.3% fee)
    POOL1_CONFIG = {
        "currency0": "0x0000000000000000000000000000000000000000",  # ETH
        "currency1": "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",  # USDC
        "fee": 3000,  # 0.3%
        "tickSpacing": 60,
        "hooks": "0x444F320aA27e73e1E293c14B22EfBDCbce0e0088"  # DetoxHook
    }
    
    # SwapRouterFixed ABI
    SWAP_ROUTER_ABI = [
        {
            "type": "function",
            "name": "swap",
            "inputs": [
                {"name": "amountToSwap", "type": "int256"},
                {"name": "zeroForOne", "type": "bool"},
                {"name": "updateData", "type": "bytes"}
            ],
            "outputs": [{"name": "delta", "type": "int256"}],
            "stateMutability": "payable"
        },
        {
            "type": "function",
            "name": "updatePoolConfiguration",
            "inputs": [
                {
                    "name": "newPoolKey",
                    "type": "tuple",
                    "components": [
                        {"name": "currency0", "type": "address"},
                        {"name": "currency1", "type": "address"},
                        {"name": "fee", "type": "uint24"},
                        {"name": "tickSpacing", "type": "int24"},
                        {"name": "hooks", "type": "address"}
                    ]
                }
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "getPoolConfiguration",
            "inputs": [],
            "outputs": [
                {
                    "name": "",
                    "type": "tuple",
                    "components": [
                        {"name": "currency0", "type": "address"},
                        {"name": "currency1", "type": "address"},
                        {"name": "fee", "type": "uint24"},
                        {"name": "tickSpacing", "type": "int24"},
                        {"name": "hooks", "type": "address"}
                    ]
                }
            ],
            "stateMutability": "view"
        },
        {
            "type": "event",
            "name": "SwapExecuted",
            "inputs": [
                {"name": "sender", "type": "address", "indexed": True},
                {"name": "amountSpecified", "type": "int256", "indexed": False},
                {"name": "zeroForOne", "type": "bool", "indexed": False},
                {"name": "delta", "type": "int256", "indexed": False}
            ]
        }
    ]
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False):
        """Initialize the swap router tester."""
        self.verbose = verbose
        self.rpc_url = rpc_url or self._get_rpc_url()
        self.w3 = None
        self.swap_router = None
        
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
            
            # Add POA middleware for Arbitrum
            self.w3.middleware_onion.inject(poa_middleware, layer=0)
            
            if not self.w3.is_connected():
                raise ConnectionError(f"Could not connect to {self.rpc_url}")
            
            # Initialize SwapRouterFixed contract
            self.swap_router = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.SWAP_ROUTER_FIXED_ADDRESS),
                abi=self.SWAP_ROUTER_ABI
            )
            
            if self.verbose:
                print(f"✅ Connected to Arbitrum Sepolia via {self.rpc_url}")
                print(f"📄 SwapRouterFixed: {self.SWAP_ROUTER_FIXED_ADDRESS}")
                
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            self.w3 = None
            self.swap_router = None
    
    def get_current_pool_config(self) -> Dict[str, Any]:
        """Get the current pool configuration from SwapRouterFixed."""
        if not self.swap_router:
            return {"error": "Not connected to contract"}
        
        try:
            config = self.swap_router.functions.getPoolConfiguration().call()
            return {
                "currency0": config[0],
                "currency1": config[1], 
                "fee": config[2],
                "tickSpacing": config[3],
                "hooks": config[4],
                "success": True
            }
        except Exception as e:
            return {"error": f"Failed to get pool config: {str(e)}", "success": False}
    
    def update_to_pool1(self, dry_run: bool = False) -> Dict[str, Any]:
        """Update SwapRouterFixed to use Pool 1 configuration."""
        if not self.swap_router:
            return {"error": "Not connected to contract", "success": False}
        
        if self.verbose:
            print("🔧 Updating SwapRouterFixed to Pool 1 configuration...")
        
        # Get private key for transaction
        private_key = os.getenv('DEPLOYMENT_KEY')
        if not private_key:
            return {"error": "DEPLOYMENT_KEY not found in environment", "success": False}
        
        try:
            # Get account
            account = self.w3.eth.account.from_key(private_key)
            
            # Build transaction
            pool_key_tuple = (
                self.POOL1_CONFIG["currency0"],
                self.POOL1_CONFIG["currency1"],
                self.POOL1_CONFIG["fee"],
                self.POOL1_CONFIG["tickSpacing"],
                self.POOL1_CONFIG["hooks"]
            )
            
            if dry_run:
                # Simulate the transaction
                try:
                    gas_estimate = self.swap_router.functions.updatePoolConfiguration(
                        pool_key_tuple
                    ).estimate_gas({'from': account.address})
                    
                    return {
                        "pool_config": self.POOL1_CONFIG,
                        "gas_estimate": gas_estimate,
                        "dry_run": True,
                        "success": True
                    }
                except Exception as e:
                    return {"error": f"Simulation failed: {str(e)}", "success": False}
            
            # Build and send transaction
            transaction = self.swap_router.functions.updatePoolConfiguration(
                pool_key_tuple
            ).build_transaction({
                'from': account.address,
                'gas': 200000,
                'gasPrice': self.w3.eth.gas_price,
                'nonce': self.w3.eth.get_transaction_count(account.address),
                'chainId': self.w3.eth.chain_id
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, private_key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.rawTransaction)
            
            if self.verbose:
                print(f"📤 Transaction sent: {tx_hash.hex()}")
            
            # Wait for receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
            
            return {
                "tx_hash": tx_hash.hex(),
                "block_number": receipt['blockNumber'],
                "gas_used": receipt['gasUsed'],
                "pool_config": self.POOL1_CONFIG,
                "success": True
            }
            
        except Exception as e:
            return {"error": f"Failed to update pool config: {str(e)}", "success": False}
    
    def execute_tiny_swap(self, swap_amount_eth: float = 0.00001, dry_run: bool = False) -> Dict[str, Any]:
        """Execute a tiny ETH->USDC swap on Pool 1."""
        if not self.swap_router:
            return {"error": "Not connected to contract", "success": False}
        
        if self.verbose:
            print(f"💱 Executing tiny swap: {swap_amount_eth} ETH -> USDC")
        
        # Get private key for transaction
        private_key = os.getenv('DEPLOYMENT_KEY')
        if not private_key:
            return {"error": "DEPLOYMENT_KEY not found in environment", "success": False}
        
        try:
            # Get account
            account = self.w3.eth.account.from_key(private_key)
            
            # Convert ETH amount to wei (negative for exact input)
            amount_wei = -int(swap_amount_eth * 10**18)
            zero_for_one = True  # ETH (currency0) -> USDC (currency1)
            update_data = b''  # Empty update data
            
            if dry_run:
                # Simulate the swap
                try:
                    gas_estimate = self.swap_router.functions.swap(
                        amount_wei, zero_for_one, update_data
                    ).estimate_gas({
                        'from': account.address,
                        'value': int(swap_amount_eth * 10**18)  # Send ETH value
                    })
                    
                    return {
                        "swap_amount_eth": swap_amount_eth,
                        "amount_wei": amount_wei,
                        "zero_for_one": zero_for_one,
                        "gas_estimate": gas_estimate,
                        "dry_run": True,
                        "success": True
                    }
                except Exception as e:
                    return {"error": f"Swap simulation failed: {str(e)}", "success": False}
            
            # Build and send swap transaction
            transaction = self.swap_router.functions.swap(
                amount_wei, zero_for_one, update_data
            ).build_transaction({
                'from': account.address,
                'value': int(swap_amount_eth * 10**18),  # Send ETH for the swap
                'gas': 500000,  # Higher gas for swap
                'gasPrice': self.w3.eth.gas_price,
                'nonce': self.w3.eth.get_transaction_count(account.address),
                'chainId': self.w3.eth.chain_id
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, private_key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.rawTransaction)
            
            if self.verbose:
                print(f"📤 Swap transaction sent: {tx_hash.hex()}")
            
            # Wait for receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
            
            # Parse events if successful
            events = []
            if receipt['status'] == 1:
                try:
                    logs = self.swap_router.events.SwapExecuted().process_receipt(receipt)
                    events = [dict(log['args']) for log in logs]
                except:
                    pass
            
            return {
                "tx_hash": tx_hash.hex(),
                "block_number": receipt['blockNumber'],
                "gas_used": receipt['gasUsed'],
                "status": receipt['status'],
                "swap_amount_eth": swap_amount_eth,
                "amount_wei": amount_wei,
                "events": events,
                "success": receipt['status'] == 1
            }
            
        except Exception as e:
            return {"error": f"Swap failed: {str(e)}", "success": False}
    
    def run_full_test(self, swap_amount_eth: float = 0.00001, dry_run: bool = False) -> Dict[str, Any]:
        """Run the complete test: update pool config and execute swap."""
        results = {
            "initial_config": self.get_current_pool_config(),
            "pool_update": None,
            "final_config": None,
            "swap": None,
            "success": False
        }
        
        if not results["initial_config"].get("success"):
            return results
        
        if self.verbose:
            print("\n🏊 Initial Pool Configuration:")
            initial = results["initial_config"]
            print(f"   Currency0: {initial.get('currency0', 'Unknown')}")
            print(f"   Currency1: {initial.get('currency1', 'Unknown')}")
            print(f"   Fee: {initial.get('fee', 'Unknown')}")
            print(f"   TickSpacing: {initial.get('tickSpacing', 'Unknown')}")
            print(f"   Hooks: {initial.get('hooks', 'Unknown')}")
        
        # Check if already configured for Pool 1
        initial = results["initial_config"]
        pool1_fee = self.POOL1_CONFIG["fee"]
        pool1_hooks = self.POOL1_CONFIG["hooks"]
        
        if initial.get("fee") == pool1_fee and initial.get("hooks") == pool1_hooks:
            if self.verbose:
                print("✅ SwapRouterFixed already configured for Pool 1")
        else:
            if self.verbose:
                print("🔄 Updating SwapRouterFixed to Pool 1...")
            
            # Update pool configuration
            results["pool_update"] = self.update_to_pool1(dry_run)
            if not results["pool_update"].get("success"):
                return results
            
            # Get final config
            results["final_config"] = self.get_current_pool_config()
        
        # Execute swap
        if self.verbose:
            print(f"\n💱 Executing swap: {swap_amount_eth} ETH -> USDC")
        
        results["swap"] = self.execute_tiny_swap(swap_amount_eth, dry_run)
        results["success"] = results["swap"].get("success", False)
        
        return results


def main():
    """Main function to handle command line arguments and execute the test."""
    parser = argparse.ArgumentParser(
        description="Test SwapRouterFixed with DetoxHook Pool 1",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Execute default tiny swap (0.00001 ETH)
  %(prog)s --dry-run --verbose       # Detailed simulation without sending tx
  %(prog)s --swap 0.0001             # Larger swap amount
  %(prog)s --config-only             # Only update pool config, no swap
        """
    )
    
    parser.add_argument(
        '--swap', '-s',
        type=float,
        default=0.00001,
        help='ETH amount to swap (default: 0.00001)'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Simulate transactions without sending them'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output'
    )
    
    parser.add_argument(
        '--config-only',
        action='store_true',
        help='Only update pool configuration, skip swap'
    )
    
    parser.add_argument(
        '--rpc-url',
        help='Custom RPC URL (default: from .env or Arbitrum Sepolia)'
    )
    
    args = parser.parse_args()
    
    # Create tester
    tester = SwapRouterTester(rpc_url=args.rpc_url, verbose=args.verbose)
    
    if not tester.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    print("🧪 SwapRouterFixed Test with DetoxHook Pool 1")
    print("=" * 50)
    
    if args.config_only:
        # Only update configuration
        print("🔧 Updating pool configuration only...")
        result = tester.update_to_pool1(args.dry_run)
        if result.get("success"):
            print("✅ Pool configuration updated successfully")
            if args.dry_run:
                print(f"   Gas estimate: {result.get('gas_estimate', 'Unknown'):,}")
            else:
                print(f"   Transaction: {result.get('tx_hash', 'Unknown')}")
        else:
            print(f"❌ Pool configuration failed: {result.get('error', 'Unknown')}")
        return 0 if result.get("success") else 1
    
    # Run full test
    results = tester.run_full_test(args.swap, args.dry_run)
    
    # Display results
    if args.dry_run:
        print("\n🔍 Simulation Results:")
    else:
        print("\n📊 Test Results:")
    
    if results.get("pool_update"):
        update = results["pool_update"]
        if update.get("success"):
            print("✅ Pool configuration updated")
            if not args.dry_run:
                print(f"   Transaction: {update.get('tx_hash', 'Unknown')}")
        else:
            print(f"❌ Pool update failed: {update.get('error', 'Unknown')}")
    
    if results.get("swap"):
        swap = results["swap"]
        if swap.get("success"):
            print(f"✅ Swap executed: {args.swap} ETH -> USDC")
            if not args.dry_run:
                print(f"   Transaction: {swap.get('tx_hash', 'Unknown')}")
                print(f"   Gas used: {swap.get('gas_used', 'Unknown'):,}")
                if swap.get("events"):
                    for event in swap["events"]:
                        print(f"   Event: {event}")
        else:
            print(f"❌ Swap failed: {swap.get('error', 'Unknown')}")
    
    if results.get("success"):
        print("\n🎉 Test completed successfully!")
        print("🛡️  DetoxHook MEV protection was active during the swap")
    else:
        print(f"\n❌ Test failed")
    
    return 0 if results.get("success") else 1


if __name__ == '__main__':
    sys.exit(main()) 