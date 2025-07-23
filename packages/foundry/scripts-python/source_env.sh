#!/bin/bash
# DetoxHook Environment Sourcing Script
# =====================================
#
# This script loads environment variables from .env files and sources them
# into the current shell session using the Python environment loader.
#
# Usage:
#   source packages/foundry/scripts-python/source_env.sh
#   source source_env.sh                    # from scripts-python directory
#   source source_env.sh .env.local         # with custom .env file

set -e  # Exit on any error

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_LOADER="$SCRIPT_DIR/load_env.py"

# Default .env file
ENV_FILE="${1:-.env}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 DetoxHook Environment Sourcer${NC}"
echo -e "${BLUE}=================================${NC}"

# Check if Python script exists
if [[ ! -f "$PYTHON_LOADER" ]]; then
    echo -e "${RED}❌ Python loader not found: $PYTHON_LOADER${NC}"
    return 1 2>/dev/null || exit 1
fi

# Check if Python is available
if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
    echo -e "${RED}❌ Python not found. Please install Python 3.6+${NC}"
    return 1 2>/dev/null || exit 1
fi

# Determine Python command
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
else
    PYTHON_CMD="python"
fi

# Create a temporary file for environment exports
TEMP_ENV_FILE=$(mktemp)
trap 'rm -f "$TEMP_ENV_FILE"' EXIT

# Run the Python loader to generate shell exports
echo -e "${YELLOW}📂 Loading environment variables from: $ENV_FILE${NC}"

if "$PYTHON_CMD" "$PYTHON_LOADER" --env-file "$ENV_FILE" --export-shell --shell-file "$TEMP_ENV_FILE" --verbose; then
    echo -e "${GREEN}📝 Sourcing environment variables...${NC}"
    
    # Source the generated environment file
    if [[ -f "$TEMP_ENV_FILE" ]]; then
        source "$TEMP_ENV_FILE"
        echo -e "${GREEN}✅ Environment variables loaded successfully!${NC}"
    else
        echo -e "${RED}❌ Failed to generate environment export file${NC}"
        return 1 2>/dev/null || exit 1
    fi
else
    echo -e "${RED}❌ Failed to load environment variables${NC}"
    return 1 2>/dev/null || exit 1
fi

# Optional: Show some loaded variables (non-sensitive ones)
if [[ -n "$RPC_URL" ]]; then
    echo -e "${GREEN}🌐 RPC_URL is set${NC}"
fi

if [[ -n "$NODE_ENV" ]]; then
    echo -e "${GREEN}⚙️  NODE_ENV: $NODE_ENV${NC}"
fi

if [[ -n "$PRIVATE_KEY" ]] || [[ -n "$DEPLOYMENT_KEY" ]]; then
    echo -e "${GREEN}🔑 Private key variables are set${NC}"
fi

echo -e "${BLUE}💡 Environment variables are now available in this shell session${NC}" 