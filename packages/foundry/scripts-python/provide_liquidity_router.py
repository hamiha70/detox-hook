#!/usr/bin/env python3
"""
LiquidityRouter Liquidity Provision Script

This script uses the LiquidityRouter contract to provide liquidity to a Uniswap V4 pool
on Arbitrum Sepolia using the specified parameters.
"""

import os
import sys
import json
import subprocess
from decimal import Decimal
from web3 import Web3
from eth_account import Account
import argparse

# Configuration
LIQUIDITY_ROUTER_ADDRESS = "0x438E9E3cf5eB83D0c1Fe7Ce999159859bd97b34a"
ARBITRUM_SEPOLIA_RPC_URL = "https://sepolia-rollup.arbitrum.io/rpc"

# Pool configuration
POOL_KEY = {
    "currency0": "0x0000000000000000000000000000000000000000",
    "currency1": "0x9D5A68fDFEcc14683324640D5e835936422a47b1",
    "fee": 300,
    "tickSpacing": 40,
    "hooks": "0x25b9b40a53c9FAB2d7b2190eb406A22e2d738088"
}

# Liquidity parameters - centered around current pool tick (-81160)
TICK_LOWER = -85160  # Below current price (center - 4000, divisible by 40)
TICK_UPPER = -77160   # Above current price (center + 4000, divisible by 40)
LIQUIDITY_DELTA = 100  # Smaller amount to test
SALT = "0x0000000000000000000000000000000000000000000000000000000000000001"

