# ERC-20 Allowances and Approvals: Complete Guide

## 📋 **Overview**

ERC-20 allowances and approvals are fundamental mechanisms for secure token transfers in Ethereum. This guide explains how they work, when they're required, and the differences between them.

## 🔍 **Core Concepts**

### **1. Approval vs Allowance**

#### **Approval (Action)**
```solidity
// Approval is the ACTION of granting permission
function approve(address spender, uint256 amount) external returns (bool)
```
- **What it is**: A transaction that grants permission
- **Who calls it**: Token owner (msg.sender)
- **What it does**: Sets allowance for a specific spender

#### **Allowance (State)**
```solidity
// Allowance is the STATE of granted permission
mapping(address => mapping(address => uint256)) private _allowances;
```
- **What it is**: The stored permission amount
- **Where it's stored**: In contract storage
- **What it tracks**: How much a spender can transfer

### **2. The Relationship**
```solidity
// Approval sets the allowance
function approve(address spender, uint256 amount) external returns (bool) {
    _approve(msg.sender, spender, amount);
    return true;
}

// Allowance is checked during transferFrom
function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
    _allowances[from][msg.sender] -= amount;
    _transfer(from, to, amount);
    return true;
}
```

## 🏗️ **How Allowances Work**

### **1. Storage Structure**
```solidity
// Nested mapping: owner => spender => amount
mapping(address => mapping(address => uint256)) private _allowances;

// Example:
// _allowances[alice][bob] = 1000
// Alice has approved Bob to spend 1000 tokens
```

### **2. Approval Process**
```solidity
function approve(address spender, uint256 amount) external returns (bool) {
    require(spender != address(0), "Approve to zero address");
    
    _allowances[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    
    return true;
}
```

### **3. Allowance Checking**
```solidity
function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(from != address(0), "Transfer from zero address");
    require(to != address(0), "Transfer to zero address");
    require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
    
    // Decrease allowance
    _allowances[from][msg.sender] -= amount;
    
    // Transfer tokens
    _transfer(from, to, amount);
    
    return true;
}
```

## ⚡ **When Allowances Are Required**

### **1. Direct Transfers (NOT Required)**
```solidity
// Owner transfers their own tokens - NO allowance needed
function transfer(address to, uint256 amount) external returns (bool) {
    require(_balances[msg.sender] >= amount, "Insufficient balance");
    _transfer(msg.sender, to, amount);
    return true;
}
```

### **2. Delegated Transfers (REQUIRED)**
```solidity
// Third party transfers on behalf of owner - ALLOWANCE required
function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
    _allowances[from][msg.sender] -= amount;
    _transfer(from, to, amount);
    return true;
}
```

### **3. Smart Contract Interactions (REQUIRED)**
```solidity
// When contracts need to move user tokens
contract LiquidityRouter {
    function addLiquidity(PoolKey calldata key, ...) external {
        // Contract needs allowance to move user's USDC
        IERC20(USDC_ADDRESS).transferFrom(msg.sender, address(this), usdcAmount);
    }
}
```

## 🔄 **Allowance Lifecycle**

### **1. Initial State**
```solidity
// No allowance granted
_allowances[alice][bob] = 0;
// Bob cannot transfer Alice's tokens
```

### **2. Granting Approval**
```solidity
// Alice approves Bob for 1000 tokens
alice.approve(bob, 1000);
// _allowances[alice][bob] = 1000;
```

### **3. Using Allowance**
```solidity
// Bob transfers 500 tokens on Alice's behalf
bob.transferFrom(alice, charlie, 500);
// _allowances[alice][bob] = 500; (1000 - 500)
```

### **4. Revoking Approval**
```solidity
// Alice revokes Bob's allowance
alice.approve(bob, 0);
// _allowances[alice][bob] = 0;
```

## 🛡️ **Security Considerations**

### **1. Double-Spend Protection**
```solidity
// Without allowance checking:
function transferFrom(address from, address to, uint256 amount) external {
    // DANGEROUS: No allowance check
    _transfer(from, to, amount);
}

// With allowance checking:
function transferFrom(address from, address to, uint256 amount) external {
    require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
    _allowances[from][msg.sender] -= amount; // Decrease allowance
    _transfer(from, to, amount);
}
```

### **2. Race Condition Protection**
```solidity
// Safe approval pattern
function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
    _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
    return true;
}

function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
    uint256 currentAllowance = _allowances[msg.sender][spender];
    require(currentAllowance >= subtractedValue, "Decreased allowance below zero");
    _approve(msg.sender, spender, currentAllowance - subtractedValue);
    return true;
}
```

### **3. Zero-Address Protection**
```solidity
function approve(address spender, uint256 amount) external returns (bool) {
    require(spender != address(0), "Approve to zero address");
    _approve(msg.sender, spender, amount);
    return true;
}
```

## 📊 **Practical Examples**

### **1. Uniswap V4 Liquidity Provision**
```solidity
contract LiquidityRouter {
    function addLiquidity(PoolKey calldata key, ...) external {
        // User must approve LiquidityRouter to spend their USDC
        IERC20(USDC_ADDRESS).transferFrom(msg.sender, address(this), usdcAmount);
        
        // User must approve LiquidityRouter to spend their ETH (if wrapped)
        IERC20(WETH_ADDRESS).transferFrom(msg.sender, address(this), wethAmount);
        
        // Router then interacts with PoolManager
        poolManager.modifyLiquidity(key, params);
    }
}
```

### **2. DetoxHook MEV Protection**
```solidity
contract DetoxHook {
    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params) external {
        // Hook needs allowance to take tokens from pool
        poolManager.take(currency0, address(this), amount0);
        poolManager.take(currency1, address(this), amount1);
    }
}
```

