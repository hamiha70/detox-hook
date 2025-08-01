#!/usr/bin/env python3
"""
MockUSDC Token Transfer Script
============================

This script transfers MockUSDC tokens from one wallet to another on Arbitrum Sepolia.
It takes wallet addresses, private key, and amount as command line arguments.

Usage:
    python3 move_mock.py <from_address> <private_key> <to_address> <amount>
    python3 move_mock.py --from 0x1234... --key 0xabcd... --to 0x5678... --amount 100
    
Examples:
    python3 move_mock.py 0x1234... 0xabcd... 0x5678... 100
    python3 move_mock.py --from 0x1234... --key 0xabcd... --to 0x5678... --amount 50 --dry-run
    python3 move_mock.py --from 0x1234... --key 0xabcd... --to 0x5678... --amount 25 --verbose
"""

import os
import sys
import argparse
import json
from typing import Dict, Any, Optional, Tuple
from pathlib import Path
from decimal import Decimal, getcontext

# Set high precision for financial calculations
getcontext().prec = 50

# Try to import web3
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

# Import our environment loader
try:
    from load_env import EnvLoader
except ImportError:
    print("⚠️  Environment loader not found. Some features may be limited.")
    EnvLoader = None


class MockUSDCTransfer:
    """Transfers MockUSDC tokens between wallet addresses."""
    
    # MockUSDC contract address on Arbitrum Sepolia
    MOCK_USDC_ADDRESS = "0x9D5A68fDFEcc14683324640D5e835936422a47b1"
    
    # ERC-20 ABI (minimal required functions)
    ERC20_ABI = [
        {
            "constant": True,
            "inputs": [{"name": "_owner", "type": "address"}],
            "name": "balanceOf",
            "outputs": [{"name": "balance", "type": "uint256"}],
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
            "name": "symbol",
            "outputs": [{"name": "", "type": "string"}],
            "type": "function"
        },
        {
            "constant": False,
            "inputs": [
                {"name": "_to", "type": "address"},
                {"name": "_value", "type": "uint256"}
            ],
            "name": "transfer",
            "outputs": [{"name": "", "type": "bool"}],
            "type": "function"
        },
        {
            "constant": True,
            "inputs": [
                {"name": "_owner", "type": "address"},
                {"name": "_spender", "type": "address"}
            ],
            "name": "allowance",
            "outputs": [{"name": "", "type": "uint256"}],
            "type": "function"
        },
        {
            "constant": False,
            "inputs": [
                {"name": "_spender", "type": "address"},
                {"name": "_value", "type": "uint256"}
            ],
            "name": "approve",
            "outputs": [{"name": "", "type": "bool"}],
            "type": "function"
        }
    ]
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False, dry_run: bool = False):
        self.verbose = verbose
        self.dry_run = dry_run
        self.rpc_url = rpc_url or self._get_rpc_url()
        self.w3 = None
        self.mock_usdc = None
        self.account = None
        
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
            
            self.mock_usdc = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.MOCK_USDC_ADDRESS),
                abi=self.ERC20_ABI
            )
            
            if self.verbose:
                print(f"✅ Connected to Arbitrum Sepolia via {self.rpc_url}")
                print(f"📄 MockUSDC: {self.MOCK_USDC_ADDRESS}")
                
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            self.w3 = None
            self.mock_usdc = None
    
    def _validate_address(self, address: str) -> bool:
        """Validate wallet address format."""
        if not self.w3:
            return False
        
        try:
            return self.w3.is_address(address)
        except:
            return False
    
    def _validate_private_key(self, private_key: str) -> bool:
        """Validate private key format."""
        try:
            # Remove 0x prefix if present
            if private_key.startswith('0x'):
                private_key = private_key[2:]
            
            # Check if it's a valid hex string of correct length
            if len(private_key) != 64:
                return False
            
            # Try to create account from private key
            self.w3.eth.account.from_key('0x' + private_key)
            return True
        except:
            return False
    
    def _get_token_info(self) -> Dict[str, Any]:
        """Get MockUSDC token information."""
        try:
            return {
                "symbol": self.mock_usdc.functions.symbol().call(),
                "decimals": self.mock_usdc.functions.decimals().call(),
                "address": self.MOCK_USDC_ADDRESS
            }
        except Exception as e:
            if self.verbose:
                print(f"❌ Error getting token info: {e}")
            return {"symbol": "MockUSDC", "decimals": 6, "address": self.MOCK_USDC_ADDRESS}
    
    def _format_amount(self, amount: int, decimals: int = 6) -> str:
        """Format token amount for display."""
        try:
            decimal_amount = Decimal(amount) / Decimal(10 ** decimals)
            return f"{decimal_amount:,.6f}"
        except:
            return f"{amount:,}"
    
    def _parse_amount(self, amount_str: str, decimals: int = 6) -> int:
        """Parse amount string to token units."""
        try:
            # Handle different input formats
            if amount_str.endswith('k') or amount_str.endswith('K'):
                amount_str = amount_str[:-1] + '000'
            elif amount_str.endswith('m') or amount_str.endswith('M'):
                amount_str = amount_str[:-1] + '000000'
            
            decimal_amount = Decimal(amount_str)
            token_units = int(decimal_amount * Decimal(10 ** decimals))
            return token_units
        except Exception as e:
            if self.verbose:
                print(f"❌ Error parsing amount '{amount_str}': {e}")
            return 0
    
    def get_balance(self, address: str) -> Optional[Dict[str, Any]]:
        """Get MockUSDC balance for an address."""
        if not self.w3 or not self.mock_usdc:
            return None
        
        try:
            balance = self.mock_usdc.functions.balanceOf(
                Web3.to_checksum_address(address)
            ).call()
            
            token_info = self._get_token_info()
            formatted_balance = self._format_amount(balance, token_info["decimals"])
            
            return {
                "address": Web3.to_checksum_address(address),
                "balance": balance,
                "formatted_balance": formatted_balance,
                "symbol": token_info["symbol"],
                "success": True
            }
        except Exception as e:
            if self.verbose:
                print(f"❌ Error getting balance for {address}: {e}")
            return None
    
    def transfer_tokens(self, from_address: str, private_key: str, to_address: str, 
                       amount: int) -> Dict[str, Any]:
        """Transfer MockUSDC tokens from one address to another."""
        if not self.w3 or not self.mock_usdc:
            return {"error": "Not connected to blockchain", "success": False}
        
        try:
            # Validate addresses
            if not self._validate_address(from_address):
                return {"error": f"Invalid from address: {from_address}", "success": False}
            
            if not self._validate_address(to_address):
                return {"error": f"Invalid to address: {to_address}", "success": False}
            
            # Validate private key
            if not self._validate_private_key(private_key):
                return {"error": "Invalid private key format", "success": False}
            
            # Ensure private key has 0x prefix
            if not private_key.startswith('0x'):
                private_key = '0x' + private_key
            
            # Create account from private key
            try:
                self.account = self.w3.eth.account.from_key(private_key)
                if self.account.address.lower() != from_address.lower():
                    return {"error": "Private key doesn't match from address", "success": False}
            except Exception as e:
                return {"error": f"Invalid private key: {e}", "success": False}
            
            # Check balances
            from_balance = self.get_balance(from_address)
            if not from_balance or from_balance["balance"] < amount:
                return {"error": f"Insufficient balance. Available: {from_balance['formatted_balance'] if from_balance else 'Unknown'}", "success": False}
            
            # Build transaction
            nonce = self.w3.eth.get_transaction_count(from_address)
            
            transaction = self.mock_usdc.functions.transfer(
                Web3.to_checksum_address(to_address),
                amount
            ).build_transaction({
                'from': from_address,
                'gas': 100000,
                'gasPrice': self.w3.eth.gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id
            })
            
            if self.dry_run:
                return {
                    "success": True,
                    "dry_run": True,
                    "transaction": {
                        "from": from_address,
                        "to": to_address,
                        "amount": amount,
                        "gas": transaction['gas'],
                        "gasPrice": transaction['gasPrice']
                    }
                }
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, private_key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.rawTransaction)
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            if receipt.status == 1:
                # Get updated balances
                new_from_balance = self.get_balance(from_address)
                new_to_balance = self.get_balance(to_address)
                
                return {
                    "success": True,
                    "transaction_hash": tx_hash.hex(),
                    "block_number": receipt.blockNumber,
                    "gas_used": receipt.gasUsed,
                    "from_balance_before": from_balance,
                    "from_balance_after": new_from_balance,
                    "to_balance_after": new_to_balance
                }
            else:
                return {"error": "Transaction failed", "success": False}
                
        except Exception as e:
            return {"error": f"Transfer failed: {str(e)}", "success": False}
    
    def display_results(self, result: Dict[str, Any]):
        """Display transfer results."""
        if not result.get("success", False):
            print(f"❌ Transfer failed: {result.get('error', 'Unknown error')}")
            return
        
        if result.get("dry_run", False):
            print("🧪 Dry Run Results")
            print("=" * 30)
            tx = result["transaction"]
            print(f"📤 From: {tx['from']}")
            print(f"📥 To: {tx['to']}")
            print(f"💰 Amount: {self._format_amount(tx['amount'])} MockUSDC")
            print(f"⛽ Gas: {tx['gas']:,}")
            print(f"⛽ Gas Price: {tx['gasPrice']:,} wei")
            print("✅ Transaction would succeed")
        else:
            print("✅ Transfer Successful!")
            print("=" * 30)
            print(f"🔗 Transaction: {result['transaction_hash']}")
            print(f"📦 Block: {result['block_number']:,}")
            print(f"⛽ Gas Used: {result['gas_used']:,}")
            
            # Show balance changes
            from_before = result['from_balance_before']
            from_after = result['from_balance_after']
            to_after = result['to_balance_after']
            
            print(f"\n📊 Balance Changes:")
            print(f"   📤 From: {from_before['formatted_balance']} → {from_after['formatted_balance']}")
            print(f"   📥 To: {to_after['formatted_balance']}")


