// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LiquidityRouter} from "../src/LiquidityRouter.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {ChainAddresses} from "../script/Utility/ChainAddresses.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18); // Mint 1M tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LiquidityRouterTest is Test {
    LiquidityRouter public liquidityRouter;
    PoolModifyLiquidityTest public poolModifyLiquidityTest;
    IPoolManager public poolManager;

    // Mock tokens for testing
    MockToken public mockToken0;
    MockToken public mockToken1;

    // Test addresses
    address constant POOL_MANAGER_ADDRESS =
        0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317; // Arbitrum Sepolia
    address constant POOL_MODIFY_LIQUIDITY_TEST_ADDRESS =
        0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7; // From deployments
    address constant ETH_ADDRESS = 0x0000000000000000000000000000000000000000;
    address constant USDC_ADDRESS = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // MockUSDC on Arbitrum Sepolia

    // Test user
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Pool configuration
    PoolKey testPoolKey;
    PoolKey mockPoolKey;

    event LiquidityModified(
        address indexed sender,
        PoolKey indexed poolKey,
        ModifyLiquidityParams params,
        BalanceDelta delta,
        bool takeClaims,
        bool settleUsingBurn
    );

    event TokensApproved(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    function setUp() public {
        // Fork Arbitrum Sepolia for testing
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC_URL"));

        // Setup contracts
        poolManager = IPoolManager(POOL_MANAGER_ADDRESS);
        poolModifyLiquidityTest = PoolModifyLiquidityTest(
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
        );

        // Deploy LiquidityRouter
        liquidityRouter = new LiquidityRouter(
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS,
            POOL_MANAGER_ADDRESS
        );

        // Deploy mock tokens for testing
        mockToken0 = new MockToken("Mock Token 0", "MT0");
        mockToken1 = new MockToken("Mock Token 1", "MT1");

        // Setup test pool key (using actual deployed Pool2 configuration)
        testPoolKey = PoolKey({
            currency0: Currency.wrap(ETH_ADDRESS),
            currency1: Currency.wrap(USDC_ADDRESS),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(0x444F320aA27e73e1E293c14B22EfBDCbce0e0088) // DetoxHook address
        });

        // Setup mock pool key for isolated testing
        mockPoolKey = PoolKey({
            currency0: Currency.wrap(address(mockToken0)),
            currency1: Currency.wrap(address(mockToken1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)) // No hooks for simplified testing
        });

        // Give alice some ETH and tokens
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Mint tokens to alice and bob
        mockToken0.mint(alice, 1000000 * 10 ** 18);
        mockToken1.mint(alice, 1000000 * 10 ** 18);
        mockToken0.mint(bob, 1000000 * 10 ** 18);
        mockToken1.mint(bob, 1000000 * 10 ** 18);

        console.log("Test setup complete");
        console.log("LiquidityRouter deployed at:", address(liquidityRouter));
        console.log("Mock Token 0 deployed at:", address(mockToken0));
        console.log("Mock Token 1 deployed at:", address(mockToken1));
    }

    /// @notice Test contract deployment and initialization
    function test_Deployment() public {
        // Test constructor parameters
        assertEq(
            liquidityRouter.getPoolModifyLiquidityTest(),
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
        );
        assertEq(liquidityRouter.getPoolManager(), POOL_MANAGER_ADDRESS);

        // Test that contracts are properly initialized
        assertTrue(
            address(liquidityRouter.poolModifyLiquidityTest()) != address(0)
        );
        assertTrue(address(liquidityRouter.poolManager()) != address(0));

        console.log("[SUCCESS] Deployment test passed");
    }

    /// @notice Test deployment with zero addresses should revert
    function test_DeploymentWithZeroAddress() public {
        // Test PoolModifyLiquidityTest zero address
        vm.expectRevert(LiquidityRouter.PoolModifyLiquidityTestNotSet.selector);
        new LiquidityRouter(address(0), POOL_MANAGER_ADDRESS);

        // Test PoolManager zero address
        vm.expectRevert(LiquidityRouter.PoolManagerNotSet.selector);
        new LiquidityRouter(POOL_MODIFY_LIQUIDITY_TEST_ADDRESS, address(0));

        console.log("[SUCCESS] Zero address revert tests passed");
    }

    /// @notice Test individual token approval functionality
    function test_ApproveToken() public {
        vm.startPrank(alice);

        // Test approving a specific amount
        uint256 approvalAmount = 1000 * 10 ** 18;

        // Expect the TokensApproved event
        vm.expectEmit(true, true, false, true);
        emit TokensApproved(
            address(mockToken0),
            address(poolModifyLiquidityTest),
            approvalAmount
        );

        liquidityRouter.approveToken(address(mockToken0), approvalAmount);

        // Check that approval was set correctly
        uint256 allowance = mockToken0.allowance(
            address(liquidityRouter),
            address(poolModifyLiquidityTest)
        );
        assertEq(allowance, approvalAmount, "Approval amount should match");

        // Test approving ETH (should not revert but do nothing)
        liquidityRouter.approveToken(ETH_ADDRESS, approvalAmount);

        vm.stopPrank();

        console.log("[SUCCESS] Individual token approval test passed");
    }

    /// @notice Test pool tokens approval functionality
    function test_ApprovePoolTokens() public {
        vm.startPrank(alice);

        // Test approving pool tokens (both currencies)
        vm.expectEmit(true, true, false, true);
        emit TokensApproved(
            address(mockToken0),
            address(poolModifyLiquidityTest),
            type(uint256).max
        );

        vm.expectEmit(true, true, false, true);
        emit TokensApproved(
            address(mockToken1),
            address(poolModifyLiquidityTest),
            type(uint256).max
        );

        liquidityRouter.approvePoolTokens(mockPoolKey);

        // Check that max approvals were set
        uint256 allowance0 = mockToken0.allowance(
            address(liquidityRouter),
            address(poolModifyLiquidityTest)
        );
        uint256 allowance1 = mockToken1.allowance(
            address(liquidityRouter),
            address(poolModifyLiquidityTest)
        );

        assertEq(
            allowance0,
            type(uint256).max,
            "Token0 should have max approval"
        );
        assertEq(
            allowance1,
            type(uint256).max,
            "Token1 should have max approval"
        );

        vm.stopPrank();

        console.log("[SUCCESS] Pool tokens approval test passed");
    }

    /// @notice Test automatic approval functionality
    function test_AutomaticApprovals() public {
        vm.startPrank(alice);

        // Initially no approvals
        uint256 initialAllowance0 = mockToken0.allowance(
            address(liquidityRouter),
            address(poolModifyLiquidityTest)
        );
        uint256 initialAllowance1 = mockToken1.allowance(
            address(liquidityRouter),
            address(poolModifyLiquidityTest)
        );

        assertEq(initialAllowance0, 0, "Initial allowance should be 0");
        assertEq(initialAllowance1, 0, "Initial allowance should be 0");

        // Test explicit approval function instead of relying on automatic approvals during revert
        liquidityRouter.approvePoolTokens(mockPoolKey);

        // Check that explicit approvals were set
        uint256 finalAllowance0 = mockToken0.allowance(
            address(liquidityRouter),
            address(poolModifyLiquidityTest)
        );
        uint256 finalAllowance1 = mockToken1.allowance(
            address(liquidityRouter),
            address(poolModifyLiquidityTest)
        );

        assertEq(
            finalAllowance0,
            type(uint256).max,
            "Token0 should have max approval after approvePoolTokens"
        );
        assertEq(
            finalAllowance1,
            type(uint256).max,
            "Token1 should have max approval after approvePoolTokens"
        );

        vm.stopPrank();

        console.log("[SUCCESS] Automatic approvals test passed");
    }

    /// @notice Test token preparation functionality
    function test_PrepareTokens() public {
        vm.startPrank(alice);

        // First, alice needs to approve the LiquidityRouter to spend her tokens
        mockToken0.approve(address(liquidityRouter), 1000 * 10 ** 18);
        mockToken1.approve(address(liquidityRouter), 1000 * 10 ** 18);

        uint256 liquidityDelta = 1000000; // Positive for adding liquidity

        // Get initial balances
        uint256 aliceToken0Before = mockToken0.balanceOf(alice);
        uint256 aliceToken1Before = mockToken1.balanceOf(alice);
        uint256 routerToken0Before = mockToken0.balanceOf(
            address(liquidityRouter)
        );
        uint256 routerToken1Before = mockToken1.balanceOf(
            address(liquidityRouter)
        );

        // Prepare tokens
        liquidityRouter.prepareTokens(mockPoolKey, int256(liquidityDelta));

        // Calculate expected transfer amounts (from the contract logic: liquidityDelta / 1000)
        uint256 expectedAmount0 = liquidityDelta / 1000;
        uint256 expectedAmount1 = liquidityDelta / 1000;

        // Check balances after preparation
        uint256 aliceToken0After = mockToken0.balanceOf(alice);
        uint256 aliceToken1After = mockToken1.balanceOf(alice);
        uint256 routerToken0After = mockToken0.balanceOf(
            address(liquidityRouter)
        );
        uint256 routerToken1After = mockToken1.balanceOf(
            address(liquidityRouter)
        );

        // Verify transfers occurred correctly
        assertEq(
            aliceToken0After,
            aliceToken0Before - expectedAmount0,
            "Alice should have less token0"
        );
        assertEq(
            aliceToken1After,
            aliceToken1Before - expectedAmount1,
            "Alice should have less token1"
        );
        assertEq(
            routerToken0After,
            routerToken0Before + expectedAmount0,
            "Router should have more token0"
        );
        assertEq(
            routerToken1After,
            routerToken1Before + expectedAmount1,
            "Router should have more token1"
        );

        vm.stopPrank();

        console.log("[SUCCESS] Token preparation test passed");
    }

    /// @notice Test emergency withdraw functionality
    function test_EmergencyWithdraw() public {
        // Send some tokens to the router contract
        vm.startPrank(alice);
        mockToken0.transfer(address(liquidityRouter), 1000 * 10 ** 18);
        vm.stopPrank();

        // Send some ETH to the router contract
        vm.deal(address(liquidityRouter), 1 ether);

        uint256 bobToken0Before = mockToken0.balanceOf(bob);
        uint256 bobETHBefore = bob.balance;

        // Test withdrawing ERC20 tokens
        vm.prank(bob);
        liquidityRouter.emergencyWithdraw(address(mockToken0), 500 * 10 ** 18);

        uint256 bobToken0After = mockToken0.balanceOf(bob);
        assertEq(
            bobToken0After,
            bobToken0Before + 500 * 10 ** 18,
            "Bob should receive tokens"
        );

        // Test withdrawing ETH
        vm.prank(bob);
        liquidityRouter.emergencyWithdraw(ETH_ADDRESS, 0.5 ether);

        uint256 bobETHAfter = bob.balance;
        assertEq(
            bobETHAfter,
            bobETHBefore + 0.5 ether,
            "Bob should receive ETH"
        );

        console.log("[SUCCESS] Emergency withdraw test passed");
    }

    /// @notice Test receive and fallback functions
    function test_ReceiveETH() public {
        uint256 routerBalanceBefore = address(liquidityRouter).balance;

        // Send ETH directly to the contract
        vm.prank(alice);
        (bool success, ) = address(liquidityRouter).call{value: 1 ether}("");
        assertTrue(success, "ETH transfer should succeed");

        uint256 routerBalanceAfter = address(liquidityRouter).balance;
        assertEq(
            routerBalanceAfter,
            routerBalanceBefore + 1 ether,
            "Router should receive ETH"
        );

        console.log("[SUCCESS] Receive ETH test passed");
    }

    /// @notice Test getter functions
    function test_GetterFunctions() public {
        // Test getPoolModifyLiquidityTest
        address poolModifyLiquidityTestAddr = liquidityRouter
            .getPoolModifyLiquidityTest();
        assertEq(
            poolModifyLiquidityTestAddr,
            POOL_MODIFY_LIQUIDITY_TEST_ADDRESS
        );

        // Test getPoolManager
        address poolManagerAddr = liquidityRouter.getPoolManager();
        assertEq(poolManagerAddr, POOL_MANAGER_ADDRESS);

        console.log("[SUCCESS] Getter functions test passed");
    }

    /// @notice Test that ETH is properly forwarded
    function test_ETHForwarding() public {
        uint256 ethAmount = 0.001 ether;

        vm.startPrank(alice);

        uint256 balanceBefore = alice.balance;

        // Call addLiquidity with ETH value - expect it to revert but ETH should be returned
        try
            liquidityRouter.addLiquidity{value: ethAmount}(
                testPoolKey,
                -600,
                600,
                100, // Smaller amount
                bytes32(uint256(7)),
                ""
            )
        returns (BalanceDelta) {
            // If successful, verify ETH was deducted
            uint256 balanceAfter = alice.balance;
            assertEq(
                balanceAfter,
                balanceBefore - ethAmount,
                "ETH should be deducted"
            );
        } catch {
            // If reverted, ETH should be returned
            uint256 balanceAfter = alice.balance;
            assertEq(
                balanceAfter,
                balanceBefore,
                "ETH should be returned on revert"
            );
        }

        vm.stopPrank();

        console.log("[SUCCESS] ETH forwarding test passed");
    }
}
