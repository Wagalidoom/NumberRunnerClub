// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract KingAuction {
    address payable owner;
    uint256 public auctionEndTime;
    uint256 public highestBid;
    uint256 public minPrice;
    uint256 public maxPrice;
    address public highestBidder;

    ERC721 public nftContract;
    uint256 public tokenId;

    event HighestBidIncreased(address bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);

    constructor(
        uint256 _biddingTime,
        address _nftAddress,
        uint256 _tokenId
    ) {
        owner = payable(msg.sender);
        auctionEndTime = block.timestamp + _biddingTime;
        minPrice = 2 ether; // Minimum price at the end of auction
        maxPrice = 20000 ether; // Initial price at the start of auction

        nftContract = ERC721(_nftAddress);
        tokenId = _tokenId;
    }

    function bid() public payable {
        require(block.timestamp <= auctionEndTime, "Auction already ended.");
        uint256 currentPrice = getCurrentPrice();
        require(msg.value >= currentPrice, "The bid is too low.");

        if (msg.value > highestBid) {
            if (highestBidder != address(0)) {
                // Refund the old highest bidder
                highestBidder.transfer(highestBid);
            }
            highestBidder = msg.sender;
            highestBid = msg.value;
            emit HighestBidIncreased(msg.sender, msg.value);
        }
    }

    function auctionEnd() public {
        require(block.timestamp >= auctionEndTime, "The auction has not ended.");
        emit AuctionEnded(highestBidder, highestBid);
        nftContract.transferFrom(owner, highestBidder, tokenId);
        owner.transfer(highestBid);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (block.timestamp >= auctionEndTime) {
            return minPrice;
        } else {
            uint256 timeElapsed = block.timestamp - (auctionEndTime - 30 days);
            uint256 priceDifference = maxPrice - minPrice;
            uint256 priceDrop = (priceDifference * timeElapsed) / 30 days;
            return maxPrice - priceDrop;
        }
    }
}

