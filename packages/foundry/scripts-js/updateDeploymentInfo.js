#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

/**
 * Updates deployment info file with contract deployment details
 * Usage: node updateDeploymentInfo.js <contractAddress> <deploymentHash> <blockNumber> <deployer>
 */

async function updateDeploymentInfo() {
    const args = process.argv.slice(2);
    
    if (args.length < 4) {
        console.log('Usage: node updateDeploymentInfo.js <contractAddress> <deploymentHash> <blockNumber> <deployer>');
        console.log('Example: node updateDeploymentInfo.js 0x123...abc 0x456...def 12345678 0x789...ghi');
        process.exit(1);
    }

    const [contractAddress, deploymentHash, blockNumber, deployer] = args;
    const deploymentFile = path.join(__dirname, '../deployments/arbitrum-sepolia.json');

    try {
        // Read existing deployment file
        const deploymentData = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'));

        // Update SwapRouter deployment info
        deploymentData.deployments.SwapRouter.address = contractAddress;
        deploymentData.deployments.SwapRouter.deployer = deployer;
        deploymentData.deployments.SwapRouter.deploymentHash = deploymentHash;
        deploymentData.deployments.SwapRouter.blockNumber = parseInt(blockNumber);
        deploymentData.deployments.SwapRouter.timestamp = new Date().toISOString();
        deploymentData.lastUpdated = new Date().toISOString();

        // Write updated deployment file
        fs.writeFileSync(deploymentFile, JSON.stringify(deploymentData, null, 2));

        console.log('✅ Deployment info updated successfully!');
        console.log(`📝 Contract Address: ${contractAddress}`);
        console.log(`🔗 Block Explorer: ${deploymentData.configuration.blockExplorer}/address/${contractAddress}`);
        console.log(`📄 Deployment file: ${deploymentFile}`);

        // Also create a human-readable summary
        const summaryFile = path.join(__dirname, '../deployments/SwapRouter-deployment-summary.txt');
        const summary = `
SwapRouter Deployment Summary
============================

Network: Arbitrum Sepolia
Chain ID: 421614
Deployment Date: ${new Date().toLocaleString()}

Contract Details:
- Address: ${contractAddress}
- Deployer: ${deployer}
- Transaction Hash: ${deploymentHash}
- Block Number: ${blockNumber}

Configuration:
- PoolSwapTest: ${deploymentData.deployments.SwapRouter.constructorArgs.poolSwapTest}
- Pool: ETH/USDC
- Fee: 0.3% (3000 basis points)
- Tick Spacing: 60

Links:
- Contract: ${deploymentData.configuration.blockExplorer}/address/${contractAddress}
- Transaction: ${deploymentData.configuration.blockExplorer}/tx/${deploymentHash}
- Block: ${deploymentData.configuration.blockExplorer}/block/${blockNumber}

Usage Examples:
- Basic swap: swapRouter.swap(-1e18, "")  // Sell 1 ETH
- Exact output: swapRouter.swap(100e6, "") // Buy 100 USDC
        `.trim();

        fs.writeFileSync(summaryFile, summary);
        console.log(`📋 Summary file created: ${summaryFile}`);

    } catch (error) {
        console.error('❌ Error updating deployment info:', error.message);
        process.exit(1);
    }
}

updateDeploymentInfo(); 