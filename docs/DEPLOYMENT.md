markdown# 📦 Gnomeland Deployment Guide (Foundry/Forge)

## Overview

This guide covers complete deployment of the Gnomeland ecosystem using Foundry.

---

## Prerequisites

### 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify installation
forge --version
cast --version
2. Install Dependencies
bashcd gnomeland

# Install OpenZeppelin contracts
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit

# Install Uniswap V4 (if available)
forge install Uniswap/v4-core --no-commit
forge install Uniswap/v4-periphery --no-commit
3. Configure Environment
Create .env file:
bashcp .env.example .env
nano .env
Required Configuration:
bash# Deployer wallet (NEVER commit this!)
PRIVATE_KEY=your_private_key_without_0x_prefix

# RPC Endpoints
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# Default RPC
RPC_URL=${SEPOLIA_RPC_URL}

# Etherscan (for verification)
ETHERSCAN_API_KEY=your_etherscan_api_key

# Deployment Addresses
TREASURY_ADDRESS=0xYourTreasuryAddress
POOL_MANAGER_ADDRESS=0xUniswapV4PoolManagerAddress

# Chain IDs
CHAIN_ID=11155111  # Sepolia testnet
# CHAIN_ID=1       # Mainnet
4. Get Testnet ETH
For Sepolia deployment, get test ETH:

Alchemy Faucet: https://sepoliafaucet.com/
QuickNode Faucet: https://faucet.quicknode.com/ethereum/sepolia
Infura Faucet: https://www.infura.io/faucet/sepolia

You'll need ~0.5 ETH for full deployment.

Pre-Deployment Checklist
Before deploying, verify:

 All tests passing: forge test
 Gas report reviewed: forge test --gas-report
 .env configured correctly
 Treasury address is correct (you control it!)
 Sufficient ETH in deployer wallet
 Etherscan API key is valid
 Backup of all contract code


Deployment to Sepolia (Testnet)
Step 1: Test Build
bash# Clean previous builds
forge clean

# Build contracts
forge build

# Should see:
# [⠊] Compiling...
# [⠒] Compiling 3 files with 0.8.20
# [⠢] Solc 0.8.20 finished in X.XXs
# Compiler run successful!
Step 2: Run Tests
bash# Run all tests
forge test -vvv

# Should see tests passing
# [PASS] testTokenDeployment()
# [PASS] testPricingCurve()
# [PASS] testMinting()
# etc.
Step 3: Simulate Deployment (Dry Run)
CRITICAL: Always dry run first!
bashforge script script/Deploy.s.sol:DeployScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    -vvvv
What to check:

✅ No errors
✅ Gas estimates reasonable
✅ Constructor arguments correct
✅ All 4 contracts deploy

Step 4: Deploy to Sepolia
bashforge script script/Deploy.s.sol:DeployScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
Output will show:
== Logs ==
Deploying GNOME Token...
GNOME Token deployed at: 0x123...

Deploying GnomeStickers NFT...
GnomeStickers deployed at: 0x456...

Deploying Hook Implementation...
Hook Implementation deployed at: 0x789...

Deploying Hook Proxy...
Hook Proxy deployed at: 0xabc...

=== DEPLOYMENT COMPLETE ===
GNOME Token: 0x123...
NFT Contract: 0x456...
Hook Implementation: 0x789...
Hook Proxy: 0xabc...
Treasury: 0xdef...
Step 5: Save Deployment Addresses
Addresses are automatically saved to deployments/addresses.json:
bashcat deployments/addresses.json
Copy these to your .env:
bashTOKEN_ADDRESS=0x123...
NFT_CONTRACT=0x456...
HOOK_IMPL_ADDRESS=0x789...
HOOK_PROXY=0xabc...
Step 6: Verify on Etherscan
If auto-verification failed, verify manually:
GNOME Token:
bashforge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor()") \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.20 \
    $TOKEN_ADDRESS \
    src/GNOMEToken.sol:GNOMEToken
NFT Contract:
bashforge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,string)" $TREASURY_ADDRESS "https://api.gnomeland.io/metadata/") \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.20 \
    $NFT_CONTRACT \
    src/GnomeStickers.sol:GnomeStickers
Hook Implementation:
bashforge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address)" $POOL_MANAGER_ADDRESS) \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.20 \
    $HOOK_IMPL_ADDRESS \
    src/GnomelandHook.sol:GnomelandHook
Step 7: Configure Contracts
bashforge script script/Configure.s.sol:ConfigureScript \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
This configures:

✅ Verifies pricing (72nd NFT = ~1 ETH)
✅ Sets hook fee percentage
✅ Sets auto-transfer threshold