# LiquidityRouter ABI (minimal for addLiquidity function)
LIQUIDITY_ROUTER_ABI = [{'type': 'constructor',
  'inputs': [{'name': '_poolModifyLiquidityTest',
    'type': 'address',
    'internalType': 'address'},
   {'name': '_poolManager', 'type': 'address', 'internalType': 'address'}],
  'stateMutability': 'nonpayable'},
 {'type': 'fallback', 'stateMutability': 'payable'},
 {'type': 'receive', 'stateMutability': 'payable'},
 {'type': 'function',
  'name': 'addLiquidity',
  'inputs': [{'name': 'poolKey',
    'type': 'tuple',
    'internalType': 'struct PoolKey',
    'components': [{'name': 'currency0',
      'type': 'address',
      'internalType': 'Currency'},
     {'name': 'currency1', 'type': 'address', 'internalType': 'Currency'},
     {'name': 'fee', 'type': 'uint24', 'internalType': 'uint24'},
     {'name': 'tickSpacing', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'hooks', 'type': 'address', 'internalType': 'contract IHooks'}]},
   {'name': 'tickLower', 'type': 'int24', 'internalType': 'int24'},
   {'name': 'tickUpper', 'type': 'int24', 'internalType': 'int24'},
   {'name': 'liquidityDelta', 'type': 'int256', 'internalType': 'int256'},
   {'name': 'salt', 'type': 'bytes32', 'internalType': 'bytes32'},
   {'name': 'updateData', 'type': 'bytes', 'internalType': 'bytes'}],
  'outputs': [{'name': 'delta',
    'type': 'int256',
    'internalType': 'BalanceDelta'}],
  'stateMutability': 'payable'},
 {'type': 'function',
  'name': 'approvePoolTokens',
  'inputs': [{'name': 'poolKey',
    'type': 'tuple',
    'internalType': 'struct PoolKey',
    'components': [{'name': 'currency0',
      'type': 'address',
      'internalType': 'Currency'},
     {'name': 'currency1', 'type': 'address', 'internalType': 'Currency'},
     {'name': 'fee', 'type': 'uint24', 'internalType': 'uint24'},
     {'name': 'tickSpacing', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'hooks',
      'type': 'address',
      'internalType': 'contract IHooks'}]}],
  'outputs': [],
  'stateMutability': 'nonpayable'},
 {'type': 'function',
  'name': 'approveToken',
  'inputs': [{'name': 'token', 'type': 'address', 'internalType': 'address'},
   {'name': 'amount', 'type': 'uint256', 'internalType': 'uint256'}],
  'outputs': [],
  'stateMutability': 'nonpayable'},
 {'type': 'function',
  'name': 'emergencyWithdraw',
  'inputs': [{'name': 'token', 'type': 'address', 'internalType': 'address'},
   {'name': 'amount', 'type': 'uint256', 'internalType': 'uint256'}],
  'outputs': [],
  'stateMutability': 'nonpayable'},
 {'type': 'function',
  'name': 'getPoolManager',
  'inputs': [],
  'outputs': [{'name': '', 'type': 'address', 'internalType': 'address'}],
  'stateMutability': 'view'},
 {'type': 'function',
  'name': 'getPoolModifyLiquidityTest',
  'inputs': [],
  'outputs': [{'name': '', 'type': 'address', 'internalType': 'address'}],
  'stateMutability': 'view'},
 {'type': 'function',
  'name': 'modifyLiquidity',
  'inputs': [{'name': 'poolKey',
    'type': 'tuple',
    'internalType': 'struct PoolKey',
    'components': [{'name': 'currency0',
      'type': 'address',
      'internalType': 'Currency'},
     {'name': 'currency1', 'type': 'address', 'internalType': 'Currency'},
     {'name': 'fee', 'type': 'uint24', 'internalType': 'uint24'},
     {'name': 'tickSpacing', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'hooks', 'type': 'address', 'internalType': 'contract IHooks'}]},
   {'name': 'params',
    'type': 'tuple',
    'internalType': 'struct ModifyLiquidityParams',
    'components': [{'name': 'tickLower',
      'type': 'int24',
      'internalType': 'int24'},
     {'name': 'tickUpper', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'liquidityDelta', 'type': 'int256', 'internalType': 'int256'},
     {'name': 'salt', 'type': 'bytes32', 'internalType': 'bytes32'}]},
   {'name': 'updateData', 'type': 'bytes', 'internalType': 'bytes'},
   {'name': 'takeClaims', 'type': 'bool', 'internalType': 'bool'},
   {'name': 'settleUsingBurn', 'type': 'bool', 'internalType': 'bool'}],
  'outputs': [{'name': 'delta',
    'type': 'int256',
    'internalType': 'BalanceDelta'}],
  'stateMutability': 'payable'},
 {'type': 'function',
  'name': 'modifyLiquidity',
  'inputs': [{'name': 'poolKey',
    'type': 'tuple',
    'internalType': 'struct PoolKey',
    'components': [{'name': 'currency0',
      'type': 'address',
      'internalType': 'Currency'},
     {'name': 'currency1', 'type': 'address', 'internalType': 'Currency'},
     {'name': 'fee', 'type': 'uint24', 'internalType': 'uint24'},
     {'name': 'tickSpacing', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'hooks', 'type': 'address', 'internalType': 'contract IHooks'}]},
   {'name': 'params',
    'type': 'tuple',
    'internalType': 'struct ModifyLiquidityParams',
    'components': [{'name': 'tickLower',
      'type': 'int24',
      'internalType': 'int24'},
     {'name': 'tickUpper', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'liquidityDelta', 'type': 'int256', 'internalType': 'int256'},
     {'name': 'salt', 'type': 'bytes32', 'internalType': 'bytes32'}]},
   {'name': 'updateData', 'type': 'bytes', 'internalType': 'bytes'}],
  'outputs': [{'name': 'delta',
    'type': 'int256',
    'internalType': 'BalanceDelta'}],
  'stateMutability': 'payable'},
 {'type': 'function',
  'name': 'poolManager',
  'inputs': [],
  'outputs': [{'name': '',
    'type': 'address',
    'internalType': 'contract IPoolManager'}],
  'stateMutability': 'view'},
 {'type': 'function',
  'name': 'poolModifyLiquidityTest',
  'inputs': [],
  'outputs': [{'name': '',
    'type': 'address',
    'internalType': 'contract PoolModifyLiquidityTest'}],
  'stateMutability': 'view'},
 {'type': 'function',
  'name': 'prepareTokens',
  'inputs': [{'name': 'poolKey',
    'type': 'tuple',
    'internalType': 'struct PoolKey',
    'components': [{'name': 'currency0',
      'type': 'address',
      'internalType': 'Currency'},
     {'name': 'currency1', 'type': 'address', 'internalType': 'Currency'},
     {'name': 'fee', 'type': 'uint24', 'internalType': 'uint24'},
     {'name': 'tickSpacing', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'hooks', 'type': 'address', 'internalType': 'contract IHooks'}]},
   {'name': 'liquidityDelta', 'type': 'int256', 'internalType': 'int256'}],
  'outputs': [],
  'stateMutability': 'payable'},
 {'type': 'function',
  'name': 'removeLiquidity',
  'inputs': [{'name': 'poolKey',
    'type': 'tuple',
    'internalType': 'struct PoolKey',
    'components': [{'name': 'currency0',
      'type': 'address',
      'internalType': 'Currency'},
     {'name': 'currency1', 'type': 'address', 'internalType': 'Currency'},
     {'name': 'fee', 'type': 'uint24', 'internalType': 'uint24'},
     {'name': 'tickSpacing', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'hooks', 'type': 'address', 'internalType': 'contract IHooks'}]},
   {'name': 'tickLower', 'type': 'int24', 'internalType': 'int24'},
   {'name': 'tickUpper', 'type': 'int24', 'internalType': 'int24'},
   {'name': 'liquidityDelta', 'type': 'int256', 'internalType': 'int256'},
   {'name': 'salt', 'type': 'bytes32', 'internalType': 'bytes32'},
   {'name': 'updateData', 'type': 'bytes', 'internalType': 'bytes'}],
  'outputs': [{'name': 'delta',
    'type': 'int256',
    'internalType': 'BalanceDelta'}],
  'stateMutability': 'payable'},
 {'type': 'event',
  'name': 'LiquidityModified',
  'inputs': [{'name': 'sender',
    'type': 'address',
    'indexed': True,
    'internalType': 'address'},
   {'name': 'poolKey',
    'type': 'tuple',
    'indexed': True,
    'internalType': 'struct PoolKey',
    'components': [{'name': 'currency0',
      'type': 'address',
      'internalType': 'Currency'},
     {'name': 'currency1', 'type': 'address', 'internalType': 'Currency'},
     {'name': 'fee', 'type': 'uint24', 'internalType': 'uint24'},
     {'name': 'tickSpacing', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'hooks', 'type': 'address', 'internalType': 'contract IHooks'}]},
   {'name': 'params',
    'type': 'tuple',
    'indexed': False,
    'internalType': 'struct ModifyLiquidityParams',
    'components': [{'name': 'tickLower',
      'type': 'int24',
      'internalType': 'int24'},
     {'name': 'tickUpper', 'type': 'int24', 'internalType': 'int24'},
     {'name': 'liquidityDelta', 'type': 'int256', 'internalType': 'int256'},
     {'name': 'salt', 'type': 'bytes32', 'internalType': 'bytes32'}]},
   {'name': 'delta',
    'type': 'int256',
    'indexed': False,
    'internalType': 'BalanceDelta'},
   {'name': 'takeClaims',
    'type': 'bool',
    'indexed': False,
    'internalType': 'bool'},
   {'name': 'settleUsingBurn',
    'type': 'bool',
    'indexed': False,
    'internalType': 'bool'}],
  'anonymous': False},
 {'type': 'event',
  'name': 'TokensApproved',
  'inputs': [{'name': 'token',
    'type': 'address',
    'indexed': True,
    'internalType': 'address'},
   {'name': 'spender',
    'type': 'address',
    'indexed': True,
    'internalType': 'address'},
   {'name': 'amount',
    'type': 'uint256',
    'indexed': False,
    'internalType': 'uint256'}],
  'anonymous': False},
 {'type': 'error', 'name': 'InsufficientBalance', 'inputs': []},
 {'type': 'error', 'name': 'PoolManagerNotSet', 'inputs': []},
 {'type': 'error', 'name': 'PoolModifyLiquidityTestNotSet', 'inputs': []},
 {'type': 'error',
  'name': 'SafeERC20FailedOperation',
  'inputs': [{'name': 'token', 'type': 'address', 'internalType': 'address'}]},
 {'type': 'error', 'name': 'TokenTransferFailed', 'inputs': []}
 ]

