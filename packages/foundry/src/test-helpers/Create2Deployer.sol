// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Create2Deployer
 * @notice Simple CREATE2 deployer for testing hook deployments
 * @dev Allows deterministic contract deployment for testing without forking
 */
contract Create2Deployer {
    
    /// @notice Event emitted when a contract is deployed
    event ContractDeployed(address indexed deployedAddress, bytes32 indexed salt, address indexed deployer);
    
    /// @notice Error thrown when deployment fails
    error DeploymentFailed();
    
    /// @notice Error thrown when contract already exists at computed address
    error ContractAlreadyExists(address existingAddress);
    
    /**
     * @notice Deploy a contract using CREATE2
     * @param salt Salt for deterministic address generation
     * @param bytecode Complete contract bytecode (creation code + constructor args)
     * @return deployedAddress Address of the deployed contract
     */
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address deployedAddress) {
        // Compute the address where the contract will be deployed
        deployedAddress = computeAddress(salt, bytecode);
        
        // Check if contract already exists at this address
        if (deployedAddress.code.length > 0) {
            revert ContractAlreadyExists(deployedAddress);
        }
        
        // Deploy the contract using CREATE2
        assembly {
            deployedAddress := create2(
                0,                          // value (ETH to send)
                add(bytecode, 0x20),       // bytecode start (skip length prefix)
                mload(bytecode),           // bytecode length
                salt                       // salt
            )
        }
        
        // Check if deployment was successful
        if (deployedAddress == address(0)) {
            revert DeploymentFailed();
        }
        
        // Emit deployment event
        emit ContractDeployed(deployedAddress, salt, msg.sender);
    }
    
    /**
     * @notice Compute the address where a contract would be deployed
     * @param salt Salt for deterministic address generation
     * @param bytecode Complete contract bytecode (creation code + constructor args)
     * @return computedAddress The address where the contract would be deployed
     */
    function computeAddress(bytes32 salt, bytes memory bytecode) public view returns (address computedAddress) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),              // CREATE2 prefix
                address(this),             // deployer address
                salt,                      // salt
                keccak256(bytecode)        // bytecode hash
            )
        );
        
        // Extract address from hash (last 20 bytes)
        computedAddress = address(uint160(uint256(hash)));
    }
    
    /**
     * @notice Check if a contract exists at a given address
     * @param contractAddress Address to check
     * @return exists Whether a contract exists at the address
     */
    function contractExists(address contractAddress) external view returns (bool exists) {
        return contractAddress.code.length > 0;
    }
    
    /**
     * @notice Get the bytecode hash for a given bytecode
     * @param bytecode Bytecode to hash
     * @return hash The keccak256 hash of the bytecode
     */
    function getBytecodeHash(bytes memory bytecode) external pure returns (bytes32 hash) {
        return keccak256(bytecode);
    }
    
    /**
     * @notice Batch deploy multiple contracts
     * @param salts Array of salts for each deployment
     * @param bytecodes Array of bytecodes for each deployment
     * @return deployedAddresses Array of deployed contract addresses
     */
    function batchDeploy(
        bytes32[] memory salts, 
        bytes[] memory bytecodes
    ) external returns (address[] memory deployedAddresses) {
        require(salts.length == bytecodes.length, "Array length mismatch");
        
        deployedAddresses = new address[](salts.length);
        
        for (uint256 i = 0; i < salts.length; i++) {
            deployedAddresses[i] = this.deploy(salts[i], bytecodes[i]);
        }
    }
    
    /**
     * @notice Batch compute addresses for multiple deployments
     * @param salts Array of salts for each deployment
     * @param bytecodes Array of bytecodes for each deployment
     * @return computedAddresses Array of computed addresses
     */
    function batchComputeAddresses(
        bytes32[] memory salts, 
        bytes[] memory bytecodes
    ) external view returns (address[] memory computedAddresses) {
        require(salts.length == bytecodes.length, "Array length mismatch");
        
        computedAddresses = new address[](salts.length);
        
        for (uint256 i = 0; i < salts.length; i++) {
            computedAddresses[i] = computeAddress(salts[i], bytecodes[i]);
        }
    }
} 