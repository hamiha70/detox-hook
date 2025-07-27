.PHONY: build deploy generate-abis get-address account chain compile flatten fork format lint test verify update-frontend-address test-fast test-core test-libs test-integration test-deployment test-all test-gas dev-test ci-test

DEPLOY_SCRIPT ?= script/Deploy.s.sol

# setup wallet for anvil
setup-anvil-wallet:
	shx rm ~/.foundry/keystores/scaffold-eth-default 2>/dev/null; 	shx rm -rf broadcast/Deploy.s.sol/31337
	cast wallet import --private-key 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6 --unsafe-password 'localhost' scaffold-eth-default

# Start local chain
chain: setup-anvil-wallet
	anvil

# Start a fork
fork: setup-anvil-wallet
	anvil --fork-url ${FORK_URL} --chain-id 31337

# Deploy the contracts
deploy:
	@if [ ! -f "$(DEPLOY_SCRIPT)" ]; then 		echo "Error: Deploy script '$(DEPLOY_SCRIPT)' not found"; 		exit 1; 	fi
	@if [ "$(RPC_URL)" = "localhost" ]; then 		if [ "$(ETH_KEYSTORE_ACCOUNT)" = "scaffold-eth-default" ]; then 			forge script $(DEPLOY_SCRIPT) --rpc-url localhost --password localhost --broadcast --legacy --ffi; 		else 			forge script $(DEPLOY_SCRIPT) --rpc-url localhost --broadcast --legacy --ffi; 		fi 	else 		forge script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL) --broadcast --legacy --ffi; 	fi

# Deploy SwapRouter to Arbitrum Sepolia
deploy-swap-router-arbitrum-sepolia:
	@echo "🚀 Deploying SwapRouter to Arbitrum Sepolia..."
	@if [ -z "$(DEPLOYMENT_KEY)" ]; then \
		echo "❌ Error: DEPLOYMENT_KEY environment variable is not set"; \
		echo "   Please set your deployment private key with: export DEPLOYMENT_KEY=0x..."; \
		exit 1; \
	fi
	@echo "📝 Using DEPLOYMENT_KEY for deployment"
	forge script script/DeploySwapRouterFixed.s.sol:DeploySwapRouterFixed \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		--verify \
		--etherscan-api-key $(ARBISCAN_API_KEY) \
		-vvvv

# Test SwapRouter deployment configuration (no broadcast)
test-swap-router-deployment:
	@echo "🧪 Testing SwapRouter deployment configuration..."
	@echo "📋 This will validate deployment parameters without broadcasting"
	forge script script/DeploySwapRouterFixed.s.sol:DeploySwapRouterFixed \
		--sig "testDeployment()" \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		-vvvv

# Update SwapRouter address in frontend after deployment
update-frontend-address:
	@echo "🔄 Updating SwapRouter address in frontend..."
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "❌ Error: CONTRACT_ADDRESS environment variable is not set"; \
		echo "   Usage: CONTRACT_ADDRESS=0x123...abc make update-frontend-address"; \
		exit 1; \
	fi
	cd ../nextjs && node scripts/updateSwapRouterAddress.js $(CONTRACT_ADDRESS)

# Deploy and generate ABIs
deploy-and-generate-abis: deploy generate-abis

# Generate TypeScript ABIs
generate-abis:
	node scripts-js/generateTsAbis.js

# List account
account:
	@node scripts-js/checkAccountBalance.js

# Get address of a keystore
get-address:
	@cast wallet address --account $(ACCOUNT_NAME)

# Compile contracts
compile:
	forge compile

# Flatten contracts
flatten:
	forge flatten

# Format code
format:
	forge fmt && prettier --write ./scripts-js/**/*.js

# Lint code
lint:
	forge fmt --check && prettier --check ./scripts-js/**/*.js

# Run tests
test:
	forge test

# Verify contracts
verify:
	forge script script/VerifyAll.s.sol --ffi --rpc-url $(RPC_URL)

# Deploy DetoxHookV2 (current version) to Arbitrum Sepolia
deploy-detox-hook-v2-arbitrum-sepolia:
	@echo "🚀 DetoxHookV2 Deployment to Arbitrum Sepolia..."
	@if [ -z "$(DEPLOYMENT_KEY)" ]; then \
		echo "❌ Error: DEPLOYMENT_KEY environment variable is not set"; \
		echo "   Please set your deployment private key with: export DEPLOYMENT_KEY=0x..."; \
		exit 1; \
	fi
	@echo "📝 Using DEPLOYMENT_KEY for deployment"
	forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://arbitrum-sepolia.blockscout.com/api \
		-vvvv

# Test DetoxHookV2 deployment configuration (no broadcast)
test-detox-hook-v2-deployment:
	@echo "🧪 Testing DetoxHookV2 deployment configuration..."
	@echo "📋 This will validate deployment parameters without broadcasting"
	forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
		--sig "testDeploymentConfig()" \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		-vvvv

