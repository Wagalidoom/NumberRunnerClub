// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import "@ensdomains/ens-contracts/contracts/resolvers/profiles/TextResolver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NumberRunnerClub is ERC721URIStorage {
    using Counters for Counters.Counter;
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
        uint256 currentSupply;
        uint256 totalMinted;
        uint256 percentage;
        uint256 burnTax;
    }

    Piece[] public collection;
    uint256 public constant MAX_NFT_SUPPLY = 10000;

    Counters.Counter private _tokenIds;

    ENS ens;
    TextResolver textResolver;

    // Mapping from ENS node to token ID
    mapping(bytes32 => uint256) public tokenIdOfNode;

    // Mapping to store the balance of each Piece type
    mapping(Piece => uint256) public pieceBalance;

    mapping(Piece => PieceDetails) public pieceDetails;

    mapping(address => uint256) private holderBalance;

    constructor(
        address _ens,
        address _resolver
    ) ERC721("NumberRunnerClub", "NRC") {
        pieceDetails[Piece.King] = PieceDetails(2, 0, 0, 350, 0);
        pieceDetails[Piece.Queen] = PieceDetails(10, 0, 0, 225, 35);
        pieceDetails[Piece.Rook] = PieceDetails(50, 0, 0, 150, 35);
        pieceDetails[Piece.Knight] = PieceDetails(100, 0, 0, 125, 30);
        pieceDetails[Piece.Bishop] = PieceDetails(200, 0, 0, 100, 25);
        pieceDetails[Piece.Pawn] = PieceDetails(9638, 0, 0, 650, 25);
        ens = ENS(_ens);
        textResolver = TextResolver(_resolver);
    }

    function mint(
        Piece _piece,
        string memory tokenURI
    ) public payable returns (uint256) {
        require(msg.value > 200000000000000000);
        uint256 newItemId = _tokenIds.current();
        require(newItemId < MAX_NFT_SUPPLY, "Maximum NFTs reached.");
        require(
            pieceDetails[_piece].currentSupply < pieceDetails[_piece].maxSupply,
            "Max supply for this piece type reached"
        );
        collection.push(_piece);
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);
        pieceDetails[_piece].currentSupply++;
        pieceDetails[_piece].totalMinted++;

        if (pieceDetails[_piece].currentSupply == 1) {
            // If it's the first piece of this type
            if (_piece != Piece.Pawn && _piece != Piece.King) {
                pieceDetails[Piece.Pawn].percentage -= pieceDetails[_piece]
                    .percentage;
            }
        }

        // Add the transaction fee to the piece's balance
        for (uint8 i = 0; i < 6; i++) {
            PieceDetails memory piece = pieceDetails[Piece(i)];
            if (piece.currentSupply > 0) {
                uint256 pieceShare = (100000000000000 * piece.percentage);
                pieceBalance[Piece(i)] += pieceShare;
            }
        }
        _tokenIds.increment();
        return newItemId;
    }

    function sellNFT(uint256 tokenId, address buyer) public {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        uint256 taxAmount = (holderBalance[_msgSender()] * 16) / 100;
        holderBalance[_msgSender()] -= taxAmount;
        for (uint8 i = 0; i < 6; i++) {
            PieceDetails memory pieceType = pieceDetails[Piece(i)];
            if (pieceType.currentSupply > 0) {
                uint256 pieceShare = (taxAmount * pieceType.percentage);
                pieceBalance[Piece(i)] += pieceShare;
            }
        }
        safeTransferFrom(_msgSender(), buyer, tokenId);
    }

    function burnNFT(uint256 tokenId) public {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: burn caller is not owner nor approved"
        );
        Piece piece = collection[tokenId];
        require(piece != Piece.King, "Cannot burn the King");
        uint256 taxAmount = (holderBalance[_msgSender()] *
            pieceDetails[piece].burnTax) / 100;
        holderBalance[_msgSender()] -= taxAmount;
        for (uint8 i = 0; i < 6; i++) {
            PieceDetails memory pieceType = pieceDetails[Piece(i)];
            if (pieceType.currentSupply > 0) {
                uint256 pieceShare = (taxAmount * pieceType.percentage);
                pieceBalance[Piece(i)] += pieceShare;
            }
        }
        _burn(tokenId);
        pieceDetails[piece].currentSupply--;
    }

    function stake(
        bytes32 node,
        address nftContract,
        uint256 tokenId
    ) external {
        // Ensure the function caller owns the ENS node
        require(ens.owner(node) == msg.sender, "Not owner of ENS node");

        // Ensure the function caller owns the NFT
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not owner of NFT"
        );

        // Ensure the NFT is approved for this contract to manage
        require(
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "NFT not approved for staking"
        );

        // Transfer the NFT to this contract
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        // Set the token ID for the ENS node
        tokenIdOfNode[node] = tokenId;

        // Set the NFT as the avatar for the ENS node
        textResolver.setText(
            node,
            "avatar",
            string(abi.encodePacked("eip721:", nftContract, "/", tokenId))
        );
    }

    function unstake(bytes32 node, address nftContract) external {
        // Ensure the function caller owns the ENS node
        require(ens.owner(node) == msg.sender, "Not owner of ENS node");

        // Ensure the NFT is managed by this contract
        require(
            IERC721(nftContract).ownerOf(tokenIdOfNode[node]) == address(this),
            "NFT not staked"
        );

        // Transfer the NFT back to the function caller
        IERC721(nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            tokenIdOfNode[node]
        );

        // Remove the token ID for the ENS node
        delete tokenIdOfNode[node];

        // Remove the NFT as the avatar for the ENS node
        textResolver.setText(node, "avatar", "");
    }
}
