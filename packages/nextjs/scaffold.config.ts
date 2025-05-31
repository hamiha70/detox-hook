import * as chains from "viem/chains";

export type ScaffoldConfig = {
  targetNetworks: readonly chains.Chain[];
  pollingInterval: number;
  alchemyApiKey: string;
  rpcOverrides?: Record<number, string>;
  walletConnectProjectId: string;
  onlyLocalBurnerWallet: boolean;
  blockExplorers?: { [chainId: number]: { name: string; url: string } };
};

export const DEFAULT_ALCHEMY_API_KEY = "oKxs-03sij-U_N0iOlrSsZFr29-IqbuF";

const scaffoldConfig = {
  // The networks on which your DApp is live
  // Prioritizing Arbitrum Sepolia where SwapRouter is deployed
  targetNetworks: [chains.arbitrumSepolia],

  // The interval at which your front-end polls the RPC servers for new data
  // Shorter polling for better UX on testnet
  pollingInterval: 15000,

  // This is ours Alchemy's default API key.
  // You can get your own at https://dashboard.alchemyapi.io
  // It's recommended to store it in an env variable:
  // .env.local for local testing, and in the Vercel/system env config for live apps.
  alchemyApiKey: process.env.NEXT_PUBLIC_ALCHEMY_API_KEY || DEFAULT_ALCHEMY_API_KEY,

  // Optimized RPC for Arbitrum Sepolia
  rpcOverrides: {
    [chains.arbitrumSepolia.id]: "https://sepolia-rollup.arbitrum.io/rpc",
  },

  // This is ours WalletConnect's default project ID.
  // You can get your own at https://cloud.walletconnect.com
  // It's recommended to store it in an env variable:
  // .env.local for local testing, and in the Vercel/system env config for live apps.
  walletConnectProjectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || "3a8170812b534d0ff9d794f19a901d64",

  // Allow burner wallet for testing on Arbitrum Sepolia
  onlyLocalBurnerWallet: false,

  // Custom block explorers for specific networks
  // Override the default block explorer for any network
  blockExplorers: {
    [chains.arbitrumSepolia.id]: {
      name: "Arbitrum Sepolia Blockscout",
      url: "https://arbitrum-sepolia.blockscout.com",
    },
  } as { [chainId: number]: { name: string; url: string } },
} as const satisfies ScaffoldConfig;

export default scaffoldConfig;
