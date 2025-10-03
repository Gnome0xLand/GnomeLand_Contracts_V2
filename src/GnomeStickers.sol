// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title GnomeStickers - Instant Liquidity NFT Marketplace
 * @notice NFTs with automated minting and instant buy/sell liquidity
 * @dev Contract acts as market maker - buys at floor, sells at 1.5x floor
 */
contract GnomeStickers is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // Token tracking
    uint256 private _nextTokenId;
    uint256 public constant MAX_SUPPLY = 10000;
    
    // Pricing parameters
    uint256 public constant TARGET_TOKEN_ID = 72;
    uint256 public constant TARGET_PRICE = 1 ether;
    uint256 public pricingMultiplier;
    
    // Treasury
    address public treasury;
    uint256 public constant TREASURY_FEE_BPS = 600; // 6%
    
    // Marketplace parameters
    uint256 public constant SELL_PRICE_MULTIPLIER = 150; // 1.5x = 150%
    uint256 public floorPrice;
    
    // Liquidity pool
    uint256 public liquidityPool; // ETH available for buying back NFTs
    
    // Base URI
    string private _baseTokenURI;
    
    // Track which NFTs are owned by contract (available for sale)
    mapping(uint256 => bool) public availableForPurchase;
    uint256[] public availableTokens;
    mapping(uint256 => uint256) private availableTokenIndex;
    
    event Minted(uint256 indexed tokenId, uint256 mintCost);
    event BoughtFromContract(address indexed buyer, uint256 indexed tokenId, uint256 price);
    event SoldToContract(address indexed seller, uint256 indexed tokenId, uint256 price);
    event FloorPriceUpdated(uint256 newFloorPrice);
    event LiquidityAdded(uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    constructor(
        address _treasury,
        string memory baseURI
    ) ERC721("Gnomeland Stickers", "GNOME") Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
        _baseTokenURI = baseURI;
        
        // Calculate pricing multiplier so that token 72 costs 1 ETH
        pricingMultiplier = (TARGET_PRICE * 1000) / (TARGET_TOKEN_ID * TARGET_TOKEN_ID);
        
        // Initial floor price
        floorPrice = getMintPrice(1);
    }

    /**
     * @notice Calculate the base price for minting a specific token ID
     */
    function getMintPrice(uint256 tokenId) public view returns (uint256) {
        if (tokenId == 0) return 0.001 ether;
        
        uint256 price = (pricingMultiplier * tokenId * tokenId) / 1000;
        
        if (price < 0.001 ether) {
            price = 0.001 ether;
        }
        
        return price;
    }

    /**
     * @notice Get current mint price for next token
     */
    function getCurrentMintPrice() public view returns (uint256) {
        return getMintPrice(_nextTokenId);
    }

    /**
     * @notice Get price to BUY from contract (1.5x floor)
     */
    function getBuyPrice() public view returns (uint256) {
        return (floorPrice * SELL_PRICE_MULTIPLIER) / 100;
    }

    /**
     * @notice Get price to SELL to contract (1x floor)
     */
    function getSellPrice() public view returns (uint256) {
        return floorPrice;
    }

    /**
     * @notice Hook contract mints new NFT when pool is sufficient
     * @dev Only callable by hook contract (owner)
     */
    function hookMint() external onlyOwner nonReentrant {
        require(_nextTokenId < MAX_SUPPLY, "Max supply reached");
        
        uint256 mintCost = getCurrentMintPrice();
        require(address(this).balance >= mintCost, "Insufficient contract balance");
        
        uint256 tokenId = _nextTokenId++;
        
        // Mint to this contract
        _safeMint(address(this), tokenId);
        
        // Mark as available for purchase
        availableForPurchase[tokenId] = true;
        availableTokenIndex[tokenId] = availableTokens.length;
        availableTokens.push(tokenId);
        
        // Update floor price based on mint cost
        _updateFloorPrice(mintCost);
        
        emit Minted(tokenId, mintCost);
    }

    /**
     * @notice Buy NFT from contract at 1.5x floor price
     * @param tokenId The token to purchase
     */
    function buyFromContract(uint256 tokenId) external payable nonReentrant {
        require(availableForPurchase[tokenId], "NFT not available");
        require(ownerOf(tokenId) == address(this), "Contract doesn't own this NFT");
        
        uint256 price = getBuyPrice();
        require(msg.value >= price, "Insufficient payment");
        
        // Remove from available list
        _removeFromAvailable(tokenId);
        
        // Transfer NFT to buyer
        _transfer(address(this), msg.sender, tokenId);
        
        // Add payment to liquidity pool
        liquidityPool += price;
        
        // Send treasury fee
        uint256 treasuryFee = (price * TREASURY_FEE_BPS) / 10000;
        if (treasuryFee > 0) {
            liquidityPool -= treasuryFee;
            (bool success, ) = treasury.call{value: treasuryFee}("");
            require(success, "Treasury transfer failed");
        }
        
        // Refund excess
        if (msg.value > price) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - price}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit BoughtFromContract(msg.sender, tokenId, price);
    }

    /**
     * @notice Sell NFT to contract at floor price (instant liquidity!)
     * @param tokenId The token to sell
     */
    function sellToContract(uint256 tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(_nextTokenId > 0, "No floor price set");
        
        uint256 price = getSellPrice();
        require(liquidityPool >= price, "Insufficient liquidity in contract");
        
        // Transfer NFT to contract
        _transfer(msg.sender, address(this), tokenId);
        
        // Mark as available for purchase
        availableForPurchase[tokenId] = true;
        availableTokenIndex[tokenId] = availableTokens.length;
        availableTokens.push(tokenId);
        
        // Pay seller
        liquidityPool -= price;
        (bool success, ) = msg.sender.call{value: price}("");
        require(success, "Payment to seller failed");
        
        emit SoldToContract(msg.sender, tokenId, price);
    }

    /**
     * @notice Get all NFTs available for purchase from contract
     */
    function getAvailableNFTs() external view returns (uint256[] memory) {
        return availableTokens;
    }

    /**
     * @notice Get count of available NFTs
     */
    function getAvailableCount() external view returns (uint256) {
        return availableTokens.length;
    }

    /**
     * @dev Remove token from available list
     */
    function _removeFromAvailable(uint256 tokenId) internal {
        availableForPurchase[tokenId] = false;
        
        uint256 index = availableTokenIndex[tokenId];
        uint256 lastIndex = availableTokens.length - 1;
        
        if (index != lastIndex) {
            uint256 lastTokenId = availableTokens[lastIndex];
            availableTokens[index] = lastTokenId;
            availableTokenIndex[lastTokenId] = index;
        }
        
        availableTokens.pop();
        delete availableTokenIndex[tokenId];
    }

    /**
     * @dev Update floor price based on mint cost
     */
    function _updateFloorPrice(uint256 newFloorPrice) internal {
        floorPrice = newFloorPrice;
        emit FloorPriceUpdated(newFloorPrice);
    }

    /**
     * @notice Manual floor price adjustment (admin)
     */
    function setFloorPrice(uint256 newFloorPrice) external onlyOwner {
        require(newFloorPrice > 0, "Invalid floor price");
        _updateFloorPrice(newFloorPrice);
    }

    /**
     * @notice Update treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Update pricing multiplier
     */
    function setPricingMultiplier(uint256 _multiplier) external onlyOwner {
        require(_multiplier > 0, "Invalid multiplier");
        pricingMultiplier = _multiplier;
    }

    /**
     * @notice Update base URI
     */
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Override to return base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Get token URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 
            ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
            : "";
    }

    /**
     * @notice Receive ETH from hook to fund minting and liquidity
     */
    receive() external payable {
        liquidityPool += msg.value;
        emit LiquidityAdded(msg.value);
    }

    /**
     * @notice Get total supply
     */
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @notice Get contract stats
     */
    function getStats() external view returns (
        uint256 totalMinted,
        uint256 availableCount,
        uint256 currentFloorPrice,
        uint256 buyPrice,
        uint256 sellPrice,
        uint256 contractLiquidity
    ) {
        return (
            _nextTokenId,
            availableTokens.length,
            floorPrice,
            getBuyPrice(),
            getSellPrice(),
            liquidityPool
        );
    }
}