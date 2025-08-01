#!/usr/bin/env python3
"""
Add Liquidity to POOL5 (ETH/MockUSDC 0.05%)
========================================

This script adds liquidity to DetoxHook POOL5 (ETH/MockUSDC 0.05% fee pool)
using the provide_liquidity.py script with predefined parameters.

Pool Details:
- Pool ID: 0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa
- Pair: ETH/MockUSDC
- Fee: 500 (0.05%)
- Tick Spacing: 60
- Hook: DetoxHook

Usage:
    python3 add_liquidity_pool5.py [--dry-run] [--verbose] [--amount <amount>]
"""

import os
import sys
import json
import subprocess
import argparse
from pathlib import Path
from typing import Optional


class Pool5LiquidityProvider:
    """Adds liquidity to DetoxHook POOL5 (ETH/MockUSDC 0.05%)."""
    
    # POOL5 configuration
    POOL5_ID = "0xfd3578eb0674a59b02da434a248e1c4120554a747a994409c62deafdb9ca6daa"
    POOL5_DESCRIPTION = "ETH/MockUSDC 0.05% fee pool (~2600 MockUSDC/ETH)"
    
    # Default liquidity amounts (in MockUSDC)
    DEFAULT_MOCKUSDC_AMOUNT = 100  # 100 MockUSDC
    DEFAULT_ETH_AMOUNT = 0.04  # 0.04 ETH (approximately $100 at $2500/ETH)
    
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.script_dir = Path(__file__).parent
        self.provide_liquidity_script = self.script_dir / "provide_liquidity.py"
    
    def get_env_wallet(self) -> Optional[str]:
        """Get wallet address from environment variables."""
        # Try to load environment
        try:
            from load_env import EnvLoader
            loader = EnvLoader(verbose=False, dry_run=False)
            if loader.load_environment():
                # Check for deployment wallet
                wallet = os.getenv('DEPLOYMENT_WALLET')
                if wallet:
                    return wallet.split('#')[0].strip()  # Remove comments
                
                # Check for other wallet variables
                for env_var in ['LIQUIDITY_PROVIDER_WALLET', 'SWAPPER_WALLET']:
                    wallet = os.getenv(env_var)
                    if wallet:
                        return wallet.split('#')[0].strip()
        except Exception as e:
            if self.verbose:
                print(f"⚠️  Could not load environment: {e}")
        
        return None
    
    def build_command(self, wallet_address: str, mockusdc_amount: Optional[float] = None, 
                     eth_amount: Optional[float] = None, dry_run: bool = False) -> list:
        """Build the command to call provide_liquidity.py."""
        
        # Use default amounts if none specified
        if mockusdc_amount is None and eth_amount is None:
            mockusdc_amount = self.DEFAULT_MOCKUSDC_AMOUNT
            eth_amount = self.DEFAULT_ETH_AMOUNT
        
        cmd = [
            "python3",
            str(self.provide_liquidity_script),
            wallet_address,
            self.POOL5_ID
        ]
        
        # Add amount parameters
        if mockusdc_amount is not None:
            cmd.extend(["--usdc-amount", str(mockusdc_amount)])
        
        if eth_amount is not None:
            cmd.extend(["--eth-amount", str(eth_amount)])
        
        # Add flags
        if dry_run:
            cmd.append("--dry-run")
        
        if self.verbose:
            cmd.append("--verbose")
        
        return cmd
    
    def display_pool_info(self):
        """Display information about POOL5."""
        print("🏊 DetoxHook POOL5 Information")
        print("=" * 40)
        print(f"📊 Description: {self.POOL5_DESCRIPTION}")
        print(f"🆔 Pool ID: {self.POOL5_ID}")
        print(f"💰 Pair: ETH/MockUSDC")
        print(f"💸 Fee: 500 (0.05%)")
        print(f"🎯 Tick Spacing: 60")
        print(f"🪝 Hook: DetoxHook")
        print(f"💱 Target Price: ~2600 MockUSDC/ETH")
        print()
    
    def display_default_amounts(self):
        """Display default liquidity amounts."""
        print("💰 Default Liquidity Amounts")
        print("=" * 30)
        print(f"💵 MockUSDC Amount: {self.DEFAULT_MOCKUSDC_AMOUNT} MockUSDC")
        print(f"🪙 ETH Amount: {self.DEFAULT_ETH_AMOUNT} ETH")
        print(f"💱 Total Value: ~${self.DEFAULT_MOCKUSDC_AMOUNT + (self.DEFAULT_ETH_AMOUNT * 2500):.2f}")
        print()
    
    def run_liquidity_provision(self, wallet_address: str, mockusdc_amount: Optional[float] = None,
                               eth_amount: Optional[float] = None, dry_run: bool = False) -> int:
        """Run the liquidity provision command."""
        
        # Check if provide_liquidity.py exists
        if not self.provide_liquidity_script.exists():
            print(f"❌ Error: provide_liquidity.py not found at {self.provide_liquidity_script}")
            return 1
        
        # Build command
        cmd = self.build_command(wallet_address, mockusdc_amount, eth_amount, dry_run)
        
        # Display what we're doing
        print("🚀 Adding Liquidity to POOL5")
        print("=" * 30)
        print(f"👛 Wallet: {wallet_address}")
        print(f"🏊 Pool: {self.POOL5_ID}")
        
        if mockusdc_amount is not None:
            print(f"💵 MockUSDC Amount: {mockusdc_amount}")
        if eth_amount is not None:
            print(f"🪙 ETH Amount: {eth_amount}")
        
        print(f"🔍 Mode: {'Dry Run' if dry_run else 'Live Transaction'}")
        print(f"📄 Command: {' '.join(cmd)}")
        print()
        
        # Execute command
        try:
            result = subprocess.run(
                cmd,
                cwd=self.script_dir,
                capture_output=False,  # Let output go directly to terminal
                text=True
            )
            
            print(f"\n📈 Liquidity provision completed with exit code: {result.returncode}")
            return result.returncode
            
        except subprocess.CalledProcessError as e:
            print(f"❌ Command failed with exit code {e.returncode}")
            if e.stdout:
                print("STDOUT:", e.stdout)
            if e.stderr:
                print("STDERR:", e.stderr)
            return e.returncode
        
        except FileNotFoundError:
            print("❌ Error: python3 command not found")
            return 1
        
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
            return 1