# ERC20 ABI for token operations
ERC20_ABI = [
    {
        "inputs": [
            {"name": "spender", "type": "address"},
            {"name": "amount", "type": "uint256"}
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {"name": "owner", "type": "address"},
            {"name": "spender", "type": "address"}
        ],
        "name": "allowance",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [{"name": "account", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function"
    }
]

def load_environment():
    """Load environment variables"""
    try:
        wallet_address = os.environ["LIQUIDITY_PROVIDER_WALLET"]
        private_key = os.environ["LIQUIDITY_PROVIDER_PRIVATE_KEY"]
        return wallet_address, private_key
    except KeyError as e:
        print(f"❌ Environment variable not set: {e}")
        print("Please set LIQUIDITY_PROVIDER_WALLET and LIQUIDITY_PROVIDER_PRIVATE_KEY")
        sys.exit(1)

def connect_to_network():
    """Connect to Arbitrum Sepolia network"""
    try:
        w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC_URL))
        if not w3.is_connected():
            raise Exception("Failed to connect to RPC")
        
        # Check chain ID
        chain_id = w3.eth.chain_id
        if chain_id != 421614:
            print(f"❌ Wrong network! Expected Arbitrum Sepolia (421614), got {chain_id}")
            sys.exit(1)
        
        print(f"✅ Connected to Arbitrum Sepolia (Chain ID: {chain_id})")
        return w3
    except Exception as e:
        print(f"❌ Failed to connect to network: {e}")
        sys.exit(1)

