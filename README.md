# 🏗 Scaffold-ETH 2 + DetoxHook

<h4 align="center">
  <a href="https://docs.scaffoldeth.io">Documentation</a> |
  <a href="https://scaffoldeth.io">Website</a> |
  <a href="./DEVELOPMENT.md">DetoxHook Development Guide</a> |
  <a href="./QUICK_REFERENCE.md">Quick Reference</a>
</h4>

## 🦄 DetoxHook - Uniswap V4 MEV Protection

This project implements **DetoxHook**, a Uniswap V4 hook designed to detect and capture MEV (Maximum Extractable Value) for redistribution to liquidity providers. Built for ETHGlobal hackathon.

### 🚀 Quick Start for DetoxHook

```bash
# Start development
yarn dev

# Run tests
yarn test:detox

# Deploy to Arbitrum Sepolia
yarn deploy:arbitrum

# Generate contracts for frontend
yarn generate:contracts
```

**📖 [Full Development Guide](./DEVELOPMENT.md)** - Complete commands and workflows

### ✨ Features

- 🎯 **MEV Detection**: Identifies arbitrage opportunities in real-time
- 🛡️ **MEV Capture**: Captures value before external arbitrageurs
- 💰 **LP Rewards**: Redistributes captured value to liquidity providers
- 🔧 **HookMiner Integration**: Proper CREATE2 deployment with permission flags
- 🌐 **Arbitrum Sepolia**: Deployed and tested on testnet
- 🧪 **Comprehensive Testing**: 37/37 tests passing with fork testing

---

🧪 An open-source, up-to-date toolkit for building decentralized applications (dapps) on the Ethereum blockchain. It's designed to make it easier for developers to create and deploy smart contracts and build user interfaces that interact with those contracts.

⚙️ Built using NextJS, RainbowKit, Foundry, Wagmi, Viem, and Typescript.

- ✅ **Contract Hot Reload**: Your frontend auto-adapts to your smart contract as you edit it.
- 🪝 **[Custom hooks](https://docs.scaffoldeth.io/hooks/)**: Collection of React hooks wrapper around [wagmi](https://wagmi.sh/) to simplify interactions with smart contracts with typescript autocompletion.
- 🧱 [**Components**](https://docs.scaffoldeth.io/components/): Collection of common web3 components to quickly build your frontend.
- 🔥 **Burner Wallet & Local Faucet**: Quickly test your application with a burner wallet and local faucet.
- 🔐 **Integration with Wallet Providers**: Connect to different wallet providers and interact with the Ethereum network.

![Debug Contracts tab](https://github.com/scaffold-eth/scaffold-eth-2/assets/55535804/b237af0c-5027-4849-a5c1-2e31495cccb1)

## Requirements

Before you begin, you need to install the following tools:

- [Node (>= v20.18.3)](https://nodejs.org/en/download/)
- Yarn ([v1](https://classic.yarnpkg.com/en/docs/install/) or [v2+](https://yarnpkg.com/getting-started/install))
- [Git](https://git-scm.com/downloads)

## Quickstart

To get started with Scaffold-ETH 2, follow the steps below:

1. Install dependencies if it was skipped in CLI:

```
cd my-dapp-example
yarn install
```

2. Run a local network in the first terminal:

```
yarn chain
```

This command starts a local Ethereum network using Foundry. The network runs on your local machine and can be used for testing and development. You can customize the network configuration in `packages/foundry/foundry.toml`.

3. On a second terminal, deploy the test contract:

```
yarn deploy
```

This command deploys a test smart contract to the local network. The contract is located in `packages/foundry/contracts` and can be modified to suit your needs. The `yarn deploy` command uses the deploy script located in `packages/foundry/script` to deploy the contract to the network. You can also customize the deploy script.

4. On a third terminal, start your NextJS app:

```
yarn start
```

Visit your app on: `http://localhost:3000`. You can interact with your smart contract using the `Debug Contracts` page. You can tweak the app config in `packages/nextjs/scaffold.config.ts`.

Run smart contract test with `yarn foundry:test`

- Edit your smart contracts in `packages/foundry/contracts`
- Edit your frontend homepage at `packages/nextjs/app/page.tsx`. For guidance on [routing](https://nextjs.org/docs/app/building-your-application/routing/defining-routes) and configuring [pages/layouts](https://nextjs.org/docs/app/building-your-application/routing/pages-and-layouts) checkout the Next.js documentation.
- Edit your deployment scripts in `packages/foundry/script`

## 🚀 Setup Ponder Extension

This extension allows to use Ponder (https://ponder.sh/) for event indexing on an SE-2 dapp.

Ponder is an open-source framework for blockchain application backends. With Ponder, you can rapidly build & deploy an API that serves custom data from smart contracts on any EVM blockchain.

### Config

Ponder config (```packages/ponder/ponder.config.ts```) is set automatically from the deployed contracts and using the first blockchain network setup at ```packages/nextjs/scaffold.config.ts```.

### Design your schema

You can define your Ponder data schema on the file at ```packages/ponder/ponder.schema.ts``` following the Ponder documentation (https://ponder.sh/docs/schema).

### Indexing data

You can index events by adding files to ```packages/ponder/src/``` (https://ponder.sh/docs/indexing/write-to-the-database)

### Start the development server

Run ```yarn ponder:dev``` to start the Ponder development server, for indexing and serving the GraphQL API endpoint at http://localhost:42069

### Query the GraphQL API

With the dev server running, open http://localhost:42069 in your browser to use the GraphiQL interface. GraphiQL is a useful tool for exploring your schema and testing queries during development. (https://ponder.sh/docs/query/graphql)

You can query data on a page using ```@tanstack/react-query```. Check the code at ```packages/nextjs/app/greetings/page.ts``` to get the greetings updates data and show it.

### Deploy

To deploy the Ponder indexer please refer to the Ponder Deploy documentation https://ponder.sh/docs/production/deploy

At **Settings** -> **Deploy** -> you must set **Custom Start Command** to ```yarn ponder:start```.

For faster indexing, you can add the ***startBlock*** to each deployed contract on the file ```packages/nextjs/contracts/deployedContracts.ts```.

And then you have to set up the ```NEXT_PUBLIC_PONDER_URL``` env variable on your SE-2 dapp to use the deployed ponder indexer.


## Documentation

Visit our [docs](https://docs.scaffoldeth.io) to learn how to start building with Scaffold-ETH 2.

To know more about its features, check out our [website](https://scaffoldeth.io).

## Contributing to Scaffold-ETH 2

We welcome contributions to Scaffold-ETH 2!

Please see [CONTRIBUTING.MD](https://github.com/scaffold-eth/scaffold-eth-2/blob/main/CONTRIBUTING.md) for more information and guidelines for contributing to Scaffold-ETH 2.