def main():
    """Main function to handle command line arguments."""
    parser = argparse.ArgumentParser(
        description="Transfer MockUSDC tokens between wallet addresses",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 0x1234... 0xabcd... 0x5678... 100
  %(prog)s --from 0x1234... --key 0xabcd... --to 0x5678... --amount 50
  %(prog)s --from 0x1234... --key 0xabcd... --to 0x5678... --amount 25 --dry-run
        """
    )
    
    parser.add_argument(
        'from_address',
        nargs='?',
        help='Source wallet address'
    )
    
    parser.add_argument(
        'private_key',
        nargs='?',
        help='Private key for source wallet'
    )
    
    parser.add_argument(
        'to_address',
        nargs='?',
        help='Destination wallet address'
    )
    
    parser.add_argument(
        'amount',
        nargs='?',
        type=str,
        help='Amount to transfer (e.g., 100, 1.5k, 2.5m)'
    )
    
    parser.add_argument(
        '--from', '--from-address',
        dest='from_addr',
        help='Source wallet address'
    )
    
    parser.add_argument(
        '--key', '--private-key',
        dest='private_key_arg',
        help='Private key for source wallet'
    )
    
    parser.add_argument(
        '--to', '--to-address',
        dest='to_addr',
        help='Destination wallet address'
    )
    
    parser.add_argument(
        '--amount',
        type=str,
        help='Amount to transfer'
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
        '--dry-run',
        action='store_true',
        help='Simulate the transaction without executing it'
    )
    
    args = parser.parse_args()
    
    # Determine addresses, private key, and amount
    from_address = args.from_addr or args.from_address
    private_key = args.private_key_arg or args.private_key
    to_address = args.to_addr or args.to_address
    amount_str = args.amount
    
    # Handle positional arguments
    if not from_address and args.from_address:
        from_address = args.from_address
    if not private_key and args.private_key:
        private_key = args.private_key
    if not to_address and args.to_address:
        to_address = args.to_address
    if not amount_str and args.amount:
        amount_str = args.amount
    
    # Create transfer object
    transfer = MockUSDCTransfer(rpc_url=args.rpc_url, verbose=args.verbose, dry_run=args.dry_run)
    
    if not transfer.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    # Validate required parameters
    if not from_address:
        print("❌ No source address provided. Use --from or positional argument")
        return 1
    
    if not private_key:
        print("❌ No private key provided. Use --key or positional argument")
        return 1
    
    if not to_address:
        print("❌ No destination address provided. Use --to or positional argument")
        return 1
    
    if not amount_str:
        print("❌ No amount provided. Use --amount or positional argument")
        return 1
    
    # Parse amount
    token_info = transfer._get_token_info()
    amount = transfer._parse_amount(amount_str, token_info["decimals"])
    
    if amount <= 0:
        print(f"❌ Invalid amount: {amount_str}")
        return 1
    
    if args.verbose:
        print(f"🔍 Transfer Details:")
        print(f"   📤 From: {from_address}")
        print(f"   🔑 Private Key: {private_key[:10]}...{private_key[-4:]}")
        print(f"   📥 To: {to_address}")
        print(f"   💰 Amount: {transfer._format_amount(amount)} {token_info['symbol']}")
        print(f"   🧪 Dry Run: {args.dry_run}")
        print()
    
    # Check balances before transfer
    if args.verbose:
        from_balance = transfer.get_balance(from_address)
        to_balance = transfer.get_balance(to_address)
        
        if from_balance:
            print(f"📊 Source Balance: {from_balance['formatted_balance']} {from_balance['symbol']}")
        if to_balance:
            print(f"📊 Destination Balance: {to_balance['formatted_balance']} {to_balance['symbol']}")
        print()
    
    # Execute transfer
    result = transfer.transfer_tokens(from_address, private_key, to_address, amount)
    
    # Display results
    transfer.display_results(result)
    
    return 0 if result.get("success", False) else 1


if __name__ == '__main__':
    sys.exit(main()) 