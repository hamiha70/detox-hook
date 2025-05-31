"use client";

import { useState } from "react";
import type { NextPage } from "next";
import { useAccount } from "wagmi";
import { parseEther, formatEther } from "viem";
import { ArrowUpDownIcon, Cog6ToothIcon } from "@heroicons/react/24/outline";
import { Address, Balance, EtherInput } from "~~/components/scaffold-eth";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import { notification } from "~~/utils/scaffold-eth";

const SwapDashboard: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const [swapAmount, setSwapAmount] = useState("");
  const [updateData, setUpdateData] = useState("");
  const [isSwapping, setIsSwapping] = useState(false);
  const [swapDirection, setSwapDirection] = useState("sell"); // "sell" for ETH->USDC, "buy" for USDC->ETH

  // Read contract data
  const { data: poolConfig } = useScaffoldReadContract({
    contractName: "SwapRouter",
    functionName: "getPoolConfiguration",
  });

  const { data: testSettings } = useScaffoldReadContract({
    contractName: "SwapRouter",
    functionName: "getTestSettings",
  });

  const { writeContractAsync: writeSwapRouterAsync } = useScaffoldWriteContract({
    contractName: "SwapRouter",
  });

  const handleSwap = async () => {
    if (!swapAmount || parseFloat(swapAmount) <= 0) {
      notification.error("Please enter a valid swap amount");
      return;
    }

    if (!connectedAddress) {
      notification.error("Please connect your wallet");
      return;
    }

    try {
      setIsSwapping(true);
      
      // Calculate the amount to swap based on direction
      // For exact input swaps, amount should be negative
      // For exact output swaps, amount should be positive
      const amount = swapDirection === "sell" 
        ? -parseEther(swapAmount) // Negative for exact input (selling ETH)
        : parseEther(swapAmount);  // Positive for exact output (buying specified amount)

      const updateDataBytes = updateData ? updateData : "0x";

      const result = await writeSwapRouterAsync({
        functionName: "swap",
        args: [amount, updateDataBytes],
        value: swapDirection === "sell" ? parseEther(swapAmount) : BigInt(0),
      });

      notification.success("Swap executed successfully!");
      setSwapAmount("");
    } catch (error: any) {
      console.error("Swap failed:", error);
      notification.error(`Swap failed: ${error.message || "Unknown error"}`);
    } finally {
      setIsSwapping(false);
    }
  };

  const toggleSwapDirection = () => {
    setSwapDirection(prev => prev === "sell" ? "buy" : "sell");
    setSwapAmount(""); // Clear amount when switching direction
  };

  return (
    <div className="flex items-center flex-col grow pt-10">
      <div className="px-5 w-full max-w-2xl">
        <h1 className="text-center mb-8">
          <span className="block text-4xl font-bold mb-2">SwapRouter Dashboard</span>
          <span className="block text-lg text-base-content/70">
            Simple ETH ⇄ USDC Swap Interface
          </span>
        </h1>

        {/* Wallet Connection Status */}
        <div className="bg-base-200 rounded-2xl p-6 mb-6">
          <div className="flex justify-center items-center space-x-2 flex-col">
            <p className="my-2 font-medium">Connected Address:</p>
            <Address address={connectedAddress} />
            {connectedAddress && (
              <div className="mt-4 flex space-x-4">
                <div className="text-center">
                  <p className="text-sm text-base-content/70">ETH Balance:</p>
                  <Balance address={connectedAddress} />
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Pool Configuration Display */}
        {poolConfig && (
          <div className="bg-base-200 rounded-2xl p-6 mb-6">
            <h3 className="text-lg font-semibold mb-4 flex items-center">
              <Cog6ToothIcon className="w-5 h-5 mr-2" />
              Pool Configuration
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
              <div>
                <span className="font-medium">Currency0 (ETH):</span>
                <p className="font-mono text-xs break-all">{poolConfig[0]}</p>
              </div>
              <div>
                <span className="font-medium">Currency1 (USDC):</span>
                <p className="font-mono text-xs break-all">{poolConfig[1]}</p>
              </div>
              <div>
                <span className="font-medium">Fee:</span>
                <p>{Number(poolConfig[2]) / 10000}%</p>
              </div>
              <div>
                <span className="font-medium">Tick Spacing:</span>
                <p>{Number(poolConfig[3])}</p>
              </div>
            </div>
          </div>
        )}

        {/* Main Swap Interface */}
        <div className="bg-base-100 rounded-3xl border-2 border-base-300 p-8 shadow-lg">
          <div className="flex justify-between items-center mb-6">
            <h2 className="text-2xl font-bold">Swap</h2>
            <div className="badge badge-primary">
              {swapDirection === "sell" ? "Sell ETH" : "Buy ETH"}
            </div>
          </div>

          {/* Swap Direction Toggle */}
          <div className="flex justify-center mb-6">
            <button
              onClick={toggleSwapDirection}
              className="btn btn-circle btn-outline hover:btn-primary"
              disabled={isSwapping}
            >
              <ArrowUpDownIcon className="w-5 h-5" />
            </button>
          </div>

          {/* Amount Input */}
          <div className="mb-6">
            <label className="block text-sm font-medium mb-2">
              {swapDirection === "sell" ? "Amount to Sell (ETH)" : "Amount to Buy (ETH)"}
            </label>
            <EtherInput
              value={swapAmount}
              onChange={setSwapAmount}
              placeholder="0.0"
            />
            <p className="text-xs text-base-content/50 mt-1">
              {swapDirection === "sell" 
                ? "Enter the amount of ETH you want to sell for USDC"
                : "Enter the amount of ETH you want to buy with USDC"
              }
            </p>
          </div>

          {/* Update Data Input */}
          <div className="mb-6">
            <label className="block text-sm font-medium mb-2">
              Update Data (Optional)
            </label>
            <input
              type="text"
              className="input input-bordered w-full"
              value={updateData}
              onChange={(e) => setUpdateData(e.target.value)}
              placeholder="0x... (Leave empty for no additional data)"
            />
            <p className="text-xs text-base-content/50 mt-1">
              Additional data for price updates or hook data (hex format)
            </p>
          </div>

          {/* Swap Button */}
          <button
            onClick={handleSwap}
            disabled={!connectedAddress || !swapAmount || isSwapping}
            className={`btn btn-primary w-full text-lg py-4 ${isSwapping ? "loading" : ""}`}
          >
            {!connectedAddress
              ? "Connect Wallet"
              : isSwapping
              ? "Swapping..."
              : `Swap ${swapAmount || "0"} ETH`}
          </button>

          {/* Swap Details */}
          {swapAmount && (
            <div className="mt-6 p-4 bg-base-200 rounded-xl">
              <h4 className="font-medium mb-2">Swap Details:</h4>
              <div className="text-sm space-y-1">
                <div className="flex justify-between">
                  <span>Direction:</span>
                  <span>{swapDirection === "sell" ? "ETH → USDC" : "USDC → ETH"}</span>
                </div>
                <div className="flex justify-between">
                  <span>Amount:</span>
                  <span>{swapAmount} ETH</span>
                </div>
                <div className="flex justify-between">
                  <span>Type:</span>
                  <span>{swapDirection === "sell" ? "Exact Input" : "Exact Output"}</span>
                </div>
                <div className="flex justify-between">
                  <span>Pool Fee:</span>
                  <span>{poolConfig ? Number(poolConfig[2]) / 10000 : "0.3"}%</span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Additional Information */}
        <div className="mt-8 text-center text-sm text-base-content/70">
          <p>
            This interface connects to the SwapRouter contract on Arbitrum Sepolia.
            <br />
            Make sure you have sufficient ETH balance and are connected to the correct network.
          </p>
        </div>
      </div>
    </div>
  );
};

export default SwapDashboard; 