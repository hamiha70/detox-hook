# DetoxHook Realistic ETH/USDC Testing Guide

## Architecture Overview

DetoxHook uses **native ETH + MockUSDC** architecture for comprehensive testing across all environments.

### Core Principles
- **Native ETH**: Always use `address(0)` - "ETH address is 0, we do not use WETH!!! We use real ETH"
- **MockUSDC**: Only mock USDC since "we cannot mint real USDC"
- **Currency Ordering**: `address(0) < any_other_address`, so ETH is always currency0, USDC is currency1

## 🚨 CRITICAL: Liquidity Availability Patterns

### **The Liquidity Reality Check**

After extensive testing, we discovered a critical pattern that affects all DetoxHook testing:

**Problem**: Even with massive liquidity provision (1M USDC worth), actual available liquidity in concentrated pools can be extremely limited due to:
1. **Tick positioning**: Pool initialized at tick -198080 (far from tick 0)
2. **Narrow ranges**: Liquidity concentrated in small tick ranges
3. **Price sensitivity**: "Very high sensitivity for a pool far from price=1 like the ETH/USDC pool"

**Real Example from Testing**:
- **Liquidity provided**: 1,000,000 USDC worth (`liquidityDelta: 1000000000000`)
- **Actual pool balance**: Only 22.5 USDC available for swaps
- **Test failure**: 1000 USDC swap trying to capture 800 USDC arbitrage → underflow

### **Testing Strategy Solutions**

#### **1. Match Swap Amounts to Available Liquidity**
```solidity
// ❌ WRONG: Large swap with limited liquidity
uint256 swapAmount = 1000 * 1e6; // 1000 USDC - pool only has 22 USDC

// ✅ CORRECT: Small swap matching available liquidity  
uint256 swapAmount = 1 * 1e6; // 1 USDC - works with 22 USDC available
```

#### **2. Pre-Swap Balance Validation**
```solidity
// Always check available liquidity before testing
console.log("PoolManager USDC balance:", realUSDC.balanceOf(address(manager)));
console.log("Swap amount:", swapAmount);
console.log("Expected arbitrage capture:", expectedArbitrageAmount);
```

#### **3. Price ID Mapping Validation**
```solidity
// ❌ WRONG: Mismatched price IDs
mockOracle.updatePriceFeeds(ETH_USD_PRICE_ID, ...); // Real price ID
// But pool uses: TOK1_PRICE_ID, TOK2_PRICE_ID

// ✅ CORRECT: Match oracle updates to pool configuration
mockOracle.updatePriceFeeds(TOK1_PRICE_ID, ...); // Matches simple pool
mockOracle.updatePriceFeeds(TOK2_PRICE_ID, ...); // Matches simple pool
```

### **Environment-Specific Strategies**

#### **Local Testing (`forge test`)**
- **Liquidity**: Use `vm.deal()` for unlimited ETH, `mint()` for unlimited USDC
- **Swap sizes**: Start with 1-10 USDC, scale up based on available pool liquidity
- **Debugging**: Full access to balance inspection and tick analysis

#### **Local Anvil**
- **Liquidity**: Pre-funded accounts (~10,000 ETH each)
- **Swap sizes**: Medium amounts (10-100 USDC) depending on pool setup
- **Considerations**: Limited by pre-funded amounts

#### **Live Networks** 
- **Liquidity**: Limited by wallet balances (~1-2 ETH)
- **Swap sizes**: Very small amounts (0.1-1 USDC) for safety
- **Considerations**: Real gas costs, limited funds

## Multi-Environment Support

### Environment Detection
```solidity
// Detect environment and adjust accordingly
if (block.chainid == 31337) {
    // Local Anvil - use pre-funded accounts
    vm.deal(alice, 1000 * 1e18);
} else if (block.chainid == 421614) {
    // Arbitrum Sepolia - use limited amounts
    vm.deal(alice, 1 * 1e18); // Only 1 ETH for safety
}
```

### Liquidity Provision Patterns
```solidity
// Scale liquidity based on environment
uint256 liquidityAmount;
if (isLocalTesting()) {
    liquidityAmount = 1000000 * 1e6; // 1M USDC for comprehensive testing
} else {
    liquidityAmount = 1000 * 1e6;    // 1K USDC for live networks
}
```

## Implementation Details

### Native ETH Integration
```solidity
// ✅ CORRECT: Native ETH setup
Currency ethCurrency = Currency.wrap(address(0));
vm.deal(address(this), ethAmount);
modifyLiquidityRouter.modifyLiquidity{value: ethValueNeeded}(poolKey, params, "");
```

