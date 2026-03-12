// SPDX-License-Identifier: SEE LICENSE IN LICENSE.md
pragma solidity ^0.8.20;

import { Script, console } from "forge-std/Script.sol";
import { LiquidityPool } from "src/LiquidityPool.sol";
import { TokenA } from "src/TokenA.sol";
import { TokenB } from "src/TokenB.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        TokenA tokenA = new TokenA();
        TokenB tokenB = new TokenB();
        LiquidityPool pool = new LiquidityPool(address(tokenA), address(tokenB));

        // Seed the pool with initial liquidity
        uint256 seedA = 10_000 ether;
        uint256 seedB = 20_000 ether;

        tokenA.approve(address(pool), seedA);
        tokenB.approve(address(pool), seedB);
        pool.addLiquidity(seedA, seedB, 0, 0);

        vm.stopBroadcast();

        console.log("Deployer    :", deployer);
        console.log("TokenA      :", address(tokenA));
        console.log("TokenB      :", address(tokenB));
        console.log("Pool        :", address(pool));
    }
}