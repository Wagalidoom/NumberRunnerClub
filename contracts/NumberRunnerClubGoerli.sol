// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@ensdomains/ens-contracts/contracts/ethregistrar/BaseRegistrarImplementation.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

using Strings for uint256;

contract KingAuctionGoerli is VRFV2WrapperConsumerBase, Ownable {
	using ABDKMath64x64 for int128;

	uint256 auctionEndTime;
	uint256 auctionDuration;
	uint256 minPrice;
	bool[2] public kingsInSale = [true, true];

	bool isKingsHandSet = false;

	uint256 kingHandsPrize = 0;
	uint256[10] internal kingHands;

	uint256 public recentRequestId;

	constructor(uint256 endTime, uint256 duration, uint256 minAuctionPrice, address _vrfCoordinator, address _link) VRFV2WrapperConsumerBase(_link, _vrfCoordinator) {
		auctionEndTime = endTime;
		auctionDuration = duration;
		minPrice = minAuctionPrice;
	}

	function generateKingHands() public {
		recentRequestId = requestRandomness(10000000, 15, 10);
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

	function buyKing(uint256 _color, uint256 value) external payable returns (bool) {
		require(block.timestamp <= auctionEndTime, "Auction already ended.");
		require(kingsInSale[_color - 1], "This king's color is already sold");
		uint256 currentPrice = getCurrentPrice();
		require(value >= currentPrice, "The bid is too low.");
		kingHandsPrize += value;
		kingsInSale[_color - 1] = false;
		return true;
	}

	function getCurrentPrice() public view returns (uint256) {
		uint256 ts = block.timestamp;
		if (ts >= auctionEndTime) {
			return minPrice * 1e18; // scale to match the precision
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

			// Convert result to uint256 for comparison and scale it
			uint256 resultUint = ABDKMath64x64.toUInt(ABDKMath64x64.mul(result, ABDKMath64x64.fromUInt(1e0)));

			return resultUint;
		}
	}

	function revealKingHand(uint256 tokenId) external view returns (bool) {
		bool isKingsHand = false;
		for (uint i = 0; i < 10; i++) {
			if (tokenId == kingHands[i]) {
				isKingsHand = true;
				break;
			}
		}
		return isKingsHand;
	}

	function claimKingHand(uint256 tokenId) external returns (uint256) {
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
		require(pieceShare > 0, "Incorrect Piece Share");
		kingHands[i] = 0;
		return pieceShare;
	}
}

contract NumberRunnerClubGoerli is ERC721URIStorage, Ownable, ReentrancyGuard {
	event NFTPurchased(address buyer, address seller, uint256 tokenId, uint256 price);
	event KingBought(address buyer, uint256 price, uint256 tokenId, bytes32 ensName);
	event ColorChoosed(uint8 color, address user);
	event NFTListed(address seller, uint256 tokenId, uint256 price);
	event NFTUnlisted(address seller, uint256 tokenId, uint256 price);
	event KingHandBurned(uint256 tokenId);
	event NFTBurned(address owner, uint256 tokenId);
	event NFTMinted(address owner, uint256 tokenId);
	event globalSharesUpdated(uint256[6] shares);
	event nftSharesUpdated(uint256 tokenId, uint256 shares);
	event NFTStacked(uint256 tokenId, bytes32 ensName, uint256 expiration);
	event NFTUnstacked(uint256 tokenId, bytes32 ensName);
	event UpdateUnclaimedRewards(uint256 tokenId, uint256 rewards);
	event KingHandRevealed(bool success);
	event NFTKilled(uint256 tokenId);
	event DebugInfo(bytes32 label, uint256 labelId, uint256 tokenId);

	uint256 constant ONE_WEEK = 1 weeks;
	bytes32 constant ETH_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256(abi.encodePacked(".eth"))));

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

	KingAuctionGoerli public kingAuction;

	uint256 public constant MAX_NFT_SUPPLY = 10000;
	uint256 public totalMinted = 0;
	uint256 public currentSupply = 0;
	uint256 public userStacked = 0;
	uint256 public currentEpoch = 0;
	// King auction constants
	uint256 public constant auctionDuration = 21 days;
	uint256 public constant minPrice = 2 ether;
	uint256 public constant maxPrice = 20000 ether;
	uint256 public auctionEndTime;
	// L'epoch actuel
	uint256 public epoch = 0;
	uint256 prizePool;

	BaseRegistrarImplementation public baseRegistrar;
	mapping(bytes32 => uint256) public tokenIdOfName; // Mapping of ENS hash to the corresponding tokenId
	mapping(uint256 => bytes32) public nameOfTokenId; // Mapping of tokenId to the corresponding ENS name
	mapping(uint256 => uint256) private _unstakeTimestamps;
	mapping(uint256 => uint256) public expiration;
	mapping(address => uint256) private _killFeeDebt;
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
	mapping(uint256 => bool) public hasClaimedGeneral;
	mapping(uint256 => uint256) public nftPriceForSale;

	constructor(address _baseRegistrar, address _vrfCoordinator, address _link) ERC721("Number Runner Club", "NRC") {
		pieceDetails[0] = PieceDetails(2, 0, 0, 0, 2, 0, 0, 7, 0, 0, false);
		pieceDetails[1] = PieceDetails(10, 0, 0, 0, 1, 15, 2, 7, 15, 15, false);
		pieceDetails[2] = PieceDetails(50, 0, 0, 0, 1, 15, 12, 8, 15, 15, true);
		pieceDetails[3] = PieceDetails(100, 0, 0, 0, 1, 15, 62, 8, 10, 10, false);
		pieceDetails[4] = PieceDetails(200, 0, 0, 0, 1, 15, 162, 8, 10, 0, false);
		pieceDetails[5] = PieceDetails(9638, 0, 0, 0, 8, 20, 362, 9, 0, 0, false);
		baseRegistrar = BaseRegistrarImplementation(_baseRegistrar);
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

		kingAuction = new KingAuctionGoerli(auctionEndTime, auctionDuration, minPrice, _vrfCoordinator, _link);
	}

	modifier saleIsActive() {
		require(currentSupply + MAX_NFT_SUPPLY - totalMinted > 999);
		_;
	}

	modifier saleIsNotActive() {
		require(!(currentSupply + MAX_NFT_SUPPLY - totalMinted > 999));
		_;
	}

	function multiMint(uint256 _n) external payable {
		require(msg.value >= 10000000000000 * _n);
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2);
		require(pieceDetails[5].totalMinted + _n < pieceDetails[5].maxSupply);
		if (userColor[msg.sender] == 1) {
			require(pieceDetails[5].blackMinted + _n < pieceDetails[5].maxSupply / 2);
		} else {
			require(pieceDetails[5].whiteMinted + _n < pieceDetails[5].maxSupply / 2);
		}

		uint256 startId = userColor[msg.sender] == 1 ? 362 + 2 * pieceDetails[5].blackMinted : 363 + 2 * pieceDetails[5].whiteMinted;

		for (uint8 i = 0; i < _n; i++) {
			uint256 newItemId = startId + 2 * i;
			_mint(msg.sender, newItemId);
			_setTokenURI(newItemId, string(abi.encodePacked("ipfs://QmUSL1sxdiSPMUL1s39qpjENXi6kQTmLY1icq9KVjYmc4N/NumberRunner", newItemId.toString(), ".json")));
			pieceDetails[5].totalMinted++;
			unclaimedRewards[newItemId] = 0;
			nftShares[newItemId] = 0;
			_unstakeTimestamps[newItemId] = block.timestamp;
			expiration[newItemId] = 0;
			userColor[msg.sender] == 1 ? pieceDetails[5].blackMinted++ : pieceDetails[5].whiteMinted++;
			totalMinted++;
			currentSupply++;
			prizePool += 2500000000000;
			// If there are no pawn stacked, send the fees to prizepool
			if (typeStacked[5] == 0) {
				uint256 pawnShare = (2500000000000 * pieceDetails[5].percentage) / 10;
				prizePool += pawnShare;
			}

			// Add the transaction fee to the piece's balance
			updateShareType(2500000000000);

			emit NFTMinted(msg.sender, newItemId);
		}

		payable(owner()).transfer(5000000000000 * _n);
	}

	function mint(uint8 _pieceType, uint256 _stackedPiece) external payable {
		require(msg.value >= 10000000000000);
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2);
		require(pieceDetails[_pieceType].totalMinted < pieceDetails[_pieceType].maxSupply);
		if (userColor[msg.sender] == 1) {
			require(pieceDetails[_pieceType].blackMinted < pieceDetails[_pieceType].maxSupply / 2);
		} else {
			require(pieceDetails[_pieceType].whiteMinted < pieceDetails[_pieceType].maxSupply / 2);
		}

		// Set the id of the minting token from the type and color of the piece chosen
		// Black token have even id
		// White token have odd id
		uint256 newItemId = userColor[msg.sender] == 1 ? pieceDetails[_pieceType].startingId + 2 * pieceDetails[_pieceType].blackMinted : pieceDetails[_pieceType].startingId + 1 + 2 * pieceDetails[_pieceType].whiteMinted;
		// No restriction for minting Pawn
		if (_pieceType != 5) {
			bool hasRequiredClubStacked = false;
			for (uint i = 7; i <= pieceDetails[_pieceType].clubRequirement; i++) {
				bytes32 name = nameOfTokenId[_stackedPiece];
				uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
				require(baseRegistrar.ownerOf(labelId) == msg.sender);
				if (isClub(name, i)) {
					hasRequiredClubStacked = true;
					break;
				}
			}
			require(hasRequiredClubStacked);
			require(burnedCount[msg.sender] >= pieceDetails[_pieceType].burnRequirement);
			burnedCount[msg.sender] -= pieceDetails[_pieceType].burnRequirement;
			if (pieceDetails[_pieceType].opponentColorBurnRequirement > 0) {
				require(burnedCounterCount[msg.sender] >= pieceDetails[_pieceType].opponentColorBurnRequirement);
				burnedCounterCount[msg.sender] -= pieceDetails[_pieceType].opponentColorBurnRequirement;
			}
		}

		_mint(msg.sender, newItemId);
		_setTokenURI(newItemId, string(abi.encodePacked("ipfs://QmUSL1sxdiSPMUL1s39qpjENXi6kQTmLY1icq9KVjYmc4N/NumberRunner", newItemId.toString(), ".json")));
		unclaimedRewards[newItemId] = 0;
		nftShares[newItemId] = 0;
		_unstakeTimestamps[newItemId] = block.timestamp;
		expiration[newItemId] = 0;
		pieceDetails[_pieceType].totalMinted++;
		userColor[msg.sender] == 1 ? pieceDetails[_pieceType].blackMinted++ : pieceDetails[_pieceType].whiteMinted++;
		totalMinted++;
		currentSupply++;
		prizePool += 2500000000000;

		// If there are no pawn stacked, send the fees to prizepool
		if (typeStacked[5] == 0) {
			uint256 pawnShare = (2500000000000 * pieceDetails[5].percentage) / 10;
			prizePool += pawnShare;
		}

		// Add the transaction fee to the piece's balance
		updateShareType(2500000000000);

		emit NFTMinted(msg.sender, newItemId);

		payable(owner()).transfer(5000000000000);
	}

	function burn(uint256 tokenId) external saleIsActive {
		require(_isApprovedOrOwner(_msgSender(), tokenId));
		require(!isForSale(tokenId));
		require(nameOfTokenId[tokenId] == 0x0);
		uint8 _pieceType = getPieceType(tokenId);
		require(_pieceType != 0);
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		uint256 taxAmount = (totalReward * pieceDetails[_pieceType].burnTax) / 100;
		uint256 holdersTax = taxAmount / 2;
		prizePool += taxAmount / 2;

		// If there are no pawn stacked, send the fees to prizepool
		if (typeStacked[5] == 0) {
			uint256 pawnShare = (holdersTax * pieceDetails[5].percentage) / 10;
			prizePool += pawnShare;
		}

		updateShareType(holdersTax);
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

	function multiKill(uint256[] calldata tokensId) external payable saleIsActive {
		require(tokensId.length > 0);
		require(msg.sender != address(0));
		// require(totalMinted == MAX_NFT_SUPPLY, "All NFT must be minted for access this feature");
		uint256 totalPrice = 0;
		uint256 killFee = 0;
		uint256 rewards = 0;
		for (uint i = 0; i < tokensId.length; i++) {
			require(!isColorValid(tokensId[i]));
			rewards = unclaimedRewards[tokensId[i]] + nftShares[tokensId[i]];

			if (nameOfTokenId[tokensId[i]] != 0x0) {
				if (expiration[tokensId[i]] == 0) {
					killFee = 30000000000000 + (rewards * 10) / 100;
				} else {
					require(block.timestamp > expiration[tokensId[i]]);
					killFee = 0;
				}
			} else {
				// require(block.timestamp >= _unstakeTimestamps[tokensId[i]] + ONE_WEEK, "Cannot burn: One week waiting period is not over");
				if (isForSale(tokensId[i])) {
					killFee = 20000000000000 + (rewards * 10) / 100;
				} else {
					killFee = 10000000000000 + (rewards * 10) / 100;
				}
			}
			_setNftPrice(tokensId[i], 0);
			unclaimedRewards[tokensId[i]] = 0;
			nftShares[tokensId[i]] = 0;
			totalPrice += killFee;
		}

		require(msg.value >= totalPrice);

		for (uint i = 0; i < tokensId.length; i++) {
			killNFT(tokensId[i]);
		}
	}

	function killNFT(uint256 tokenId) private saleIsActive {
		uint8 _pieceType = getPieceType(tokenId);
		require(_pieceType != 0);
		uint256 killFee = 0;
		uint256 rewards = unclaimedRewards[tokenId] + nftShares[tokenId];

		if (nameOfTokenId[tokenId] != 0x0) {
			if (expiration[tokenId] == 0) {
				killFee = 30000000000000 + (rewards * 10) / 100;
			} else {
				require(block.timestamp > expiration[tokenId]);
				killFee = 0;
			}
		} else {
			if (isForSale(tokenId)) {
				killFee = 20000000000000 + (rewards * 10) / 100;
			} else {
				killFee = 10000000000000 + (rewards * 10) / 100;
			}
		}
		_killFeeDebt[msg.sender] += killFee;
		prizePool += killFee;
		prizePool += (rewards * 10) / 100;

		_burn(tokenId);

		currentSupply--;

		if (rewards > 0) {
			require(address(this).balance >= rewards - (rewards * 15) / 100, "Not enough balance in contract to send rewards");
			bytes32 name = nameOfTokenId[tokenId];
			if (name != 0x0) {
				uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
				payable(baseRegistrar.ownerOf(labelId)).transfer(rewards - (rewards * 15) / 100);
				tokenIdOfName[nameOfTokenId[tokenId]] = 0;
				nameOfTokenId[tokenId] = 0x0;
			} else {
				payable(ownerOf(tokenId)).transfer(rewards - (rewards * 15) / 100);
			}
		}

		emit NFTKilled(tokenId);
		emit NFTBurned(msg.sender, tokenId);
	}

	function updateExpiration(uint256 tokenId) external {
		// Ensure the function caller owns the ENS node
		require(nameOfTokenId[tokenId] != 0x0, "Token is not stacked yet");
		// Ensure the NFT is managed by this contract, doublon?
		require(ownerOf(tokenId) == address(this), "NFT not staked");
		bytes32 name = nameOfTokenId[tokenId];
		require(tokenIdOfName[name] != 0, "ENS not used yet");
		uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
		// Ensure the function caller owns the ENS node
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "Not owner of ENS node");

		expiration[tokenId] = getDomainExpirationDate(labelId);
	}

	function stack(bytes32 label, uint256 tokenId) external {
		uint256 labelId = uint256(keccak256(abi.encodePacked(label)));
		emit DebugInfo(label, labelId, tokenId);
		return;

		require(!isForSale(tokenId), "This NFT is already on sale");
		require(nameOfTokenId[tokenId] == 0x0, "Token is already stacked");
		require(tokenIdOfName[label] == 0, "ENS name is already used");
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "Not owner of ENS name");

		// Ensure the function caller owns the NFT
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");

		require(isColorValid(tokenId), "User cannot stack this color");
		uint8 _pieceType = getPieceType(tokenId);
		bool hasValidClub = false;
		for (uint i = 7; i < 10; i++) {
			if (pieceDetails[_pieceType].palindromeClubRequirement) {
				if (i == pieceDetails[_pieceType].clubRequirement) {
					if (isClub(label, i) && isPalindrome(label, i)) {
						hasValidClub = true;
						break;
					}
				} else {
					if (isClub(label, i)) {
						hasValidClub = true;
						break;
					}
				}
			} else {
				if (isClub(label, i)) {
					hasValidClub = true;
					break;
				}
			}
		}
		require(hasValidClub, "Doesn't have a valid club name");
		typeStacked[_pieceType] += 1;
		nftShares[tokenId] = shareTypeAccumulator[_pieceType][epoch];
		expiration[tokenId] = getDomainExpirationDate(labelId);
		emit nftSharesUpdated(tokenId, shareTypeAccumulator[_pieceType][epoch]);

		if (typeStacked[_pieceType] == 1) {
			// If it's the first piece of this type
			if (_pieceType != 5) {
				pieceDetails[5].percentage -= pieceDetails[_pieceType].percentage;
			}
		}

		// Transfer the NFT to this contract
		transferFrom(msg.sender, address(this), tokenId);
		// Set the token ID for the ENS node
		nameOfTokenId[tokenId] = label;
		tokenIdOfName[label] = tokenId;
		emit NFTStacked(tokenId, label, expiration[tokenId]);
	}

	function unstack(uint256 tokenId) external {
		// Ensure the function caller owns the ENS node
		require(nameOfTokenId[tokenId] != 0x0, "Token is not stacked yet");
		// Ensure the NFT is managed by this contract, doublon?
		require(ownerOf(tokenId) == address(this), "NFT not staked");
		uint8 _pieceType = getPieceType(tokenId);
		bytes32 name = nameOfTokenId[tokenId];
		require(tokenIdOfName[name] != 0, "ENS not used yet");
		uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "Not owner of ENS node");
		typeStacked[_pieceType] -= 1;

		if (typeStacked[_pieceType] == 0) {
			if (_pieceType != 5) {
				pieceDetails[5].percentage += pieceDetails[_pieceType].percentage;
			}
		}

		// Transfer the NFT back to the function caller
		ERC721(address(this)).safeTransferFrom(address(this), msg.sender, tokenId);
		tokenIdOfName[name] = 0;
		expiration[tokenId] = 0;
		emit NFTUnstacked(tokenId, nameOfTokenId[tokenId]);
		nameOfTokenId[tokenId] = 0x0;
		_unstakeTimestamps[tokenId] = block.timestamp;

		updateUnclaimedRewards(_pieceType, tokenId);
		emit UpdateUnclaimedRewards(tokenId, unclaimedRewards[tokenId]);
		// update user and total stake count
		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
	}

	function listNFT(uint256 tokenId, uint256 price) external saleIsActive {
		require(!isForSale(tokenId));
		require(_isApprovedOrOwner(msg.sender, tokenId));
		require(price > 0);
		approve(address(this), tokenId);
		_setNftPrice(tokenId, price);
		emit NFTListed(msg.sender, tokenId, price);
	}

	function unlistNFT(uint256 tokenId) external saleIsActive {
		require(msg.sender == ownerOf(tokenId));
		require(isForSale(tokenId));
		uint256 price = getNftPrice(tokenId);
		require(price > 0);
		_setNftPrice(tokenId, 0);
		emit NFTUnlisted(msg.sender, tokenId, price);
	}

	function multiBuy(uint256[] calldata tokensId) external payable saleIsActive {
		require(tokensId.length > 0);
		require(msg.sender != address(0));
		uint256 totalPrice = 0;
		for (uint i = 0; i < tokensId.length; i++) {
			require(isForSale(tokensId[i]));
			uint256 price = getNftPrice(tokensId[i]);
			require(price > 0);
			totalPrice += price;
		}

		require(msg.value >= totalPrice);

		for (uint i = 0; i < tokensId.length; i++) {
			buyNFT(tokensId[i], getNftPrice(tokensId[i]));
			_setNftPrice(tokensId[i], 0);
		}
	}

	function buyNFT(uint256 tokenId, uint256 price) private saleIsActive {
		address seller = ownerOf(tokenId);
		require(msg.sender != seller);
		uint8 _pieceType = getPieceType(tokenId);
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		uint256 taxAmount = (totalReward * 20) / 100;

		prizePool += taxAmount / 2;
		uint256 holdersTax = taxAmount / 2;

		updateShareType(holdersTax);

		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		bool success;
		if (totalReward > 0) {
			// Ensure the contract has enough balance to pay the seller
			require(address(this).balance >= totalReward - taxAmount + price);
			(success, ) = payable(seller).call{ value: totalReward - taxAmount + price }("");
		} else {
			require(address(this).balance >= price);
			(success, ) = payable(seller).call{ value: price }("");
		}

		require(success);
		// Transfer nft
		ERC721(address(this)).safeTransferFrom(seller, msg.sender, tokenId);
		emit NFTPurchased(msg.sender, seller, tokenId, price);
	}

	function isColorValid(uint256 tokenId) private view returns (bool) {
		return (tokenId % 2 == 0 && userColor[msg.sender] == 1) || (tokenId % 2 != 0 && userColor[msg.sender] == 2);
	}

	function isPalindrome(bytes32 name, uint length) private pure returns (bool) {
		uint start = 0;
		uint end = length - 1;

		while (start < end) {
			bytes1 startByte = name[start];
			bytes1 endByte = name[end];

			// Vérifiez que les caractères sont des chiffres
			if ((startByte < 0x30) || (startByte > 0x39) || (endByte < 0x30) || (endByte > 0x39)) {
				return false;
			}
			// Vérifiez le palindrome
			if (startByte != endByte) {
				return false;
			}

			start++;
			end--;
		}

		return true;
	}

	function getPieceType(uint256 nftId) private pure returns (uint8) {
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
		} else if (nftId >= 362 && nftId < 10000) {
			return 5;
		}
	}

	// Let user choose the white or black color
	function chooseColor(uint8 _color) external {
		require(_color == 1 || _color == 2);
		require(userColor[msg.sender] == 0);
		userColor[msg.sender] = _color;
		emit ColorChoosed(_color, msg.sender);
	}

	function isClub(bytes32 name, uint length) private pure returns (bool) {
		for (uint i = 0; i < length; i++) {
			bytes1 b = name[i];
			if (b < 0x30 || b > 0x39) {
				return false;
			}
		}

		return true;
	}

	function revealKingHand(uint256 tokenId) external payable {
		require(msg.value >= 1000000000000);
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		require(getPieceType(tokenId) == 5, "Token must be a Pawn");
		prizePool += msg.value;
		bool isKingHand = kingAuction.revealKingHand(tokenId);
		emit KingHandRevealed(isKingHand);
	}

	function buyKing(bytes32 label) external payable {
		uint256 labelId = uint256(keccak256(abi.encodePacked(label)));
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "Not owner of ENS node");
		require(isClub(label, 7), "Only 999 Club can buy King");
		require(tokenIdOfName[label] == 0, "ENS name is already used");
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2, "User must choose a color before buying king");

		bool success = kingAuction.buyKing(userColor[msg.sender], msg.value);
		if (success) {
			// Stack the nft
			nameOfTokenId[userColor[msg.sender] - 1] = label;
			tokenIdOfName[label] = userColor[msg.sender] - 1;

			emit KingBought(msg.sender, msg.value, userColor[msg.sender] - 1, label);
			emit NFTStacked(userColor[msg.sender] - 1, label, getDomainExpirationDate(labelId));
		}
	}

	function getCurrentPrice() public view returns (uint256) {
		return kingAuction.getCurrentPrice();
	}

	function getDomainExpirationDate(uint256 labelId) public view returns (uint256) {
		return baseRegistrar.nameExpires(labelId) + 90 days;
	}

	// faire en sorte que la king hand puisse être claim une unique fois sa cagnotte
	function claimKingHand(uint256 tokenId) external {
		require(ownerOf(tokenId) == msg.sender);
		uint256 pieceShare = kingAuction.claimKingHand(tokenId);
		payable(msg.sender).transfer(pieceShare);
	}

	function claimPrizePool(uint256 tokenId) external saleIsNotActive {
		require(isClub(nameOfTokenId[tokenId], 7) || (isClub(nameOfTokenId[tokenId], 8)));
		require(ownerOf(tokenId) == msg.sender);
		require(hasClaimedGeneral[tokenId] == false);
		prizePool -= (prizePool / 999);
		payable(msg.sender).transfer(prizePool / 999);
		hasClaimedGeneral[tokenId] = true;
		uint8 _pieceType = getPieceType(tokenId);
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		if (totalReward > 0) {
			require(address(this).balance >= totalReward);
			payable(msg.sender).transfer(totalReward);
		}

		uint256 killFee = _killFeeDebt[msg.sender];
		if (killFee > 0) {
			_killFeeDebt[msg.sender] = 0;
			prizePool -= killFee;
			require(address(this).balance >= killFee);
			payable(msg.sender).transfer(killFee);
		}
	}

	function spawnKings() private {
		// Black king
		_mint(address(this), 0);
		_setTokenURI(0, "");
		pieceDetails[0].totalMinted++;
		pieceDetails[0].blackMinted++;
		totalMinted++;
		currentSupply++;
		typeStacked[0] += 1;
		expiration[0] = 0;
		emit NFTMinted(address(this), 0);
		nftShares[0] = 1;
		emit nftSharesUpdated(0, 1);

		// White king
		_mint(address(this), 1);
		_setTokenURI(1, "");
		pieceDetails[0].totalMinted++;
		pieceDetails[0].whiteMinted++;
		totalMinted++;
		currentSupply++;
		typeStacked[0] += 1;
		expiration[1] = 0;
		emit NFTMinted(address(this), 1);
		nftShares[1] = 1;
		emit nftSharesUpdated(1, 1);
	}

	function updateShareType(uint256 _tax) private {
		epoch += 1;

		uint256[6] memory newShares;
		for (uint8 i = 0; i < 6; i++) {
			if (typeStacked[i] > 0) {
				uint256 pieceShare = (_tax * pieceDetails[i].percentage) / 10;
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
		if (currentShares > 0 && nftShares[tokenId] > 0) {
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

	function getShareTypeAccumulator(uint i, uint j) external view returns (uint256) {
		return shareTypeAccumulator[i][j];
	}

	function getShareTypeAccumulatorSize() external view returns (uint, uint) {
		return (shareTypeAccumulator.length, shareTypeAccumulator[0].length);
	}

	function getNftShares(uint256 tokenId) external view returns (uint256) {
		return nftShares[tokenId];
	}

	function getUserColor(address user) external view returns (uint8) {
		return userColor[user];
	}

	function getBurnedCount(address user) external view returns (uint256) {
		return burnedCount[user];
	}

	function getBurnedCounterCount(address user) external view returns (uint256) {
		return burnedCounterCount[user];
	}

	function getTotalMinted() external view returns (uint256) {
		return totalMinted;
	}

	function getCurrentSupply() external view returns (uint256) {
		return currentSupply;
	}

	function getPrizePool() external view returns (uint256) {
		return prizePool;
	}
}
