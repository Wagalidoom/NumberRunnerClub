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

	struct PieceDetails {
		uint256 maxSupply;
		uint256 totalMinted;
		uint256 blackMinted;
		uint256 whiteMinted;
		uint256 percentage;
		uint256 burnTax;
		uint256 startingId;
	}

	Piece[] public collection;
	uint256 public constant MAX_NFT_SUPPLY = 10000;

	ENS ens;
	TextResolver textResolver;

	// Mapping from ENS node to token ID
	mapping(bytes32 => uint256) public tokenIdOfNode;

	mapping(Piece => PieceDetails) public pieceDetails;

	mapping(uint256 => uint256) private holderBalance;

	mapping(Piece => uint256[]) private idStacked;
	mapping(Piece => mapping(uint256 => uint256)) private idToIndex;

	// Mapping of user address to chosen color
	mapping(address => uint256) public userColor;

	constructor(address _ens, address _resolver) ERC721("NumberRunnerClub", "NRC") {
		pieceDetails[Piece.King] = PieceDetails(2, 0, 0, 0, 350, 0, 0);
		pieceDetails[Piece.Queen] = PieceDetails(10, 0, 0, 0, 225, 35, 2);
		pieceDetails[Piece.Rook] = PieceDetails(50, 0, 0, 0, 150, 35, 12);
		pieceDetails[Piece.Knight] = PieceDetails(100, 0, 0, 0, 125, 30, 62);
		pieceDetails[Piece.Bishop] = PieceDetails(200, 0, 0, 0, 100, 25, 162);
		pieceDetails[Piece.Pawn] = PieceDetails(9638, 0, 0, 0, 650, 25, 362);
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

		uint256 newItemId = color == 1 ? pieceDetails[_piece].startingId + 2 * pieceDetails[_piece].blackMinted : pieceDetails[_piece].startingId + 1 + 2 * pieceDetails[_piece].blackMinted;

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
	}

	function _stake(bytes32 node, address nftContract, uint256 tokenId) private {
		// Ensure the function caller owns the ENS node
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");

		// Ensure the function caller owns the NFT
		require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner of NFT");

		// Ensure the NFT is approved for this contract to manage
		require(IERC721(nftContract).getApproved(tokenId) == address(this), "NFT not approved for staking");
		Piece pieceType = getPieceType(tokenId);
		idToIndex[pieceType][tokenId] = idStacked[pieceType].length;
		idStacked[pieceType].push(tokenId);

		if (idStacked[pieceType].length == 1) {
			// If it's the first piece of this type
			if (pieceType != Piece.Pawn && pieceType != Piece.King) {
				pieceDetails[Piece.Pawn].percentage -= pieceDetails[pieceType].percentage;
			}
		}

		// Transfer the NFT to this contract
		IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

		// Set the token ID for the ENS node
		tokenIdOfNode[node] = tokenId;

		// Set the NFT as the avatar for the ENS node
		textResolver.setText(node, "avatar", string(abi.encodePacked("eip721:", nftContract, "/", tokenId)));
	}

	function _unstake(bytes32 node, address nftContract, uint256 tokenId) private {
		// Ensure the function caller owns the ENS node
		require(ens.owner(node) == msg.sender, "Not owner of ENS node");

		// Ensure the NFT is managed by this contract
		require(IERC721(nftContract).ownerOf(tokenIdOfNode[node]) == address(this), "NFT not staked");

		Piece pieceType = getPieceType(tokenId);
		uint256 index = idToIndex[pieceType][tokenId];
		uint256 lastId = idStacked[pieceType][idStacked[pieceType].length - 1];

		idStacked[pieceType][index] = lastId;
		idStacked[pieceType].pop();
		idToIndex[pieceType][lastId] = index;
		delete idToIndex[pieceType][tokenId];

		// Transfer the NFT back to the function caller
		IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenIdOfNode[node]);

		// Remove the token ID for the ENS node
		delete tokenIdOfNode[node];

		// Remove the NFT as the avatar for the ENS node
		textResolver.setText(node, "avatar", "");
	}

    // rajouter require sur l'id du token s'il correspond bien au type de piece et passer le type en attribut de la fonction mint?
	function stakePawn(bytes32 node, address nftContract, uint256 tokenId) external {
		require(is999Club(node) || is10kClub(node) || is100kClub(node));
		require(isColorValid(tokenId), "User cannot stack this color");
		_stake(node, nftContract, tokenId);
	}

	function stakeBishop(bytes32 node, address nftContract, uint256 tokenId) external {
		require(is999Club(node) || is10kClub(node) || (is100kClub(node) && isPalindrome(node)));
		require(isColorValid(tokenId), "User cannot stack this color");
		_stake(node, nftContract, tokenId);
	}

    function stakeKnight(bytes32 node, address nftContract, uint256 tokenId) external {
		require(is999Club(node) || is10kClub(node));
		require(isColorValid(tokenId), "User cannot stack this color");
		_stake(node, nftContract, tokenId);
	}

    function stakeRook(bytes32 node, address nftContract, uint256 tokenId) external {
		require(is999Club(node) || (is10kClub(node) && isPalindrome(node)));
		require(isColorValid(tokenId), "User cannot stack this color");
		_stake(node, nftContract, tokenId);
	}

    function stakeQueen(bytes32 node, address nftContract, uint256 tokenId) external {
		require(is999Club(node));
		require(isColorValid(tokenId), "User cannot stack this color");
		_stake(node, nftContract, tokenId);
	}

    function stakeKing(bytes32 node, address nftContract, uint256 tokenId) external {
		require(is999Club(node) || is10kClub(node));
		require(isColorValid(tokenId), "User cannot stack this color");
		_stake(node, nftContract, tokenId);
	}

	function isColorValid(uint256 tokenId) private view returns (bool) {
		if (tokenId % 2 == 0) {
			if (userColor[msg.sender] == 1) {
				return true;
			}
		} else {
			if (userColor[msg.sender] == 2) {
				return true;
			}
		}
		return false;
	}

	function is999Club(bytes32 name) public pure returns (bool) {
		bytes32 b = name;
		if (b.length != 7) return false; // Length should be 7 to fit "123.eth"

		// Check if the first part is a number
		for (uint i = 0; i < 3; i++) {
			if (b[i] < 0x30 || b[i] > 0x39) return false; // ASCII values for '0' and '9'
		}

		// Check if the last part is ".eth"
		if (
			b[3] != 0x2e || // ASCII value for '.'
			b[4] != 0x65 || // ASCII value for 'e'
			b[5] != 0x74 || // ASCII value for 't'
			b[6] != 0x68 // ASCII value for 'h'
		) return false;

		return true;
	}

	function is10kClub(bytes32 name) public pure returns (bool) {
		bytes32 b = name;
		if (b.length != 8) return false; // Length should be 7 to fit "123.eth"

		// Check if the first part is a number
		for (uint i = 0; i < 4; i++) {
			if (b[i] < 0x30 || b[i] > 0x39) return false; // ASCII values for '0' and '9'
		}

		// Check if the last part is ".eth"
		if (
			b[4] != 0x2e || // ASCII value for '.'
			b[5] != 0x65 || // ASCII value for 'e'
			b[6] != 0x74 || // ASCII value for 't'
			b[7] != 0x68 // ASCII value for 'h'
		) return false;

		return true;
	}

	function is100kClub(bytes32 name) public pure returns (bool) {
		bytes32 b = name;
		if (b.length != 9) return false; // Length should be 7 to fit "123.eth"

		// Check if the first part is a number
		for (uint i = 0; i < 5; i++) {
			if (b[i] < 0x30 || b[i] > 0x39) return false; // ASCII values for '0' and '9'
		}

		// Check if the last part is ".eth"
		if (
			b[5] != 0x2e || // ASCII value for '.'
			b[6] != 0x65 || // ASCII value for 'e'
			b[7] != 0x74 || // ASCII value for 't'
			b[8] != 0x68 // ASCII value for 'h'
		) return false;

		return true;
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
}
