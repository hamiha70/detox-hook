#!/usr/bin/env python3
"""
Simple SwapRouterFixed Test Script
==================================

This script executes a tiny swap using the existing SwapRouterFixed configuration (Pool 2).
It's designed to be simple and reliable for testing DetoxHook MEV protection.

Usage:
    python simple_swap_test.py --dry-run          # Simulate without sending transaction
    python simple_swap_test.py --swap 0.00001     # Execute tiny swap (default)
    python simple_swap_test.py --verbose          # Show detailed output

Examples:
    python simple_swap_test.py                    # Execute default tiny swap
    python simple_swap_test.py --dry-run --verbose # Detailed simulation
"""

import os
import sys
import argparse
from typing import Dict, Optional, Any

# Try to import web3 and related dependencies
try:
    from web3 import Web3
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


class SimpleSwapTester:
    """Simple SwapRouterFixed tester for DetoxHook."""
    
    # Contract addresses on Arbitrum Sepolia
    SWAP_ROUTER_FIXED_ADDRESS = "0x6cBf35A8fBEc26b5e16c7774B41710e369C97CB7"
    
    # Simple SwapRouterFixed ABI - just what we need
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
        }
    ]
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False):
        """Initialize the simple swap tester."""
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
            except Exception:
                pass
        
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
    
    def get_pool_info(self) -> Dict[str, Any]:
        """Get current pool configuration."""
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
                "fee_percent": config[2] / 10000,
                "pool_name": "Pool 2 (ETH/USDC 0.05%)" if config[2] == 500 else f"Custom Pool ({config[2]/10000:.2f}%)",
                "success": True
            }
        except Exception as e:
            return {"error": f"Failed to get pool config: {str(e)}", "success": False}
    
    def execute_swap(self, swap_amount_eth: float = 0.00001, dry_run: bool = False) -> Dict[str, Any]:
        """Execute a tiny ETH->USDC swap."""
        if not self.swap_router:
            return {"error": "Not connected to contract", "success": False}
        
        if self.verbose:
            print(f"💱 Executing swap: {swap_amount_eth} ETH -> USDC")
        
        # Get private key for transaction
        private_key = os.getenv('DEPLOYMENT_KEY')
        if not private_key:
            return {"error": "DEPLOYMENT_KEY not found in environment", "success": False}
        
        try:
            # Get account
            account = self.w3.eth.account.from_key(private_key)
            
            # Check account balance
            balance_wei = self.w3.eth.get_balance(account.address)
            balance_eth = balance_wei / 10**18
            
            if balance_eth < swap_amount_eth + 0.001:  # Include gas costs
                return {
                    "error": f"Insufficient balance: {balance_eth:.6f} ETH, need {swap_amount_eth + 0.001:.6f} ETH",
                    "success": False
                }
            
            # Convert ETH amount to wei (negative for exact input)
            amount_wei = -int(swap_amount_eth * 10**18)
            zero_for_one = True  # ETH (currency0) -> USDC (currency1)
            update_data = b''  # Empty update data
            
            if dry_run:
                # Simulate the swap
                try:
                    # Check if we can call the function
                    self.swap_router.functions.swap(
                        amount_wei, zero_for_one, update_data
                    ).call({
                        'from': account.address,
                        'value': int(swap_amount_eth * 10**18)
                    })
                    
                    # Estimate gas
                    gas_estimate = self.swap_router.functions.swap(
                        amount_wei, zero_for_one, update_data
                    ).estimate_gas({
                        'from': account.address,
                        'value': int(swap_amount_eth * 10**18)
                    })
                    
                    return {
                        "swap_amount_eth": swap_amount_eth,
                        "amount_wei": amount_wei,
                        "zero_for_one": zero_for_one,
                        "gas_estimate": gas_estimate,
                        "account_balance_eth": balance_eth,
                        "dry_run": True,
                        "success": True
                    }
                except Exception as e:
                    return {"error": f"Swap simulation failed: {str(e)}", "success": False}
            
            # Build and send swap transaction
            nonce = self.w3.eth.get_transaction_count(account.address)
            
            # Use EIP-1559 gas pricing for better compatibility
            try:
                # Get EIP-1559 style pricing
                latest_block = self.w3.eth.get_block('latest')
                base_fee = latest_block.get('baseFeePerGas', 0)
                max_priority_fee = min(self.w3.eth.max_priority_fee, 2000000000)  # Cap at 2 gwei
                max_fee_per_gas = (base_fee * 2) + max_priority_fee  # 2x base fee + priority
                
                transaction = self.swap_router.functions.swap(
                    amount_wei, zero_for_one, update_data
                ).build_transaction({
                    'from': account.address,
                    'value': int(swap_amount_eth * 10**18),  # Send ETH for the swap
                    'gas': 800000,  # High gas limit for DetoxHook + Pyth oracle calls
                    'maxFeePerGas': max_fee_per_gas,
                    'maxPriorityFeePerGas': max_priority_fee,
                    'nonce': nonce,
                    'chainId': self.w3.eth.chain_id,
                    'type': 2  # EIP-1559 transaction
                })
            except:
                # Fallback to legacy pricing with buffer
                gas_price = self.w3.eth.gas_price
                buffered_gas_price = int(gas_price * 1.5)  # 50% buffer
                
                transaction = self.swap_router.functions.swap(
                    amount_wei, zero_for_one, update_data
                ).build_transaction({
                    'from': account.address,
                    'value': int(swap_amount_eth * 10**18),  # Send ETH for the swap
                    'gas': 800000,  # High gas limit for DetoxHook + Pyth oracle calls
                    'gasPrice': buffered_gas_price,
                    'nonce': nonce,
                    'chainId': self.w3.eth.chain_id
                })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, private_key)
            raw_transaction = getattr(signed_txn, 'rawTransaction', getattr(signed_txn, 'raw_transaction', None))
            
            if raw_transaction is None:
                return {"error": "Could not get raw transaction data", "success": False}
            
            tx_hash = self.w3.eth.send_raw_transaction(raw_transaction)
            
            if self.verbose:
                print(f"📤 Swap transaction sent: {tx_hash.hex()}")
                print("⏳ Waiting for confirmation...")
            
            # Wait for receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
            
            return {
                "tx_hash": tx_hash.hex(),
                "block_number": receipt['blockNumber'],
                "gas_used": receipt['gasUsed'],
                "status": receipt['status'],
                "swap_amount_eth": swap_amount_eth,
                "amount_wei": amount_wei,
                "account_balance_eth": balance_eth,
                "success": receipt['status'] == 1
            }
            
        except Exception as e:
            return {"error": f"Swap failed: {str(e)}", "success": False}


