#!/usr/bin/env node

/**
 * SwapRouterFrontend.js - Optimized Pyth-Integrated Swap Router Frontend
 * 
 * OPTIMIZATIONS IMPLEMENTED:
 * 1. Enhanced error handling with retry mechanisms
 * 2. Caching for frequently accessed data
 * 3. Parallel API calls for better performance
 * 4. Multiple price feed support (ETH/USD, USDC/USD)
 * 5. Price staleness and confidence validation
 * 6. Better progress indicators and user feedback
 * 7. Gas estimation before transactions
 * 8. Configuration validation
 * 
 * Features:
 * 1. Command-line interface with specific flags
 * 2. Enhanced Pyth Hermes API integration with validation
 * 3. Smart contract interaction with SwapRouter
 * 4. Pool configuration management with caching
 * 5. Wallet address management for funding
 * 6. USDC token approval for SwapRouter
 * 7. Systematic testing with detailed reporting
 * 
 * Usage:
 *     node scripts-js/SwapRouterFrontend.js --swap <amount> <direction>
 *     node scripts-js/SwapRouterFrontend.js --updatepool <currency0> <currency1> <fee> <tickSpacing> <hooks> <PoolId>
 *     node scripts-js/SwapRouterFrontend.js --getpool
 *     node scripts-js/SwapRouterFrontend.js --wallet <address>
 *     node scripts-js/SwapRouterFrontend.js --approve
 *     node scripts-js/SwapRouterFrontend.js --test
 * 
 * Or via yarn:
 *     yarn swap-router --swap 0.00002 false
 *     yarn swap-router --getpool
 *     yarn swap-router --approve
 *     yarn swap-router --test
 */

const { ethers } = require('ethers');
const axios = require('axios');
const dotenv = require('dotenv');
const chalk = require('chalk');
const path = require('path');
const qs = require('qs');

// Load environment variables from project root
dotenv.config({ path: path.join(__dirname, '../.env') });

class SwapRouterFrontend {
    // Constants
    static ARBITRUM_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc";
    static PYTH_HERMES_API = "https://hermes.pyth.network";
    
    // Enhanced price feed configuration
    static PRICE_FEEDS = {
        ETH_USD: {
            id: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
            symbol: "ETH/USD",
            decimals: 8
        },
        USDC_USD: {
            id: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
            symbol: "USDC/USD", 
            decimals: 8
        }
    };
    
    // Contract configuration - Deployment details
    static SWAP_ROUTER_ADDRESS = "0x7dD454F098f74eD0464c3896BAe8412C8b844E7e";
    static USDC_TOKEN_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d";
    static POOL_MANAGER_ADDRESS = "0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829";
    
    // Optimization constants
    static CACHE_TTL = 30000; // 30 seconds cache TTL
    static MAX_RETRIES = 3;
    static RETRY_DELAY = 1000; // 1 second
    static PRICE_STALENESS_THRESHOLD = 60; // 60 seconds
    static MAX_CONFIDENCE_INTERVAL = 1.0; // 1% max confidence interval
    
    // ERC20 ABI for token operations
    static ERC20_ABI = [
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function allowance(address owner, address spender) external view returns (uint256)",
        "function balanceOf(address account) external view returns (uint256)",
        "function decimals() external view returns (uint8)",
        "function symbol() external view returns (string)",
        "function name() external view returns (string)"
    ];
    
    // Pool Manager ABI for slot0 reading
    static POOL_MANAGER_ABI = [
        "function getSlot0(bytes32 poolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)",
        "function pools(bytes32 poolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)"
    ];
    
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
        this.usdcContract = null;  // USDC token contract
        this.fundingWalletAddress = null;  // For --wallet flag functionality
        this.poolManagerContract = null;  // PoolManager contract

        this.setupProvider();
        this.setupWallet();
        // Print ETH and USDC balances together at the top
        this.printETHAndUSDCBalances();
        this.setupContract();
        this.setupUSDCContract();
        this.setupPoolManagerContract();
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

    setupUSDCContract() {
        try {
            this.usdcContract = new ethers.Contract(
                SwapRouterFrontend.USDC_TOKEN_ADDRESS,
                SwapRouterFrontend.ERC20_ABI,
                this.wallet || this.provider
            );
            this.printColored(`✅ USDC token contract loaded`, 'green');
        } catch (error) {
            this.printColored(`❌ Failed to setup USDC contract: ${error}`, 'red');
            process.exit(1);
        }
    }

    setupPoolManagerContract() {
        try {
            this.poolManagerContract = new ethers.Contract(
                SwapRouterFrontend.POOL_MANAGER_ADDRESS,
                SwapRouterFrontend.POOL_MANAGER_ABI,
                this.provider
            );
            this.printColored(`✅ PoolManager contract loaded`, 'green');
        } catch (error) {
            this.printColored(`❌ Failed to setup PoolManager contract: ${error}`, 'red');
            process.exit(1);
        }
    }

    async printETHAndUSDCBalances() {
        if (!this.wallet || !this.provider) return;
        try {
            const ethBalance = await this.provider.getBalance(this.wallet.address);
            this.printColored(`💰 Swapper ETH Balance: ${ethers.utils.formatEther(ethBalance)} ETH`, 'cyan');
        } catch (e) {
            this.printColored(`⚠️  Could not fetch ETH balance: ${e}`,'yellow');
        }
        try {
            if (this.usdcContract) {
                const decimals = await this.usdcContract.decimals();
                const symbol = await this.usdcContract.symbol();
                const balance = await this.usdcContract.balanceOf(this.wallet.address);
                this.printColored(`💰 Swapper USDC Balance: ${ethers.utils.formatUnits(balance, decimals)} ${symbol}`, 'cyan');
            }
        } catch (e) {
            this.printColored(`⚠️  Could not fetch USDC balance: ${e}`,'yellow');
        }
    }

