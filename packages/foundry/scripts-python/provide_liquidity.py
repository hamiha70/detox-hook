#!/usr/bin/env python3
"""
Liquidity Provider for DetoxHook Uniswap V4 Pools
===============================================

This script allows a wallet to provide liquidity to Uniswap V4 pools on Arbitrum Sepolia.
It integrates with the DetoxHook ecosystem and handles all necessary token approvals and calculations.

Usage:
    python provide_liquidity.py <wallet_address> <pool_id> [options]
    python provide_liquidity.py --env-wallet <pool_id> [options]
    python provide_liquidity.py --list-pools
    
Examples:
    python provide_liquidity.py 0x1234... 0x5e6967b5... --usdc-amount 100
    python provide_liquidity.py --env-wallet 0x5e6967b5... --eth-amount 0.1 --dry-run
    python provide_liquidity.py --list-pools --verbose
"""

import os
import sys
import argparse
import json
from typing import List, Dict, Optional, Any, Tuple
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
    print("   or: pip3 install web3")
    sys.exit(1)

# Import our environment loader
try:
    from load_env import EnvLoader
except ImportError:
    print("⚠️  Environment loader not found. Some features may be limited.")
    EnvLoader = None


class LiquidityProvider:
    """Provides liquidity to Uniswap V4 pools on Arbitrum Sepolia."""
    
    # Contract addresses on Arbitrum Sepolia
    POOL_MANAGER_ADDRESS = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"
    POOL_MODIFY_LIQUIDITY_TEST_ADDRESS = "0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7"
    USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"
    
    # Pool configurations file
    POOLS_CONFIG_PATH = "../deployments/detox-hook-pools.json"
    
    # ABI for contracts (minimal required functions)
    POOL_MODIFY_LIQUIDITY_TEST_ABI = [
        {
            "type": "function",
            "name": "modifyLiquidity",
            "inputs": [
                {
                    "name": "key",
                    "type": "tuple",
                    "components": [
                        {"name": "currency0", "type": "address"},
                        {"name": "currency1", "type": "address"},
                        {"name": "fee", "type": "uint24"},
                        {"name": "tickSpacing", "type": "int24"},
                        {"name": "hooks", "type": "address"}
                    ]
                },
                {
                    "name": "params",
                    "type": "tuple",
                    "components": [
                        {"name": "tickLower", "type": "int24"},
                        {"name": "tickUpper", "type": "int24"},
                        {"name": "liquidityDelta", "type": "int256"},
                        {"name": "salt", "type": "bytes32"}
                    ]
                },
                {"name": "hookData", "type": "bytes"}
            ],
            "outputs": [
                {"name": "delta", "type": "int256"}
            ],
            "stateMutability": "payable"
        }
    ]
    
    ERC20_ABI = [
        {
            "type": "function", "name": "approve", "inputs": [{"name": "spender", "type": "address"}, {"name": "amount", "type": "uint256"}],
            "outputs": [{"name": "", "type": "bool"}], "stateMutability": "nonpayable"
        },
        {
            "type": "function", "name": "balanceOf", "inputs": [{"name": "account", "type": "address"}],
            "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view"
        },
        {
            "type": "function", "name": "allowance", "inputs": [{"name": "owner", "type": "address"}, {"name": "spender", "type": "address"}],
            "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view"
        },
        {
            "type": "function", "name": "decimals", "inputs": [],
            "outputs": [{"name": "", "type": "uint8"}], "stateMutability": "view"
        },
        {
            "type": "function", "name": "symbol", "inputs": [],
            "outputs": [{"name": "", "type": "string"}], "stateMutability": "view"
        },
    ]
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False, dry_run: bool = False):
        self.verbose = verbose
        self.dry_run = dry_run
        self.rpc_url = rpc_url or self._get_rpc_url()
        self.w3 = None
        self.pools_config = None
        
        if self.rpc_url:
            self._connect()
        
        self._load_pools_config()
    
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
    
    def _load_pools_config(self):
        """Load pool configurations from the deployment file."""
        try:
            config_path = Path(__file__).parent / self.POOLS_CONFIG_PATH
            
            if not config_path.exists():
                if self.verbose:
                    print(f"⚠️  Pool config not found at {config_path}")
                return
            
            with open(config_path, 'r') as f:
                self.pools_config = json.load(f)
                
            if self.verbose:
                pools_count = len(self.pools_config.get('pools', {}))
                print(f"📋 Loaded {pools_count} pool configurations")
                
        except Exception as e:
            if self.verbose:
                print(f"⚠️  Could not load pools config: {e}")
    
    def list_pools(self) -> List[Dict[str, Any]]:
        """List all available pools."""
        if not self.pools_config:
            return []
        
        pools = []
        for pool_name, pool_data in self.pools_config.get('pools', {}).items():
            pools.append({
                "name": pool_name,
                "pool_id": pool_data.get('poolId'),
                "description": pool_data.get('description'),
                "fee": pool_data.get('poolKey', {}).get('fee'),
                "status": pool_data.get('status'),
                "currency0": pool_data.get('poolKey', {}).get('currency0'),
                "currency1": pool_data.get('poolKey', {}).get('currency1'),
            })
        
        return pools
    
    def get_pool_config(self, pool_id: str) -> Optional[Dict[str, Any]]:
        """Get configuration for a specific pool ID."""
        if not self.pools_config:
            return None
        
        for pool_data in self.pools_config.get('pools', {}).values():
            if pool_data.get('poolId') == pool_id:
                return pool_data
        
        return None
    
    def get_wallet_balances(self, wallet_address: str) -> Dict[str, Any]:
        """Get ETH and USDC balances for a wallet."""
        if not self.w3:
            return {"error": "Not connected to blockchain"}
        
        try:
            checksum_address = Web3.to_checksum_address(wallet_address)
            
            # Get ETH balance
            eth_balance_wei = self.w3.eth.get_balance(checksum_address)
            eth_balance = self.w3.from_wei(eth_balance_wei, 'ether')
            
            # Get USDC balance
            usdc_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.USDC_ADDRESS),
                abi=self.ERC20_ABI
            )
            
            usdc_balance_raw = usdc_contract.functions.balanceOf(checksum_address).call()
            usdc_decimals = usdc_contract.functions.decimals().call()
            usdc_balance = usdc_balance_raw / (10 ** usdc_decimals)
            
            return {
                "address": checksum_address,
                "eth_balance": float(eth_balance),
                "eth_balance_wei": eth_balance_wei,
                "usdc_balance": usdc_balance,
                "usdc_balance_raw": usdc_balance_raw,
                "usdc_decimals": usdc_decimals,
                "success": True
            }
            
        except Exception as e:
            return {
                "address": wallet_address,
                "error": f"Failed to get balances: {str(e)}",
                "success": False
            }
    
    def calculate_liquidity_amounts(self, pool_config: Dict[str, Any], 
                                  eth_amount: Optional[float] = None, 
                                  usdc_amount: Optional[float] = None) -> Tuple[int, int]:
        """Calculate ETH and USDC amounts for liquidity provision."""
        
        # Get price from pool config
        initial_price = pool_config.get('initialPrice', {})
        price_usdc = initial_price.get('priceUSDC', 2500)  # Default to 2500 USDC/ETH
        
        if eth_amount is not None:
            # Calculate USDC amount from ETH
            usdc_amount_calc = eth_amount * price_usdc
            eth_wei = int(eth_amount * 1e18)
            usdc_raw = int(usdc_amount_calc * 1e6)  # USDC has 6 decimals
            
        elif usdc_amount is not None:
            # Calculate ETH amount from USDC
            eth_amount_calc = usdc_amount / price_usdc
            eth_wei = int(eth_amount_calc * 1e18)
            usdc_raw = int(usdc_amount * 1e6)  # USDC has 6 decimals
            
        else:
            # Default to 1 USDC worth of liquidity (like the deployment scripts)
            usdc_amount = 1.0
            eth_amount_calc = usdc_amount / price_usdc
            eth_wei = int(eth_amount_calc * 1e18)
            usdc_raw = int(usdc_amount * 1e6)
        
        return eth_wei, usdc_raw
    
    def check_allowances(self, wallet_address: str) -> Dict[str, Any]:
        """Check if wallet has approved tokens for the liquidity contract."""
        if not self.w3:
            return {"error": "Not connected to blockchain"}
        
        try:
            checksum_address = Web3.to_checksum_address(wallet_address)
            spender = Web3.to_checksum_address(self.POOL_MODIFY_LIQUIDITY_TEST_ADDRESS)
            
            # Check USDC allowance
            usdc_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.USDC_ADDRESS),
                abi=self.ERC20_ABI
            )
            
            usdc_allowance = usdc_contract.functions.allowance(checksum_address, spender).call()
            usdc_decimals = usdc_contract.functions.decimals().call()
            
            return {
                "wallet": checksum_address,
                "spender": spender,
                "usdc_allowance": usdc_allowance,
                "usdc_allowance_formatted": usdc_allowance / (10 ** usdc_decimals),
                "usdc_approved": usdc_allowance > 0,
                "success": True
            }
            
        except Exception as e:
            return {
                "wallet": wallet_address,
                "error": f"Failed to check allowances: {str(e)}",
                "success": False
            }
    
    def provide_liquidity(self, wallet_address: str, pool_id: str, 
                         eth_amount: Optional[float] = None,
                         usdc_amount: Optional[float] = None,
                         private_key: Optional[str] = None,
                         tick_lower: int = -600,
                         tick_upper: int = 600) -> Dict[str, Any]:
        """Provide liquidity to a Uniswap V4 pool."""
        
        if not self.w3:
            return {"error": "Not connected to blockchain", "success": False}
        
        if self.dry_run:
            return self._simulate_liquidity_provision(wallet_address, pool_id, eth_amount, usdc_amount, tick_lower, tick_upper)
        
        # Get pool configuration
        pool_config = self.get_pool_config(pool_id)
        if not pool_config:
            return {"error": f"Pool {pool_id} not found in configuration", "success": False}
        
        try:
            checksum_address = Web3.to_checksum_address(wallet_address)
            
            # Calculate amounts
            eth_wei, usdc_raw = self.calculate_liquidity_amounts(pool_config, eth_amount, usdc_amount)
            
            # Check balances
            balances = self.get_wallet_balances(wallet_address)
            if not balances.get('success', False):
                return {"error": f"Could not get wallet balances: {balances.get('error')}", "success": False}
            
            # Validate sufficient balances
            if balances['eth_balance_wei'] < eth_wei:
                return {
                    "error": f"Insufficient ETH balance. Need {eth_wei / 1e18:.6f} ETH, have {balances['eth_balance']:.6f} ETH",
                    "success": False
                }
            
            if balances['usdc_balance_raw'] < usdc_raw:
                return {
                    "error": f"Insufficient USDC balance. Need {usdc_raw / 1e6:.6f} USDC, have {balances['usdc_balance']:.6f} USDC",
                    "success": False
                }
            
            # Get private key for signing
            if not private_key:
                private_key = os.getenv('PRIVATE_KEY') or os.getenv('DEPLOYMENT_KEY')
                
            if not private_key:
                return {"error": "Private key not provided and not found in environment", "success": False}
            
            # Build pool key from config
            pool_key = pool_config['poolKey']
            
            # Create contracts
            liquidity_contract = self.w3.eth.contract(
                address=Web3.to_checksum_address(self.POOL_MODIFY_LIQUIDITY_TEST_ADDRESS),
                abi=self.POOL_MODIFY_LIQUIDITY_TEST_ABI
            )
            
            # Check if USDC needs approval
            allowances = self.check_allowances(wallet_address)
            if allowances.get('success') and not allowances.get('usdc_approved'):
                if self.verbose:
                    print("🔐 USDC approval required but not handled in this script")
                    print("   Please approve USDC manually first")
                
                return {
                    "error": "USDC approval required. Please approve USDC for the liquidity contract first.",
                    "approval_needed": True,
                    "spender": self.POOL_MODIFY_LIQUIDITY_TEST_ADDRESS,
                    "success": False
                }
            
            # Prepare transaction
            pool_key_tuple = (
                pool_key['currency0'],
                pool_key['currency1'], 
                pool_key['fee'],
                pool_key['tickSpacing'],
                pool_key['hooks']
            )
            
            modify_params = (
                tick_lower,
                tick_upper,
                usdc_raw,  # Use USDC amount as liquidity delta (like in deployment scripts)
                b'\x00' * 32  # salt as bytes32
            )
            
            hook_data = b''  # Empty hook data
            
            # Get current gas price and add buffer for dynamic pricing
            try:
                # Try to get EIP-1559 style pricing first
                latest_block = self.w3.eth.get_block('latest')
                base_fee = latest_block.get('baseFeePerGas', 0)
                max_priority_fee = min(self.w3.eth.max_priority_fee, 2000000000)  # Cap at 2 gwei
                max_fee_per_gas = (base_fee * 2) + max_priority_fee  # 2x base fee + priority
                
                tx_params = {
                    'from': checksum_address,
                    'value': eth_wei,
                    'gas': 500000,  # Conservative gas limit
                    'maxFeePerGas': max_fee_per_gas,
                    'maxPriorityFeePerGas': max_priority_fee,
                    'nonce': self.w3.eth.get_transaction_count(checksum_address),
                    'chainId': self.w3.eth.chain_id,
                    'type': 2  # EIP-1559 transaction
                }
            except:
                # Fallback to legacy pricing with buffer
                gas_price = self.w3.eth.gas_price
                buffered_gas_price = int(gas_price * 1.2)  # 20% buffer
                
                tx_params = {
                    'from': checksum_address,
                    'value': eth_wei,
                    'gas': 500000,  # Conservative gas limit  
                    'gasPrice': buffered_gas_price,
                    'nonce': self.w3.eth.get_transaction_count(checksum_address),
                    'chainId': self.w3.eth.chain_id
                }

            # Build transaction
            transaction = liquidity_contract.functions.modifyLiquidity(
                pool_key_tuple,
                modify_params,
                hook_data
            ).build_transaction(tx_params)
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, private_key)
            # Handle both old and new web3.py versions
            raw_transaction = getattr(signed_txn, 'rawTransaction', getattr(signed_txn, 'raw_transaction', None))
            if raw_transaction is None:
                raise AttributeError("Could not find raw transaction data in signed transaction")
            tx_hash = self.w3.eth.send_raw_transaction(raw_transaction)
            
            if self.verbose:
                print(f"📤 Transaction sent: {tx_hash.hex()}")
                print("⏳ Waiting for confirmation...")
            
            # Wait for confirmation
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            success = receipt.status == 1
            
            return {
                "success": success,
                "transaction_hash": tx_hash.hex(),
                "block_number": receipt.blockNumber,
                "gas_used": receipt.gasUsed,
                "eth_amount": eth_wei / 1e18,
                "usdc_amount": usdc_raw / 1e6,
                "pool_id": pool_id,
                "tick_range": f"{tick_lower} to {tick_upper}",
                "receipt": receipt
            }
            
        except Exception as e:
            return {
                "error": f"Liquidity provision failed: {str(e)}",
                "success": False
            }
    
    def _simulate_liquidity_provision(self, wallet_address: str, pool_id: str,
                                    eth_amount: Optional[float], usdc_amount: Optional[float],
                                    tick_lower: int, tick_upper: int) -> Dict[str, Any]:
        """Simulate liquidity provision without sending transaction."""
        
        pool_config = self.get_pool_config(pool_id)
        if not pool_config:
            return {"error": f"Pool {pool_id} not found in configuration", "success": False}
        
        try:
            # Calculate amounts
            eth_wei, usdc_raw = self.calculate_liquidity_amounts(pool_config, eth_amount, usdc_amount)
            
            # Get balances
            balances = self.get_wallet_balances(wallet_address)
            
            # Check allowances
            allowances = self.check_allowances(wallet_address)
            
            return {
                "success": True,
                "simulation": True,
                "pool_id": pool_id,
                "pool_description": pool_config.get('description'),
                "wallet": wallet_address,
                "eth_amount": eth_wei / 1e18,
                "usdc_amount": usdc_raw / 1e6,
                "tick_range": f"{tick_lower} to {tick_upper}",
                "current_balances": balances,
                "allowances": allowances,
                "sufficient_eth": balances.get('eth_balance_wei', 0) >= eth_wei,
                "sufficient_usdc": balances.get('usdc_balance_raw', 0) >= usdc_raw,
                "usdc_approved": allowances.get('usdc_approved', False)
            }
            
        except Exception as e:
            return {
                "error": f"Simulation failed: {str(e)}",
                "success": False
            }
    
    def display_results(self, result: Dict[str, Any]):
        """Display liquidity provision results."""
        print("\n💧 Liquidity Provision Report")
        print("=" * 50)
        
        if not result.get('success', False):
            error = result.get('error', 'Unknown error')
            print(f"❌ Failed: {error}")
            
            if result.get('approval_needed'):
                print(f"\n🔐 Manual Approval Required:")
                print(f"   Contract: {result.get('spender')}")
                print(f"   Token: USDC ({self.USDC_ADDRESS})")
                print(f"   Command: approve({result.get('spender')}, MAX_UINT256)")
            
            return
        
        if result.get('simulation'):
            print("🎯 SIMULATION MODE - No transaction sent")
            print()
        
        # Basic info
        pool_id = result.get('pool_id', 'Unknown')
        print(f"🏊 Pool: {pool_id[:16]}...")
        
        if result.get('pool_description'):
            print(f"📄 Description: {result['pool_description']}")
        
        wallet = result.get('wallet', 'Unknown')
        print(f"👤 Wallet: {wallet}")
        
        # Amounts
        eth_amount = result.get('eth_amount', 0)
        usdc_amount = result.get('usdc_amount', 0)
        print(f"💎 ETH Amount: {eth_amount:.6f} ETH")
        print(f"💵 USDC Amount: {usdc_amount:.6f} USDC")
        
        tick_range = result.get('tick_range', 'Unknown')
        print(f"📏 Tick Range: {tick_range}")
        
        if result.get('simulation'):
            # Simulation-specific info
            balances = result.get('current_balances', {})
            allowances = result.get('allowances', {})
            
            print(f"\n💰 Current Balances:")
            print(f"   ETH: {balances.get('eth_balance', 0):.6f} ETH")
            print(f"   USDC: {balances.get('usdc_balance', 0):.6f} USDC")
            
            print(f"\n✅ Validation:")
            print(f"   Sufficient ETH: {'✅' if result.get('sufficient_eth') else '❌'}")
            print(f"   Sufficient USDC: {'✅' if result.get('sufficient_usdc') else '❌'}")
            print(f"   USDC Approved: {'✅' if result.get('usdc_approved') else '❌'}")
            
        else:
            # Real transaction info
            tx_hash = result.get('transaction_hash', 'Unknown')
            block_number = result.get('block_number', 'Unknown')
            gas_used = result.get('gas_used', 'Unknown')
            
            print(f"\n📤 Transaction:")
            print(f"   Hash: {tx_hash}")
            print(f"   Block: {block_number:,}")
            print(f"   Gas Used: {gas_used:,}")
            
            # Block explorer link
            explorer_url = f"https://arbitrum-sepolia.blockscout.com/tx/{tx_hash}"
            print(f"   🔗 Explorer: {explorer_url}")
        
        print()


