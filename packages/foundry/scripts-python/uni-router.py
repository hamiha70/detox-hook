#!/usr/bin/env python3
"""
Uniswap V4 Script for Arbitrum Sepolia
Performs ETH/USD swaps using Uniswap V4 PoolManager with Pyth price data
Uses real V4 contracts: PoolManager + PoolSwapTest for direct V4 functionality

Requirements:
- web3.py: pip3 install web3
- requests: pip3 install requests
- eth-account: pip3 install eth-account

Environment Variables:
- DEPLOYMENT_KEY: Private key for transaction signing (64 hex chars)
- PRIVATE_KEY: Alternative private key environment variable (fallback)

Usage:
  python3 uni-router.py 0.001 true                    # ETH -> USD
  python3 uni-router.py 5 false                       # USD -> ETH
  python3 uni-router.py 0.01 true --private-key KEY   # With explicit key
"""

import argparse
import json
import sys
from decimal import Decimal
from typing import Tuple, Optional
import os

import requests
from web3 import Web3
from eth_account import Account

# Uniswap V4 Contract addresses for Arbitrum Sepolia (REAL V4 contracts)
POOL_MANAGER_ADDRESS = "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"        # V4 PoolManager
POOL_SWAP_TEST_ADDRESS = "0xf3a39c86dbd13c45365e57fb90fe413371f65af8"      # V4 PoolSwapTest  
WETH_ADDRESS = "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73"              # WETH on Arbitrum Sepolia  
USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"               # USDC on Arbitrum Sepolia

# Pyth configuration
PYTH_HERMES_API = "https://hermes.pyth.network"
ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"

# RPC configuration
ARBITRUM_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc"