def main():
    """Main function to handle command line arguments and execute the test."""
    parser = argparse.ArgumentParser(
        description="Simple SwapRouterFixed test for DetoxHook",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Execute default tiny swap (0.00001 ETH)
  %(prog)s --dry-run --verbose       # Detailed simulation without sending tx
  %(prog)s --swap 0.0001             # Larger swap amount
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
        '--rpc-url',
        help='Custom RPC URL (default: from .env or Arbitrum Sepolia)'
    )
    
    args = parser.parse_args()
    
    # Create tester
    tester = SimpleSwapTester(rpc_url=args.rpc_url, verbose=args.verbose)
    
    if not tester.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    print("🧪 Simple SwapRouterFixed Test")
    print("=" * 40)
    
    # Get pool info
    pool_info = tester.get_pool_info()
    if not pool_info.get("success"):
        print(f"❌ Could not get pool info: {pool_info.get('error', 'Unknown')}")
        return 1
    
    if args.verbose:
        print("🏊 Current Pool Configuration:")
        print(f"   Pool: {pool_info['pool_name']}")
        print(f"   Currency0 (ETH): {pool_info['currency0']}")
        print(f"   Currency1 (USDC): {pool_info['currency1']}")
        print(f"   Fee: {pool_info['fee']} ({pool_info['fee_percent']}%)")
        print(f"   TickSpacing: {pool_info['tickSpacing']}")
        print(f"   DetoxHook: {pool_info['hooks']}")
        print()
    
    # Execute swap
    result = tester.execute_swap(args.swap, args.dry_run)
    
    # Display results
    if args.dry_run:
        print("🔍 Simulation Results:")
    else:
        print("📊 Swap Results:")
    
    if result.get("success"):
        print(f"✅ Swap successful: {args.swap} ETH -> USDC")
        if args.dry_run:
            print(f"   Gas estimate: {result.get('gas_estimate', 'Unknown'):,}")
            print(f"   Account balance: {result.get('account_balance_eth', 'Unknown'):.6f} ETH")
        else:
            print(f"   Transaction: {result.get('tx_hash', 'Unknown')}")
            print(f"   Block: {result.get('block_number', 'Unknown'):,}")
            print(f"   Gas used: {result.get('gas_used', 'Unknown'):,}")
        
        print(f"\n🛡️  DetoxHook MEV protection was active during this swap!")
        print(f"🎯 Pool: {pool_info['pool_name']}")
    else:
        print(f"❌ Swap failed: {result.get('error', 'Unknown')}")
    
    return 0 if result.get("success") else 1


if __name__ == '__main__':
    sys.exit(main()) 