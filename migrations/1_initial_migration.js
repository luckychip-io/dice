const DiceToken = artifacts.require("DiceToken")
const Dice = artifacts.require("Dice")

module.exports = async function(deployer) {
  await deployer.deploy(DiceToken, "LC Dice BPs", "LC-DICE-WBNB");
  let instanceToken = await DiceToken.deployed();
  console.log(instanceToken.address);

  await deployer.deploy(
	Dice,
	"0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
	"0x30998b6283D428a1e85068F416a1992365d9e0Db",
	instanceToken.address,
	//"0x56c1Bcdad3996000DE41d503B38F3b7b2f71d842",
	"0x98ebA625BE3C2a5ea65c9B691f3362d0d3e88179",
	0,
	20,
	500,
	600,
	1000000000000000,
	1000000000000000
	);
};
