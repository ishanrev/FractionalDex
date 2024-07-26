// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./AssetToken.sol";

contract CombinedDex { 
    struct LockedNFT {
        address nftCollectionAddress;
        address owner;
        uint256 tokenId;
        uint256 lockTimestamp;
    }
    event NFTUnlocked(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed owner
    );
    event NFTLocked(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed owner
    );

    AssetToken public assetToken;
    LockedNFT private lockedNFT;
    bool private isLocked = false;
    uint256 valuation;
    uint256 private platformSwapFees = 5;
    uint256 private liquidityProviderSwapFees = 25;
    address payable public platformFeeAddress;

    constructor(
        string memory _assetTokenName,
        string memory _assetTokenSymbol,
        address payable _platformFeeAddress
    ) {
        assetToken = new AssetToken(_assetTokenName, _assetTokenSymbol);
        // I need to approve the ERC20 tokens with the maximum number of tokens that the
        // spender can acctually approve

        //Remember the _token should
        assetToken.approve(address(this), type(uint256).max);

        platformFeeAddress = _platformFeeAddress;
    }

    function uploadNFT(
        uint256 _valuation,
        uint256 _numFractionalTokens,
        address _nftCollectionAddress,
        uint256 _tokenId
    ) public returns (bool) {
        require(isLocked == false, "Already an NFT associated with this DEX");
        require(_valuation > 0);
        require(_numFractionalTokens > 10);
        IERC721 tempNFT = IERC721(_nftCollectionAddress);

        //I need to manage the decimals in the _numFractionalToken

        //Each nft marketplace needs to approve the transfer through the approve(addres, tokenID) function
        //THis is taken care of in the frontend.

        //I need certain read functions that will help you get the address of the nfts assetToken
        //read fucntions for the actual nft metadata to display on the platform you know

        require(
            msg.sender == tempNFT.ownerOf(_tokenId),
            " is not the owner of the nft"
        );
        tempNFT.transferFrom(msg.sender, address(this), _tokenId);

        LockedNFT memory _lockedNFT = LockedNFT({
            nftCollectionAddress: _nftCollectionAddress,
            owner: msg.sender,
            tokenId: _tokenId,
            lockTimestamp: block.timestamp
        });
        lockedNFT = _lockedNFT;
        emit NFTLocked(_nftCollectionAddress, _tokenId, msg.sender);
        assetToken.mint(msg.sender, _numFractionalTokens);
        valuation = _valuation;
        isLocked = true;
        return (true);
    }

    function getTokensInContract() public view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function addLiquidity(uint256 _amount) public payable returns (uint256) {
        require(
            isLocked == true,
            "This contract has no locked NFT belonging to it"
        );
        require(msg.value > 0, "ETH value must be greater than zero");

        uint256 _liquidity;
        uint256 balanceInEth = address(this).balance;
        uint256 tokenReserve = getTokensInContract();

        if (tokenReserve == 0) {
            assetToken.transferFrom(msg.sender, address(this), _amount);
            _liquidity = msg.value;
            assetToken.mint(msg.sender, _liquidity);
        } else {
            uint256 reservedEth = balanceInEth - msg.value;
            require(
                reservedEth > 0,
                "Reserved ETH must be greater than zero after subtracting msg.value"
            );

            require(
                _amount >= (tokenReserve * msg.value) / reservedEth,
                "Amount of tokens  is less than the required number of tokens"
            );
            assetToken.transferFrom(msg.sender, address(this), _amount);
            uint256 numLiquidityTokens = (msg.value *
                assetToken.totalSupply()) / reservedEth;
            assetToken.mint(msg.sender, numLiquidityTokens);
            _liquidity = numLiquidityTokens;
        }
        return _liquidity;
    }

    // I need a function that allows the person to fully redeem the nft
    // what are the pricing mechanisms for this I need to understand honestly
    // Im thinking that if the amount of eth provided is equivalent to the valuation
    /* in terms of eth then I transfer al the money with the swap fees
    then the ngt is unlocked, the event is emitted and then transferred to the msg.senderand 
    money is transferred to the address of the owner
    I also ned to implement swap fees and
    unlockNFT fees
    I also need to implement a seperate buyout mechanism
    The buyout mechanism is a whole next step to the stage of the applicaiton of 
    holding nfts honestly.
    First I need to check if the current functions of the contract suffice. 
    let me start developing this.
    Theres no need to unlock an NFT 

    */

    function removeLiquidity(uint256 _amount)
        public
        returns (uint256, uint256)
    {
        uint256 ethBalance = address(this).balance;
        uint256 tokenReserve = getTokensInContract();
        uint256 ethAmount = (_amount * ethBalance) / assetToken.totalSupply();
        uint256 tokenAmount = (tokenReserve * ethAmount) / ethBalance;
        // Transfer the calculated amount of tokens to the user
        assetToken.burn(msg.sender, _amount);
        assetToken.transfer(msg.sender, tokenAmount);
        // Transfer the calculated amount of ETH to the user
        payable(msg.sender).transfer(ethAmount);
        // Burn the liquidity tokens from the user's balance
        return (ethAmount, tokenAmount);
    }

    function unlockNFT() external {
        require(isLocked, "NFT is not locked");
        require(
            lockedNFT.owner == msg.sender,
            "Only the owner can unlock this NFT"
        );

        IERC721 nft = IERC721(lockedNFT.nftCollectionAddress);
        nft.transferFrom(address(this), msg.sender, lockedNFT.tokenId);

        isLocked = false;
        emit NFTUnlocked(
            lockedNFT.nftCollectionAddress,
            lockedNFT.tokenId,
            msg.sender
        );
        delete lockedNFT;
    }

    function swapMainforNative() public payable returns (uint256) {
        uint256 ethInputAfterSwapFees = (msg.value *
            (10000 - liquidityProviderSwapFees - platformSwapFees)) / 10000;
        uint256 ethBalance = address(this).balance - ethInputAfterSwapFees;
        uint256 tokenReserve = getTokensInContract();
        uint256 tokenReturn = (ethInputAfterSwapFees * tokenReserve) /
            (ethBalance + ethInputAfterSwapFees);
        require(tokenReserve > tokenReturn, "Not enough tokens in the reserve");

        assetToken.transfer(msg.sender, tokenReturn);

        /*Actually pay the platform and the liquidity providers money 
        would still stay in the same contract which would then be receieved 
        after the removeLiquidity functions is executed
        I need read functions as well thrat get the swap values I dont want to mix 
        the actual function implementations primarily because I am still learning 
        and therefore I cant blend everything together that well honestly
        */
        uint256 platformFees = (msg.value * (platformSwapFees)) / 10000;
        require(platformFeeAddress != address(0));
        payable(platformFeeAddress).transfer(platformFees);

        return tokenReturn;
    }

    function swapNativeForMain(uint256 _tokenAmount)
        public
        payable
        returns (uint256)
    {
        uint256 ethBalance = address(this).balance;
        uint256 tokenReserve = getTokensInContract();
        uint256 ethReturn = (ethBalance * _tokenAmount) /
            (tokenReserve + _tokenAmount);
        assetToken.transferFrom(msg.sender, address(this), _tokenAmount);
        uint256 ethReturnAfterSwapFees = (ethReturn *
            (10000 - liquidityProviderSwapFees + platformSwapFees)) / 10000;
        require(ethBalance > ethReturnAfterSwapFees, "Not enough ETH in the reserve");

        payable(msg.sender).transfer(ethReturnAfterSwapFees);

        uint256 platformFees = (ethReturn * (platformSwapFees)) / 10000;
        require(platformFeeAddress != address(0));
        payable(platformFeeAddress).transfer(platformFees);

        return ethReturn;
    }

    function getMainForNativeTokens(uint256 _main)
        public
        view
        returns (uint256)
    {
        uint256 ethInputAfterSwapFees = (_main *
            (10000 - liquidityProviderSwapFees - platformSwapFees)) / 10000;
        uint256 ethBalance = address(this).balance;
        uint256 tokenReserve = getTokensInContract();
        uint256 tokenReturn = (ethInputAfterSwapFees * tokenReserve) /
            (ethBalance + ethInputAfterSwapFees);
        return tokenReturn;
    }

    function getNativeForMainTokens(uint256 _native)
        public
        view
        returns (uint256)
    {
        uint256 ethBalance = address(this).balance;
        uint256 tokenReserve = getTokensInContract();
        uint256 ethReturn = (ethBalance * _native) / (tokenReserve + _native);
        uint256 ethReturnAfterSwapFees = (ethReturn *
            (10000 - liquidityProviderSwapFees + platformSwapFees)) / 10000;
        return ethReturnAfterSwapFees;
    }
}
