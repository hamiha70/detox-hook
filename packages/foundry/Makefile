.PHONY: build deploy generate-abis get-address account chain compile flatten fork format lint test verify update-frontend-address

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
	@echo "📋 Validating deployment configuration first..."
	@make test-swap-router-deployment
	@echo "📝 Using DEPLOYMENT_KEY for deployment"
	forge script script/DeploySwapRouter.s.sol:DeploySwapRouter \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		--verify \
		--etherscan-api-key $(ARBISCAN_API_KEY) \
		-vvvv

# Deploy SwapRouter without verification (faster for testing)
deploy-swap-router-arbitrum-sepolia-no-verify:
	@echo "🚀 Deploying SwapRouter to Arbitrum Sepolia (no verification)..."
	@if [ -z "$(DEPLOYMENT_KEY)" ]; then \
		echo "❌ Error: DEPLOYMENT_KEY environment variable is not set"; \
		echo "   Please set your deployment private key with: export DEPLOYMENT_KEY=0x..."; \
		exit 1; \
	fi
	@echo "📝 Using DEPLOYMENT_KEY for deployment"
	forge script script/DeploySwapRouter.s.sol:DeploySwapRouter \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		--broadcast \
		-vvvv

# Test SwapRouter deployment configuration (no broadcast)
test-swap-router-deployment:
	@echo "🧪 Testing SwapRouter deployment configuration..."
	@echo "📋 This will validate deployment parameters without broadcasting"
	forge script script/DeploySwapRouter.s.sol:DeploySwapRouter \
		--sig "testDeployment()" \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		-vvvv

# Test SwapRouter contracts locally
test-swap-router:
	@echo "🧪 Running SwapRouter unit tests..."
	forge test --match-contract SwapRouterTest -vvv

# Test deployed SwapRouter functionality
test-deployed-swap-router:
	@echo "🧪 Testing deployed SwapRouter functionality..."
	@if [ -z "$(SWAP_ROUTER_ADDRESS)" ]; then \
		echo "❌ Error: SWAP_ROUTER_ADDRESS environment variable is not set"; \
		echo "   Usage: SWAP_ROUTER_ADDRESS=0x123...abc make test-deployed-swap-router"; \
		exit 1; \
	fi
	forge script script/DeploySwapRouter.s.sol:DeploySwapRouter \
		--sig "testSwapRouterFunctionality(address)" $(SWAP_ROUTER_ADDRESS) \
		--rpc-url https://sepolia-rollup.arbitrum.io/rpc \
		-vvvv

# Complete deployment workflow
deploy-swap-router-complete:
	@echo "🚀 Complete SwapRouter deployment workflow..."
	@echo "1️⃣ Running tests..."
	@make test-swap-router
	@echo "2️⃣ Validating deployment configuration..."
	@make test-swap-router-deployment
	@echo "3️⃣ Deploying to Arbitrum Sepolia..."
	@make deploy-swap-router-arbitrum-sepolia-no-verify
	@echo "✅ Deployment complete! Remember to update frontend with CONTRACT_ADDRESS"

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