def validate_contract(w3, address, name):
    """Validate that a contract exists at the given address"""
    try:
        code = w3.eth.get_code(address)
        if code == b'':
            raise Exception(f"No contract found at {address}")
        print(f"✅ Validated {name} at: {address}")
        return True
    except Exception as e:
        print(f"❌ {name} validation failed: {e}")
        return False

def get_contract_info(w3, contract_address, abi):
    """Get contract instance and basic info"""
    try:
        contract = w3.eth.contract(address=contract_address, abi=abi)
        
        # Get basic contract info
        pool_manager = contract.functions.getPoolManager().call()
        pool_modify_liquidity_test = contract.functions.getPoolModifyLiquidityTest().call()
        
        print(f"✅ LiquidityRouter contract info:")
        print(f"   Address: {contract_address}")
        print(f"   PoolManager: {pool_manager}")
        print(f"   PoolModifyLiquidityTest: {pool_modify_liquidity_test}")
        
        return contract
    except Exception as e:
        print(f"❌ Failed to get contract info: {e}")
        return None

def prepare_pool_key():
    """Prepare the pool key tuple for the contract call"""
    return (
        POOL_KEY["currency0"],
        POOL_KEY["currency1"],
        POOL_KEY["fee"],
        POOL_KEY["tickSpacing"],
        POOL_KEY["hooks"]
    )

def check_wallet_balance(w3, wallet_address):
    """Check wallet ETH balance"""
    try:
        balance = w3.eth.get_balance(wallet_address)
        balance_eth = w3.from_wei(balance, 'ether')
        print(f"💰 Wallet ETH balance: {balance_eth} ETH")
        
        if balance < w3.to_wei(0.001, 'ether'):
            print("❌ Insufficient ETH balance for transaction")
            return False
        
        return True
    except Exception as e:
        print(f"❌ Failed to check wallet balance: {e}")
        return False

def check_token_balance(w3, token_address, wallet_address):
    """Check wallet token balance"""
    try:
        if token_address == "0x0000000000000000000000000000000000000000":
            return True  # ETH - already checked
        
        token_contract = w3.eth.contract(address=token_address, abi=ERC20_ABI)
        balance = token_contract.functions.balanceOf(wallet_address).call()
        print(f"💰 MockUSDC balance: {balance}")
        
        if balance < 1000:  # Need some tokens for liquidity
            print("❌ Insufficient MockUSDC balance")
            return False
        
        return True
    except Exception as e:
        print(f"❌ Failed to check token balance: {e}")
        return False

def check_token_approval(w3, token_address, wallet_address, spender_address):
    """Check token approval"""
    try:
        if token_address == "0x0000000000000000000000000000000000000000":
            return True  # ETH doesn't need approval
        
        token_contract = w3.eth.contract(address=token_address, abi=ERC20_ABI)
        allowance = token_contract.functions.allowance(wallet_address, spender_address).call()
        print(f"🔍 Current MockUSDC allowance: {allowance}")
        
        # Check if allowance is sufficient (need at least some amount)
        return allowance > 1000
    except Exception as e:
        print(f"❌ Failed to check token approval: {e}")
        return False

