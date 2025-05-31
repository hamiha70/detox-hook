#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

/**
 * Updates the SwapRouter contract address in deployedContracts.ts
 * Usage: node updateSwapRouterAddress.js <contractAddress>
 */

async function updateSwapRouterAddress() {
    const args = process.argv.slice(2);
    
    if (args.length < 1) {
        console.log('Usage: node updateSwapRouterAddress.js <contractAddress>');
        console.log('Example: node updateSwapRouterAddress.js 0x123...abc');
        process.exit(1);
    }

    const [contractAddress] = args;
    const contractsFile = path.join(__dirname, '../contracts/deployedContracts.ts');

    try {
        // Read existing contracts file
        let contractsContent = fs.readFileSync(contractsFile, 'utf8');

        // Replace the placeholder address with the actual deployed address
        const placeholderAddress = '0x0000000000000000000000000000000000000000';
        contractsContent = contractsContent.replace(
            `address: "${placeholderAddress}", // Placeholder - will be updated after deployment`,
            `address: "${contractAddress}",`
        );

        // Write updated contracts file
        fs.writeFileSync(contractsFile, contractsContent);

        console.log('✅ SwapRouter address updated successfully!');
        console.log(`📝 Contract Address: ${contractAddress}`);
        console.log(`📄 Updated file: ${contractsFile}`);

    } catch (error) {
        console.error('❌ Error updating SwapRouter address:', error.message);
        process.exit(1);
    }
}

updateSwapRouterAddress(); 