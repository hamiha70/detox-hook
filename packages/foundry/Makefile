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
	forge script script/DeploySwapRouter.s.sol:DeploySwapRouter \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		--verify \
		--etherscan-api-key $(ARBISCAN_API_KEY) \
		-vvvv

# Test SwapRouter deployment configuration (no broadcast)
test-swap-router-deployment:
	@echo "🧪 Testing SwapRouter deployment configuration..."
	@echo "📋 This will validate deployment parameters without broadcasting"
	forge script script/DeploySwapRouter.s.sol:DeploySwapRouter \
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

# Deploy DetoxHookV2 Complete (production deployment with all components)
deploy-detox-complete:
	@echo "🚀 Complete DetoxHookV2 Deployment..."
	@echo "⚠️  Note: Using DetoxHookV2.s.sol - the production-ready deployment script"
	forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://arbitrum-sepolia.blockscout.com/api \
		-vvvv

# Deploy DetoxHookV2 Complete to Arbitrum Sepolia
deploy-detox-complete-arbitrum-sepolia:
	@echo "🚀 Complete DetoxHookV2 Deployment to Arbitrum Sepolia..."
	@echo "⚠️  Note: Using DetoxHookV2.s.sol - the production-ready deployment script"
	forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://arbitrum-sepolia.blockscout.com/api \
		-vvvv

# Test DetoxHookV2 Complete deployment on fork
test-detox-complete-fork:
	@echo "🧪 Testing DetoxHookV2 Complete deployment on Arbitrum Sepolia fork..."
	forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
		--fork-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		-vvvv

# Dry run DetoxHookV2 Complete deployment (no broadcast)
dry-run-detox-complete:
	@echo "🔍 Dry run DetoxHookV2 Complete deployment..."
	forge script script/DeployDetoxHookV2.s.sol:DeployDetoxHookV2 \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		-vvvv

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

# Deploy DetoxHook (legacy - use deploy-detox-hook-v2-arbitrum-sepolia instead)
deploy-detox-hook-arbitrum-sepolia:
	@echo "⚠️  WARNING: This target uses legacy deployment script!"
	@echo "⚠️  Please use 'make deploy-detox-hook-v2-arbitrum-sepolia' for production deployment"
	@echo "🚀 Legacy DetoxHook Deployment to Arbitrum Sepolia..."
	forge script script/DeployDetoxHook.s.sol:DeployDetoxHook \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://arbitrum-sepolia.blockscout.com/api \
		-vvvv

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