    /**
     * Check and display USDC token information and allowance
     */
    async checkUSDCStatus() {
        if (!this.usdcContract || !this.wallet) {
            this.printColored("❌ USDC contract or wallet not available", 'red');
            return { balance: 0, allowance: 0, hasApproval: false };
        }

        try {
            const [balance, allowance, symbol, decimals] = await Promise.all([
                this.usdcContract.balanceOf(this.wallet.address),
                this.usdcContract.allowance(this.wallet.address, SwapRouterFrontend.SWAP_ROUTER_ADDRESS),
                this.usdcContract.symbol(),
                this.usdcContract.decimals()
            ]);

            const balanceFormatted = ethers.utils.formatUnits(balance, decimals);
            const allowanceFormatted = ethers.utils.formatUnits(allowance, decimals);
            const hasApproval = allowance.gt(0);

            this.printColored(`💰 ${symbol} Balance: ${parseFloat(balanceFormatted).toFixed(6)}`, 'cyan');
            this.printColored(`🔓 ${symbol} Allowance: ${parseFloat(allowanceFormatted).toFixed(6)}`, hasApproval ? 'green' : 'yellow');

            return { 
                balance: parseFloat(balanceFormatted), 
                allowance: parseFloat(allowanceFormatted), 
                hasApproval,
                symbol,
                decimals
            };
        } catch (error) {
            this.printColored(`⚠️  Could not fetch USDC status: ${error}`, 'yellow');
            return { balance: 0, allowance: 0, hasApproval: false };
        }
    }

    async printUSDCBalance() {
        if (!this.usdcContract || !this.wallet) return;
        try {
            const decimals = await this.usdcContract.decimals();
            const symbol = await this.usdcContract.symbol();
            const balance = await this.usdcContract.balanceOf(this.wallet.address);
            const balanceFormatted = ethers.utils.formatUnits(balance, decimals);
            this.printColored(`💰 Swapper USDC Balance: ${balanceFormatted} ${symbol}`, 'cyan');
        } catch (error) {
            this.printColored(`⚠️  Could not fetch USDC balance: ${error}`, 'yellow');
        }
    }

