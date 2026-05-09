// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GameAMM - constant product AMM for in-game resources
contract GameAMM is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable TOKEN_A;
    IERC20 public immutable TOKEN_B;

    uint256 public constant FEE = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;

    event Swap(address indexed user, uint256 amountIn, uint256 amountOut, bool aToB);
    event LiquidityAdded(address indexed user, uint256 amountA, uint256 amountB, uint256 shares);
    event LiquidityRemoved(address indexed user, uint256 amountA, uint256 amountB, uint256 shares);

    constructor(address _tokenA, address _tokenB) ERC20("GameLP", "GLP") {
        require(_tokenA != _tokenB, "Same tokens");
        TOKEN_A = IERC20(_tokenA);
        TOKEN_B = IERC20(_tokenB);
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external nonReentrant returns (uint256 shares) {
        TOKEN_A.safeTransferFrom(msg.sender, address(this), amountA);
        TOKEN_B.safeTransferFrom(msg.sender, address(this), amountB);

        uint256 reserveA = TOKEN_A.balanceOf(address(this)) - amountA;
        uint256 reserveB = TOKEN_B.balanceOf(address(this)) - amountB;

        if (totalSupply() == 0) {
            shares = _sqrt(amountA * amountB);
        } else {
            shares = _min(
                (amountA * totalSupply()) / reserveA,
                (amountB * totalSupply()) / reserveB
            );
        }

        require(shares > 0, "Zero shares");
        _mint(msg.sender, shares);
        emit LiquidityAdded(msg.sender, amountA, amountB, shares);
    }

    function removeLiquidity(uint256 shares) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        uint256 supply = totalSupply();
        amountA = (shares * TOKEN_A.balanceOf(address(this))) / supply;
        amountB = (shares * TOKEN_B.balanceOf(address(this))) / supply;

        _burn(msg.sender, shares);
        TOKEN_A.safeTransfer(msg.sender, amountA);
        TOKEN_B.safeTransfer(msg.sender, amountB);
        emit LiquidityRemoved(msg.sender, amountA, amountB, shares);
    }

    function swapAtoB(uint256 amountIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Zero input");
        TOKEN_A.safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = _getAmountOut(amountIn, TOKEN_A.balanceOf(address(this)) - amountIn, TOKEN_B.balanceOf(address(this)));
        require(amountOut >= minAmountOut, "Slippage exceeded");
        TOKEN_B.safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, amountIn, amountOut, true);
    }

    function swapBtoA(uint256 amountIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Zero input");
        TOKEN_B.safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = _getAmountOut(amountIn, TOKEN_B.balanceOf(address(this)) - amountIn, TOKEN_A.balanceOf(address(this)));
        require(amountOut >= minAmountOut, "Slippage exceeded");
        TOKEN_A.safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, amountIn, amountOut, false);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE);
        return (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y / 2 + 1; while (x < z) { z = x; x = (y / x + x) / 2; } }
        else if (y != 0) { z = 1; }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}