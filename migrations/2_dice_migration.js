var diceContract = artifacts.require("Dice");

module.exports = function(deployer) {
  deployer.deploy(diceContract);
};