def approve_tokens(w3, wallet_address, private_key):
    """Approve MockUSDC tokens for LiquidityRouter"""
    try:
        print("🔐 Approving MockUSDC tokens...")
        
        # Create token contract instance
        token_contract = w3.eth.contract(
            address=POOL_KEY["currency1"],  # MockUSDC
            abi=ERC20_ABI
        )
        
        # Check current allowance
        current_allowance = token_contract.functions.allowance(
            wallet_address, 
            LIQUIDITY_ROUTER_ADDRESS
        ).call()
        
        if current_allowance >= 2**255:  # Already has max approval
            print("✅ MockUSDC already approved")
            return True
        
        # Build approval transaction
        approval_tx = token_contract.functions.approve(
            LIQUIDITY_ROUTER_ADDRESS,
            2**256 - 1  # Max approval
        ).build_transaction({
            'from': wallet_address,
            'gas': 100000,
            'gasPrice': w3.eth.gas_price,
            'nonce': w3.eth.get_transaction_count(wallet_address)
        })
        
        # Sign and send approval transaction
        signed_approval = w3.eth.account.sign_transaction(approval_tx, private_key)
        approval_hash = w3.eth.send_raw_transaction(signed_approval.rawTransaction)
        
        print(f"📝 Approval transaction sent: {approval_hash.hex()}")
        print("⏳ Waiting for approval confirmation...")
        
        approval_receipt = w3.eth.wait_for_transaction_receipt(approval_hash, timeout=60)
        
        if approval_receipt.status == 1:
            print("✅ MockUSDC approval successful!")
            return True
        else:
            print("❌ MockUSDC approval failed!")
            return False
            
    except Exception as e:
        print(f"❌ Token approval failed: {e}")
        return False

def estimate_gas(w3, contract, wallet_address, pool_key_tuple):
    """Estimate gas for the liquidity provision transaction"""
    try:
        # Estimate gas
        estimated_gas = contract.functions.addLiquidity(
            pool_key_tuple,
            TICK_LOWER,
            TICK_UPPER,
            LIQUIDITY_DELTA,
            SALT,
            b''  # updateData (empty for now)
        ).estimate_gas({
            'from': wallet_address,
            'value': w3.to_wei(0.001, 'ether')
        })
        
        # Get gas price
        gas_price = w3.eth.gas_price
        
        print(f"✅ Gas estimation successful:")
        print(f"   Estimated gas: {estimated_gas:,}")
        print(f"   Gas price: {w3.from_wei(gas_price, 'gwei')} gwei")
        print(f"   Estimated cost: {w3.from_wei(estimated_gas * gas_price, 'ether')} ETH")
        
        return estimated_gas, gas_price
        
    except Exception as e:
        print(f"❌ Gas estimation failed: {e}")
        
        # Try to decode the error if it's a contract error
        if hasattr(e, 'args') and len(e.args) > 0:
            error_data = e.args[0]
            if isinstance(error_data, dict) and 'data' in error_data:
                error_hex = error_data['data']
                print(f"🔍 Error data: {error_hex}")
                
                # Try to decode common Uniswap V4 errors
                if error_hex.startswith('0x'):
                    error_selector = error_hex[:10]
                    print(f"🔍 Error selector: {error_selector}")
                    
                    # Common Uniswap V4 error selectors
                    error_messages = {
                        '0xe450d38c': 'Invalid tick range (tickLower >= tickUpper)',
                        '0x7983c051': 'Pool already initialized',
                        '0x4e487b71': 'Pool not initialized',
                        '0x4d2301cc': 'Invalid pool key',
                        '0x4d2301cd': 'Invalid liquidity amount',
                        '0x4d2301ce': 'Tick out of bounds',
                        '0x4d2301cf': 'Invalid tick spacing',
                        '0x4d2301d0': 'Invalid currency order',
                        '0x4d2301d1': 'Invalid hook address',
                        '0x4d2301d2': 'Invalid fee tier',
                        '0x4d2301d3': 'Invalid tick spacing for fee tier'
                    }
                    
                    if error_selector in error_messages:
                        print(f"🔍 Error meaning: {error_messages[error_selector]}")
                    else:
                        print(f"🔍 Unknown error selector: {error_selector}")
                        
                    # Try to decode additional error data
                    if len(error_hex) > 10:
                        error_data_hex = error_hex[10:]
                        print(f"🔍 Additional error data: {error_data_hex}")
                        
                        # Try to decode as addresses or numbers
                        try:
                            # Check if it contains addresses
                            if len(error_data_hex) >= 64:  # At least 32 bytes
                                # Try to decode as address
                                address_part = error_data_hex[:40]  # 20 bytes = 40 hex chars
                                print(f"🔍 Possible address in error: 0x{address_part}")
                        except:
                            pass
        
        return None, None

