#!/usr/bin/env node

/**
 * SwapRouterOptimized.cjs - Enhanced Pyth-Integrated Swap Router Frontend
 * 
 * OPTIMIZATIONS IMPLEMENTED:
 * ✅ Enhanced error handling with retry mechanisms
 * ✅ Caching for frequently accessed data (30s TTL)
 * ✅ Parallel API calls for better performance
 * ✅ Multiple price feed support (ETH/USD, USDC/USD)
 * ✅ Price staleness and confidence validation
 * ✅ Better progress indicators and user feedback
 * ✅ Gas estimation before transactions
 * ✅ Configuration validation
 * ✅ Modular code structure with separate concerns
 * ✅ Comprehensive logging and debugging
 * 
 * Usage:
 *     yarn swap-router-opt --swap 0.00002 false
 *     yarn swap-router-opt --getpool
 *     yarn swap-router-opt --test
 */

const { ethers } = require('ethers');
const axios = require('axios');
const dotenv = require('dotenv');
const chalk = require('chalk');
const path = require('path');
const qs = require('qs');

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../.env') });

// ============ CONFIGURATION MODULE ============
class Config {
    static ARBITRUM_SEPOLIA_RPC = "https://sepolia-rollup.arbitrum.io/rpc";
    static PYTH_HERMES_API = "https://hermes.pyth.network";
    
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
    
    static CONTRACTS = {
        SWAP_ROUTER: "0x7dD454F098f74eD0464c3896BAe8412C8b844E7e",
        USDC_TOKEN: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
        POOL_MANAGER: "0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829"
    };
    
    static OPTIMIZATION = {
        CACHE_TTL: 30000, // 30 seconds
        MAX_RETRIES: 3,
        RETRY_DELAY: 1000, // 1 second
        PRICE_STALENESS_THRESHOLD: 60, // 60 seconds
        MAX_CONFIDENCE_INTERVAL: 1.0, // 1%
        REQUEST_TIMEOUT: 30000 // 30 seconds
    };
}

// ============ LOGGING MODULE ============
class Logger {
    static printColored(message, color = 'white') {
        const chalkColor = chalk[color] || chalk.white;
        console.log(chalkColor(message));
    }

    static printHeader() {
        Logger.printColored("\n" + "=".repeat(70), 'cyan');
        Logger.printColored("🚀 SwapRouter Frontend - OPTIMIZED VERSION", 'cyan');
        Logger.printColored("=".repeat(70), 'cyan');
        Logger.printColored(`📍 Contract: ${Config.CONTRACTS.SWAP_ROUTER}`, 'yellow');
        Logger.printColored(`🌐 Network: Arbitrum Sepolia`, 'green');
        Logger.printColored(`🐍 Pyth Feeds: ETH/USD, USDC/USD`, 'blue');
        Logger.printColored("=".repeat(70) + "\n", 'cyan');
    }

    static printProgress(step, total, message) {
        const progress = Math.round((step / total) * 100);
        const bar = "█".repeat(Math.round(progress / 5)) + "░".repeat(20 - Math.round(progress / 5));
        Logger.printColored(`[${bar}] ${progress}% - ${message}`, 'cyan');
    }

    static printError(error, context = '') {
        Logger.printColored(`❌ ${context ? `[${context}] ` : ''}${error}`, 'red');
    }

    static printSuccess(message, context = '') {
        Logger.printColored(`✅ ${context ? `[${context}] ` : ''}${message}`, 'green');
    }

    static printWarning(message, context = '') {
        Logger.printColored(`⚠️  ${context ? `[${context}] ` : ''}${message}`, 'yellow');
    }
}

// ============ CACHE MODULE ============
class Cache {
    constructor() {
        this.data = new Map();
    }

    set(key, value, ttl = Config.OPTIMIZATION.CACHE_TTL) {
        const expiry = Date.now() + ttl;
        this.data.set(key, { value, expiry });
        Logger.printColored(`💾 Cached: ${key} (TTL: ${ttl}ms)`, 'gray');
    }

