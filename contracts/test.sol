// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "abdk-libraries-solidity/ABDKMath64x64.sol";

contract ExponentialFunction {
    using ABDKMath64x64 for int128;

    function calculateFunction(uint256 timestamp) public pure returns (int128) {
        int128 negOneThird = ABDKMath64x64.divi(-1, 3);
        int128 one = ABDKMath64x64.fromUInt(1);

        // Convert timestamp (in seconds) to days
        int128 _days = ABDKMath64x64.divu(timestamp, 60 * 60 * 24);
        
        // Convert days to 64.64 fixed point number
        int128 x64x64 = ABDKMath64x64.fromUInt(_days.toUInt());

        int128 innerCalculation = ABDKMath64x64.add(ABDKMath64x64.mul(negOneThird, x64x64), one);

        int128 result = ABDKMath64x64.exp_2(innerCalculation);

        return result;
    }
}
