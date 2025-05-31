import { readFileSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Updates externalContracts.ts with the current local DetoxHook address
 */
function updateExternalContracts() {
  console.log("🔄 Updating external contracts with current DetoxHook address...");

  try {
    // Get the current local DetoxHook address from test
    const testOutput = execSync(
      'forge test --match-contract DetoxHookLocal --match-test test_LocalHookExists -vv',
      { 
        cwd: join(__dirname, '..'),
        encoding: 'utf8'
      }
    );

    // Extract the hook address from test output
    const addressMatch = testOutput.match(/Hook address: (0x[a-fA-F0-9]{40})/);
    if (!addressMatch) {
      throw new Error("Could not find DetoxHook address in test output");
    }

    const hookAddress = addressMatch[1];
    console.log(`📍 Found DetoxHook address: ${hookAddress}`);

    // Read the current ABI from compiled artifacts
    const artifactPath = join(__dirname, '..', 'out', 'DetoxHook.sol', 'DetoxHook.json');
    const artifact = JSON.parse(readFileSync(artifactPath, 'utf8'));
    const abi = artifact.abi;

    // Read the current external contracts file
    const externalContractsPath = join(__dirname, '..', '..', 'nextjs', 'contracts', 'externalContracts.ts');
    let content = readFileSync(externalContractsPath, 'utf8');

    // Update the address in the file
    const addressRegex = /address: "0x[a-fA-F0-9]{40}"/;
    const newAddressLine = `address: "${hookAddress}"`;
    
    if (content.includes('DetoxHook')) {
      // Update existing address
      content = content.replace(addressRegex, newAddressLine);
      console.log(`✅ Updated DetoxHook address to ${hookAddress}`);
    } else {
      console.log("⚠️  DetoxHook not found in externalContracts.ts - manual setup required");
      return;
    }

    // Write the updated file
    writeFileSync(externalContractsPath, content);
    console.log("📝 External contracts updated successfully!");

  } catch (error) {
    console.error("❌ Error updating external contracts:", error.message);
    process.exit(1);
  }
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  updateExternalContracts();
}

export { updateExternalContracts }; 