// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import "@ensdomains/ens-contracts/contracts/resolvers/profiles/TextResolver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract NumberRunnerClub is ERC721URIStorage {
	enum Piece {
		King,
		Queen,
		Rook,
		Knight,
		Bishop,
		Pawn
	}

	// Intégrer toutes les conditions de stack/mint dans PieceDetails pour avoir une seule fonction de mint et une seule de stack

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

	Piece[] public collection;
	uint256 public constant MAX_NFT_SUPPLY = 10000;

	ENS ens;
	TextResolver textResolver;

	// Mapping from ENS node to token ID
	mapping(uint256 => bytes32) public nodeOfTokenId;

	mapping(Piece => PieceDetails) public pieceDetails;

	mapping(uint256 => uint256) private holderBalance;

	mapping(Piece => uint256[]) private idStacked;
	mapping(Piece => mapping(uint256 => uint256)) private idToIndex;

	// Mapping of user address to chosen color
	mapping(address => uint256) public userColor;

	mapping(address => uint256) private burnedCount;
	mapping(address => uint256) private burnedCounterCount;
	mapping(address => uint256[]) public userStackedNFTs;
	mapping(uint256 => bool) public isStaked;

	constructor(address _ens, address _resolver) ERC721("NumberRunnerClub", "NRC") {
		pieceDetails[Piece.King] = PieceDetails(2, 0, 0, 0, 350, 0, 0, 8, 0, 0, true);
		pieceDetails[Piece.Queen] = PieceDetails(10, 0, 0, 0, 225, 35, 2, 7, 15, 15, false);
		pieceDetails[Piece.Rook] = PieceDetails(50, 0, 0, 0, 150, 35, 12, 8, 15, 15, true);
		pieceDetails[Piece.Knight] = PieceDetails(100, 0, 0, 0, 125, 30, 62, 8, 10, 10, false);
		pieceDetails[Piece.Bishop] = PieceDetails(200, 0, 0, 0, 100, 25, 162, 9, 10, 0, true);
		pieceDetails[Piece.Pawn] = PieceDetails(9638, 0, 0, 0, 650, 25, 362, 9, 0, 0, false);
		ens = ENS(_ens);
		textResolver = TextResolver(_resolver);
	}

	function mint(Piece _piece, string memory tokenURI, uint256 color) public payable returns (uint256) {
		require(msg.value > 200000000000000000);
		require(color == 1 || color == 2, "Color must be Black or White");
		require(userColor[msg.sender] == color, "Can't mint piece of different color");
		require(pieceDetails[_piece].totalMinted < pieceDetails[_piece].maxSupply, "Max supply for this piece type reached");
		require(pieceDetails[_piece].blackMinted < pieceDetails[_piece].maxSupply / 2, "Max supply for this color reached");
		require(pieceDetails[_piece].whiteMinted < pieceDetails[_piece].maxSupply / 2, "Max supply for this color reached");
		require(_piece != Piece.King, "Cannot mint the king");

		// enlever startingId de pieceDetails et fixer la valeur de départ dans les fonctions mintPawn, mintBishop, etc
		uint256 newItemId = color == 1 ? pieceDetails[_piece].startingId + 2 * pieceDetails[_piece].blackMinted : pieceDetails[_piece].startingId + 1 + 2 * pieceDetails[_piece].blackMinted;
		if (_piece != Piece.Pawn) {
			for (uint i = 7; i < pieceDetails[_piece].clubRequirement; i++) {
				require(hasClubStacked(msg.sender, i));
			}
			require(burnedCounterCount[msg.sender] > pieceDetails[_piece].burnRequirement);
			if (pieceDetails[_piece].opponentColorBurnRequirement > 0) {
				// If the piece requires burning tokens of the opponent's color
				require(burnedCounterCount[msg.sender] > pieceDetails[_piece].opponentColorBurnRequirement);
			}
		}

		collection.push(_piece);
		_mint(msg.sender, newItemId);
		_setTokenURI(newItemId, tokenURI);
		pieceDetails[_piece].totalMinted++;
		color == 1 ? pieceDetails[_piece].blackMinted++ : pieceDetails[_piece].whiteMinted++;

		// Add the transaction fee to the piece's balance
		for (uint8 i = 0; i < 6; i++) {
			PieceDetails memory piece = pieceDetails[Piece(i)];
			if (idStacked[Piece(i)].length > 0) {
				uint256 pieceShare = (100000000000000 * piece.percentage);
				distributePieceShare(Piece(i), pieceShare);
			}
		}
		return newItemId;
	}

	function sellNFT(uint256 tokenId, address buyer) public {
		require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
		// uint256 taxAmount = (holderBalance[_msgSender()] * 16) / 100;
		// holderBalance[_msgSender()] -= taxAmount;
		for (uint8 i = 0; i < 6; i++) {
			// PieceDetails memory pieceType = pieceDetails[Piece(i)];
			// if (pieceType.currentSupply > 0) {
			//     uint256 pieceShare = (taxAmount * pieceType.percentage);
			//     pieceBalance[Piece(i)] += pieceShare;
			// }
		}
		safeTransferFrom(_msgSender(), buyer, tokenId);
	}

	function burnNFT(uint256 tokenId) public {
		require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: burn caller is not owner nor approved");
		Piece piece = collection[tokenId];
		require(piece != Piece.King, "Cannot burn the King");
		uint256 taxAmount = (holderBalance[tokenId] * pieceDetails[piece].burnTax) / 100;
		holderBalance[tokenId] -= taxAmount;
		for (uint8 i = 0; i < 6; i++) {
			PieceDetails memory pieceType = pieceDetails[Piece(i)];
			if (idStacked[Piece(i)].length > 0) {
				uint256 pieceShare = (taxAmount * pieceType.percentage);
				distributePieceShare(Piece(i), pieceShare);
			}
		}
		_burn(tokenId);
		burnedCount[msg.sender]++;
		if (!isColorValid(tokenId)) {
			burnedCounterCount[msg.sender]++;
		}
	}

	function _stake(bytes32 node, address nftContract, uint256 tokenId) private {
		// Ensure the function caller owns the ENS node
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");

		// Ensure the function caller owns the NFT
		require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner of NFT");

		// Ensure the NFT is approved for this contract to manage
		require(IERC721(nftContract).getApproved(tokenId) == address(this), "NFT not approved for staking");
		require(!isStaked[tokenId], "This token is already staked");
		require(isColorValid(tokenId), "User cannot stack this color");
		Piece _piece = getPieceType(tokenId);
		for (uint i = 7; i < pieceDetails[_piece].clubRequirement; i++) {
			if (pieceDetails[_piece].palindromeClubRequirement) {
				if(i == pieceDetails[_piece].clubRequirement){
					require(isPalindrome(node));
				}
			}
			require(isClub(node, i));
		}
		idToIndex[_piece][tokenId] = idStacked[_piece].length;
		idStacked[_piece].push(tokenId);

		if (idStacked[_piece].length == 1) {
			// If it's the first piece of this type
			if (_piece != Piece.Pawn && _piece != Piece.King) {
				pieceDetails[Piece.Pawn].percentage -= pieceDetails[_piece].percentage;
			}
		}

		// Transfer the NFT to this contract
		IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
		isStaked[tokenId] = true;
		userStackedNFTs[msg.sender].push(tokenId);
		// Set the token ID for the ENS node
		nodeOfTokenId[tokenId] = node;

		// Set the NFT as the avatar for the ENS node
		textResolver.setText(node, "avatar", string(abi.encodePacked("eip721:", nftContract, "/", tokenId)));
	}

	function _unstake(bytes32 node, address nftContract, uint256 tokenId) private {
		// Ensure the function caller owns the ENS node
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");

		// Ensure the NFT is managed by this contract
		require(IERC721(nftContract).ownerOf(tokenId) == address(this), "NFT not staked");

		// Transfer the NFT back to the function caller
		IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
		Piece pieceType = getPieceType(tokenId);
		uint256 index = idToIndex[pieceType][tokenId];
		uint256 lastId = idStacked[pieceType][idStacked[pieceType].length - 1];

		idStacked[pieceType][index] = lastId;
		idStacked[pieceType].pop();
		idToIndex[pieceType][lastId] = index;
		delete idToIndex[pieceType][tokenId];
		uint256 indexNFT = findIndexOfNFT(msg.sender, tokenId);
		userStackedNFTs[msg.sender][indexNFT] = userStackedNFTs[msg.sender][userStackedNFTs[msg.sender].length - 1];
		userStackedNFTs[msg.sender].pop();
		isStaked[tokenId] = false;

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

	function getPieceType(uint256 nftId) private pure returns (Piece) {
		require(nftId < MAX_NFT_SUPPLY, "NFT ID out of range");
		if (nftId >= 0 && nftId < 2) {
			return Piece.King;
		} else if (nftId >= 2 && nftId < 12) {
			return Piece.Queen;
		} else if (nftId >= 12 && nftId < 62) {
			return Piece.Rook;
		} else if (nftId >= 62 && nftId < 162) {
			return Piece.Knight;
		} else if (nftId >= 162 && nftId < 362) {
			return Piece.Bishop;
		} else {
			return Piece.Pawn;
		}
	}

	function distributePieceShare(Piece pieceType, uint256 pieceShare) private {
		// regler le pb de distribution pour n'importe quelle couleur
		uint256[] storage stackedIds = idStacked[pieceType];
		uint256 numStacked = stackedIds.length;
		uint256 pieceSharePerNFT = pieceShare / numStacked;

		for (uint256 i = 0; i < numStacked; i++) {
			uint256 tokenId = stackedIds[i];
			holderBalance[tokenId] += pieceSharePerNFT;
		}
	}

	function chooseColor(uint256 _color) external {
		require(_color == 1 || _color == 2, "Invalid color");
		require(userColor[msg.sender] == 0, "Color already chosen");
		userColor[msg.sender] = _color;
	}

	function findIndexOfNFT(address user, uint256 tokenId) private view returns (uint256) {
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
}
