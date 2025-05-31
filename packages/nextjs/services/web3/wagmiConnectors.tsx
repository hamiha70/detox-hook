import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import {
  coinbaseWallet,
  ledgerWallet,
  metaMaskWallet,
  rainbowWallet,
  safeWallet,
  walletConnectWallet,
  // Add more wallet imports as needed:
  // trustWallet,
  // phantomWallet,
  // argentWallet,
} from "@rainbow-me/rainbowkit/wallets";
import { rainbowkitBurnerWallet } from "burner-connector";
import * as chains from "viem/chains";
import scaffoldConfig from "~~/scaffold.config";

const { onlyLocalBurnerWallet, targetNetworks } = scaffoldConfig;

// Customize your wallet list here
const wallets = [
  metaMaskWallet,           // 🦊 Most popular
  walletConnectWallet,      // 🔗 Connects to 300+ wallets
  ledgerWallet,             // 🔐 Hardware wallet
  coinbaseWallet,           // 🟦 Coinbase users
  rainbowWallet,            // 🌈 Rainbow users
  safeWallet,               // 🛡️ Multi-sig wallets
  
  // Add more wallets here:
  // trustWallet,           // Trust Wallet
  // phantomWallet,         // Phantom (Solana-focused but supports Ethereum)
  // argentWallet,          // Argent Wallet
  
  // Burner wallet for testing (only on non-mainnet)
  ...(!targetNetworks.some(network => network.id !== (chains.hardhat as chains.Chain).id) || !onlyLocalBurnerWallet
    ? [rainbowkitBurnerWallet]
    : []),
];

/**
 * wagmi connectors for the wagmi context
 * 
 * To add a specific wallet:
 * 1. Import it from "@rainbow-me/rainbowkit/wallets"
 * 2. Add it to the wallets array above
 * 3. Restart your dev server
 * 
 * To remove a wallet:
 * 1. Remove it from the wallets array
 * 2. Restart your dev server
 */
export const wagmiConnectors = connectorsForWallets(
  [
    {
      groupName: "Supported Wallets",
      wallets,
    },
  ],

  {
    appName: "scaffold-eth-2",
    projectId: scaffoldConfig.walletConnectProjectId,
  },
);
