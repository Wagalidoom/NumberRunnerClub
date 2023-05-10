pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NumberRunnerClub is ERC721 {
    using Counters for Counters.Counter;
    enum Piece {
        King,
        Queen,
        Rook,
        Knight,
        Bishop,
        Pawn
    }

    Piece[] public collection;
    uint256 public constant MAX_NFT_SUPPLY = 10000;
    uint256 public constant MAX_KING_SUPPLY = 2;
    uint256 public constant MAX_QUEEN_SUPPLY = 10;
    uint256 public constant MAX_ROOK_SUPPLY = 50;
    uint256 public constant MAX_KNIGHT_SUPPLY = 100;
    uint256 public constant MAX_BISHOP_SUPPLY = 200;

    Counters.Counter private _tokenIds;
    Counters.Counter private _tokenIds;
    Counters.Counter private _kingCounter;
    Counters.Counter private _queenCounter;
    Counters.Counter private _rookCounter;
    Counters.Counter private _knightCounter;
    Counters.Counter private _bishopCounter;

    constructor() ERC721("NumberRunnerClub", "NRC") {}

    function mint(Piece _piece, string memory tokenURI)
        public
        returns (uint256)
    {
        uint256 newItemId = _tokenIds.current();
        require(newItemId < MAX_NFT_SUPPLY, "Maximum NFTs reached.");
        collection.push(_piece);
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);
        _tokenIds.increment();
        return newItemId;
    }
}
