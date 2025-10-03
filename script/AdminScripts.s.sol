// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GnomeStickers.sol";
import "../src/GnomelandHook.sol";
import "../src/GNOMEToken.sol";

contract UpdateTreasury is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address nftContractAddress = vm.envAddress("NFT_CONTRACT");
        address newTreasuryAddress = vm.envAddress("NEW_TREASURY_ADDRESS");
        
        require(newTreasuryAddress != address(0), "Invalid treasury");
        
        vm.startBroadcast(deployerPrivateKey);
        
        GnomeStickers nft = GnomeStickers(payable(nftContractAddress));
        
        address oldTreasury = nft.treasury();
        console.log("Current treasury:", oldTreasury);
        console.log("New treasury:", newTreasuryAddress);
        
        nft.setTreasury(newTreasuryAddress);
        
        console.log("✅ Treasury updated!");
        
        vm.stopBroadcast();
    }
}

contract UpdatePricing is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address nftContractAddress = vm.envAddress("NFT_CONTRACT");
        
        vm.startBroadcast(deployerPrivateKey);
        
        GnomeStickers nft = GnomeStickers(payable(nftContractAddress));
        
        console.log("=== Current Pricing ===");
        console.log("  Token 72:", nft.getMintPrice(72));
        
        // Example: Change to make 100th token cost 1 ETH
        uint256 newMultiplier = (1 ether * 1000) / (100 * 100);
        
        console.log("\n=== Updating Pricing ===");
        console.log("New multiplier:", newMultiplier);
        
        nft.setPricingMultiplier(newMultiplier);
        
        console.log("\n=== New Pricing ===");
        console.log("  Token 100:", nft.getMintPrice(100));
        
        console.log("\n✅ Pricing updated!");
        
        vm.stopBroadcast();
    }
}

contract UpdateHookConfig is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address hookProxyAddress = vm.envAddress("HOOK_PROXY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        GnomelandHook hook = GnomelandHook(payable(hookProxyAddress));
        
        console.log("=== Current Config ===");
        console.log("Fee Percentage:", hook.feePercentage());
        console.log("Threshold:", hook.autoTransferThreshold());
        
        // Update settings
        hook.setFeePercentage(75); // 0.75%
        hook.setAutoTransferThreshold(0.5 ether);
        
        console.log("\n=== Updated Config ===");
        console.log("Fee Percentage:", hook.feePercentage());
        console.log("Threshold:", hook.autoTransferThreshold());
        
        console.log("\n✅ Config updated!");
        
        vm.stopBroadcast();
    }
}

contract BatchMint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address nftContractAddress = vm.envAddress("NFT_CONTRACT");
        
        address[] memory recipients = new address[](3);
        recipients[0] = 0x1111111111111111111111111111111111111111;
        recipients[1] = 0x2222222222222222222222222222222222222222;
        recipients[2] = 0x3333333333333333333333333333333333333333;
        
        vm.startBroadcast(deployerPrivateKey);
        
        GnomeStickers nft = GnomeStickers(payable(nftContractAddress));
        
        console.log("=== Batch Minting ===");
        console.log("Current supply:", nft.totalSupply());
        
        for (uint256 i = 0; i < recipients.length; i++) {
            console.log("\nMinting to:", recipients[i]);
            nft.adminMint(recipients[i]);
        }
        
        console.log("\n✅ Batch mint complete!");
        console.log("New supply:", nft.totalSupply());
        
        vm.stopBroadcast();
    }
}

contract CheckSystemHealth is Script {
    function run() external view {
        address nftContractAddress = vm.envAddress("NFT_CONTRACT");
        address hookProxyAddress = vm.envAddress("HOOK_PROXY");
        
        console.log("=== SYSTEM HEALTH CHECK ===\n");
        
        GnomeStickers nft = GnomeStickers(payable(nftContractAddress));
        console.log("NFT Contract");
        console.log("  Total Minted:", nft.totalSupply());
        console.log("  Minting Pool:", nft.mintingPool());
        console.log("  Floor Price:", nft.floorPrice());
        
        GnomelandHook hook = GnomelandHook(payable(hookProxyAddress));
        console.log("\nHook Contract");
        console.log("  Accumulated Fees:", hook.accumulatedFees());
        console.log("  Fee Percentage:", hook.feePercentage());
        
        console.log("\n=== END HEALTH CHECK ===");
    }
}