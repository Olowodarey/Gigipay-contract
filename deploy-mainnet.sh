#!/bin/bash

# Gigipay Mainnet Deployment Script
# This script deploys the Gigipay contract to Celo Mainnet

set -e  # Exit on error

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Gigipay Mainnet Deployment Script                 ║"
echo "║         Celo Mainnet                                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}❌ Error: .env file not found!${NC}"
    exit 1
fi

# Load environment variables
source .env

# Verify required variables
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}❌ Error: PRIVATE_KEY not set in .env${NC}"
    exit 1
fi

if [ -z "$DEFAULT_ADMIN" ]; then
    echo -e "${RED}❌ Error: DEFAULT_ADMIN not set in .env${NC}"
    exit 1
fi

if [ -z "$PAUSER" ]; then
    echo -e "${RED}❌ Error: PAUSER not set in .env${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Deployment Configuration:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Network:        ${GREEN}Celo Mainnet${NC}"
echo -e "RPC URL:        ${CELO_RPC_URL}"
echo -e "Default Admin:  ${DEFAULT_ADMIN}"
echo -e "Pauser:         ${PAUSER}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Confirmation prompt
echo -e "${YELLOW}⚠️  WARNING: You are about to deploy to MAINNET!${NC}"
echo -e "${YELLOW}⚠️  This will cost real CELO for gas fees.${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${RED}❌ Deployment cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}🔨 Step 1: Cleaning build artifacts...${NC}"
forge clean

echo -e "${BLUE}� Step 2: Compiling contracts...${NC}"
forge build

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Compilation failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Compilation successful!${NC}"
echo ""

echo -e "${BLUE}🧪 Step 3: Running tests...${NC}"
forge test

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Tests failed! Aborting deployment.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All tests passed!${NC}"
echo ""

echo -e "${BLUE}🚀 Step 4: Deploying to Celo Mainnet...${NC}"
echo "This may take a few minutes..."
echo ""

# Deploy and capture output
DEPLOY_OUTPUT=$(forge script script/DeployGigipay.s.sol \
    --rpc-url $CELO_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --verifier blockscout \
    --verifier-url https://explorer.celo.org/mainnet/api \
    -vvv 2>&1)

DEPLOY_EXIT_CODE=$?

echo "$DEPLOY_OUTPUT"

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Deployment failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Deployment successful!${NC}"
echo ""

# Extract addresses from output
IMPLEMENTATION=$(echo "$DEPLOY_OUTPUT" | grep "Gigipay Implementation deployed at:" | awk '{print $NF}')
PROXY=$(echo "$DEPLOY_OUTPUT" | grep "Gigipay Proxy deployed at:" | awk '{print $NF}')

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              Deployment Successful! 🎉                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}📝 Contract Addresses:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Implementation: ${BLUE}${IMPLEMENTATION}${NC}"
echo -e "Proxy (Main):   ${BLUE}${PROXY}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Save deployment info
DEPLOYMENT_FILE="deployments/mainnet-$(date +%Y%m%d-%H%M%S).json"
mkdir -p deployments

cat > $DEPLOYMENT_FILE << EOF
{
  "network": "celo-mainnet",
  "chainId": 42220,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployer": "$DEFAULT_ADMIN",
  "contracts": {
    "implementation": "$IMPLEMENTATION",
    "proxy": "$PROXY"
  },
  "roles": {
    "defaultAdmin": "$DEFAULT_ADMIN",
    "pauser": "$PAUSER",
    "withdrawer": "$DEFAULT_ADMIN"
  },
  "explorer": {
    "implementation": "https://explorer.celo.org/mainnet/address/$IMPLEMENTATION",
    "proxy": "https://explorer.celo.org/mainnet/address/$PROXY"
  }
}
EOF

echo -e "${GREEN}✅ Deployment info saved to: ${DEPLOYMENT_FILE}${NC}"
echo ""

echo -e "${BLUE}🔗 Explorer Links:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Implementation: ${BLUE}https://explorer.celo.org/mainnet/address/${IMPLEMENTATION}${NC}"
echo -e "Proxy (Main):   ${BLUE}https://explorer.celo.org/mainnet/address/${PROXY}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. ✅ Verify contracts on block explorer (automatic)"
echo "2. 🔍 Test contract functions on explorer"
echo "3. 🔄 Update frontend with new proxy address:"
echo "   ${PROXY}"
echo "4. 🔄 Update backend with new proxy address"
echo "5. 📝 Update ABI files in frontend/backend"
echo "6. 🧪 Test with small amounts first"
echo "7. 📢 Announce new contract to users"
echo "8. 🗑️  Deprecate old contract (pause + withdraw)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo ""

# Generate ABI
echo -e "${BLUE}📄 Generating ABI...${NC}"
forge inspect Gigipay abi > deployments/Gigipay.abi.json
echo -e "${GREEN}✅ ABI saved to: deployments/Gigipay.abi.json${NC}"
echo ""

echo -e "${YELLOW}💡 Quick Commands:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Check contract on explorer:"
echo "open https://explorer.celo.org/mainnet/address/${PROXY}"
echo ""
echo "# Test a function (example - check available funds):"
echo "cast call ${PROXY} \"getAvailableBillFunds(address)\" \"0x0000000000000000000000000000000000000000\" --rpc-url \$CELO_RPC_URL"
echo ""
echo "# Pause contract (emergency):"
echo "cast send ${PROXY} \"pause()\" --private-key \$PRIVATE_KEY --rpc-url \$CELO_RPC_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${GREEN}✨ All done! Your contract is live on Celo Mainnet! ✨${NC}"
