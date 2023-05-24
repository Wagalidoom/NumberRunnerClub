// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// These files are dynamically created at test time
import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/NumberRunnerClub.sol";

contract TestNumberRunnerClub {

//   function testInitialBalanceUsingDeployedContract() public {
//     NumberRunnerClub NRC = NumberRunnerClub(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e,
//     0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e, 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e, 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

//     uint expected = 10000;

//     Assert.equal(NRC.getBalance(tx.origin), expected, "Owner should have 10000 MetaCoin initially");
//   }

  function testInitialBalanceWithNewNRC() public {
    NumberRunnerClub NRC = new NumberRunnerClub(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e,
    0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e, 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e, 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

    uint expected = 10000;

    // Assert.equal(NRC.getBalance(tx.origin), expected, "Owner should have 10000 MetaCoin initially");
  }

}