### MockUSDC Integration  
```solidity
// ✅ CORRECT: MockUSDC setup
MockERC20 realUSDC = new MockERC20("USD Coin", "USDC", 6);
realUSDC.mint(address(this), usdcAmount);
realUSDC.approve(address(modifyLiquidityRouter), type(uint256).max);
```

### Price Registry Configuration
```solidity
// ✅ CORRECT: Configure both currencies
priceRegistry.setPriceMapping(address(0), ETH_USD_PRICE_ID, "ETH");
priceRegistry.setPriceMapping(address(realUSDC), USDC_USD_PRICE_ID, "USDC");
```

## Key Success Metrics

### Successful Test Results (DetoxHookV2Test: 6/6 PASSING ✅)
- **test_SetupValidation**: ✅ All components deploy correctly
- **test_RealisticETHUSDCScenario**: ✅ 0.799 USDC captured from 1 USDC swap (~80% rate)
- **test_ArbitrageWhenPoolOverpays**: ✅ 0.52 tokens captured from 1 token swap (~52% rate)
- **test_HookDoesNotInterferWithLiquidity**: ✅ Normal operations unaffected
- **test_NoArbitrageWhenOracleMatchesPool**: ✅ No false positives
- **test_SmallSwapAmounts**: ✅ Handles edge cases correctly

### Example Success Cases
```
# Realistic ETH/USDC Test
Swap amount: 1000000 (1 USDC)
Hook captured: 799994 (0.799 USDC)
Arbitrage rate: ~80% capture ✅

# Simple Pool Arbitrage Test  
Swap amount: 1000000000000000000 (1 token)
Hook captured: 521379310344827586 (~0.52 tokens)
Arbitrage rate: ~52% capture ✅
```

## Testing Strategies and Debugging

### Progressive Testing Approach
1. **Start with setup validation** - ensure all components deploy correctly
2. **Test with minimal amounts** - 1 USDC swaps to validate mechanism
3. **Scale up gradually** - increase amounts based on available liquidity
4. **Add comprehensive scenarios** - various arbitrage conditions

### Common Debugging Patterns
```solidity
// Pre-swap validation
console.log("=== PRE-SWAP VALIDATION ===");
console.log("Pool liquidity:", token.balanceOf(address(manager)));
console.log("Swap amount:", swapAmount);
console.log("Expected arbitrage:", expectedArbitrageAmount);

// Price ID verification
console.log("Oracle price for currency0:", mockOracle.getPriceUnsafe(priceId0));
console.log("Oracle price for currency1:", mockOracle.getPriceUnsafe(priceId1));

// Post-swap analysis
console.log("=== POST-SWAP ANALYSIS ===");
console.log("Hook captured:", hookCapturedAmount);
console.log("ArbitrageCaptured event found:", eventFound);
```

## Remaining Deployment Issues

### **Current Status: 71 tests passed, 3 failed**

#### **❌ Fork Tests (2 failures)**
- **DetoxHookArbitrumSepoliaFork**: `arithmetic underflow or overflow (0x11)` in setUp()
- **DetoxHookUnichainSepoliaFork**: `arithmetic underflow or overflow (0x11)` in setUp()

**Likely Issue**: Same liquidity availability problem, but with real network constraints

#### **❌ SwapRouterIntegrationTest (1 failure)**  
- **Error**: `StdCheats deployCodeTo(string,bytes,uint256,address): Failed to create runtime bytecode`

**Likely Issue**: Deployment script compatibility or missing dependencies

### **Deployment Priority**
1. **Fix fork test liquidity issues** - Apply same small swap amount patterns
2. **Fix SwapRouter deployment** - Ensure all dependencies are correctly deployed
3. **Validate deployment scripts** - Make sure CREATE2 deployment works in all environments

## Critical Insights

### Hook Mechanism Understanding
"Arbitrage opportunity is a part of the input from the swapper that goes to the hook and only the remaining part gets exchanged." - The hook extracts its fair share via `poolManager.take()` and signals this through `BeforeSwapDelta`.

### Liquidity Sensitivity
"Very high sensitivity for a pool far from price=1 like the ETH/USDC pool" - Only small part of provided liquidity might be in range around current price.

### Architecture Constraints
Core hook logic/libraries are "thoroughly tested and should be assumed correct" - only modify tests, setup, and deployment scripts.

---

**🛡️ Remember: Always validate available liquidity before testing arbitrage scenarios. Start small and scale up based on actual pool conditions.** 