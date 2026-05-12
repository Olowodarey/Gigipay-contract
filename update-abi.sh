#!/bin/bash

# Script to update ABI in backend and frontend

echo "🔄 Updating ABI files..."

# Generate ABI
echo "📝 Generating ABI..."
forge inspect Gigipay abi > deployments/Gigipay.abi.json

# Copy to backend
echo "📦 Copying to backend..."
cp deployments/Gigipay.abi.json ../Gigipay-backend/src/blockchain/gigipay.abi.json

# Copy to frontend  
echo "📦 Copying to frontend..."
cp deployments/Gigipay.abi.json ../Gigipay/apps/web/src/lib/gigipay.abi.json

echo "✅ ABI files updated!"
echo ""
echo "📋 Next steps:"
echo "1. Update backend abi.ts to import from gigipay.abi.json"
echo "2. Update frontend to import from gigipay.abi.json"
echo "3. Restart backend and frontend"
