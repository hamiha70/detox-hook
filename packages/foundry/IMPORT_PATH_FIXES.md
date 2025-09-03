# Import Path Fixes Guide

## 🚨 CRITICAL: Import Path Issues Detected

The compilation errors show that many scripts have incorrect import paths. This guide provides the correct import paths for all files.

## 📁 File Structure Reference

```
packages/foundry/
├── src/
│   ├── DetoxHookV2.sol
│   ├── LiquidityRouter.sol
│   ├── SwapRouterFixed.sol
│   ├── PriceRegistry.sol
│   ├── PoolStateReader.sol
│   ├── PoolStateViewer.sol
│   ├── libraries/
│   │   └── HookLibrary.sol
│   └── test-helpers/
│       └── Create2Deployer.sol
└── script/
    ├── Deploy/
    │   ├── DeployDetoxHookComplete.s.sol
    │   ├── DeployDetoxHookV2.s.sol
    │   ├── DeployLiquidityRouter.s.sol
    │   ├── DeployPoolStateReader.s.sol
    │   ├── DeployPoolStateViewer.s.sol
    │   ├── DeployPriceRegistry.s.sol
    │   ├── DeploySwapRouterFixed.s.sol
    │   ├── EstimateDeploymentResources.s.sol
    │   ├── ChainAddresses.sol
    │   ├── PoolParameters.sol
    │   ├── MockUSDC.sol
    │   ├── SafetyChecks.sol
    │   ├── TokenHelpers.sol
    │   └── PublicRPCURL.sol
    ├── ERC20/
    │   └── MockUSDC/
    │       ├── TokenHelpers.sol
    │       └── Utility/
    │           └── SafetyChecks.sol
    ├── Hook/
    │   ├── FundDetoxHook.s.sol
    │   └── ChainAddresses.sol
    ├── Pool/
    │   ├── InitializePools.s.sol
    │   ├── InitializePoolsWithHook.s.sol
    │   └── ChainAddresses.sol
    └── Transaction/
        ├── QuickLiquidityFX.s.sol
        ├── ProvideLiquidity.s.sol
        └── ProvideLiquidityFX.s.sol
```

## 🔧 Required Import Path Fixes

### 1. Script/Deploy/ Directory Fixes

#### DeployDetoxHookComplete.s.sol
```solidity
// ❌ WRONG
import { DetoxHookV2 } from "../src/DetoxHookV2.sol";
import { ChainAddresses } from "./ChainAddresses.sol";
import { SwapRouterFixed } from "../src/SwapRouterFixed.sol";
import { PoolParameters } from "./PoolParameters.sol";
import { MockUSDC } from "./MockUSDC.sol";
import { SafetyChecks } from "./SafetyChecks.sol";
import { TokenHelpers } from "./TokenHelpers.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";
import { PublicRPCURL } from "./PublicRPCURL.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";

// ✅ CORRECT
import { DetoxHookV2 } from "../../src/DetoxHookV2.sol";
import { ChainAddresses } from "./ChainAddresses.sol";
import { SwapRouterFixed } from "../../src/SwapRouterFixed.sol";
import { PoolParameters } from "./PoolParameters.sol";
import { MockUSDC } from "./MockUSDC.sol";
import { SafetyChecks } from "./SafetyChecks.sol";
import { TokenHelpers } from "./TokenHelpers.sol";
import { PriceRegistry } from "../../src/PriceRegistry.sol";
import { PublicRPCURL } from "./PublicRPCURL.sol";
import { HookLibrary } from "../../src/libraries/HookLibrary.sol";
```

#### DeployDetoxHookV2.s.sol
```solidity
// ❌ WRONG
import { DetoxHookV2 } from "../src/DetoxHookV2.sol";
import { PriceRegistry } from "../src/PriceRegistry.sol";
import { ChainAddresses } from "./ChainAddresses.sol";
import { Create2Deployer } from "../src/test-helpers/Create2Deployer.sol";

// ✅ CORRECT
import { DetoxHookV2 } from "../../src/DetoxHookV2.sol";
import { PriceRegistry } from "../../src/PriceRegistry.sol";
import { ChainAddresses } from "./ChainAddresses.sol";
import { Create2Deployer } from "../../src/test-helpers/Create2Deployer.sol";
```

#### DeployLiquidityRouter.s.sol
```solidity
// ❌ WRONG
import {LiquidityRouter} from "../src/LiquidityRouter.sol";
import {ChainAddresses} from "./ChainAddresses.sol";

// ✅ CORRECT
import {LiquidityRouter} from "../../src/LiquidityRouter.sol";
import {ChainAddresses} from "./ChainAddresses.sol";
```

#### DeployPoolStateReader.s.sol
```solidity
// ❌ WRONG
import {PoolStateReader} from "../src/PoolStateReader.sol";

// ✅ CORRECT
import {PoolStateReader} from "../../src/PoolStateReader.sol";
```

#### DeployPoolStateViewer.s.sol
```solidity
// ❌ WRONG
import "../src/PoolStateViewer.sol";

// ✅ CORRECT
import "../../src/PoolStateViewer.sol";
```

#### DeployPriceRegistry.s.sol
```solidity
// ❌ WRONG
import { PriceRegistry } from "../src/PriceRegistry.sol";
import { ChainAddresses } from "./ChainAddresses.sol";

// ✅ CORRECT
import { PriceRegistry } from "../../src/PriceRegistry.sol";
import { ChainAddresses } from "./ChainAddresses.sol";
```

