const NumberRunnerClub = artifacts.require("NumberRunnerClub");
// const test = artifacts.require("ExponentialFunction");

module.exports = function(deployer) {
  deployer.deploy(NumberRunnerClub, "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e", "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e", "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e");
  // deployer.deploy(test);
};