def get_env_wallet() -> Optional[str]:
    """Get wallet address from environment variables."""
    
    # Load environment if needed
    if EnvLoader and not os.getenv('ARBITRUM_SEPOLIA_RPC_URL'):
        try:
            loader = EnvLoader(verbose=False, dry_run=False)
            loader.load_environment()
        except Exception:
            pass
    
    # Check various wallet environment variables
    wallet_vars = [
        'DEPLOYMENT_WALLET',
        'SWAPPER_WALLET', 
        'LIQUIDITY_PROVIDER_WALLET',
        'WALLET_ADDRESS'
    ]
    
    for var in wallet_vars:
        address = os.getenv(var)
        if address and Web3.is_address(address):
            return address
    
    return None


def main():
    """Main function to handle command line arguments and execute liquidity provision."""
    parser = argparse.ArgumentParser(
        description="Provide liquidity to Uniswap V4 pools on Arbitrum Sepolia",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 0x1234... 0x5e6967b5... --usdc-amount 100
  %(prog)s --env-wallet 0x5e6967b5... --eth-amount 0.1 --dry-run
  %(prog)s --list-pools --verbose
        """
    )
    
    parser.add_argument(
        'wallet',
        nargs='?',
        help='Wallet address to provide liquidity from'
    )
    
    parser.add_argument(
        'pool_id',
        nargs='?',
        help='Pool ID to provide liquidity to'
    )
    
    parser.add_argument(
        '--env-wallet',
        action='store_true',
        help='Use wallet address from environment variables'
    )
    
    parser.add_argument(
        '--list-pools',
        action='store_true',
        help='List all available pools and exit'
    )
    
    parser.add_argument(
        '--eth-amount',
        type=float,
        help='Amount of ETH to provide (will calculate USDC automatically)'
    )
    
    parser.add_argument(
        '--usdc-amount',
        type=float,
        help='Amount of USDC to provide (will calculate ETH automatically)'
    )
    
    parser.add_argument(
        '--tick-lower',
        type=int,
        default=-600,
        help='Lower tick for liquidity range (default: -600)'
    )
    
    parser.add_argument(
        '--tick-upper',
        type=int,
        default=600,
        help='Upper tick for liquidity range (default: 600)'
    )
    
    parser.add_argument(
        '--private-key',
        help='Private key for signing (or set PRIVATE_KEY/DEPLOYMENT_KEY env var)'
    )
    
    parser.add_argument(
        '--rpc-url',
        help='Custom RPC URL (default: from .env or Arbitrum Sepolia)'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Simulate the transaction without sending it'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output'
    )
    
    args = parser.parse_args()
    
    # Create liquidity provider
    provider = LiquidityProvider(rpc_url=args.rpc_url, verbose=args.verbose, dry_run=args.dry_run)
    
    if not provider.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    # Handle list pools
    if args.list_pools:
        pools = provider.list_pools()
        
        if not pools:
            print("❌ No pools found in configuration")
            return 1
        
        print(f"\n📋 Available Pools ({len(pools)})")
        print("=" * 60)
        
        for pool in pools:
            print(f"🏊 {pool['name']}: {pool['description']}")
            print(f"   ID: {pool['pool_id']}")
            print(f"   Fee: {pool['fee'] / 10000:.2f}%")  # Fee is in basis points (10000 = 100%)
            print(f"   Status: {pool['status']}")
            print()
        
        return 0
    
    # Get wallet address and pool ID
    wallet_address = None
    pool_id = None
    
    if args.env_wallet:
        wallet_address = get_env_wallet()
        if not wallet_address:
            print("❌ No wallet address found in environment variables")
            return 1
        
        if args.verbose:
            print(f"📂 Using wallet from environment: {wallet_address}")
        
        # When using --env-wallet, the first positional arg is the pool_id
        pool_id = args.wallet if args.wallet else args.pool_id
    
    else:
        # Normal case: wallet and pool_id are positional arguments
        if not args.wallet:
            print("❌ Wallet address required. Use --wallet <address> or --env-wallet")
            return 1
        
        wallet_address = args.wallet
        pool_id = args.pool_id
    
    # Validate wallet address
    if not Web3.is_address(wallet_address):
        print(f"❌ Invalid wallet address: {wallet_address}")
        return 1
    
    # Get pool ID
    if not pool_id:
        print("❌ Pool ID required. Use --list-pools to see available pools")
        return 1
    
    # Validate amounts
    if args.eth_amount and args.usdc_amount:
        print("❌ Specify either --eth-amount OR --usdc-amount, not both")
        return 1
    
    # Provide liquidity
    result = provider.provide_liquidity(
        wallet_address=wallet_address,
        pool_id=pool_id,
        eth_amount=args.eth_amount,
        usdc_amount=args.usdc_amount,
        private_key=args.private_key,
        tick_lower=args.tick_lower,
        tick_upper=args.tick_upper
    )
    
    # Display results
    provider.display_results(result)
    
    return 0 if result.get('success', False) else 1


if __name__ == '__main__':
    sys.exit(main()) 