#### DeploySwapRouterFixed.s.sol
```solidity
// ❌ WRONG
import {SwapRouterFixed} from "../src/SwapRouterFixed.sol";
import {ChainAddresses} from "./ChainAddresses.sol";
import {PoolParameters} from "./PoolParameters.sol";

// ✅ CORRECT
import {SwapRouterFixed} from "../../src/SwapRouterFixed.sol";
import {ChainAddresses} from "./ChainAddresses.sol";
import {PoolParameters} from "./PoolParameters.sol";
```

#### EstimateDeploymentResources.s.sol
```solidity
// ❌ WRONG
import { PoolParameters } from "./PoolParameters.sol";
import { HookLibrary } from "../src/libraries/HookLibrary.sol";

// ✅ CORRECT
import { PoolParameters } from "./PoolParameters.sol";
import { HookLibrary } from "../../src/libraries/HookLibrary.sol";
```

### 2. Script/ERC20/MockUSDC/ Directory Fixes

#### TokenHelpers.sol
```solidity
// ❌ WRONG
import {SafetyChecks} from "./Utility/SafetyChecks.sol";

// ✅ CORRECT
import {SafetyChecks} from "./Utility/SafetyChecks.sol";
```

### 3. Script/Hook/ Directory Fixes

#### FundDetoxHook.s.sol
```solidity
// ❌ WRONG
import { ChainAddresses } from "./ChainAddresses.sol";

// ✅ CORRECT
import { ChainAddresses } from "./ChainAddresses.sol";
```

### 4. Script/Pool/ Directory Fixes

#### InitializePools.s.sol
```solidity
// ❌ WRONG
import { ChainAddresses } from "./ChainAddresses.sol";

// ✅ CORRECT
import { ChainAddresses } from "./ChainAddresses.sol";
```

#### InitializePoolsWithHook.s.sol
```solidity
// ❌ WRONG
import {DetoxHookV2} from "../src/DetoxHookV2.sol";

// ✅ CORRECT
import {DetoxHookV2} from "../../src/DetoxHookV2.sol";
```

### 5. Script/Transaction/ Directory Fixes

#### ProvideLiquidity.s.sol
```solidity
// ❌ WRONG
import "../src/LiquidityRouter.sol";

// ✅ CORRECT
import "../../src/LiquidityRouter.sol";
```

## 🛠️ Automated Fix Commands

### Using sed (Unix/Linux/macOS)

```bash
# Navigate to the foundry directory
cd packages/foundry

# Fix DeployDetoxHookComplete.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/DeployDetoxHookComplete.s.sol

# Fix DeployDetoxHookV2.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/DeployDetoxHookV2.s.sol

# Fix DeployLiquidityRouter.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/DeployLiquidityRouter.s.sol

# Fix DeployPoolStateReader.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/DeployPoolStateReader.s.sol

# Fix DeployPoolStateViewer.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/DeployPoolStateViewer.s.sol

# Fix DeployPriceRegistry.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/DeployPriceRegistry.s.sol

# Fix DeploySwapRouterFixed.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/DeploySwapRouterFixed.s.sol

# Fix EstimateDeploymentResources.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Deploy/EstimateDeploymentResources.s.sol

# Fix InitializePoolsWithHook.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Pool/InitializePoolsWithHook.s.sol

# Fix ProvideLiquidity.s.sol
sed -i '' 's|"../src/|"../../src/|g' script/Transaction/ProvideLiquidity.s.sol
```

### Using PowerShell (Windows)

```powershell
# Navigate to the foundry directory
cd packages/foundry

# Fix all files at once
Get-ChildItem -Recurse -Filter "*.sol" | ForEach-Object {
    (Get-Content $_.FullName) -replace '"../src/', '"../../src/' | Set-Content $_.FullName
}
```

## 🔍 Verification Steps

After applying the fixes:

1. **Test compilation**:
   ```bash
   cd packages/foundry
   forge build
   ```

2. **Check specific scripts**:
   ```bash
   forge build --contracts script/Deploy/DeployDetoxHookComplete.s.sol
   forge build --contracts script/Transaction/QuickLiquidityFX.s.sol
   ```

3. **Verify no import errors**:
   ```bash
   forge build 2>&1 | grep "Source.*not found"
   ```

## 📋 Summary of Changes

| File | Old Path | New Path |
|------|----------|----------|
| DeployDetoxHookComplete.s.sol | `../src/` | `../../src/` |
| DeployDetoxHookV2.s.sol | `../src/` | `../../src/` |
| DeployLiquidityRouter.s.sol | `../src/` | `../../src/` |
| DeployPoolStateReader.s.sol | `../src/` | `../../src/` |
| DeployPoolStateViewer.s.sol | `../src/` | `../../src/` |
| DeployPriceRegistry.s.sol | `../src/` | `../../src/` |
| DeploySwapRouterFixed.s.sol | `../src/` | `../../src/` |
| EstimateDeploymentResources.s.sol | `../src/` | `../../src/` |
| InitializePoolsWithHook.s.sol | `../src/` | `../../src/` |
| ProvideLiquidity.s.sol | `../src/` | `../../src/` |

## ⚠️ Important Notes

1. **Relative paths**: All paths are relative to the script file location
2. **Same directory imports**: Files in the same directory use `./` (no change needed)
3. **Library imports**: External library imports (like `@uniswap/v4-core`) remain unchanged
4. **Test files**: Test files in `test/` directory may need similar fixes

## 🚀 After Fixes

Once all import paths are corrected:

1. **Compile the project**: `forge build`
2. **Run tests**: `forge test`
3. **Deploy contracts**: Use the deployment scripts
4. **Test QuickLiquidityFX**: `forge script script/Transaction/QuickLiquidityFX.s.sol`

---

**✅ This guide will resolve all import path compilation errors in the DetoxHook codebase.**