def main():
    """Main function to handle command line arguments."""
    parser = argparse.ArgumentParser(
        description="Add liquidity to DetoxHook POOL5 (ETH/MockUSDC 0.3%)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                                    # Use default amounts with env wallet
  %(prog)s 0x1234...                         # Use specific wallet with default amounts
  %(prog)s --mockusdc-amount 50 --eth-amount 0.02  # Custom amounts
  %(prog)s --dry-run --verbose               # Dry run with details
  %(prog)s --amount 200                      # 200 MockUSDC worth of liquidity
        """
    )
    
    parser.add_argument(
        'wallet_address',
        nargs='?',
        help='Wallet address to use (default: from environment)'
    )
    
    parser.add_argument(
        '--mockusdc-amount',
        type=float,
        help='Amount of MockUSDC to provide (default: 100)'
    )
    
    parser.add_argument(
        '--eth-amount',
        type=float,
        help='Amount of ETH to provide (default: 0.04)'
    )
    
    parser.add_argument(
        '--amount',
        type=float,
        help='Total amount in MockUSDC to provide (will calculate ETH amount)'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Simulate the transaction without executing it'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output including errors'
    )
    
    parser.add_argument(
        '--info',
        action='store_true',
        help='Show pool information and exit'
    )
    
    args = parser.parse_args()
    
    # Create provider
    provider = Pool5LiquidityProvider(verbose=args.verbose)
    
    # Show pool info if requested
    if args.info:
        provider.display_pool_info()
        provider.display_default_amounts()
        return 0
    
    # Get wallet address
    wallet_address = args.wallet_address
    if not wallet_address:
        wallet_address = provider.get_env_wallet()
        if not wallet_address:
            print("❌ No wallet address provided and none found in environment")
            print("   Use: --help for usage information")
            return 1
    
    # Validate wallet address
    try:
        from web3 import Web3
        if not Web3.is_address(wallet_address):
            print(f"❌ Invalid wallet address: {wallet_address}")
            return 1
    except ImportError:
        # Skip validation if web3 not available
        pass
    
    # Handle amount parameter
    mockusdc_amount = args.mockusdc_amount
    eth_amount = args.eth_amount
    
    if args.amount is not None:
        # Calculate amounts based on total MockUSDC value
        total_mockusdc = args.amount
        # Assume 50/50 split for simplicity (in reality, this would depend on current price)
        mockusdc_amount = total_mockusdc / 2
        eth_amount = (total_mockusdc / 2) / 2500  # Approximate ETH amount at $2500/ETH
        
        if args.verbose:
            print(f"💡 Calculated amounts from total ${args.amount}:")
            print(f"   MockUSDC: {mockusdc_amount:.2f}")
            print(f"   ETH: {eth_amount:.6f}")
    
    # Run liquidity provision
    return provider.run_liquidity_provision(
        wallet_address=wallet_address,
        mockusdc_amount=mockusdc_amount,
        eth_amount=eth_amount,
        dry_run=args.dry_run
    )


if __name__ == '__main__':
    main()