# Initialize pools after hook deployment
initialize-pools-arbitrum-sepolia:
	@echo "🏊 Initializing ETH/USDC pools on Arbitrum Sepolia..."
	@echo "Make sure to set HOOK_ADDRESS environment variable first!"
	forge script script/InitializePools.s.sol:InitializePools \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		-vvvv

# Deploy PoolRegistry to store DetoxHook pool configurations
deploy-pool-registry-arbitrum-sepolia:
	@echo "📋 Deploying PoolRegistry to Arbitrum Sepolia..."
	forge script script/DeployPoolRegistry.s.sol:DeployPoolRegistry \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://arbitrum-sepolia.blockscout.com/api \
		-vvvv

# Initialize pools with existing DetoxHookV2 (production version)
initialize-pools-with-hook-arbitrum-sepolia:
	@echo "🏊 Initializing ETH/USDC pools with existing DetoxHookV2 on Arbitrum Sepolia..."
	@echo "Make sure to set HOOK_ADDRESS environment variable first!"
	@if [ -z "$(HOOK_ADDRESS)" ]; then \
		echo "❌ Error: HOOK_ADDRESS environment variable is not set"; \
		echo "   Please set your hook address with: export HOOK_ADDRESS=0x..."; \
		exit 1; \
	fi
	forge script script/InitializePools.s.sol:InitializePools \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		-vvvv

# Fund DetoxHook with ETH
fund-detox-hook-arbitrum-sepolia:
	@echo "💰 Funding DetoxHook with ETH on Arbitrum Sepolia..."
	@echo "Make sure to set HOOK_ADDRESS environment variable first!"
	@if [ -z "$(HOOK_ADDRESS)" ]; then \
		echo "❌ Error: HOOK_ADDRESS environment variable is not set"; \
		echo "   Please set your hook address with: export HOOK_ADDRESS=0x..."; \
		exit 1; \
	fi
	forge script script/FundDetoxHook.s.sol:FundDetoxHook \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		-vvvv

# SwapRouter Frontend - Pyth-Integrated DEX Interface
swap-router:
	@echo "🔄 Starting SwapRouter Frontend with Pyth Integration..."
	@echo "Usage: make swap-router ARGS='--swap 0.00002 false'"
	@echo "       make swap-router ARGS='--getpool'"
	@echo "       make swap-router ARGS='--wallet 0x...'"
	@if [ -z "$(ARGS)" ]; then \
		node scripts-js/SwapRouterFrontend.cjs; \
	else \
		node scripts-js/SwapRouterFrontend.cjs $(ARGS); \
	fi

# Test commands for rapid development
test-fast:
	@echo "🚀 Running fast tests (unit + integration only)..."
	@forge test --match-contract "DetoxHookV2Test|ArbitrageLibTest|OracleLibTest|SwapRouterIntegrationTest|PriceRegistryTest" -vv

test-core:
	@echo "🔧 Running core hook tests only..."
	@forge test --match-contract "DetoxHookV2Test|DetoxHookArbitrumSepoliaFork" -vv

test-libs:
	@echo "📚 Running library tests only..."
	@forge test --match-contract "ArbitrageLibTest|OracleLibTest" -vv

test-integration:
	@echo "🔗 Running integration tests only..."
	@forge test --match-contract "SwapRouterIntegrationTest|PriceRegistryTest" -vv

test-deployment:
	@echo "🚀 Running deployment tests only..."
	@forge test --match-contract "DeployDetoxHookScriptTest" -vv

test-all:
	@echo "🎯 Running all tests..."
	@forge test --summary

test-gas:
	@echo "⛽ Running tests with gas reporting..."
	@forge test --gas-report

# Development workflow shortcuts
dev-test: test-fast
	@echo "✅ Fast development tests completed!"

ci-test: test-all
	@echo "✅ Full CI test suite completed!"

# ============ DEPLOYMENT VERIFICATION ============

# Verify current Arbitrum Sepolia deployment
verify-deployment-arbitrum-sepolia:
	@echo "🔍 Verifying DetoxHook deployment on Arbitrum Sepolia..."
	@chmod +x script/verify-deployment.sh
	@./script/verify-deployment.sh 421614 $(RPC_URL_421614)

# Verify deployment on any chain (requires CHAIN_ID and RPC_URL)
verify-deployment:
	@echo "🔍 Verifying DetoxHook deployment on chain $(CHAIN_ID)..."
	@if [ -z "$(CHAIN_ID)" ] || [ -z "$(RPC_URL)" ]; then \
		echo "❌ Error: CHAIN_ID and RPC_URL must be set"; \
		echo "   Usage: make verify-deployment CHAIN_ID=421614 RPC_URL=https://..."; \
		exit 1; \
	fi
	@chmod +x script/verify-deployment.sh
	@./script/verify-deployment.sh $(CHAIN_ID) $(RPC_URL)

# Verify using Solidity script (more comprehensive)
verify-deployment-solidity:
	@echo "🔍 Running comprehensive Solidity verification..."
	@forge script script/VerifyDeployment.s.sol:VerifyDeployment \
		--rpc-url $(RPC_URL) \
		-vvv