class UniswapV4Router:
    def __init__(self, rpc_url: str = ARBITRUM_SEPOLIA_RPC):
        """Initialize the Uniswap V4 Router using PoolSwapTest contract"""
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        if not self.w3.is_connected():
            raise ConnectionError(f"Failed to connect to RPC: {rpc_url}")
        
        print(f"✅ Connected to Arbitrum Sepolia")
        print(f"   Chain ID: {self.w3.eth.chain_id}")
        print(f"   Block: {self.w3.eth.block_number}")
        
        # V4 PoolSwapTest ABI for swap function
        self.swap_test_abi = [
            {
                "inputs": [
                    {
                        "components": [
                            {"internalType": "Currency", "name": "currency0", "type": "address"},
                            {"internalType": "Currency", "name": "currency1", "type": "address"},
                            {"internalType": "uint24", "name": "fee", "type": "uint24"},
                            {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                            {"internalType": "contract IHooks", "name": "hooks", "type": "address"}
                        ],
                        "internalType": "struct PoolKey",
                        "name": "key",
                        "type": "tuple"
                    },
                    {
                        "components": [
                            {"internalType": "bool", "name": "zeroForOne", "type": "bool"},
                            {"internalType": "int256", "name": "amountSpecified", "type": "int256"},
                            {"internalType": "uint160", "name": "sqrtPriceLimitX96", "type": "uint160"}
                        ],
                        "internalType": "struct IPoolManager.SwapParams",
                        "name": "params",
                        "type": "tuple"
                    },
                    {"internalType": "bytes", "name": "hookData", "type": "bytes"}
                ],
                "name": "swap",
                "outputs": [],
                "stateMutability": "payable",
                "type": "function"
            }
        ]
        
        # Convert to proper checksum address
        swap_test_checksum = self.w3.to_checksum_address(POOL_SWAP_TEST_ADDRESS)
        print(f"   V4 PoolSwapTest: {swap_test_checksum}")
        
        self.swap_contract = self.w3.eth.contract(
            address=swap_test_checksum,
            abi=self.swap_test_abi
        )

    def fetch_pyth_price(self) -> Tuple[float, str]:
        """
        Fetch current ETH/USD price and update data from Pyth Hermes API
        Returns: (price, update_data_hex)
        """
        try:
            url = f"{PYTH_HERMES_API}/v2/updates/price/latest"
            params = {
                'ids[]': ETH_USD_PRICE_ID,
                'encoding': 'hex'
            }
            
            print(f"🔍 Fetching ETH/USD price from Pyth Hermes...")
            response = requests.get(url, params=params, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            
            if not data.get('binary') or not data.get('parsed'):
                raise ValueError("Invalid response format from Hermes API")
            
            # Extract price from parsed data
            parsed_data = data['parsed'][0]
            price_obj = parsed_data['price']
            
            # Calculate actual price: price * 10^expo
            price_raw = int(price_obj['price'])
            expo = int(price_obj['expo'])
            confidence = int(price_obj['conf'])
            
            actual_price = price_raw * (10 ** expo)
            
            # Get update data
            update_data = data['binary']['data'][0]
            
            print(f"📊 Current ETH/USD Price: ${actual_price:.2f}")
            print(f"   Confidence: ±${confidence * (10 ** expo):.2f}")
            print(f"   Publish Time: {parsed_data['price']['publish_time']}")
            print(f"   Update Data Length: {len(update_data)} chars")
            
            return actual_price, update_data
            
        except requests.RequestException as e:
            raise ConnectionError(f"Failed to fetch Pyth price: {e}")
        except (KeyError, ValueError, TypeError) as e:
            raise ValueError(f"Failed to parse Pyth response: {e}")

    def build_pool_key(self, eth_to_usd: bool) -> tuple:
        """Build Uniswap V4 PoolKey structure"""
        if eth_to_usd:
            # ETH -> USDC (WETH -> USDC)
            currency0 = self.w3.to_checksum_address(WETH_ADDRESS)
            currency1 = self.w3.to_checksum_address(USDC_ADDRESS)
        else:
            # USDC -> ETH (USDC -> WETH)  
            currency0 = self.w3.to_checksum_address(USDC_ADDRESS)
            currency1 = self.w3.to_checksum_address(WETH_ADDRESS)
        
        # Ensure currency0 < currency1 (Uniswap V4 requirement)
        if currency0.lower() > currency1.lower():
            currency0, currency1 = currency1, currency0
        
        return (
            currency0,                                                      # currency0
            currency1,                                                      # currency1
            3000,                                                          # fee (0.3%)
            60,                                                            # tickSpacing
            "0x0000000000000000000000000000000000000000"                   # hooks (none)
        )

    def build_swap_params(self, amount_wei: int, eth_to_usd: bool) -> tuple:
        """Build Uniswap V4 SwapParams structure"""
        # For V4: negative amount = exactInput, positive = exactOutput
        amount_specified = -amount_wei  # exactInput (negative)
        
        # Determine swap direction based on pool's currency ordering
        weth_checksum = self.w3.to_checksum_address(WETH_ADDRESS)
        usdc_checksum = self.w3.to_checksum_address(USDC_ADDRESS)
        
        if weth_checksum.lower() < usdc_checksum.lower():
            # WETH is currency0, USDC is currency1
            zero_for_one = eth_to_usd  # ETH->USDC = currency0->currency1 = zeroForOne=true
        else:
            # USDC is currency0, WETH is currency1  
            zero_for_one = not eth_to_usd  # ETH->USDC = currency1->currency0 = zeroForOne=false
        
        return (
            zero_for_one,                                                  # zeroForOne
            amount_specified,                                              # amountSpecified (negative for exactInput)
            0                                                              # sqrtPriceLimitX96 (0 = no limit)
        )

    def execute_swap(self, amount: str, direction: bool, private_key: str) -> str:
        """
        Execute the V4 swap transaction
        
        Args:
            amount: Amount to swap (in ETH for ETH->USD, in USD for USD->ETH)
            direction: True for ETH->USD, False for USD->ETH
            private_key: Private key for signing transaction
            
        Returns:
            Transaction hash
        """
        try:
            # Setup account
            account = Account.from_key(private_key)
            sender = account.address
            
            print(f"💰 Sender: {sender}")
            balance = self.w3.eth.get_balance(sender)
            print(f"   Balance: {self.w3.from_wei(balance, 'ether'):.6f} ETH")
            
            # Fetch Pyth price and update data
            price, update_data = self.fetch_pyth_price()
            
            # Convert amount to appropriate units
            if direction:  # ETH -> USD
                amount_wei = self.w3.to_wei(Decimal(amount), 'ether')
                print(f"🔄 Swapping {amount} ETH → USDC")
                print(f"   Amount in wei: {amount_wei}")
                
                # Check balance
                if balance < amount_wei:
                    raise ValueError(f"Insufficient ETH balance: {self.w3.from_wei(balance, 'ether'):.6f} < {amount}")
                    
            else:  # USD -> ETH
                amount_wei = int(Decimal(amount) * 10**6)  # USDC has 6 decimals
                print(f"🔄 Swapping {amount} USDC → ETH")
                print(f"   Amount in USDC units: {amount_wei}")
            
            # Build V4 PoolKey and SwapParams
            pool_key = self.build_pool_key(direction)
            swap_params = self.build_swap_params(amount_wei, direction)
            
            print(f"🏗️  Building V4 swap...")
            print(f"   Pool Key: currency0={pool_key[0]}, currency1={pool_key[1]}, fee={pool_key[2]}")
            print(f"   Swap Params: zeroForOne={swap_params[0]}, amount={swap_params[1]}")
            
            # Build V4 swap transaction using PoolSwapTest
            print(f"🔧 Building V4 swap transaction...")
            
            # Use Pyth price data as hook data
            hook_data = bytes.fromhex(update_data[2:] if update_data.startswith('0x') else update_data)
            
            tx_data = self.swap_contract.functions.swap(
                pool_key,
                swap_params,
                hook_data
            )
            
            # Estimate gas
            try:
                print(f"⛽ Estimating gas...")
                gas_estimate = tx_data.estimate_gas({
                    'from': sender,
                    'value': amount_wei if direction else 0
                })
                print(f"✅ Estimated gas: {gas_estimate:,}")
            except Exception as e:
                print(f"❌ Gas estimation failed: {e}")
                print(f"   This likely means V4 pool doesn't exist or command structure is wrong")
                
                # Let's try a simple contract call to see if it exists
                swap_test_checksum = self.w3.to_checksum_address(POOL_SWAP_TEST_ADDRESS)
                code = self.w3.eth.get_code(swap_test_checksum)
                if code == '0x':
                    raise Exception(f"V4 PoolSwapTest not deployed at {swap_test_checksum}")
                else:
                    print(f"   Contract exists ({len(code)} bytes)")
                    print(f"   Error code: {e}")
                    raise Exception(f"Gas estimation failed - likely V4 pool doesn't exist or wrong params: {e}")
            
            # Get current gas price
            gas_price = self.w3.eth.gas_price
            print(f"⛽ Gas price: {self.w3.from_wei(gas_price, 'gwei'):.2f} gwei")
            
            # Calculate total ETH needed
            gas_cost = gas_estimate * gas_price
            if direction:  # ETH -> USD
                total_eth_needed = amount_wei + gas_cost
                if balance < total_eth_needed:
                    raise ValueError(f"Insufficient ETH for swap + gas: need {self.w3.from_wei(total_eth_needed, 'ether'):.6f}, have {self.w3.from_wei(balance, 'ether'):.6f}")
            else:
                if balance < gas_cost:
                    raise ValueError(f"Insufficient ETH for gas: need {self.w3.from_wei(gas_cost, 'ether'):.6f}, have {self.w3.from_wei(balance, 'ether'):.6f}")
            
            # Build transaction
            tx = tx_data.build_transaction({
                'from': sender,
                'gas': gas_estimate,
                'gasPrice': gas_price,
                'nonce': self.w3.eth.get_transaction_count(sender),
                'value': amount_wei if direction else 0
            })
            
            print(f"📋 Transaction built:")
            print(f"   Gas: {tx['gas']:,}")
            print(f"   Value: {tx['value']} wei ({self.w3.from_wei(tx['value'], 'ether'):.6f} ETH)")
            print(f"   Nonce: {tx['nonce']}")
            
            # Sign and send transaction
            signed_tx = account.sign_transaction(tx)
            
            print(f"📤 Sending transaction...")
            tx_hash = self.w3.eth.send_raw_transaction(signed_tx.rawTransaction)
            tx_hash_hex = tx_hash.hex()
            
            print(f"✅ Transaction sent!")
            print(f"   Hash: {tx_hash_hex}")
            print(f"   Explorer: https://sepolia.arbiscan.io/tx/{tx_hash_hex}")
            
            return tx_hash_hex
            
        except Exception as e:
            print(f"❌ Swap execution failed: {e}")
            import traceback
            traceback.print_exc()
            raise

def main():
    """Main function to handle CLI arguments and execute swap"""
    parser = argparse.ArgumentParser(description='Uniswap V4 ETH/USD Swap on Arbitrum Sepolia')
    parser.add_argument('amount', type=str, help='Amount to swap (ETH for ETH->USD, USD for USD->ETH)')
    parser.add_argument('direction', type=str, choices=['true', 'false'], 
                       help='Swap direction: true for ETH->USD, false for USD->ETH')
    parser.add_argument('--private-key', type=str, 
                       help='Private key (or set DEPLOYMENT_KEY/PRIVATE_KEY env vars)')
    parser.add_argument('--rpc-url', type=str, default=ARBITRUM_SEPOLIA_RPC,
                       help='RPC URL for Arbitrum Sepolia')
    parser.add_argument('--debug', action='store_true',
                       help='Enable debug output')
    
    args = parser.parse_args()
    
    # Convert direction string to boolean
    direction = args.direction.lower() == 'true'
    direction_str = "ETH → USD" if direction else "USD → ETH"
    
    print("=" * 60)
    print("🦄 Uniswap V4 ETH/USD Swap")
    print("=" * 60)
    print(f"Amount: {args.amount}")
    print(f"Direction: {direction_str}")
    print(f"Network: Arbitrum Sepolia")
    print(f"V4 PoolSwapTest: {POOL_SWAP_TEST_ADDRESS}")
    print(f"Debug: {args.debug}")
    print("=" * 60)
    
    try:
        # Initialize V4 swap client
        swap_client = UniswapV4Router(args.rpc_url)
        
        # Get private key - prioritize DEPLOYMENT_KEY
        private_key = args.private_key
        if not private_key:
            deployment_key = os.getenv('DEPLOYMENT_KEY')
            private_key_env = os.getenv('PRIVATE_KEY')
            
            # Validate DEPLOYMENT_KEY format
            if deployment_key:
                clean_key = deployment_key.replace('0x', '').lower()
                if len(clean_key) == 64 and all(c in '0123456789abcdef' for c in clean_key):
                    private_key = deployment_key
                else:
                    print(f"⚠️  DEPLOYMENT_KEY invalid format, falling back to PRIVATE_KEY")
            
            if not private_key:
                private_key = private_key_env
        
        if not private_key:
            print("❌ Private key required for transaction signing")
            print("📝 Use one of these methods:")
            print("   1. --private-key YOUR_PRIVATE_KEY")
            print("   2. export DEPLOYMENT_KEY='0x1234...5678'  (64 hex chars)")
            print("   3. export PRIVATE_KEY='0x1234...5678'")
            sys.exit(1)
        
        # Validate private key format
        clean_key = private_key.replace('0x', '').lower()
        if len(clean_key) != 64 or not all(c in '0123456789abcdef' for c in clean_key):
            print("❌ Invalid private key format")
            print("   Private key must be exactly 64 hex characters (32 bytes)")
            print(f"   Received: {len(clean_key)} characters")
            sys.exit(1)
        
        # Execute swap
        tx_hash = swap_client.execute_swap(args.amount, direction, private_key)
        
        print("\n✅ V4 Swap completed successfully!")
        print(f"Transaction: {tx_hash}")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        if args.debug:
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main() 