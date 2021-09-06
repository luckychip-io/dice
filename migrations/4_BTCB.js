const ethers = require('ethers')
const DiceToken = artifacts.require("DiceToken")
const Dice = artifacts.require("Dice")

module.exports = async function(deployer) {
  await deployer.deploy(DiceToken, "LuckyBTCB", "LuckyBTCB");
  let instanceToken = await DiceToken.deployed();
  console.log(instanceToken.address);

  await deployer.deploy(
	Dice,
	"0x6ce8dA28E2f864420840cF74474eFf5fD80E65B8",
	"0xD263fA5F95F7F2Cbd0218BA83E9baFD29971A3D6",
	instanceToken.address,
	"0x7aB09C37Dd457EDf843f1e27C415BF9cE3F11828",
	3,
	20,
	500,
	600,
    ethers.utils.parseEther('0.001'),
    ethers.utils.parseEther('0.001'),
    ethers.utils.parseEther('300000')
	);

  let instanceDice = await Dice.deployed();
  console.log(instanceDice.address);
  await instanceToken.transferOwnership(instanceDice.address);
  console.log('transferOwnership done');

};
