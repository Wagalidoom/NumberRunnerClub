contract NumberRunnerClub is ERC721URIStorage, Ownable, ReentrancyGuard {
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

	uint256 public epoch = 0;
	uint256 prizePool;
	uint256 proposalCounter;

	ENS ens;
	mapping(uint256 => bytes32) public nodeOfTokenId; // Mapping of tokenId to the corresponding ENS hash
	mapping(bytes32 => uint256) public tokenIdOfNode; // Mapping of ENS hash to the corresponding tokenId
	mapping(uint256 => bytes32) public nameOfTokenId; // Mapping of tokenId to the corresponding ENS name
	PieceDetails[6] pieceDetails;

	uint256[6] private typeStacked;

	uint256[][6] shareTypeAccumulator;

	mapping(uint256 => uint256) nftShares;

	mapping(uint256 => uint256) public unclaimedRewards; // Mapping des récompenses non claim associées au nft
	mapping(address => uint8) public userColor; // Mapping of user address to chosen color
	mapping(address => uint256) private burnedCount; // Mapping of user address to counter of nft burned
	mapping(address => uint256) private burnedCounterCount; // Mapping of user address to counter of nft from the opponent color burned
	mapping(uint256 => Proposal) public proposals; // Mapping of nft stacked in the contract
	mapping(uint256 => bool) public hasClaimedGeneral;
	mapping(uint256 => uint256) public nftPriceForSale;

	constructor(address _ens, address _vrfCoordinator, address _link) ERC721("NumberRunnerClub", "NRC") {
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

		kingAuction = new KingAuction(auctionEndTime, auctionDuration, minPrice, _vrfCoordinator, _link);
	}

	modifier saleIsActive() {
		require(totalMinted < MAX_NFT_SUPPLY || currentSupply > 999, "Collection ended");
		_;
	}

	function multiMint(uint8 _n) public payable {
		require(msg.value >= 20000000000000 * _n, "User must send at least _n * 0.2 eth for minting a token");
		require(userColor[msg.sender] == 1 || userColor[msg.sender] == 2, "User must choose a color before minting");
		require(pieceDetails[5].totalMinted + _n < pieceDetails[5].maxSupply, "Max supply for this Pawn type reached");
		if (userColor[msg.sender] == 1) {
			require(pieceDetails[5].blackMinted + _n < pieceDetails[5].maxSupply / 2, "Max supply for black color reached");
		} else {
			require(pieceDetails[5].whiteMinted + _n < pieceDetails[5].maxSupply / 2, "Max supply for white color reached");
		}

		for (uint8 i = 0; i < _n; i++) {
			uint256 newItemId = userColor[msg.sender] == 1 ? 362 + 2 * pieceDetails[5].blackMinted + 2 * i : 363 + 2 * pieceDetails[5].whiteMinted + 2 * i;
			_mint(msg.sender, newItemId);
			_setTokenURI(newItemId, string(abi.encodePacked("ipfs://QmPp5WG6DFfXM1sHshkA9sU6je8rWbjivrZjQmmGBXVEr7/NumberRunner#", newItemId, ".json")));
			pieceDetails[5].totalMinted++;
			userColor[msg.sender] == 1 ? pieceDetails[5].blackMinted++ : pieceDetails[5].whiteMinted++;
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
		}
	}

	function mint(uint8 _pieceType, uint256 _stackedPiece) public payable {
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
		_setTokenURI(newItemId, string(abi.encodePacked("ipfs://QmPp5WG6DFfXM1sHshkA9sU6je8rWbjivrZjQmmGBXVEr7/NumberRunner#", newItemId, ".json")));
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

	}

	function burn(uint256 tokenId) public saleIsActive {
		require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: burn caller is not owner nor approved");
		require(!isForSale(tokenId), "This NFT is already on sale");
		require(nodeOfTokenId[tokenId] == 0x0, "Cannot burn a stacked token");
		uint8 _pieceType = getPieceType(tokenId);
		require(_pieceType != 0, "Cannot burn the King");
		updateUnclaimedRewards(_pieceType, tokenId);
		uint256 totalReward = unclaimedRewards[tokenId];
		unclaimedRewards[tokenId] = 0;
		emit UpdateUnclaimedRewards(tokenId, 0);
		uint256 taxAmount = (totalReward * pieceDetails[_pieceType].burnTax) / 100;
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
				} else {
					if (isClub(name, i)) {
						hasValidClub = true;
						break;
					}
				}
			} else {
				if (isClub(name, i)) {
					hasValidClub = true;
					break;
				}
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
		transferFrom(msg.sender, address(this), tokenId);
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
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");
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
		nftShares[tokenId] = 0;
		emit nftSharesUpdated(tokenId, 0);
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

	function multiBuy(uint256[] calldata tokensId) public payable saleIsActive {
		require(tokensId.length > 0, "TokensId array is empty");
		require(msg.sender != address(0), "Buyer is zero address");
		uint256 totalPrice = 0;
		for (uint i = 0; i < tokensId.length; i++) {
        	require(isForSale(tokensId[i]), "NFT is not for sale");
			uint256 price = getNftPrice(tokensId[i]);
			require(price > 0);
			totalPrice += price;
		}

		require(msg.value >= totalPrice, "Insufficient amount sent");

		for (uint i = 0; i < tokensId.length; i++) {
        	buyNFT(tokensId[i], getNftPrice(tokensId[i]));
		}
    }

	function buyNFT(uint256 tokenId, uint256 price) private saleIsActive {
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
}
