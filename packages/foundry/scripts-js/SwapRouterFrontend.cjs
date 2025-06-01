#!/usr/bin/env node

/**
 * SwapRouterFrontend.js - Pyth-Integrated Swap Router Frontend (JavaScript)
 * 
 * This script provides a command-line interface for executing swaps on the SwapRouter contract
 * with real-time price data from Pyth Network.
 * 
 * Features:
 * 1. Command-line interface with specific flags
 * 2. Pyth Hermes API integration for price updates
 * 3. Smart contract interaction with SwapRouter
 * 4. Pool configuration management
 * 5. Wallet address management for funding
 * 
 * Usage:
 *     node scripts-js/SwapRouterFrontend.js --swap <amount> <direction>
 *     node scripts-js/SwapRouterFrontend.js --updatepool <currency0> <currency1> <fee> <tickSpacing> <hooks> <PoolId>
 *     node scripts-js/SwapRouterFrontend.js --getpool
 *     node scripts-js/SwapRouterFrontend.js --wallet <address>
 * 
 * Or via yarn:
 *     yarn swap-router --swap 0.00002 false
 *     yarn swap-router --getpool
 */

const { ethers } = require('ethers');
const axios = require('axios');
const dotenv = require('dotenv');
const chalk = require('chalk');
const path = require('path');

// Load environment variables from project root
dotenv.config({ path: path.join(__dirname, '../.env') });

class SwapRouterFrontend {
    // Constants
    static ARBITRUM_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc";
    static PYTH_HERMES_API = "https://hermes.pyth.network";
    static ETH_USD_PRICE_ID = "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace";
    
    // Contract configuration - Deployment details
    static SWAP_ROUTER_ADDRESS = "0x5Edcd78A069604a649450c17186FDdBBA139fBfd";
    
