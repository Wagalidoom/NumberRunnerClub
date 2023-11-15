const NumberRunnerClubGoerli = artifacts.require("NumberRunnerClubGoerli");
const ethers = require("ethers");
const namehash = require('eth-ens-namehash');
const BigNumber = require('bignumber.js');

const userA = "0x3BDF3e474EB74ac40106A20Bc4901A1919356891";
const userB = "0x244614a322ADc2579DEE5772fa436B646dC1a528";
const contractAddress = "0x6D36970F4202F3cC6b141AB49BD68B1e8719726B";

const chooseColor = async (instance, colorIndex, fromAddress) => {
    await instance.chooseColor(colorIndex, { from: fromAddress });
    console.log(`Chose color ${colorIndex}`);
};

const mintToken = async (instance, fromAddress, value) => {
    const _Mint = await instance.mint(5, 0, { from: fromAddress, value });
    const id = _Mint.logs[0].args.tokenId.words[0]
    console.log(`Minted token ${id}`);
    return id;
};

const multiMint = async (instance, _n, fromAddress, value) => {
    const _Mint = await instance.multiMint(_n, { from: fromAddress, value });
    // const id = _Mint.logs[0].args.tokenId.words[0]
    console.log(`Minted token ${_Mint}`);
    // return id;
};

const killTokens = async (instance, tokenIds, fromAddress, value) => {
    await instance.multiKill(tokenIds, { from: fromAddress, value });
    console.log(`Kill tokens ${tokenIds}`);
};

const burnToken = async (instance, tokenId, fromAddress) => {
    await instance.burn(tokenId, { from: fromAddress });
    console.log(`Burned token ${tokenId}`);
};


const approveToken = async (instance, tokenId, toAddress, fromAddress) => {
    await instance.approve(toAddress, tokenId, { from: fromAddress });
    console.log(`Approved token ${tokenId}`);
};

const stackToken = async (instance, domain, tokenId, fromAddress) => {
    console.log(web3.utils.asciiToHex(domain), tokenId);
    const _Stack = await instance.stack(domain, tokenId, { from: fromAddress });
    console.log(`Stacked token ${JSON.stringify(_Stack, null, 2)}`);
};

const unstackToken = async (instance, tokenId, fromAddress) => {
    await instance.unstack(tokenId, { from: fromAddress });
    console.log(`Unstacked token ${tokenId}`);
};

const listToken = async (instance, tokenId, price, fromAddress) => {
    await instance.listNFT(tokenId, price, { from: fromAddress });
    console.log(`Listed token ${tokenId}`);
};

const getPieceType = (nftId) => {
    if (nftId >= 0 && nftId < 2) {
        return 0;
    } else if (nftId >= 2 && nftId < 12) {
        return 1;
    } else if (nftId >= 12 && nftId < 62) {
        return 2;
    } else if (nftId >= 62 && nftId < 162) {
        return 3;
    } else if (nftId >= 162 && nftId < 362) {
        return 4;
    } else {
        return 5;
    }
};

module.exports = async function (callback) {
    try {
        console.log(ethers.version)
        const instance = await NumberRunnerClubGoerli.deployed();
        const balance = await web3.eth.getBalance(contractAddress);
        console.log("Deployed ! Contract balance : ", balance);

        
        // await chooseColor(instance, 1, userA);
        await chooseColor(instance, 2, userB);
        // const tokenId1 = await mintToken(instance, userA, 10000000000000);
        // await stackToken(instance, "764", 362, userA);
        // const tokenId2 = await mintToken(instance, userA, 20000000000000);
        const tokenId1 = await multiMint(instance, 1, userB, 0);
        // await listToken(instance, tokenId1, web3.utils.toWei('10', 'ether'), userA);
        // await burnToken(instance, "370", userA);
        // await stackToken(instance, "17921.eth", tokenId1, userA);

        // for (let i=0; i<10; i++) { 
        //   const mintBlanc = await mintToken(instance, userA, 20000000000000);
        //   const mintNoir = await mintToken(instance, userB, 20000000000000);
        // }

        // await killTokens(instance, [tokenId1, tokenId2], userB, 80000000000000);


        callback();
    } catch (error) {
        console.error(error);
        callback(error);
    }
};
