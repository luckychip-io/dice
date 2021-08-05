// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

// Dice Limit
contract DiceLimit is Ownable {
    using SafeMath for uint256;
    using Address for address;

    uint256 public intervalBlocks;
    uint256 public playerTimeBlocks;
    uint256 public bankerTimeBlocks;
    uint256 public constant TOTAL_RATE = 10000; // 100%
    uint256 public gapRate = 500;
    uint256 public lcBackRate = 1000; // 10% in gap
    uint256 public bonusRate = 1000; // 10% in gap
    uint256 public minBetAmount;
    uint256 public maxBetRatio = 5;
    uint256 public feeAmount;
    uint256 public maxBankerAmount;
    address public adminAddress;

    event RatesUpdated(uint256 indexed block, uint256 gapRate, uint256 lcBackRate, uint256 bonusRate);
    event MinBetAmountUpdated(uint256 indexed block, uint256 minBetAmount);
    event MaxBetRatioUpdated(uint256 indexed block, uint256 maxBetRatio);
    event FeeAmountUpdated(uint256 indexed block, uint256 feeAmount);

	constructor() public {}

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    // set blocks
    function setBlocks(uint256 _intervalBlocks, uint256 _playerTimeBlocks, uint256 _bankerTimeBlocks) external onlyAdmin {
        intervalBlocks = _intervalBlocks;
        playerTimeBlocks = _playerTimeBlocks;
        bankerTimeBlocks = _bankerTimeBlocks;
    }

    // set rates
    function setRates(uint256 _gapRate, uint256 _lcBackRate, uint256 _bonusRate) external onlyAdmin {
        require(_gapRate <= 1000, "gapRate <= 10%");
        require(_lcBackRate.add(_bonusRate) <= TOTAL_RATE, "_lcBackRate + _bonusRate <= TOTAL_RATE");
        gapRate = _gapRate;
        lcBackRate = _lcBackRate;
        bonusRate = _bonusRate;

        emit RatesUpdated(block.number, gapRate, lcBackRate, bonusRate);
    }

    // set minBetAmount
    function setMinBetAmount(uint256 _minBetAmount) external onlyAdmin {
        minBetAmount = _minBetAmount;
        emit MinBetAmountUpdated(block.number, minBetAmount);
    }

    // set maxBetRatio
    function setMaxBetRatio(uint256 _maxBetRatio) external onlyAdmin {
        maxBetRatio = _maxBetRatio;
        emit MaxBetRatioUpdated(block.number, maxBetRatio);
    }

    // set feeAmount
    function setFeeAmount(uint256 _feeAmount) external onlyAdmin {
        feeAmount = _feeAmount;
        emit FeeAmountUpdated(block.number, feeAmount);
    }

    // set admin address
    function setAdmin(address _adminAddress) external onlyOwner {
        require(_adminAddress != address(0), "Cannot be zero address");
        adminAddress = _adminAddress;
    }
}
