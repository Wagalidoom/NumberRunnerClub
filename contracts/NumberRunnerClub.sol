// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

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
        uint256 percentage;
    }

    Piece[] public collection;
    uint256 public constant MAX_NFT_SUPPLY = 10000;

    Counters.Counter private _tokenIds;

    // Mapping to store the balance of each Piece type
    mapping(Piece => uint256) public pieceBalance;

    mapping(Piece => PieceDetails) public pieceDetails;

    constructor() ERC721("NumberRunnerClub", "NRC") {
        pieceDetails[Piece.King] = PieceDetails(2, 0, 350);
        pieceDetails[Piece.Queen] = PieceDetails(10, 0, 225);
        pieceDetails[Piece.Rook] = PieceDetails(50, 0, 150);
        pieceDetails[Piece.Knight] = PieceDetails(100, 0, 125);
        pieceDetails[Piece.Bishop] = PieceDetails(200, 0, 100);
        pieceDetails[Piece.Pawn] = PieceDetails(9638, 0, 650);
    }

    function mint(Piece _piece, string memory tokenURI)
        public
        payable
        returns (uint256)
    {
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

        if (pieceDetails[_piece].currentSupply == 1) {
            // If it's the first piece of this type
            if(_piece != Piece.Pawn && _piece != Piece.King){
                pieceDetails[Piece.Pawn].percentage -= pieceDetails[_piece].percentage;
            }
        }

        // Add the transaction fee to the piece's balance
        for (uint8 i = 0; i < 6; i++) {
            PieceDetails memory piece = pieceDetails[Piece(i)];
            if(piece.currentSupply > 0) {
                uint256 pieceShare = (100000000000000 * piece.percentage);
                pieceBalance[Piece(i)] += pieceShare;
            }
        }
        _tokenIds.increment();
        return newItemId;
    }
}
