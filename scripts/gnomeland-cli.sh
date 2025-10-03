#!/bin/bash

# Gnomeland CLI Tool
# Interactive command-line interface for managing Gnomeland contracts

set -e

# Load environment
if [ -f .env ]; then
    source .env
else
    echo "❌ .env file not found!"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper functions
print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  $1"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

wei_to_eth() {
    cast --to-unit $1 ether 2>/dev/null || echo "0"
}

# Main menu
show_menu() {
    clear
    print_header "🍄 GNOMELAND CLI v1.0"
    echo ""
    echo -e "${MAGENTA}NFT Operations:${NC}"
    echo "  1) Mint NFT"
    echo "  2) List NFT for Sale"
    echo "  3) Purchase NFT"
    echo "  4) Delist NFT"
    echo "  5) View My NFTs"
    echo ""
    echo -e "${MAGENTA}Marketplace:${NC}"
    echo "  6) View All Listings"
    echo "  7) Check Floor Price"
    echo "  8) View NFT Details"
    echo ""
    echo -e "${MAGENTA}System Info:${NC}"
    echo "  9) System Dashboard"
    echo " 10) Check Mint Price"
    echo " 11) Check Minting Pool"
    echo " 12) Check Hook Fees"
    echo ""
    echo -e "${MAGENTA}Admin (Owner Only):${NC}"
    echo " 13) Fund Minting Pool"
    echo " 14) Forward Hook Fees"
    echo " 15) Update Treasury"
    echo " 16) Admin Mint"
    echo ""
    echo " 0) Exit"
    echo ""
    echo -n "Select option: "
}