# Check broadcast files for deployment history
check-broadcast:
	@echo "📁 Checking broadcast files..."
	@find broadcast -name "run-latest.json" -exec echo "Found: {}" \; -exec jq -r '.transactions[] | "Contract: \(.contractName // "Unknown") Address: \(.contractAddress // .to)"' {} \; 2>/dev/null || echo "No broadcast files found or jq not installed"

# Quick deployment status check
deployment-status:
	@echo "📊 DetoxHook Deployment Status"
	@echo "=============================="
	@echo "🏗️  Latest successful deployment addresses:"
	@echo "   DetoxHook: 0xB7d53527Fd072ea45e15FC09101Eb379D3778088"
	@echo "   PriceRegistry: 0x927a871865B739ae9844EA83fC4163a487DB17Fe"
	@echo "   SwapRouterFixed: 0xAaFd63797e2Eaedc2b59386B21ed30e2501A78F1"
	@echo "   MockUSDC: 0x6c00492dF8fcaE1309C7A60CcdeB2E4ECe587Aba"
	@echo ""
	@echo "🔗 Block Explorer Links (Arbitrum Sepolia):"
	@echo "   https://arbitrum-sepolia.blockscout.com/address/0xB7d53527Fd072ea45e15FC09101Eb379D3778088"
	@echo ""
	@echo "📋 To verify deployment, run:"
	@echo "   make verify-deployment-arbitrum-sepolia"

# ============================================================================
# 🔍 CONTRACT VERIFICATION
# ============================================================================

# Verify all contracts on Arbitrum Sepolia
verify-contracts-arbitrum-sepolia:
	@echo "🔍 Verifying all contracts on Arbitrum Sepolia..."
	@source .env && make verify-detoxhook-arbitrum-sepolia
	@source .env && make verify-priceregistry-arbitrum-sepolia  
	@source .env && make verify-swaprouter-arbitrum-sepolia

# Verify DetoxHook on Arbitrum Sepolia
verify-detoxhook-arbitrum-sepolia:
	@echo "🔍 Verifying DetoxHook on Arbitrum Sepolia..."
	@source .env && forge verify-contract $(DETOXHOOK_ADDRESS_421614) src/DetoxHookV2.sol:DetoxHookV2 \
		--chain-id 421614 \
		--constructor-args $$(cast abi-encode "constructor(address,address,address,address)" \
			$(POOL_MANAGER_421614) $(DEPLOYMENT_WALLET_421614) $(PYTH_ORACLE_421614) $(PRICEREGISTRY_ADDRESS_421614)) \
		--verifier blockscout \
		--verifier-url $(VERIFIER_URL_421614)

# Verify PriceRegistry on Arbitrum Sepolia  
verify-priceregistry-arbitrum-sepolia:
	@echo "🔍 Verifying PriceRegistry on Arbitrum Sepolia..."
	@source .env && forge verify-contract $(PRICEREGISTRY_ADDRESS_421614) src/PriceRegistry.sol:PriceRegistry \
		--chain-id 421614 \
		--constructor-args $$(cast abi-encode "constructor(address)" $(DEPLOYMENT_WALLET_421614)) \
		--verifier blockscout \
		--verifier-url $(VERIFIER_URL_421614)

# Verify SwapRouterFixed on Arbitrum Sepolia
verify-swaprouter-arbitrum-sepolia:
	@echo "🔍 Verifying SwapRouterFixed on Arbitrum Sepolia..."
	@source .env && forge verify-contract $(SWAPROUTER_ADDRESS_421614) src/SwapRouterFixed.sol:SwapRouterFixed \
		--chain-id 421614 \
		--constructor-args $$(cast abi-encode "constructor(address,(address,address,uint24,int24,address))" \
			$(POOL_SWAP_TEST_421614) "($(CURRENCY0_421614),$(MOCKUSDC_ADDRESS_421614),500,10,$(DETOXHOOK_ADDRESS_421614))") \
		--verifier blockscout \
		--verifier-url $(VERIFIER_URL_421614)

# Generic verification for any chain (pass CHAIN_ID as parameter)
verify-contracts:
	@echo "🔍 Verifying contracts on chain $(CHAIN_ID)..."
	@if [ "$(CHAIN_ID)" = "421614" ]; then \
		make verify-contracts-arbitrum-sepolia; \
	elif [ "$(CHAIN_ID)" = "11155111" ]; then \
		make verify-contracts-ethereum-sepolia; \
	elif [ "$(CHAIN_ID)" = "1301" ]; then \
		make verify-contracts-unichain-sepolia; \
	else \
		echo "❌ Chain ID $(CHAIN_ID) not supported for verification"; \
		exit 1; \
	fi

# Verify all contracts on Ethereum Sepolia (template)
verify-contracts-ethereum-sepolia:
	@echo "🔍 Verifying all contracts on Ethereum Sepolia..."
	@echo "⚠️  Not implemented yet - add contract addresses to .env first"

# Verify all contracts on Unichain Sepolia (template)
verify-contracts-unichain-sepolia:
	@echo "🔍 Verifying all contracts on Unichain Sepolia..."
	@echo "⚠️  Not implemented yet - add contract addresses to .env first"

