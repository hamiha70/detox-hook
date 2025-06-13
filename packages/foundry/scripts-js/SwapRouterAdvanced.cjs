#!/usr/bin/env node

/**
 * SwapRouterAdvanced.cjs - Advanced Swap Router with Comprehensive Configuration
 * 
 * FEATURES:
 * ✅ Multiple currency support (ETH, USDC, custom tokens)
 * ✅ Exact input and exact output swaps
 * ✅ Both swap directions (zeroForOne, oneForZero)
 * ✅ Configurable price feeds and oracle data
 * ✅ Advanced command-line parameter management
 * ✅ Preset configurations for common scenarios
 * ✅ Real-time validation and gas estimation
 * ✅ Comprehensive logging and error handling
 * 
 * Usage Examples:
 *     # Basic swaps
 *     yarn swap-advanced --preset eth-to-usdc --amount 0.01
 *     yarn swap-advanced --preset usdc-to-eth --amount 50
 *     
 *     # Advanced configuration
 *     yarn swap-advanced --currency0 ETH --currency1 USDC --amount 0.01 --exact-input --zero-for-one
 *     yarn swap-advanced --currency0 USDC --currency1 ETH --amount 50 --exact-output --one-for-zero
 *     
 *     # Custom configurations
 *     yarn swap-advanced --config custom-pool.json --amount 0.01
 *     yarn swap-advanced --list-presets
 *     yarn swap-advanced --validate-config
 */

const { ethers } = require('ethers');
const axios = require('axios');
const dotenv = require('dotenv');
const chalk = require('chalk');
const path = require('path');
const fs = require('fs');
const qs = require('qs');

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../.env') });

class SwapRouterAdvanced {
    // ============ CONFIGURATION PRESETS ============
    
    static PRESETS = {
        'eth-to-usdc': {
            currency0: 'ETH',
            currency1: 'USDC',
            swapType: 'exact-input',
            direction: 'zero-for-one',
            description: 'ETH → USDC (exact input)',
            defaultAmount: 0.0001,
            priceFeeds: ['ETH_USD', 'USDC_USD']
        },
        'usdc-to-eth': {
            currency0: 'ETH',
            currency1: 'USDC',
            swapType: 'exact-input',
            direction: 'one-for-zero',
            description: 'USDC → ETH (exact input)',
            defaultAmount: 0.5,
            priceFeeds: ['ETH_USD', 'USDC_USD']
        },
        'eth-to-usdc-exact-out': {
            currency0: 'ETH',
            currency1: 'USDC',
            swapType: 'exact-output',
            direction: 'zero-for-one',
            description: 'ETH → USDC (exact output)',
            defaultAmount: 0.0002,
            priceFeeds: ['ETH_USD', 'USDC_USD']
        },
        'usdc-to-eth-exact-out': {
            currency0: 'ETH',
            currency1: 'USDC',
            swapType: 'exact-output',
            direction: 'one-for-zero',
            description: 'USDC → ETH (exact output)',
            defaultAmount: 1,
            priceFeeds: ['ETH_USD', 'USDC_USD']
        },
        'small-test': {
            currency0: 'ETH',
            currency1: 'USDC',
            swapType: 'exact-input',
            direction: 'zero-for-one',
            description: 'Small test swap (0.0005 ETH)',
            defaultAmount: 0.0005,
            priceFeeds: ['ETH_USD']
        }
    };