    // Contract ABI
    static SWAP_ROUTER_ABI = [
        {
            "inputs": [
                {"internalType": "address", "name": "_poolSwapTest", "type": "address"},
                {
                    "components": [
                        {"internalType": "Currency", "name": "currency0", "type": "address"},
                        {"internalType": "Currency", "name": "currency1", "type": "address"},
                        {"internalType": "uint24", "name": "fee", "type": "uint24"},
                        {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                        {"internalType": "contract IHooks", "name": "hooks", "type": "address"}
                    ],
                    "internalType": "struct PoolKey",
                    "name": "_poolKey",
                    "type": "tuple"
                }
            ],
            "stateMutability": "nonpayable",
            "type": "constructor"
        },
        {"inputs": [], "name": "InvalidSwapAmount", "type": "error"},
        {"inputs": [], "name": "PoolSwapTestNotSet", "type": "error"},
        {
            "anonymous": false,
            "inputs": [
                {"indexed": false, "internalType": "Currency", "name": "currency0", "type": "address"},
                {"indexed": false, "internalType": "Currency", "name": "currency1", "type": "address"},
                {"indexed": false, "internalType": "uint24", "name": "fee", "type": "uint24"},
                {"indexed": false, "internalType": "int24", "name": "tickSpacing", "type": "int24"},
                {"internalType": "contract IHooks", "name": "hooks", "type": "address"}
            ],
            "name": "PoolConfigurationUpdated",
            "type": "event"
        },
        {
            "anonymous": false,
            "inputs": [
                {"indexed": true, "internalType": "address", "name": "sender", "type": "address"},
                {"indexed": false, "internalType": "int256", "name": "amountSpecified", "type": "int256"},
                {"indexed": false, "internalType": "bool", "name": "zeroForOne", "type": "bool"},
                {"indexed": false, "internalType": "BalanceDelta", "name": "delta", "type": "int256"}
            ],
            "name": "SwapExecuted",
            "type": "event"
        },
        {
            "inputs": [],
            "name": "defaultTestSettings",
            "outputs": [
                {"internalType": "bool", "name": "takeClaims", "type": "bool"},
                {"internalType": "bool", "name": "settleUsingBurn", "type": "bool"}
            ],
            "stateMutability": "view",
            "type": "function"
        },
        {
            "inputs": [],
            "name": "getPoolConfiguration",
            "outputs": [
                {
                    "components": [
                        {"internalType": "Currency", "name": "currency0", "type": "address"},
                        {"internalType": "Currency", "name": "currency1", "type": "address"},
                        {"internalType": "uint24", "name": "fee", "type": "uint24"},
                        {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                        {"internalType": "contract IHooks", "name": "hooks", "type": "address"}
                    ],
                    "internalType": "struct PoolKey",
                    "name": "",
                    "type": "tuple"
                }
            ],
            "stateMutability": "view",
            "type": "function"
        },
        {
            "inputs": [],
            "name": "getTestSettings",
            "outputs": [
                {
                    "components": [
                        {"internalType": "bool", "name": "takeClaims", "type": "bool"},
                        {"internalType": "bool", "name": "settleUsingBurn", "type": "bool"}
                    ],
                    "internalType": "struct IPoolSwapTest.TestSettings",
                    "name": "",
                    "type": "tuple"
                }
            ],
            "stateMutability": "view",
            "type": "function"
        },
        {
            "inputs": [],
            "name": "poolKey",
            "outputs": [
                {"internalType": "Currency", "name": "currency0", "type": "address"},
                {"internalType": "Currency", "name": "currency1", "type": "address"},
                {"internalType": "uint24", "name": "fee", "type": "uint24"},
                {"internalType": "int24", "name": "tickSpacing", "type": "int24"},
                {"internalType": "contract IHooks", "name": "hooks", "type": "address"}
            ],
            "stateMutability": "view",
            "type": "function"
        },
        {
            "inputs": [],
            "name": "poolSwapTest",
            "outputs": [
                {"internalType": "contract IPoolSwapTest", "name": "", "type": "address"}
            ],
            "stateMutability": "view",
            "type": "function"
        },
        {
            "inputs": [
                {"internalType": "int256", "name": "amountToSwap", "type": "int256"},
                {"internalType": "bool", "name": "zeroForOne", "type": "bool"},
                {"internalType": "bytes", "name": "updateData", "type": "bytes"}
            ],
            "name": "swap",
            "outputs": [
                {"internalType": "BalanceDelta", "name": "delta", "type": "int256"}
            ],
            "stateMutability": "payable",
            "type": "function"
        },
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
                    "name": "newPoolKey",
                    "type": "tuple"
                }
            ],
            "name": "updatePoolConfiguration",
            "outputs": [],
            "stateMutability": "nonpayable",
            "type": "function"
        },
        {
            "inputs": [
                {"internalType": "bool", "name": "takeClaims", "type": "bool"},
                {"internalType": "bool", "name": "settleUsingBurn", "type": "bool"}
            ],
            "name": "updateTestSettings",
            "outputs": [],
            "stateMutability": "nonpayable",
            "type": "function"
        }
    ];

    constructor() {
        this.provider = null;
        this.wallet = null;
        this.contract = null;
        this.fundingWalletAddress = null;  // For --wallet flag functionality

        this.setupProvider();
        this.setupWallet();
        this.setupContract();
        this.printHeader();
    }

    printColored(message, color = 'white') {
        const chalkColor = chalk[color] || chalk.white;
        console.log(chalkColor(message));
    }

    printHeader() {
        this.printColored("\n" + "=".repeat(70), 'cyan');
        this.printColored("🔄 SwapRouter Frontend - Pyth-Integrated DEX Interface", 'cyan');
        this.printColored("=".repeat(70), 'cyan');
        this.printColored(`📍 Contract: ${SwapRouterFrontend.SWAP_ROUTER_ADDRESS}`, 'yellow');
        this.printColored(`🌐 Network: Arbitrum Sepolia`, 'green');
        this.printColored(`🐍 Pyth Price Feed: ETH/USD`, 'blue');
        this.printColored("=".repeat(70) + "\n", 'cyan');
    }

    setupProvider() {
        try {
            const rpcUrl = process.env.ARBITRUM_SEPOLIA_RPC_URL || SwapRouterFrontend.ARBITRUM_SEPOLIA_RPC;
            this.provider = new ethers.providers.JsonRpcProvider(rpcUrl);
            
            this.printColored(`✅ Connected to Arbitrum Sepolia: ${rpcUrl}`, 'green');
        } catch (error) {
            this.printColored(`❌ Failed to setup Web3: ${error}`, 'red');
            process.exit(1);
        }
    }

    setupWallet() {
        try {
            // Try new wallet format first
            const deploymentWallet = process.env.DEPLOYMENT_WALLET;
            const deploymentKey = process.env.DEPLOYMENT_KEY;
            
            if (deploymentWallet && deploymentKey) {
                // Clean the private key
                const privateKey = deploymentKey.startsWith('0x') ? deploymentKey : `0x${deploymentKey}`;
                this.wallet = new ethers.Wallet(privateKey, this.provider);
                
                // Validate address match
                if (this.wallet.address.toLowerCase() !== deploymentWallet.toLowerCase()) {
                    throw new Error("DEPLOYMENT_KEY does not match DEPLOYMENT_WALLET");
                }
                
                this.printColored(`✅ Wallet loaded: ${this.wallet.address}`, 'green');
            } else {
                // Fallback to legacy format
                const privateKey = process.env.PRIVATE_KEY;
                if (!privateKey) {
                    throw new Error("No wallet credentials found");
                }
                
                const cleanKey = privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`;
                this.wallet = new ethers.Wallet(cleanKey, this.provider);
                this.printColored(`✅ Wallet loaded (legacy): ${this.wallet.address}`, 'green');
                this.printColored("⚠️  Consider migrating to DEPLOYMENT_WALLET/DEPLOYMENT_KEY", 'yellow');
            }

            // Check balance
            this.checkBalance();
        } catch (error) {
            this.printColored(`❌ Failed to setup account: ${error}`, 'red');
            this.printColored("💡 Set DEPLOYMENT_WALLET + DEPLOYMENT_KEY or PRIVATE_KEY", 'cyan');
            process.exit(1);
        }
    }

    async checkBalance() {
        if (!this.wallet) return;

        try {
            const balance = await this.provider.getBalance(this.wallet.address);
            const balanceEth = ethers.utils.formatEther(balance);
            this.printColored(`💰 Balance: ${parseFloat(balanceEth).toFixed(6)} ETH`, 'cyan');
        } catch (error) {
            this.printColored(`⚠️  Could not fetch balance: ${error}`, 'yellow');
        }
    }

    setupContract() {
        try {
            this.contract = new ethers.Contract(
                SwapRouterFrontend.SWAP_ROUTER_ADDRESS,
                SwapRouterFrontend.SWAP_ROUTER_ABI,
                this.wallet || this.provider
            );
            this.printColored(`✅ SwapRouter contract loaded`, 'green');
        } catch (error) {
            this.printColored(`❌ Failed to setup contract: ${error}`, 'red');
            process.exit(1);
        }
    }

    /**
     * Generate Pyth update data from Hermes API.
     * Fetches the latest ETH/USD price data required for reading data on-chain.
     * 
     * @returns {Promise<string>} Encoded update data for the smart contract
     */
    async generate() {
        this.printColored("\n📡 Fetching latest price data from Pyth Hermes...", 'magenta');
        
        try {
            const url = `${SwapRouterFrontend.PYTH_HERMES_API}/v2/updates/price/latest`;
            const params = {
                'ids[]': SwapRouterFrontend.ETH_USD_PRICE_ID,
                'encoding': 'hex'
            };
            
            this.printColored(`🔗 Requesting: ${url}`, 'cyan');
            
            const response = await axios.get(url, { params, timeout: 30000 });
            const data = response.data;
            
            if (!data.binary || !data.parsed) {
                throw new Error("Invalid response format from Hermes API");
            }
            
            // Extract update data
            const updateDataHex = data.binary.data[0];
            
            // Parse price information for display
            const parsedData = data.parsed[0];
            const priceInfo = parsedData.price;
            
            const priceRaw = parseInt(priceInfo.price);
            const expo = parseInt(priceInfo.expo);
            const confRaw = parseInt(priceInfo.conf);
            
            const actualPrice = priceRaw * Math.pow(10, expo);
            const confidenceInterval = confRaw * Math.pow(10, expo);
            const confidencePct = actualPrice !== 0 ? (confidenceInterval / actualPrice) * 100 : 0;
            
            this.printColored("✅ Successfully fetched price data from Hermes", 'green');
            this.printColored(`💰 ETH/USD Price: $${actualPrice.toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})} (±${confidencePct.toFixed(3)}%)`, 'green');
            this.printColored(`📅 Publish Time: ${parsedData.price.publish_time}`, 'cyan');
            
            // Add 0x prefix to hex data
            const updateDataBytes = `0x${updateDataHex}`;
            this.printColored(`📦 Update Data Size: ${updateDataBytes.length / 2 - 1} bytes`, 'cyan');
            
            return updateDataBytes;
        } catch (error) {
            if (error.isAxiosError) {
                this.printColored(`❌ Network error fetching from Hermes: ${error.message}`, 'red');
            } else {
                this.printColored(`❌ Error in generate(): ${error}`, 'red');
            }
            throw error;
        }
    }

    /**
     * --swap flag functionality
     * Read from the cl the size and direction of a swap
     * Call the Hermes system and generate the update data required for reading data on-chain
     * Make a call to the function swap() of the smart contract SwapRouter.sol
     */
    async executeSwap(amount, direction) {
        this.printColored(`\n🔄 [--swap] Executing swap with amount: ${amount}, direction: ${direction}`, 'magenta');
        
        if (!this.contract || !this.wallet) {
            this.printColored("❌ Contract or wallet not available", 'red');
            return;
        }

        // Use funding wallet if specified, otherwise use default wallet
        const activeWallet = this.fundingWalletAddress ? 
            new ethers.Wallet(this.wallet.privateKey, this.provider) : this.wallet;
        
        try {
            // 1. Call the Hermes system and generate the update data required for reading data on-chain
            const updateData = await this.generate();
            
            // 2. Convert amount to Wei (assuming 18 decimals)
            // Fix scientific notation issue by using toFixed() to get proper decimal string
            const amountString = amount.toFixed(18).replace(/\.?0+$/, ''); // Remove trailing zeros
            const amountWei = ethers.utils.parseEther(amountString);
            
            this.printColored(`\n📊 Swap Parameters:`, 'cyan');
            this.printColored(`   Amount: ${amount} (${amountWei.toString()} wei)`, 'white');
            this.printColored(`   Amount String: ${amountString}`, 'gray');
            this.printColored(`   Direction (zeroForOne): ${direction}`, 'white');
            this.printColored(`   Update Data: ${(updateData.length - 2) / 2} bytes`, 'white');
            this.printColored(`   Funding Wallet: ${this.fundingWalletAddress || activeWallet.address}`, 'white');
            
            // 3. Make a call to the function swap() of the smart contract SwapRouter.sol with deployment details
            this.printColored("\n⛽ Estimating gas for swap...", 'cyan');
            
            const gasEstimate = await this.contract.estimateGas.swap(
                amountWei,
                direction,
                updateData,
                { from: activeWallet.address }
            );
            
            // Add 20% buffer
            const gasLimit = gasEstimate.mul(120).div(100);
            this.printColored(`⛽ Gas estimate: ${gasEstimate.toLocaleString()} (limit: ${gasLimit.toLocaleString()})`, 'cyan');
            
            // Send transaction
            this.printColored("✍️  Signing and sending swap transaction...", 'cyan');
            
            const contractWithSigner = this.contract.connect(activeWallet);
            const tx = await contractWithSigner.swap(
                amountWei,
                direction,
                updateData,
                { gasLimit: gasLimit }
            );
            
            this.printColored(`✅ Swap transaction sent: ${tx.hash}`, 'green');
            this.printColored("⏳ Waiting for confirmation...", 'cyan');
            
            // Wait for confirmation
            const receipt = await tx.wait();
            
            if (receipt && receipt.status === 1) {
                this.printColored("✅ Swap transaction confirmed!", 'green');
                this.printColored(`📊 Block: ${receipt.blockNumber}`, 'cyan');
                this.printColored(`⛽ Gas used: ${receipt.gasUsed.toLocaleString()}`, 'cyan');
                this.printColored(`🔗 Arbiscan: https://sepolia.arbiscan.io/tx/${tx.hash}`, 'blue');
                
                // Parse logs for SwapExecuted event
                this.parseSwapEvents(receipt);
            } else {
                this.printColored("❌ Swap transaction failed!", 'red');
            }
        } catch (error) {
            this.printColored(`❌ Error in executeSwap(): ${error}`, 'red');
        }
    }

    /**
     * --updatepool flag functionality
     * Read from the cl the fields 'currency0', 'currency1', 'fee', 'tickSpacing', 'hooks', 'PoolId'
     * Package these fields as a pool key
     * Make a call to the function updatePoolConfiguration() of the smart contract SwapRouter.sol
     */
    async updatePool(currency0, currency1, fee, tickSpacing, hooks, poolId) {
        this.printColored(`\n🔧 [--updatepool] Updating pool configuration`, 'magenta');
        
        if (!this.contract || !this.wallet) {
            this.printColored("❌ Contract or wallet not available", 'red');
            return;
        }

        // Use funding wallet if specified, otherwise use default wallet
        const activeWallet = this.fundingWalletAddress ? 
            new ethers.Wallet(this.wallet.privateKey, this.provider) : this.wallet;
        
        try {
            // Package the standard PoolKey fields (as supported by the contract)
            const poolKey = {
                currency0,
                currency1,
                fee,
                tickSpacing,
                hooks
            };
            
            this.printColored(`📊 New Pool Configuration:`, 'cyan');
            this.printColored(`   Currency 0: ${poolKey.currency0}`, 'white');
            this.printColored(`   Currency 1: ${poolKey.currency1}`, 'white');
            this.printColored(`   Fee Tier: ${poolKey.fee}`, 'white');
            this.printColored(`   Tick Spacing: ${poolKey.tickSpacing}`, 'white');
            this.printColored(`   Hooks: ${poolKey.hooks}`, 'white');
            this.printColored(`   Pool ID: ${poolId} (client-side identifier only)`, 'yellow');
            this.printColored(`   Funding Wallet: ${this.fundingWalletAddress || activeWallet.address}`, 'white');
            
            // Estimate gas
            this.printColored("\n⛽ Estimating gas for updatePoolConfiguration...", 'cyan');
            
            const gasEstimate = await this.contract.estimateGas.updatePoolConfiguration(
                poolKey,
                { from: activeWallet.address }
            );
            
            // Add 20% buffer
            const gasLimit = gasEstimate.mul(120).div(100);
            this.printColored(`⛽ Gas estimate: ${gasEstimate.toLocaleString()} (limit: ${gasLimit.toLocaleString()})`, 'cyan');
            
            // Send transaction
            this.printColored("✍️  Signing and sending updatePoolConfiguration transaction...", 'cyan');
            
            const contractWithSigner = this.contract.connect(activeWallet);
            const tx = await contractWithSigner.updatePoolConfiguration(
                poolKey,
                { gasLimit: gasLimit }
            );
            
            this.printColored(`✅ UpdatePoolConfiguration transaction sent: ${tx.hash}`, 'green');
            this.printColored("⏳ Waiting for confirmation...", 'cyan');
            
            // Wait for confirmation
            const receipt = await tx.wait();
            
            if (receipt && receipt.status === 1) {
                this.printColored("✅ UpdatePoolConfiguration transaction confirmed!", 'green');
                this.printColored(`📊 Block: ${receipt.blockNumber}`, 'cyan');
                this.printColored(`⛽ Gas used: ${receipt.gasUsed.toLocaleString()}`, 'cyan');
                this.printColored(`🔗 Arbiscan: https://sepolia.arbiscan.io/tx/${tx.hash}`, 'blue');
                this.printColored(`ℹ️  Note: PoolId '${poolId}' is not stored on-chain (client-side only)`, 'yellow');
            } else {
                this.printColored("❌ UpdatePoolConfiguration transaction failed!", 'red');
            }
        } catch (error) {
            this.printColored(`❌ Error in updatePool(): ${error}`, 'red');
        }
    }

    /**
     * --getpool flag functionality
     * Call the function getPoolConfiguration() of the smart contract SwapRouter.sol with deployment details
     * Get the pool key returned, separate to fields and print to the cl
     */
    async getPool() {
        this.printColored(`\n📋 [--getpool] Getting pool configuration`, 'magenta');
        
        if (!this.contract) {
            this.printColored("❌ Contract not available", 'red');
            return;
        }
        
        try {
            this.printColored("🔍 Calling getPoolConfiguration() on SwapRouter contract...", 'cyan');
            
            const poolConfig = await this.contract.getPoolConfiguration();
            const [currency0, currency1, fee, tickSpacing, hooks] = poolConfig;
            
            this.printColored("✅ Successfully retrieved pool configuration!", 'green');
            this.printColored("\n📊 Current Pool Configuration (separated fields):", 'cyan');
            this.printColored(`   Currency0: ${currency0}`, 'white');
            this.printColored(`   Currency1: ${currency1}`, 'white');
            this.printColored(`   Fee: ${fee}`, 'white');
            this.printColored(`   TickSpacing: ${tickSpacing}`, 'white');
            this.printColored(`   Hooks: ${hooks}`, 'white');
            this.printColored(`   ⚠️  Note: Contract does not store PoolId (client-side only)`, 'yellow');
            
            // Print in structured format for easy copying (contract fields only)
            const poolKey = {
                currency0,
                currency1,
                fee: fee.toString(),
                tickSpacing: tickSpacing.toString(),
                hooks
            };
            
            this.printColored("\n📋 Pool Key (JSON format - contract fields only):", 'yellow');
            console.log(JSON.stringify(poolKey, null, 2));
            
        } catch (error) {
            this.printColored(`❌ Error in getPool(): ${error}`, 'red');
        }
    }

    /**
     * --wallet flag functionality
     * Read from the cl the address for the wallet to be used to fund all calls requiring funding
     * Save the address internally and use it for all --swap and --updatepool
     */
    setFundingWallet(address) {
        this.printColored(`\n💼 [--wallet] Setting funding wallet address`, 'magenta');
        
        try {
            // Validate the address format
            if (!ethers.utils.isAddress(address)) {
                throw new Error("Invalid Ethereum address format");
            }
            
            this.fundingWalletAddress = address;
            this.printColored(`✅ Funding wallet address set: ${address}`, 'green');
            this.printColored(`ℹ️  This address will be used for all --swap and --updatepool funding`, 'cyan');
            
            // Check if we have access to this wallet's private key
            if (this.wallet && this.wallet.address.toLowerCase() === address.toLowerCase()) {
                this.printColored(`✅ Private key available for this address`, 'green');
            } else {
                this.printColored(`⚠️  Private key not available for this address`, 'yellow');
                this.printColored(`   Make sure to set DEPLOYMENT_KEY/PRIVATE_KEY for this wallet`, 'yellow');
            }
            
        } catch (error) {
            this.printColored(`❌ Error in setFundingWallet(): ${error}`, 'red');
        }
    }

    parseSwapEvents(receipt) {
        if (!this.contract) return;

        try {
            // Parse logs for SwapExecuted events
            const swapExecutedInterface = new ethers.utils.Interface(SwapRouterFrontend.SWAP_ROUTER_ABI);
            
            for (const log of receipt.logs) {
                try {
                    const parsed = swapExecutedInterface.parseLog(log);
                    
                    if (parsed && parsed.name === 'SwapExecuted') {
                        this.printColored("\n📈 Swap Event Details:", 'green');
                        this.printColored(`   Sender: ${parsed.args.sender}`, 'white');
                        this.printColored(`   Amount Specified: ${parsed.args.amountSpecified}`, 'white');
                        this.printColored(`   Zero For One: ${parsed.args.zeroForOne}`, 'white');
                        this.printColored(`   Delta: ${parsed.args.delta}`, 'white');
                    }
                } catch (parseError) {
                    // Not a SwapExecuted event, continue
                }
            }
        } catch (error) {
            this.printColored(`⚠️  Could not parse swap events: ${error}`, 'yellow');
        }
    }
}

