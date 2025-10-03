// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GnomelandHook.sol";

contract UpgradeHook is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address hookProxyAddress = vm.envAddress("HOOK_PROXY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Upgrading Hook Implementation ===");
        console.log("Current Proxy:", hookProxyAddress);
        
        // Deploy new implementation
        console.log("\nDeploying new implementation...");
        GnomelandHook newImplementation = new GnomelandHook(IPoolManager(poolManagerAddress));
        console.log("New Implementation deployed at:", address(newImplementation));
        
        // Get current implementation
        GnomelandHook proxy = GnomelandHook(payable(hookProxyAddress));
        
        console.log("\nCurrent state:");
        console.log("  NFT Contract:", proxy.nftContract());
        console.log("  Fee Percentage:", proxy.feePercentage());
        
        // Upgrade
        console.log("\nUpgrading proxy...");
        proxy.upgradeToAndCall(address(newImplementation), "");
        
        console.log("\n✅ Upgrade complete!");
        console.log("Proxy:", hookProxyAddress);
        console.log("New Implementation:", address(newImplementation));
        
        vm.stopBroadcast();
        
        // Save upgrade info
        string memory upgradeInfo = string.concat(
            '{\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "proxyAddress": "', vm.toString(hookProxyAddress), '",\n',
            '  "newImplementation": "', vm.toString(address(newImplementation)), '"\n',
            '}'
        );
        
        string memory filename = string.concat(
            "deployments/upgrade-",
            vm.toString(block.timestamp),
            ".json"
        );
        vm.writeFile(filename, upgradeInfo);
        console.log("\nUpgrade info saved to", filename);
    }
}