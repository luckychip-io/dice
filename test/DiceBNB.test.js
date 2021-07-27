const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');
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

		await this.dice.deposit({from: alice, value: 10});
		await this.dice.deposit({from: bob, value: 20});

		assert.equal((await this.dice.bankerAmount()).toString(), '30');
		assert.equal((await this.dice.canWithdrawToken(alice)).toString(), '10');

		let randomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let bankHash = ethers.utils.keccak256(randomNumber);
		console.log(randomNumber, bankHash);
		await expectRevert(this.dice.endBankerTime(1, bankHash, {from: minter}), 'operator: wut?');
		await this.dice.endBankerTime(1, bankHash, {from: operator});
		
		await this.dice.betNumber([false,false,true,false,false,false], {from:alice, value:2});
		await this.dice.betNumber([true,true,true,true,true,true], {from:bob, value:7});

		let round = await this.dice.rounds(1);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}

		lockBlock = round[1];
		console.log(`Current block: ${(await time.latestBlock())},${lockBlock}`);
		await expectRevert(this.dice.claim(1, {from: alice}), 'Round has not locked');
		await time.advanceBlockTo(lockBlock);
		let newRandomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let newBankHash = ethers.utils.keccak256(newRandomNumber);
		console.log(newRandomNumber, newBankHash);
		await this.dice.executeRound(1, newBankHash, {from: operator});
		await this.dice.sendSecret(1, randomNumber, {from: operator});

		round = await this.dice.rounds(1);
		console.log(`finalNumber,${round[11]}`);
		

    });
});
