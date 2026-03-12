// SPDX-License-Identifier: SEE LICENSE IN LICENSE.md
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { LiquidityPool } from "src/LiquidityPool.sol";
import { TokenA } from "src/TokenA.sol";
import { TokenB } from "src/TokenB.sol";

contract LiquidityPoolTest is Test {

    uint256 constant INITIAL_MINT = 100_000 ether;
    address john = makeAddr("john");    // Dummy address 1
    address jane = makeAddr("jane");    // Dummy address 2
    LiquidityPool pool;
    TokenA tokenA;
    TokenB tokenB;

    function setUp() public {
        tokenA = new TokenA();
        tokenB = new TokenB();
        pool = new LiquidityPool(address(tokenA), address(tokenB));

        // Fund John and Jane
        require(tokenA.transfer(john, INITIAL_MINT), "Transfer failed");
        require(tokenB.transfer(john, INITIAL_MINT), "Transfer failed");
        require(tokenA.transfer(jane, INITIAL_MINT), "Transfer failed");
        require(tokenB.transfer(jane, INITIAL_MINT), "Transfer failed");
    }

    /* ─────────────────────── LIQUIDITY TESTS ─────────────────────── */

    function testAddInitialLiquidity() public {
        vm.startPrank(john);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 2000 ether);

        (uint256 amtA, uint256 amtB, uint256 lp) = pool.addLiquidity(
            1000 ether, 2000 ether, 0, 0
        );

        assertEq(amtA, 1000 ether);
        assertEq(amtB, 2000 ether);
        assertGt(lp, 0);
        assertEq(pool.balanceOf(john), lp);

        (uint256 rA, uint256 rB) = pool.getReserves();
        assertEq(rA, 1000 ether);
        assertEq(rB, 2000 ether);
        vm.stopPrank();
    }

    function testAddSubsequentLiquidity() public {
        vm.startPrank(john);    // John adds first
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 2000 ether);
        pool.addLiquidity(1000 ether, 2000 ether, 0, 0);
        vm.stopPrank();

        vm.startPrank(jane);    // Jane adds at the same ratio
        tokenA.approve(address(pool), 500 ether);
        tokenB.approve(address(pool), 1000 ether);
        ( , , uint256 lpJane) = pool.addLiquidity(500 ether, 1000 ether, 0, 0);
        assertGt(lpJane, 0);
        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        vm.startPrank(john);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 2000 ether);
        (, , uint256 lp) = pool.addLiquidity(1000 ether, 2000 ether, 0, 0);

        pool.approve(address(pool), lp);
        (uint256 outA, uint256 outB) = pool.removeLiquidity(lp, 0, 0);

        assertGt(outA, 0);
        assertGt(outB, 0);
        assertEq(pool.balanceOf(john), 0);
        vm.stopPrank();
    }

    /* ────────────────────────── SWAP TESTS ───────────────────────── */

    function testSwapTokenAForTokenB() public {
        vm.startPrank(john);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 2000 ether);
        pool.addLiquidity(1000 ether, 2000 ether, 0, 0);
        vm.stopPrank();

        vm.startPrank(jane);
        uint256 amountIn = 100 ether;
        tokenA.approve(address(pool), amountIn);

        uint256 janeBefore = tokenB.balanceOf(jane);
        uint256 out = pool.swapExactInput(address(tokenA), amountIn, 0);
        uint256 janeAfter = tokenB.balanceOf(jane);

        assertEq(janeAfter - janeBefore, out);
        assertGt(out, 0);
        vm.stopPrank();
    }

    function testSwapTokenBForTokenA() public {
        vm.startPrank(john);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 2000 ether);
        pool.addLiquidity(1000 ether, 2000 ether, 0, 0);
        vm.stopPrank();

        vm.startPrank(jane);
        uint256 amountIn = 100 ether;
        tokenB.approve(address(pool), amountIn);

        uint256 out = pool.swapExactInput(address(tokenB), amountIn, 0);
        assertGt(out, 0);
        vm.stopPrank();
    }

    function testSwapRespectsConstantProduct() public {
        vm.startPrank(john);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 1000 ether);
        pool.addLiquidity(1000 ether, 1000 ether, 0, 0);
        vm.stopPrank();

        (uint256 rA_before, uint256 rB_before) = pool.getReserves();
        uint256 k_before = rA_before * rB_before;

        vm.startPrank(jane);
        tokenA.approve(address(pool), 100 ether);
        pool.swapExactInput(address(tokenA), 100 ether, 0);
        vm.stopPrank();

        (uint256 rA_after, uint256 rB_after) = pool.getReserves();
        uint256 k_after = rA_after * rB_after;

        assertGe(k_after, k_before);
    }

    function testSwapRevertOnSlippage() public {
        vm.startPrank(john);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 1000 ether);
        pool.addLiquidity(1000 ether, 1000 ether, 0, 0);
        vm.stopPrank();

        vm.startPrank(jane);
        tokenA.approve(address(pool), 100 ether);

        // Demand impossibly high output
        vm.expectRevert(LiquidityPool.SlippageExceeded.selector);
        pool.swapExactInput(address(tokenA), 100 ether, 999999 ether);
        vm.stopPrank();
    }

    function testSwapRevertOnInvalidToken() public {
        vm.startPrank(jane);
        vm.expectRevert(LiquidityPool.InvalidToken.selector);
        pool.swapExactInput(address(0xdead), 100 ether, 0);
        vm.stopPrank();
    }

    /* ────────────────────────── FUZZ TESTS ───────────────────────── */

    function testFuzzSwapNeverDrainsPool(uint256 amountIn) public {
        vm.assume(amountIn > 1e6 && amountIn < 100 ether);

        vm.startPrank(john);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 1000 ether);
        pool.addLiquidity(1000 ether, 1000 ether, 0, 0);
        vm.stopPrank();

        vm.startPrank(jane);
        tokenA.approve(address(pool), amountIn);
        uint256 out = pool.swapExactInput(address(tokenA), amountIn, 0);
        vm.stopPrank();

        (, uint256 rB) = pool.getReserves();
        assertGt(rB, 0, "Pool must never be fully drained");
        assertLt(out, 1000 ether, "Cannot get more than pool holds");
    }

    function testFuzzLPTokensProportional(uint256 amtA) public {
        vm.assume(amtA > 1 ether && amtA < 10_000 ether);
        uint256 amtB = amtA * 2; // 1:2 ratio

        vm.startPrank(john);
        tokenA.approve(address(pool), amtA);
        tokenB.approve(address(pool), amtB);
        (, , uint256 lp) = pool.addLiquidity(amtA, amtB, 0, 0);

        assertGt(lp, 0);
        vm.stopPrank();
    }
}