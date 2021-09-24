// SPDX-License-Identifier: MIT
  
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";

contract DiceLottery is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 public lcToken;
    mapping(address => uint256) public balanceOf;

    event InjectFunds(address indexed src, address indexed dst, uint256 blockNumber, uint256 amount);
    event ClaimLottery(address indexed user, uint256 blockNumber, uint256 amount);

    constructor(address _lcTokenAddress) public {
        lcToken = IBEP20(_lcTokenAddress);
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
        emit InjectFunds(msg.sender, dst, block.number, amount); 
    }

    function claimLottery() external nonReentrant notContract{
        uint256 amount = balanceOf[msg.sender];
        if(amount > 0) {
            balanceOf[msg.sender] = 0;
            lcToken.safeTransfer(msg.sender, amount);
            emit ClaimLottery(msg.sender, block.number, amount); 
        }
    }

}
