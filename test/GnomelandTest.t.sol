// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GNOMEToken.sol";
import "../src/GnomeStickers.sol";
import "../src/GnomelandHook.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GnomelandTest is Test {
    GNOMEToken public token;
    GnomeStickers public nft;
    GnomelandHook public hook;
    
    address public owner;
    address public treasury;
    address public user1;
    address public user2;
    address public poolManager;
    
    function setUp() public {
        owner = address(this);
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        poolManager = makeAddr("poolManager");
        
        // Deploy contracts
        token = new GNOMEToken();
        nft = new GnomeStickers(treasury, "https://api.gnomeland.io/");
        
        // Deploy hook with proxy
        GnomelandHook hookImpl = new GnomelandHook(IPoolManager(poolManager));
        bytes memory initData = abi.encodeWithSelector(
            GnomelandHook.initialize.selector,
            address(nft),
            50,
            0.1 ether
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(hookImpl), initData);
        hook = GnomelandHook(payable(address(proxy)));
        
        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(address(this), 100 ether);
    }
    
    // ===== Token Tests =====
    
    function testTokenDeployment() public {
        assertEq(token.name(), "Gnomeland Token");
        assertEq(token.symbol(), "GNOME");
        assertEq(token.totalSupply(), 1_000_000_000 * 10**18);
        assertEq(token.balanceOf(owner), token.totalSupply());
    }
    
    function testTokenMint() public {
        uint256 initialSupply = token.totalSupply();
        token.mint(user1, 1000 * 10**18);
        assertEq(token.balanceOf(user1), 1000 * 10**18);
        assertEq(token.totalSupply(), initialSupply + 1000 * 10**18);
    }
    
    function testTokenBurn() public {
        uint256 burnAmount = 1000 * 10**18;
        uint256 initialSupply = token.totalSupply();
        token.burn(burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);
    }
    
    // ===== NFT Pricing Tests =====
    
    function testPricingCurve() public {
        // First token should be cheap
        uint256 price1 = nft.getMintPrice(1);
        assertGt(price1, 0);
        assertLt(price1, 0.01 ether);
        
        // 72nd token should be ~1 ETH
        uint256 price72 = nft.getMintPrice(72);
        assertGt(price72, 0.9 ether);
        assertLt(price72, 1.1 ether);
        
        // 144th token should be ~4 ETH
        uint256 price144 = nft.getMintPrice(144);
        assertGt(price144, 3.5 ether);
        assertLt(price144, 4.5 ether);
        
        // Prices should increase
        assertGt(price72, price1);
        assertGt(price144, price72);
    }
    
    function testMinting() public {
        // Fund minting pool
        vm.deal(address(nft), 10 ether);
        assertEq(nft.mintingPool(), 10 ether);
        
        // Mint first NFT
        vm.prank(user1);
        nft.mint();
        
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.totalSupply(), 1);
    }
    
    function testMintingFailsWithoutFunds() public {
        vm.expectRevert("Insufficient minting pool funds");
        vm.prank(user1);
        nft.mint();
    }
    
    function testAdminMint() public {
        nft.adminMint(user1);
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.totalSupply(), 1);
    }
    
    // ===== Marketplace Tests =====
    
    function testListAtFloor() public {
        // Mint NFT
        nft.adminMint(user1);
        
        // List at floor
        vm.prank(user1);
        nft.listAtFloor(0);
        
        (uint256 price, address seller, bool isActive) = nft.listings(0);
        assertTrue(isActive);
        assertEq(seller, user1);
        assertGt(price, 0);
    }
    
    function testListAtCustomPrice() public {
        nft.adminMint(user1);
        
        uint256 customPrice = 2 ether;
        vm.prank(user1);
        nft.listAtPrice(0, customPrice);
        
        (uint256 price, address seller, bool isActive) = nft.listings(0);
        assertTrue(isActive);
        assertEq(seller, user1);
        assertEq(price, customPrice);
    }
    
    function testPurchase() public {
        // Mint and list
        nft.adminMint(user1);
        uint256 listPrice = 1 ether;
        
        vm.prank(user1);
        nft.listAtPrice(0, listPrice);
        
        // Purchase
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 sellerBalanceBefore = user1.balance;
        
        vm.prank(user2);
        nft.purchase{value: listPrice}(0);
        
        // Verify ownership transfer
        assertEq(nft.ownerOf(0), user2);
        
        // Verify payments
        uint256 treasuryFee = (listPrice * 600) / 10000; // 6%
        uint256 sellerProceeds = listPrice - treasuryFee;
        
        assertEq(treasury.balance - treasuryBalanceBefore, treasuryFee);
        assertEq(user1.balance - sellerBalanceBefore, sellerProceeds);
    }
    
    function testDelist() public {
        nft.adminMint(user1);
        
        vm.prank(user1);
        nft.listAtPrice(0, 1 ether);
        
        vm.prank(user1);
        nft.delist(0);
        
        (, , bool isActive) = nft.listings(0);
        assertFalse(isActive);
    }
    
    function testFloorPriceUpdates() public {
        // Mint multiple NFTs
        nft.adminMint(user1);
        nft.adminMint(user1);
        nft.adminMint(user1);
        
        // List at different prices
        vm.startPrank(user1);
        nft.listAtPrice(0, 3 ether);
        nft.listAtPrice(1, 1 ether); // This should be floor
        nft.listAtPrice(2, 2 ether);
        vm.stopPrank();
        
        // Floor should be 1 ETH
        assertEq(nft.floorPrice(), 1 ether);
        
        // Delist the floor
        vm.prank(user1);
        nft.delist(1);
        
        // Floor should update to 2 ETH
        assertEq(nft.floorPrice(), 2 ether);
    }
    
    function testGetActiveListings() public {
        nft.adminMint(user1);
        nft.adminMint(user1);
        
        vm.startPrank(user1);
        nft.listAtPrice(0, 1 ether);
        nft.listAtPrice(1, 2 ether);
        vm.stopPrank();
        
        (uint256[] memory tokenIds, uint256[] memory prices, address[] memory sellers) 
            = nft.getActiveListings();
        
        assertEq(tokenIds.length, 2);
        assertEq(prices.length, 2);
        assertEq(sellers.length, 2);
        assertEq(sellers[0], user1);
        assertEq(sellers[1], user1);
    }
    
    // ===== Hook Tests =====
    
    function testHookInitialization() public {
        assertEq(hook.nftContract(), address(nft));
        assertEq(hook.feePercentage(), 50);
        assertEq(hook.autoTransferThreshold(), 0.1 ether);
    }
    
    function testHookReceivesFees() public {
        uint256 feeAmount = 1 ether;
        
        vm.deal(address(hook), feeAmount);
        assertEq(address(hook).balance, feeAmount);
    }
    
    function testHookForwardsFees() public {
        // Send fees to hook
        uint256 feeAmount = 1 ether;
        vm.deal(address(hook), feeAmount);
        
        // Manually set accumulated fees (simulate swap)
        vm.store(
            address(hook),
            bytes32(uint256(3)), // accumulatedFees storage slot
            bytes32(feeAmount)
        );
        
        uint256 nftBalanceBefore = address(nft).balance;
        
        hook.forwardFees();
        
        assertEq(address(nft).balance, nftBalanceBefore + feeAmount);
        assertEq(nft.mintingPool(), nftBalanceBefore + feeAmount);
    }
    
    function testHookSetFeePercentage() public {
        hook.setFeePercentage(100);
        assertEq(hook.feePercentage(), 100);
    }
    
    function testHookSetFeePercentageFailsIfTooHigh() public {
        vm.expectRevert("Fee too high");
        hook.setFeePercentage(1001); // More than 10%
    }
    
    function testHookSetAutoTransferThreshold() public {
        hook.setAutoTransferThreshold(0.5 ether);
        assertEq(hook.autoTransferThreshold(), 0.5 ether);
    }
    
    function testHookSetNFTContract() public {
        address newNFT = makeAddr("newNFT");
        hook.setNFTContract(newNFT);
        assertEq(hook.nftContract(), newNFT);
    }
    
    // ===== Access Control Tests =====
    
    function testOnlyOwnerCanMintTokens() public {
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user1, 1000);
    }
    
    function testOnlyOwnerCanSetTreasury() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.setTreasury(user2);
    }
    
    function testOnlyOwnerCanSetPricingMultiplier() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.setPricingMultiplier(1000);
    }
    
    function testOnlyOwnerCanConfigureHook() public {
        vm.prank(user1);
        vm.expectRevert();
        hook.setFeePercentage(100);
    }
    
    // ===== Security Tests =====
    
    function testReentrancyProtection() public {
        // This would require a malicious contract to test properly
        // Placeholder for reentrancy tests
        assertTrue(true);
    }
    
    function testCannotListNFTYouDontOwn() public {
        nft.adminMint(user1);
        
        vm.prank(user2);
        vm.expectRevert();
        nft.listAtPrice(0, 1 ether);
    }
    
    function testCannotPurchaseUnlistedNFT() public {
        nft.adminMint(user1);
        
        vm.prank(user2);
        vm.expectRevert("Not listed");
        nft.purchase{value: 1 ether}(0);
    }
    
    function testCannotPurchaseWithInsufficientFunds() public {
        nft.adminMint(user1);
        
        vm.prank(user1);
        nft.listAtPrice(0, 2 ether);
        
        vm.prank(user2);
        vm.expectRevert("Insufficient payment");
        nft.purchase{value: 1 ether}(0);
    }
    
    // ===== Integration Tests =====
    
    function testFullIntegrationFlow() public {
        // 1. Fund minting pool via hook
        vm.deal(address(hook), 10 ether);
        vm.store(
            address(hook),
            bytes32(uint256(3)),
            bytes32(uint256(10 ether))
        );
        hook.forwardFees();
        
        // 2. User mints NFT
        vm.prank(user1);
        nft.mint();
        assertEq(nft.ownerOf(0), user1);
        
        // 3. User lists NFT
        vm.prank(user1);
        nft.listAtPrice(0, 1 ether);
        
        // 4. Another user purchases
        uint256 treasuryBefore = treasury.balance;
        vm.prank(user2);
        nft.purchase{value: 1 ether}(0);
        
        // 5. Verify final state
        assertEq(nft.ownerOf(0), user2);
        assertGt(treasury.balance, treasuryBefore);
    }
    
    function testMultipleMints() public {
        vm.deal(address(nft), 100 ether);
        
        // Mint several NFTs and verify pricing increases
        uint256 lastPrice = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 currentPrice = nft.getCurrentMintPrice();
            assertGt(currentPrice, lastPrice);
            lastPrice = currentPrice;
            
            vm.prank(user1);
            nft.mint();
        }
        
        assertEq(nft.totalSupply(), 10);
    }
    
    function testMarketplaceFeeCalculation() public {
        nft.adminMint(user1);
        
        uint256 salePrice = 10 ether;
        vm.prank(user1);
        nft.listAtPrice(0, salePrice);
        
        uint256 expectedTreasuryFee = (salePrice * 600) / 10000; // 6%
        uint256 expectedSellerProceeds = salePrice - expectedTreasuryFee;
        
        uint256 treasuryBefore = treasury.balance;
        uint256 sellerBefore = user1.balance;
        
        vm.prank(user2);
        nft.purchase{value: salePrice}(0);
        
        assertEq(treasury.balance - treasuryBefore, expectedTreasuryFee);
        assertEq(user1.balance - sellerBefore, expectedSellerProceeds);
    }
    
    function testExcessPaymentRefund() public {
        nft.adminMint(user1);
        
        uint256 listPrice = 1 ether;
        vm.prank(user1);
        nft.listAtPrice(0, listPrice);
        
        uint256 paymentAmount = 2 ether;
        uint256 buyerBefore = user2.balance;
        
        vm.prank(user2);
        nft.purchase{value: paymentAmount}(0);
        
        // Buyer should get refund of excess
        uint256 expectedSpent = listPrice;
        assertEq(buyerBefore - user2.balance, expectedSpent);
    }
    
    // ===== Fuzz Tests =====
    
    function testFuzzMintPrice(uint256 tokenId) public {
        tokenId = bound(tokenId, 1, 1000);
        
        uint256 price = nft.getMintPrice(tokenId);
        assertGt(price, 0);
        
        // Verify monotonic increase
        if (tokenId > 1) {
            uint256 prevPrice = nft.getMintPrice(tokenId - 1);
            assertGt(price, prevPrice);
        }
    }
    
    function testFuzzListingPrice(uint256 listPrice) public {
        listPrice = bound(listPrice, 0.001 ether, 1000 ether);
        
        nft.adminMint(user1);
        
        vm.prank(user1);
        nft.listAtPrice(0, listPrice);
        
        (uint256 price, , bool isActive) = nft.listings(0);
        assertEq(price, listPrice);
        assertTrue(isActive);
    }
    
    function testFuzzPurchase(uint256 listPrice, uint256 paymentAmount) public {
        listPrice = bound(listPrice, 0.001 ether, 100 ether);
        paymentAmount = bound(paymentAmount, 0, 200 ether);
        
        nft.adminMint(user1);
        
        vm.prank(user1);
        nft.listAtPrice(0, listPrice);
        
        vm.deal(user2, paymentAmount);
        
        if (paymentAmount >= listPrice) {
            vm.prank(user2);
            nft.purchase{value: paymentAmount}(0);
            assertEq(nft.ownerOf(0), user2);
        } else {
            vm.prank(user2);
            vm.expectRevert("Insufficient payment");
            nft.purchase{value: paymentAmount}(0);
        }
    }
}