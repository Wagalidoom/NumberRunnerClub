// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract KingAuction {
	using ABDKMath64x64 for int128;

	event KingBought(address winner, uint256 amount, uint256 color);

	uint256 auctionEndTime;
	uint256 auctionDuration;
	uint256 minPrice;

	constructor(uint256 endTime, uint256 duration, uint256 minAuctionPrice) {
		auctionEndTime = endTime;
		auctionDuration = duration;
		minPrice = minAuctionPrice;
	}

	function buyKing(uint256 _color, bool[2] memory kingsInSale, uint256 kingHandsPrize) public payable {
		require(block.timestamp <= auctionEndTime, "Auction already ended.");
		require(kingsInSale[_color - 1], "This king's color is already sold");
		int128 currentPrice = getCurrentPrice();
		int128 msgValueInt128 = ABDKMath64x64.fromUInt(msg.value);
		int128 msgValue = ABDKMath64x64.mul(msgValueInt128, ABDKMath64x64.fromUInt(10000));
		require(msgValue >= currentPrice, "The bid is too low.");
		// Transfer nft
		ERC721(address(this)).safeTransferFrom(address(this), msg.sender, _color - 1);

		emit KingBought(msg.sender, msg.value, _color);
		kingHandsPrize += msg.value;
		kingsInSale[_color - 1] = false;
	}

	function getCurrentPrice() public view returns (int128) {
		uint256 ts = block.timestamp;
		if (ts >= auctionEndTime) {
			return ABDKMath64x64.fromUInt(minPrice);
		} else {
			uint256 timeElapsed = ts - (auctionEndTime - auctionDuration);
			int128 _secondsElapsed = ABDKMath64x64.fromUInt(timeElapsed);
			int128 _secondsInDay = ABDKMath64x64.fromUInt(60 * 60 * 24);
			int128 _days = ABDKMath64x64.div(_secondsElapsed, _secondsInDay);
			int128 x64x64 = _days;

			int128 negOneThird = ABDKMath64x64.divi(-1, 3);
			int128 one = ABDKMath64x64.fromUInt(1);
			
			int128 innerCalculation = ABDKMath64x64.add(ABDKMath64x64.mul(negOneThird, x64x64), one);

			int128 result = ABDKMath64x64.exp_2(innerCalculation);

			return result;
		}
	}
}

