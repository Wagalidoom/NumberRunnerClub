const NumberRunnerClubGoerli = artifacts.require("NumberRunnerClubGoerli");
// const test = artifacts.require("ExponentialFunction");

module.exports = function (deployer) {
    deployer.deploy(NumberRunnerClubGoerli, "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85", "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e", "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e");
    // deployer.deploy(test);
};