function showUsage() {
    console.log(chalk.cyan('SwapRouter Frontend with Pyth Integration (JavaScript)'));
    console.log(chalk.white(''));
    console.log(chalk.white('Usage:'));
    console.log(chalk.green('  node scripts-js/SwapRouterFrontend.js --swap <amount> <direction>'));
    console.log(chalk.green('  node scripts-js/SwapRouterFrontend.js --updatepool <currency0> <currency1> <fee> <tickSpacing> <hooks> <PoolId>'));
    console.log(chalk.green('  node scripts-js/SwapRouterFrontend.js --getpool'));
    console.log(chalk.green('  node scripts-js/SwapRouterFrontend.js --wallet <address>'));
    console.log(chalk.white(''));
    console.log(chalk.white('Or via yarn:'));
    console.log(chalk.green('  yarn swap-router --swap 0.00002 false'));
    console.log(chalk.green('  yarn swap-router --getpool'));
    console.log(chalk.white(''));
    console.log(chalk.white('Flags:'));
    console.log(chalk.white('  --swap         Execute a swap on the SwapRouter contract'));
    console.log(chalk.white('  --updatepool   Update the pool configuration with PoolId'));
    console.log(chalk.white('  --getpool      Get and display current pool configuration'));
    console.log(chalk.white('  --wallet       Set funding wallet address for transactions'));
    console.log(chalk.white(''));
    console.log(chalk.white('Examples:'));
    console.log(chalk.yellow('  node scripts-js/SwapRouterFrontend.js --swap 0.02 true'));
    console.log(chalk.yellow('  yarn swap-router --swap 0.00002 false'));
    console.log(chalk.yellow('  yarn swap-router --updatepool 0x... 0x... 3000 60 0x... pool123'));
    console.log(chalk.yellow('  yarn swap-router --getpool'));
    console.log(chalk.yellow('  yarn swap-router --wallet 0x742d35Cc6644C44532767eaFA8CA3b8d8ad67A95'));
}

