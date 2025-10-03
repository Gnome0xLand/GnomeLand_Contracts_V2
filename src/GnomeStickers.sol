// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title GnomeStickers
 * @notice ERC721 NFT with dynamic pricing and integrated marketplace
 * @dev Implements bonding curve pricing where the 72nd NFT costs ~1 ETH
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
    
    // Base URI for metadata
    string private _baseTokenURI;
    
    // Marketplace
    struct Listing {
        uint256 price;
        address seller;
        bool isActive;
    }
    
    mapping(uint256 => Listing) public listings;
    uint256 public floorPrice;
    uint256[] private activeListings;
    mapping(uint256 => uint256) private listingIndex;
    
    // Minting pool funded by Uniswap hook fees
    uint256 public mintingPool;
    
    event Minted(address indexed to, uint256 indexed tokenId, uint256 price);
    event Listed(uint256 indexed tokenId, uint256 price, address indexed seller);
    event Delisted(uint256 indexed tokenId, address indexed seller);
    event Purchased(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeesReceived(uint256 amount);
    event PricingMultiplierUpdated(uint256 newMultiplier);

    constructor(
        address _treasury,
        string memory baseURI
    ) ERC721("Gnomeland Stickers", "GNOME") Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
        _baseTokenURI = baseURI;
        
        // Calculate pricing multiplier so that token 72 costs 1 ETH
        pricingMultiplier = (TARGET_PRICE * 1000) / (TARGET_TOKEN_ID * TARGET_TOKEN_ID);
        
        floorPrice = type(uint256).max;
    }

    /**
     * @notice Calculate the price for minting a specific token ID
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
     * @notice Get the current mint price for the next token
     */
    function getCurrentMintPrice() external view returns (uint256) {
        return getMintPrice(_nextTokenId);
    }

    /**
     * @notice Mint a new NFT using funds from the minting pool
     */
    function mint() external nonReentrant {
        require(_nextTokenId < MAX_SUPPLY, "Max supply reached");
        
        uint256 price = getMintPrice(_nextTokenId);
        require(mintingPool >= price, "Insufficient minting pool funds");
        
        mintingPool -= price;
        
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        
        emit Minted(msg.sender, tokenId, price);
    }

    /**
     * @notice Admin mint function
     */
    function adminMint(address to) external onlyOwner {
        require(_nextTokenId < MAX_SUPPLY, "Max supply reached");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        emit Minted(to, tokenId, 0);
    }

    /**
     * @notice List an NFT for sale at floor price
     */
    function listAtFloor(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!listings[tokenId].isActive, "Already listed");
        
        uint256 price = floorPrice == type(uint256).max ? getMintPrice(tokenId) : floorPrice;
        
        _createListing(tokenId, price);
    }

    /**
     * @notice List an NFT for sale at a custom price
     */
    function listAtPrice(uint256 tokenId, uint256 price) external {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!listings[tokenId].isActive, "Already listed");
        require(price > 0, "Price must be positive");
        
        _createListing(tokenId, price);
    }

    /**
     * @dev Internal function to create a listing
     */
    function _createListing(uint256 tokenId, uint256 price) internal {
        listings[tokenId] = Listing({
            price: price,
            seller: msg.sender,
            isActive: true
        });
        
        listingIndex[tokenId] = activeListings.length;
        activeListings.push(tokenId);
        
        if (price < floorPrice) {
            floorPrice = price;
        }
        
        emit Listed(tokenId, price, msg.sender);
    }

    /**
     * @notice Delist an NFT from sale
     */
    function delist(uint256 tokenId) external {
        Listing storage listing = listings[tokenId];
        require(listing.isActive, "Not listed");
        require(listing.seller == msg.sender, "Not seller");
        
        _removeListing(tokenId);
        
        emit Delisted(tokenId, msg.sender);
    }

    /**
     * @notice Purchase a listed NFT
     */
    function purchase(uint256 tokenId) external payable nonReentrant {
        Listing storage listing = listings[tokenId];
        require(listing.isActive, "Not listed");
        require(msg.value >= listing.price, "Insufficient payment");
        
        uint256 price = listing.price;
        address seller = listing.seller;
        
        _removeListing(tokenId);
        
        uint256 treasuryFee = (price * TREASURY_FEE_BPS) / 10000;
        uint256 sellerProceeds = price - treasuryFee;
        
        _transfer(seller, msg.sender, tokenId);
        
        (bool treasurySuccess, ) = treasury.call{value: treasuryFee}("");
        require(treasurySuccess, "Treasury transfer failed");
        
        (bool sellerSuccess, ) = seller.call{value: sellerProceeds}("");
        require(sellerSuccess, "Seller transfer failed");
        
        if (msg.value > price) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - price}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit Purchased(tokenId, msg.sender, seller, price);
    }

    /**
     * @dev Remove a listing and update floor price
     */
    function _removeListing(uint256 tokenId) internal {
        uint256 listingPrice = listings[tokenId].price;
        delete listings[tokenId];
        
        uint256 index = listingIndex[tokenId];
        uint256 lastIndex = activeListings.length - 1;
        
        if (index != lastIndex) {
            uint256 lastTokenId = activeListings[lastIndex];
            activeListings[index] = lastTokenId;
            listingIndex[lastTokenId] = index;
        }
        
        activeListings.pop();
        delete listingIndex[tokenId];
        
        if (listingPrice == floorPrice) {
            _updateFloorPrice();
        }
    }

    /**
     * @dev Recalculate the floor price from active listings
     */
    function _updateFloorPrice() internal {
        if (activeListings.length == 0) {
            floorPrice = type(uint256).max;
            return;
        }
        
        uint256 newFloor = type(uint256).max;
        for (uint256 i = 0; i < activeListings.length; i++) {
            uint256 tokenId = activeListings[i];
            if (listings[tokenId].isActive && listings[tokenId].price < newFloor) {
                newFloor = listings[tokenId].price;
            }
        }
        floorPrice = newFloor;
    }

    /**
     * @notice Get all active listings
     */
    function getActiveListings() external view returns (
        uint256[] memory tokenIds,
        uint256[] memory prices,
        address[] memory sellers
    ) {
        uint256 count = activeListings.length;
        tokenIds = new uint256[](count);
        prices = new uint256[](count);
        sellers = new address[](count);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = activeListings[i];
            tokenIds[i] = tokenId;
            prices[i] = listings[tokenId].price;
            sellers[i] = listings[tokenId].seller;
        }
        
        return (tokenIds, prices, sellers);
    }

    /**
     * @notice Update the treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Update the pricing multiplier
     */
    function setPricingMultiplier(uint256 _multiplier) external onlyOwner {
        require(_multiplier > 0, "Invalid multiplier");
        pricingMultiplier = _multiplier;
        emit PricingMultiplierUpdated(_multiplier);
    }

    /**
     * @notice Update base URI for token metadata
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
     * @notice Get token URI for a specific token
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 
            ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
            : "";
    }

    /**
     * @notice Receive ETH from Uniswap hook to fund minting pool
     */
    receive() external payable {
        mintingPool += msg.value;
        emit FeesReceived(msg.value);
    }

    /**
     * @notice Get total number of minted tokens
     */
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }
}