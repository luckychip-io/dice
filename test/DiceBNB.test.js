const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');
const JSBI           = require('jsbi')
const DiceToken = artifacts.require('DiceToken');
const WBNB = artifacts.require('libs/WBNB');
const DiceBNB = artifacts.require('DiceBNB');
const MasterChef = artifacts.require('MasterChef');

contract('DiceBNB', ([alice, bob, carol, dev, refFeeAddr, operator, minter]) => {
    beforeEach(async () => {
		this.wbnb = await WBNB.new({from: minter});

        this.lc = await DiceToken.new('LC Tokens', 'LC', { from: minter });
        await this.lc.addMinter(minter, { from: minter });
		this.chef = await MasterChef.new(this.lc.address, dev, refFeeAddr, '1000', '100', '900000','90000', '10000', { from: minter });	

        this.token = await DiceToken.new('LC Dice BPs', 'LC-DICE-WBNB', { from: minter }); 
        await this.token.addMinter(minter, { from: minter });
		
        this.dice = await DiceBNB.new(this.wbnb.address, this.lc.address, this.token.address, this.chef.address, 0, 20, 500, 600, 1, 1, { from: minter });
        await this.token.addMinter(this.dice.address, { from: minter});
    
    });
    it('real case', async () => {
		await this.dice.setAdmin(dev, {from: minter});
		await this.dice.setOperator(operator, {from: dev});

		await this.dice.deposit({from: alice, value: 1});
		await this.dice.deposit({from: bob, value: 2});

		assert(await this.dice.bankerAmount().toString(), '2');
		assert(await this.dice.canWithdrawToken(alice).toString(), '1');

		let randomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		console.log(randomNumber);
		let bankHash = ethers.utils.keccak256(randomNumber);
		console.log(bankHash);
		await this.dice.endBankerTime(1, bankHash, {from: operator});

    });
});
