#!/usr/bin/env python3
"""
Check LiquidityRouter Contract Availability

This script checks if the LiquidityRouter contract exists at the specified address
and provides deployment guidance if it doesn't.
"""

import os
import sys
from web3 import Web3

# Configuration
EXPECTED_LIQUIDITY_ROUTER_ADDRESS = "0x0eC2F4a959c0f4AE7596F75CF6760b8AC4298A48"
ARBITRUM_SEPOLIA_RPC_URL = "https://sepolia-rollup.arbitrum.io/rpc"

# Alternative addresses to check (from deployments)
ALTERNATIVE_ADDRESSES = [
    "0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7",  # PoolModifyLiquidityTest
    "0xf3A39C86dbd13C45365E57FB90fe413371F65AF8",  # PoolSwapTest
]

def connect_to_network():
    """Connect to Arbitrum Sepolia"""
    try:
        w3 = Web3(Web3.HTTPProvider(ARBITRUM_SEPOLIA_RPC_URL))
        if not w3.is_connected():
            print("❌ Failed to connect to Arbitrum Sepolia")
            return None
        
        chain_id = w3.eth.chain_id
        if chain_id != 421614:
            print(f"❌ Wrong network! Expected 421614, got {chain_id}")
            return None
            
        print(f"✅ Connected to Arbitrum Sepolia (Chain ID: {chain_id})")
        return w3
    except Exception as e:
        print(f"❌ Network connection failed: {e}")
        return None

def check_contract_exists(w3, address, name="Contract"):
    """Check if a contract exists at the given address"""
    try:
        code = w3.eth.get_code(address)
        if code != b'':
            print(f"✅ {name} exists at: {address}")
            print(f"   Code size: {len(code)} bytes")
            return True
        else:
            print(f"❌ No contract found at: {address}")
            return False
    except Exception as e:
        print(f"❌ Error checking {name}: {e}")
        return False

def check_deployment_status():
    """Check the status of LiquidityRouter deployment"""
    print("🔍 Checking LiquidityRouter Deployment Status")
    print("=" * 50)
    
    # Connect to network
    w3 = connect_to_network()
    if not w3:
        return False
    
    # Check expected address
    print(f"\n📋 Checking expected LiquidityRouter address...")
    router_exists = check_contract_exists(w3, EXPECTED_LIQUIDITY_ROUTER_ADDRESS, "LiquidityRouter")
    
    if router_exists:
        print(f"\n🎉 LiquidityRouter is deployed and ready!")
        return True
    
    # Check alternative addresses
    print(f"\n🔍 Checking alternative addresses...")
    for i, address in enumerate(ALTERNATIVE_ADDRESSES):
        name = f"Alternative Contract {i+1}"
        if check_contract_exists(w3, address, name):
            print(f"   ℹ️  This might be usable as an alternative")
    
    return False

def provide_deployment_guidance():
    """Provide guidance for deploying the LiquidityRouter"""
    print(f"\n📝 Deployment Guidance")
    print("=" * 30)
    print("The LiquidityRouter contract needs to be deployed first.")
    print("Here's how to deploy it:")
    print()
    print("1. Navigate to the project root:")
    print("   cd ~/Work/Entrepreneurship/SamexLabs/detox-hook")
    print()
    print("2. Load environment variables:")
    print("   source load_env.sh")
    print()
    print("3. Deploy the contract:")
    print("   cd packages/foundry")
    print("   forge script script/DeployLiquidityRouter.s.sol:DeployLiquidityRouter \\")
    print("     --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \\")
    print("     --broadcast")
    print()
    print("4. After deployment, update the address in provide_liquidity_router.py")
    print()
    print("💡 Alternative: Use the existing PoolModifyLiquidityTest contract directly:")
    print("   Address: 0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7")
    print("   This contract has the same modifyLiquidity functionality")

def check_environment():
    """Check if required environment variables are set"""
    print(f"\n🔧 Checking Environment Variables")
    print("=" * 35)
    
    required_vars = [
        "DEPLOYMENT_WALLET",
        "DEPLOYMENT_PRIVATE_KEY", 
        "ARBITRUM_SEPOLIA_RPC_URL"
    ]
    
    missing_vars = []
    for var in required_vars:
        if var in os.environ:
            if "PRIVATE_KEY" in var:
                print(f"✅ {var}: {'*' * 10}{os.environ[var][-4:]}")
            else:
                print(f"✅ {var}: {os.environ[var]}")
        else:
            print(f"❌ {var}: Not set")
            missing_vars.append(var)
    
    if missing_vars:
        print(f"\n⚠️  Missing environment variables: {', '.join(missing_vars)}")
        print("Run 'source load_env.sh' to load them.")
        return False
    
    return True

def main():
    """Main function"""
    print("🧪 LiquidityRouter Contract Check")
    print("=" * 40)
    
    # Check deployment status
    is_deployed = check_deployment_status()
    
    # Check environment
    env_ok = check_environment()
    
    if not is_deployed:
        provide_deployment_guidance()
        
        if not env_ok:
            print(f"\n❌ Cannot proceed: Missing environment variables")
            sys.exit(1)
        else:
            print(f"\n✅ Environment is ready for deployment")
            sys.exit(2)  # Exit code 2 = ready to deploy
    else:
        print(f"\n🚀 Ready to provide liquidity!")
        sys.exit(0)

if __name__ == "__main__":
    main() 