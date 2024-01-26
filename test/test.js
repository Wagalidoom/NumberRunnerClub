const NumberRunnerClub = artifacts.require("NumberRunnerClub");
const ethers = require("ethers");
const namehash = require('eth-ens-namehash');
const BigNumber = require('bignumber.js');

const userA = "0x9106D192e10AAdd5288C4f264E1F3988aD58dCAb";

const getCurrentPrice = async (instance, fromAddress) => {
    const r = await instance.getCurrentPrice({ from: fromAddress });
    console.log(r);
};


module.exports = async function (callback) {
    try {
        const instance = await NumberRunnerClub.deployed();
        await getCurrentPrice(instance, userA);


        callback();
    } catch (error) {
        console.error(error);
        callback(error);
    }
};
