const ethers = require('ethers')
const DiceToken = artifacts.require("DiceToken")
const Dice = artifacts.require("Dice")

module.exports = async function(deployer) {
  await deployer.deploy(DiceToken, "LuckyWBNB", "LuckyWBNB");
  let instanceToken = await DiceToken.deployed();
  console.log(instanceToken.address);

  await deployer.deploy(
	Dice,
	"0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
	"0x0bd5B0bF4dA8249ed9502eeD2ed318D17C843f89",
	instanceToken.address,
	"0xB0940bf20358011093ea4391b3f15981A3e53Ab0",
	0,
	20,
	500,
	600,
    ethers.utils.parseEther('0.001'),
    ethers.utils.parseEther('0.001'),
    ethers.utils.parseEther('300000')
	);

};
