#!/bin/bash

# Gigipay Deployment Script for Base Mainnet
# ⚠️  WARNING: This deploys to PRODUCTION - use real funds carefully!

set -e  # Exit on error

echo "🚀 Deploying Gigipay to Base Mainnet..."
echo ""
echo "⚠️  WARNING: You are deploying to MAINNET!"
echo "⚠️  This will use REAL funds. Make sure you have:"
echo "   - Sufficient ETH for gas fees on Base"
echo "   - Verified your contract code"
echo "   - Tested on testnet first"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found!"
    echo "Please create a .env file from .env.example:"
    echo "  cp .env.example .env"
    echo "  nano .env"
    exit 1
fi

# Load environment variables
source .env

# Validate required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY not set in .env file"
    exit 1
fi

if [ -z "$DEFAULT_ADMIN" ]; then
    echo "❌ Error: DEFAULT_ADMIN not set in .env file"
    exit 1
fi

if [ -z "$PAUSER" ]; then
    echo "❌ Error: PAUSER not set in .env file"
    exit 1
fi

echo "📋 Deployment Configuration:"
echo "  Network: Base Mainnet"
echo "  RPC: https://mainnet.base.org"
echo "  Default Admin: $DEFAULT_ADMIN"
echo "  Pauser: $PAUSER"
echo ""

# Run the deployment script
echo "🔨 Compiling contracts..."
forge build

echo ""
echo "📤 Deploying contracts to Base Mainnet..."

# Check if ETHERSCAN_API_KEY is set for verification
if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "⚠️  Warning: ETHERSCAN_API_KEY not set - contract verification will be skipped"
    echo "   You can verify manually later on BaseScan"
    forge script script/DeployGigipay.s.sol:DeployGigipay \
      --rpc-url https://mainnet.base.org \
      --private-key $PRIVATE_KEY \
      --broadcast \
      -vvvv
else
    echo "✅ ETHERSCAN_API_KEY found - will attempt automatic verification"
    forge script script/DeployGigipay.s.sol:DeployGigipay \
      --rpc-url https://mainnet.base.org \
      --private-key $PRIVATE_KEY \
      --broadcast \
      --verify \
      --etherscan-api-key $ETHERSCAN_API_KEY \
      -vvvv
fi

echo ""
echo "✅ Deployment complete!"
echo ""
echo "⚠️  IMPORTANT: Save the proxy address from the output above."
echo "    Users should interact with the PROXY address, not the implementation!"
echo ""
echo "📝 Next steps:"
echo "   1. Save the proxy address"
echo "   2. Verify the contract on BaseScan (if --verify failed)"
echo "      Visit: https://basescan.org/verifyContract"
echo "   3. Test the deployment with a small transaction"
echo "   4. Update your frontend with the new contract address"
echo ""
echo "🔗 Useful links:"
echo "   - BaseScan: https://basescan.org"
echo "   - Base Docs: https://docs.base.org"