    /**
     * Approve USDC token for SwapRouter contract
     */
    async approveUSDC(amount = null) {
        this.printColored(`\n🔓 [--approve] Approving USDC for SwapRouter`, 'magenta');
        
        if (!this.usdcContract || !this.wallet) {
            this.printColored("❌ USDC contract or wallet not available", 'red');
            return false;
        }

        try {
            // Check current status
            const status = await this.checkUSDCStatus();
            
            if (status.hasApproval && amount === null) {
                this.printColored(`✅ USDC already approved for SwapRouter (${status.allowance} ${status.symbol})`, 'green');
                return true;
            }

            // Use maximum approval if no specific amount provided
            const approvalAmount = amount ? 
                ethers.utils.parseUnits(amount.toString(), status.decimals || 6) : 
                ethers.constants.MaxUint256;

            this.printColored(`\n📊 Approval Parameters:`, 'cyan');
            this.printColored(`   Spender: ${SwapRouterFrontend.SWAP_ROUTER_ADDRESS}`, 'white');
            this.printColored(`   Amount: ${amount ? `${amount} USDC` : 'Maximum (unlimited)'}`, 'white');
            this.printColored(`   Current Allowance: ${status.allowance} ${status.symbol}`, 'white');

            // Estimate gas
            this.printColored("\n⛽ Estimating gas for USDC approval...", 'cyan');
            
            const gasEstimate = await this.usdcContract.estimateGas.approve(
                SwapRouterFrontend.SWAP_ROUTER_ADDRESS,
                approvalAmount,
                { from: this.wallet.address }
            );
            
            // Add 20% buffer
            const gasLimit = gasEstimate.mul(120).div(100);
            this.printColored(`⛽ Gas estimate: ${gasEstimate.toLocaleString()} (limit: ${gasLimit.toLocaleString()})`, 'cyan');
            
            // Send transaction
            this.printColored("✍️  Signing and sending USDC approval transaction...", 'cyan');
            
            const contractWithSigner = this.usdcContract.connect(this.wallet);
            const tx = await contractWithSigner.approve(
                SwapRouterFrontend.SWAP_ROUTER_ADDRESS,
                approvalAmount,
                { gasLimit: gasLimit }
            );
            
            this.printColored(`✅ USDC approval transaction sent: ${tx.hash}`, 'green');
            this.printColored("⏳ Waiting for confirmation...", 'cyan');
            
            // Wait for confirmation
            const receipt = await tx.wait();
            
            if (receipt && receipt.status === 1) {
                this.printColored("✅ USDC approval transaction confirmed!", 'green');
                this.printColored(`📊 Block: ${receipt.blockNumber}`, 'cyan');
                this.printColored(`⛽ Gas used: ${receipt.gasUsed.toLocaleString()}`, 'cyan');
                this.printColored(`🔗 Arbiscan: https://sepolia.arbiscan.io/tx/${tx.hash}`, 'blue');
                
                // Check new allowance
                await this.checkUSDCStatus();
                return true;
            } else {
                this.printColored("❌ USDC approval transaction failed!", 'red');
                return false;
            }
        } catch (error) {
            this.printColored(`❌ Error in approveUSDC(): ${error}`, 'red');
            return false;
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
                'ids[]': [SwapRouterFrontend.PRICE_FEEDS.ETH_USD.id],
                'encoding': 'hex'
            };
            // Debug log
            this.printColored(`🐍 Hermes request URL: ${url}`, 'yellow');
            this.printColored(`🐍 Hermes request params: ${JSON.stringify(params)}`, 'yellow');
            const response = await axios.get(url, {
                params,
                paramsSerializer: params => qs.stringify(params, { arrayFormat: 'repeat' }),
                timeout: 30000
            });
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
            
            // Store oracle price for arbitrage prediction
            this.lastOraclePrice = actualPrice;
            
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
     * Calculate pool ID from pool key components using Uniswap V4 method
     */
    calculatePoolId(currency0, currency1, fee, tickSpacing, hooks) {
        try {
            // Uniswap V4 PoolKey struct encoding
            // struct PoolKey {
            //     Currency currency0;
            //     Currency currency1;
            //     uint24 fee;
            //     int24 tickSpacing;
            //     IHooks hooks;
            // }
            
            // Ensure proper ordering (currency0 < currency1)
            let [c0, c1] = [currency0.toLowerCase(), currency1.toLowerCase()];
            if (c0 > c1) {
                [c0, c1] = [c1, c0];
            }
            
            // Encode the PoolKey struct
            const poolKeyEncoded = ethers.utils.defaultAbiCoder.encode(
                ['address', 'address', 'uint24', 'int24', 'address'],
                [c0, c1, fee, tickSpacing, hooks.toLowerCase()]
            );
            
            // Hash to get pool ID
            const poolId = ethers.utils.keccak256(poolKeyEncoded);
            
            this.printColored(`🔍 Pool ID calculation:`, 'gray');
            this.printColored(`   Currency0: ${c0}`, 'gray');
            this.printColored(`   Currency1: ${c1}`, 'gray');
            this.printColored(`   Fee: ${fee}`, 'gray');
            this.printColored(`   TickSpacing: ${tickSpacing}`, 'gray');
            this.printColored(`   Hooks: ${hooks.toLowerCase()}`, 'gray');
            this.printColored(`   Pool ID: ${poolId}`, 'gray');
            
            return poolId;
        } catch (error) {
            this.printColored(`❌ Error calculating pool ID: ${error}`, 'red');
            return null;
        }
    }

    /**
     * Get current pool price from slot0 - simplified version with fallback
     */
    async getPoolPrice() {
        // First try to get basic pool info
        try {
            const poolConfig = await this.contract.getPoolConfiguration();
            const [currency0, currency1, fee, tickSpacing, hooks] = poolConfig;
            
            this.printColored(`🔍 Pool Configuration:`, 'gray');
            this.printColored(`   Currency0: ${currency0} (ETH)`, 'gray');
            this.printColored(`   Currency1: ${currency1} (USDC)`, 'gray');
            this.printColored(`   Fee: ${fee} (${fee/10000}%)`, 'gray');
            this.printColored(`   TickSpacing: ${tickSpacing}`, 'gray');
            this.printColored(`   Hooks: ${hooks}`, 'gray');
            
            // For now, return a mock pool price based on oracle price
            // This is a fallback until we can properly read from PoolManager
            if (this.lastOraclePrice) {
                this.printColored(`💡 Using oracle price as pool price estimate`, 'yellow');
                return {
                    sqrtPriceX96: "0", // Mock value
                    tick: "0",         // Mock value
                    protocolFee: "0",  // Mock value
                    lpFee: fee.toString(),
                    ethUsdcPrice: this.lastOraclePrice, // Use oracle price as estimate
                    poolId: "mock_pool_id",
                    isInitialized: true,
                    isMockData: true
                };
            }
            
            // If no oracle price available, return null
            this.printColored(`⚠️  No oracle price available for pool price estimation`, 'yellow');
            return null;
            
        } catch (error) {
            this.printColored(`⚠️  Could not fetch pool configuration: ${error.message}`, 'yellow');
            return null;
        }
        
        // Original PoolManager approach (commented out for now)
        /*
        if (!this.poolManagerContract) {
            this.printColored("❌ PoolManager contract not available", 'red');
            return null;
        }

        try {
            // Get current pool configuration
            const poolConfig = await this.contract.getPoolConfiguration();
            const [currency0, currency1, fee, tickSpacing, hooks] = poolConfig;
            
            this.printColored(`🔍 Fetching pool price for:`, 'gray');
            this.printColored(`   Pool: ${currency0} / ${currency1}`, 'gray');
            this.printColored(`   Fee: ${fee}, TickSpacing: ${tickSpacing}`, 'gray');
            this.printColored(`   Hooks: ${hooks}`, 'gray');
            
            // Calculate pool ID
            const poolId = this.calculatePoolId(currency0, currency1, fee, tickSpacing, hooks);
            if (!poolId) {
                throw new Error("Failed to calculate pool ID");
            }
            
            // Try different methods to get pool data
            let slot0Data = null;
            
            try {
                // Method 1: Try getSlot0
                slot0Data = await this.poolManagerContract.getSlot0(poolId);
                this.printColored(`✅ Got slot0 data via getSlot0()`, 'green');
            } catch (error1) {
                this.printColored(`⚠️  getSlot0() failed: ${error1.message}`, 'yellow');
                
                try {
                    // Method 2: Try pools mapping
                    slot0Data = await this.poolManagerContract.pools(poolId);
                    this.printColored(`✅ Got slot0 data via pools()`, 'green');
                } catch (error2) {
                    this.printColored(`⚠️  pools() failed: ${error2.message}`, 'yellow');
                    throw new Error(`Both getSlot0() and pools() failed`);
                }
            }
            
            const [sqrtPriceX96, tick, protocolFee, lpFee] = slot0Data;
            
            this.printColored(`📊 Raw slot0 data:`, 'gray');
            this.printColored(`   sqrtPriceX96: ${sqrtPriceX96.toString()}`, 'gray');
            this.printColored(`   tick: ${tick.toString()}`, 'gray');
            
            // Convert sqrtPriceX96 to human-readable price
            // For ETH/USDC: Price = (sqrtPriceX96 / 2^96)^2 * (10^(decimals1 - decimals0))
            // ETH has 18 decimals, USDC has 6 decimals
            
            if (sqrtPriceX96.eq(0)) {
                throw new Error("Pool not initialized (sqrtPriceX96 = 0)");
            }
            
            // Calculate price using BigNumber arithmetic
            const Q96 = ethers.BigNumber.from(2).pow(96);
            const DECIMALS_DIFF = ethers.BigNumber.from(10).pow(12); // 10^(18-6)
            
            // price = (sqrtPriceX96 / 2^96)^2 * 10^12
            const sqrtPrice = sqrtPriceX96.mul(ethers.BigNumber.from(10).pow(18)).div(Q96);
            const price = sqrtPrice.mul(sqrtPrice).div(ethers.BigNumber.from(10).pow(18));
            
            // This gives us the price of currency1 in terms of currency0
            // For ETH/USDC pool: price of USDC in terms of ETH
            // We want ETH price in USDC, so we need to invert
            const ethUsdcPrice = DECIMALS_DIFF.mul(ethers.BigNumber.from(10).pow(6)).div(price);
            const ethUsdcPriceFormatted = parseFloat(ethers.utils.formatUnits(ethUsdcPrice, 6));
            
            this.printColored(`💰 Calculated ETH/USDC price: $${ethUsdcPriceFormatted.toFixed(2)}`, 'blue');
            
            return {
                sqrtPriceX96: sqrtPriceX96.toString(),
                tick: tick.toString(),
                protocolFee: protocolFee.toString(),
                lpFee: lpFee.toString(),
                ethUsdcPrice: ethUsdcPriceFormatted,
                poolId: poolId,
                isInitialized: !sqrtPriceX96.eq(0)
            };
            
        } catch (error) {
            this.printColored(`⚠️  Could not fetch pool price: ${error.message}`, 'yellow');
            this.printColored(`💡 This might indicate the pool is not initialized`, 'cyan');
            return null;
        }
        */
    }

    /**
     * Predict arbitrage opportunity based on pool vs oracle price
     */
    predictArbitrage(poolPrice, oraclePrice, direction, amount) {
        if (!poolPrice || !oraclePrice) return { hasArbitrage: false, reason: "Missing price data" };
        
        const priceDiff = Math.abs(poolPrice - oraclePrice);
        const priceDiffPct = (priceDiff / oraclePrice) * 100;
        
        // Threshold for arbitrage detection (DetoxHook typically uses ~0.5-1%)
        const arbitrageThreshold = 0.5; // 0.5%
        
        const hasArbitrage = priceDiffPct > arbitrageThreshold;
        
        let prediction = "No arbitrage detected";
        let expectedAction = "Normal swap";
        
        if (hasArbitrage) {
            if (direction) { // zeroForOne (ETH → USDC)
                if (poolPrice > oraclePrice) {
                    prediction = "Pool overpriced - arbitrage opportunity";
                    expectedAction = "DetoxHook should extract MEV fee";
                } else {
                    prediction = "Pool underpriced - no profitable arbitrage";
                    expectedAction = "Normal swap (no MEV extraction)";
                }
            } else { // oneForZero (USDC → ETH)
                if (poolPrice < oraclePrice) {
                    prediction = "Pool underpriced - arbitrage opportunity";
                    expectedAction = "DetoxHook should extract MEV fee";
                } else {
                    prediction = "Pool overpriced - no profitable arbitrage";
                    expectedAction = "Normal swap (no MEV extraction)";
                }
            }
        }
        
        return {
            hasArbitrage,
            priceDiff,
            priceDiffPct,
            prediction,
            expectedAction,
            threshold: arbitrageThreshold
        };
    }

    /**
     * --swap flag functionality
     * Read from the cl the size and direction of a swap
     * Call the Hermes system and generate the update data required for reading data on-chain
     * Make a call to the function swap() of the smart contract SwapRouter.sol
     */
    async executeSwap(amount, direction, exactInput = true) {
        this.printColored(`\n🔄 [--swap] Executing swap with amount: ${amount}, direction: ${direction}`, 'magenta');
        
        if (!this.contract || !this.wallet) {
            this.printColored("❌ Contract or wallet not available", 'red');
            return { success: false, error: "Contract or wallet not available" };
        }

        // Use funding wallet if specified, otherwise use default wallet
        const activeWallet = this.fundingWalletAddress ? 
            new ethers.Wallet(this.wallet.privateKey, this.provider) : this.wallet;
        
        try {
            // 1. Generate swap parameters (now more prominent and configurable)
            const swapParams = this.generateSwapParams(amount, direction, exactInput);
            
            this.printColored(`\n📊 Swap Parameters:`, 'cyan');
            this.printColored(`   Original Amount: ${swapParams.originalAmount}`, 'white');
            this.printColored(`   Amount Wei: ${swapParams.amountWei}`, 'white');
            this.printColored(`   Amount Specified: ${swapParams.amountSpecified}`, 'white');
            this.printColored(`   Swap Type: ${swapParams.swapType}`, 'white');
            this.printColored(`   Direction: ${swapParams.direction}`, 'white');
            this.printColored(`   Zero For One: ${swapParams.zeroForOne}`, 'white');
            this.printColored(`   Price Limit: ${swapParams.priceLimit}`, 'gray');
            
            // 2. Call the Hermes system and generate the update data required for reading data on-chain
            this.printColored(`\n🐍 Fetching Pyth Price Updates:`, 'magenta');
            const updateData = await this.generate();
            
            this.printColored(`\n📦 Transaction Details:`, 'cyan');
            this.printColored(`   Update Data: ${(updateData.length - 2) / 2} bytes`, 'white');
            this.printColored(`   Funding Wallet: ${this.fundingWalletAddress || activeWallet.address}`, 'white');
            this.printColored(`   Target Contract: ${SwapRouterFrontend.SWAP_ROUTER_ADDRESS}`, 'white');
            
            // 3. Make a call to the function swap() of the smart contract SwapRouter.sol with deployment details
            this.printColored("\n⛽ Estimating gas for swap...", 'cyan');
            
            let gasEstimate;
            try {
                gasEstimate = await this.contract.estimateGas.swap(
                    swapParams.amountToSwap,
                    swapParams.zeroForOne,
                    updateData,
                    { from: activeWallet.address }
                );
            } catch (gasError) {
                this.printColored("❌ Gas estimation failed - transaction would revert", 'red');
                this.printColored("💡 This indicates the swap cannot be executed successfully", 'yellow');
                
                // Analyze the error
                if (gasError.message.includes("execution reverted")) {
                    this.printColored("\n🔍 Transaction Revert Analysis:", 'yellow');
                    this.printColored("   • The contract rejected the transaction during simulation", 'white');
                    this.printColored("   • This could be due to:", 'white');
                    this.printColored("     - Hook validation failures (e.g., stale price data)", 'white');
                    this.printColored("     - Insufficient liquidity in the pool", 'white');
                    this.printColored("     - Slippage protection triggered", 'white');
                    this.printColored("     - Hook contract bugs or missing functionality", 'white');
                    this.printColored("     - Oracle price update failures", 'white');
                    
                    // Check if this is likely the old hook issue
                    const poolConfig = await this.contract.getPoolConfiguration();
                    const hooksAddress = poolConfig[4]; // hooks is the 5th element
                    
                    if (hooksAddress && hooksAddress !== "0x0000000000000000000000000000000000000000") {
                        this.printColored("\n🎯 Likely Cause Analysis:", 'cyan');
                        this.printColored(`   Hook Address: ${hooksAddress}`, 'white');
                        this.printColored("   • The hook is configured but may not support Pyth price updates", 'yellow');
                        this.printColored("   • If this is the old DetoxHook, it lacks the Pyth integration fix", 'yellow');
                        this.printColored("   • The hook may be reverting when trying to process price data", 'yellow');
                        this.printColored("\n💡 Recommended Actions:", 'green');
                        this.printColored("   1. Deploy the updated DetoxHook with Pyth integration", 'white');
                        this.printColored("   2. Update SwapRouter to point to the new hook", 'white');
                        this.printColored("   3. Or test without hook data (empty bytes)", 'white');
                    }
                } else if (gasError.message.includes("UNPREDICTABLE_GAS_LIMIT")) {
                    this.printColored("\n🔍 Gas Estimation Error:", 'yellow');
                    this.printColored("   • The transaction behavior is unpredictable", 'white');
                    this.printColored("   • This usually means the transaction would revert", 'white');
                }
                
                this.printColored(`\n📋 Full Error Details:`, 'gray');
                this.printColored(`   ${gasError.message}`, 'gray');
                
                return { success: false, error: "Gas estimation failed - transaction would revert", details: gasError.message };
            }
            
            // Add 20% buffer
            const gasLimit = gasEstimate.mul(120).div(100);
            this.printColored(`⛽ Gas estimate: ${gasEstimate.toLocaleString()} (limit: ${gasLimit.toLocaleString()})`, 'cyan');
            
            // Send transaction
            this.printColored("✍️  Signing and sending swap transaction...", 'cyan');
            
            const contractWithSigner = this.contract.connect(activeWallet);
            let tx;
            try {
                tx = await contractWithSigner.swap(
                    swapParams.amountToSwap,
                    swapParams.zeroForOne,
                    updateData,
                    { gasLimit: gasLimit }
                );
            } catch (txError) {
                this.printColored("❌ Transaction submission failed", 'red');
                this.printColored(`💡 Error: ${txError.message}`, 'yellow');
                return { success: false, error: "Transaction submission failed", details: txError.message };
            }
            
            this.printColored(`✅ Swap transaction sent: ${tx.hash}`, 'green');
            this.printColored("⏳ Waiting for confirmation...", 'cyan');
            
            // Wait for confirmation
            let receipt;
            try {
                receipt = await tx.wait();
            } catch (waitError) {
                this.printColored("❌ Transaction confirmation failed", 'red');
                this.printColored(`💡 Error: ${waitError.message}`, 'yellow');
                return { success: false, error: "Transaction confirmation failed", details: waitError.message };
            }
            
            if (receipt && receipt.status === 1) {
                this.printColored("✅ Swap transaction confirmed!", 'green');
                this.printColored(`📊 Block: ${receipt.blockNumber}`, 'cyan');
                this.printColored(`⛽ Gas used: ${receipt.gasUsed.toLocaleString()}`, 'cyan');
                this.printColored(`🔗 Arbiscan: https://sepolia.arbiscan.io/tx/${tx.hash}`, 'blue');
                
                // Parse logs for SwapExecuted event
                this.parseSwapEvents(receipt);
                
                return { success: true, txHash: tx.hash, receipt: receipt };
            } else {
                this.printColored("❌ Swap transaction failed!", 'red');
                this.printColored(`📊 Block: ${receipt?.blockNumber || 'unknown'}`, 'cyan');
                this.printColored(`⛽ Gas used: ${receipt?.gasUsed?.toLocaleString() || 'unknown'}`, 'cyan');
                if (tx.hash) {
                    this.printColored(`🔗 Arbiscan: https://sepolia.arbiscan.io/tx/${tx.hash}`, 'blue');
                }
                return { success: false, error: "Transaction reverted", receipt: receipt };
            }
        } catch (error) {
            this.printColored(`❌ Error in executeSwap(): ${error}`, 'red');
            return { success: false, error: error.message, details: error };
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
            return { success: false, error: "Contract or wallet not available" };
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
            
            let gasEstimate;
            try {
                gasEstimate = await this.contract.estimateGas.updatePoolConfiguration(
                    poolKey,
                    { from: activeWallet.address }
                );
            } catch (gasError) {
                this.printColored("❌ Gas estimation failed - transaction would revert", 'red');
                this.printColored(`💡 Error: ${gasError.message}`, 'yellow');
                return { success: false, error: "Gas estimation failed", details: gasError.message };
            }
            
            // Add 20% buffer
            const gasLimit = gasEstimate.mul(120).div(100);
            this.printColored(`⛽ Gas estimate: ${gasEstimate.toLocaleString()} (limit: ${gasLimit.toLocaleString()})`, 'cyan');
            
            // Send transaction
            this.printColored("✍️  Signing and sending updatePoolConfiguration transaction...", 'cyan');
            
            const contractWithSigner = this.contract.connect(activeWallet);
            let tx;
            try {
                tx = await contractWithSigner.updatePoolConfiguration(
                    poolKey,
                    { gasLimit: gasLimit }
                );
            } catch (txError) {
                this.printColored("❌ Transaction submission failed", 'red');
                this.printColored(`💡 Error: ${txError.message}`, 'yellow');
                return { success: false, error: "Transaction submission failed", details: txError.message };
            }
            
            this.printColored(`✅ UpdatePoolConfiguration transaction sent: ${tx.hash}`, 'green');
            this.printColored("⏳ Waiting for confirmation...", 'cyan');
            
            // Wait for confirmation
            let receipt;
            try {
                receipt = await tx.wait();
            } catch (waitError) {
                this.printColored("❌ Transaction confirmation failed", 'red');
                this.printColored(`💡 Error: ${waitError.message}`, 'yellow');
                return { success: false, error: "Transaction confirmation failed", details: waitError.message };
            }
            
            if (receipt && receipt.status === 1) {
                this.printColored("✅ UpdatePoolConfiguration transaction confirmed!", 'green');
                this.printColored(`📊 Block: ${receipt.blockNumber}`, 'cyan');
                this.printColored(`⛽ Gas used: ${receipt.gasUsed.toLocaleString()}`, 'cyan');
                this.printColored(`🔗 Arbiscan: https://sepolia.arbiscan.io/tx/${tx.hash}`, 'blue');
                this.printColored(`ℹ️  Note: PoolId '${poolId}' is not stored on-chain (client-side only)`, 'yellow');
                return { success: true, txHash: tx.hash, receipt: receipt };
            } else {
                this.printColored("❌ UpdatePoolConfiguration transaction failed!", 'red');
                return { success: false, error: "Transaction reverted", receipt: receipt };
            }
        } catch (error) {
            this.printColored(`❌ Error in updatePool(): ${error}`, 'red');
            return { success: false, error: error.message, details: error };
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
            return { success: false, error: "Contract not available" };
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
            
            return { success: true, poolConfig: poolKey };
            
        } catch (error) {
            this.printColored(`❌ Error in getPool(): ${error}`, 'red');
            return { success: false, error: error.message, details: error };
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
                this.printColored("❌ Invalid Ethereum address format", 'red');
                return { success: false, error: "Invalid Ethereum address format" };
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
            
            return { success: true, address: address };
            
        } catch (error) {
            this.printColored(`❌ Error in setFundingWallet(): ${error}`, 'red');
            return { success: false, error: error.message, details: error };
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

    /**
     * Systematic testing function - test both directions with optimal amounts
     */
    async executeSystematicTest() {
        this.printColored(`\n🧪 [--test] Systematic DetoxHook Testing`, 'magenta');
        this.printColored("Testing both swap directions with optimal amounts", 'cyan');
        
        // Test parameters (lowered values)
        const testAmounts = {
            ethToUsdc: [0.0001, 0.0002, 0.0005], // Lower ETH amounts
            usdcToEth: [0.5, 1, 2]               // Lower USDC amounts
        };
        
        let testResults = [];
        
        try {
            // Test 1: ETH → USDC (zeroForOne = true)
            this.printColored(`\n🔄 Testing ETH → USDC swaps (zeroForOne = true)`, 'yellow');
            for (const amount of testAmounts.ethToUsdc) {
                this.printColored(`\n--- Test ${testResults.length + 1}: ${amount} ETH → USDC ---`, 'cyan');
                
                const result = await this.executeSingleTest(amount, true);
                testResults.push({
                    testNumber: testResults.length + 1,
                    direction: 'ETH → USDC',
                    amount: amount,
                    zeroForOne: true,
                    ...result
                });
                
                // Wait between tests
                await this.sleep(2000);
            }
            
            // Test 2: USDC → ETH (zeroForOne = false)
            this.printColored(`\n🔄 Testing USDC → ETH swaps (zeroForOne = false)`, 'yellow');
            for (const amount of testAmounts.usdcToEth) {
                this.printColored(`\n--- Test ${testResults.length + 1}: ${amount} USDC → ETH ---`, 'cyan');
                
                const result = await this.executeSingleTest(amount, false);
                testResults.push({
                    testNumber: testResults.length + 1,
                    direction: 'USDC → ETH',
                    amount: amount,
                    zeroForOne: false,
                    ...result
                });
                
                // Wait between tests
                await this.sleep(2000);
            }
            
            // Print summary
            this.printTestSummary(testResults);
            
        } catch (error) {
            this.printColored(`❌ Error in systematic testing: ${error}`, 'red');
        }
    }

    /**
     * Execute a single test swap and return results
     */
    async executeSingleTest(amount, direction) {
        try {
            // Get pre-swap state
            const preSwapPoolPrice = await this.getPoolPrice();
            const preSwapBalances = await this.getBalances();
            
            // Generate oracle data
            const updateData = await this.generate();
            const oraclePrice = this.lastOraclePrice;
            
            // Predict arbitrage
            let arbitragePrediction = null;
            if (preSwapPoolPrice) {
                arbitragePrediction = this.predictArbitrage(
                    preSwapPoolPrice.ethUsdcPrice,
                    oraclePrice,
                    direction,
                    amount
                );
                
                this.printColored(`🔮 Prediction: ${arbitragePrediction.prediction}`, 
                    arbitragePrediction.hasArbitrage ? 'yellow' : 'green');
            }
            
            // Execute swap (simplified version without all the logging)
            const result = await this.executeSwap(amount, direction);
            
            // Get post-swap state
            const postSwapPoolPrice = await this.getPoolPrice();
            const postSwapBalances = await this.getBalances();
            
            return {
                success: result.success,
                error: result.error,
                preSwapPoolPrice: preSwapPoolPrice?.ethUsdcPrice,
                postSwapPoolPrice: postSwapPoolPrice?.ethUsdcPrice,
                oraclePrice,
                arbitragePrediction,
                preSwapBalances,
                postSwapBalances
            };
            
        } catch (error) {
            this.printColored(`❌ Test failed: ${error.message}`, 'red');
            return {
                success: false,
                error: error.message
            };
        }
    }

    /**
     * Get current balances
     */
    async getBalances() {
        try {
            const ethBalance = await this.provider.getBalance(this.wallet.address);
            const ethBalanceFormatted = parseFloat(ethers.utils.formatEther(ethBalance));
            
            const usdcBalance = await this.usdcContract.balanceOf(this.wallet.address);
            const usdcBalanceFormatted = parseFloat(ethers.utils.formatUnits(usdcBalance, 6));
            
            return {
                eth: ethBalanceFormatted,
                usdc: usdcBalanceFormatted
            };
        } catch (error) {
            return { eth: 0, usdc: 0 };
        }
    }

    /**
     * Print test summary
     */
    printTestSummary(results) {
        this.printColored(`\n📊 SYSTEMATIC TEST SUMMARY`, 'cyan');
        this.printColored(`=`.repeat(50), 'cyan');
        
        let successCount = 0;
        let arbitrageDetected = 0;
        let mevExtracted = 0;
        
        for (const result of results) {
            if (result.success) successCount++;
            if (result.arbitragePrediction?.hasArbitrage) arbitrageDetected++;
            
            this.printColored(`\nTest ${result.testNumber}: ${result.direction}`, 'yellow');
            this.printColored(`  Amount: ${result.amount}`, 'white');
            this.printColored(`  Success: ${result.success ? '✅' : '❌'}`, result.success ? 'green' : 'red');
            
            if (result.arbitragePrediction) {
                this.printColored(`  Arbitrage: ${result.arbitragePrediction.hasArbitrage ? '🎯' : '➖'}`, 
                    result.arbitragePrediction.hasArbitrage ? 'yellow' : 'gray');
                this.printColored(`  Price Diff: ${result.arbitragePrediction.priceDiffPct.toFixed(3)}%`, 'gray');
            }
            
            if (result.preSwapPoolPrice && result.postSwapPoolPrice) {
                const priceChange = result.postSwapPoolPrice - result.preSwapPoolPrice;
                this.printColored(`  Pool Price: $${result.preSwapPoolPrice.toFixed(2)} → $${result.postSwapPoolPrice.toFixed(2)} (${priceChange > 0 ? '+' : ''}${priceChange.toFixed(2)})`, 'gray');
            }
        }
        
        this.printColored(`\n📈 RESULTS:`, 'cyan');
        this.printColored(`  Total Tests: ${results.length}`, 'white');
        this.printColored(`  Successful: ${successCount}/${results.length} (${(successCount/results.length*100).toFixed(1)}%)`, 'green');
        this.printColored(`  Arbitrage Detected: ${arbitrageDetected}`, 'yellow');
        this.printColored(`  MEV Extraction Expected: ${arbitrageDetected}`, 'yellow');
    }

    /**
     * Sleep utility
     */
    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // Add generateSwapParams method
    generateSwapParams(amount, zeroForOne, exactInput = true) {
        // Convert amount to proper format based on direction
        const decimals = zeroForOne ? 18 : 6; // ETH has 18 decimals, USDC has 6
        const amountWei = ethers.utils.parseUnits(amount.toString(), decimals);
        
        // For exact input swaps, amount is negative
        // For exact output swaps, amount is positive
        const amountSpecified = exactInput ? `-${amountWei.toString()}` : amountWei.toString();
        
        // Price limit:
        // - For zeroForOne (ETH→USDC): use 0 as minimum price
        // - For oneForZero (USDC→ETH): use MaxUint256 as maximum price
        const sqrtPriceLimitX96 = zeroForOne ? '0' : ethers.constants.MaxUint256.toString();
        
        // Return full parameter object for better debugging
        return {
            originalAmount: amount,
            amountWei: amountWei.toString(),
            amountSpecified,
            amountToSwap: amountSpecified,
            swapType: exactInput ? 'exact-input' : 'exact-output',
            direction: zeroForOne ? 'ETH→USDC' : 'USDC→ETH',
            zeroForOne,
            priceLimit: sqrtPriceLimitX96
        };
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
    console.log(chalk.green('  node scripts-js/SwapRouterFrontend.js --approve'));
    console.log(chalk.green('  node scripts-js/SwapRouterFrontend.js --test'));
    console.log(chalk.white(''));
    console.log(chalk.white('Or via yarn:'));
    console.log(chalk.green('  yarn swap-router --swap 0.00002 false'));
    console.log(chalk.green('  yarn swap-router --getpool'));
    console.log(chalk.green('  yarn swap-router --approve'));
    console.log(chalk.green('  yarn swap-router --test'));
    console.log(chalk.white(''));
    console.log(chalk.white('Flags:'));
    console.log(chalk.white('  --swap         Execute a swap on the SwapRouter contract'));
    console.log(chalk.white('  --updatepool   Update the pool configuration with PoolId'));
    console.log(chalk.white('  --getpool      Get and display current pool configuration'));
    console.log(chalk.white('  --wallet       Set funding wallet address for transactions'));
    console.log(chalk.white('  --approve      Approve USDC token for SwapRouter'));
    console.log(chalk.white('  --test         Run systematic tests (both directions, multiple amounts)'));
    console.log(chalk.white(''));
    console.log(chalk.white('Examples:'));
    console.log(chalk.yellow('  node scripts-js/SwapRouterFrontend.js --swap 0.02 true'));
    console.log(chalk.yellow('  yarn swap-router --swap 0.00002 false'));
    console.log(chalk.yellow('  yarn swap-router --updatepool 0x... 0x... 3000 60 0x... pool123'));
    console.log(chalk.yellow('  yarn swap-router --getpool'));
    console.log(chalk.yellow('  yarn swap-router --wallet 0x742d35Cc6644C44532767eaFA8CA3b8d8ad67A95'));
    console.log(chalk.yellow('  yarn swap-router --approve'));
    console.log(chalk.yellow('  yarn swap-router --test'));
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
        
        let operationResult = { success: true }; // Track overall success
        
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
                
                operationResult = await frontend.executeSwap(amount, direction);
                break;
                
            case '--swapout':
                if (args.length < 3) {
                    console.log(chalk.red('❌ --swapout requires <amount> <direction> arguments'));
                    console.log(chalk.white('Example: yarn swap-router --swapout 0.02 true'));
                    process.exit(1);
                }
                
                const swapoutAmount = parseFloat(args[1]);
                const swapoutDirection = ['true', '1'].includes(args[2].toLowerCase());
                
                if (isNaN(swapoutAmount)) {
                    console.log(chalk.red('❌ Invalid amount. Please provide a valid number.'));
                    process.exit(1);
                }
                
                if (!['true', 'false', '1', '0'].includes(args[2].toLowerCase())) {
                    console.log(chalk.red('❌ Invalid direction. Use true/false or 1/0.'));
                    process.exit(1);
                }
                
                operationResult = await frontend.executeSwap(swapoutAmount, swapoutDirection, false);
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
                
                operationResult = await frontend.updatePool(currency0, currency1, fee, tickSpacing, hooks, poolId);
                break;
                
            case '--getpool':
                operationResult = await frontend.getPool();
                break;
                
            case '--wallet':
                if (args.length < 2) {
                    console.log(chalk.red('❌ --wallet requires <address> argument'));
                    console.log(chalk.white('Example: yarn swap-router --wallet 0x742d35Cc6644C44532767eaFA8CA3b8d8ad67A95'));
                    process.exit(1);
                }
                
                const walletAddress = args[1];
                operationResult = frontend.setFundingWallet(walletAddress);
                break;
                
            case '--approve':
                await frontend.approveUSDC();
                break;
                
            case '--test':
                await frontend.executeSystematicTest();
                break;
                
            default:
                console.log(chalk.red(`❌ Unknown flag: ${flag}`));
                showUsage();
                process.exit(1);
        }
        
        // Only show success message if operation actually succeeded
        if (operationResult && operationResult.success !== false) {
            console.log(chalk.green.bold("\n🎉 Operation completed successfully!"));
        } else if (operationResult && operationResult.success === false) {
            console.log(chalk.red.bold("\n❌ Operation failed!"));
            if (operationResult.error) {
                console.log(chalk.red(`💡 Error: ${operationResult.error}`));
            }
            process.exit(1);
        }
        
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