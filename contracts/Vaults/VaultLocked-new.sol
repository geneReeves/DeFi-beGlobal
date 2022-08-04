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
        uint256 amount;
        uint256 nextWithdrawable;
    }

    mapping(address => DepositInfo[]) public depositInfo;
    // mapping(address => bool) public userExistance;
    // address[] public users;

    IBEP20 public global;
    IGlobalMasterChef public globalMasterChef;

    uint256 public constant DUST = 1000;
    uint256 public constant LOCKUP = 90 days;

    uint256 public totalDeposited; // Total deposited amount in smart contract
    uint256 public globalBalance; // Total reward amount accumulated in smart contract

    mapping(address => uint256) public userTotalDeposited; // Total deposited amount by user
    mapping(address => uint256) public globalEarned; // Total reward amount accumulated by user

    // struct StatisticData {
    // 	uint256 totalApproved;
    // 	uint256 totalRewarded;
    // 	uint256 totalStakedForEarn;
    // 	uint256 totalWithdrawn;
    // }
    // uint256 public lastRewardHour;
    uint256 public rewardRatePerHour;
    // uint256[] rewardPerDaySeries;
    struct RewardInfo {
        uint256 amount;
        uint256 rewardCalMoment;
    }
    mapping(address => RewardInfo[]) public rewardInfo;

    event Deposited(address indexed _user, uint256 _amount);
    event RewardDeposited(address indexed _user, uint256 _amount);
    event WithdrawDeposited(address indexed _user, uint256 _amount);
    event RewadPaid(address indexed _user, uint256 _amount);
    event DistributedGlobal(uint256 globalAmount);

    constructor(address _global, address _globalMasterChef) public {
        global = IBEP20(_global);
        globalMasterChef = IGlobalMasterChef(_globalMasterChef);

        minGlobalAmountToDeposit = 100e18;
        globalBalance = 0;
    }

    function rewardsByUserPerDay(address _address) private {
        uint256 rewardPercentage = userTotalDeposited[_address]
            .div(totalDeposited)
            .mul(100);
        uint256 rewardPerDay = rewardPercentage
            .mul(globalBalance)
            .mul(rewardRatePerHour)
            .mul(24)
            .div(100);
        rewardInfo[msg.sender].push(
            RewardInfo({amount: rewardPerDay, rewardCalMoment: block.timestamp})
        );
    }

    // function globalToEarn(address _account) public view returns (uint256) {
    //     if (userTotalDeposited[_account] > 0) {
    //         return globalEarned[_account];
    //     } else {
    //         return 0;
    //     }
    // }

    function deposit(uint256 _amount) public nonReentrant {
        require(
            _amount >= minGlobalAmountToDeposit,
            "Deposit Amount is less than min Amount."
        );
        global.safeTransferFrom(msg.sender, address(this), _amount);
        depositInfo[msg.sender].push(
            DepositInfo({
                amount: _amount,
                nextWithdrawal: block.timestamp.add(LOCKUP)
            })
        );
        global.approve(address(globalMasterChef), _amount);
        globalMasterChef.enterStaking(_amount);

        // if (userExistance[msg.sender] == false) {
        //     users.push(msg.sender);
        // }

        totalDeposited = totalDeposited.add(_amount);
        userTotalDeposited[msg.sender] = userTotalDeposited[msg.sender].add(
            _amount
        );
        // uint256 globalEarnedUntilNow = rewardByUser(msg.sender);
        // globalEarned[msg.sender] = globalEarned[msg.sender].add(
        //     globalEarnedUntilNow
        // );

        // if (globalToEarn(msg.sender) == 0) {
        //     globalEarned[msg.sender] = 0;
        // }

        // userExistance[msg.sender] = true;
        emit Deposited(msg.sender, _amount);
    }

    function rewardByUser(address _address) private returns (uint256) {
        uint256 rewardPercentage;
        uint256 globalRewardToUser;
        rewardPercentage = userTotalDeposited[_address].mul(100).div(
            totalDeposited
        );
        globalRewardToUser = globalBalance.mul(rewardPercentage).div(100).div(
            20
        );
        globalEarned[_address] = globalEarned[_address].add(globalRewardToUser);
        return globalEarned[_address];
    }

    function depositRewards(uint256 _amount) public onlyDepositories {
        globalBalance = globalBalance.add(_admount);
        globalEarned[msg.sender] = globalEarned[msg.sender].sub(_amount);
        deposit(_amount);
        emit RewardDeposited(msg.sender, _amount);
    }

    function withdrawRewards(uint256 _earnedGlobal) private {
        global.safeTransfer(msg.sender, _earnedGlobal);
        emit RewardPaid(msg.sender, _earnedGlobal);
    }

    function claim() external nonReentrant {
        uint256 earnedGlobal = globalToEarn(msg.sender);
        require(
            earnedGlobal > DUST,
            "Earned Amount is less than minimum claimable Amount."
        );
        withdrawRewards(earnedGlobal);
        delete globalEarned[msg.sender];
        userTotalDeposited[msg.sender] = userTotalDeposited[msg.sender].sub(
            earnedGlobal
        );
    }

    function withdraw() external nonReentrant {
        uint256 amount = availableAmountForWithdraw(
            block.timestamp,
            msg.sender
        );
        require(amount > 0, "VaultLocked: No available to withdraw.");
        uint256 earnedGlobal = globalToEarn(msg.sender);
        globalMasterChef.leaveStaking(amount);
        global.safeTransfer(msg.sender, amount);
        withdrawRewards(earnedGlobal);
        totalDeposited = totalDeposited.sub(amount);
        userTotalDeposited[msg.sender] = userTotalDeposited[msg.sender].sub(
            amount
        );

        emit WithdrawDeposited(msg.sender, amount);
    }

    function removeAvailableDeposits(address _address) private {
        uint256 btimeStamp = block.timestamp;

        while (
            depositInfo[_address].length > 0 &&
            depositInfo[_address][0].nextWithdrawable < btimeStamp
        ) {
            for (uint256 i = 0; i < depositInfo[_address].length - 1; i++) {
                depositInfo[_address][i] = depositInfo[_address][i + 1];
            }
            depositInfo[_address].pop();
        }
    }

    function availableAmountForWithdraw(uint256 _time, address _address)
        public
        view
        returns (uint256 totalAmount)
    {
        totalAmount = 0;
        DepositInfo[] memory myDeposits = depositInfo[_address];
        for (uint256 i = 0; i < myDeposits.length; i++) {
            if (myDeposits[i].nextWithdrwal < _time) {
                totalAmount = totalAmount.add(myDeposits[i].amount);
            }
        }
    }

    // function availableForWithdrawAndPopFromDeposits(
    //     uint256 _time,
    //     address _address
    // ) public view returns (uint256 totalAmount) {
    //     totalAmount = 0;
    //     uint256 offset = 0;

    //     DepositInfo[] memory myDeposits = depositInfo[_address];
    //     require(
    //         myDeposits.length > 0,
    //         "VaultLocked: There is no deposit from current address"
    //     );
    //     for (uint256 i = 0; i < myDeposits.length; i++) {
    //         if (myDeposits[i].nextWithdrawable < _time) {
    //             totalAmount = totalAmount.add(myDeposits[i].amount);
    //             offset++;
    //         } else {
    //             myDeposits[i - offset] = myDeposits[i];
    //         }
    //     }
    //     for (uint256 j = 0; j < offset; j++) {
    //         myDeposits.pop();
    //     }
    // }

    function getTotalDepositedAmountByUser(address _address)
        public
        view
        returns (uint256)
    {
        return userTotalDeposited[_address];
    }
}
