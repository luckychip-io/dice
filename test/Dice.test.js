const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');
const DiceToken = artifacts.require('DiceToken');
const Dice = artifacts.require('Dice');
const MockBEP20 = artifacts.require('libs/MockBEP20');
const MasterChef = artifacts.require('MasterChef');

contract('Dice', ([alice, bob, carol, david, refFeeAddr, admin, minter]) => {
    beforeEach(async () => {
		this.token = await MockBEP20.new('Wrapped BNB', 'WBNB', '10000000', { from: minter });
		await this.token.transfer(alice, '100000', {from: minter});
		await this.token.transfer(bob, '100000', {from: minter});
		await this.token.transfer(carol, '100000', {from: minter});
		await this.token.transfer(david, '100000', {from: minter});

        this.lc = await DiceToken.new('LC Tokens', 'LC', { from: minter });
        await this.lc.addMinter(minter, { from: minter });
		this.chef = await MasterChef.new(this.lc.address, admin, refFeeAddr, '1000', '100', '900000','90000', '10000', { from: minter });	

        this.diceToken = await DiceToken.new('LC Dice BPs', 'LC-DICE-WBNB', { from: minter }); 
        await this.diceToken.addMinter(minter, { from: minter });
		
        this.dice = await Dice.new(this.token.address, this.lc.address, this.diceToken.address, this.chef.address, 0, 20, 500, 600, 1, 1, { from: minter });
        await this.diceToken.addMinter(this.dice.address, { from: minter});
    
    });
    it('real case', async () => {
		await this.dice.setAdmin(admin, {from: minter});

		await this.token.approve(this.dice.address, '100000', { from: alice });
		await this.token.approve(this.dice.address, '100000', { from: bob });
		await this.token.approve(this.dice.address, '100000', { from: carol });
		await this.token.approve(this.dice.address, '100000', { from: david });
		await this.dice.deposit(10000, {from: alice});
		await this.dice.deposit(20000, {from: bob});

		assert.equal((await this.dice.bankerAmount()).toString(), '30000');
		assert.equal((await this.dice.canWithdrawToken(alice)).toString(), '10000');

		let randomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let bankHash = ethers.utils.keccak256(randomNumber);
		console.log(randomNumber, bankHash);
		await expectRevert(this.dice.endBankerTime(1, bankHash, {from: minter}), 'admin: wut?');
		await this.dice.endBankerTime(1, bankHash, {from: admin});
		
		await this.dice.betNumber([false,false,true,false,false,false], 10, {from:alice, value:1});
		await this.dice.betNumber([true,true,true,true,true,true], 60, {from:bob, value:1});

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
		await this.dice.executeRound(1, newBankHash, {from: admin});
		await this.dice.sendSecret(1, randomNumber, {from: admin});

		round = await this.dice.rounds(1);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}
		console.log(`finalNumber,${round[11]}`);

		betInfo = await this.dice.ledger(1, alice, {from: alice});
		console.log(`${betInfo[0]},${betInfo[1]},${betInfo[2]},${betInfo[3]},${betInfo[4]}`)
		betInfo = await this.dice.ledger(1, bob, {from: alice});
		console.log(`${betInfo[0]},${betInfo[1]},${betInfo[2]},${betInfo[3]},${betInfo[4]}`)

		console.log(await this.dice.claimable(1, alice, {from: alice}));
		console.log(await this.dice.claimable(1, bob, {from: bob}));

    });
});