def provide_liquidity(w3, contract, wallet_address, private_key, pool_key_tuple):
    """Execute the liquidity provision transaction"""
    try:
        # Get current nonce
        nonce = w3.eth.get_transaction_count(wallet_address)
        
        # Estimate gas
        estimated_gas, gas_price = estimate_gas(w3, contract, wallet_address, pool_key_tuple)
        if estimated_gas is None:
            return False
        
        # Build transaction
        transaction = contract.functions.addLiquidity(
            pool_key_tuple,
            TICK_LOWER,
            TICK_UPPER,
            LIQUIDITY_DELTA,
            SALT,
            b''  # updateData (empty for now)
        ).build_transaction({
            'from': wallet_address,
            'value': w3.to_wei(0.001, 'ether'),  # Small ETH value
            'gas': int(estimated_gas * 1.2),  # Add 20% buffer
            'gasPrice': gas_price,
            'nonce': nonce
        })
        
        # Sign transaction
        signed_txn = w3.eth.account.sign_transaction(transaction, private_key)
        
        print(f"📝 Sending transaction...")
        print(f"   From: {wallet_address}")
        print(f"   To: {LIQUIDITY_ROUTER_ADDRESS}")
        print(f"   Gas: {transaction['gas']:,}")
        print(f"   Value: {w3.from_wei(transaction['value'], 'ether')} ETH")
        
        # Send transaction
        tx_hash = w3.eth.send_raw_transaction(signed_txn.rawTransaction)
        print(f"✅ Transaction sent: {tx_hash.hex()}")
        
        # Wait for transaction receipt
        print("⏳ Waiting for transaction confirmation...")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        
        if receipt.status == 1:
            print(f"✅ Transaction successful!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed:,}")
            print(f"   Transaction hash: {receipt.transactionHash.hex()}")
            
            # Try to decode events if any
            try:
                logs = receipt.logs
                if logs:
                    print(f"📋 {len(logs)} events emitted")
                    for i, log in enumerate(logs):
                        print(f"   Event {i+1}: {log}")
            except Exception as e:
                print(f"⚠️ Could not decode events: {e}")
            
            return True
        else:
            print(f"❌ Transaction failed!")
            return False
            
    except Exception as e:
        print(f"❌ Transaction failed: {e}")
        return False

def check_pool_exists(w3, pool_key_tuple):
    """Check if the pool exists and is initialized"""
    try:
        # Use the deployed PoolStateViewer contract
        #pool_state_viewer_address = "0xD87870729fe0efB97be17FD5735513782c33Db56"
        # ABI for PoolStateViewer with both getIdByKey and getPoolStateById
        # pool_state_viewer_abi = [
        #     {
        #         "inputs": [
        #             {
        #                 "internalType": "tuple",
        #                 "name": "poolKey",
        #                 "type": "tuple",
        #                 "components": [
        #                     {"internalType": "address", "name": "currency0", "type": "address"},
        #                     {"internalType": "address", "name": "currency1", "type": "address"},
        #                     {"internalType": "uint24", "name": "fee", "type": "uint24"},
        #                     {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
        #                     {"internalType": "address", "name": "hooks", "type": "address"}
        #                 ]
        #             }
        #         ],
        #         "name": "getIdByKey",
        #         "outputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
        #         "stateMutability": "view",
        #         "type": "function"
        #     },
        #     {
        #         "inputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
        #         "name": "getPoolStateById",
        #         "outputs": [
        #             {"internalType": "uint160", "name": "sqrtPriceX96", "type": "uint160"},
        #             {"internalType": "int24", "name": "tick", "type": "int24"},
        #             {"internalType": "uint8", "name": "protocolFee", "type": "uint8"},
        #             {"internalType": "uint8", "name": "swapFee", "type": "uint8"}
        #         ],
        #         "stateMutability": "view",
        #         "type": "function"
        #     }
        # ]
        pool_state_viewer_address = "0xA0386BBB0d8F176D4EdCFfAD6Aa1CDa833f11380"
        pool_state_viewer_abi =[
            {
                "inputs": [{"internalType": "bytes32", "name": "poolId", "type": "bytes32"}],
                "name": "getPoolStateById",
                "outputs": [
                    {"internalType": "uint160", "name": "sqrtPriceX96", "type": "uint160"},
                    {"internalType": "int24", "name": "tick", "type": "int24"},
                    {"internalType": "uint24", "name": "protocolFee", "type": "uint24"},
                    {"internalType": "uint24", "name": "lpFee", "type": "uint24"},
                    {"internalType": "uint128", "name": "liquidity", "type": "uint128"},
                    {"internalType": "bool", "name": "success", "type": "bool"}
                ],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [
                    {"internalType": "bytes32", "name": "poolId", "type": "bytes32"},
                    {"internalType": "int24", "name": "tick", "type": "int24"}
                ],
                "name": "getTickInfo",
                "outputs": [
                    {"internalType": "uint128", "name": "liquidity", "type": "uint128"},
                    {"internalType": "bool", "name": "success", "type": "bool"}
                ],
                "stateMutability": "view",
                "type": "function"
            }
        ]

        pool_state_viewer = w3.eth.contract(address=pool_state_viewer_address, abi=pool_state_viewer_abi)
        
        print(f"🔍 Checking pool existence using PoolStateViewer...")
        
        # Get pool ID from PoolStateViewer
        pool_id = pool_state_viewer.functions.getIdByKey(pool_key_tuple).call()
        pool_id_hex ='0x'+pool_id.hex()
        
        print(f"   Pool ID-: {pool_id_hex}")
        
        pool_state = pool_state_viewer.functions.getPoolStateByKey(pool_key_tuple).call()
        print(f"✅ Pool exists and is initialized!")


        # Try to get pool state using PoolStateViewer (not PoolManager)
        try:
            pool_state = pool_state_viewer.functions.getPoolStateById(pool_id).call()
            
            print(f"✅ Pool exists and is initialized!")
            print(f"   Current tick: {pool_state[1]}")
            print(f"   Current sqrtPriceX96: {pool_state[0]}")
            print(f"   Protocol fee: {pool_state[2]}")
            print(f"   Swap fee: {pool_state[3]}")
            return True
            
        except Exception as e:
            print(f"❌ Pool state query failed: {e}")
            return False
        
    except Exception as e:
        print(f"❌ Pool does not exist or is not initialized: {e}")
        return False

