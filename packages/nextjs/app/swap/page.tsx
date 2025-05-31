"use client";

import { useState } from "react";
import type { NextPage } from "next";
import { useAccount, useConnect } from "wagmi";

const SwapDashboard: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const { connect, connectors } = useConnect();
  const [swapAmount, setSwapAmount] = useState("");

  // Function to connect to specific wallet
  const connectToMetaMask = () => {
    const metaMaskConnector = connectors.find(
      connector => connector.name.toLowerCase().includes('metamask')
    );
    if (metaMaskConnector) {
      connect({ connector: metaMaskConnector });
    }
  };

  const connectToWalletConnect = () => {
    const walletConnectConnector = connectors.find(
      connector => connector.name.toLowerCase().includes('walletconnect')
    );
    if (walletConnectConnector) {
      connect({ connector: walletConnectConnector });
    }
  };

  return (
    <div className="flex items-center flex-col grow pt-10">
      <div className="px-5 w-full max-w-2xl">
        <h1 className="text-center mb-8">
          <span className="block text-4xl font-bold mb-2">SwapRouter Dashboard</span>
          <span className="block text-lg text-base-content/70">
            ETH ⇄ USDC Swap on Arbitrum Sepolia
          </span>
        </h1>

        {/* Network Status */}
        <div className="alert alert-info mb-6">
          <span>📡 Connected to: <strong>Arbitrum Sepolia</strong></span>
          <span>🏦 Contract: <code className="text-xs">0xAe91...5443</code></span>
        </div>

        {/* Wallet Connection Status */}
        <div className="bg-base-200 rounded-2xl p-6 mb-6">
          <div className="flex justify-center items-center space-x-2 flex-col">
            <p className="my-2 font-medium">Connected Address:</p>
            {connectedAddress ? (
              <code className="text-xs bg-base-300 p-2 rounded">{connectedAddress}</code>
            ) : (
              <div className="space-y-2">
                <p className="text-base-content/50">Not connected</p>
                {/* Specific Wallet Connection Buttons */}
                <div className="flex gap-2 flex-wrap justify-center">
                  <button
                    onClick={connectToMetaMask}
                    className="btn btn-sm btn-outline"
                  >
                    🦊 MetaMask
                  </button>
                  <button
                    onClick={connectToWalletConnect}
                    className="btn btn-sm btn-outline"
                  >
                    🔗 WalletConnect
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Main Swap Interface */}
        <div className="bg-base-100 rounded-3xl border-2 border-base-300 p-8 shadow-lg">
          <h2 className="text-2xl font-bold mb-6">Swap Interface</h2>
          <p className="mb-4">SwapRouter contract is ready for testing.</p>
          
          <div className="mb-6">
            <label className="block text-sm font-medium mb-2">
              Amount to Swap (ETH)
            </label>
            <input
              type="number"
              className="input input-bordered w-full"
              value={swapAmount}
              onChange={(e) => setSwapAmount(e.target.value)}
              placeholder="0.0"
              step="0.01"
            />
          </div>

          <button
            disabled={!connectedAddress || !swapAmount}
            className="btn btn-primary w-full text-lg py-4"
          >
            {!connectedAddress
              ? "Connect Wallet to Swap"
              : `Ready to Swap ${swapAmount || "0"} ETH`}
          </button>
        </div>

        {/* Additional Information */}
        <div className="mt-8 text-center text-sm text-base-content/70">
          <p className="mb-2">
            🔗 This interface connects to the SwapRouter contract on <strong>Arbitrum Sepolia</strong>
          </p>
          <p className="mb-2">
            📝 Contract Address: <code>0xAe91123dD0930b3bEa45dB227522839A9e095443</code>
          </p>
          <p>
            ⚠️ Make sure you have sufficient ETH balance and are connected to Arbitrum Sepolia network
          </p>
        </div>
      </div>
    </div>
  );
};

export default SwapDashboard; 