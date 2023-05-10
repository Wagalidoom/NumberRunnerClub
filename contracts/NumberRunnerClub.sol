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

    Piece[] public collection;
    uint256 public constant MAX_NFT_SUPPLY = 10000;
    uint256 public constant MAX_KING_SUPPLY = 2;
    uint256 public constant MAX_QUEEN_SUPPLY = 10;
    uint256 public constant MAX_ROOK_SUPPLY = 50;
    uint256 public constant MAX_KNIGHT_SUPPLY = 100;
    uint256 public constant MAX_BISHOP_SUPPLY = 200;

    Counters.Counter private _tokenIds;
    Counters.Counter private _kingCounter;
    Counters.Counter private _queenCounter;
    Counters.Counter private _rookCounter;
    Counters.Counter private _knightCounter;
    Counters.Counter private _bishopCounter;

    // Mapping to store the balance of each Piece type
    mapping(Piece => uint256) public pieceBalance;

    constructor() ERC721("NumberRunnerClub", "NRC") {}

    function mint(Piece _piece, string memory tokenURI)
        public
        payable
        returns (uint256)
    {
        require(msg.value > 200000000000000000);
        uint256 newItemId = _tokenIds.current();
        require(newItemId < MAX_NFT_SUPPLY, "Maximum NFTs reached.");
        collection.push(_piece);
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);

        // Add the transaction fee to the piece's balance
        pieceBalance[_piece] += 100000000000000000;
        _tokenIds.increment();
        return newItemId;
    }
}
