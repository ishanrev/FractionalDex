// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./LiquidityToken.sol";

contract Dex {
    address public token;
    LiquidityToken public liquidityToken;

    constructor(address _token, address _liquidityToken) {
        token = _token;
        liquidityToken = LiquidityToken(_liquidityToken);
    }

    function getTokensInContract() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function addLiquidity(uint256 _amount) public payable returns (uint256) {
        uint256 _liquidity;
        uint256 balanceInEth = address(this).balance;
        uint256 tokenReserve = getTokensInContract();

        if (tokenReserve == 0) {
            IERC20(token).transferFrom(msg.sender, address(this), _amount);
            _liquidity = msg.value;
            liquidityToken.mint(msg.sender, _liquidity);
        } else {
            uint256 reservedEth = balanceInEth - msg.value;
            require(
                _amount >= (tokenReserve * msg.value) / reservedEth,
                "Amount of tokens  is less than the required number of tokens"
            );
            IERC20(token).transferFrom(msg.sender, address(this), _amount);
            uint256 numLiquidityTokens = (msg.value *
                liquidityToken.totalSupply()) / reservedEth;
            liquidityToken.mint(msg.sender, numLiquidityTokens);
            _liquidity = numLiquidityTokens;
        }
        return _liquidity;
    }

    function removeLiquidity(
        uint256 _amount
    ) public returns (uint256, uint256) {
        uint256 ethBalance = address(this).balance;
        uint256 tokenReserve = getTokensInContract();
        uint256 ethAmount = (_amount * ethBalance) /
            liquidityToken.totalSupply();
        uint256 tokenAmount = (tokenReserve * ethAmount) / ethBalance;
        // Transfer the calculated amount of tokens to the user
        IERC20(token).transfer(msg.sender, tokenAmount);
        // Transfer the calculated amount of ETH to the user
        payable(msg.sender).transfer(ethAmount);
        // Burn the liquidity tokens from the user's balance
        liquidityToken.burn(msg.sender, _amount);
        return (ethAmount, tokenAmount);
    }

    function swapMainforNative() public payable returns (uint256) {
        uint256 ethBalance = address(this).balance - msg.value;
        uint256 tokenReserve = getTokensInContract();
        uint256 tokenReturn = (msg.value * tokenReserve)/(ethBalance + msg.value);
        IERC20(token).transfer(msg.sender, tokenReturn);

        return tokenReturn;
    }

    function swapNativeForMain(
        uint256 _tokenAmount
    ) public payable returns (uint256) {
        uint256 ethBalance = address(this).balance;
        uint256 tokenReserve = getTokensInContract();
        uint256 ethReturn = (ethBalance * _tokenAmount) /
            (tokenReserve + _tokenAmount);
        IERC20(token).transferFrom(msg.sender, address(this), _tokenAmount);
        payable(msg.sender).transfer(ethReturn);
        return ethReturn;
    }
}
