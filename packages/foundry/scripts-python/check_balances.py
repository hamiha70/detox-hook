#!/usr/bin/env python3
"""
Wallet Balance Checker for DetoxHook
====================================

This script checks ETH and USDC balances for wallet addresses on Arbitrum Sepolia.
It integrates with the DetoxHook environment configuration and provides detailed
balance information for development and monitoring.

Usage:
    python check_balances.py                        # Check all wallets (default)
    python check_balances.py <address1> [address2] [address3] ...
    python check_balances.py --env-wallets
    python check_balances.py --all
    
Examples:
    python check_balances.py                        # Check all wallets (default)
    python check_balances.py 0x00cA5716A51f8E48055d03fCadE8CFE0A463Bab6
    python check_balances.py --env-wallets  # Check all wallets from .env
    python check_balances.py --all --verbose  # Check all with details
"""

import os
import sys
import argparse
import asyncio
from typing import List, Dict, Optional, Tuple
from pathlib import Path
import json

# Try to import web3, if not available, provide installation instructions
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


class BalanceChecker:
    """Checks ETH and token balances on Arbitrum Sepolia."""
    
    # Known token contracts on Arbitrum Sepolia
    TOKENS = {
        "USDC": {
            "address": "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d", 
            "decimals": 6,
            "symbol": "USDC"
        },
        "MockUSDC": {
            "address": "0x9D5A68fDFEcc14683324640D5e835936422a47b1", 
            "decimals": 6,
            "symbol": "MockUSDC"
        },
        # Add more tokens as needed
    }
    
    # ERC-20 ABI (minimal - just what we need)
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
            "constant": True,
            "inputs": [],
            "name": "name",
            "outputs": [{"name": "", "type": "string"}],
            "type": "function"
        }
    ]
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False):
        self.verbose = verbose
        self.rpc_url = rpc_url or self._get_rpc_url()
        self.w3 = None
        self._token_contracts = {}
        
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
            
            if self.verbose:
                print(f"✅ Connected to Arbitrum Sepolia via {self.rpc_url}")
                
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            self.w3 = None
    
    def _get_token_contract(self, token_address: str):
        """Get or create token contract instance."""
        if token_address not in self._token_contracts:
            try:
                contract = self.w3.eth.contract(
                    address=Web3.to_checksum_address(token_address),
                    abi=self.ERC20_ABI
                )
                self._token_contracts[token_address] = contract
            except Exception as e:
                if self.verbose:
                    print(f"⚠️  Could not create contract for {token_address}: {e}")
                return None
        
        return self._token_contracts[token_address]
    
    def _format_balance(self, balance: int, decimals: int = 18) -> str:
        """Format balance with proper decimal places."""
        if balance == 0:
            return "0.0"
        
        # Convert to human-readable format
        divisor = 10 ** decimals
        formatted = balance / divisor
        
        # Format with appropriate precision
        if formatted >= 1:
            return f"{formatted:,.6f}".rstrip('0').rstrip('.')
        else:
            # For small amounts, show more precision
            return f"{formatted:.8f}".rstrip('0').rstrip('.')
    
    def check_eth_balance(self, address: str) -> Optional[Dict]:
        """Check ETH balance for an address."""
        if not self.w3:
            return None
        
        try:
            checksum_address = Web3.to_checksum_address(address)
            balance_wei = self.w3.eth.get_balance(checksum_address)
            balance_eth = self._format_balance(balance_wei, 18)
            
            return {
                "symbol": "ETH",
                "balance_raw": balance_wei,
                "balance_formatted": balance_eth,
                "decimals": 18,
                "success": True
            }
            
        except Exception as e:
            if self.verbose:
                print(f"⚠️  ETH balance check failed for {address}: {e}")
            return {
                "symbol": "ETH",
                "error": str(e),
                "success": False
            }
    
    def check_token_balance(self, address: str, token_info: Dict) -> Optional[Dict]:
        """Check token balance for an address."""
        if not self.w3:
            return None
        
        try:
            contract = self._get_token_contract(token_info["address"])
            if not contract:
                return {
                    "symbol": token_info["symbol"],
                    "error": "Could not create contract",
                    "success": False
                }
            
            checksum_address = Web3.to_checksum_address(address)
            balance_raw = contract.functions.balanceOf(checksum_address).call()
            balance_formatted = self._format_balance(balance_raw, token_info["decimals"])
            
            return {
                "symbol": token_info["symbol"],
                "balance_raw": balance_raw,
                "balance_formatted": balance_formatted,
                "decimals": token_info["decimals"],
                "contract_address": token_info["address"],
                "success": True
            }
            
        except Exception as e:
            if self.verbose:
                print(f"⚠️  {token_info['symbol']} balance check failed for {address}: {e}")
            return {
                "symbol": token_info["symbol"],
                "error": str(e),
                "success": False
            }
    
    def check_address_balances(self, address: str) -> Dict:
        """Check all balances for a single address."""
        if not Web3.is_address(address):
            return {
                "address": address,
                "error": "Invalid address format",
                "balances": {}
            }
        
        balances = {}
        
        # Check ETH balance
        eth_balance = self.check_eth_balance(address)
        if eth_balance:
            balances["ETH"] = eth_balance
        
        # Check token balances
        for token_name, token_info in self.TOKENS.items():
            token_balance = self.check_token_balance(address, token_info)
            if token_balance:
                balances[token_name] = token_balance
        
        return {
            "address": Web3.to_checksum_address(address),
            "balances": balances,
            "success": len(balances) > 0
        }
    
    def get_env_wallets(self) -> List[str]:
        """Get wallet addresses from environment variables."""
        wallets = []
        
        # Load environment if needed
        if EnvLoader and not os.getenv('DEPLOYMENT_WALLET'):
            try:
                loader = EnvLoader(verbose=False, dry_run=False)
                loader.load_environment()
            except Exception:
                pass
        
        # Known wallet environment variables
        wallet_env_vars = [
            'DEPLOYMENT_WALLET',
            'DEPLOYMENT_WALLET_31337',
            'SWAPPER_WALLET', 
            'LIQUIDITY_PROVIDER_WALLET',
            'POOL_CREATION_WALLET'
        ]
        
        for env_var in wallet_env_vars:
            wallet = os.getenv(env_var)
            if wallet:
                # Clean the wallet address (remove comments and whitespace)
                cleaned_wallet = wallet.split('#')[0].strip()
                if cleaned_wallet and Web3.is_address(cleaned_wallet):
                    wallets.append(cleaned_wallet)
                    if self.verbose:
                        print(f"📋 Found wallet from {env_var}: {cleaned_wallet}")
        
        return wallets
    
    def display_results(self, results: List[Dict], show_empty: bool = False):
        """Display balance check results in a nice format."""
        print("\n🏦 DetoxHook Wallet Balance Report")
        print("=" * 50)
        
        total_addresses = len(results)
        successful_checks = sum(1 for r in results if r.get('success', False))
        
        print(f"📊 Checked {total_addresses} addresses, {successful_checks} successful")
        
        if not self.w3:
            print("⚠️  Not connected to blockchain")
            return
        
        try:
            latest_block = self.w3.eth.block_number
            print(f"📈 Latest block: {latest_block:,}")
        except:
            pass
        
        print()
        
        for result in results:
            address = result.get('address', 'Unknown')
            print(f"👛 Address: {address}")
            
            if 'error' in result:
                print(f"   ❌ Error: {result['error']}")
                print()
                continue
            
            balances = result.get('balances', {})
            has_balance = False
            
            for token, balance_info in balances.items():
                if not balance_info.get('success', False):
                    if self.verbose:
                        error = balance_info.get('error', 'Unknown error')
                        print(f"   ⚠️  {token}: Error - {error}")
                    continue
                
                balance_formatted = balance_info.get('balance_formatted', '0.0')
                balance_raw = balance_info.get('balance_raw', 0)
                
                if balance_raw > 0 or show_empty:
                    has_balance = True
                    symbol = balance_info.get('symbol', token)
                    
                    if balance_raw > 0:
                        print(f"   💰 {symbol}: {balance_formatted}")
                    else:
                        print(f"   🔹 {symbol}: {balance_formatted}")
                        
                    if self.verbose and 'contract_address' in balance_info:
                        print(f"      📄 Contract: {balance_info['contract_address']}")
            
            if not has_balance and not show_empty:
                print("   💸 All balances are zero")
            
            print()


