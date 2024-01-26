// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@ensdomains/ens-contracts/contracts/ethregistrar/BaseRegistrarImplementation.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

using Strings for uint256;

contract KingAuction is VRFV2WrapperConsumerBase, Ownable {
	uint256 constant AUCTION_DURATION = 21 days;
	uint256 public constant END_PRICE = 2 ether;
	uint256 public auctionEndTime;

	address constant link = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
	address constant wrapper = 0x708701a1DfF4f478de54383E49a627eD4852C816;
	bool[2] public kingsInSale = [true, true];

	bool isKingsHandSet = false;

	uint256 kingHandsPrize = 0;
	uint256[10] internal kingHands;
	uint256 public recentRequestId;

	constructor() VRFV2WrapperConsumerBase(link, wrapper) {
		auctionEndTime = block.timestamp + AUCTION_DURATION;
	}

	function generateKingHands() public {
		require(!isKingsHandSet, "KA01");
		recentRequestId = requestRandomness(1000000, 3, 10);
		isKingsHandSet = true;
	}

	function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
		require(requestId == recentRequestId, "KA02");
		for (uint i = 0; i < 10; i++) {
			uint256 randomValue = uint256(keccak256(abi.encode(randomWords[i], i)));
			randomValue = (randomValue % 9637) + 362;
			kingHands[i] = randomValue;
		}
	}

	function buyKing(uint256 _color, uint256 value) external onlyOwner returns (bool) {
		require(block.timestamp <= auctionEndTime);
		require(kingsInSale[_color - 1]);
		uint256 currentPrice = getCurrentPrice();
		require(value >= currentPrice);
		kingHandsPrize += value;
		kingsInSale[_color - 1] = false;
		return true;
	}

	function getCurrentPrice() public view returns (uint256) {
		uint256 ts = block.timestamp;
		if (ts >= auctionEndTime) {
			return END_PRICE;
		} else {
			uint256 timeElapsed = ts - (auctionEndTime - AUCTION_DURATION);
			int128 _secondsElapsed = ABDKMath64x64.fromUInt(timeElapsed);
			int128 _secondsInDay = ABDKMath64x64.fromUInt(60 * 60 * 24);
			int128 _days = ABDKMath64x64.div(_secondsElapsed, _secondsInDay);
			int128 x64x64 = _days;

			int128 negOneThird = ABDKMath64x64.divi(-100, 158);
			int128 one = ABDKMath64x64.fromUInt(1);

			int128 innerCalculation = ABDKMath64x64.add(ABDKMath64x64.mul(negOneThird, x64x64), one);

			int128 result = ABDKMath64x64.exp_2(innerCalculation);

			uint256 resultUint = ABDKMath64x64.toUInt(ABDKMath64x64.mul(result, ABDKMath64x64.fromUInt(1e18)));
			uint256 resultEther = resultUint * 10000;

			if (resultEther < END_PRICE) {
				resultEther = END_PRICE;
			}

			return resultEther;
		}
	}

	function revealKingHand(uint256 tokenId) external view onlyOwner returns (bool) {
		bool isKingsHand = false;
		for (uint i = 0; i < 10; i++) {
			if (tokenId == kingHands[i]) {
				isKingsHand = true;
				break;
			}
		}
		return isKingsHand;
	}

	function claimKingHand() external view returns (uint256) {
		uint256 pieceShare = kingHandsPrize / 10;
		return pieceShare;
	}
}

