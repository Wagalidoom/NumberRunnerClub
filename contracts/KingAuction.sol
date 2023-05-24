// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract KingAuction {
	address owner;
	uint256 public auctionEndTime;
	uint256[2] public highestBid;
	uint256 public minPrice;
	uint256 public maxPrice;
	address[2] public highestBidder;
	uint256[10] kingHands;
	ERC721URIStorage public nftContract;
	event AuctionEnded(address winner, uint256 amount, uint256 color);

	constructor(uint256 _biddingTime, address _nftAddress, uint256[10] memory _kingHands) {
		owner = msg.sender;
		auctionEndTime = block.timestamp + _biddingTime;
		minPrice = 2 ether; // Minimum price at the end of auction
		maxPrice = 20000 ether; // Initial price at the start of auction
		kingHands = _kingHands;

		nftContract = ERC721URIStorage(_nftAddress);
	}

	function bid(uint256 _color) public payable {
		require(block.timestamp <= auctionEndTime, "Auction already ended.");
		uint256 currentPrice = getCurrentPrice();
		require(msg.value >= currentPrice, "The bid is too low.");
		nftContract.transferFrom(owner, msg.sender, _color);
        payable(address(nftContract)).transfer(msg.value);
        emit AuctionEnded(msg.sender, msg.value, _color);
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