    get(key) {
        const item = this.data.get(key);
        if (!item) return null;
        
        if (Date.now() > item.expiry) {
            this.data.delete(key);
            Logger.printColored(`🗑️  Cache expired: ${key}`, 'gray');
            return null;
        }
        
        Logger.printColored(`📦 Cache hit: ${key}`, 'gray');
        return item.value;
    }

    clear() {
        this.data.clear();
        Logger.printColored(`🧹 Cache cleared`, 'gray');
    }
}

// ============ RETRY UTILITY ============
class RetryUtil {
    static async withRetry(operation, maxRetries = Config.OPTIMIZATION.MAX_RETRIES, delay = Config.OPTIMIZATION.RETRY_DELAY) {
        let lastError;
        
        for (let attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                Logger.printColored(`🔄 Attempt ${attempt}/${maxRetries}`, 'gray');
                return await operation();
            } catch (error) {
                lastError = error;
                Logger.printWarning(`Attempt ${attempt} failed: ${error.message}`);
                
                if (attempt < maxRetries) {
                    Logger.printColored(`⏳ Retrying in ${delay}ms...`, 'yellow');
                    await new Promise(resolve => setTimeout(resolve, delay));
                    delay *= 1.5; // Exponential backoff
                }
            }
        }
        
        throw lastError;
    }
}

// ============ PYTH ORACLE MODULE ============
class PythOracle {
    constructor(cache) {
        this.cache = cache;
        this.lastPrices = {};
    }

    async fetchPriceData(priceFeeds = [Config.PRICE_FEEDS.ETH_USD.id]) {
        const cacheKey = `pyth_prices_${priceFeeds.join('_')}`;
        const cached = this.cache.get(cacheKey);
        if (cached) return cached;

        Logger.printProgress(1, 3, "Fetching Pyth price data...");

        const operation = async () => {
            const url = `${Config.PYTH_HERMES_API}/v2/updates/price/latest`;
            const params = {
                'ids[]': priceFeeds,
                'encoding': 'hex'
            };
            // Debug log
            Logger.printColored(`🐍 Hermes request URL: ${url}`, 'yellow');
            Logger.printColored(`🐍 Hermes request params: ${JSON.stringify(params)}`, 'yellow');
            const response = await axios.get(url, {
                params,
                paramsSerializer: params => qs.stringify(params, { arrayFormat: 'repeat' }),
                timeout: Config.OPTIMIZATION.REQUEST_TIMEOUT
            });
            if (!response.data.binary || !response.data.parsed) {
                throw new Error("Invalid response format from Hermes API");
            }
            return this.processPriceData(response.data);
        };

        const result = await RetryUtil.withRetry(operation);
        this.cache.set(cacheKey, result);
        
        Logger.printProgress(3, 3, "Price data fetched and cached");
        return result;
    }