# NFT Operations
mint_nft() {
    print_header "Mint NFT"
    
    # Check mint price
    PRICE=$(cast call $NFT_CONTRACT "getCurrentMintPrice()(uint256)" --rpc-url $RPC_URL)
    PRICE_ETH=$(wei_to_eth $PRICE)
    
    echo "Current mint price: ${PRICE_ETH} ETH"
    
    # Check minting pool
    POOL=$(cast call $NFT_CONTRACT "mintingPool()(uint256)" --rpc-url $RPC_URL)
    POOL_ETH=$(wei_to_eth $POOL)
    
    echo "Minting pool balance: ${POOL_ETH} ETH"
    
    if (( $(echo "$POOL_ETH < $PRICE_ETH" | bc -l) )); then
        print_error "Insufficient funds in minting pool!"
        echo ""
        echo "Options:"
        echo "1. Wait for hook fees to accumulate"
        echo "2. Manually fund pool (Admin only)"
        read -p "Press enter to continue..."
        return
    fi
    
    echo ""
    read -p "Confirm mint? (y/n): " confirm
    
    if [ "$confirm" == "y" ]; then
        echo "Minting..."
        TX=$(cast send $NFT_CONTRACT "mint()" \
            --private-key $PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            TX_HASH=$(echo $TX | jq -r '.transactionHash')
            print_success "NFT minted! TX: $TX_HASH"
            
            # Get token ID
            SUPPLY=$(cast call $NFT_CONTRACT "totalSupply()(uint256)" --rpc-url $RPC_URL)
            TOKEN_ID=$((SUPPLY - 1))
            echo "Your NFT Token ID: $TOKEN_ID"
        else
            print_error "Mint failed!"
        fi
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

list_nft() {
    print_header "List NFT for Sale"
    
    echo -n "Enter Token ID: "
    read TOKEN_ID
    
    # Verify ownership
    OWNER=$(cast call $NFT_CONTRACT "ownerOf(uint256)(address)" $TOKEN_ID --rpc-url $RPC_URL 2>/dev/null)
    if [ $? -ne 0 ]; then
        print_error "Token does not exist!"
        read -p "Press enter to continue..."
        return
    fi
    
    MY_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
    
    if [ "${OWNER,,}" != "${MY_ADDRESS,,}" ]; then
        print_error "You don't own this NFT!"
        echo "Owner: $OWNER"
        echo "You: $MY_ADDRESS"
        read -p "Press enter to continue..."
        return
    fi
    
    # Get floor price
    FLOOR=$(cast call $NFT_CONTRACT "floorPrice()(uint256)" --rpc-url $RPC_URL)
    FLOOR_ETH=$(wei_to_eth $FLOOR)
    
    echo ""
    echo "Current floor price: ${FLOOR_ETH} ETH"
    echo ""
    echo "Listing options:"
    echo "  1) List at floor price"
    echo "  2) List at custom price"
    echo -n "Select: "
    read OPTION
    
    if [ "$OPTION" == "1" ]; then
        echo "Listing at floor price..."
        TX=$(cast send $NFT_CONTRACT "listAtFloor(uint256)" $TOKEN_ID \
            --private-key $PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            TX_HASH=$(echo $TX | jq -r '.transactionHash')
            print_success "Listed! TX: $TX_HASH"
        else
            print_error "Listing failed!"
        fi
    elif [ "$OPTION" == "2" ]; then
        echo -n "Enter price in ETH: "
        read PRICE_ETH
        PRICE_WEI=$(cast --to-wei $PRICE_ETH ether)
        
        echo "Listing at ${PRICE_ETH} ETH..."
        TX=$(cast send $NFT_CONTRACT "listAtPrice(uint256,uint256)" $TOKEN_ID $PRICE_WEI \
            --private-key $PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            TX_HASH=$(echo $TX | jq -r '.transactionHash')
            print_success "Listed! TX: $TX_HASH"
        else
            print_error "Listing failed!"
        fi
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

purchase_nft() {
    print_header "Purchase NFT"
    
    echo -n "Enter Token ID: "
    read TOKEN_ID
    
    # Get listing info
    LISTING=$(cast call $NFT_CONTRACT "listings(uint256)(uint256,address,bool)" $TOKEN_ID --rpc-url $RPC_URL 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_error "Could not fetch listing info!"
        read -p "Press enter to continue..."
        return
    fi
    
    PRICE=$(echo $LISTING | awk '{print $1}')
    SELLER=$(echo $LISTING | awk '{print $2}')
    ACTIVE=$(echo $LISTING | awk '{print $3}')
    
    if [ "$ACTIVE" != "true" ]; then
        print_error "NFT is not listed for sale!"
        read -p "Press enter to continue..."
        return
    fi
    
    PRICE_ETH=$(wei_to_eth $PRICE)
    
    echo "Price: ${PRICE_ETH} ETH"
    echo "Seller: $SELLER"
    echo ""
    read -p "Confirm purchase? (y/n): " confirm
    
    if [ "$confirm" == "y" ]; then
        echo "Purchasing..."
        TX=$(cast send $NFT_CONTRACT "purchase(uint256)" $TOKEN_ID \
            --value ${PRICE}wei \
            --private-key $PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            TX_HASH=$(echo $TX | jq -r '.transactionHash')
            print_success "Purchased! TX: $TX_HASH"
            echo "You now own token #$TOKEN_ID"
        else
            print_error "Purchase failed!"
        fi
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

delist_nft() {
    print_header "Delist NFT"
    
    echo -n "Enter Token ID: "
    read TOKEN_ID
    
    echo "Delisting..."
    TX=$(cast send $NFT_CONTRACT "delist(uint256)" $TOKEN_ID \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo $TX | jq -r '.transactionHash')
        print_success "Delisted! TX: $TX_HASH"
    else
        print_error "Delist failed!"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

view_my_nfts() {
    print_header "My NFTs"
    
    MY_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
    BALANCE=$(cast call $NFT_CONTRACT "balanceOf(address)(uint256)" $MY_ADDRESS --rpc-url $RPC_URL 2>/dev/null)
    
    echo "Your address: $MY_ADDRESS"
    echo "You own $BALANCE NFT(s)"
    echo ""
    
    if [ "$BALANCE" -gt 0 ]; then
        echo "Scanning for your NFTs..."
        TOTAL_SUPPLY=$(cast call $NFT_CONTRACT "totalSupply()(uint256)" --rpc-url $RPC_URL)
        
        echo "Token IDs you own:"
        for ((i=0; i<$TOTAL_SUPPLY; i++)); do
            OWNER=$(cast call $NFT_CONTRACT "ownerOf(uint256)(address)" $i --rpc-url $RPC_URL 2>/dev/null)
            if [ "${OWNER,,}" == "${MY_ADDRESS,,}" ]; then
                echo "  • Token #$i"
            fi
        done
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

# Marketplace
view_all_listings() {
    print_header "All Active Listings"
    
    echo "Fetching listings..."
    
    # This requires more complex parsing - simplified version
    RESULT=$(cast call $NFT_CONTRACT "getActiveListings()(uint256[],uint256[],address[])" --rpc-url $RPC_URL 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "Active listings found!"
        echo "(Note: Use web interface or block explorer for detailed view)"
        echo ""
        echo "Raw data:"
        echo "$RESULT"
    else
        print_error "Could not fetch listings"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

check_floor_price() {
    print_header "Floor Price"
    
    FLOOR=$(cast call $NFT_CONTRACT "floorPrice()(uint256)" --rpc-url $RPC_URL)
    
    if [ "$FLOOR" == "115792089237316195423570985008687907853269984665640564039457584007913129639935" ]; then
        echo "No active listings"
    else
        FLOOR_ETH=$(wei_to_eth $FLOOR)
        echo "Current floor price: ${FLOOR_ETH} ETH"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

view_nft_details() {
    print_header "NFT Details"
    
    echo -n "Enter Token ID: "
    read TOKEN_ID
    
    # Owner
    OWNER=$(cast call $NFT_CONTRACT "ownerOf(uint256)(address)" $TOKEN_ID --rpc-url $RPC_URL 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        print_error "Token does not exist or not minted yet"
        read -p "Press enter to continue..."
        return
    fi
    
    echo "Owner: $OWNER"
    
    # Listing status
    LISTING=$(cast call $NFT_CONTRACT "listings(uint256)(uint256,address,bool)" $TOKEN_ID --rpc-url $RPC_URL 2>/dev/null)
    PRICE=$(echo $LISTING | awk '{print $1}')
    ACTIVE=$(echo $LISTING | awk '{print $3}')
    
    if [ "$ACTIVE" == "true" ]; then
        PRICE_ETH=$(wei_to_eth $PRICE)
        echo "Status: Listed for ${PRICE_ETH} ETH"
    else
        echo "Status: Not listed"
    fi
    
    # Token URI
    TOKEN_URI=$(cast call $NFT_CONTRACT "tokenURI(uint256)(string)" $TOKEN_ID --rpc-url $RPC_URL 2>/dev/null || echo "Not available")
    echo "Metadata URI: $TOKEN_URI"
    
    echo ""
    read -p "Press enter to continue..."
}

# System Info
system_dashboard() {
    clear
    print_header "System Dashboard"
    
    echo -e "${CYAN}📊 NFT Contract${NC}"
    SUPPLY=$(cast call $NFT_CONTRACT "totalSupply()(uint256)" --rpc-url $RPC_URL 2>/dev/null || echo "0")
    echo "  Total Minted: $SUPPLY / 10000"
    
    POOL=$(cast call $NFT_CONTRACT "mintingPool()(uint256)" --rpc-url $RPC_URL 2>/dev/null || echo "0")
    POOL_ETH=$(wei_to_eth $POOL)
    echo "  Minting Pool: ${POOL_ETH} ETH"
    
    FLOOR=$(cast call $NFT_CONTRACT "floorPrice()(uint256)" --rpc-url $RPC_URL 2>/dev/null || echo "0")
    if [ "$FLOOR" == "115792089237316195423570985008687907853269984665640564039457584007913129639935" ]; then
        echo "  Floor Price: No listings"
    else
        FLOOR_ETH=$(wei_to_eth $FLOOR)
        echo "  Floor Price: ${FLOOR_ETH} ETH"
    fi
    
    echo ""
    echo -e "${CYAN}🪝 Uniswap Hook${NC}"
    FEES=$(cast call $HOOK_PROXY "accumulatedFees()(uint256)" --rpc-url $RPC_URL 2>/dev/null || echo "0")
    FEES_ETH=$(wei_to_eth $FEES)
    echo "  Accumulated Fees: ${FEES_ETH} ETH"
    
    FEE_PCT=$(cast call $HOOK_PROXY "feePercentage()(uint256)" --rpc-url $RPC_URL 2>/dev/null || echo "0")
    FEE_PERCENT=$(echo "scale=2; $FEE_PCT / 100" | bc)
    echo "  Fee Percentage: ${FEE_PERCENT}%"
    
    echo ""
    echo -e "${CYAN}💰 Treasury${NC}"
    TREASURY=$(cast call $NFT_CONTRACT "treasury()(address)" --rpc-url $RPC_URL 2>/dev/null || echo "Unknown")
    TREASURY_BAL=$(cast balance $TREASURY --rpc-url $RPC_URL 2>/dev/null || echo "0")
    TREASURY_ETH=$(wei_to_eth $TREASURY_BAL)
    echo "  Address: $TREASURY"
    echo "  Balance: ${TREASURY_ETH} ETH"
    
    echo ""
    echo -e "${CYAN}⛽ Network${NC}"
    GAS=$(cast gas-price --rpc-url $RPC_URL 2>/dev/null || echo "0")
    GAS_GWEI=$(cast --to-unit $GAS gwei 2>/dev/null || echo "0")
    echo "  Gas Price: ${GAS_GWEI} gwei"
    
    BLOCK=$(cast block-number --rpc-url $RPC_URL 2>/dev/null || echo "0")
    echo "  Block Number: $BLOCK"
    
    echo ""
    read -p "Press enter to continue..."
}

check_mint_price() {
    print_header "Current Mint Price"
    
    PRICE=$(cast call $NFT_CONTRACT "getCurrentMintPrice()(uint256)" --rpc-url $RPC_URL)
    PRICE_ETH=$(wei_to_eth $PRICE)
    
    echo "Next NFT mint price: ${PRICE_ETH} ETH"
    
    SUPPLY=$(cast call $NFT_CONTRACT "totalSupply()(uint256)" --rpc-url $RPC_URL)
    echo "This would be token #$SUPPLY"
    
    echo ""
    read -p "Press enter to continue..."
}

check_minting_pool() {
    print_header "Minting Pool Status"
    
    POOL=$(cast call $NFT_CONTRACT "mintingPool()(uint256)" --rpc-url $RPC_URL)
    POOL_ETH=$(wei_to_eth $POOL)
    
    echo "Minting Pool Balance: ${POOL_ETH} ETH"
    
    PRICE=$(cast call $NFT_CONTRACT "getCurrentMintPrice()(uint256)" --rpc-url $RPC_URL)
    PRICE_ETH=$(wei_to_eth $PRICE)
    
    echo "Current Mint Price: ${PRICE_ETH} ETH"
    
    if (( $(echo "$POOL_ETH > 0 && $PRICE_ETH > 0" | bc -l) )); then
        MINTS_AVAILABLE=$(echo "$POOL_ETH / $PRICE_ETH" | bc)
        echo "Approximate mints available: $MINTS_AVAILABLE"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

check_hook_fees() {
    print_header "Hook Accumulated Fees"
    
    FEES=$(cast call $HOOK_PROXY "accumulatedFees()(uint256)" --rpc-url $RPC_URL)
    FEES_ETH=$(wei_to_eth $FEES)
    
    echo "Accumulated fees: ${FEES_ETH} ETH"
    
    THRESHOLD=$(cast call $HOOK_PROXY "autoTransferThreshold()(uint256)" --rpc-url $RPC_URL)
    THRESHOLD_ETH=$(wei_to_eth $THRESHOLD)
    
    echo "Auto-transfer threshold: ${THRESHOLD_ETH} ETH"
    
    if (( $(echo "$FEES_ETH >= $THRESHOLD_ETH" | bc -l) )); then
        print_warning "Fees ready to forward!"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

# Admin Functions
fund_minting_pool() {
    print_header "Fund Minting Pool (Admin)"
    
    echo -n "Enter amount in ETH: "
    read AMOUNT
    
    echo "Funding pool with ${AMOUNT} ETH..."
    TX=$(cast send $NFT_CONTRACT \
        --value ${AMOUNT}ether \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo $TX | jq -r '.transactionHash')
        print_success "Funded! TX: $TX_HASH"
    else
        print_error "Funding failed!"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

forward_hook_fees() {
    print_header "Forward Hook Fees (Admin)"
    
    FEES=$(cast call $HOOK_PROXY "accumulatedFees()(uint256)" --rpc-url $RPC_URL)
    FEES_ETH=$(wei_to_eth $FEES)
    
    echo "Forwarding ${FEES_ETH} ETH to NFT contract..."
    TX=$(cast send $HOOK_PROXY "forwardFees()" \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo $TX | jq -r '.transactionHash')
        print_success "Forwarded! TX: $TX_HASH"
    else
        print_error "Forward failed!"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

update_treasury() {
    print_header "Update Treasury (Admin)"
    
    CURRENT=$(cast call $NFT_CONTRACT "treasury()(address)" --rpc-url $RPC_URL)
    echo "Current treasury: $CURRENT"
    echo ""
    echo -n "Enter new treasury address: "
    read NEW_TREASURY
    
    echo "Updating treasury..."
    TX=$(cast send $NFT_CONTRACT "setTreasury(address)" $NEW_TREASURY \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo $TX | jq -r '.transactionHash')
        print_success "Updated! TX: $TX_HASH"
    else
        print_error "Update failed!"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

admin_mint() {
    print_header "Admin Mint (Admin)"
    
    echo -n "Enter recipient address: "
    read RECIPIENT
    
    echo "Minting NFT to $RECIPIENT..."
    TX=$(cast send $NFT_CONTRACT "adminMint(address)" $RECIPIENT \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        TX_HASH=$(echo $TX | jq -r '.transactionHash')
        print_success "Minted! TX: $TX_HASH"
    else
        print_error "Mint failed!"
    fi
    
    echo ""
    read -p "Press enter to continue..."
}

# Main loop
main() {
    # Check dependencies
    command -v cast >/dev/null 2>&1 || { 
        print_error "cast not found. Please install Foundry."
        exit 1
    }
    
    command -v bc >/dev/null 2>&1 || { 
        print_error "bc not found. Please install bc."
        exit 1
    }
    
    command -v jq >/dev/null 2>&1 || { 
        print_warning "jq not found. Some features may not work."
    }
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) mint_nft ;;
            2) list_nft ;;
            3) purchase_nft ;;
            4) delist_nft ;;
            5) view_my_nfts ;;
            6) view_all_listings ;;
            7) check_floor_price ;;
            8) view_nft_details ;;
            9) system_dashboard ;;
            10) check_mint_price ;;
            11) check_minting_pool ;;
            12) check_hook_fees ;;
            13) fund_minting_pool ;;
            14) forward_hook_fees ;;
            15) update_treasury ;;
            16) admin_mint ;;
            0) 
                clear
                echo "Goodbye! 🍄"
                exit 0 
                ;;
            *) 
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Run
main