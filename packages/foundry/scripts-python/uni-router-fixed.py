#!/usr/bin/env python3
"""
Universal Router Script for Arbitrum Sepolia - FIXED VERSION
Performs ETH/USD swaps using Universal Router with Pyth price data

Environment Variables:
- DEPLOYMENT_KEY: Private key for transaction signing (recommended, matches project standard)
- PRIVATE_KEY: Alternative private key environment variable (fallback)

Usage:
  python3 uni-router-fixed.py 0.001 true                    # ETH -> USDC
  python3 uni-router-fixed.py 5 false                       # USDC -> ETH
  python3 uni-router-fixed.py 0.01 true --private-key KEY   # With explicit key
"""

import argparse
import json
import sys
from decimal import Decimal
from typing import Tuple, Optional

import requests
from web3 import Web3
from eth_account import Account

# Contract addresses for Arbitrum Sepolia
UNIVERSAL_ROUTER_ADDRESS = "0x4A7b5Da61326A6379179b40d00F57E5bbDC962c2"
WETH_ADDRESS = "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73"  # WETH on Arbitrum Sepolia
USDC_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"   # USDC on Arbitrum Sepolia

# Pyth configuration
PYTH_HERMES_API = "https://hermes.pyth.network"
ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"

# RPC configuration
ARBITRUM_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc"