// TODO add system of burn/sell before claiming personal prize
contract NumberRunnerClub is ERC721URIStorage, VRFV2WrapperConsumerBase, Ownable, ReentrancyGuard {

	event NFTPurchased(address buyer, address seller, uint256 tokenId, uint256 price);
	event ColorChoosed(uint8 color, address user);
	event NFTListed(address seller, uint256 tokenId, uint256 price);
	event NFTUnlisted(address seller, uint256 tokenId, uint256 price);
	event KingHandBurned(uint256 tokenId);
	event NFTBurned(address owner, uint256 tokenId);
	event NFTMinted(address owner, uint256 tokenId);
	event globalSharesUpdated(uint256[6] shares);
	event nftSharesUpdated(uint256 tokenId, uint256 shares);
	event NFTStacked(uint256 tokenId, bytes32 ensName);
	event NFTUnstacked(uint256 tokenId, bytes32 ensName);
	event UpdateUnclaimedRewards(uint256 tokenId, uint256 rewards);

	struct PieceDetails {
		uint256 maxSupply;
		uint256 totalMinted;
		uint256 blackMinted;
		uint256 whiteMinted;
		uint256 percentage;
		uint256 burnTax;
		uint256 startingId;
		uint256 clubRequirement;
		uint256 burnRequirement;
		uint256 opponentColorBurnRequirement;
		bool palindromeClubRequirement;
	}

	struct Proposal {
		bytes32 ensName;
		uint256 price;
		uint256 votes;
		bool executed;
		bytes rawTx;
		mapping(uint256 => bool) voted;
	}

	KingAuction public kingAuction;

	uint256 public constant MAX_NFT_SUPPLY = 10000;
	uint256 public totalMinted = 0;
	uint256 public currentSupply = 0;
	uint256 public userStacked = 0;
	uint256 public currentEpoch = 0;
	// King auction constants
	uint256 public constant auctionDuration = 30 days;
	uint256 public constant minPrice = 2 ether;
	uint256 public constant maxPrice = 20000 ether;
	bool[2] public kingsInSale = [true, true];
	uint256 public auctionEndTime;
	// L'epoch actuel
	uint256 public epoch = 0;
	uint256[10] kingHands;
	bool isKingsHandSet = false;
	uint256 public recentRequestId;
	uint256 prizePool;
	uint256 proposalCounter;
	uint256 kingHandsPrize = 0;

	ENS ens;
	mapping(uint256 => bytes32) public nodeOfTokenId; // Mapping of tokenId to the corresponding ENS hash
	mapping(bytes32 => uint256) public tokenIdOfNode; // Mapping of ENS hash to the corresponding tokenId
	mapping(uint256 => bytes32) public nameOfTokenId; // Mapping of tokenId to the corresponding ENS name
	PieceDetails[6] pieceDetails;

	uint256[6] private typeStacked;

	// La somme totale de tous les sharePerTokenAtEpoch pour chaque type de pièce
	uint256[][6] shareTypeAccumulator;
	// Le sharePerToken de l'utilisateur à l'epoch où il a stacké son dernier token
	mapping(uint256 => uint256) nftShares;

	mapping(uint256 => uint256) public unclaimedRewards; // Mapping des récompenses non claim associées au nft
	mapping(address => uint8) public userColor; // Mapping of user address to chosen color
	mapping(address => uint256) private burnedCount; // Mapping of user address to counter of nft burned
	mapping(address => uint256) private burnedCounterCount; // Mapping of user address to counter of nft from the opponent color burned
	mapping(uint256 => Proposal) public proposals; // Mapping of nft stacked in the contract
	mapping(uint256 => bool) public hasClaimedGeneral;
	mapping(uint256 => uint256) public nftPriceForSale;

	constructor(address _ens, address _vrfCoordinator, address _link) ERC721("NumberRunnerClub", "NRC") VRFV2WrapperConsumerBase(_link, _vrfCoordinator) {
		pieceDetails[0] = PieceDetails(2, 0, 0, 0, 350, 0, 0, 8, 0, 0, true);
		pieceDetails[1] = PieceDetails(10, 0, 0, 0, 225, 35, 2, 7, 15, 15, false);
		pieceDetails[2] = PieceDetails(50, 0, 0, 0, 150, 35, 12, 8, 15, 15, true);
		pieceDetails[3] = PieceDetails(100, 0, 0, 0, 125, 30, 62, 8, 10, 10, false);
		pieceDetails[4] = PieceDetails(200, 0, 0, 0, 100, 25, 162, 9, 10, 0, true);
		pieceDetails[5] = PieceDetails(9638, 0, 0, 0, 650, 25, 362, 9, 0, 0, false);
		ens = ENS(_ens);
		prizePool = 0;
		for (uint8 i = 0; i < 6; i++) {
			shareTypeAccumulator[i].push(1);
		}
		
		epoch += 1;
		for (uint8 i = 0; i < 6; i++) {
			shareTypeAccumulator[i].push(shareTypeAccumulator[i][epoch - 1]);
		}
		// Emit shares event
		uint256[6] memory currentShares;
		for (uint8 i = 0; i < 6; i++) {
			currentShares[i] = shareTypeAccumulator[i][epoch];
		}
		emit globalSharesUpdated(currentShares);

		spawnKings();
		auctionEndTime = block.timestamp + auctionDuration;


		kingAuction = new KingAuction(auctionEndTime, auctionDuration, minPrice);
	}

	modifier saleIsActive() {
		require(totalMinted < MAX_NFT_SUPPLY || currentSupply > 999, "Collection ended");
		_;
	}

	function mint(uint8 _pieceType, uint256 _stackedPiece) public payable returns (uint256) {
		require(msg.value >= 20000000000000, "User must send at least 0.2 eth for minting a token");
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2, "User must choose a color before minting");
		require(pieceDetails[_pieceType].totalMinted < pieceDetails[_pieceType].maxSupply, "Max supply for this piece type reached");
		if (userColor[msg.sender] == 1) {
			require(pieceDetails[_pieceType].blackMinted < pieceDetails[_pieceType].maxSupply / 2, "Max supply for black color reached");
		} else {
			require(pieceDetails[_pieceType].whiteMinted < pieceDetails[_pieceType].maxSupply / 2, "Max supply for white color reached");
		}

		// Set the id of the minting token from the type and color of the piece chosen
		// Black token have even id
		// White token have odd id
		uint256 newItemId = userColor[msg.sender] == 1 ? pieceDetails[_pieceType].startingId + 2 * pieceDetails[_pieceType].blackMinted : pieceDetails[_pieceType].startingId + 1 + 2 * pieceDetails[_pieceType].whiteMinted;
		// No restriction for minting Pawn
		if (_pieceType != 5) {
			bool hasRequiredClubStacked = false;
			for (uint i = 7; i <= pieceDetails[_pieceType].clubRequirement; i++) {
				bytes32 node = nodeOfTokenId[_stackedPiece];
				bytes32 name = nameOfTokenId[_stackedPiece];
				require(ens.owner(node) == msg.sender, "Not owner of ENS node");
				if (isClub(name, i)) {
					hasRequiredClubStacked = true;
					break;
				}
			}
			require(hasRequiredClubStacked, "Doesn't have a required club stacked");
			require(burnedCount[msg.sender] >= pieceDetails[_pieceType].burnRequirement, "Doesn't burn enough piece");
			if (pieceDetails[_pieceType].opponentColorBurnRequirement > 0) {
				require(burnedCounterCount[msg.sender] >= pieceDetails[_pieceType].opponentColorBurnRequirement, "Doesn't burn enough opponent piece");
			}
		}

		_mint(msg.sender, newItemId);
		_setTokenURI(newItemId, "");
		pieceDetails[_pieceType].totalMinted++;
		userColor[msg.sender] == 1 ? pieceDetails[_pieceType].blackMinted++ : pieceDetails[_pieceType].whiteMinted++;
		totalMinted++;
		currentSupply++;

		// If there are no pawn stacked, send the fees to prizepool
		if (typeStacked[5] == 0) {
			uint256 pawnShare = (10000000000000 * pieceDetails[5].percentage);
			prizePool += pawnShare;
		}

		// Add the transaction fee to the piece's balance
		updateShareType(10000000000000);

		emit NFTMinted(msg.sender, newItemId);
		return newItemId;
	}

	function burn(uint256 tokenId) public saleIsActive {
		require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: burn caller is not owner nor approved");
		require(!isForSale(tokenId), "This NFT is already on sale");
		// require(nodeOfTokenId[tokenId] == 0x0, "Cannot burn a stacked token");
		uint8 _pieceType = getPieceType(tokenId);
		require(_pieceType != 0, "Cannot burn the King");
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		uint256 taxAmount = (totalReward * pieceDetails[_pieceType].burnTax) / 100;
		// TODO revoir la redistribution pour gérer les arrondis
		uint256 holdersTax = taxAmount / 2;
		prizePool += taxAmount / 2;

		// If there are no pawn stacked, send the fees to prizepool
		if (typeStacked[5] == 0) {
			uint256 pawnShare = (holdersTax * pieceDetails[5].percentage) / 1000;
			prizePool += pawnShare;
		}

		updateShareType(holdersTax);

		nodeOfTokenId[tokenId] = 0x0;
		nameOfTokenId[tokenId] = 0x0;

		_burn(tokenId);
		burnedCount[msg.sender]++;
		if (!isColorValid(tokenId)) {
			burnedCounterCount[msg.sender]++;
		}
		currentSupply--;
		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		if (totalReward > 0) {
			require(address(this).balance >= totalReward - taxAmount, "Not enough balance in contract to send rewards");
			payable(msg.sender).transfer(totalReward - taxAmount);
		}
		emit NFTBurned(msg.sender, tokenId);
	}

	function stack(bytes32 node, bytes32 name, uint256 tokenId) public {
		// Ensure the function caller owns the ENS node
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");
		require(!isForSale(tokenId), "This NFT is already on sale");
		require(nodeOfTokenId[tokenId] == 0x0, "Token is already stacked");
		require(tokenIdOfNode[node] == 0, "ENS name is already used");
		// Ensure the function caller owns the NFT
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		// Ensure the NFT is approved for this contract to manage
		require(getApproved(tokenId) == address(this), "NFT not approved for staking");
		require(isColorValid(tokenId), "User cannot stack this color");
		uint8 _pieceType = getPieceType(tokenId);
		bool hasValidClub = false;
		for (uint i = 7; i < 10; i++) {
			if (pieceDetails[_pieceType].palindromeClubRequirement) {
				if (i == pieceDetails[_pieceType].clubRequirement) {
					if (isClub(name, i) && isPalindrome(name, i)) {
						hasValidClub = true;
						break;
					}
				}
			}
			if (isClub(name, i)) {
				hasValidClub = true;
				break;
			}
		}
		require(hasValidClub, "Doesn't have a valid club name");
		typeStacked[_pieceType] += 1;
		nftShares[tokenId] = shareTypeAccumulator[_pieceType][epoch];
		emit nftSharesUpdated(tokenId, shareTypeAccumulator[_pieceType][epoch]);

		if (typeStacked[_pieceType] == 1) {
			// If it's the first piece of this type
			if (_pieceType != 5 && _pieceType != 0) {
				pieceDetails[5].percentage -= pieceDetails[_pieceType].percentage;
			}
		}

		// Transfer the NFT to this contract
		transferFrom(msg.sender, address(this), tokenId); //remplacer par safeTransferFrom?
		// Set the token ID for the ENS node
		nodeOfTokenId[tokenId] = node;
		nameOfTokenId[tokenId] = name;
		tokenIdOfNode[node] = tokenId;
		emit NFTStacked(tokenId, name);
	}

	function unstack(uint256 tokenId) public {
		// Ensure the function caller owns the ENS node
		require(nodeOfTokenId[tokenId] != 0x0, "Token is not stacked yet");
		// Ensure the NFT is managed by this contract, doublon?
		require(ownerOf(tokenId) == address(this), "NFT not staked");
		bytes32 node = nodeOfTokenId[tokenId];
		uint8 _pieceType = getPieceType(tokenId);
		require(tokenIdOfNode[node] != 0, "ENS not used yet");
		// require(ens.owner(node) == msg.sender, "Not owner of ENS node");
		typeStacked[_pieceType] -= 1;

		// Transfer the NFT back to the function caller
		ERC721(address(this)).safeTransferFrom(address(this), msg.sender, tokenId);

		nodeOfTokenId[tokenId] = 0x0;
		tokenIdOfNode[node] = 0;
		emit NFTUnstacked(tokenId, nameOfTokenId[tokenId]);	
		nameOfTokenId[tokenId] = 0x0;

		updateUnclaimedRewards(_pieceType, tokenId);
		emit UpdateUnclaimedRewards(tokenId, unclaimedRewards[tokenId]);
		// update user and total stake count
		nftShares[tokenId] = shareTypeAccumulator[_pieceType][epoch];
		emit nftSharesUpdated(tokenId, shareTypeAccumulator[_pieceType][epoch]);
	}

	function listNFT(uint256 tokenId, uint256 price) public saleIsActive {
		require(!isForSale(tokenId));
		require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
		require(price > 0);
		_setNftPrice(tokenId, price);
		emit NFTListed(msg.sender, tokenId, price);
	}

	function unlistNFT(uint256 tokenId) public saleIsActive {
		require(msg.sender == ownerOf(tokenId), "Not owner of the NFT");
		require(isForSale(tokenId), "NFT is not for sale");
		uint256 price = getNftPrice(tokenId);
		require(price > 0);
		_setNftPrice(tokenId, 0);
		emit NFTUnlisted(msg.sender, tokenId, price);
	}

	function buyNFT(uint256 tokenId) public payable saleIsActive {
		require(isForSale(tokenId), "NFT is not for sale");
		require(msg.sender != address(0), "Buyer is zero address");
		uint256 price = getNftPrice(tokenId);
		require(price > 0);
		require(msg.value >= price, "Insufficient amount sent");

		address seller = ownerOf(tokenId);
		uint8 _pieceType = getPieceType(tokenId);
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		uint256 taxAmount = (totalReward * 16) / 100;

		prizePool += taxAmount / 2;
		uint256 holdersTax = taxAmount / 2;
		
		updateShareType(holdersTax);

		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		bool success;
		if (totalReward > 0) {
			// Ensure the contract has enough balance to pay the seller
			require(address(this).balance >= totalReward - taxAmount + price, "Not enough balance in contract to pay seller");
			(success, ) = payable(seller).call{ value: totalReward - taxAmount + price }("");
		} else {
			require(address(this).balance >= price, "Not enough balance in contract to pay price seller");
			(success, ) = payable(seller).call{ value: price }("");
		}

		require(success, "Failed to transfer ether to seller");
		// Transfer nft
		ERC721(address(this)).safeTransferFrom(seller, msg.sender, tokenId);
		emit NFTPurchased(msg.sender, seller, tokenId, price);
	}

	function isColorValid(uint256 tokenId) private view returns (bool) {
		return (tokenId % 2 == 0 && userColor[msg.sender] == 1) || (tokenId % 2 != 0 && userColor[msg.sender] == 2);
	}

	function isPalindrome(bytes32 name, uint length) public pure returns (bool) {
		uint start = 0;
		uint end = length - 5; // Exclude ".eth"

		while (start < end) {
			bytes1 startByte = name[start];
			bytes1 endByte = name[end];

			if (startByte < bytes1(0x30) || startByte > bytes1(0x39)) return false; // ASCII values for '0' and '9'
			if (endByte < bytes1(0x30) || endByte > bytes1(0x39)) return false; // ASCII values for '0' and '9'
			if (startByte != endByte) return false; // Checking palindrome

			start++;
			end--;
		}

		return true;
	}

	function getPieceType(uint256 nftId) public pure returns (uint8) {
		// require(nftId < MAX_NFT_SUPPLY, "NFT ID out of range");
		if (nftId >= 0 && nftId < 2) {
			return 0;
		} else if (nftId >= 2 && nftId < 12) {
			return 1;
		} else if (nftId >= 12 && nftId < 62) {
			return 2;
		} else if (nftId >= 62 && nftId < 162) {
			return 3;
		} else if (nftId >= 162 && nftId < 362) {
			return 4;
		} else {
			return 5;
		}
	}

	// Let user choose the white or black color
	function chooseColor(uint8 _color) public {
		require(_color == 1 || _color == 2, "Invalid color");
		require(userColor[msg.sender] == 0, "Color already chosen");
		userColor[msg.sender] = _color;
		emit ColorChoosed(_color, msg.sender);
	}

	function isClub(bytes32 name, uint length) public pure returns (bool) {
		if (length > 32 || length < 5) return false;

		// Check if the last part is ".eth"
		if (
			name[length - 4] != bytes1(0x2e) || // ASCII value for '.'
			name[length - 3] != bytes1(0x65) || // ASCII value for 'e'
			name[length - 2] != bytes1(0x74) || // ASCII value for 't'
			name[length - 1] != bytes1(0x68) // ASCII value for 'h'
		) return false;

		// Check if the first part is a number
		for (uint i = 0; i < length - 4; i++) {
			bytes1 b = name[i];
			if (b < bytes1(0x30) || b > bytes1(0x39)) return false;
		}

		return true;
	}

	function revealKingHand(uint256 tokenId) public payable returns (bool) {
		require(msg.value > 10000000000000); // reveal price fixed at 0.2 eth
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		require(getPieceType(tokenId) == 5, "Token must be a Pawn");
		// require(isStacked[tokenId] == false, "Token must be unstack");
		bool isKingsHand = false;
		for (uint i = 0; i < 10; i++) {
			if (tokenId == kingHands[i]) {
				isKingsHand = true;
				break;
			}
		}
		prizePool += msg.value;

		return isKingsHand;
	}

	// Passer la fonction en OnlyOwner ?
	function generateKingHands() public {
		recentRequestId = requestRandomness(10000000, 15, 10);
	}

	function buyKing(uint256 _color) public payable {
		kingAuction.buyKing(_color, kingsInSale, kingHandsPrize);
	}

	function getCurrentPrice() public view returns (int128) {
		return kingAuction.getCurrentPrice();
	}

	function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
		require(!isKingsHandSet, "King's Hands already generated");
		require(requestId == recentRequestId, "Wrong request ID");
		uint256 index = 0;
		for (uint i = 0; i < randomWords.length; i++) {
			uint256 randomValue = uint256(keccak256(abi.encode(randomWords[i], i)));
			// Ensure the random number is in the range [362, 9999]
			randomValue = (randomValue % (9999 - 362 + 1)) + 362;
			// Check if the number is already in the array
			bool exists = false;
			for (uint j = 0; j < index; j++) {
				if (kingHands[j] == randomValue) {
					exists = true;
					break;
				}
			}
			// If number does not exist in the array, add it
			if (!exists) {
				kingHands[index] = randomValue;
				index++;
				// If we have found 10 unique random numbers, exit the loop
				if (index == 10) {
					break;
				}
			}
		}
		// If we didn't find 10 unique random numbers, revert the transaction
		require(index == 10, "Not enough unique random numbers generated");
		isKingsHandSet = true;
	}

	function claimKingHand(uint256 tokenId) public {
		require(totalMinted == MAX_NFT_SUPPLY && currentSupply == 999, "Collection not ended yet");

		// Ensure the function caller owns the NFT
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		uint256 i = 0;
		bool isKingHand = false;
		for (i; i < 10; i++) {
			if (tokenId == kingHands[i]) {
				isKingHand = true;
				break;
			}
		}
		require(isKingHand, "Token must be a King's Hand");
		uint256 pieceShare = kingHandsPrize / 10;
		burn(tokenId);
		payable(msg.sender).transfer(pieceShare);
	}

	function vote(uint256 proposalId, uint256 tokenId, bool voteFor) public {
		uint8 piece = getPieceType(tokenId);
		require(piece == 1 || piece == 0, "Only King and Queen can vote to general pirze pool");
		require(ownerOf(tokenId) == msg.sender);
		Proposal storage proposal = proposals[proposalId];
		require(!proposal.voted[tokenId], "Cannot vote more than once with the same token");
		if (voteFor) {
			if (piece == 1) {
				proposal.votes += 4;
			}
			proposal.votes++;
		} else {
			if (piece == 0) {
				proposal.votes -= 4;
			}
			proposal.votes--;
		}
		proposal.voted[tokenId] = true;
	}

	function executeProposal(uint256 proposalId) external onlyOwner nonReentrant returns (bool) {
		// TODO verifier implementation de nonReentrant
		Proposal storage proposal = proposals[proposalId];
		require(proposal.executed == false);
		require(proposal.price < prizePool, "Not enough fund in the prize pool");
		bool _success = false;
		bytes memory _result;
		if (proposal.votes > 10) {
			(_success, _result) = address(this).call(proposal.rawTx);
		}
		proposal.executed = true;
		return _success;
	}

	function createProposal(bytes32 ensName, uint256 price, bytes calldata rawTx) external onlyOwner {
		require(price < prizePool, "Not enough fund in the prize pool");
		proposals[proposalCounter].ensName = ensName;
		proposals[proposalCounter].price = price;
		proposals[proposalCounter].executed = false;
		proposals[proposalCounter].rawTx = rawTx;
		proposalCounter++;
	}

	// how long to claim prize pool before ending
	function claimPrizePool(uint256 tokenId) public {
		require(totalMinted == MAX_NFT_SUPPLY && currentSupply <= 999, "Collection not ended yet");
		require(isClub(nodeOfTokenId[tokenId], 7) || (isClub(nodeOfTokenId[tokenId], 8) && isPalindrome(nodeOfTokenId[tokenId], 8)), "Only 999Club and 10kClub Palindrome can claim Prize");
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		require(hasClaimedGeneral[tokenId] == false, "Prize already claimed on this nft");
		// TODO echelle des pourcentages dans les calculs
		uint256 prizePoolTax = (prizePool / 999) * 35;
		prizePool -= (prizePool / 999) - prizePoolTax;
		payable(msg.sender).transfer((prizePool / 999) - prizePoolTax);
		hasClaimedGeneral[tokenId] = true;
	}

	function claimPrivatePrize(uint256 tokenId) public {
		require(totalMinted == MAX_NFT_SUPPLY && currentSupply <= 999, "Burn or sell the nft to claim your rewards");
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		uint8 _pieceType = getPieceType(tokenId);
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		if (totalReward > 0){
			require(address(this).balance >= totalReward, "Not enough balance in contract to send rewards");
			payable(msg.sender).transfer(totalReward);
		}
	}

	function spawnKings() public {
		// Black king
		_mint(address(this), 0);
		_setTokenURI(0, "");
		pieceDetails[0].totalMinted++;
		pieceDetails[0].blackMinted++;
		totalMinted++;
		currentSupply++;
		typeStacked[0] += 1;
		emit NFTMinted(address(this), 0);
		nftShares[0] =  1;
		emit nftSharesUpdated(0, 1);


		// White king
		_mint(address(this), 1);
		_setTokenURI(1, "");
		pieceDetails[0].totalMinted++;
		pieceDetails[0].whiteMinted++;
		totalMinted++;
		currentSupply++;
		typeStacked[0] += 1;
		emit NFTMinted(address(this), 1);
		nftShares[1] =  1;
		emit nftSharesUpdated(1, 1);
	}

	function updateShareType(uint256 _tax) private {
		epoch += 1;

		uint256[6] memory newShares;
		for (uint8 i = 0; i < 6; i++) {
			if (typeStacked[i] > 0) {
				uint256 pieceShare = (_tax * pieceDetails[i].percentage) / 1000;
				newShares[i] = shareTypeAccumulator[i][epoch - 1] + pieceShare / typeStacked[i];
			} else {
				newShares[i] = shareTypeAccumulator[i][epoch - 1];
			}
		}

		for (uint8 i = 0; i < 6; i++) {
			shareTypeAccumulator[i].push(newShares[i]);
		}

		emit globalSharesUpdated(newShares);
	}

	function updateUnclaimedRewards(uint8 _pieceType, uint256 tokenId) private {
		uint256 currentShares = shareTypeAccumulator[_pieceType][epoch];
		uint256 unclaimedReward;
		if (currentShares > 0) {
			unclaimedReward = currentShares - nftShares[tokenId];
			// update unclaimed rewards
			unclaimedRewards[tokenId] += unclaimedReward;
		}
	}

	function getNftPrice(uint256 tokenId) public view returns (uint256) {
		return (nftPriceForSale[tokenId]);
	}

	function _setNftPrice(uint256 tokenId, uint256 price) private {
		nftPriceForSale[tokenId] = price;
	}

	function isForSale(uint256 tokenId) public view returns (bool) {
		if (nftPriceForSale[tokenId] > 0) {
			return true;
		}
		return false;
	}

	function getShareTypeAccumulator(uint i, uint j) public view returns (uint256) {
		return shareTypeAccumulator[i][j];
	}

	function getShareTypeAccumulatorSize() public view returns (uint, uint) {
		return (shareTypeAccumulator.length, shareTypeAccumulator[0].length);
	}

	function getNftShares(uint256 tokenId) public view returns (uint256) {
		return nftShares[tokenId];
	}

	function getUserColor(address user) public view returns (uint8) {
		return userColor[user];
	}

	function getTokenIdOfNode(bytes32 node) public view returns (uint256) {
		return tokenIdOfNode[node];
	}

	function getBurnedCount(address user) public view returns (uint256) {
		return burnedCount[user];
	}

	function getBurnedCounterCount(address user) public view returns (uint256) {
		return burnedCounterCount[user];
	}

	function getTotalMinted() public view returns (uint256) {
		return totalMinted;
	}

	function getCurrentSupply() public view returns (uint256) {
		return currentSupply;
	}

	function getPrizePool() public view returns (uint256) {
		return prizePool;
	}
}
