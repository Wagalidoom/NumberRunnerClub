// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// These files are dynamically created at test time
import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/NumberRunnerClub.sol";

contract TestNumberRunnerClub {

  function testInitialBalanceUsingDeployedContract() public {
    NumberRunnerClub nrc = NumberRunnerClub(DeployedAddresses.NumberRunnerClub());

    uint expected = 10000;

    // Assert.equal(meta.getBalance(tx.origin), expected, "Owner should have 10000 MetaCoin initially");
  }

}