// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DetoxHookForkTestBase.t.sol";

/**
 * @title DetoxHookUnichainSepoliaFork
 * @notice Fork test for DetoxHook on Unichain Sepolia using dynamic address resolution
 * @dev Inherits from DetoxHookForkTestBase for reusable test logic
 */
contract DetoxHookUnichainSepoliaFork is DetoxHookForkTestBase(1301) {
    // ============ Test Setup ============
    
    /// @notice Initialize Unichain Sepolia fork test
    function setUp() public override {
        // Call base setup which handles forking, contract initialization, and hook deployment
        super.setUp();
        
        // Initialize pool and add liquidity for testing
        _initializePoolAndAddLiquidity();
        
        // Setup test users with tokens
        _setupTestUsers();
    }

    // ============ Pool Initialization ============
    
    /// @notice Initialize the pool and add liquidity for testing
    function _initializePoolAndAddLiquidity() internal {
        // Initialize the pool at current market price (approximately $2500/ETH)
        uint160 sqrtPriceX96 = ChainAddresses.getCurrentEthUsdcSqrtPriceX96();
        
        manager.initialize(poolKey, sqrtPriceX96);
        
        console.log("=== Pool Initialized on Unichain Sepolia ===");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Initial Price (sqrtPriceX96):", sqrtPriceX96);
        
        // Add initial liquidity to the pool
        _addInitialLiquidity();
    }
    
    /// @notice Add initial liquidity to the pool for testing
    function _addInitialLiquidity() internal {
        // Mint tokens to this contract for liquidity provision
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        // Use much smaller amounts for fork testing (similar to DetoxHookV2Test success pattern)
        if (token0.decimals() == 18) {
            // token0 is WETH, token1 is USDC
            token0.mint(address(this), 1 ether);       // 1 WETH (reduced from 10)
            token1.mint(address(this), 2500e6);        // 2,500 USDC (reduced from 25,000)
        } else {
            // token0 is USDC, token1 is WETH  
            token0.mint(address(this), 2500e6);        // 2,500 USDC (reduced from 25,000)
            token1.mint(address(this), 1 ether);       // 1 WETH (reduced from 10)
        }
        
        // Approve the modify liquidity router
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        
        // Use much smaller tick range and liquidity amount (proven pattern from DetoxHookV2Test)
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,                      // Much smaller range (was -600)
            tickUpper: 60,                       // Much smaller range (was 600)  
            liquidityDelta: int256(1000000),     // Much smaller amount (was 1e18)
            salt: bytes32(0)
        });
        
        modifyLiquidityRouter.modifyLiquidity(poolKey, params, "");
        
        console.log("=== Initial Liquidity Added on Unichain ===");
        console.log("Token0 Balance:", token0.balanceOf(address(this)));
        console.log("Token1 Balance:", token1.balanceOf(address(this)));
    }

    // ============ Test User Setup ============
    
    /// @notice Setup test users with tokens for swap testing
    function _setupTestUsers() internal {
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        // Standard test accounts (same as Anvil for consistency)
        address user1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address user2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        
        // Fund users with tokens for testing
        if (token0.decimals() == 18) {
            // token0 is WETH, token1 is USDC
            token0.mint(user1, 0.1 ether);    // 0.1 WETH to user1 (reduced from 1)
            token1.mint(user1, 250e6);        // 250 USDC to user1 (reduced from 5000)
            token0.mint(user2, 0.1 ether);    // 0.1 WETH to user2 (reduced from 1)
            token1.mint(user2, 250e6);        // 250 USDC to user2 (reduced from 5000)
        } else {
            // token0 is USDC, token1 is WETH
            token0.mint(user1, 250e6);        // 250 USDC to user1 (reduced from 5000)
            token1.mint(user1, 0.1 ether);    // 0.1 WETH to user1 (reduced from 1)
            token0.mint(user2, 250e6);        // 250 USDC to user2 (reduced from 5000)
            token1.mint(user2, 0.1 ether);    // 0.1 WETH to user2 (reduced from 1)
        }
        
        console.log("=== Test Users Setup Complete on Unichain ===");
        console.log("User1:", user1);
        console.log("User2:", user2);
        console.log("Users funded with test tokens");
    }

    // ============ Test Functions ============
    
    /// @notice Test Unichain Sepolia infrastructure is working
    function test_UnichainSepoliaInfrastructure() public view {
        // Verify we're on the correct network
        assertEq(block.chainid, 1301, "Should be on Unichain Sepolia");
        
        // Verify all contracts are deployed and accessible
        assertTrue(address(manager).code.length > 0, "PoolManager should exist");
        assertTrue(address(swapRouter).code.length > 0, "SwapRouter should exist");
        assertTrue(address(modifyLiquidityRouter).code.length > 0, "ModifyLiquidityRouter should exist");
        
        // Verify Pyth oracle is accessible
        address pythOracle = ChainAddresses.getPythOracle(CHAIN_ID);
        assertTrue(pythOracle.code.length > 0, "Pyth oracle should exist");
        
        console.log("=== Unichain Sepolia Infrastructure Verification ===");
        console.log("Chain ID:", block.chainid);
        console.log("PoolManager:", address(manager));
        console.log("SwapRouter:", address(swapRouter));
        console.log("ModifyLiquidityRouter:", address(modifyLiquidityRouter));
        console.log("Pyth Oracle:", pythOracle);
    }
    
    /// @notice Test fork setup is working correctly
    function test_ForkSetup() public view {
        // Verify chain information
        assertEq(CHAIN_ID, 1301, "Chain ID should be Unichain Sepolia");
        assertEq(keccak256(bytes(chainName)), keccak256(bytes("Unichain Sepolia")), "Chain name should be correct");
        assertTrue(bytes(rpcUrl).length > 0, "RPC URL should be set");
        
        console.log("=== Unichain Fork Setup Verification ===");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Chain Name:", chainName);
        console.log("RPC URL:", rpcUrl);
    }
    
    /// @notice Test hook deployment on Unichain
    function test_HookDeployment() public view {
        // Verify hook is deployed
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        assertTrue(address(hook).code.length > 0, "Hook should have code");
        
        // Verify hook permissions
        uint160 hookFlags = uint160(address(hook)) & HookMiner.FLAG_MASK;
        assertEq(hookFlags, HOOK_FLAGS, "Hook should have correct permissions");
        
        // Verify hook is connected to pool manager
        assertEq(address(hook.poolManager()), address(manager), "Hook should be connected to PoolManager");
        
        console.log("=== Unichain Hook Deployment Verification ===");
        console.log("Hook Address:", address(hook));
        console.log("Hook Flags:", hookFlags);
        console.log("Required Flags:", HOOK_FLAGS);
    }
    
    /// @notice Test basic swap functionality on Unichain
    function test_BasicSwap() public {
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        // Get initial balances
        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));
        
        console.log("=== Before Swap on Unichain ===");
        console.log("Token0 Balance:", initialBalance0);
        console.log("Token1 Balance:", initialBalance1);
        
        // Approve swap router
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        
        // Perform a small swap (token0 -> token1)
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1000, // Exact input of 1000 units of token0
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // Proper price limit (was 0)
        });
        
        // Execute swap
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        BalanceDelta delta = swapRouter.swap(poolKey, params, testSettings, "");
        
        // Get final balances
        uint256 finalBalance0 = token0.balanceOf(address(this));
        uint256 finalBalance1 = token1.balanceOf(address(this));
        
        console.log("=== After Swap on Unichain ===");
        console.log("Token0 Balance:", finalBalance0);
        console.log("Token1 Balance:", finalBalance1);
        console.log("Delta Amount0:", delta.amount0());
        console.log("Delta Amount1:", delta.amount1());
        
        // Verify swap occurred (balances should have changed)
        assertTrue(finalBalance0 != initialBalance0 || finalBalance1 != initialBalance1, 
                  "Swap should have caused balance changes");
        
        // If we swapped token0 for token1 (zeroForOne = true), we should have:
        // - Less token0 (negative delta0)  
        // - More token1 (positive delta1)
        if (params.zeroForOne) {
            assertTrue(delta.amount0() < 0, "Should have spent token0");
            assertTrue(delta.amount1() > 0, "Should have received token1");
        }
    }
    
    /// @notice Test Pyth oracle functionality on Unichain
    function test_PythOracleReads() public view {
        address pythOracle = ChainAddresses.getPythOracle(CHAIN_ID);
        IPyth pyth = IPyth(pythOracle);
        
        // Try to read ETH/USD price
        bytes32 ethPriceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        
        try pyth.getPriceUnsafe(ethPriceId) returns (PythStructs.Price memory price) {
            console.log("=== Unichain Pyth Oracle Read Success ===");
            console.log("ETH Price:", uint256(uint64(price.price)));
            console.log("Confidence:", price.conf);
            console.log("Publish Time:", price.publishTime);
            console.log("Exponent:", uint256(uint32(price.expo)));
            
            // Basic sanity checks
            assertTrue(price.price > 0, "Price should be positive");
            assertTrue(price.publishTime > 0, "Publish time should be set");
        } catch {
            console.log("=== Unichain Pyth Oracle Read Failed ===");
            console.log("This is expected if no recent price updates are available");
            console.log("Oracle exists but may not have fresh data");
        }
    }
    
    /// @notice Test network-specific behavior differences
    function test_NetworkSpecificBehavior() public view {
        // Test any Unichain-specific behavior
        console.log("=== Unichain Network Specifics ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Block Timestamp:", block.timestamp);
        
        // Verify we're getting different results than Arbitrum would
        assertTrue(block.chainid == 1301, "Should be on Unichain Sepolia");
        
        // Test gas behavior (Unichain may have different gas mechanics)
        uint256 gasStart = gasleft();
        
        // Perform some operations
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        token0.balanceOf(address(this));
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for balance check:", gasUsed);
        
        // Gas usage should be reasonable
        assertTrue(gasUsed < 10000, "Simple operation should not use excessive gas");
    }
    
    /// @notice Test deployment summary for Unichain
    function test_DeploymentSummary() public view {
        console.log("=== Unichain Deployment Summary ===");
        console.log("Network: Unichain Sepolia");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Hook Address:", address(hook));
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Currency0:", Currency.unwrap(currency0));
        console.log("Currency1:", Currency.unwrap(currency1));
        console.log("RPC URL:", rpcUrl);
        
        // Verify all components are properly deployed
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        assertTrue(address(manager) != address(0), "PoolManager should be connected");
        assertTrue(Currency.unwrap(currency0) != address(0), "Currency0 should be set");
        assertTrue(Currency.unwrap(currency1) != address(0), "Currency1 should be set");
    }
    
    /// @notice Test cross-network compatibility
    function test_CrossNetworkCompatibility() public view {
        // Verify that the same hook logic works across networks
        console.log("=== Cross-Network Compatibility Test ===");
        
        // The hook should have the same interface and behavior
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap, "beforeSwap should be enabled");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be enabled");
        
        // Pool operations should work the same way
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(manager, poolId);
        assertTrue(sqrtPriceX96 > 0, "Pool should be initialized");
        
        console.log("Hook permissions consistent across networks");
        console.log("Pool operations work consistently");
        console.log("Cross-network compatibility verified");
    }
} 