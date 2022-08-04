// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import "../Modifiers/Ownable.sol";
import "../Modifiers/ReentrancyGuard.sol";
import "../Modifiers/DepositoryRestriction.sol";
import "../Modifiers/RewarderRestriction.sol";
import "../IGlobalMasterChef.sol";

contract VaultLocked is
    Ownable,
    ReentrancyGuard,
    DepositoryRestriction,
    RewarderRestriction
{
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;
    using SafeMath for uint16;

    struct DepositInfo {
        uint256 depositAmount;
        uint256 nextWithdrawable;
        uint256 createdAt;
        uint256 updatedAt;
    }

    mapping(address => DepositInfo[]) public depositInfo;
    mapping(address => bool) public userExistance;
    address[] public users;

    IBEP20 public global;
    IGlobalMasterChef public globalMasterChef;

    uint256 public constant DUST = 1000;
    uint256 public constant LOCKUP = 7776000; // lockup 90 days

    uint256 public minGlobalAmountToDistribute;
    mapping(address => uint256) public globalEarned;

    mapping(address => uint256) public depositCount;
    mapping(address => uint256[]) public depositAmount;

    uint256 public totalSupply;
    mapping(address => uint256) public userTotalSupply;
    mapping(address => uint256) public userReward;

    uint256 public lastRewardEvent;
    uint256 public rewardInterval;
    uint256 public globalBalance;
    unit256 public lastDistributedGlobalAmount;

    event Deposited(address indexed _user, uint256 _amount);
    event RewardDeposited(address indexed _user, uint256 _amount);
    event WithdrawDeposit(address indexed _user, uint256 _amount);
    event WithdrawReward(address indexed _user, uint256 _amount);
    event DistributedGlobal(uint256 globalAmount);

    constructor(address _global, address _globalMasterChef) public {
        pid = 0;

        global = IBEP20(_global);
        globalMasterChef = IGlobalMasterChef(_globalMasterChef);

        minGlobalAmountToDistribute = 100e18; // 100 BEP20 Token
        globalBalance = 0;
        lastDistributedGlobalAmount = 0;

        rewardInterval = 24 hours;
        lastRewardEvent = block.timestamp;
    }

    function setRewardInterval(uint256 _rewardInterval) external onlyOwner {
        rewardInterval = _rewardInterval;
    }

    function setMinGlobalAmountToDistribute(
        uint256 _minGlobalAmountToDistribute
    ) external onlyOwner {
        minGlobalAmountToDistribute = _minGlobalAmountToDistribute;
    }

    function getDepositInfoLengthByAddress(addres addr)
        public
        view
        returns (uint256)
    {
        return depositInfo[addr].length;
    }

    function globalToEarn(address _addr) public view returns (uint256) {
        if (userTotalSupply[_addr] > 0) {
            return globalEarned[_addr];
        } else {
            return 0;
        }
    }

    function getLastDistributedGlobalAmount() external view returns (uint256) {
        return lastDistributedGlobalAmount;
    }

    function deposit(uint256 _amount) public nonReentrant {
        global.safeTransferFrom(msg.sender, address(this), _amount);
        depositInfo[msg.sender].push(
            DepositInfo({
                depositAmount: _amount,
                nextWithdrawal: block.timestamp.add(LOCKUP)
            })
        );
        global.approve(address(globalMasterChef), _amount);
        globalMasterChef.enterStaking(_amount);

        if (userExistance[msg.sender] == false) {
            users.push(msg.sender);
        }

        totalSupply = totalSupply.add(_amount);
        userTotalSupply = userTotalSupply.add(_amount);
        uint256 reward1 = rewardByUser(msg.sender);
        userReward = userReward.add(reward1);

        if (globalToEarn(msg.sender) == 0) {
            globalEarned[msg.sender] = 0;
        }

        userExistance[msg.sender] = true;
    }

    function rewardByUser(address _addr) public returns (uint256) {
        uint256 earnedGlobal = globalToEarn(_addr);
        delete globalEarned[_addr];
    }
}
