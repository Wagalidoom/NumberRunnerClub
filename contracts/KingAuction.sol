// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract KingAuction {
    address owner;
    uint256 public auctionEndTime;
    uint256[2] public highestBid;
    uint256 public minPrice;
    uint256 public maxPrice;
    address[2] public highestBidder;
    ERC721 public nftContract;

    event HighestBidIncreased(address bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);

    constructor(
        uint256 _biddingTime,
        address _nftAddress
    ) {
        owner = msg.sender;
        auctionEndTime = block.timestamp + _biddingTime;
        minPrice = 2 ether; // Minimum price at the end of auction
        maxPrice = 20000 ether; // Initial price at the start of auction

        nftContract = ERC721(_nftAddress);
    }

    function bid(uint256 _color) public payable {
        require(block.timestamp <= auctionEndTime, "Auction already ended.");
        uint256 currentPrice = getCurrentPrice();
        require(msg.value >= currentPrice, "The bid is too low.");

        if (msg.value > highestBid[_color]) {
            if (highestBidder[_color] != address(0)) {
                // Refund the old highest bidder
                payable(highestBidder[_color]).transfer(highestBid[_color]);
            }
            highestBidder[_color] = msg.sender;
            highestBid[_color] = msg.value;
            emit HighestBidIncreased(msg.sender, msg.value);
        }
    }

    function auctionEnd() public {
        require(block.timestamp >= auctionEndTime, "The auction has not ended.");
        emit AuctionEnded(highestBidder[0], highestBid[0]);
        emit AuctionEnded(highestBidder[1], highestBid[1]);
        nftContract.transferFrom(owner, highestBidder[0], 0);
        nftContract.transferFrom(owner, highestBidder[1], 1);
        // owner.transfer(highestBid);
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

