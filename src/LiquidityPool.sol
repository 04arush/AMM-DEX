// SPDX-License-Identifier: SEE LICENSE IN LICENSE.md
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/**
 * @title LiquidityPool - A constant product AMM (x * y = k)
 * @notice Allows users to add/remove liquidity and swap between two ERC20 tokens
 */
contract LiquidityPool is ERC20, ReentrancyGuard {
    
    /* ==================== State Variables ==================== */

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000; // 0.3% fee
    IERC20 public immutable I_TOKEN_A;
    IERC20 public immutable I_TOKEN_B;
    uint256 public reserveA;
    uint256 public reserveB;


    /* ======================== Events ========================= */

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpTokens);
    event Swap(address indexed user, address tokenIn, uint256 amountIn, uint256 amountOut);


    /* ======================== Errors ========================= */

    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InvalidToken();
    error SlippageExceeded();


    /* ===================== Constructors ====================== */

    constructor(address _tokenA, address _tokenB) ERC20("LP Token", "LPT") {
        I_TOKEN_A = IERC20(_tokenA);
        I_TOKEN_B = IERC20(_tokenB);
    }


    /* ======================= Functions ======================= */

    /* ------------------ External Functions ------------------- */

    /* ///////////////////////////////////////////////////////// */
    /*                         LIQUIDITY                         */
    /* ///////////////////////////////////////////////////////// */

    /// @notice Add liquidity to the pool. First LP sets the price ratio.
    function addLiquidity (
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) external nonReentrant returns ( uint256 amountA, uint256 amountB, uint256 lpToken) {
        if (reserveA == 0 && reserveB == 0) {
            // First deposit - set the initial price
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            // Maintain current price ratio
            uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
            if (amountBOptimal < amountBDesired) {
                require(amountBOptimal > amountBMin, "TokenB slippage");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
                require(amountAOptimal >= amountAMin, "TokenA slippage");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        require(I_TOKEN_A.transferFrom(msg.sender, address(this), amountA), "Transfer failed");
        require(I_TOKEN_B.transferFrom(msg.sender, address(this), amountB), "Transfer failed");
        

        /// @notice Mint LP Tokens
        uint256 supply = totalSupply();
        if (supply == 0) {
            lpToken = _sqrt(amountA * amountB);
        } else {
            lpToken = _min(
                (amountA * supply) / reserveA,
                (amountB * supply) / reserveB
            );
        }

        require(lpToken > 0, "Insufficient LP Tokens");
        _mint(msg.sender, lpToken);

        reserveA += amountA;
        reserveB += amountB;

        emit LiquidityAdded(msg.sender, amountA, amountB, lpToken);
    }

    /// @notice Remove liquidity and receive back proportional tokens
    function removeLiquidity (
        uint256 lpTokens,
        uint256 amountAMin,
        uint256 amountBMin
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(lpTokens > 0, "Insufficient LP Tokens");
        uint256 supply = totalSupply();
        
        amountA = (lpTokens * reserveA) / supply;
        amountB = (lpTokens * reserveB) / supply;

        require(amountA >= amountAMin, "TokenA slippage");
        require(amountB >= amountBMin, "TokenB slippage");

        _burn(msg.sender, lpTokens);
        reserveA -= amountA;
        reserveB -= amountB;

        require(I_TOKEN_A.transfer(msg.sender, amountA), "Transfer failed");
        require(I_TOKEN_B.transfer(msg.sender, amountB), "Transfer failed");

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpTokens);
    }

    /* ///////////////////////////////////////////////////////// */
    /*                            SWAP                           */
    /* ///////////////////////////////////////////////////////// */

    /// @notice Swap an exact amount of tokenIn for as much tokenOut as possible
    function swapExactInput (
        address _tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) external nonReentrant returns (uint256 amountOut) {
        if (_tokenIn != address(I_TOKEN_A) && _tokenIn != address(I_TOKEN_B)) revert InvalidToken();
        if (amountIn == 0) revert InsufficientInputAmount();

        bool isTokenA = _tokenIn == address(I_TOKEN_A);
        (uint256 reserveIn, uint256 reserveOut) = 
            isTokenA ? (reserveA, reserveB) : (reserveB, reserveA);

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < amountOutMin) revert SlippageExceeded();

        require(IERC20(_tokenIn).transferFrom(msg.sender, address(this), amountIn), "Transfer failed");

        if (isTokenA) {
            reserveA += amountIn;
            reserveB -= amountOut;
            require(I_TOKEN_B.transfer(msg.sender, amountOut), "Transfer failed");
        } else {
            reserveB += amountIn;
            reserveA -= amountOut;
            require(I_TOKEN_A.transfer(msg.sender, amountOut), "Transfer failed");
        }

        emit Swap(msg.sender, _tokenIn, amountIn, amountOut);
    }

    /// @notice Getter Function
    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    function getPrice() external view returns (uint256 priceAinB, uint256 priceBinA) {
        require(reserveA > 0 && reserveB > 0, "No liquidity");
        priceAinB = (reserveB * 1e18) / reserveA;
        priceBinA = (reserveA * 1e18) / reserveB;
    }

    /* ------------------- Public Functions -------------------- */

    /// @notice Calculate output amount given input, with 0.3% fee
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256) {
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        return (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
    }

    /* ------------------ Internal Functions ------------------- */

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) { z = x; x = (y / x + x) / 2; }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}