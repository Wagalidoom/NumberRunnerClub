// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import "@ensdomains/ens-contracts/contracts/resolvers/profiles/TextResolver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./INumberRunnerClub.sol";

// TODO add system of burn/sell before claiming personal prize
contract NumberRunnerClub is INumberRunnerClub, ERC721URIStorage, VRFV2WrapperConsumerBase, Ownable, ReentrancyGuard {
	enum Piece {
		King,
		Queen,
		Rook,
		Knight,
		Bishop,
		Pawn
	}

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

	Piece[] public collection;
	uint256 public constant MAX_NFT_SUPPLY = 10000;
	uint256 public totalMinted = 0;
	uint256 public currentSupply = 0;
	uint256 public userStacked = 0;
	uint256 public currentEpoch = 0;
	// L'epoch actuel
	uint256 public epoch;
	uint256[] kingHands;
	bool isKingsHandSet = false;
	uint256 public recentRequestId;
	uint256 prizePool;
	uint256 proposalCounter;
	uint256 kingHandsPrize = 0;

	ENS ens;
	TextResolver textResolver;
	mapping(uint256 => bytes32) public nodeOfTokenId; // Mapping of tokenId to the corresponding ENS name
	// mapping(Piece => PieceDetails) public pieceDetails; // Mapping of Chess Piece to the corresponding Details
	PieceDetails[6] pieceDetails;
	mapping(uint256 => uint256) private tokenBalance; // Mapping of tokenId to the matching balance
	// uint256[6][][] private idStacked;
	mapping(uint8 => uint256[]) private idStacked; // Mapping of Piece to the tokenIds of this piece type stacked in contract
	uint256[6][] private idToIndex;
	// mapping(Piece => mapping(uint256 => uint256)) private idToIndex;

	// La somme totale de tous les sharePerTokenAtEpoch pour chaque type de pièce
	uint256[6][] totalSharePerToken;
	// Le sharePerToken de l'utilisateur à l'epoch où il a stacké son dernier token
	mapping(bytes32 => mapping(uint8 => uint256)) userSharePerToken;
	// Le nombre total de tokens stakés pour chaque type de pièce
	uint256[8] totalStaked;
	// Le nombre de tokens que chaque utilisateur a staké pour chaque type de pièce
	mapping(bytes32 => mapping(uint8 => uint256)) userStaked;

	mapping(address => uint8) public userColor; // Mapping of user address to chosen color
	mapping(address => uint256) private burnedCount; // Mapping of user address to counter of nft burned
	mapping(address => uint256) private burnedCounterCount; // Mapping of user address to counter of nft from the opponent color burned
	mapping(address => uint256[]) public userOwnedNFTs; // Mapping of user address to his owned nft
	mapping(address => uint256[]) public userStackedNFTs; // Mapping of user address to his nft stacked in the contract
	mapping(uint256 => bool) public isStaked; // Mapping of nft stacked in the contract
	mapping(uint256 => Proposal) public proposals; // Mapping of nft stacked in the contract
	mapping(uint256 => bool) public hasClaimedGeneral;

	event KingHandBurned(uint256 tokenId);

	constructor(address _ens, address _resolver, address _vrfCoordinator, address _link) ERC721("NumberRunnerClub", "NRC") VRFV2WrapperConsumerBase(_link, _vrfCoordinator) {
		pieceDetails[0] = PieceDetails(2, 0, 0, 0, 350, 0, 0, 8, 0, 0, true);
		pieceDetails[1] = PieceDetails(10, 0, 0, 0, 225, 35, 2, 7, 15, 15, false);
		pieceDetails[2] = PieceDetails(50, 0, 0, 0, 150, 35, 12, 8, 15, 15, true);
		pieceDetails[3] = PieceDetails(100, 0, 0, 0, 125, 30, 62, 8, 10, 10, false);
		pieceDetails[4] = PieceDetails(200, 0, 0, 0, 100, 25, 162, 9, 10, 0, true);
		pieceDetails[5] = PieceDetails(9638, 0, 0, 0, 650, 25, 362, 9, 0, 0, false);
		ens = ENS(_ens);
		textResolver = TextResolver(_resolver);
		prizePool = 0;
	}

	// TODO à qui redistribuer les frais de mint sur le premier mint et/ou quand il n'y a pas de nft stacké
	function mint(uint8 _pieceType) public payable returns (uint256) {
		require(msg.value >= 200000000000000000, "User must send at least 0.2 eth for minting a token");
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
			for (uint i = 7; i < pieceDetails[_pieceType].clubRequirement; i++) {
				if (hasClubStacked(msg.sender, i)) {
					hasRequiredClubStacked = true;
					break;
				}
			}
			require(hasRequiredClubStacked, "Doesn't have a required club stacked");
			require(burnedCounterCount[msg.sender] > pieceDetails[_pieceType].burnRequirement, "Doesn't burn enough piece");
			if (pieceDetails[_pieceType].opponentColorBurnRequirement > 0) {
				require(burnedCounterCount[msg.sender] > pieceDetails[_pieceType].opponentColorBurnRequirement, "Doesn't burn enough opponent piece");
			}
		}

		_mint(msg.sender, newItemId);
		_setTokenURI(newItemId, "");
		// collection.push(_piece);
		userOwnedNFTs[msg.sender].push(newItemId);
		pieceDetails[_pieceType].totalMinted++;
		userColor[msg.sender] == 1 ? pieceDetails[_pieceType].blackMinted++ : pieceDetails[_pieceType].whiteMinted++;
		totalMinted++;
		currentSupply++;

		// Add the transaction fee to the piece's balance
		for (uint8 i = 0; i < 6; i++) {
			if (idStacked[i].length > 0) {
				uint256 pieceShare = (100000000000000 * pieceDetails[i].percentage);
				if (totalStaked[i] > 0) {
					totalSharePerToken[i][epoch] = totalSharePerToken[i][epoch - 1] + pieceShare / totalStaked[i];
				}
				updateEpoch();
			}
		}
		return newItemId;
	}

	// fonction en cours de production
	// TODO intégrer systeme de vente sur ce contrat ou contrat externe
	function sellNFT(uint256 tokenId, address buyer) public {
		require(totalMinted == MAX_NFT_SUPPLY && currentSupply > 999, "Collection ended");
		require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
		uint256 taxAmount = (tokenBalance[tokenId] * 16) / 100;
		uint256 balance = tokenBalance[tokenId];
		uint256 holdersTax = taxAmount / 2;
		prizePool += taxAmount / 2;

		// Mettre à jour les rewards 
		for (uint8 i = 0; i < 6; i++) {
			if (idStacked[i].length > 0) {
				uint256 pieceShare = (holdersTax * pieceDetails[i].percentage);
				if (totalStaked[i] > 0) {
					totalSharePerToken[i][epoch] = totalSharePerToken[i][epoch - 1] + pieceShare / totalStaked[i];
				}
				updateEpoch();
			}
		}

		tokenBalance[tokenId] = 0;
		payable(msg.sender).transfer(balance - taxAmount);
		safeTransferFrom(_msgSender(), buyer, tokenId);
		uint256 indexNFT = findIndexOfOwnedNFT(msg.sender, tokenId);
		userOwnedNFTs[msg.sender][indexNFT] = userOwnedNFTs[msg.sender][userOwnedNFTs[msg.sender].length - 1];
		userOwnedNFTs[msg.sender].pop();
	}

	function burnNFT(uint256 tokenId) public {
		require(totalMinted == MAX_NFT_SUPPLY && currentSupply > 999, "Collection ended");
		require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: burn caller is not owner nor approved");
		require(isStaked[tokenId] == false, "Cannot burn a stacked token");
		uint8 _pieceType = getPieceType(tokenId);
		require(_pieceType != 0, "Cannot burn the King");
		uint256 taxAmount = (tokenBalance[tokenId] * pieceDetails[_pieceType].burnTax) / 100;
		uint256 balance = tokenBalance[tokenId];
		// TODO revoir la redistribution pour gérer les arrondis
		uint256 holdersTax = taxAmount / 2;
		prizePool += taxAmount / 2;
		// Mettre à jour les rewards 
		for (uint8 i = 0; i < 6; i++) {
			if (idStacked[i].length > 0) {
				uint256 pieceShare = (holdersTax * pieceDetails[i].percentage);
				if (totalStaked[i] > 0) {
					totalSharePerToken[i][epoch] = totalSharePerToken[i][epoch - 1] + pieceShare / totalStaked[i];
				}
				updateEpoch();
			}
		}

		_burn(tokenId);
		burnedCount[msg.sender]++;
		if (!isColorValid(tokenId)) {
			burnedCounterCount[msg.sender]++;
		}
		if (getPieceType(tokenId) == 5) {
			for (uint256 i = 0; i < kingHands.length; i++) {
				if (tokenId == kingHands[i]) {
					kingHands[i] = kingHands[kingHands.length - 1];
					kingHands.pop();
					emit KingHandBurned(tokenId);
				}
			}
		}
		uint256 indexNFT = findIndexOfOwnedNFT(msg.sender, tokenId);
		userOwnedNFTs[msg.sender][indexNFT] = userOwnedNFTs[msg.sender][userOwnedNFTs[msg.sender].length - 1];
		userOwnedNFTs[msg.sender].pop();
		currentSupply--;
		tokenBalance[tokenId] = 0;
		payable(msg.sender).transfer(balance - taxAmount);
	}

	// comment verifier que le token stake provient bien de la collection ?
	function _stake(bytes32 node, uint256 tokenId) public {
		// Ensure the function caller owns the ENS node
		require(!isStaked[tokenId], "Token is already stacked");
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");

		// Ensure the function caller owns the NFT
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");

		// Ensure the NFT is approved for this contract to manage
		require(getApproved(tokenId) == address(this), "NFT not approved for staking");
		require(isColorValid(tokenId), "User cannot stack this color");
		uint8 _pieceType = getPieceType(tokenId);
		bool hasValidClub = false;
		for (uint i = 7; i < pieceDetails[_pieceType].clubRequirement; i++) {
			if (pieceDetails[_pieceType].palindromeClubRequirement) {
				if (i == pieceDetails[_pieceType].clubRequirement) {
					if (isClub(node, i) && isPalindrome(node)) {
						hasValidClub = true;
						break;
					}
				}
			}
			if (isClub(node, i)) {
				hasValidClub = true;
				break;
			}
		}
		require(hasValidClub, "Doesn't have a valid club name");
		idToIndex[_pieceType][tokenId] = idStacked[_pieceType].length;
		idStacked[_pieceType].push(tokenId);
		totalStaked[_pieceType] += 1;
		// Marquer l'epoch de la personne qui stacke dans les cagnottes
		userStaked[node][_pieceType] += 1;
		userSharePerToken[node][_pieceType] = totalSharePerToken[_pieceType][epoch];
		updateEpoch();

		if (idStacked[_pieceType].length == 1) {
			// If it's the first piece of this type
			if (_pieceType != 5 && _pieceType != 0) {
				pieceDetails[5].percentage -= pieceDetails[_pieceType].percentage;

				// TODO gérer le cas ou aucun pion ou aucun roi n'est stacké
			}
		}

		// Transfer the NFT to this contract
		safeTransferFrom(msg.sender, address(this), tokenId);
		isStaked[tokenId] = true;
		userStackedNFTs[msg.sender].push(tokenId);
		// Set the token ID for the ENS node
		nodeOfTokenId[tokenId] = node;

		// Set the NFT as the avatar for the ENS node
		textResolver.setText(node, "avatar", string(abi.encodePacked("eip721:", address(this), "/", tokenId)));
	}

	function _unstake(bytes32 node, uint256 tokenId) public {
		// Ensure the function caller owns the ENS node
		require(isStaked[tokenId], "Token is not stacked yet");
		require(nodeOfTokenId[tokenId] == node, "ENS name must match the token stacked");
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");

		// Ensure the NFT is managed by this contract
		require(ownerOf(tokenId) == address(this), "NFT not staked");

		// Transfer the NFT back to the function caller
		safeTransferFrom(address(this), msg.sender, tokenId);
		uint8 _pieceType = getPieceType(tokenId);
		uint256 index = idToIndex[_pieceType][tokenId];
		uint256 lastId = idStacked[_pieceType][idStacked[_pieceType].length - 1];

		idStacked[_pieceType][index] = lastId;
		idStacked[_pieceType].pop();
		idToIndex[_pieceType][lastId] = index;
		delete idToIndex[_pieceType][tokenId];
		uint256 indexNFT = findIndexOfStackedNFT(msg.sender, tokenId);
		userStackedNFTs[msg.sender][indexNFT] = userStackedNFTs[msg.sender][userStackedNFTs[msg.sender].length - 1];
		userStackedNFTs[msg.sender].pop();
		isStaked[tokenId] = false;
		nodeOfTokenId[tokenId] = 0x0;

		// distribute rewards
		uint256 userReward = (totalSharePerToken[_pieceType][epoch] - userSharePerToken[node][_pieceType]) * userStaked[node][_pieceType];
		// transfer reward to user
		_safeTransfer(address(this), msg.sender, userReward, ""); // To user or to node ?
		// update user and total stake count
		totalStaked[_pieceType] -= 1;
		userStaked[node][_pieceType] -= 1;
		userSharePerToken[node][_pieceType] = totalSharePerToken[_pieceType][epoch]; // par sureté mais redondant

		// Remove the token ID for the ENS node
		delete nodeOfTokenId[tokenId];

		// Remove the NFT as the avatar for the ENS node
		textResolver.setText(node, "avatar", "");
	}

	function isColorValid(uint256 tokenId) private view returns (bool) {
		return (tokenId % 2 == 0 && userColor[msg.sender] == 1) || (tokenId % 2 != 0 && userColor[msg.sender] == 2);
	}

	function isPalindrome(bytes32 name) public pure returns (bool) {
		bytes32 b = name;
		uint start = 0;
		uint end = b.length - 4;
		while (start < end) {
			if (b[start] < 0x30 || b[start] > 0x39) return false; // ASCII values for '0' and '9'
			if (b[end] < 0x30 || b[end] > 0x39) return false; // ASCII values for '0' and '9'
			if (b[start] != b[end]) return false; // Checking palindrome
			start++;
			end--;
		}
		return true;
	}

	function getPieceType(uint256 nftId) public pure returns (uint8) {
		require(nftId < MAX_NFT_SUPPLY, "NFT ID out of range");
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

		// potentielle faille
	}

	// Let user choose the white or black color
	function chooseColor(uint8 _color) public {
		require(_color == 1 || _color == 2, "Invalid color");
		require(userColor[msg.sender] == 0, "Color already chosen");
		userColor[msg.sender] = _color;
	}

	function findIndexOfStackedNFT(address user, uint256 tokenId) private view returns (uint256) {
		for (uint256 i = 0; i < userStackedNFTs[user].length; i++) {
			if (userStackedNFTs[user][i] == tokenId) {
				return i;
			}
		}
		revert("NFT not found");
	}

	function findIndexOfOwnedNFT(address user, uint256 tokenId) private view returns (uint256) {
		for (uint256 i = 0; i < userStackedNFTs[user].length; i++) {
			if (userStackedNFTs[user][i] == tokenId) {
				return i;
			}
		}
		revert("NFT not found");
	}

	function isClub(bytes32 name, uint length) public pure returns (bool) {
		bytes32 b = name;
		if (b.length != length) return false;

		// Check if the first part is a number
		for (uint i = 0; i < b.length - 4; i++) {
			if (b[i] < 0x30 || b[i] > 0x39) return false;
		}

		// Check if the last part is ".eth"
		if (
			b[b.length - 4] != 0x2e || // ASCII value for '.'
			b[b.length - 3] != 0x65 || // ASCII value for 'e'
			b[b.length - 2] != 0x74 || // ASCII value for 't'
			b[b.length - 1] != 0x68 // ASCII value for 'h'
		) return false;

		return true;
	}

	function hasClubStacked(address user, uint lenght) private view returns (bool) {
		for (uint256 i = 0; i < userStackedNFTs[user].length; i++) {
			uint256 tokenId = userStackedNFTs[user][i];
			if (isClub(nodeOfTokenId[tokenId], lenght)) {
				return true;
			}
		}
		return false;
	}

	function revealKingHand(uint256 tokenId) public payable returns (bool) {
		require(msg.value > 200000000000000000); // reveal price fixed at 0.2 eth
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		require(getPieceType(tokenId) == 5, "Token must be a Pawn");
		// require(isStaked[tokenId] == false, "Token must be unstack");
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

	// Laquelle des deux fonctions utiliser ? Et reverser a la cagnotte du nft ou directement transfer au holder?
	function distributeKingAuction() private {
		uint256 pieceShare = kingHandsPrize / kingHands.length;
		for (uint256 i = 0; i < kingHands.length; i++) {
			tokenBalance[kingHands[i]] += pieceShare;
		}
	}

	function claimKingHand(uint256 tokenId) public {
		require(totalMinted == MAX_NFT_SUPPLY && currentSupply == 999, "Collection not ended yet");

		// Ensure the function caller owns the NFT
		require(ownerOf(tokenId) == msg.sender, "Not owner of NFT");
		uint256 i = 0;
		bool isKingHand = false;
		for (i; i < kingHands.length; i++) {
			if (tokenId == kingHands[i]) {
				isKingHand = true;
				break;
			}
		}
		require(isKingHand, "Token must be a King's Hand");
		uint256 pieceShare = kingHandsPrize / kingHands.length;
		tokenBalance[tokenId] += pieceShare;
		kingHands[i] = kingHands[kingHands.length - 1];
		kingHands.pop();
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
		require(isClub(nodeOfTokenId[tokenId], 7) || (isClub(nodeOfTokenId[tokenId], 8) && isPalindrome(nodeOfTokenId[tokenId])), "Only 999Club and 10kClub Palindrome can claim Prize");
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
		uint256 balance = tokenBalance[tokenId];
		tokenBalance[tokenId] = 0;
		payable(msg.sender).transfer(balance);
	}

	function updateEpoch() public onlyOwner {
		epoch += 1;
	}

	function getUserOwnedNFTs(address user) public view returns(uint256[] memory){
		return userOwnedNFTs[user];
	}

	function getUserColor(address user) public view returns(uint8){
		return userColor[user];
	}

	// a terminer
	// function auctionEnded(uint256 _price, address _newOwner, uint256 _tokenId) public {
	// 	kingHandsPrize += _price;
	// }
}

// notes : pourquoi vendre sur le marché secondaire du contrat plutot que sur une marketplace type opensea si la cagnotte personnelle
// a claim est trop faible comparé aux taxes ?

// le cas ou tous les nfts sont mint puis on burn jusqu a 999
// le cas ou il y a moins de 999 nft et ont mint tout jusqu'a atteindre 999 nft
