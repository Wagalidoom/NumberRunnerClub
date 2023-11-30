const NumberRunnerClubGoerli = artifacts.require("NumberRunnerClubGoerli");
// const test = artifacts.require("ExponentialFunction");

module.exports = function (deployer) {
    deployer.deploy(NumberRunnerClubGoerli);
    // deployer.deploy(test);
};