class UniRouterSwap:
    def __init__(self, rpc_url: str = ARBITRUM_SEPOLIA_RPC):
        """Initialize the Universal Router swap client"""
        self.w3 = Web3(Web3.HTTPProvider(rpc_url))
        
        if not self.w3.is_connected():
            raise ConnectionError(f"Failed to connect to RPC: {rpc_url}")
        
        print(f"✅ Connected to Arbitrum Sepolia")
        print(f"   Chain ID: {self.w3.eth.chain_id}")
        print(f"   Block: {self.w3.eth.block_number}")
        
        # Simplified Universal Router ABI - just the execute function
        self.router_abi = [
            {
                "inputs": [
                    {"internalType": "bytes", "name": "commands", "type": "bytes"},
                    {"internalType": "bytes[]", "name": "inputs", "type": "bytes[]"},
                    {"internalType": "uint256", "name": "deadline", "type": "uint256"}
                ],
                "name": "execute",
                "outputs": [],
                "stateMutability": "payable",
                "type": "function"
            }
        ]
        
        self.router_contract = self.w3.eth.contract(
            address=UNIVERSAL_ROUTER_ADDRESS,
            abi=self.router_abi
        )

    def fetch_pyth_price(self) -> Tuple[float, str]:
        """
        Fetch current ETH/USD price and update data from Pyth Hermes API
        Returns: (price, update_data_hex)
        """
        try:
            # Fetch latest price update
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
            
            return actual_price, update_data
            
        except requests.RequestException as e:
            raise ConnectionError(f"Failed to fetch Pyth price: {e}")
        except (KeyError, ValueError, TypeError) as e:
            raise ValueError(f"Failed to parse Pyth response: {e}")

    def build_v3_swap_commands(self, amount_wei: int, eth_to_usd: bool, recipient: str) -> Tuple[bytes, list]:
        """
        Build Universal Router commands for V3 swap
        Simplified version that uses direct V3 swap without wrapping
        """
        # Universal Router command IDs (as single bytes)
        if eth_to_usd:
            # ETH -> USDC: Use command 0x0b (WRAP_ETH) + 0x00 (V3_SWAP_EXACT_IN)
            commands = bytes([0x0b, 0x00])  # WRAP_ETH + V3_SWAP_EXACT_IN
        else:
            # USDC -> ETH: Use command 0x00 (V3_SWAP_EXACT_IN) + 0x0c (UNWRAP_WETH)  
            commands = bytes([0x00, 0x0c])  # V3_SWAP_EXACT_IN + UNWRAP_WETH
        
        inputs = []
        
        if eth_to_usd:
            # Input 1: WRAP_ETH (recipient, amount)
            wrap_input = self.w3.codec.encode(
                ['address', 'uint256'],
                [recipient, amount_wei]
            )
            inputs.append(wrap_input)
            
            # Input 2: V3_SWAP_EXACT_IN (recipient, amountIn, amountOutMin, path, payerIsUser)
            path = self.encode_v3_path(WETH_ADDRESS, 3000, USDC_ADDRESS)
            swap_input = self.w3.codec.encode(
                ['address', 'uint256', 'uint256', 'bytes', 'bool'],
                [recipient, amount_wei, 0, path, True]
            )
            inputs.append(swap_input)
        else:
            # Input 1: V3_SWAP_EXACT_IN (recipient, amountIn, amountOutMin, path, payerIsUser)
            path = self.encode_v3_path(USDC_ADDRESS, 3000, WETH_ADDRESS)
            swap_input = self.w3.codec.encode(
                ['address', 'uint256', 'uint256', 'bytes', 'bool'],
                [recipient, amount_wei, 0, path, True]
            )
            inputs.append(swap_input)
            
            # Input 2: UNWRAP_WETH (recipient, amountMin)
            unwrap_input = self.w3.codec.encode(
                ['address', 'uint256'],
                [recipient, 0]  # 0 = unwrap all
            )
            inputs.append(unwrap_input)
        
        return commands, inputs

    def encode_v3_path(self, token_a: str, fee: int, token_b: str) -> bytes:
        """
        Encode Uniswap V3 path for single hop swap
        Format: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes)
        """
        try:
            # Ensure addresses start with 0x and are valid
            if not token_a.startswith('0x') or len(token_a) != 42:
                raise ValueError(f"Invalid token_a address: {token_a}")
            if not token_b.startswith('0x') or len(token_b) != 42:
                raise ValueError(f"Invalid token_b address: {token_b}")
            
            # Convert to bytes (remove 0x prefix and ensure proper hex)
            token_a_clean = token_a[2:].lower()
            token_b_clean = token_b[2:].lower()
            
            # Validate hex characters
            if not all(c in '0123456789abcdef' for c in token_a_clean):
                raise ValueError(f"Invalid hex characters in token_a: {token_a}")
            if not all(c in '0123456789abcdef' for c in token_b_clean):
                raise ValueError(f"Invalid hex characters in token_b: {token_b}")
            
            token_a_bytes = bytes.fromhex(token_a_clean)
            token_b_bytes = bytes.fromhex(token_b_clean)
            fee_bytes = fee.to_bytes(3, 'big')
            
            path = token_a_bytes + fee_bytes + token_b_bytes
            
            print(f"🛣️  Encoded path: {token_a} → (fee: {fee}) → {token_b}")
            print(f"   Path length: {len(path)} bytes")
            
            return path
            
        except ValueError as e:
            raise ValueError(f"Failed to encode V3 path: {e}")

    def execute_swap(self, amount: str, direction: bool, private_key: str) -> str:
        """
        Execute the swap transaction
        
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
            
            # Convert amount to wei/smallest unit
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
            
            # Build swap commands
            print(f"🏗️  Building swap commands...")
            commands, inputs = self.build_v3_swap_commands(amount_wei, direction, sender)
            
            print(f"✅ Commands built: {commands.hex()}")
            print(f"   Number of inputs: {len(inputs)}")
            
            # Set deadline (10 minutes from now)
            latest_block = self.w3.eth.get_block('latest')
            deadline = latest_block['timestamp'] + 600
            print(f"⏰ Deadline: {deadline}")
            
            # Build transaction
            print(f"🔧 Building transaction...")
            tx_data = self.router_contract.functions.execute(
                commands,
                inputs,
                deadline
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
                print(f"   This might be due to insufficient balance, liquidity, or invalid parameters")
                raise Exception(f"Gas estimation failed: {e}")
            
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
    parser = argparse.ArgumentParser(description='Universal Router ETH/USD Swap on Arbitrum Sepolia - FIXED')
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
    print("🔄 Universal Router ETH/USD Swap - FIXED VERSION")
    print("=" * 60)
    print(f"Amount: {args.amount}")
    print(f"Direction: {direction_str}")
    print(f"Network: Arbitrum Sepolia")
    print(f"Debug: {args.debug}")
    print("=" * 60)
    
    try:
        # Initialize swap client
        swap_client = UniRouterSwap(args.rpc_url)
        
        # Fetch current price from Pyth
        price, update_data = swap_client.fetch_pyth_price()
        
        # Get private key - prioritize DEPLOYMENT_KEY for consistency with project deployment
        private_key = args.private_key
        if not private_key:
            import os
            # Try DEPLOYMENT_KEY first (project standard), then fall back to PRIVATE_KEY
            deployment_key = os.getenv('DEPLOYMENT_KEY')
            private_key_env = os.getenv('PRIVATE_KEY')
            
            # Validate DEPLOYMENT_KEY if it exists
            if deployment_key:
                # Check if it's a valid private key (64 hex chars + optional 0x prefix)
                clean_key = deployment_key.replace('0x', '').lower()
                if len(clean_key) == 64 and all(c in '0123456789abcdef' for c in clean_key):
                    private_key = deployment_key
                else:
                    print(f"⚠️  DEPLOYMENT_KEY appears to be an address ({deployment_key[:10]}...), not a private key")
                    print("   Falling back to PRIVATE_KEY environment variable")
            
            # Fall back to PRIVATE_KEY if DEPLOYMENT_KEY is invalid or not set
            if not private_key:
                private_key = private_key_env
        
        if not private_key:
            print("❌ Private key required for transaction signing")
            print("📝 Use one of these methods:")
            print("   1. --private-key YOUR_PRIVATE_KEY")
            print("   2. export DEPLOYMENT_KEY='0x1234...5678'  (64 hex chars)")
            print("   3. export PRIVATE_KEY='0x1234...5678'")
            print("   Note: Private key must be 64 hex characters (32 bytes)")
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
        
        print("\n✅ Swap completed successfully!")
        print(f"Transaction: {tx_hash}")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        if args.debug:
            import traceback
            traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main() 