### **3. DEX Trading**
```solidity
contract DEX {
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        // User must approve DEX to spend their tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // Execute swap logic
        // ...
        
        // Send output tokens to user
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}
```

## 🔧 **Allowance Management Patterns**

### **1. Infinite Approval**
```solidity
// Grant maximum allowance (gas efficient for frequent interactions)
function approveMax(address spender) external {
    _approve(msg.sender, spender, type(uint256).max);
}
```

### **2. Incremental Approval**
```solidity
// Increase allowance by specific amount
function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
    _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
    return true;
}
```

### **3. Decremental Approval**
```solidity
// Decrease allowance by specific amount
function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
    uint256 currentAllowance = _allowances[msg.sender][spender];
    require(currentAllowance >= subtractedValue, "Decreased allowance below zero");
    _approve(msg.sender, spender, currentAllowance - subtractedValue);
    return true;
}
```

## 🧪 **Testing Allowances**

### **1. Foundry Test Example**
```solidity
contract AllowanceTest is Test {
    MockUSDC token;
    address alice = address(1);
    address bob = address(2);
    
    function setUp() public {
        token = new MockUSDC("MockUSDC", "mUSDC", 6, address(this));
        token.mint(alice, 1000e6);
    }
    
    function testAllowanceFlow() public {
        vm.startPrank(alice);
        
        // Initial state
        assertEq(token.allowance(alice, bob), 0);
        
        // Grant approval
        token.approve(bob, 500e6);
        assertEq(token.allowance(alice, bob), 500e6);
        
        // Use allowance
        vm.stopPrank();
        vm.prank(bob);
        token.transferFrom(alice, bob, 300e6);
        
        // Check remaining allowance
        assertEq(token.allowance(alice, bob), 200e6);
    }
}
```

### **2. JavaScript Testing**
```javascript
async function testAllowance() {
    // Deploy token
    const token = await MockUSDC.deploy("MockUSDC", "mUSDC", 6, owner.address);
    
    // Mint tokens to Alice
    await token.mint(alice.address, ethers.parseUnits("1000", 6));
    
    // Check initial allowance
    expect(await token.allowance(alice.address, bob.address)).to.equal(0);
    
    // Grant approval
    await token.connect(alice).approve(bob.address, ethers.parseUnits("500", 6));
    expect(await token.allowance(alice.address, bob.address)).to.equal(ethers.parseUnits("500", 6));
    
    // Use allowance
    await token.connect(bob).transferFrom(alice.address, bob.address, ethers.parseUnits("300", 6));
    expect(await token.allowance(alice.address, bob.address)).to.equal(ethers.parseUnits("200", 6));
}
```

## 📈 **Gas Optimization**

### **1. Infinite Approvals**
```solidity
// Gas efficient for frequent interactions
function approveMax(address spender) external {
    _approve(msg.sender, spender, type(uint256).max);
}
```

### **2. Batch Approvals**
```solidity
// Approve multiple spenders in one transaction
function approveMultiple(address[] calldata spenders, uint256[] calldata amounts) external {
    require(spenders.length == amounts.length, "Length mismatch");
    for (uint i = 0; i < spenders.length; i++) {
        _approve(msg.sender, spenders[i], amounts[i]);
    }
}
```

### **3. Permit Pattern (EIP-2612)**
```solidity
// Gasless approvals using signatures
function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    require(deadline >= block.timestamp, "Permit expired");
    
    bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
    bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    
    address signer = ecrecover(hash, v, r, s);
    require(signer == owner, "Invalid signature");
    
    _approve(owner, spender, value);
}
```

## 🚨 **Common Mistakes**

### **1. Forgetting to Check Allowance**
```solidity
// WRONG: No allowance check
function transferFrom(address from, address to, uint256 amount) external {
    _transfer(from, to, amount); // Missing allowance check!
}

// CORRECT: Check allowance
function transferFrom(address from, address to, uint256 amount) external {
    require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
    _allowances[from][msg.sender] -= amount;
    _transfer(from, to, amount);
}
```

### **2. Not Decreasing Allowance**
```solidity
// WRONG: Allowance not decreased
function transferFrom(address from, address to, uint256 amount) external {
    require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
    _transfer(from, to, amount); // Missing allowance decrease!
}

// CORRECT: Decrease allowance
function transferFrom(address from, address to, uint256 amount) external {
    require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
    _allowances[from][msg.sender] -= amount; // Decrease allowance
    _transfer(from, to, amount);
}
```

### **3. Race Conditions**
```solidity
// WRONG: Race condition possible
function approve(address spender, uint256 amount) external {
    _allowances[msg.sender][spender] = amount;
}

// CORRECT: Use increaseAllowance/decreaseAllowance
function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
    _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
    return true;
}
```

## 📚 **Summary**

### **Key Differences:**

| Aspect | Approval | Allowance |
|--------|----------|-----------|
| **Type** | Action/Transaction | State/Storage |
| **Purpose** | Grant permission | Track permission |
| **When Required** | For delegated transfers | For delegated transfers |
| **Storage** | Updates allowance mapping | Stored in mapping |
| **Gas Cost** | ~46,000 gas | ~5,000 gas (read) |

### **When Allowances Are Required:**
1. **Third-party transfers** (`transferFrom`)
2. **Smart contract interactions** (DEX, Router, Hook)
3. **Delegated operations** (staking, liquidity provision)
4. **Batch operations** (multiple transfers)

### **When Allowances Are NOT Required:**
1. **Direct transfers** (`transfer`)
2. **Self-operations** (user moving their own tokens)
3. **Contract internal operations** (minting, burning)

---

**This comprehensive guide covers ERC-20 allowances, approvals, security considerations, and practical implementation patterns for DetoxHook development.** 🛡️ 