Step 8: Deploy Uniswap V4 Pool
bashforge script script/DeployPool.s.sol:DeployPool \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
Pool info saved to deployments/pool-info.json

Post-Deployment Testing
1. Fund Minting Pool
bashcast send $NFT_CONTRACT \
    --value 10ether \
    --private-key $PRIVATE_KEY \
    --rpc-url $SEPOLIA_RPC_URL
2. Check Minting Pool Balance
bashcast call $NFT_CONTRACT "mintingPool()(uint256)" --rpc-url $SEPOLIA_RPC_URL

# Convert to ETH
cast --to-unit $(cast call $NFT_CONTRACT "mintingPool()(uint256)" --rpc-url $SEPOLIA_RPC_URL) ether
3. Mint Test NFT
bashcast send $NFT_CONTRACT "mint()" \
    --private-key $PRIVATE_KEY \
    --rpc-url $SEPOLIA_RPC_URL \
    --gas-limit 500000
4. Verify NFT Ownership
bash# Check owner of token 0
cast call $NFT_CONTRACT "ownerOf(uint256)(address)" 0 --rpc-url $SEPOLIA_RPC_URL

# Check your address
cast wallet address --private-key $PRIVATE_KEY
5. Test Marketplace
List NFT:
bashcast send $NFT_CONTRACT "listAtPrice(uint256,uint256)" 0 1000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $SEPOLIA_RPC_URL
Check Listing:
bashcast call $NFT_CONTRACT "listings(uint256)(uint256,address,bool)" 0 --rpc-url $SEPOLIA_RPC_URL
6. Run Health Check
bashforge script script/AdminScripts.s.sol:CheckSystemHealth \
    --rpc-url $SEPOLIA_RPC_URL \
    -vvv

Deployment to Mainnet
Pre-Mainnet Checklist
CRITICAL CHECKS:

 Deployed to Sepolia for 7+ days
 All functionality tested thoroughly
 No critical bugs found
 External audit completed (recommended)
 Bug bounty program ready
 Multi-sig wallet setup for admin
 Emergency procedures documented
 Team trained on emergency response
 Monitoring systems ready
 Gas price is favorable (<50 gwei)
 Sufficient ETH for deployment (~0.5 ETH)
 All private keys secured
 Backup of all contract code
 Etherscan verification ready
 Community notification prepared

Mainnet Deployment Steps
1. Update Environment
bash# Update .env
export RPC_URL=$MAINNET_RPC_URL
export CHAIN_ID=1
2. DRY RUN (Mandatory!)
bashforge script script/Deploy.s.sol:DeployScript \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    -vvvv
Review carefully:

Gas estimates
Constructor arguments
All addresses
Transaction order

3. Deploy to Mainnet
⚠️ FINAL WARNING: This uses real ETH!
bashforge script script/Deploy.s.sol:DeployScript \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --slow \
    -vvvv
Deployment will take 5-10 minutes. DO NOT interrupt!
4. Save Mainnet Addresses
bash# Backup addresses immediately
cp deployments/addresses.json deployments/mainnet-addresses-$(date +%Y%m%d).json

# Update .env
nano .env
# Set TOKEN_ADDRESS, NFT_CONTRACT, HOOK_PROXY
5. Configure Mainnet Contracts
bashforge script script/Configure.s.sol:ConfigureScript \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
6. Transfer to Multi-Sig (IMPORTANT!)
bash# Transfer ownership of all contracts to multi-sig
export NEW_OWNER_ADDRESS=0xYourMultiSigAddress

cast send $TOKEN_ADDRESS "transferOwnership(address)" $NEW_OWNER_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url $MAINNET_RPC_URL

cast send $NFT_CONTRACT "transferOwnership(address)" $NEW_OWNER_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url $MAINNET_RPC_URL

cast send $HOOK_PROXY "transferOwnership(address)" $NEW_OWNER_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url $MAINNET_RPC_URL
7. Deploy Uniswap Pool
bashforge script script/DeployPool.s.sol:DeployPool \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv
8. Add Initial Liquidity
bash# Approve tokens
cast send $TOKEN_ADDRESS "approve(address,uint256)" $POOL_MANAGER_ADDRESS 1000000000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $MAINNET_RPC_URL

# Add liquidity (adjust amounts as needed)
# Use Uniswap V4 UI or custom script

Useful Commands
Check Contract State
bash# Total NFT supply
cast call $NFT_CONTRACT "totalSupply()(uint256)" --rpc-url $RPC_URL

# Current mint price
cast call $NFT_CONTRACT "getCurrentMintPrice()(uint256)" --rpc-url $RPC_URL | xargs cast --to-unit - ether

# Floor price
cast call $NFT_CONTRACT "floorPrice()(uint256)" --rpc-url $RPC_URL | xargs cast --to-unit - ether

