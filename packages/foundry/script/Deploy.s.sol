// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { DeployYourContract } from "./DeployYourContract.s.sol";

/**
 * @notice Main deployment script that orchestrates all contract deployments
 * @dev This script can be used to deploy all contracts in the correct order
 */
contract Deploy {
    function run() external {
        // Deploy DetoxHook (via the updated DeployYourContract script)
        DeployYourContract deployDetoxHook = new DeployYourContract();
        deployDetoxHook.run();
        
        // Add other contract deployments here as needed
        // For example:
        // - Deploy additional hooks
        // - Deploy pool initialization scripts
        // - Deploy frontend helper contracts
    }
}
