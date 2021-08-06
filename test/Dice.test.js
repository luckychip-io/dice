const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { AddressZero } = require("@ethersproject/constants")
const { assert } = require('chai');
const ethers = require('ethers');
const DiceToken = artifacts.require('DiceToken');
const LCToken = artifacts.require('LCToken');
const Dice = artifacts.require('Dice');
const MockBEP20 = artifacts.require('libs/MockBEP20');
const MasterChef = artifacts.require('MasterChef');

contract('Dice', ([alice, bob, carol, david, refFeeAddr, admin, minter]) => {
    beforeEach(async () => {
		this.token = await MockBEP20.new('Wrapped BNB', 'WBNB', '10000000', { from: minter });
		await this.token.transfer(alice, '1000000', {from: minter});
		await this.token.transfer(bob, '1000000', {from: minter});
		await this.token.transfer(carol, '1000000', {from: minter});
		await this.token.transfer(david, '1000000', {from: minter});

        this.lc = await LCToken.new({ from: minter});
		this.chef = await MasterChef.new(this.lc.address, admin, refFeeAddr, '1000', '100', '900000','90000', '10000', { from: minter });	
        await this.lc.transferOwnership(this.chef.address, { from: minter });

        this.diceToken = await DiceToken.new('LC Dice BPs', 'LC-DICE-WBNB', { from: minter }); 
        this.dice = await Dice.new(this.token.address, this.lc.address, this.diceToken.address, this.chef.address, 0, 20, 500, 600, 1, 1, 1000000, { from: minter });
        await this.diceToken.transferOwnership(this.dice.address, { from: minter});

		this.lp1 = await MockBEP20.new('LPToken', 'LP1', '10000000', { from: minter });
		await this.lp1.transfer(carol, '100000', {from:minter});
		await this.lp1.transfer(david, '100000', {from:minter});
		await this.chef.add('1000', '90', this.lp1.address, true, { from: minter });
		await this.chef.addBonus(this.token.address, { from: minter });
		await this.lp1.approve(this.chef.address, '100000', {from:carol});
		await this.lp1.approve(this.chef.address, '100000', {from:david});
    
    });
    it('real case', async () => {
		await this.dice.setAdmin(admin, {from: minter});

		await this.token.approve(this.dice.address, '1000000', { from: alice });
		await this.token.approve(this.dice.address, '1000000', { from: bob });
		await this.token.approve(this.dice.address, '1000000', { from: carol });
		await this.token.approve(this.dice.address, '1000000', { from: david });
		await this.chef.deposit(0, '100', AddressZero, {from:carol});
		await this.chef.deposit(0, '200', AddressZero, {from:david});
		await this.diceToken.approve(this.dice.address, '1000000', { from: carol });
		await this.diceToken.approve(this.dice.address, '1000000', { from: david });
		await this.dice.deposit(200000, {from: carol});
		await this.dice.deposit(400000, {from: david});

		assert.equal((await this.dice.bankerAmount()).toString(), '600000');
		assert.equal((await this.dice.canWithdrawToken(carol)).toString(), '200000');

		let randomNumber = ethers.utils.hexlify(ethers.utils.randomBytes(32));
		let bankHash = ethers.utils.keccak256(randomNumber);
		console.log(randomNumber, bankHash);
		await expectRevert(this.dice.endBankerTime(1, bankHash, {from: minter}), 'admin: wut?');
		await this.dice.endBankerTime(1, bankHash, {from: admin});

		console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());		
		await this.dice.betNumber([false,false,true,false,false,false], 200, {from:alice, value:1});
		await this.dice.betNumber([true,true,true,true,true,true], 1200, {from:bob, value:1});
		console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());		

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

		canClaim = await this.dice.claimable(1, alice, {from: alice});
		if(canClaim){
			await this.dice.claim(1, {from: alice});
			console.log(canClaim, 'claim for alice');
		}else{
			await expectRevert(this.dice.claim(1, {from: alice}), 'Not eligible for claim');
		}

		await this.dice.claim(1, {from: bob});
		console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());		
		console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());		
		console.log('bankerAmount',(await this.dice.bankerAmount()).toString());

		await expectRevert(this.dice.deposit(200000, {from: alice}), 'Pausable: not paused');
		await expectRevert(this.dice.withdraw(200000, {from: alice}), 'Pausable: not paused');

		await this.dice.betNumber([false,false,true,false,false,true], 200, {from:alice, value:1});
        await this.dice.betNumber([true,true,true,false,false,false], 600, {from:bob, value:1});
        console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());
        console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());
		
		round = await this.dice.rounds(2);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}

		lockBlock = round[1];
		await time.advanceBlockTo(lockBlock);
		await this.dice.lockRound(2, {from:admin});
		await this.dice.endPlayerTime(2, newRandomNumber, {from: admin});

		round = await this.dice.rounds(2);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}
		console.log(`finalNumber,${round[11]}`);

		canClaim = await this.dice.claimable(2, alice, {from: alice});
        if(canClaim){
            await this.dice.claim(2, {from: alice});
            console.log(canClaim, 'claim for alice');
        }else{
            await expectRevert(this.dice.claim(2, {from: alice}), 'Not eligible for claim');
        }

		canClaim = await this.dice.claimable(2, bob, {from: bob});
        if(canClaim){
            await this.dice.claim(2, {from: bob});
            console.log(canClaim, 'claim for alice');
        }else{
            await expectRevert(this.dice.claim(2, {from: bob}), 'Not eligible for claim');
        }

        console.log('alice balance: ', (await this.token.balanceOf(alice)).toString());
        console.log('bob balance: ', (await this.token.balanceOf(bob)).toString());
        console.log('bankerAmount',(await this.dice.bankerAmount()).toString());

		round = await this.dice.rounds(2);
		for(var i = 0; i < 13; i ++){
			console.log(`${round[i]}`);
		}

        console.log('netValue ', (await this.dice.netValue()).toString());
        console.log('carol diceToken balance: ', (await this.diceToken.balanceOf(carol)).toString());
        console.log('david diceToken balance: ', (await this.diceToken.balanceOf(david)).toString());
        console.log('carol balance: ', (await this.token.balanceOf(carol)).toString());
        console.log('david balance: ', (await this.token.balanceOf(david)).toString());
		
		await this.dice.withdraw(200000, {from: carol});
		await this.dice.withdraw(400000, {from: david});
        console.log('carol diceToken balance: ', (await this.diceToken.balanceOf(carol)).toString());
        console.log('david diceToken balance: ', (await this.diceToken.balanceOf(david)).toString());
        console.log('carol token balance: ', (await this.token.balanceOf(carol)).toString());
        console.log('david token balance: ', (await this.token.balanceOf(david)).toString());
        console.log('carol lp1 balance: ', (await this.lp1.balanceOf(carol)).toString());
        console.log('david lp1 balance: ', (await this.lp1.balanceOf(david)).toString());
        console.log('chef token balance: ', (await this.token.balanceOf(this.chef.address)).toString());
		await this.chef.withdraw(0, 100, {from: carol});
		await this.chef.withdraw(0, 200, {from: david});
        console.log('chef token balance: ', (await this.token.balanceOf(this.chef.address)).toString());
        console.log('carol lp1 balance: ', (await this.lp1.balanceOf(carol)).toString());
        console.log('david lp1 balance: ', (await this.lp1.balanceOf(david)).toString());
        console.log('carol token balance: ', (await this.token.balanceOf(carol)).toString());
        console.log('david token balance: ', (await this.token.balanceOf(david)).toString());

    });
});
