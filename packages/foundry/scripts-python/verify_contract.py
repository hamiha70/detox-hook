#!/usr/bin/env python3
"""
Contract Address Verifier for DetoxHook
=======================================

This script verifies if addresses belong to deployed contracts on Arbitrum Sepolia.
It provides multiple verification methods and integrates with DetoxHook environment.

Usage:
    python verify_contract.py <address1> [address2] [address3] ...
    python verify_contract.py --env-contracts
    python verify_contract.py --all
    
Examples:
    python verify_contract.py 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
    python verify_contract.py --env-contracts --verbose
    python verify_contract.py --all --json
"""

import os
import sys
import argparse
import json
from typing import List, Dict, Optional, Any
from pathlib import Path

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


class ContractVerifier:
    """Verifies if addresses are deployed contracts on Arbitrum Sepolia."""
    
    # Known contract addresses in DetoxHook ecosystem
    KNOWN_CONTRACTS = {
        "PoolManager": "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317",
        "USDC": "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
        "PythOracle": "0x4374e5a8b9C22271E9EB878A2AA31DE97DF15DAF",
        "PoolSwapTest": "0xf3A39C86dbd13C45365E57FB90fe413371F65AF8",
        "PoolModifyLiquidityTest": "0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7",
        "DetoxHook": "0x444F320aA27e73e1E293c14B22EfBDCbce0e0088",
    }
    
    def __init__(self, rpc_url: Optional[str] = None, verbose: bool = False):
        self.verbose = verbose
        self.rpc_url = rpc_url or self._get_rpc_url()
        self.w3 = None
        
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
    
    def verify_contract(self, address: str) -> Dict[str, Any]:
        """Verify if an address is a deployed contract."""
        if not self.w3:
            return {
                "address": address,
                "error": "Not connected to blockchain",
                "is_contract": False,
                "success": False
            }
        
        # Validate address format
        if not Web3.is_address(address):
            return {
                "address": address,
                "error": "Invalid address format",
                "is_contract": False,
                "success": False
            }
        
        try:
            checksum_address = Web3.to_checksum_address(address)
            
            # Get contract bytecode
            bytecode = self.w3.eth.get_code(checksum_address)
            
            # Check if bytecode exists (more than just '0x')
            is_contract = len(bytecode) > 0
            bytecode_size = len(bytecode)
            
            # Get additional information if it's a contract
            result = {
                "address": checksum_address,
                "is_contract": is_contract,
                "bytecode_size": bytecode_size,
                "bytecode_hex_length": len(bytecode.hex()),
                "success": True
            }
            
            if is_contract:
                # Try to get more contract information
                try:
                    # Get balance
                    balance_wei = self.w3.eth.get_balance(checksum_address)
                    balance_eth = self.w3.from_wei(balance_wei, 'ether')
                    
                    result["balance_wei"] = balance_wei
                    result["balance_eth"] = float(balance_eth)
                    
                    # Check if it's a known contract
                    known_name = None
                    for name, known_address in self.KNOWN_CONTRACTS.items():
                        if known_address.lower() == checksum_address.lower():
                            known_name = name
                            break
                    
                    if known_name:
                        result["known_contract"] = known_name
                    
                    # Try to detect contract type (very basic)
                    bytecode_hex = bytecode.hex()
                    if "a264697066735822" in bytecode_hex:  # IPFS hash indicator
                        result["has_metadata"] = True
                    
                    result["contract_type"] = "Smart Contract"
                    
                except Exception as e:
                    if self.verbose:
                        print(f"⚠️  Could not get additional contract info: {e}")
            else:
                # It's an EOA (Externally Owned Account)
                try:
                    balance_wei = self.w3.eth.get_balance(checksum_address)
                    balance_eth = self.w3.from_wei(balance_wei, 'ether')
                    
                    result["balance_wei"] = balance_wei
                    result["balance_eth"] = float(balance_eth)
                    result["contract_type"] = "EOA (Externally Owned Account)"
                    
                except Exception as e:
                    if self.verbose:
                        print(f"⚠️  Could not get balance: {e}")
            
            return result
            
        except Exception as e:
            return {
                "address": address,
                "error": f"Verification failed: {str(e)}",
                "is_contract": False,
                "success": False
            }
    
    def get_env_contracts(self) -> List[str]:
        """Get contract addresses from environment variables."""
        contracts = []
        
        # Load environment if needed
        if EnvLoader and not os.getenv('ARBITRUM_SEPOLIA_RPC_URL'):
            try:
                loader = EnvLoader(verbose=False, dry_run=False)
                loader.load_environment()
            except Exception:
                pass
        
        # Check environment variables for contract addresses
        env_contract_vars = [
            'SWAP_ROUTER_CONTRACT_ADDRESS',
            'PYTHTEST_CONTRACT_ADDRESS', 
            'POOL_MANAGER_ADDRESS',
            'DETOX_HOOK_ADDRESS',
        ]
        
        for env_var in env_contract_vars:
            address = os.getenv(env_var)
            if address and Web3.is_address(address):
                contracts.append(address)
        
        return contracts
    
    def display_results(self, results: List[Dict[str, Any]], show_details: bool = False):
        """Display verification results in a nice format."""
        print("\n📋 Contract Address Verification Report")
        print("=" * 55)
        
        total_addresses = len(results)
        contracts_found = sum(1 for r in results if r.get('is_contract', False))
        eoas_found = total_addresses - contracts_found
        
        print(f"📊 Checked {total_addresses} addresses:")
        print(f"   🏗️  {contracts_found} Smart Contracts")
        print(f"   👤 {eoas_found} EOA/Non-contracts")
        
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
            print(f"📍 Address: {address}")
            
            if not result.get('success', False):
                error = result.get('error', 'Unknown error')
                print(f"   ❌ Error: {error}")
                print()
                continue
            
            is_contract = result.get('is_contract', False)
            
            if is_contract:
                print("   ✅ STATUS: Smart Contract Deployed")
                
                # Show contract details
                bytecode_size = result.get('bytecode_size', 0)
                print(f"   📄 Bytecode size: {bytecode_size:,} bytes")
                
                known_name = result.get('known_contract')
                if known_name:
                    print(f"   🏷️  Known contract: {known_name}")
                
                balance_eth = result.get('balance_eth', 0)
                if balance_eth > 0:
                    print(f"   💰 Balance: {balance_eth:.6f} ETH")
                
                has_metadata = result.get('has_metadata', False)
                if has_metadata:
                    print(f"   📋 Has metadata: Yes")
                
                if show_details:
                    hex_length = result.get('bytecode_hex_length', 0)
                    print(f"   🔍 Bytecode hex length: {hex_length:,} chars")
                    
            else:
                print("   ⚪ STATUS: EOA (Externally Owned Account)")
                
                balance_eth = result.get('balance_eth', 0)
                if balance_eth > 0:
                    print(f"   💰 Balance: {balance_eth:.6f} ETH")
                else:
                    print(f"   💸 Balance: 0 ETH")
            
            print()


