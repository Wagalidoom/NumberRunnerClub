const NumberRunnerClub = artifacts.require("NumberRunnerClub");

module.exports = async function(callback) {
  try {
    const instance = await NumberRunnerClub.deployed();
    // await instance.chooseColor(1, {from: "0x892a8ae9356f6706a6c2a0d0431b66d7e4eca3d1"})
    for (let i = 0; i < 100; i++) {
        const _Mint = await instance.mint(5, {from: "0x892a8ae9356f6706a6c2a0d0431b66d7e4eca3d1", value: web3.utils.toWei('0.21', 'ether')});
        console.log("Gas used MINT :", _Mint.receipt.gasUsed)
        id = _Mint.logs[0].args.tokenId.words[0]
        console.log(id)
        console.log(`Minted token ${id}`);
        await instance.approve("0x9C163b47501670493E363ad855A99A6F5f282Dc0", id)
        const _Stake = await instance.stack(web3.utils.asciiToHex("121.eth"), id);
        console.log("Gas used STAKING :", _Stake.receipt.gasUsed)
        console.log(_Stake.logs[0].args)
        console.log(`Staked token ${id}`);

      
    }

    let size = await instance.getTotalSharePerTokenSize();
    for (let i = 0; i < size[0]; i++) {
        for (let j = 0; j < size[1]; j++) {
            let element = await instance.getTotalSharePerToken(i, j);
            console.log(`totalSharePerToken[${i}][${j}] = ${element}`);
        }
    }


    callback();
  } catch (error) {
    console.error(error);
    callback(error);
  }
};