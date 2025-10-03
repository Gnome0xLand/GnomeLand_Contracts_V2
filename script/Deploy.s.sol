// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GNOMEToken.sol";
import "../src/GnomeStickers.sol";
import "../src/GnomelandHook.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy GNOME Token
        console.log("Deploying GNOME Token...");
        GNOMEToken gnomeToken = new GNOMEToken();
        console.log("GNOME Token deployed at:", address(gnomeToken));
        
        // 2. Deploy NFT Contract
        console.log("\nDeploying GnomeStickers NFT...");
        string memory baseURI = "https://api.gnomeland.io/metadata/";
        GnomeStickers nftContract = new GnomeStickers(treasury, baseURI);
        console.log("GnomeStickers deployed at:", address(nftContract));
        
        // 3. Deploy Hook Implementation
        console.log("\nDeploying Hook Implementation...");
        GnomelandHook hookImpl = new GnomelandHook(IPoolManager(poolManager));
        console.log("Hook Implementation deployed at:", address(hookImpl));
        
        // 4. Deploy Hook Proxy
        console.log("\nDeploying Hook Proxy...");
        bytes memory initData = abi.encodeWithSelector(
            GnomelandHook.initialize.selector,
            address(nftContract),  // NFT contract
            50,                     // 0.5% fee
            0.1 ether              // Auto-transfer threshold
        );
        
        ERC1967Proxy hookProxy = new ERC1967Proxy(
            address(hookImpl),
            initData
        );
        console.log("Hook Proxy deployed at:", address(hookProxy));
        
        // Save deployment addresses
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("GNOME Token:", address(gnomeToken));
        console.log("NFT Contract:", address(nftContract));
        console.log("Hook Implementation:", address(hookImpl));
        console.log("Hook Proxy:", address(hookProxy));
        console.log("Treasury:", treasury);
        
        vm.stopBroadcast();
        
        // Save to file
        string memory addresses = string.concat(
            '{\n',
            '  "gnomeToken": "', vm.toString(address(gnomeToken)), '",\n',
            '  "nftContract": "', vm.toString(address(nftContract)), '",\n',
            '  "hookImplementation": "', vm.toString(address(hookImpl)), '",\n',
            '  "hookProxy": "', vm.toString(address(hookProxy)), '",\n',
            '  "treasury": "', vm.toString(treasury), '"\n',
            '}'
        );
        vm.writeFile("deployments/addresses.json", addresses);
        console.log("\nAddresses saved to deployments/addresses.json");
    }
}