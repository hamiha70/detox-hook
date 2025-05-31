#!/bin/bash

# load_env.sh - Load environment variables from .env file
# Usage: source load_env.sh  OR  . load_env.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔧 Loading environment variables from .env file...${NC}"

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ Error: .env file not found${NC}"
    echo "Please create a .env file with your wallet addresses:"
    echo ""
    echo "DEPLOYMENT_WALLET=0x..."
    echo "SWAPPER_WALLET=0x..."
    echo "LIQUIDITY_PROVIDER_WALLET=0x..."
    return 1 2>/dev/null || exit 1
fi

# Read .env file and export non-commented lines
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines
    if [ -z "$line" ]; then
        continue
    fi
    
    # Skip lines that start with # (comments)
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Skip lines that don't contain =
    if [[ ! "$line" =~ = ]]; then
        continue
    fi
    
    # Remove leading/trailing whitespace
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Export the variable
    export "$line"
    
    # Extract variable name for display (everything before the first =)
    var_name=$(echo "$line" | cut -d'=' -f1)
    echo -e "  ✅ Exported: ${GREEN}$var_name${NC}"
    
done < ".env"

echo ""
echo -e "${GREEN}✅ Environment variables loaded successfully!${NC}"
echo -e "${YELLOW}💡 You can now run: python3 wallet_balance_checker.py${NC}" 