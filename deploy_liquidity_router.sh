#!/bin/bash

# LiquidityRouter Deployment Script
# This script deploys the LiquidityRouter contract to Arbitrum Sepolia

echo "🚀 LiquidityRouter Deployment Script"
echo "===================================="

# Navigate to project root
cd ~/Work/Entrepreneurship/SamexLabs/detox-hook

# Load environment variables
echo "📋 Loading environment variables..."
source load_env.sh

# Verify environment variables are set
if [ -z "$DEPLOYMENT_WALLET" ]; then
    echo "❌ DEPLOYMENT_WALLET not set"
    exit 1
fi

if [ -z "$DEPLOYMENT_PRIVATE_KEY" ]; then
    echo "❌ DEPLOYMENT_PRIVATE_KEY not set"
    exit 1
fi

if [ -z "$ARBITRUM_SEPOLIA_RPC_URL" ]; then
    echo "❌ ARBITRUM_SEPOLIA_RPC_URL not set"
    exit 1
fi

echo "✅ Environment variables loaded"
echo "Deployer: $DEPLOYMENT_WALLET"
echo "RPC URL: $ARBITRUM_SEPOLIA_RPC_URL"

# Navigate to foundry directory
cd packages/foundry

# Build contracts
echo ""
echo "🔨 Building contracts..."
forge build

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful"

# Deploy using script method
echo ""
echo "🚀 Deploying LiquidityRouter using script..."
forge script script/DeployLiquidityRouter.s.sol:DeployLiquidityRouter \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast \
  --verify

if [ $? -eq 0 ]; then
    echo "✅ Deployment using script successful!"
    exit 0
fi

echo "⚠️ Script deployment failed, trying direct deployment..."

# Deploy using direct method
echo ""
echo "🚀 Deploying LiquidityRouter directly..."
forge create src/LiquidityRouter.sol:LiquidityRouter \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $DEPLOYMENT_PRIVATE_KEY \
  --constructor-args \
    "0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7" \
    "0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317"

if [ $? -eq 0 ]; then
    echo "✅ Direct deployment successful!"
    echo ""
    echo "📋 Next Steps:"
    echo "1. Copy the 'Deployed to:' address from above"
    echo "2. Update provide_liquidity_router.py with the new address"
    echo "3. Run the liquidity provision script"
else
    echo "❌ Both deployment methods failed"
    echo "Please check the troubleshooting guide in DEPLOYMENT_GUIDE_LiquidityRouter.md"
    exit 1
fi 