contract NumberRunnerClub is ERC721URIStorage, ReentrancyGuard {
	event NFTPurchased(address buyer, address seller, uint256 tokenId, uint256 price);
	event KingBought(address buyer, uint256 price, uint256 tokenId, string ensName);
	event ColorChoosed(uint8 color, address user);
	event NFTListed(address seller, uint256 tokenId, uint256 price);
	event NFTUnlisted(address seller, uint256 tokenId, uint256 price);
	event KingHandBurned(uint256 tokenId);
	event NFTBurned(address owner, uint256 tokenId);
	event NFTMinted(address owner, uint256 tokenId);
	event globalSharesUpdated(uint256[6] shares);
	event nftSharesUpdated(uint256 tokenId, uint256 shares);
	event NFTStacked(uint256 tokenId, string ensName, uint256 expiration);
	event NFTUnstacked(uint256 tokenId, string ensName);
	event UpdateUnclaimedRewards(uint256 tokenId, uint256 rewards);
	event KingHandRevealed(bool success);
	event NFTKilled(uint256 tokenId);

	uint256 constant ONE_WEEK = 1 weeks;

	address constant _baseRegistrar = 0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85;
	address constant NRC = 0xA113BEFb068c6583acf123C86cdbBB24B35D2D37;

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

	KingAuction public kingAuction;

	uint256 public constant MAX_NFT_SUPPLY = 10000;
	uint256 public totalMinted = 0;
	uint256 public freeMintCounter = 0;
	uint256 public currentSupply = 0;
	uint256 public userStacked = 0;
	uint256 public currentEpoch = 0;
	uint256 public epoch = 0;
	uint256 prizePool;

	BaseRegistrarImplementation public baseRegistrar;
	mapping(string => uint256) public tokenIdOfName; // Mapping of ENS hash to the corresponding tokenId
	mapping(uint256 => string) public nameOfTokenId; // Mapping of tokenId to the corresponding ENS name
	mapping(uint256 => uint256) private _unstakeTimestamps;
	mapping(uint256 => uint256) public expiration;
	PieceDetails[6] pieceDetails;

	uint256[6] private typeStacked;
	uint256[][6] shareTypeAccumulator;
	mapping(uint256 => uint256) nftShares;

	mapping(uint256 => uint256) public unclaimedRewards;
	mapping(address => uint8) public userColor;
	mapping(address => uint256) private burnedCount;
	mapping(address => uint256) private burnedCounterCount;
	mapping(address => bool) public hasClaimedFreeMint;
	mapping(uint256 => uint256) public nftPriceForSale;

	constructor() ERC721("Number Runner Club", "NRC") {
		pieceDetails[0] = PieceDetails(2, 0, 0, 0, 2, 0, 0, 3, 0, 0, false);
		pieceDetails[1] = PieceDetails(10, 0, 0, 0, 1, 15, 2, 3, 15, 15, false);
		pieceDetails[2] = PieceDetails(50, 0, 0, 0, 1, 15, 12, 4, 15, 15, true);
		pieceDetails[3] = PieceDetails(100, 0, 0, 0, 1, 15, 62, 4, 10, 10, false);
		pieceDetails[4] = PieceDetails(200, 0, 0, 0, 1, 15, 162, 4, 10, 0, false);
		pieceDetails[5] = PieceDetails(9638, 0, 0, 0, 8, 20, 362, 5, 0, 0, false);
		baseRegistrar = BaseRegistrarImplementation(_baseRegistrar);
		prizePool = 0;
		for (uint8 i = 0; i < 6; i++) {
			shareTypeAccumulator[i].push(1);
		}

		epoch += 1;
		for (uint8 i = 0; i < 6; i++) {
			shareTypeAccumulator[i].push(shareTypeAccumulator[i][epoch - 1]);
		}
		uint256[6] memory currentShares;
		for (uint8 i = 0; i < 6; i++) {
			currentShares[i] = shareTypeAccumulator[i][epoch];
		}
		emit globalSharesUpdated(currentShares);

		spawnKings();

		kingAuction = new KingAuction();
	}

	modifier saleIsActive() {
		require(currentSupply + MAX_NFT_SUPPLY - totalMinted > 15, "NRC01");
		_;
	}

	modifier saleIsNotActive() {
		require(!(currentSupply + MAX_NFT_SUPPLY - totalMinted > 15), "NRC02");
		_;
	}

	function multiMint(uint256 _n) external payable {
		require(_n > 0);
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2, "NRC03");
		if (userColor[msg.sender] == 1) {
			require(pieceDetails[5].blackMinted + _n <= pieceDetails[5].maxSupply / 2, "NRC04");
		} else {
			require(pieceDetails[5].whiteMinted + _n <= pieceDetails[5].maxSupply / 2, "NRC04");
		}
		uint256 startId = userColor[msg.sender] == 1 ? 362 + 2 * pieceDetails[5].blackMinted : 363 + 2 * pieceDetails[5].whiteMinted;
		uint256 mintCount = _n;

		if (!hasClaimedFreeMint[msg.sender] && freeMintCounter < 30) {
			hasClaimedFreeMint[msg.sender] = true;
			freeMintCounter++;
			mintCount = _n - 1;
		}

		if (mintCount > 0) {
			require(msg.value >= 50000000000000000 * mintCount, "NRC05");
		}

		for (uint8 i = 0; i < _n; i++) {
			uint256 newItemId = startId + 2 * i;
			_mint(msg.sender, newItemId);
			_setTokenURI(newItemId, string(abi.encodePacked("ipfs://QmceFYj1a3xvhuwqb5dNstbzZ5FWNfkWfiDvPkVwvgfQpm/NumberRunner", newItemId.toString(), ".json")));
			pieceDetails[5].totalMinted++;
			unclaimedRewards[newItemId] = 0;
			nftShares[newItemId] = 0;
			_unstakeTimestamps[newItemId] = block.timestamp;
			expiration[newItemId] = 0;
			userColor[msg.sender] == 1 ? pieceDetails[5].blackMinted++ : pieceDetails[5].whiteMinted++;
			totalMinted++;
			currentSupply++;
			if (i < mintCount) {
				prizePool += 12500000000000000;
				updateShareType(12500000000000000);
			}

			emit NFTMinted(msg.sender, newItemId);
		}

		if (mintCount > 0) {
			payable(NRC).transfer(25000000000000000 * mintCount);
		}
	}

	function mint(uint8 _pieceType, uint256 _stackedPiece) external payable {
		require(msg.value >= 50000000000000000, "NRC05");
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2, "NRC03");
		if (userColor[msg.sender] == 1) {
			require(pieceDetails[_pieceType].blackMinted <= pieceDetails[_pieceType].maxSupply / 2, "NRC04");
		} else {
			require(pieceDetails[_pieceType].whiteMinted <= pieceDetails[_pieceType].maxSupply / 2, "NRC04");
		}

		// Set the id of the minting token from the type and color of the piece chosen
		// Black token have even id
		// White token have odd id
		uint256 newItemId = userColor[msg.sender] == 1 ? pieceDetails[_pieceType].startingId + 2 * pieceDetails[_pieceType].blackMinted : pieceDetails[_pieceType].startingId + 1 + 2 * pieceDetails[_pieceType].whiteMinted;
		// No restriction for minting Pawn
		if (_pieceType != 5) {
			bool hasRequiredClubStacked = false;
			for (uint i = 3; i <= pieceDetails[_pieceType].clubRequirement; i++) {
				string memory name = nameOfTokenId[_stackedPiece];
				uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
				require(baseRegistrar.ownerOf(labelId) == msg.sender, "NRC06");
				if (isClub(name, i)) {
					hasRequiredClubStacked = true;
					break;
				}
			}
			require(hasRequiredClubStacked, "NRC08");
			require(burnedCount[msg.sender] >= pieceDetails[_pieceType].burnRequirement);
			burnedCount[msg.sender] -= pieceDetails[_pieceType].burnRequirement;
			if (pieceDetails[_pieceType].opponentColorBurnRequirement > 0) {
				require(burnedCounterCount[msg.sender] >= pieceDetails[_pieceType].opponentColorBurnRequirement);
				burnedCounterCount[msg.sender] -= pieceDetails[_pieceType].opponentColorBurnRequirement;
			}
		}

		_mint(msg.sender, newItemId);
		_setTokenURI(newItemId, string(abi.encodePacked("ipfs://QmceFYj1a3xvhuwqb5dNstbzZ5FWNfkWfiDvPkVwvgfQpm/NumberRunner", newItemId.toString(), ".json")));
		unclaimedRewards[newItemId] = 0;
		nftShares[newItemId] = 0;
		_unstakeTimestamps[newItemId] = block.timestamp;
		expiration[newItemId] = 0;
		pieceDetails[_pieceType].totalMinted++;
		userColor[msg.sender] == 1 ? pieceDetails[_pieceType].blackMinted++ : pieceDetails[_pieceType].whiteMinted++;
		totalMinted++;
		currentSupply++;
		prizePool += 12500000000000000;

		// Add the transaction fee to the piece's balance
		updateShareType(12500000000000000);

		emit NFTMinted(msg.sender, newItemId);

		payable(NRC).transfer(25000000000000000);
	}

	function burn(uint256 tokenId) external saleIsActive {
		require(ownerOf(tokenId) == msg.sender, "NRC07");
		require(!isForSale(tokenId));
		require(bytes(nameOfTokenId[tokenId]).length == 0);
		uint8 _pieceType = getPieceType(tokenId);
		require(_pieceType != 0, "NRC11");
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		uint256 taxAmount = (totalReward * pieceDetails[_pieceType].burnTax) / 100;
		uint256 holdersTax = taxAmount / 2;
		prizePool += taxAmount / 2;

		updateShareType(holdersTax);
		nameOfTokenId[tokenId] = "";

		_burn(tokenId);
		burnedCount[msg.sender]++;
		if (!isColorValid(tokenId)) {
			burnedCounterCount[msg.sender]++;
		}
		currentSupply--;
		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		if (totalReward > 0) {
			require(address(this).balance >= totalReward - taxAmount);
			payable(msg.sender).transfer(totalReward - taxAmount);
		}
		emit NFTBurned(msg.sender, tokenId);
	}

	function multiKill(uint256[] calldata tokensId) external payable saleIsActive {
		require(tokensId.length > 0);
		require(msg.sender != address(0));
		require(totalMinted == MAX_NFT_SUPPLY, "All NFT must be minted for access this feature");
		uint256 totalPrice = 0;
		uint256 killFee = 0;
		uint256 rewards = 0;
		for (uint i = 0; i < tokensId.length; i++) {
			require(!isColorValid(tokensId[i]));
			rewards = unclaimedRewards[tokensId[i]] + nftShares[tokensId[i]];

			if (bytes(nameOfTokenId[tokensId[i]]).length != 0) {
				if (isClub(nameOfTokenId[tokensId[i]], 5)) {
					killFee = 150000000000000000 + (rewards * 10) / 100;
				} else {
					require(block.timestamp > expiration[tokensId[i]]);
					killFee = 0;
				}
			} else {
				require(block.timestamp >= _unstakeTimestamps[tokensId[i]] + ONE_WEEK, "Cannot burn: One week waiting period is not over");
				if (isForSale(tokensId[i])) {
					killFee = 100000000000000000 + (rewards * 10) / 100;
				} else {
					killFee = 50000000000000000 + (rewards * 10) / 100;
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

	function killNFT(uint256 tokenId) private {
		uint8 _pieceType = getPieceType(tokenId);
		require(_pieceType != 0, "NRC11");
		uint256 killFee = 0;
		uint256 rewards = unclaimedRewards[tokenId] + nftShares[tokenId];

		if (bytes(nameOfTokenId[tokenId]).length != 0) {
			if (isClub(nameOfTokenId[tokenId], 5)) {
				killFee = 150000000000000000 + (rewards * 10) / 100;
			} else {
				require(block.timestamp > expiration[tokenId]);
				killFee = 0;
			}
		} else {
			if (isForSale(tokenId)) {
				killFee = 100000000000000000 + (rewards * 10) / 100;
			} else {
				killFee = 50000000000000000 + (rewards * 10) / 100;
			}
		}
		prizePool += (rewards * 10) / 100;

		_burn(tokenId);

		currentSupply--;

		if (rewards > 0) {
			require(address(this).balance >= rewards - (rewards * 15) / 100);
			string memory name = nameOfTokenId[tokenId];
			if (bytes(name).length != 0) {
				uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
				payable(baseRegistrar.ownerOf(labelId)).transfer(rewards - (rewards * 15) / 100);
				tokenIdOfName[nameOfTokenId[tokenId]] = 0;
				nameOfTokenId[tokenId] = "";
			} else {
				payable(ownerOf(tokenId)).transfer(rewards - (rewards * 15) / 100);
			}
		}

		emit NFTKilled(tokenId);
		emit NFTBurned(msg.sender, tokenId);
	}

	function updateExpiration(uint256 tokenId) external {
		// Ensure the function caller owns the ENS node
		require(bytes(nameOfTokenId[tokenId]).length != 0, "NRC09");
		require(ownerOf(tokenId) == address(this));
		string memory name = nameOfTokenId[tokenId];
		require(tokenIdOfName[name] != 0);
		uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
		// Ensure the function caller owns the ENS node
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "NRC06");

		expiration[tokenId] = getDomainExpirationDate(labelId);
		emit NFTStacked(tokenId, name, expiration[tokenId]);
	}

	function stack(string memory label, uint256 tokenId) external {
		uint256 labelId = uint256(keccak256(abi.encodePacked(label)));
		require(!isForSale(tokenId));
		require(bytes(nameOfTokenId[tokenId]).length == 0);
		require(tokenIdOfName[label] == 0);
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "NRC06");

		require(ownerOf(tokenId) == msg.sender, "NRC07");

		require(isColorValid(tokenId));
		uint8 _pieceType = getPieceType(tokenId);
		bool hasValidClub = false;
		for (uint i = 3; i <= pieceDetails[_pieceType].clubRequirement; i++) {
			if (pieceDetails[_pieceType].palindromeClubRequirement) {
				if (i == pieceDetails[_pieceType].clubRequirement) {
					if (isClub(label, i) && isPalindrome(label)) {
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
		require(hasValidClub, "NRC08");
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

		transferFrom(msg.sender, address(this), tokenId);
		nameOfTokenId[tokenId] = label;
		tokenIdOfName[label] = tokenId;
		emit NFTStacked(tokenId, label, expiration[tokenId]);
	}

	function unstack(uint256 tokenId) external {
		// Ensure the function caller owns the ENS node
		require(bytes(nameOfTokenId[tokenId]).length != 0, "NRC09");
		// Ensure the NFT is managed by this contract, doublon?
		require(ownerOf(tokenId) == address(this), "NFT not staked");
		uint8 _pieceType = getPieceType(tokenId);
		string memory name = nameOfTokenId[tokenId];
		// require(tokenIdOfName[name] != 0, "ENS not used yet");
		uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "NRC06");
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
		nameOfTokenId[tokenId] = "";
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
		require(msg.sender == ownerOf(tokenId), "NRC07");
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
		uint256 taxAmount = (totalReward * 20) / 100 + (price * 20) / 100;

		prizePool += taxAmount / 2;
		uint256 holdersTax = taxAmount / 2;

		updateShareType(holdersTax);

		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		bool success;
		if (totalReward > 0) {
			// Ensure the contract has enough balance to pay the seller
			require(address(this).balance >= totalReward - taxAmount + ((price * 80) / 100));
			(success, ) = payable(seller).call{ value: totalReward - taxAmount + price }("");
		} else {
			require(address(this).balance >= price);
			(success, ) = payable(seller).call{ value: ((price * 80) / 100) }("");
		}

		require(success);
		// Transfer nft
		ERC721(address(this)).safeTransferFrom(seller, msg.sender, tokenId);
		emit NFTPurchased(msg.sender, seller, tokenId, price);
	}

	function isColorValid(uint256 tokenId) private view returns (bool) {
		return (tokenId % 2 == 0 && userColor[msg.sender] == 1) || (tokenId % 2 != 0 && userColor[msg.sender] == 2);
	}

	function isPalindrome(string memory name) private pure returns (bool) {
		bytes memory nameBytes = bytes(name);
		uint start = 0;
		uint end = nameBytes.length - 1;

		while (start < end) {
			if (nameBytes[start] != nameBytes[end]) {
				return false;
			}
			start++;
			end--;
		}
		return true;
	}

	function isClub(string memory name, uint length) private pure returns (bool) {
		bytes memory nameBytes = bytes(name);
		if (nameBytes.length != length) {
			return false;
		}
		for (uint i = 0; i < nameBytes.length; i++) {
			if (nameBytes[i] < 0x30 || nameBytes[i] > 0x39) {
				return false;
			}
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
		} else if (nftId >= 362 && nftId < 9999) {
			return 5;
		} else {
			return 10;
		}
	}

	// Let user choose the white or black color
	function chooseColor(uint8 _color) external {
		require(_color == 1 || _color == 2);
		require(userColor[msg.sender] == 0);
		userColor[msg.sender] = _color;
		emit ColorChoosed(_color, msg.sender);
	}

	function revealKingHand(uint256 tokenId) external payable {
		require(msg.value >= 10000000000000000); // reveal price fixed at 0.01 eth
		require(ownerOf(tokenId) == msg.sender, "NRC07");
		require(getPieceType(tokenId) == 5);
		prizePool += msg.value;
		bool isKingHand = kingAuction.revealKingHand(tokenId);
		emit KingHandRevealed(isKingHand);
	}

	function buyKing(string memory label) external payable {
		uint256 labelId = uint256(keccak256(abi.encodePacked(label)));
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "NRC06");
		require(isClub(label, 3), "NRC08");
		require(tokenIdOfName[label] == 0);
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2);

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

	function claimPrizePool(uint256 tokenId) external saleIsNotActive {
		require(isClub(nameOfTokenId[tokenId], 3) || (isClub(nameOfTokenId[tokenId], 4)), "NRC08");
		string memory name = nameOfTokenId[tokenId];
		require(bytes(nameOfTokenId[tokenId]).length != 0, "NRC09");
		uint256 labelId = uint256(keccak256(abi.encodePacked(name)));
		require(baseRegistrar.ownerOf(labelId) == msg.sender, "NRC06");
		if (kingAuction.revealKingHand(tokenId)) {
			uint256 pieceShare = kingAuction.claimKingHand();
			payable(msg.sender).transfer(pieceShare);
		}
		payable(msg.sender).transfer(prizePool / 999);
		uint8 _pieceType = getPieceType(tokenId);
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		// Reset reward to 0
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
		if (totalReward > 0) {
			require(address(this).balance >= totalReward, "NRC10");
			payable(msg.sender).transfer(totalReward);
		}

		_burn(tokenId);
		emit NFTBurned(msg.sender, tokenId);
	}

	function spawnKings() private {
		// Black king
		_mint(address(this), 0);
		_setTokenURI(0, "ipfs://QmceFYj1a3xvhuwqb5dNstbzZ5FWNfkWfiDvPkVwvgfQpm/NumberRunner0.json");
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
		_setTokenURI(1, "ipfs://QmceFYj1a3xvhuwqb5dNstbzZ5FWNfkWfiDvPkVwvgfQpm/NumberRunner1.json");
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

	function getTokenIdOfName(string memory name) external view returns (uint256) {
		return tokenIdOfName[name];
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

	function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
		if (isForSale(tokenId)) {
			_setNftPrice(tokenId, 0);
			emit NFTUnlisted(from, tokenId, getNftPrice(tokenId));
		}

		ERC721.transferFrom(from, to, tokenId);
	}

	function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override(ERC721, IERC721) {
		if (isForSale(tokenId)) {
			_setNftPrice(tokenId, 0);
			emit NFTUnlisted(from, tokenId, getNftPrice(tokenId));
		}

		ERC721.safeTransferFrom(from, to, tokenId, _data);
	}
}