# Minting pool balance
cast call $NFT_CONTRACT "mintingPool()(uint256)" --rpc-url $RPC_URL | xargs cast --to-unit - ether

# Hook accumulated fees
cast call $HOOK_PROXY "accumulatedFees()(uint256)" --rpc-url $RPC_URL | xargs cast --to-unit - ether

# Token balance
cast call $TOKEN_ADDRESS "balanceOf(address)(uint256)" YOUR_ADDRESS --rpc-url $RPC_URL
Admin Operations
bash# Update treasury
export NEW_TREASURY_ADDRESS=0x...
forge script script/AdminScripts.s.sol:UpdateTreasury \
    --rpc-url $RPC_URL \
    --broadcast

# Update pricing
forge script script/AdminScripts.s.sol:UpdatePricing \
    --rpc-url $RPC_URL \
    --broadcast

# Update hook config
forge script script/AdminScripts.s.sol:UpdateHookConfig \
    --rpc-url $RPC_URL \
    --broadcast

# Batch mint
forge script script/AdminScripts.s.sol:BatchMint \
    --rpc-url $RPC_URL \
    --broadcast

# Health check
forge script script/AdminScripts.s.sol:CheckSystemHealth \
    --rpc-url $RPC_URL
Upgrade Hook
bashforge script script/UpgradeHook.s.sol:UpgradeHook \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv

Troubleshooting
Deployment Fails
Check:
bash# Sufficient balance
cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $RPC_URL

# Gas price
cast gas-price --rpc-url $RPC_URL

# Nonce
cast nonce $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $RPC_URL
Verification Fails
bash# Check compiler version matches
forge --version

# Ensure constructor args are exact
# Retry with explicit parameters
Transaction Reverts
bash# Get detailed trace
cast run $TX_HASH --rpc-url $RPC_URL --trace

# Check revert reason
cast receipt $TX_HASH --rpc-url $RPC_URL

Gas Optimization Tips
Deploy During Low Gas
bash# Monitor gas prices
watch -n 60 'cast gas-price --rpc-url $MAINNET_RPC_URL'

# Optimal times: Late night/early morning UTC
# Target: <30 gwei for mainnet
Estimate Costs
bash# Get current gas price
GAS_PRICE=$(cast gas-price --rpc-url $MAINNET_RPC_URL)

# Estimate deployment cost
# ~7,200,000 gas for full deployment
echo "scale=4; 7200000 * $GAS_PRICE / 10^18" | bc

Post-Deployment Monitoring
Set Up Monitoring
bash# Run health checks regularly
crontab -e

# Add:
*/30 * * * * cd /path/to/gnomeland && forge script script/AdminScripts.s.sol:CheckSystemHealth --rpc-url $MAINNET_RPC_URL >> /var/log/gnomeland.log 2>&1
Monitor Events
bash# Watch for new mints
cast logs --address $NFT_CONTRACT \
    --from-block latest \
    --rpc-url $RPC_URL

# Watch for purchases
cast logs --address $NFT_CONTRACT \
    "Purchased(uint256,address,address,uint256)" \
    --from-block latest \
    --rpc-url $RPC_URL

Emergency Procedures
Pause System (if needed)
bash# Forward all hook fees immediately
cast send $HOOK_PROXY "forwardFees()" \
    --private-key $PRIVATE_KEY \
    --rpc-url $MAINNET_RPC_URL

# Check all balances
cast balance $NFT_CONTRACT --rpc-url $MAINNET_RPC_URL
cast balance $HOOK_PROXY --rpc-url $MAINNET_RPC_URL
cast balance $TREASURY_ADDRESS --rpc-url $MAINNET_RPC_URL
Contact Information
Keep emergency contacts ready:

Lead developer
Security team
Audit firm
Legal counsel


Success Criteria
After deployment, verify:

 All contracts deployed successfully
 All contracts verified on Etherscan
 Ownership transferred to multi-sig
 Initial liquidity added
 Minting pool funded
 First test mint successful
 Marketplace working
 Hook collecting fees
 Health checks passing
 Monitoring active
 Community notified


Next Steps
After successful deployment:

Monitor closely for first 24-48 hours
Engage community with launch announcement
List on aggregators (DEX Screener, DexTools, etc.)
Marketing campaign begins
Regular updates to community
Continuous security monitoring


Resources

Foundry Documentation: https://book.getfoundry.sh/
OpenZeppelin: https://docs.openzeppelin.com/
Uniswap V4: https://docs.uniswap.org/
Etherscan: https://etherscan.io/
Gas Tracker: https://etherscan.io/gastracker


Good luck with your deployment! 🚀🍄
```
