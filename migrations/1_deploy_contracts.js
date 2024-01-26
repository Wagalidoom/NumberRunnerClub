const NumberRunnerClub = artifacts.require("NumberRunnerClub");
// const test = artifacts.require("ExponentialFunction");

module.exports = function (deployer) {
    deployer.deploy(NumberRunnerClub);
    // deployer.deploy(test);
};