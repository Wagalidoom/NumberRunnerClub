const NumberRunnerClubGoerli = artifacts.require("NumberRunnerClubGoerli");
const ethers = require("ethers");
const namehash = require('eth-ens-namehash');
const BigNumber = require('bignumber.js');

const userA = "0xD553F496748F85195c1Ba7CfD7d5899f9D3c0EC3";
const userB = "0xA614E2f05F5561aF8119692076A499C707465cC7";
const contractAddress = "0xA1234A8aC6707162707bd2c09f62A06004d0967e";

const chooseColor = async (instance, colorIndex, fromAddress) => {
  await instance.chooseColor(colorIndex, { from: fromAddress });
  console.log(`Chose color ${colorIndex}`);
};

const fulfillRandomWord = async (instance, fromAddress) => {
    await instance.fulfillRandomWord( { from: fromAddress });
    console.log(`King Hands Generated`);
  };

const revealKingHand = async (instance, tokenId, fromAddress) => {
  const r = await instance.revealKingHand(tokenId, { from: fromAddress, value: 10000000000000 });
  const success = r.logs[0].args.success;
  console.log("Token", tokenId, " : ", success);
  return r;
};

const claimKingHand = async (instance, tokenId, fromAddress) => {
  const r = await instance.claimKingHand(tokenId, { from: fromAddress });
  console.log("Claimed King Hand for ", tokenId);
  return r;
};

const mintToken = async (instance, fromAddress, value) => {
  const _Mint = await instance.mint(5, 0, { from: fromAddress, value });
  const id = _Mint.logs[0].args.tokenId.words[0]
  console.log(`Minted token ${id}`);
  return id;
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
  await instance.stack(namehash.hash(domain), web3.utils.asciiToHex(domain), tokenId, { from: fromAddress });
  console.log(`Stacked token ${tokenId}`);
};

const unstackToken = async (instance, tokenId, fromAddress) => {
  await instance.unstack(tokenId, { from: fromAddress });
  console.log(`Unstacked token ${tokenId}`);
};

const listToken = async (instance, tokenId, price, fromAddress) => {
  await instance.listNFT(tokenId, price, { from: fromAddress });
  console.log(`Listed token ${tokenId}`);
};

const buyToken = async (instance, tokenId, fromAddress, value) => {
  await instance.buyNFT(tokenId, { from: fromAddress, value: value });
  console.log(`Bought token ${tokenId}`);
};

const buyKing = async (instance, color, amountIn, fromAddress) => {
  let res = await instance.buyKing(color, { from: fromAddress, value:amountIn });
  console.log(`Bought King ${res}`);
  return res
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

const getUnclaimedRewards = async (instance, tokenId) => {
  const unclaimedRewards = await instance.unclaimedRewards(tokenId);
  const nftShares = await instance.getNftShares(tokenId);

  const pieceType = getPieceType(tokenId);
  const size = await instance.getShareTypeAccumulatorSize();
  const [rows, cols] = [size[0].toNumber(), size[1].toNumber()];

  // Now we only fetch the last value of shareTypeAccumulator for the relevant type
  const lastValue = await instance.getShareTypeAccumulator(pieceType, cols-1);
  console.log(unclaimedRewards.toNumber(), lastValue.toNumber(), nftShares.toNumber())
  const totalRewards = unclaimedRewards.toNumber() + lastValue.toNumber() - nftShares.toNumber();
  console.log(`Total rewards for token ${tokenId}: ${totalRewards}`);
};

const displayShareTypeAccumulator = async (instance) => {
  // get size of shareTypeAccumulator
  const size = await instance.getShareTypeAccumulatorSize();
  const [rows, cols] = [size[0].toNumber(), size[1].toNumber()];

  // Define token types
  const tokenTypes = ["King", "Queen", "Rook", "Knight", "Bishop", "Pawn"];

  // Header
  console.log("Epoch | Share King | Share Queen | Share Rook | Share Knight | Share Bishop | Share Pawn");

  // iterate over each column (epoch)
  for(let col = 0; col < cols; col++) {
    let epochInfo = `Epoch ${col} | `;

    // iterate over each type
    for(let type = 0; type <= 5; type++) {
      const value = await instance.getShareTypeAccumulator(type, col);
      epochInfo += `Share ${tokenTypes[type]}: ${value} | `;
    }

    // Print info of the epoch
    console.log(epochInfo);
  }
};




module.exports = async function(callback) {
  try {
    console.log(ethers.version)
    const instance = await NumberRunnerClubGoerli.deployed();
    console.log(instance);
    // const balance = await web3.eth.getBalance(contractAddress);
    // console.log("Deployed ! Contract balance : ",balance)
    // await displayShareTypeAccumulator(instance);
    // await fulfillRandomWord(instance, userA)
    // await chooseColor(instance, 1, userA);
    // await chooseColor(instance, 2, userB);
    // const tokenId = await mintToken(instance, userA, 20000000000000);;
    // console.log(kingId)

    // for (let i=0; i<500; i++) {
    //   const mintBlanc = await mintToken(instance, userA, 20000000000000);
    //   const mintNoir = await mintToken(instance, userB, 20000000000000);
    //   await revealKingHand(instance, mintBlanc, userA);
    //   await revealKingHand(instance, mintNoir, userB);
    // }
    // const initialBalanceUserB = await web3.eth.getBalance(userB);
    // console.log("Balance of userB before claiming king hand: ", initialBalanceUserB);
    // const balance1 = await web3.eth.getBalance(contractAddress);
    // console.log("Deployed ! Contract balance BEFORE: ",balance1)
    // await claimKingHand(instance, 1217, userB);
    // const finalBalanceUserB = await web3.eth.getBalance(userB);
    // console.log("Balance of userB after claiming king hand: ", finalBalanceUserB);
    // const balance2 = await web3.eth.getBalance(contractAddress);
    // console.log("Contract balance after claiming king hand ",balance2)
    callback();
  } catch (error) {
    console.error(error);
    callback(error);
  }
};