    static CURRENCIES = {
        ETH: {
            address: '0x0000000000000000000000000000000000000000',
            symbol: 'ETH',
            decimals: 18,
            name: 'Ethereum'
        },
        USDC: {
            address: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
            symbol: 'USDC',
            decimals: 6,
            name: 'USD Coin'
        }
    };

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
        POOL_MANAGER: "0x7Da1D65F8B249183667cdE74C5CBD46dD38AA829",
        DETOX_HOOK: "0x444F320aA27e73e1E293c14B22EfBDCbce0e0088"
    };

    static NETWORK = {
        RPC_URL: "https://sepolia-rollup.arbitrum.io/rpc",
        CHAIN_ID: 421614,
        PYTH_HERMES: "https://hermes.pyth.network"
    };

    constructor() {
        this.provider = null;
        this.wallet = null;
        this.contracts = {};
        this.config = null;
    }

    // ============ LOGGING UTILITIES ============
    
    printColored(message, color = 'white') {
        const chalkColor = chalk[color] || chalk.white;
        console.log(chalkColor(message));
    }

    printHeader() {
        this.printColored("\n" + "=".repeat(80), 'cyan');
        this.printColored("🚀 Advanced SwapRouter - Multi-Currency & Multi-Type Support", 'cyan');
        this.printColored("=".repeat(80), 'cyan');
        this.printColored(`🌐 Network: Arbitrum Sepolia`, 'green');
        this.printColored(`📅 Session: ${new Date().toISOString()}`, 'gray');
        this.printColored("=".repeat(80) + "\n", 'cyan');
    }

    printConfig(config) {
        this.printColored("📋 SWAP CONFIGURATION", 'cyan');
        this.printColored("-".repeat(50), 'gray');
        this.printColored(`Currency Pair: ${config.currency0} / ${config.currency1}`, 'white');
        this.printColored(`Swap Type: ${config.swapType}`, 'white');
        this.printColored(`Direction: ${config.direction}`, 'white');
        this.printColored(`Amount: ${config.amount} ${config.inputCurrency}`, 'white');
        this.printColored(`Price Feeds: ${config.priceFeeds.join(', ')}`, 'white');
        if (config.description) {
            this.printColored(`Description: ${config.description}`, 'gray');
        }
        this.printColored("-".repeat(50) + "\n", 'gray');
    }

    // ============ CONFIGURATION MANAGEMENT ============

    parseCommandLineArgs() {
        const args = process.argv.slice(2);
        const config = {
            preset: null,
            currency0: null,
            currency1: null,
            amount: null,
            swapType: 'exact-input', // default
            direction: null,
            priceFeeds: [],
            configFile: null,
            validate: false,
            listPresets: false,
            help: false
        };

        for (let i = 0; i < args.length; i++) {
            const arg = args[i];
            const nextArg = args[i + 1];

            switch (arg) {
                case '--preset':
                    config.preset = nextArg;
                    i++;
                    break;
                case '--currency0':
                    config.currency0 = nextArg;
                    i++;
                    break;
                case '--currency1':
                    config.currency1 = nextArg;
                    i++;
                    break;
                case '--amount':
                    config.amount = parseFloat(nextArg);
                    i++;
                    break;
                case '--exact-input':
                    config.swapType = 'exact-input';
                    break;
                case '--exact-output':
                    config.swapType = 'exact-output';
                    break;
                case '--zero-for-one':
                    config.direction = 'zero-for-one';
                    break;
                case '--one-for-zero':
                    config.direction = 'one-for-zero';
                    break;
                case '--price-feeds':
                    config.priceFeeds = nextArg.split(',');
                    i++;
                    break;
                case '--config':
                    config.configFile = nextArg;
                    i++;
                    break;
                case '--validate-config':
                    config.validate = true;
                    break;
                case '--list-presets':
                    config.listPresets = true;
                    break;
                case '--help':
                case '-h':
                    config.help = true;
                    break;
            }
        }

        return config;
    }

    buildSwapConfig(args) {
        let config = {};

        // Start with preset if specified
        if (args.preset) {
            if (!SwapRouterAdvanced.PRESETS[args.preset]) {
                throw new Error(`Unknown preset: ${args.preset}. Use --list-presets to see available options.`);
            }
            config = { ...SwapRouterAdvanced.PRESETS[args.preset] };
            this.printColored(`✅ Using preset: ${args.preset}`, 'green');
        }

        // Override with command line arguments
        if (args.currency0) config.currency0 = args.currency0;
        if (args.currency1) config.currency1 = args.currency1;
        if (args.amount !== null) config.amount = args.amount;
        if (args.swapType) config.swapType = args.swapType;
        if (args.direction) config.direction = args.direction;
        if (args.priceFeeds.length > 0) config.priceFeeds = args.priceFeeds;

        // Load from config file if specified
        if (args.configFile) {
            const fileConfig = this.loadConfigFile(args.configFile);
            config = { ...config, ...fileConfig };
        }

        // Set defaults if not specified
        if (!config.currency0) config.currency0 = 'ETH';
        if (!config.currency1) config.currency1 = 'USDC';
        if (!config.amount) config.amount = config.defaultAmount || 0.01;
        if (!config.swapType) config.swapType = 'exact-input';
        if (!config.direction) {
            // Auto-determine direction based on currencies
            config.direction = 'zero-for-one'; // Default ETH -> USDC
        }
        if (!config.priceFeeds || config.priceFeeds.length === 0) {
            config.priceFeeds = ['ETH_USD'];
        }

        // Validate configuration
        this.validateConfig(config);

        // Add computed properties
        config.zeroForOne = config.direction === 'zero-for-one';
        config.exactInput = config.swapType === 'exact-input';
        config.inputCurrency = config.zeroForOne ? config.currency0 : config.currency1;
        config.outputCurrency = config.zeroForOne ? config.currency1 : config.currency0;

        return config;
    }

    validateConfig(config) {
        // Validate currencies
        if (!SwapRouterAdvanced.CURRENCIES[config.currency0]) {
            throw new Error(`Unknown currency0: ${config.currency0}`);
        }
        if (!SwapRouterAdvanced.CURRENCIES[config.currency1]) {
            throw new Error(`Unknown currency1: ${config.currency1}`);
        }

        // Validate amount
        if (isNaN(config.amount) || config.amount <= 0) {
            throw new Error(`Invalid amount: ${config.amount}`);
        }

        // Validate swap type
        if (!['exact-input', 'exact-output'].includes(config.swapType)) {
            throw new Error(`Invalid swap type: ${config.swapType}`);
        }

        // Validate direction
        if (!['zero-for-one', 'one-for-zero'].includes(config.direction)) {
            throw new Error(`Invalid direction: ${config.direction}`);
        }

        // Validate price feeds
        for (const feed of config.priceFeeds) {
            if (!SwapRouterAdvanced.PRICE_FEEDS[feed]) {
                throw new Error(`Unknown price feed: ${feed}`);
            }
        }
    }

    loadConfigFile(filePath) {
        try {
            const fullPath = path.resolve(filePath);
            const content = fs.readFileSync(fullPath, 'utf8');
            return JSON.parse(content);
        } catch (error) {
            throw new Error(`Failed to load config file ${filePath}: ${error.message}`);
        }
    }

    // ============ INITIALIZATION ============

    async initialize() {
        this.printHeader();
        
        try {
            await this.setupProvider();
            await this.setupWallet();
            await this.setupContracts();
        } catch (error) {
            this.printColored(`❌ Initialization failed: ${error.message}`, 'red');
            throw error;
        }
    }

    async setupProvider() {
        const rpcUrl = process.env.ARBITRUM_SEPOLIA_RPC_URL || SwapRouterAdvanced.NETWORK.RPC_URL;
        this.provider = new ethers.providers.JsonRpcProvider(rpcUrl);
        
        const network = await this.provider.getNetwork();
        if (network.chainId !== SwapRouterAdvanced.NETWORK.CHAIN_ID) {
            throw new Error(`Wrong network: ${network.chainId}, expected: ${SwapRouterAdvanced.NETWORK.CHAIN_ID}`);
        }
        
        this.printColored(`✅ Connected to Arbitrum Sepolia`, 'green');
    }

    async setupWallet() {
        const deploymentWallet = process.env.DEPLOYMENT_WALLET;
        const deploymentKey = process.env.DEPLOYMENT_KEY;
        
        if (!deploymentWallet || !deploymentKey) {
            throw new Error("Missing DEPLOYMENT_WALLET or DEPLOYMENT_KEY");
        }
        
        const privateKey = deploymentKey.startsWith('0x') ? deploymentKey : `0x${deploymentKey}`;
        this.wallet = new ethers.Wallet(privateKey, this.provider);
        
        if (this.wallet.address.toLowerCase() !== deploymentWallet.toLowerCase()) {
            throw new Error("DEPLOYMENT_KEY does not match DEPLOYMENT_WALLET");
        }
        
        const balance = await this.provider.getBalance(this.wallet.address);
        this.printColored(`💰 Swapper ETH Balance: ${ethers.utils.formatEther(balance)} ETH`, 'cyan');
        // Print USDC balance immediately after ETH
        await this.printUSDCBalance();
        this.printColored(`✅ Wallet: ${this.wallet.address} (${ethers.utils.formatEther(balance)} ETH)`, 'green');
    }

    async setupContracts() {
        this.contracts.swapRouter = new ethers.Contract(
            SwapRouterAdvanced.CONTRACTS.SWAP_ROUTER,
            this.getSwapRouterABI(),
            this.wallet
        );

        // Setup currency contracts
        for (const [symbol, currency] of Object.entries(SwapRouterAdvanced.CURRENCIES)) {
            if (currency.address !== ethers.constants.AddressZero) {
                this.contracts[symbol] = new ethers.Contract(
                    currency.address,
                    this.getERC20ABI(),
                    this.wallet
                );
            }
        }

        this.printColored(`✅ Contracts initialized`, 'green');
        // Print USDC balance after contract setup
        await this.printUSDCBalance();
    }

    async printUSDCBalance() {
        try {
            const usdc = this.contracts.USDC;
            const decimals = await usdc.decimals();
            const symbol = await usdc.symbol();
            const balance = await usdc.balanceOf(this.wallet.address);
            this.printColored(`💰 Swapper USDC Balance: ${ethers.utils.formatUnits(balance, decimals)} ${symbol}`, 'cyan');
        } catch (error) {
            this.printColored(`⚠️  Could not fetch USDC balance: ${error.message}`, 'yellow');
        }
    }

    // ============ PYTH ORACLE INTEGRATION ============

    async fetchPythData(priceFeeds) {
        this.printColored(`\n🐍 Fetching Pyth price data for: ${priceFeeds.join(', ')}`, 'cyan');
        
        const feedIds = priceFeeds.map(feed => SwapRouterAdvanced.PRICE_FEEDS[feed].id);
        
        const url = `${SwapRouterAdvanced.NETWORK.PYTH_HERMES}/v2/updates/price/latest`;
        const params = {
            'ids[]': feedIds,
            'encoding': 'hex'
        };
        // Debug log
        this.printColored(`🐍 Hermes request URL: ${url}`, 'yellow');
        this.printColored(`🐍 Hermes request params: ${JSON.stringify(params)}`, 'yellow');
        try {
            const response = await axios.get(url, {
                params,
                paramsSerializer: params => qs.stringify(params, { arrayFormat: 'repeat' }),
                timeout: 10000
            });
            
            if (!response.data.binary || !response.data.parsed) {
                throw new Error("Invalid response format from Hermes API");
            }

            // Process and display price data
            const prices = [];
            for (let i = 0; i < response.data.parsed.length; i++) {
                const parsed = response.data.parsed[i];
                const priceInfo = parsed.price;
                
                const price = parseInt(priceInfo.price) * Math.pow(10, parseInt(priceInfo.expo));
                const confidence = parseInt(priceInfo.conf) * Math.pow(10, parseInt(priceInfo.expo));
                const confidencePct = (confidence / price) * 100;
                
                const feedSymbol = priceFeeds[i];
                prices.push({ feed: feedSymbol, price, confidence: confidencePct });
                
                this.printColored(`   ${SwapRouterAdvanced.PRICE_FEEDS[feedSymbol].symbol}: $${price.toFixed(2)} (±${confidencePct.toFixed(3)}%)`, 'white');
            }

            // Combine update data
            const updateData = response.data.binary.data.length === 1 ? 
                `0x${response.data.binary.data[0]}` :
                `0x${response.data.binary.data.map(d => d).join('')}`;

            return { updateData, prices };

        } catch (error) {
            this.printColored(`❌ Failed to fetch Pyth data: ${error.message}`, 'red');
            throw error;
        }
    }

    // ============ SWAP EXECUTION ============

    async executeSwap(config) {
        this.printConfig(config);
        
        try {
            // 1. Fetch Pyth price data
            const pythData = await this.fetchPythData(config.priceFeeds);
            
            // 2. Prepare swap parameters
            const swapParams = this.prepareSwapParams(config);
            
            // 3. Check token approvals if needed
            await this.checkAndApproveTokens(config);
            
            // 4. Estimate gas
            const gasEstimate = await this.estimateGas(swapParams, pythData.updateData);
            
            // 5. Execute swap
            const result = await this.performSwap(swapParams, pythData.updateData, gasEstimate);
            
            this.printColored(`\n🎉 Swap completed successfully!`, 'green');
            this.printColored(`🔗 Transaction: https://sepolia.arbiscan.io/tx/${result.hash}`, 'blue');
            
            return { success: true, ...result };

        } catch (error) {
            this.printColored(`\n❌ Swap failed: ${error.message}`, 'red');
            return { success: false, error: error.message };
        }
    }

    prepareSwapParams(config) {
        const currency0Info = SwapRouterAdvanced.CURRENCIES[config.currency0];
        const currency1Info = SwapRouterAdvanced.CURRENCIES[config.currency1];
        
        // Determine input currency and decimals
        const inputCurrency = config.zeroForOne ? currency0Info : currency1Info;
        const amountWei = ethers.utils.parseUnits(config.amount.toString(), inputCurrency.decimals);
        
        // For exact input: negative amount, for exact output: positive amount
        const amountSpecified = config.exactInput ? amountWei.mul(-1) : amountWei;
        
        return {
            amountSpecified,
            zeroForOne: config.zeroForOne,
            originalAmount: config.amount,
            inputCurrency: inputCurrency.symbol,
            outputCurrency: config.zeroForOne ? currency1Info.symbol : currency0Info.symbol,
            swapType: config.swapType
        };
    }

    async checkAndApproveTokens(config) {
        // Only need to approve non-ETH tokens
        const inputCurrency = config.zeroForOne ? 
            SwapRouterAdvanced.CURRENCIES[config.currency0] : 
            SwapRouterAdvanced.CURRENCIES[config.currency1];
        
        if (inputCurrency.address === ethers.constants.AddressZero) {
            this.printColored(`💰 Using ETH - no approval needed`, 'gray');
            return;
        }

        const tokenContract = this.contracts[inputCurrency.symbol];
        if (!tokenContract) {
            throw new Error(`Token contract not found for ${inputCurrency.symbol}`);
        }

        const allowance = await tokenContract.allowance(
            this.wallet.address, 
            SwapRouterAdvanced.CONTRACTS.SWAP_ROUTER
        );

        const requiredAmount = ethers.utils.parseUnits(config.amount.toString(), inputCurrency.decimals);
        
        if (allowance.lt(requiredAmount)) {
            this.printColored(`🔓 Approving ${inputCurrency.symbol} for swap...`, 'yellow');
            
            const approveTx = await tokenContract.approve(
                SwapRouterAdvanced.CONTRACTS.SWAP_ROUTER,
                ethers.constants.MaxUint256
            );
            
            await approveTx.wait();
            this.printColored(`✅ ${inputCurrency.symbol} approved`, 'green');
        } else {
            this.printColored(`✅ ${inputCurrency.symbol} already approved`, 'green');
        }
    }

    async estimateGas(swapParams, updateData) {
        this.printColored(`\n⛽ Estimating gas...`, 'cyan');
        
        try {
            const gasEstimate = await this.contracts.swapRouter.estimateGas.swap(
                swapParams.amountSpecified,
                swapParams.zeroForOne,
                updateData
            );
            
            const gasPrice = await this.provider.getGasPrice();
            const gasCost = gasEstimate.mul(gasPrice);
            
            this.printColored(`   Gas estimate: ${gasEstimate.toLocaleString()}`, 'white');
            this.printColored(`   Gas cost: ${ethers.utils.formatEther(gasCost)} ETH`, 'white');
            
            return { gasEstimate, gasPrice };
            
        } catch (error) {
            this.printColored(`❌ Gas estimation failed: ${error.message}`, 'red');
            throw error;
        }
    }

    async performSwap(swapParams, updateData, gasInfo) {
        this.printColored(`\n🔄 Executing swap...`, 'cyan');
        
        const tx = await this.contracts.swapRouter.swap(
            swapParams.amountSpecified,
            swapParams.zeroForOne,
            updateData,
            {
                gasLimit: gasInfo.gasEstimate.mul(120).div(100), // 20% buffer
                gasPrice: gasInfo.gasPrice
            }
        );
        
        this.printColored(`   Transaction sent: ${tx.hash}`, 'white');
        this.printColored(`   Waiting for confirmation...`, 'yellow');
        
        const receipt = await tx.wait();
        
        if (receipt.status === 1) {
            this.printColored(`   ✅ Confirmed in block ${receipt.blockNumber}`, 'green');
            this.printColored(`   ⛽ Gas used: ${receipt.gasUsed.toLocaleString()}`, 'gray');
        } else {
            throw new Error('Transaction failed');
        }
        
        return { hash: tx.hash, receipt };
    }

    // ============ UTILITY FUNCTIONS ============

    listPresets() {
        this.printColored("\n📋 AVAILABLE PRESETS", 'cyan');
        this.printColored("=".repeat(60), 'cyan');
        
        for (const [name, preset] of Object.entries(SwapRouterAdvanced.PRESETS)) {
            this.printColored(`\n${name}:`, 'yellow');
            this.printColored(`   ${preset.description}`, 'white');
            this.printColored(`   Default amount: ${preset.defaultAmount} ${preset.currency0}`, 'gray');
            this.printColored(`   Usage: yarn swap-advanced --preset ${name} --amount <amount>`, 'gray');
        }
        
        this.printColored("\n" + "=".repeat(60), 'cyan');
    }

    showUsage() {
        console.log(chalk.cyan('Advanced SwapRouter - Multi-Currency & Multi-Type Support'));
        console.log(chalk.white(''));
        console.log(chalk.white('Usage:'));
        console.log(chalk.green('  yarn swap-advanced --preset <preset-name> --amount <amount>'));
        console.log(chalk.green('  yarn swap-advanced --currency0 <curr> --currency1 <curr> --amount <amount> [options]'));
        console.log(chalk.white(''));
        console.log(chalk.white('Quick Examples:'));
        console.log(chalk.yellow('  yarn swap-advanced --preset eth-to-usdc --amount 0.01'));
        console.log(chalk.yellow('  yarn swap-advanced --preset usdc-to-eth --amount 50'));
        console.log(chalk.yellow('  yarn swap-advanced --currency0 ETH --currency1 USDC --amount 0.01 --exact-output'));
        console.log(chalk.white(''));
        console.log(chalk.white('Options:'));
        console.log(chalk.white('  --preset <name>           Use predefined configuration'));
        console.log(chalk.white('  --currency0 <symbol>      First currency (ETH, USDC)'));
        console.log(chalk.white('  --currency1 <symbol>      Second currency (ETH, USDC)'));
        console.log(chalk.white('  --amount <number>         Amount to swap'));
        console.log(chalk.white('  --exact-input             Exact input swap (default)'));
        console.log(chalk.white('  --exact-output            Exact output swap'));
        console.log(chalk.white('  --zero-for-one            Swap currency0 → currency1'));
        console.log(chalk.white('  --one-for-zero            Swap currency1 → currency0'));
        console.log(chalk.white('  --price-feeds <feeds>     Comma-separated price feeds'));
        console.log(chalk.white('  --config <file>           Load configuration from JSON file'));
        console.log(chalk.white('  --list-presets            Show available presets'));
        console.log(chalk.white('  --validate-config         Validate configuration only'));
        console.log(chalk.white('  --help, -h                Show this help'));
    }

    // ============ ABI DEFINITIONS ============

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
            "function balanceOf(address account) view returns (uint256)",
            "function symbol() view returns (string)",
            "function decimals() view returns (uint8)"
        ];
    }
}

// ============ MAIN CLI INTERFACE ============

async function main() {
    try {
        const swapRouter = new SwapRouterAdvanced();
        const args = swapRouter.parseCommandLineArgs();
        
        // Handle special commands first
        if (args.help) {
            swapRouter.showUsage();
            process.exit(0);
        }
        
        if (args.listPresets) {
            swapRouter.listPresets();
            process.exit(0);
        }
        
        // Build configuration
        const config = swapRouter.buildSwapConfig(args);
        
        if (args.validate) {
            swapRouter.printColored("✅ Configuration is valid!", 'green');
            swapRouter.printConfig(config);
            process.exit(0);
        }
        
        // Initialize and execute swap
        await swapRouter.initialize();
        const result = await swapRouter.executeSwap(config);
        
        if (!result.success) {
            process.exit(1);
        }
        
    } catch (error) {
        console.log(chalk.red(`\n❌ Error: ${error.message}`));
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

module.exports = { SwapRouterAdvanced }; 