def main():
    """Main function to handle command line arguments and execute verification."""
    parser = argparse.ArgumentParser(
        description="Verify if addresses are deployed contracts on Arbitrum Sepolia",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
  %(prog)s --env-contracts --verbose
  %(prog)s --all --json
  %(prog)s address1 address2 --show-details
        """
    )
    
    parser.add_argument(
        'addresses',
        nargs='*',
        help='Addresses to verify'
    )
    
    parser.add_argument(
        '--env-contracts',
        action='store_true',
        help='Check contract addresses from environment variables'
    )
    
    parser.add_argument(
        '--all',
        action='store_true',
        help='Check all known contracts (combines addresses + env + known)'
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
        '--show-details',
        action='store_true',
        help='Show additional contract details'
    )
    
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    
    args = parser.parse_args()
    
    # Collect addresses to verify
    addresses_to_check = []
    
    if args.addresses:
        addresses_to_check.extend(args.addresses)
    
    if args.env_contracts or args.all:
        verifier = ContractVerifier(rpc_url=args.rpc_url, verbose=args.verbose)
        env_contracts = verifier.get_env_contracts()
        addresses_to_check.extend(env_contracts)
        
        if args.verbose:
            print(f"📂 Found {len(env_contracts)} contracts from environment")
    
    if args.all:
        known_addresses = list(ContractVerifier.KNOWN_CONTRACTS.values())
        addresses_to_check.extend(known_addresses)
        
        if args.verbose:
            print(f"📋 Added {len(known_addresses)} known DetoxHook contracts")
    
    # Remove duplicates while preserving order
    unique_addresses = []
    seen = set()
    for addr in addresses_to_check:
        addr_lower = addr.lower()
        if addr_lower not in seen:
            unique_addresses.append(addr)
            seen.add(addr_lower)
    
    if not unique_addresses:
        print("❌ No addresses provided. Use --help for usage information.")
        return 1
    
    # Create verifier and check all addresses
    verifier = ContractVerifier(rpc_url=args.rpc_url, verbose=args.verbose)
    
    if not verifier.w3:
        print("❌ Could not connect to blockchain")
        return 1
    
    results = []
    for address in unique_addresses:
        if args.verbose:
            print(f"🔍 Verifying {address}...")
        
        result = verifier.verify_contract(address)
        results.append(result)
    
    # Display results
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        verifier.display_results(results, show_details=args.show_details)
    
    return 0


if __name__ == '__main__':
    sys.exit(main()) 