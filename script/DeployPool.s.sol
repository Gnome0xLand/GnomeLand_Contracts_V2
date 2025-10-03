// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import "../src/GNOMEToken.sol";

contract DeployPool is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    uint24 constant SWAP_FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address gnomeTokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address hookAddress = vm.envAddress("HOOK_PROXY");
        
        // Initial price: 1 GNOME = 0.0001 ETH
        uint160 INITIAL_SQRT_PRICE = 2505414483750479311864138015696063;
        
        vm.startBroadcast(deployerPrivateKey);
        
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        
        console.log("=== Deploying Uniswap V4 Pool ===");
        console.log("Pool Manager:", poolManagerAddress);
        console.log("GNOME Token:", gnomeTokenAddress);
        console.log("Hook:", hookAddress);
        
        // Determine currency order
        Currency currency0;
        Currency currency1;
        
        if (address(0) < gnomeTokenAddress) {
            currency0 = CurrencyLibrary.NATIVE;
            currency1 = Currency.wrap(gnomeTokenAddress);
            console.log("Currency0: ETH");
            console.log("Currency1: GNOME");
        } else {
            currency0 = Currency.wrap(gnomeTokenAddress);
            currency1 = CurrencyLibrary.NATIVE;
            console.log("Currency0: GNOME");
            console.log("Currency1: ETH");
        }
        
        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: SWAP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hookAddress)
        });
        
        // Initialize pool
        console.log("\nInitializing pool...");
        poolManager.initialize(poolKey, INITIAL_SQRT_PRICE, "");
        
        PoolId poolId = poolKey.toId();
        console.log("Pool initialized!");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        
        vm.stopBroadcast();
        
        // Save pool info
        string memory poolInfo = string.concat(
            '{\n',
            '  "poolId": "', vm.toString(PoolId.unwrap(poolId)), '",\n',
            '  "currency0": "', vm.toString(Currency.unwrap(currency0)), '",\n',
            '  "currency1": "', vm.toString(Currency.unwrap(currency1)), '",\n',
            '  "fee": ', vm.toString(SWAP_FEE), ',\n',
            '  "tickSpacing": ', vm.toString(uint256(int256(TICK_SPACING))), ',\n',
            '  "hook": "', vm.toString(hookAddress), '"\n',
            '}'
        );
        
        vm.writeFile("deployments/pool-info.json", poolInfo);
        console.log("\nPool info saved to deployments/pool-info.json");
    }
}