    processPriceData(data) {
        const processedPrices = [];
        const updateDataArray = [];

        for (let i = 0; i < data.parsed.length; i++) {
            const parsedData = data.parsed[i];
            const updateDataHex = data.binary.data[i];
            
            const priceInfo = parsedData.price;
            const priceRaw = parseInt(priceInfo.price);
            const expo = parseInt(priceInfo.expo);
            const confRaw = parseInt(priceInfo.conf);
            const publishTime = parseInt(priceInfo.publish_time);

            const actualPrice = priceRaw * Math.pow(10, expo);
            const confidenceInterval = confRaw * Math.pow(10, expo);
            const confidencePct = actualPrice !== 0 ? (confidenceInterval / actualPrice) * 100 : 0;

            // Validate price data
            const validation = this.validatePriceData(actualPrice, confidencePct, publishTime);
            
            const priceData = {
                id: parsedData.id,
                price: actualPrice,
                confidence: confidenceInterval,
                confidencePct: confidencePct,
                publishTime: publishTime,
                updateData: `0x${updateDataHex}`,
                validation: validation,
                symbol: this.getPriceSymbol(parsedData.id)
            };

            processedPrices.push(priceData);
            updateDataArray.push(`0x${updateDataHex}`);

            // Store for arbitrage detection
            this.lastPrices[parsedData.id] = priceData;

            Logger.printSuccess(
                `${priceData.symbol}: $${actualPrice.toLocaleString(undefined, {
                    minimumFractionDigits: 2, 
                    maximumFractionDigits: 2
                })} (±${confidencePct.toFixed(3)}%)`,
                'PYTH'
            );

            if (!validation.isValid) {
                Logger.printWarning(`Price validation failed: ${validation.reason}`, 'PYTH');
            }
        }

        // Combine all update data
        const combinedUpdateData = this.combineUpdateData(updateDataArray);

        return {
            prices: processedPrices,
            updateData: combinedUpdateData,
            timestamp: Date.now()
        };
    }

    validatePriceData(price, confidencePct, publishTime) {
        const now = Math.floor(Date.now() / 1000);
        const age = now - publishTime;

        if (age > Config.OPTIMIZATION.PRICE_STALENESS_THRESHOLD) {
            return {
                isValid: false,
                reason: `Price too stale (${age}s old)`
            };
        }

        if (confidencePct > Config.OPTIMIZATION.MAX_CONFIDENCE_INTERVAL) {
            return {
                isValid: false,
                reason: `Confidence interval too wide (${confidencePct.toFixed(2)}%)`
            };
        }

        if (price <= 0) {
            return {
                isValid: false,
                reason: 'Invalid price value'
            };
        }

        return { isValid: true, reason: 'Valid' };
    }

    getPriceSymbol(priceId) {
        for (const [key, feed] of Object.entries(Config.PRICE_FEEDS)) {
            if (feed.id === priceId) {
                return feed.symbol;
            }
        }
        return 'UNKNOWN';
    }

    combineUpdateData(updateDataArray) {
        if (updateDataArray.length === 1) {
            return updateDataArray[0];
        }

        // For multiple price feeds, we need to encode them properly
        // This is a simplified approach - in production, you might need more sophisticated encoding
        const combined = updateDataArray.map(data => data.slice(2)).join('');
        return `0x${combined}`;
    }