async function main() {
    try {
        const args = process.argv.slice(2);
        
        if (args.length === 0) {
            showUsage();
            process.exit(1);
        }
        
        const flag = args[0];
        
        // Initialize frontend
        const frontend = new SwapRouterFrontend();
        
        switch (flag) {
            case '--swap':
                if (args.length < 3) {
                    console.log(chalk.red('❌ --swap requires <amount> <direction> arguments'));
                    console.log(chalk.white('Example: yarn swap-router --swap 0.02 true'));
                    process.exit(1);
                }
                
                const amount = parseFloat(args[1]);
                const directionStr = args[2].toLowerCase();
                const direction = ['true', '1'].includes(directionStr);
                
                if (isNaN(amount)) {
                    console.log(chalk.red('❌ Invalid amount. Please provide a valid number.'));
                    process.exit(1);
                }
                
                if (!['true', 'false', '1', '0'].includes(directionStr)) {
                    console.log(chalk.red('❌ Invalid direction. Use true/false or 1/0.'));
                    process.exit(1);
                }
                
                await frontend.executeSwap(amount, direction);
                break;
                
            case '--updatepool':
                if (args.length < 7) {
                    console.log(chalk.red('❌ --updatepool requires <currency0> <currency1> <fee> <tickSpacing> <hooks> <PoolId> arguments'));
                    console.log(chalk.white('Example: yarn swap-router --updatepool 0x... 0x... 3000 60 0x... pool123'));
                    process.exit(1);
                }
                
                const currency0 = args[1];
                const currency1 = args[2];
                const fee = parseInt(args[3]);
                const tickSpacing = parseInt(args[4]);
                const hooks = args[5];
                const poolId = args[6];
                
                if (isNaN(fee) || isNaN(tickSpacing)) {
                    console.log(chalk.red('❌ Invalid fee or tickSpacing. Please provide valid numbers.'));
                    process.exit(1);
                }
                
                await frontend.updatePool(currency0, currency1, fee, tickSpacing, hooks, poolId);
                break;
                
            case '--getpool':
                await frontend.getPool();
                break;
                
            case '--wallet':
                if (args.length < 2) {
                    console.log(chalk.red('❌ --wallet requires <address> argument'));
                    console.log(chalk.white('Example: yarn swap-router --wallet 0x742d35Cc6644C44532767eaFA8CA3b8d8ad67A95'));
                    process.exit(1);
                }
                
                const walletAddress = args[1];
                frontend.setFundingWallet(walletAddress);
                break;
                
            default:
                console.log(chalk.red(`❌ Unknown flag: ${flag}`));
                showUsage();
                process.exit(1);
        }
        
        console.log(chalk.green.bold("\n🎉 Operation completed successfully!"));
        
    } catch (error) {
        if (error instanceof Error) {
            console.log(chalk.red(`\n❌ Fatal error: ${error.message}`));
        } else {
            console.log(chalk.red(`\n❌ Fatal error: ${error}`));
        }
        process.exit(1);
    }
}

// Handle interrupts gracefully
process.on('SIGINT', () => {
    console.log(chalk.yellow('\n⚠️  Operation cancelled by user'));
    process.exit(0);
});

if (require.main === module) {
    main();
}

module.exports = { SwapRouterFrontend }; 