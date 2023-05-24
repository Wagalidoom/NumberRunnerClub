const NumberRunnerClub = artifacts.require("NumberRunnerClub");
// [
//     '0x7fa614a9a31B33D95CAC386646a68A8Ea2E562b3',
//     '0xA733a8F4Ca6F441881BB3431D01d1a4D7FfFE88a',
//     '0xfA951523931FA7AC0d6C139748Fb684945fb9c4C',
//     '0x477c26917d42ee71B15ABc7EC64dd8C6210F47E3',
//     '0x884117aD42dC134D4996e61A16e8c7d5002026a5',
//     '0x7994CF3448F5c63395404210ff575d4954D9BbFe',
//     '0xdd47109A2DaaD33Ef11e8D5693934081662e0790',
//     '0x0565AB5F29949d9b5607DE2E56A72db06FDbFA2c',
//     '0xc86BE514A50DD94DD045701BEab19339Fa0E5593',
//     '0xCab9A5Cd763a02Dc3C151190674D484c0858ca3F'
//   ]


module.exports = async function(callback) {
  try {
    const instance = await NumberRunnerClub.deployed();
    // await instance.chooseColor(1, {from: "0x7fa614a9a31B33D95CAC386646a68A8Ea2E562b3"})
    for (let i = 0; i < 100; i++) {
        const _Mint = await instance.mint(5, {from: "0x7fa614a9a31B33D95CAC386646a68A8Ea2E562b3", value: web3.utils.toWei('0.21', 'ether')});
        console.log("Gas used MINT :", _Mint.receipt.gasUsed)
        id = _Mint.logs[0].args.tokenId.words[0]
        console.log(id)
        console.log(`Minted token ${id}`);
        const _Stake = await instance._stake("0x7fa614a9a31B33D95CAC386646a68A8Ea2E562b3", "0x7fa614a9a31B33D95CAC386646a68A8Ea2E562b3", id);
        console.log("Gas used STAKING :", _Stake.receipt.gasUsed)
        console.log(_Stake.logs[0].args)
        console.log(`Staked token ${id}`);

      
    }

    callback();
  } catch (error) {
    console.error(error);
    callback(error);
  }
};