def main():
    """Main function to handle command line arguments and execute balance checks."""
    parser = argparse.ArgumentParser(
        description="Check ETH and USDC balances for wallet addresses",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                                  # Check all wallets (default behavior)
  %(prog)s 0x00cA5716A51f8E48055d03fCadE8CFE0A463Bab6
  %(prog)s --env-wallets                    # Check wallets from .env
  %(prog)s --all --verbose                  # Check all with details
  %(prog)s address1 address2 --show-empty   # Show zero balances
        """
    )
    
    parser.add_argument(
        'addresses',
        nargs='*',
        help='Wallet addresses to check'
    )
    
    parser.add_argument(
        '--env-wallets',
        action='store_true',
        help='Check wallet addresses from environment variables'
    )
    
    parser.add_argument(
        '--all',
        action='store_true',
        help='Check all known wallets (combines addresses + env wallets)'
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
        '--show-empty',
        action='store_true',
        help='Show balances even when they are zero'
    )
    
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    
    args = parser.parse_args()
    
    # If no arguments provided, default to --all behavior
    if not args.addresses and not args.env_wallets and not args.all:
        args.all = True
        if args.verbose:
            print("💡 No arguments provided, defaulting to --all behavior")
    
    # Collect addresses to check
    addresses_to_check = []
    
    if args.addresses:
        addresses_to_check.extend(args.addresses)
    
    if args.env_wallets or args.all:
        checker = BalanceChecker(rpc_url=args.rpc_url, verbose=args.verbose)
        env_wallets = checker.get_env_wallets()
        addresses_to_check.extend(env_wallets)
        
        if args.verbose:
            print(f"📂 Found {len(env_wallets)} wallets from environment")
    
    # Remove duplicates while preserving order
    unique_addresses = []
    seen = set()
    for addr in addresses_to_check:
        if addr not in seen:
            unique_addresses.append(addr)
            seen.add(addr)
    
    if not unique_addresses:
        print("❌ No addresses provided. Use --help for usage information.")
        return 1
    
    # Create balance checker and check all addresses
    checker = BalanceChecker(rpc_url=args.rpc_url, verbose=args.verbose)
    
    if not checker.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    results = []
    for address in unique_addresses:
        if args.verbose:
            print(f"🔍 Checking {address}...")
        
        result = checker.check_address_balances(address)
        results.append(result)
    
    # Display results
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        checker.display_results(results, show_empty=args.show_empty)
    
    return 0


if __name__ == '__main__':
    sys.exit(main()) 