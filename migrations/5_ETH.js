const ethers = require('ethers')
const DiceToken = artifacts.require("DiceToken")
const Dice = artifacts.require("Dice")

module.exports = async function(deployer) {
  await deployer.deploy(DiceToken, "LuckyETH", "LuckyETH");
  let instanceToken = await DiceToken.deployed();
  console.log(instanceToken.address);

  await deployer.deploy(
	Dice,
	"0xd66c6B4F0be8CE5b39D52E0Fd1344c389929B378",
	"0x8909BbBe374cF5158BEB18b1A8D5e93BC3e2C30F",
	instanceToken.address,
	"0xCc82850F42281E71f75ECc675ABdCc92891ec704",
	0,
	20,
	500,
	600,
    ethers.utils.parseEther('0.001'),
    ethers.utils.parseEther('0.001'),
    ethers.utils.parseEther('300000')
	);

};
