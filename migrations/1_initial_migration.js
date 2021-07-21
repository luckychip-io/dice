const DiceToken = artifacts.require("DiceToken")
const Dice = artifacts.require("Dice")

module.exports = async function(deployer) {
  //await deployer.deploy(DiceToken, "LC Dice BPs", "LC-DICE-WBNB");
  //let instanceToken = await DiceToken.deployed();
  //console.log(instanceToken.address);

  await deployer.deploy(
	Dice,
	"0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
	"0x9C10E684EF7CE6069fb6F90A5e9C8A727a13FbaB",
	//instanceToken.address,
	"0x56c1Bcdad3996000DE41d503B38F3b7b2f71d842",
	"0xa6A9010075c97f309Fc9B92e841011CAb84D12C5",
	0,
	20,
	20,
	500,
	600,
	1000000000000000,
	1000000000000000
	);
};