def main():
    """Main function"""
    print("🚀 LiquidityRouter Liquidity Provision Script")
    print("=" * 50)
    
    # Load environment variables
    print("📋 Loading environment variables...")
    wallet_address, private_key = load_environment()
    print(f"✅ Wallet: {wallet_address}")
    
    # Connect to network
    print("\n🌐 Connecting to Arbitrum Sepolia...")
    w3 = connect_to_network()
    
    # Validate LiquidityRouter contract
    print(f"\n🔍 Validating LiquidityRouter contract...")
    if not validate_contract(w3, LIQUIDITY_ROUTER_ADDRESS, "LiquidityRouter"):
        sys.exit(1)
    
    # Get contract instance
    contract = get_contract_info(w3, LIQUIDITY_ROUTER_ADDRESS, LIQUIDITY_ROUTER_ABI)
    if contract is None:
        sys.exit(1)
    
    # Check wallet balance
    print(f"\n💰 Checking wallet balance...")
    if not check_wallet_balance(w3, wallet_address):
        sys.exit(1)
    
    # Check token balance  
    print(f"\n💰 Checking MockUSDC balance...")
    if not check_token_balance(w3, POOL_KEY["currency1"], wallet_address):
        sys.exit(1)
    
    # Check token approval
    print(f"\n🔍 Checking MockUSDC approval...")
    if not check_token_approval(w3, POOL_KEY["currency1"], wallet_address, LIQUIDITY_ROUTER_ADDRESS):
        print("⚠️ Token approval needed - attempting to approve...")
        if not approve_tokens(w3, wallet_address, private_key):
            sys.exit(1)
    
    # Prepare pool key
    print(f"\n🔧 Preparing pool configuration...")
    pool_key_tuple = prepare_pool_key()
    if pool_key_tuple is None:
        sys.exit(1)
    
    # Check if pool exists
    pool_exists = check_pool_exists(w3, pool_key_tuple)
    if not pool_exists:
        print("⚠️ Pool existence check failed, but proceeding anyway...")
        print("   (Pool may exist but be inaccessible through current method)")
        print("   Continuing with liquidity provision attempt...")
    
    # Provide liquidity
    print(f"\n💧 Providing liquidity...")
    if not provide_liquidity(w3, contract, wallet_address, private_key, pool_key_tuple):
        print("❌ Liquidity provision failed!")
        sys.exit(1)
    
    print("✅ Liquidity provision completed successfully!")

if __name__ == "__main__":
    main() 