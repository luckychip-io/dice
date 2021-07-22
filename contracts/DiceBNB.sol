// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DiceToken.sol";
import "./libs/IBEP20.sol";
import "./libs/IWBNB.sol";
import "./libs/SafeBEP20.sol";
import "./libs/ILuckyChipRouter02.sol";
import "./libs/ILuckyChipFactory.sol";
import "./libs/IMasterChef.sol";

contract DiceBNB is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public prevBankerAmount;
    uint256 public bankerAmount;
    uint256 public netValue;
    uint256 public currentEpoch;
    uint256 public intervalBlocks;
    uint256 public playerTimeBlocks;
    uint256 public playerEndBlock;
    uint256 public bankerTimeBlocks;
    uint256 public bankerEndBlock;
    uint256 public constant TOTAL_RATE = 100; // 100%
    uint256 public gapRate = 5;
    uint256 public treasuryRate = 10; // 10% in gap
    uint256 public bonusRate = 10; // 10% in gap
    uint256 public minBetAmount;
	uint256 public feeAmount;
    uint256 public totalTreasuryAmount;
    uint256 public constant deadline = 5 minutes;
    uint256 public masterChefBonusId;

    address public adminAddress;
    address public operatorAddress;
    address public masterChefAddress;
    address public swapPairAddress;
	IWBNB public WBNB;
    IBEP20 public lcToken;
    DiceToken public diceToken;    
    ILuckyChipRouter02 public swapRouter;

    enum Status {
        Pending,
        Open,
        Lock,
        Claimable,
        Expired
    }

    struct Round {
        uint256 startBlock;
        uint256 lockBlock;
        uint256 secretSentBlock;
        bytes32 bankHash;
        uint256 bankSecret;
        uint256 totalAmount;
        uint256 maxBetAmount;
        uint256[6] betAmounts;
        uint256 treasuryAmount;
        uint256 bonusAmount;
        uint256 bonusLcAmount;
        uint256 betUsers;
        uint32 finalNumber;
        Status status;
    }

    struct BetInfo {
        uint256 amount;
        uint16 numberCount;    
        bool[6] numbers;
        bool claimed; // default false
        bool lcClaimed; // default false
    }

    struct BankerInfo {
        uint256 diceTokenAmount;
        uint256 avgBuyValue;
    }

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => BetInfo)) public ledger;
    mapping(address => uint256[]) public userRounds;
    mapping(address => BankerInfo) public bankerInfo;

    event StartRound(uint256 indexed epoch, uint256 blockNumber, bytes32 bankHash);
    event LockRound(uint256 indexed epoch, uint256 blockNumber);
    event SendSecretRound(uint256 indexed epoch, uint256 blockNumber, uint256 bankSecret, uint32 finalNumber);
    event BetNumber(address indexed sender, uint256 indexed currentEpoch, bool[6] numbers, uint256 amount);
    event Claim(address indexed sender, uint256 indexed currentEpoch, uint256 amount);
    event ClaimBonusLC(address indexed sender, uint256 amount);
    event ClaimTreasury(uint256 amount);
    event RewardsCalculated(
        uint256 indexed epoch,
        uint256 treasuryAmount,
        uint256 bonusAmount,
        uint256 bonusLcAmount
    );
    event EndPlayerTime(uint256 epoch, uint256 blockNumber);
    event EndBankerTime(uint256 epoch, uint256 blockNumber);
    event UpdateNetValue(uint256 epoch, uint256 blockNumber, uint256 netValue);
    event Deposit(address indexed user, uint256 tokenAmount);    
    event Withdraw(address indexed user, uint256 diceTokenAmount);    

    constructor(
		address _WBNBAddress,
        address _lcTokenAddress,
        address _diceTokenAddress,
        address _masterChefAddress,
        uint256 _masterChefBonusId,
        uint256 _intervalBlocks,
        uint256 _playerTimeBlocks,
        uint256 _bankerTimeBlocks,
        uint256 _minBetAmount,
        uint256 _feeAmount
    ) public {
		WBNB = IWBNB(_WBNBAddress);
        lcToken = IBEP20(_lcTokenAddress);
        diceToken = DiceToken(_diceTokenAddress);
        masterChefAddress = _masterChefAddress;
        masterChefBonusId = _masterChefBonusId;
        intervalBlocks = _intervalBlocks;
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
        minBetAmount = _minBetAmount;
        feeAmount = _feeAmount;
        netValue = uint256(1e12);
        _pause();
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "operator: wut?");
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    // set admin address
    function setAdmin(address _adminAddress) external onlyOwner {
        require(_adminAddress != address(0), "Cannot be zero address");
        adminAddress = _adminAddress;
    }

    // set operator address
    function setOperator(address _operatorAddress) external onlyAdmin {
        require(_operatorAddress != address(0), "Cannot be zero address");
        operatorAddress = _operatorAddress;
    }

    // set interval blocks
    function setIntervalBlocks(uint256 _intervalBlocks) external onlyAdmin {
        intervalBlocks = _intervalBlocks;
    }

    // set player time blocks
    function setPlayerTimeBlocks(uint256 _playerTimeBlocks) external onlyAdmin {
        playerTimeBlocks = _playerTimeBlocks;
    }

    // set banker time blocks
    function setBankerTimeBlocks(uint256 _bankerTimeBlocks) external onlyAdmin {
        bankerTimeBlocks = _bankerTimeBlocks;
    }

    // set gap rate
    function setGapRate(uint256 _gapRate) external onlyAdmin {
        require(_gapRate <= 10, "gapRate <= 10%");
        gapRate = _gapRate;
    }

    // set treasury rate
    function setRates(uint256 _treasuryRate, uint256 _bonusRate) external onlyAdmin {
        require(_treasuryRate.add(_bonusRate) <= TOTAL_RATE, "_treasuryRate + _bonusRate <= TOTAL_RATE");
        treasuryRate = _treasuryRate;
        bonusRate = _bonusRate;
    }

    // set minBetAmount
    function setMinBetAmount(uint256 _minBetAmount) external onlyAdmin {
        minBetAmount = _minBetAmount;
    }

    // set feeAmount
    function setFeeAmount(uint256 _feeAmount) external onlyAdmin {
        feeAmount = _feeAmount;
    }

    // End banker time
    function endBankerTime(uint256 epoch, bytes32 bankHash) external onlyOperator whenPaused {
        require(epoch == currentEpoch + 1, "epoch == currentEposh + 1");
        require(bankerAmount > 0, "Round can start only when bankerAmount > 0");
        prevBankerAmount = bankerAmount;
        _unpause();
        emit EndBankerTime(currentEpoch, block.timestamp);
        
        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch, bankHash);
        playerEndBlock = rounds[currentEpoch].startBlock + playerTimeBlocks;
        bankerEndBlock = rounds[currentEpoch].startBlock + bankerTimeBlocks;
    }

    // Start the next round n, lock for round n-1
    function executeRound(uint256 epoch, bytes32 bankHash) external onlyOperator whenNotPaused{
        require(epoch == currentEpoch, "epoch == currentEposh");

        // CurrentEpoch refers to previous round (n-1)
        _safeLockRound(currentEpoch);

        // Increment currentEpoch to current round (n)
        currentEpoch = currentEpoch + 1;
        _safeStartRound(currentEpoch, bankHash);
        require(rounds[currentEpoch].startBlock < playerEndBlock, "startBlock < playerEndBlock");
        require(rounds[currentEpoch].lockBlock <= playerEndBlock, "lockBlock < playerEndBlock");
    }

    // end player time, triggers banker time
    function endPlayerTime(uint256 epoch, uint256 bankSecret) external onlyOperator whenNotPaused{
        require(epoch == currentEpoch, "epoch == currentEposh");
        sendSecret(epoch, bankSecret);
        _pause();
        _updateNetValue(epoch);
        emit EndPlayerTime(currentEpoch, block.timestamp);
    }

    // end player time without caring last round
    function endPlayerTimeImmediately(uint256 epoch) external onlyOperator whenNotPaused{
        require(epoch == currentEpoch, "epoch == currentEposh");
        _pause();
        _updateNetValue(epoch);
        emit EndPlayerTime(currentEpoch, block.timestamp);
    }

    // update net value
    function _updateNetValue(uint256 epoch) internal whenPaused{    
        netValue = netValue.mul(bankerAmount).div(prevBankerAmount);
        emit UpdateNetValue(epoch, block.timestamp, netValue);
    }

    // send bankSecret
    function sendSecret(uint256 epoch, uint256 bankSecret) public onlyOperator whenNotPaused{
        Round storage round = rounds[epoch];
        require(round.lockBlock != 0, "End round after round has locked");
        require(round.status == Status.Lock, "End round after round has locked");
        require(block.number >= round.lockBlock, "Send secret after lockBlock");
        require(block.number <= round.lockBlock.add(intervalBlocks), "Send secret within invervalBlocks");
        require(round.bankSecret == 0, "Already revealed");
        require(keccak256(abi.encodePacked(bankSecret)) == round.bankHash, "Bank reveal not matching commitment");

        _safeSendSecret(epoch, bankSecret);
        _calculateRewards(epoch);
    }

    function _safeSendSecret(uint256 epoch, uint256 bankSecret) internal whenNotPaused {
        Round storage round = rounds[epoch];
        round.secretSentBlock = block.number;
        round.bankSecret = bankSecret;
		uint256 random = round.bankSecret ^ round.betUsers;
        round.finalNumber = uint32(random % 6);
        round.status = Status.Claimable;

        emit SendSecretRound(epoch, block.number, bankSecret, round.finalNumber);
    }

    // bet number
    function betNumber(bool[6] calldata numbers) external payable whenNotPaused notContract nonReentrant {
        require(rounds[currentEpoch].status == Status.Open, "Round not Open");
        require(_bettable(currentEpoch), "Round not bettable");
        require(ledger[currentEpoch][msg.sender].amount == 0, "Bet once per round");
        uint16 numberCount = 0;
        for (uint32 i = 0; i < 6; i ++) {
            if (numbers[i]) {
                numberCount = numberCount + 1;    
            }
        }

        require(msg.value >= minBetAmount.mul(uint256(numberCount)).add(feeAmount), "BetAmount > minBetAmount * numberCount");
		if (feeAmount > 0){
			_safeTransferBNB(operatorAddress, feeAmount);
		}

		uint256 amount = msg.value.sub(feeAmount);
        require(numberCount > 0, "numberCount > 0");

        // Update round data
        Round storage round = rounds[currentEpoch];
        round.totalAmount = round.totalAmount.add(amount);
        round.betUsers = round.betUsers.add(1);
        uint256 betAmount = amount.div(uint256(numberCount));
        for (uint32 i = 0; i < 6; i ++) {
            if (numbers[i]) {
                round.betAmounts[i] = round.betAmounts[i].add(betAmount);
            }
        }

        // Update user data
        BetInfo storage betInfo = ledger[currentEpoch][msg.sender];
        betInfo.numbers = betInfo.numbers;
        betInfo.amount = amount;
        betInfo.numberCount = numberCount;
        userRounds[msg.sender].push(currentEpoch);

        emit BetNumber(msg.sender, currentEpoch, numbers, amount);
    }


    // Claim reward
    function claim(uint256 epoch) external notContract nonReentrant {
        require(rounds[epoch].startBlock != 0, "Round has not started");
        require(block.number > rounds[epoch].lockBlock, "Round has not locked");
        require(!ledger[epoch][msg.sender].claimed, "Rewards claimed");

        uint256 reward;
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        // Round valid, claim rewards
        if (rounds[epoch].status == Status.Claimable) {
            require(claimable(epoch, msg.sender), "Not eligible for claim");
            reward = betInfo.amount.div(uint256(betInfo.numberCount)).mul(5).mul(TOTAL_RATE.sub(gapRate)).div(TOTAL_RATE);
        }
        // Round invalid, refund bet amount
        else {
            require(refundable(epoch, msg.sender), "Not eligible for refund");
            reward = ledger[epoch][msg.sender].amount;
        }

        betInfo.claimed = true;
		_safeTransferBNB(address(msg.sender), reward);

        emit Claim(msg.sender, epoch, reward);
    }

    // Claim lc back
    function claimBonusLC(address user) external notContract nonReentrant {
        uint256 lcAmount = 0;    
        uint256 epoch;
        uint256 roundLcAmount = 0;
        for (uint256 i = userRounds[user].length - 1; i >= 0; i --){
            epoch = userRounds[user][i];
            BetInfo storage betInfo = ledger[epoch][msg.sender];
            if (betInfo.lcClaimed){
                break;
            }else{
                if (rounds[epoch].status == Status.Claimable){
                    if (betInfo.numbers[rounds[epoch].finalNumber]){
                        roundLcAmount = betInfo.amount.div(uint256(betInfo.numberCount)).mul(5).mul(gapRate).div(TOTAL_RATE).mul(bonusRate).div(TOTAL_RATE);
                        if (betInfo.numberCount > 1){
                            roundLcAmount = roundLcAmount.add(betInfo.amount.div(uint256(betInfo.numberCount)).mul(uint256(betInfo.numberCount - 1)).mul(gapRate).div(TOTAL_RATE).mul(bonusRate).div(TOTAL_RATE));
                        }
                    }else{
                        roundLcAmount = betInfo.amount.mul(bonusRate).div(TOTAL_RATE).mul(rounds[epoch].bonusLcAmount).div(rounds[epoch].bonusAmount);
                    }
    
                    lcAmount = lcAmount.add(roundLcAmount);
                    betInfo.lcClaimed = true;
                }
            }
        }

        lcToken.safeTransfer(user, lcAmount);
        emit ClaimBonusLC(user, lcAmount);
    }

    // View pending lc back
    function pendingBonusLC(address user) external view returns (uint256) {
        uint256 lcAmount = 0;
        uint256 epoch;
        for (uint256 i = userRounds[user].length - 1; i >= 0; i --){
            epoch = userRounds[user][i];
            BetInfo storage betInfo = ledger[epoch][msg.sender];
            if (betInfo.lcClaimed){
                break;
            }else{
                if (rounds[epoch].status == Status.Claimable){
					uint256 roundLcAmount = 0;
                    if (betInfo.numbers[rounds[epoch].finalNumber]){
                        roundLcAmount = betInfo.amount.div(uint256(betInfo.numberCount)).mul(5).mul(gapRate).div(TOTAL_RATE).mul(bonusRate).div(TOTAL_RATE);
                        if (betInfo.numberCount > 1){
                            roundLcAmount = roundLcAmount.add(betInfo.amount.div(uint256(betInfo.numberCount)).mul(uint256(betInfo.numberCount - 1)).mul(gapRate).div(TOTAL_RATE).mul(bonusRate).div(TOTAL_RATE));
                        }
                    }else{
                        roundLcAmount = betInfo.amount.mul(bonusRate).div(TOTAL_RATE).mul(rounds[epoch].bonusLcAmount).div(rounds[epoch].bonusAmount);
                    }
                    
                    lcAmount = lcAmount.add(roundLcAmount);
                }
            }
        }
        return lcAmount;    
    }

    // Claim all treasury to masterChef
    function claimTreasury() public onlyOperator {
		WBNB.deposit{value:totalTreasuryAmount}();
		assert(WBNB.transfer(address(this), totalTreasuryAmount));
        IMasterChef(masterChefAddress).updateBonus(masterChefBonusId, totalTreasuryAmount);
        emit ClaimTreasury(totalTreasuryAmount);
        totalTreasuryAmount = 0;
    }

    // Return round epochs that a user has participated
    function getUserRounds(
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (uint256[] memory, uint256) {
        uint256 length = size;
        if (length > userRounds[user].length - cursor) {
            length = userRounds[user].length - cursor;
        }

        uint256[] memory values = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = userRounds[user][cursor.add(i)];
        }

        return (values, cursor.add(length));
    }

    // Get the claimable stats of specific epoch and user account
    function claimable(uint256 epoch, address user) public view returns (bool) {
        return (rounds[epoch].status == Status.Claimable) && (ledger[epoch][user].numbers[rounds[epoch].finalNumber]);
    }

    // Get the refundable stats of specific epoch and user account
    function refundable(uint256 epoch, address user) public view returns (bool) {
        return (rounds[epoch].status != Status.Claimable) && block.number > rounds[epoch].lockBlock.add(intervalBlocks) && ledger[epoch][user].amount != 0;
    }

    // Start round. Previous round n-1 must lock
    function _safeStartRound(uint256 epoch, bytes32 bankHash) internal {
        require(block.number >= rounds[epoch - 1].lockBlock, "Start new round after round n-1 lock");
        _startRound(epoch, bankHash);
    }

    function _startRound(uint256 epoch, bytes32 bankHash) internal {
        Round storage round = rounds[epoch];
        round.startBlock = block.number;
        round.lockBlock = block.number.add(intervalBlocks);
        round.bankHash = bankHash;
        round.totalAmount = 0;
        round.status = Status.Open;

        emit StartRound(epoch, block.number, bankHash);
    }

    // Lock round
    function _safeLockRound(uint256 epoch) internal {
        Round storage round = rounds[epoch];
        require(round.startBlock != 0, "Lock round after round has started");
        require(block.number >= round.lockBlock, "Lock round after lockBlock");
        require(block.number <= round.lockBlock.add(intervalBlocks), "Lock round within intervalBlocks");
        round.status = Status.Lock;
        emit LockRound(epoch, block.number);
    }

    // Calculate rewards for round
    function _calculateRewards(uint256 epoch) internal {
        require(treasuryRate.add(bonusRate) <= TOTAL_RATE, "TreasuryRate + bonusRate <= TOTAL_RATE");
        require(rounds[epoch].treasuryAmount == 0, "Rewards calculated");
        Round storage round = rounds[epoch];

        uint256 treasuryAmount = 0;
        uint256 bonusAmount = 0;
        for (uint32 i = 0; i < 6; i ++){
            if (i == round.finalNumber){
                uint256 tmpTreasuryAmount = round.betAmounts[i].mul(5).mul(gapRate).div(TOTAL_RATE).mul(treasuryRate).div(TOTAL_RATE);
                treasuryAmount = treasuryAmount.add(tmpTreasuryAmount);
                uint256 tmpBonusAmount = round.betAmounts[i].mul(5).mul(gapRate).div(TOTAL_RATE).mul(bonusRate).div(TOTAL_RATE);
                bonusAmount = bonusAmount.add(tmpBonusAmount);
                uint256 playerWinAmount = round.betAmounts[i].mul(5).mul(TOTAL_RATE.sub(gapRate)).div(TOTAL_RATE);
                bankerAmount = bankerAmount.sub(playerWinAmount).sub(tmpTreasuryAmount).sub(tmpBonusAmount);
            }else{
                uint256 tmpTreasuryAmount = round.betAmounts[i].mul(gapRate).div(TOTAL_RATE).mul(treasuryRate).div(TOTAL_RATE);
                treasuryAmount = treasuryAmount.add(tmpTreasuryAmount);
                uint256 tmpBonusAmount = round.betAmounts[i].mul(gapRate).div(TOTAL_RATE).mul(bonusRate).div(TOTAL_RATE);
                bonusAmount = bonusAmount.add(tmpBonusAmount);
                uint256 playerLostAmount = round.betAmounts[i];
                bankerAmount = bankerAmount.add(playerLostAmount).sub(tmpTreasuryAmount).sub(tmpBonusAmount);
            }    
        }

        round.treasuryAmount = treasuryAmount;
        round.bonusAmount = bonusAmount;

        if(address(swapRouter) != address(0) && swapPairAddress != address(0)){
            address[] memory path = new address[](2);
            path[0] = address(WBNB);
            path[1] = address(lcToken);
            uint256 lcAmout = swapRouter.swapExactETHForTokens{value:round.bonusAmount}(0, path, address(this), block.timestamp + deadline)[1];
            round.bonusLcAmount = lcAmout;
        }
        totalTreasuryAmount = totalTreasuryAmount.add(treasuryAmount);

        emit RewardsCalculated(epoch, round.treasuryAmount, round.bonusAmount, round.bonusLcAmount);
    }

    // Deposit token to Dice as a banker, get Syrup back.
    function deposit() public payable whenPaused nonReentrant notContract {
		uint256 _tokenAmount = msg.value;
        require(_tokenAmount > 0, "Deposit amount > 0");
        BankerInfo storage banker = bankerInfo[msg.sender];
        uint256 diceTokenAmount = _tokenAmount.mul(1e12).div(netValue);
        diceToken.mint(address(msg.sender), diceTokenAmount);
        uint256 totalDiceTokenAmount = banker.diceTokenAmount.add(diceTokenAmount);
        banker.avgBuyValue = banker.avgBuyValue.mul(banker.diceTokenAmount).div(1e12).add(_tokenAmount).mul(1e12).div(totalDiceTokenAmount);
        banker.diceTokenAmount = totalDiceTokenAmount;
        bankerAmount = bankerAmount.add(_tokenAmount);
        emit Deposit(msg.sender, _tokenAmount);    
    }

    // Withdraw syrup from dice to get token back
    function withdraw(uint256 _diceTokenAmount) public whenPaused nonReentrant notContract {
        require(_diceTokenAmount > 0, "diceTokenAmount > 0");
        BankerInfo storage banker = bankerInfo[msg.sender];
        banker.diceTokenAmount = banker.diceTokenAmount.sub(_diceTokenAmount); 
        SafeBEP20.safeTransferFrom(diceToken, msg.sender, address(diceToken), _diceTokenAmount);
        diceToken.burn(address(diceToken), _diceTokenAmount);
        uint256 tokenAmount = _diceTokenAmount.mul(netValue).div(1e12);
        bankerAmount = bankerAmount.sub(tokenAmount);
		_safeTransferBNB(msg.sender, tokenAmount);

        emit Withdraw(msg.sender, _diceTokenAmount);
    }

    // View function to see banker diceToken Value on frontend.
    function canWithdrawToken(address bankerAddress) external view returns (uint256){
        return bankerInfo[bankerAddress].diceTokenAmount.mul(netValue).div(1e12);    
    }

    // View function to see banker diceToken Value on frontend.
    function calProfitRate(address bankerAddress) external view returns (uint256){
        return netValue.mul(100).div(bankerInfo[bankerAddress].avgBuyValue);    
    }

    // Judge address is contract or not
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // judge epoch is within startBlock and lockBlock
    function _bettable(uint256 epoch) internal view returns (bool) {
        return
            rounds[epoch].startBlock != 0 &&
            rounds[epoch].lockBlock != 0 &&
            block.number > rounds[epoch].startBlock &&
            block.number < rounds[epoch].lockBlock;
    }
	
	// Update the swap router.
    function updateSwapRouter(address _router) external onlyOperator {
        swapRouter = ILuckyChipRouter02(_router);
        swapPairAddress = ILuckyChipFactory(swapRouter.factory()).getPair(address(WBNB), address(lcToken));
        require(swapPairAddress != address(0), "DICE::updateSwapRouter: Invalid pair address.");
    }

	function _safeTransferBNB(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
        require(success, 'TransferHelper: BNB_TRANSFER_FAILED');
    }

}
