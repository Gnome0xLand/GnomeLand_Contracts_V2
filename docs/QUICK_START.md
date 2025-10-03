markdown# Gnomeland Quick Start Guide

## 🚀 Setup (5 minutes)

### 1. Install Foundry

````bashcurl -L https://foundry.paradigm.xyz | bash
foundryup

### 2. Clone/Setup Project
```bashcd gnomeland

### 3. Install Dependencies
```bashforge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install Uniswap/v4-core --no-commit
forge install Uniswap/v4-periphery --no-commit

### 4. Configure Environment
```bashcp .env.example .env
nano .env  # Edit with your values

**Required values:**
- `PRIVATE_KEY` - Your deployer wallet private key (NO 0x prefix)
- `SEPOLIA_RPC_URL` - Alchemy or Infura RPC URL
- `ETHERSCAN_API_KEY` - For contract verification
- `TREASURY_ADDRESS` - Where 6% fees will go
- `POOL_MANAGER_ADDRESS` - Uniswap V4 PoolManager

### 5. Test Everything Works
```bashforge build
forge test

---

## 📦 Deployment to Sepolia (Testnet)

### Step 1: Dry Run
```bashforge script script/Deploy.s.sol:DeployScript
--rpc-url $SEPOLIA_RPC_URL
--private-key $PRIVATE_KEY
-vvvv

### Step 2: Deploy
```bashforge script script/Deploy.s.sol:DeployScript
--rpc-url $SEPOLIA_RPC_URL
--private-key $PRIVATE_KEY
--broadcast
--verify
-vvvv

### Step 3: Save Addresses
Addresses are automatically saved to `deployments/addresses.json`

Copy them to your `.env`:
```bashTOKEN_ADDRESS=0x...
NFT_CONTRACT=0x...
HOOK_PROXY=0x...

### Step 4: Configure
```bashforge script script/Configure.s.sol:ConfigureScript
--rpc-url $SEPOLIA_RPC_URL
--private-key $PRIVATE_KEY
--broadcast
-vvvv

---

## 🧪 Testing Your Deployment

### Fund the Minting Pool
```bashcast send $NFT_CONTRACT
--value 10ether
--private-key $PRIVATE_KEY
--rpc-url $SEPOLIA_RPC_URL

### Mint Your First NFT
```bashcast send $NFT_CONTRACT "mint()"
--private-key $PRIVATE_KEY
--rpc-url $SEPOLIA_RPC_URL

### Check Your NFT
```bashcast call $NFT_CONTRACT "ownerOf(uint256)(address)" 0
--rpc-url $SEPOLIA_RPC_URL

---

## 🎯 Next Steps

- Deploy to mainnet (see DEPLOYMENT.md)
- Set up monitoring
- Configure Uniswap pool
- Engage community

**Good luck! 🍄**2. docs/DEPLOYMENT.mdmarkdown# Gnomeland Deployment Guide (Foundry)

## Prerequisites

### Install Foundry
```bashcurl -L https://foundry.paradigm.xyz | bash
foundryup

### Install Dependencies
```bashforge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install Uniswap/v4-core --no-commit
forge install Uniswap/v4-periphery --no-commit

### Configure Environment
Create `.env` file:
```bashPRIVATE_KEY=your_private_key_without_0x
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=your_etherscan_api_key
TREASURY_ADDRESS=0xYourTreasuryAddress
POOL_MANAGER_ADDRESS=0xUniswapV4PoolManager

---

## Deployment Order

### 1. Deploy Contracts

**Dry run (Sepolia):**
```bashforge script script/Deploy.s.sol:DeployScript
--rpc-url $SEPOLIA_RPC_URL
--private-key $PRIVATE_KEY
-vvvv

**Deploy:**
```bashforge script script/Deploy.s.sol:DeployScript
--rpc-url $SEPOLIA_RPC_URL
--private-key $PRIVATE_KEY
--broadcast
--verify
-vvvv

This deploys:
- ✅ GNOME Token (ERC20)
- ✅ GnomeStickers NFT
- ✅ Hook Implementation
- ✅ Hook Proxy

### 2. Save Addresses

Check `deployments/addresses.json` and update your `.env`:
```bashTOKEN_ADDRESS=0x...
NFT_CONTRACT=0x...
HOOK_IMPL_ADDRESS=0x...
HOOK_PROXY=0x...

### 3. Configure Contracts
```bashforge script script/Configure.s.sol:ConfigureScript
--rpc-url $SEPOLIA_RPC_URL
--private-key $PRIVATE_KEY
--broadcast
-vvvv

### 4. Deploy Uniswap Pool
```bashforge script script/DeployPool.s.sol:DeployPool
--rpc-url $SEPOLIA_RPC_URL
--private-key $PRIVATE_KEY
--broadcast
-vvvv

---

## Verification

### Verify Contracts Manually

**GNOME Token:**
```bashforge verify-contract
--chain-id 11155111
--num-of-optimizations 200
--watch
--constructor-args $(cast abi-encode "constructor()")
--etherscan-api-key $ETHERSCAN_API_KEY
--compiler-version v0.8.20
$TOKEN_ADDRESS
src/GNOMEToken.sol:GNOMEToken

**NFT Contract:**
```bashforge verify-contract
--chain-id 11155111
--num-of-optimizations 200
--watch
--constructor-args $(cast abi-encode "constructor(address,string)" $TREASURY_ADDRESS "https://api.gnomeland.io/metadata/")
--etherscan-api-key $ETHERSCAN_API_KEY
--compiler-version v0.8.20
$NFT_CONTRACT
src/GnomeStickers.sol:GnomeStickers

---

## Mainnet Deployment Checklist

Before deploying to mainnet:

- [ ] All tests passing
- [ ] Gas optimization complete
- [ ] Security audit done
- [ ] Treasury address verified
- [ ] Pricing curve calibrated (72nd NFT = 1 ETH)
- [ ] Sufficient ETH for deployment (~0.5 ETH)
- [ ] Backup of all code
- [ ] Emergency procedures ready

### Deploy to Mainnet
```bashDRY RUN FIRST!
forge script script/Deploy.s.sol:DeployScript
--rpc-url $MAINNET_RPC_URL
--private-key $PRIVATE_KEY
-vvvvDeploy
forge script script/Deploy.s.sol:DeployScript
--rpc-url $MAINNET_RPC_URL
--private-key $PRIVATE_KEY
--broadcast
--verify
--slow
-vvvv

---

## Post-Deployment

### Fund Minting Pool
```bashcast send $NFT_CONTRACT
--value 10ether
--private-key $PRIVATE_KEY
--rpc-url $RPC_URL

### Check System Health
```bashforge script script/AdminScripts.s.sol:CheckSystemHealth
--rpc-url $RPC_URL

---

## Useful Commands

### Check Contract State
```bashTotal supply
cast call $NFT_CONTRACT "totalSupply()(uint256)" --rpc-url $RPC_URLMinting pool
cast call $NFT_CONTRACT "mintingPool()(uint256)" --rpc-url $RPC_URLFloor price
cast call $NFT_CONTRACT "floorPrice()(uint256)" --rpc-url $RPC_URL

### Admin Operations
```bashUpdate treasury
forge script script/AdminScripts.s.sol:UpdateTreasury --broadcastUpdate pricing
forge script script/AdminScripts.s.sol:UpdatePricing --broadcastBatch mint
forge script script/AdminScripts.s.sol:BatchMint --broadcast

Good luck with deployment! 🚀
````
