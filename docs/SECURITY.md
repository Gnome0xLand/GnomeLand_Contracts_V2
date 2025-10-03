markdown# Security Audit Checklist

## Pre-Deployment Security Review

### Code Review

- [ ] No hardcoded private keys
- [ ] All external calls handled safely
- [ ] ReentrancyGuard on state-changing functions
- [ ] Proper access control (Ownable)
- [ ] Event emissions for critical changes
- [ ] No tx.origin for authentication
- [ ] Descriptive error messages
- [ ] Safe math (Solidity 0.8.20+)

### Contract-Specific Checks

**GNOMEToken:**

- [ ] Standard ERC20 from OpenZeppelin
- [ ] Mint restricted to owner
- [ ] Burn only by token holder
- [ ] No unnecessary permissions

**GnomeStickers:**

- [ ] Sequential minting (0-9,999)
- [ ] Max supply enforced (10,000)
- [ ] SafeMint used
- [ ] Pricing curve verified (72nd = 1 ETH)
- [ ] ReentrancyGuard on purchase
- [ ] Treasury fee calculation correct (6%)
- [ ] Floor price logic secure
- [ ] Listing array bounded

**GnomelandHook:**

- [ ] Only PoolManager can call hooks
- [ ] Fee percentage capped (max 10%)
- [ ] Upgrade mechanism secure (UUPS)
- [ ] Initialize only once
- [ ] Owner controls restricted

### Testing

- [ ] All functions tested
- [ ] Edge cases covered
- [ ] Revert conditions tested
- [ ] Access control tested
- [ ] Gas costs acceptable
- [ ] Fuzz tests passing

### Static Analysis

````bashRun Slither
slither src/ --exclude-dependenciesCheck for issues
Review all findings

---

## External Audit Recommendations

Consider engaging:
1. **OpenZeppelin** - https://openzeppelin.com/security-audits
2. **ConsenSys Diligence** - https://consensys.net/diligence/
3. **Trail of Bits** - https://www.trailofbits.com/
4. **Certik** - https://www.certik.com/

### Bug Bounty
After audit, launch bug bounty on:
- **Immunefi** - Leading DeFi platform
- **Code4rena** - Community reviews

**Recommended Tiers:**
- Critical: $50,000 - $100,000
- High: $10,000 - $25,000
- Medium: $2,500 - $5,000
- Low: $500 - $1,000

---

## Emergency Response Plan

### Incident Severity

**🔴 Critical (P0):**
- Immediate fund loss
- Contract exploit in progress
- System compromised

**🟠 High (P1):**
- Potential fund loss
- Major functionality broken

**🟡 Medium (P2):**
- Minor fund risk
- Reduced functionality

**🟢 Low (P3):**
- Informational
- Performance issues

### Response Procedures

**Critical Incident:**
1. Alert team (0-5 min)
2. Assess scope
3. Execute emergency withdrawal
4. Prepare communication
5. Deploy fixes (1-24 hours)
6. Post-mortem (24-72 hours)

### Emergency Commands
```bashForward all fees
cast send $HOOK_PROXY "forwardFees()"
--private-key $PRIVATE_KEY
--rpc-url $MAINNET_RPC_URLCheck system
forge script script/AdminScripts.s.sol:CheckSystemHealth

---

## Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Lead Dev | _____ | _____ | _____ |
| Security | _____ | _____ | _____ |
| Auditor | _____ | _____ | _____ |

**Remember:** Security is ongoing, not one-time!4. docs/GAS_OPTIMIZATION.mdmarkdown# Gas Optimization Guide

## Current Gas Costs (Estimated)

### Deployment @ 30 gwei
| Contract | Gas | Cost |
|----------|-----|------|
| GNOMEToken | ~1,200,000 | ~0.036 ETH |
| GnomeStickers | ~3,500,000 | ~0.105 ETH |
| Hook | ~2,500,000 | ~0.075 ETH |
| **Total** | **~7,200,000** | **~0.216 ETH** |

### Operations @ 30 gwei
| Operation | Gas | Cost |
|-----------|-----|------|
| Mint NFT | ~150,000 | ~0.0045 ETH |
| List NFT | ~120,000 | ~0.0036 ETH |
| Purchase | ~180,000 | ~0.0054 ETH |
| Forward Fees | ~50,000 | ~0.0015 ETH |

---

## Optimization Techniques Applied

### 1. Storage Optimization

**Packed Structs:**
```soliditystruct Listing {
uint256 price;      // Slot 1
address seller;     // Slot 2 (20 bytes)
bool isActive;      // Slot 2 (1 byte) - packed!
}

### 2. View Functions
```solidity// No gas when called externally
function getMintPrice(uint256 tokenId) public view returns (uint256) {
// Pure calculation
}

### 3. Efficient Loops
```solidity// Cache array length
uint256 length = activeListings.length;
for (uint256 i = 0; i < length; i++) {
// Process
}

---

## Gas Saving Tips

### 1. Custom Errors (Solidity 0.8.4+)
```solidity// Current
require(tokenId < MAX_SUPPLY, "Invalid token ID");// Optimized (~50 gas savings)
error InvalidTokenId(uint256 tokenId);
if (tokenId >= MAX_SUPPLY) revert InvalidTokenId(tokenId);

### 2. Unchecked Math (where safe)
```solidityunchecked {
// Safe because fee < price
uint256 proceeds = price - fee;
}

### 3. Short-Circuit Logic
```solidity// Put cheaper checks first
require(msg.sender != address(0) && balance > 0, "Invalid");

---

## Testing Gas

### Generate Report
```bashforge test --gas-report

### Take Snapshots
```bashBaseline
forge snapshotAfter changes
forge snapshot --diff

### Profile Function
```bashforge test --match-test testMint --gas-report

---

## Monitor Gas Prices
```bashCheck current gas
cast gas-price --rpc-url $MAINNET_RPC_URLDeploy during low gas
Typically: Late night/early morning UTC

---

## Gas Optimization Checklist

- [ ] Gas report reviewed
- [ ] Snapshot taken
- [ ] No unbounded loops
- [ ] Storage packed efficiently
- [ ] View/pure where possible
- [ ] Constants for fixed values
- [ ] Events for historical data

**Remember:** Profile first, optimize second!
````
