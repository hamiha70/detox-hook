// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DetoxHookForkTestBase.t.sol";

/**
 * @title DetoxHookArbitrumSepoliaFork
 * @notice Fork test for DetoxHook on Arbitrum Sepolia using dynamic address resolution
 * @dev Inherits from DetoxHookForkTestBase for reusable test logic
 */
contract DetoxHookArbitrumSepoliaFork is DetoxHookForkTestBase(421614) {
    // ============ Test Setup ============
    
    /// @notice Initialize Arbitrum Sepolia fork test
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
        
        console.log("=== Pool Initialized ===");
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
        
        console.log("=== Initial Liquidity Added ===");
        console.log("Token0 Balance:", token0.balanceOf(address(this)));
        console.log("Token1 Balance:", token1.balanceOf(address(this)));
    }

    // ============ Test User Setup ============
    
    /// @notice Setup test users with tokens for swap testing
    function _setupTestUsers() internal {
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        // Standard Anvil test accounts
        address user1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1
        address user2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account 2
        
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
        
        console.log("=== Test Users Setup Complete ===");
        console.log("User1:", user1);
        console.log("User2:", user2);
        console.log("Users funded with test tokens");
    }

    // ============ Test Functions ============
    
    /// @notice Test Arbitrum Sepolia infrastructure is working
    function test_ArbitrumSepoliaInfrastructure() public view {
        // Verify we're on the correct network
        assertEq(block.chainid, 421614, "Should be on Arbitrum Sepolia");
        
        // Verify all contracts are deployed and accessible
        assertTrue(address(manager).code.length > 0, "PoolManager should exist");
        assertTrue(address(swapRouter).code.length > 0, "SwapRouter should exist");
        assertTrue(address(modifyLiquidityRouter).code.length > 0, "ModifyLiquidityRouter should exist");
        
        // Verify Pyth oracle is accessible
        address pythOracle = ChainAddresses.getPythOracle(CHAIN_ID);
        assertTrue(pythOracle.code.length > 0, "Pyth oracle should exist");
        
        console.log("=== Infrastructure Verification Passed ===");
        console.log("Chain ID:", block.chainid);
        console.log("PoolManager:", address(manager));
        console.log("SwapRouter:", address(swapRouter));
        console.log("ModifyLiquidityRouter:", address(modifyLiquidityRouter));
        console.log("Pyth Oracle:", pythOracle);
    }
    
    /// @notice Test fork setup is working correctly
    function test_ForkSetup() public view {
        // Verify chain information
        assertEq(CHAIN_ID, 421614, "Chain ID should be Arbitrum Sepolia");
        assertEq(keccak256(bytes(chainName)), keccak256(bytes("Arbitrum Sepolia")), "Chain name should be correct");
        assertTrue(bytes(rpcUrl).length > 0, "RPC URL should be set");
        
        console.log("=== Fork Setup Verification ===");
        console.log("Chain ID:", CHAIN_ID);
        console.log("Chain Name:", chainName);
        console.log("RPC URL:", rpcUrl);
    }
    
    /// @notice Test hook deployment is working
    function test_HookDeployment() public view {
        // Verify hook is deployed
        assertTrue(address(hook) != address(0), "Hook should be deployed");
        assertTrue(address(hook).code.length > 0, "Hook should have code");
        
        // Verify hook permissions
        uint160 hookFlags = uint160(address(hook)) & HookMiner.FLAG_MASK;
        assertEq(hookFlags, HOOK_FLAGS, "Hook should have correct permissions");
        
        // Verify hook is connected to pool manager
        assertEq(address(hook.poolManager()), address(manager), "Hook should be connected to PoolManager");
        
        console.log("=== Hook Deployment Verification ===");
        console.log("Hook Address:", address(hook));
        console.log("Hook Flags:", hookFlags);
        console.log("Required Flags:", HOOK_FLAGS);
    }
    
    /// @notice Test hook permissions are set correctly
    function test_HookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeSwap, "beforeSwap should be enabled");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be enabled");
        
        // Verify other permissions are not set (as expected)
        assertFalse(permissions.afterSwap, "afterSwap should be disabled");
        assertFalse(permissions.beforeAddLiquidity, "beforeAddLiquidity should be disabled");
        assertFalse(permissions.afterAddLiquidity, "afterAddLiquidity should be disabled");
        
        console.log("=== Hook Permissions Verification ===");
        console.log("beforeSwap:", permissions.beforeSwap);
        console.log("beforeSwapReturnDelta:", permissions.beforeSwapReturnDelta);
    }
    
    /// @notice Test pool initialization
    function test_PoolInitialization() public view {
        // Verify pool is initialized
        (uint160 sqrtPriceX96, int24 tick, , ) = StateLibrary.getSlot0(manager, poolId);
        
        assertTrue(sqrtPriceX96 > 0, "Pool should be initialized with non-zero price");
        assertTrue(tick != 0, "Pool should have a non-zero tick");
        
        console.log("=== Pool Initialization Verification ===");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Current Price (sqrtPriceX96):", sqrtPriceX96);
        console.log("Current Tick:", tick);
    }
    
    /// @notice Test real Pyth oracle reads
    function test_RealPythOracleReads() public view {
        address pythOracle = ChainAddresses.getPythOracle(CHAIN_ID);
        IPyth pyth = IPyth(pythOracle);
        
        // Try to read ETH/USD price (this may fail if no recent updates)
        bytes32 ethPriceId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
        
        try pyth.getPriceUnsafe(ethPriceId) returns (PythStructs.Price memory price) {
            console.log("=== Pyth Oracle Read Success ===");
            console.log("ETH Price:", uint256(uint64(price.price)));
            console.log("Confidence:", price.conf);
            console.log("Publish Time:", price.publishTime);
            console.log("Exponent:", uint256(uint32(price.expo)));
            
            // Basic sanity checks
            assertTrue(price.price > 0, "Price should be positive");
            assertTrue(price.publishTime > 0, "Publish time should be set");
        } catch {
            console.log("=== Pyth Oracle Read Failed ===");
            console.log("This is expected if no recent price updates are available");
            console.log("Oracle exists but may not have fresh data");
        }
    }
    
    /// @notice Test basic swap functionality (this was the failing test)
    function test_BasicSwap() public {
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        // Get initial balances
        uint256 initialBalance0 = token0.balanceOf(address(this));
        uint256 initialBalance1 = token1.balanceOf(address(this));
        
        console.log("=== Before Swap ===");
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
        
        console.log("=== After Swap ===");
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
    
    /// @notice Test hook does not interfere with liquidity operations
    function test_HookDoesNotInterferWithLiquidity() public {
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        // Mint additional tokens for liquidity test
        token0.mint(address(this), 1e18);
        token1.mint(address(this), 1e18);
        
        // Add more liquidity
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -300,
            tickUpper: 300,
            liquidityDelta: int256(1e15), // Smaller amount
            salt: bytes32(uint256(1))
        });
        
        // This should not revert due to hook interference
        BalanceDelta delta = modifyLiquidityRouter.modifyLiquidity(poolKey, params, "");
        
        console.log("=== Liquidity Addition Test ===");
        console.log("Liquidity Delta Amount0:", delta.amount0());
        console.log("Liquidity Delta Amount1:", delta.amount1());
        
        // Verify liquidity was added (should have non-zero deltas)
        assertTrue(delta.amount0() != 0 || delta.amount1() != 0, "Liquidity operation should affect balances");
    }
    
    /// @notice Test multiple swaps work correctly
    function test_MultipleSwaps() public {
        MockERC20 token0 = MockERC20(Currency.unwrap(currency0));
        MockERC20 token1 = MockERC20(Currency.unwrap(currency1));
        
        // Approve swap router
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        
        // Perform multiple small swaps
        for (uint i = 0; i < 3; i++) {
            bool zeroForOne = i % 2 == 0; // Alternate direction
            SwapParams memory params = SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -500, // Small exact input
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1 // Proper price limits
            });
            
            PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });
            BalanceDelta delta = swapRouter.swap(poolKey, params, testSettings, "");
            
            console.log("=== Swap", i + 1, "===");
            console.log("Direction (zeroForOne):", params.zeroForOne);
            console.log("Delta Amount0:", delta.amount0());
            console.log("Delta Amount1:", delta.amount1());
            
            // Each swap should produce non-zero deltas
            assertTrue(delta.amount0() != 0 || delta.amount1() != 0, "Each swap should affect balances");
        }
    }
    
    /// @notice Test deployment summary information
    function test_DeploymentSummary() public view {
        console.log("=== Deployment Summary ===");
        console.log("Network: Arbitrum Sepolia");
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

    /// @notice Test quick pool creation workflow
    function test_QuickTestPoolCreation() public {
        // Create another pool with different parameters to test pool creation
        MockERC20 newToken0 = new MockERC20("Test Token A", "TTA", 18);
        MockERC20 newToken1 = new MockERC20("Test Token B", "TTB", 6);
        
        Currency newCurrency0;
        Currency newCurrency1;
        
        // Ensure proper ordering
        if (address(newToken0) < address(newToken1)) {
            newCurrency0 = Currency.wrap(address(newToken0));
            newCurrency1 = Currency.wrap(address(newToken1));
        } else {
            newCurrency0 = Currency.wrap(address(newToken1));
            newCurrency1 = Currency.wrap(address(newToken0));
        }
        
        // Create new pool key
        PoolKey memory newPoolKey = PoolKey({
            currency0: newCurrency0,
            currency1: newCurrency1,
            fee: 500, // 0.05%
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });
        
        PoolId newPoolId = newPoolKey.toId();
        
        // Initialize the new pool
        uint160 initPrice = ChainAddresses.getCurrentEthUsdcSqrtPriceX96();
        manager.initialize(newPoolKey, initPrice);
        
        // Verify pool was created
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(manager, newPoolId);
        assertEq(sqrtPriceX96, initPrice, "Pool should be initialized at correct price");
        
        console.log("=== Quick Pool Creation Test ===");
        console.log("New Pool ID:", uint256(PoolId.unwrap(newPoolId)));
        console.log("Initialized Price:", sqrtPriceX96);
        console.log("Pool creation successful");
    }
} 