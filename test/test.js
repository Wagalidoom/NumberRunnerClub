const DutchAuction = artifacts.require("ExponentialFunction");

module.exports = async function(callback) {
    try {
        // Obtenir une instance du contrat
        const dutchAuction = await DutchAuction.deployed();
        const number = 1;
        // Appeler une fonction qui ne modifie pas l'état du contrat
        const price = await dutchAuction.calculateFunction(number*86400);
        console.log("Price: " + (price * 10000/2**64).toString());

        callback();
    } catch (error) {
        console.error(error);
        callback(error);
    }
};