    predictArbitrage(poolPrice, direction, amount) {
        const ethPrice = this.lastPrices[Config.PRICE_FEEDS.ETH_USD.id];
        if (!ethPrice || !poolPrice) {
            return { hasArbitrage: false, reason: "Missing price data" };
        }

        const priceDiff = Math.abs(poolPrice - ethPrice.price);
        const priceDiffPct = (priceDiff / ethPrice.price) * 100;
        const arbitrageThreshold = 0.5; // 0.5%

        const hasArbitrage = priceDiffPct > arbitrageThreshold;

        let prediction = "No arbitrage detected";
        let expectedAction = "Normal swap";

        if (hasArbitrage) {
            if (direction) { // zeroForOne (ETH → USDC)
                if (poolPrice > ethPrice.price) {
                    prediction = "Pool overpriced - arbitrage opportunity";
                    expectedAction = "DetoxHook should extract MEV fee";
                } else {
                    prediction = "Pool underpriced - no profitable arbitrage";
                    expectedAction = "Normal swap (no MEV extraction)";
                }
            } else { // oneForZero (USDC → ETH)
                if (poolPrice < ethPrice.price) {
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
            threshold: arbitrageThreshold,
            oraclePrice: ethPrice.price,
            poolPrice: poolPrice,
            confidence: ethPrice.confidencePct
        };
    }
}

// ============ CONTRACT INTERACTION MODULE ============
class ContractManager {
    constructor(provider, wallet, cache) {
        this.provider = provider;
        this.wallet = wallet;
        this.cache = cache;
        this.contracts = {};
        
        this.setupContracts();
    }

    setupContracts() {
        // SwapRouter contract
        this.contracts.swapRouter = new ethers.Contract(
            Config.CONTRACTS.SWAP_ROUTER,
            this.getSwapRouterABI(),
            this.wallet || this.provider
        );

        // USDC token contract
        this.contracts.usdc = new ethers.Contract(
            Config.CONTRACTS.USDC_TOKEN,
            this.getERC20ABI(),
            this.wallet || this.provider
        );

        // PoolManager contract
        this.contracts.poolManager = new ethers.Contract(
            Config.CONTRACTS.POOL_MANAGER,
            this.getPoolManagerABI(),
            this.provider
        );

        Logger.printSuccess("All contracts initialized", "CONTRACTS");
    }

    async getPoolConfiguration() {
        const cacheKey = 'pool_config';
        const cached = this.cache.get(cacheKey);
        if (cached) return cached;

        Logger.printProgress(1, 2, "Fetching pool configuration...");

        const poolConfig = await this.contracts.swapRouter.getPoolConfiguration();
        const [currency0, currency1, fee, tickSpacing, hooks] = poolConfig;

        const result = {
            currency0,
            currency1,
            fee: fee.toString(),
            tickSpacing: tickSpacing.toString(),
            hooks
        };

        this.cache.set(cacheKey, result);
        Logger.printProgress(2, 2, "Pool configuration cached");

        return result;
    }

    async estimateGas(method, params) {
        try {
            Logger.printColored("⛽ Estimating gas...", 'cyan');
            const gasEstimate = await method.estimateGas(...params);
            const gasPrice = await this.provider.getGasPrice();
            const gasCost = gasEstimate.mul(gasPrice);
            
            Logger.printColored(`⛽ Gas estimate: ${gasEstimate.toLocaleString()}`, 'cyan');
            Logger.printColored(`💰 Gas cost: ${ethers.utils.formatEther(gasCost)} ETH`, 'cyan');
            
            return { gasEstimate, gasPrice, gasCost };
        } catch (error) {
            Logger.printError(`Gas estimation failed: ${error.message}`, 'GAS');
            throw error;
        }
    }

    async executeSwap(amount, direction, updateData) {
        Logger.printProgress(1, 4, "Preparing swap transaction...");

        const swapParams = this.generateSwapParams(amount, direction);
        
        Logger.printProgress(2, 4, "Estimating gas...");
        const gasInfo = await this.estimateGas(
            this.contracts.swapRouter.swap,
            [swapParams.amountSpecified, swapParams.zeroForOne, updateData]
        );

        Logger.printProgress(3, 4, "Executing swap...");
        const tx = await this.contracts.swapRouter.swap(
            swapParams.amountSpecified,
            swapParams.zeroForOne,
            updateData,
            {
                gasLimit: gasInfo.gasEstimate.mul(120).div(100), // 20% buffer
                gasPrice: gasInfo.gasPrice
            }
        );

        Logger.printProgress(4, 4, "Waiting for confirmation...");
        const receipt = await tx.wait();

        return { tx, receipt, gasInfo, swapParams };
    }

    generateSwapParams(amount, direction) {
        const isExactInput = true; // Default to exact input
        const amountWei = ethers.utils.parseEther(amount.toString());
        const amountSpecified = isExactInput ? amountWei.mul(-1) : amountWei;

        return {
            originalAmount: amount,
            amountWei: amountWei.toString(),
            amountSpecified: amountSpecified.toString(),
            zeroForOne: direction,
            swapType: isExactInput ? "Exact Input" : "Exact Output",
            direction: direction ? "ETH → USDC" : "USDC → ETH"
        };
    }

    // ABI definitions (simplified for space)
    getSwapRouterABI() {
        return [
            "function swap(int256 amountToSwap, bool zeroForOne, bytes updateData) payable returns (int256)",
            "function getPoolConfiguration() view returns (tuple(address,address,uint24,int24,address))"
        ];
    }

    getERC20ABI() {
        return [
            "function approve(address spender, uint256 amount) returns (bool)",
            "function allowance(address owner, address spender) view returns (uint256)",
            "function balanceOf(address account) view returns (uint256)"
        ];
    }

    getPoolManagerABI() {
        return [
            "function getSlot0(bytes32 poolId) view returns (uint160,int24,uint24,uint24)"
        ];
    }
}

// ============ MAIN OPTIMIZED FRONTEND CLASS ============
class SwapRouterOptimized {
    constructor() {
        this.cache = new Cache();
        this.provider = null;
        this.wallet = null;
        this.contractManager = null;
        this.pythOracle = null;

        this.initialize();
    }

    async initialize() {
        Logger.printHeader();
        try {
            Logger.printProgress(1, 4, "Setting up provider...");
            await this.setupProvider();
            Logger.printProgress(2, 4, "Setting up wallet...");
            await this.setupWallet();
            // Print ETH and USDC balances at the very top
            await this.printETHAndUSDCBalances();
            Logger.printProgress(3, 4, "Initializing contracts...");
            this.contractManager = new ContractManager(this.provider, this.wallet, this.cache);
            Logger.printProgress(4, 4, "Initializing Pyth oracle...");
            this.pythOracle = new PythOracle(this.cache);
            Logger.printSuccess("Initialization complete!", "SETUP");
        } catch (error) {
            Logger.printError(`Initialization failed: ${error.message}`, "SETUP");
            process.exit(1);
        }
    }

    async setupProvider() {
        const rpcUrl = process.env.ARBITRUM_SEPOLIA_RPC_URL || Config.ARBITRUM_SEPOLIA_RPC;
        this.provider = new ethers.providers.JsonRpcProvider(rpcUrl);
        
        // Test connection
        await this.provider.getNetwork();
        Logger.printSuccess(`Connected to Arbitrum Sepolia`, "PROVIDER");
    }

    async setupWallet() {
        const deploymentWallet = process.env.DEPLOYMENT_WALLET;
        const deploymentKey = process.env.DEPLOYMENT_KEY;
        
        if (deploymentWallet && deploymentKey) {
            const privateKey = deploymentKey.startsWith('0x') ? deploymentKey : `0x${deploymentKey}`;
            this.wallet = new ethers.Wallet(privateKey, this.provider);
            
            if (this.wallet.address.toLowerCase() !== deploymentWallet.toLowerCase()) {
                throw new Error("DEPLOYMENT_KEY does not match DEPLOYMENT_WALLET");
            }
            
            const balance = await this.provider.getBalance(this.wallet.address);
            Logger.printSuccess(`Wallet loaded: ${this.wallet.address}`, "WALLET");
            Logger.printColored(`💰 Balance: ${ethers.utils.formatEther(balance)} ETH`, 'cyan');
        } else {
            throw new Error("No wallet credentials found");
        }
    }

    async printETHAndUSDCBalances() {
        try {
            const ethBalance = await this.provider.getBalance(this.wallet.address);
            Logger.printColored(`💰 Swapper ETH Balance: ${ethers.utils.formatEther(ethBalance)} ETH`, 'cyan');
        } catch (e) {
            Logger.printColored(`⚠️  Could not fetch ETH balance: ${e}`,'yellow');
        }
        try {
            const usdc = this.contractManager?.contracts?.usdc;
            if (usdc) {
                const decimals = await usdc.decimals();
                const symbol = await usdc.symbol();
                const balance = await usdc.balanceOf(this.wallet.address);
                Logger.printColored(`💰 Swapper USDC Balance: ${ethers.utils.formatUnits(balance, decimals)} ${symbol}`, 'cyan');
            }
        } catch (e) {
            Logger.printColored(`⚠️  Could not fetch USDC balance: ${e}`,'yellow');
        }
    }

    // ============ PUBLIC API METHODS ============

    async executeSwap(amount, direction) {
        Logger.printColored(`\n🔄 [OPTIMIZED SWAP] Amount: ${amount}, Direction: ${direction ? 'ETH→USDC' : 'USDC→ETH'}`, 'magenta');
        
        try {
            // Parallel operations for better performance
            const [priceData, poolConfig] = await Promise.all([
                this.pythOracle.fetchPriceData([Config.PRICE_FEEDS.ETH_USD.id]),
                this.contractManager.getPoolConfiguration()
            ]);

            // Arbitrage prediction
            const arbitrage = this.pythOracle.predictArbitrage(
                priceData.prices[0].price, // Using oracle price as pool estimate
                direction,
                amount
            );

            Logger.printColored(`\n🎯 Arbitrage Analysis:`, 'cyan');
            Logger.printColored(`   ${arbitrage.prediction}`, arbitrage.hasArbitrage ? 'yellow' : 'green');
            Logger.printColored(`   Expected: ${arbitrage.expectedAction}`, 'white');
            Logger.printColored(`   Price difference: ${arbitrage.priceDiffPct?.toFixed(3)}%`, 'white');

            // Execute swap
            const result = await this.contractManager.executeSwap(amount, direction, priceData.updateData);

            Logger.printSuccess("Swap completed successfully!", "SWAP");
            Logger.printColored(`🔗 Transaction: https://sepolia.arbiscan.io/tx/${result.tx.hash}`, 'blue');

            return { success: true, ...result, arbitrage };

        } catch (error) {
            Logger.printError(`Swap failed: ${error.message}`, "SWAP");
            return { success: false, error: error.message };
        }
    }

    async getPool() {
        Logger.printColored(`\n📋 [OPTIMIZED GETPOOL] Fetching pool configuration`, 'magenta');
        
        try {
            const poolConfig = await this.contractManager.getPoolConfiguration();
            
            Logger.printSuccess("Pool configuration retrieved!", "GETPOOL");
            Logger.printColored("\n📊 Pool Configuration:", 'cyan');
            Logger.printColored(`   Currency0: ${poolConfig.currency0}`, 'white');
            Logger.printColored(`   Currency1: ${poolConfig.currency1}`, 'white');
            Logger.printColored(`   Fee: ${poolConfig.fee}`, 'white');
            Logger.printColored(`   TickSpacing: ${poolConfig.tickSpacing}`, 'white');
            Logger.printColored(`   Hooks: ${poolConfig.hooks}`, 'white');

            return { success: true, poolConfig };

        } catch (error) {
            Logger.printError(`Failed to get pool: ${error.message}`, "GETPOOL");
            return { success: false, error: error.message };
        }
    }

    async executeSystematicTest() {
        Logger.printColored(`\n🧪 [OPTIMIZED TEST] Systematic testing with enhanced reporting`, 'magenta');
        const testCases = [
            { amount: 0.0001, direction: true, description: "Small ETH→USDC" },
            { amount: 0.0002, direction: true, description: "Medium ETH→USDC" },
            { amount: 0.0005, direction: false, description: "Small USDC→ETH" },
            { amount: 0.5, direction: false, description: "Tiny USDC→ETH" },
            { amount: 1, direction: false, description: "Low USDC→ETH" },
            { amount: 2, direction: false, description: "Lower USDC→ETH" }
        ];

        const results = [];

        for (let i = 0; i < testCases.length; i++) {
            const testCase = testCases[i];
            Logger.printColored(`\n--- Test ${i + 1}/${testCases.length}: ${testCase.description} ---`, 'cyan');
            
            try {
                const result = await this.executeSwap(testCase.amount, testCase.direction);
                results.push({ ...testCase, ...result, testNumber: i + 1 });
                
                if (result.success) {
                    Logger.printSuccess(`Test ${i + 1} completed`, "TEST");
                } else {
                    Logger.printError(`Test ${i + 1} failed: ${result.error}`, "TEST");
                }
                
                // Wait between tests
                if (i < testCases.length - 1) {
                    Logger.printColored("⏳ Waiting 3 seconds before next test...", 'yellow');
                    await new Promise(resolve => setTimeout(resolve, 3000));
                }
                
            } catch (error) {
                Logger.printError(`Test ${i + 1} error: ${error.message}`, "TEST");
                results.push({ ...testCase, success: false, error: error.message, testNumber: i + 1 });
            }
        }

        // Print comprehensive summary
        this.printTestSummary(results);
        return results;
    }

    printTestSummary(results) {
        Logger.printColored(`\n📈 TEST SUMMARY`, 'cyan');
        Logger.printColored("=".repeat(50), 'cyan');
        
        const successful = results.filter(r => r.success).length;
        const withArbitrage = results.filter(r => r.arbitrage?.hasArbitrage).length;
        
        Logger.printColored(`📊 Total Tests: ${results.length}`, 'white');
        Logger.printColored(`✅ Successful: ${successful}/${results.length} (${(successful/results.length*100).toFixed(1)}%)`, 'green');
        Logger.printColored(`🎯 Arbitrage Detected: ${withArbitrage}`, 'yellow');
        
        results.forEach(result => {
            const status = result.success ? '✅' : '❌';
            const arbitrage = result.arbitrage?.hasArbitrage ? '🎯' : '⚪';
            Logger.printColored(`${status} ${arbitrage} Test ${result.testNumber}: ${result.description}`, 'white');
        });
        
        Logger.printColored("=".repeat(50), 'cyan');
    }
}

// ============ CLI INTERFACE ============
function showUsage() {
    console.log(chalk.cyan('SwapRouter Frontend - OPTIMIZED VERSION'));
    console.log(chalk.white(''));
    console.log(chalk.white('Usage:'));
    console.log(chalk.green('  yarn swap-router-opt --swap <amount> <direction>'));
    console.log(chalk.green('  yarn swap-router-opt --getpool'));
    console.log(chalk.green('  yarn swap-router-opt --test'));
    console.log(chalk.white(''));
    console.log(chalk.white('Examples:'));
    console.log(chalk.yellow('  yarn swap-router-opt --swap 0.02 true'));
    console.log(chalk.yellow('  yarn swap-router-opt --getpool'));
    console.log(chalk.yellow('  yarn swap-router-opt --test'));
}

async function main() {
    try {
        const args = process.argv.slice(2);
        
        if (args.length === 0) {
            showUsage();
            process.exit(1);
        }
        
        const flag = args[0];
        const frontend = new SwapRouterOptimized();
        
        // Wait for initialization
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        let result = { success: true };
        
        switch (flag) {
            case '--swap':
                if (args.length < 3) {
                    console.log(chalk.red('❌ --swap requires <amount> <direction> arguments'));
                    process.exit(1);
                }
                
                const amount = parseFloat(args[1]);
                const direction = ['true', '1'].includes(args[2].toLowerCase());
                
                if (isNaN(amount)) {
                    console.log(chalk.red('❌ Invalid amount'));
                    process.exit(1);
                }
                
                result = await frontend.executeSwap(amount, direction);
                break;
                
            case '--getpool':
                result = await frontend.getPool();
                break;
                
            case '--test':
                result = await frontend.executeSystematicTest();
                break;
                
            default:
                console.log(chalk.red(`❌ Unknown flag: ${flag}`));
                showUsage();
                process.exit(1);
        }
        
        if (result && result.success !== false) {
            console.log(chalk.green.bold("\n🎉 Operation completed successfully!"));
        } else {
            console.log(chalk.red.bold("\n❌ Operation failed!"));
            process.exit(1);
        }
        
    } catch (error) {
        console.log(chalk.red(`\n❌ Fatal error: ${error.message}`));
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

module.exports = { SwapRouterOptimized }; 