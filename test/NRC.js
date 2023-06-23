const NumberRunnerClub = artifacts.require("NumberRunnerClub");
const ethers = require("ethers");

module.exports = async function(callback) {
  try {
    console.log(ethers.version)
    const instance = await NumberRunnerClub.deployed();
    await instance.chooseColor(1, {from: "0xbD49815FE274150A77Be1771B04B2F0a7De1ba01"})
    for (let i = 0; i < 8; i++) {
      // User A minte et liste le token
      const _Mint = await instance.mint(5,0, {from: "0xbD49815FE274150A77Be1771B04B2F0a7De1ba01", value: web3.utils.toWei('0.21', 'ether')});
      console.log("Gas used MINT :", _Mint.receipt.gasUsed);
      id = _Mint.logs[0].args.tokenId.words[0]
      console.log(id);
      console.log(`Minted token ${id}`);
      console.log(`TOTAL MINTED : ${await instance.totalMinted()}`)
      await instance.approve("0x6D53CF1b411C942B35F4e41D2caDE60f94E5e99b", id);
      
      const _Stake = await instance.stack(web3.utils.asciiToHex("121.eth"), id);
      console.log("Gas used STAKING :", _Stake.receipt.gasUsed)
      // console.log(_Stake.logs[0].args)
      console.log(`Staked token ${id}`);
      console.log(`Rewards du ${id} : `, (await instance.getReward(id)).toString(), "epoch : ",(await instance.epoch()).toString());

      const unstack = await instance.unstack(id, {from: "0xbD49815FE274150A77Be1771B04B2F0a7De1ba01"});
      console.log(`Unstaked token ${id}`)
      const list = await instance.listNFT(id, 1, {from: "0xbD49815FE274150A77Be1771B04B2F0a7De1ba01"});
      console.log(`listed token ${id}`)
      await instance.approve("0x6D53CF1b411C942B35F4e41D2caDE60f94E5e99b", id);
      const buy = await instance.buyNFT(id, {from: "0x2Edc4da491238b6D3AD53b1FE9b5Af78f1056F88", value: 2})
      console.log(`BOUGHT token ${id}`)
      // let size = await instance.getShareTypeAccumulatorSize();
      // for (let i = 0; i < size[0]; i++) {
      //       for (let j = 0; j < size[1]; j++) {
      //           let element = await instance.getShareTypeAccumulator(i, j);
      //           console.log(`totalSharePerToken[${i}][${j}] = ${element}`);
      //       }
      //   }
      console.log(`Rewards token ${id}`, (await instance.getReward(id)).toString(), "epoch : ",(await instance.epoch()).toString());

      
    }

    // const unstack = await instance.unstack(362, {from: "0xFeCec56CAC42117f8a6180CD83E890De54c3e7ED"});
    // console.log(unstack)
    // console.log("UNSTACKED 362")
    // let size = await instance.getShareTypeAccumulatorSize();
    // for (let i = 0; i < size[0]; i++) {
    //     for (let j = 0; j < size[1]; j++) {
    //         let element = await instance.getShareTypeAccumulator(i, j);
    //         console.log(`totalSharePerToken[${i}][${j}] = ${element}`);
    //     }
    // }

    // console.log("AVANT LE CLAMING : ", (await instance.unclaimedRewards(362)).toString());
    // console.log((await web3.eth.getBalance(instance.address)).toString());
    // const _claim = await instance.claimPrivatePrize(362, {from: "0xFeCec56CAC42117f8a6180CD83E890De54c3e7ED"});
    // console.log(_claim);
    // console.log("CLAIMED !");
    // console.log("APRES LE CLAMING : ", (await instance.unclaimedRewards(362)).toString());
    // console.log((await web3.eth.getBalance(instance.address)).toString());

    callback();
  } catch (error) {
    console.error(error);
    callback(error);
  }
};

// await instance.approve(instance.address, id, {from: "0x5f39D68caFb8B43d194792d622db6ef71d6ABdE8"});
//       const _listing = await instance.listNFT(id, 120, {from: "0x5f39D68caFb8B43d194792d622db6ef71d6ABdE8"});
//       console.log(_listing);
//       console.log("LISTED !")
//       // User B Buy le token
//       const buyNFT = await instance.buyNFT(id, {from: "0xdd1B8d541E506179a3AdBF94729598C46930EDC4", value : web3.utils.toWei('0.1', 'ether')});
//       console.log(buyNFT);
//       console.log("BOUGHT !")
//       console.log(await instance.ownerOf(id));