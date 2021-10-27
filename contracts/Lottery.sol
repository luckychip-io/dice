// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/ILottery.sol";
import "./interfaces/ILuckyPower.sol";
import "./libraries/SafeBEP20.sol";

contract Lottery is ILottery, Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    mapping(address => uint256) public balanceOf;
    IBEP20 public lcToken;
    ILuckyPower public luckyPower;

    event InjectFunds(address indexed src, address indexed dst, uint256 blockNumber, uint256 amount);
    event ClaimLottery(address indexed user, uint256 blockNumber, uint256 amount);
    event SetLuckyPower(uint256 indexed block, address luckyPowerAddr);

    constructor(address _lcTokenAddr) public {
        lcToken = IBEP20(_lcTokenAddr);
    }

    modifier notContract() {
        require((!_isContract(msg.sender)) && (msg.sender == tx.origin), "no contract");
        _;
    }

    // Judge address is contract or not
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function injectFunds(address dst, uint256 amount) public nonReentrant notContract {
        lcToken.safeTransferFrom(address(msg.sender), address(this), amount);
        balanceOf[dst] = balanceOf[dst].add(amount);
        if(address(luckyPower) != address(0)){
            luckyPower.updatePower(dst);
        }
        emit InjectFunds(msg.sender, dst, block.number, amount); 
    }

    function claimLottery() external nonReentrant notContract{
        uint256 amount = balanceOf[msg.sender];
        if(amount > 0) {
            balanceOf[msg.sender] = 0;
            lcToken.safeTransfer(msg.sender, amount);
            if(address(luckyPower) != address(0)){
                luckyPower.updatePower(msg.sender);
            }
            emit ClaimLottery(msg.sender, block.number, amount); 
        }
    }
    
    function getLuckyPower(address user) external override view returns (uint256){
        return balanceOf[user];
    }

    // set the lucky power.
    function setLuckyPower(address _luckyPower) external onlyOwner {
        require(_luckyPower != address(0), "Zero");
        luckyPower = ILuckyPower(_luckyPower);
        emit SetLuckyPower(block.number, _luckyPower);
    }
}
