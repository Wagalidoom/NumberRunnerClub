const NumberRunnerClub = artifacts.require("NumberRunnerClub");
const ethers = require("ethers");


module.exports = async function(callback) {
  try {
    console.log(ethers.version)
    const instance = await NumberRunnerClub.deployed();
    await instance.chooseColor(1, {from: "0xaa174310699b475FeCA57060Dc644EFb056FF877"})
    for (let i = 0; i < 5; i++) {
        const _Mint = await instance.mint(5,0, {from: "0xaa174310699b475FeCA57060Dc644EFb056FF877", value: web3.utils.toWei('0.21', 'ether')});
        console.log("Gas used MINT :", _Mint.receipt.gasUsed)
        id = _Mint.logs[0].args.tokenId.words[0]
        console.log(id)
        console.log(`Minted token ${id}`);
        await instance.approve("0x2b9a4aB7a36cc4514f7D2BE2B70A4065A8AC49E5", id)
        const _Stake = await instance.stack(web3.utils.asciiToHex("121.eth"), id);
        console.log("Gas used STAKING :", _Stake.receipt.gasUsed)
        // console.log(_Stake.logs[0].args)
        console.log(`Staked token ${id}`);
        console.log("Rewards du 362 : ", (await instance.getReward(362)).toString());
      
    }

    let size = await instance.getShareTypeAccumulatorSize();
    for (let i = 0; i < size[0]; i++) {
        for (let j = 0; j < size[1]; j++) {
            let element = await instance.getShareTypeAccumulator(i, j);
            console.log(`totalSharePerToken[${i}][${j}] = ${element}`);
        }
    }


    callback();
  } catch (error) {
    console.error(error);
    callback(error);
  }
};