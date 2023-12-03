# Smart Contract Error Codes

This document lists the error codes and their descriptions for the `KingAuction` and `NumberRunnerClub` smart contracts.

## KingAuction.sol

### KA01 - King's Hands already generated
This error code is returned when the King's Hands have already been generated.

### KA02 - Wrong request ID
This error code is returned when the request ID does not match the expected ID.

## NumberRunnerClub.sol

### NRC01 - Collection ended
This error code is returned when the collection has ended.

### NRC02 - Collection not ended
This error code is returned when the collection has not yet ended.

### NRC03 - Color not chosen
This error code is returned when the user has not chosen yet.

### NRC04 - Max supply for color reached
This error code is returned when the maximum number of tokens for that color has been reached.

### NRC05 - Value lower than 0.05 eth
This error code is returned when the user does not send enough ether.

### NRC06 - Not owner of ENS name
This error code is returned when the user does not own the ENS name.

### NRC07 - Not owner of NFT
This error code is returned when the user does not own the NRC token.

### NRC08 - ENS name not in the club
This error code is returned when the ENS name used does not be part of the valid club.

### NRC09 - NRC not stacked
This error code is returned when the NRC token is not stacked in the contract.

### NRC10 - Not enough balance in contract
This error code is returned when the contract don't have enough balance to pay the user.

### NRC11 - Cannot burn the king
This error code is returned when the user try to burn a King token.

