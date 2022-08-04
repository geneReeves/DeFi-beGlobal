// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import "../Modifiers/ReentrancyGuard.sol";
import "../Modifiers/RewarderRestriction.sol";
import "../IGlobalMasterChef.sol";
import "./Interfaces/IDistributable.sol";

contract VaultStaked is IDistributable, ReentrancyGuard, RewarderRestriction {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;
    using SafeMath for uint16;

    IBEP20 public global;
    IBEP20 public bnb;
    IGlobalMasterChef public globalMasterChef;

    uint256 public constant DUST = 1000;

    uint256 public pid;
    uint256 public minTokenAmountToDistribute;
    address[] public users;
    mapping(address => uint256) public principal;
    mapping(address => uint256) public bnbEarned;
    uint256 public totalSupply;
    uint256 public bnbBalance;

    event Deposited(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount);
    event RewardPaid(address indexed _user, uint256 _amount);

    constructor(
        address _global,
        address _bnb,
        address _globalMasterChef
    ) public {
        pid = 0;

        global = IBEP20(_global);
        bnb = IBEP20(_bnb);
        bnbBalance = 0;

        globalMasterChef = IGlobalMasterChef(_globalMasterChef);

        minTokenAmountToDistribute = 1e18; // 1 BEP20 Token
    }

    function triggerDistribute(uint256 _amount)
        external
        override
        nonReentrant
        onlyRewarders
    {
        bnbBalance = bnbBalance.add(_amount);

        _distribute();
    }

    function balance() external view override returns (uint256 amount) {
        (amount, ) = globalMasterChef.userInfo(pid, address(this));
    }

    function balanceOf(address _account) public view returns (uint256) {
        if (totalSupply == 0) return 0;
        return principalOf(_account);
    }

    function principalOf(address _account) public view returns (uint256) {
        return principal[_account];
    }

    function earned(address _account) public view returns (uint256) {
        if (principalOf(_account) > 0) {
            return bnbEarned[_account];
        } else {
            return 0;
        }
    }

    function getUsersLength() public view returns (uint256) {
        return users.length;
    }

    function stakingToken() external view returns (address) {
        return address(global);
    }

    function rewardsToken() external view returns (address) {
        return address(bnb);
    }

    // Deposit globals.
    function deposit(uint256 _amount) public nonReentrant {
        bool userExists = false;
        global.safeTransferFrom(msg.sender, address(this), _amount);

        global.approve(address(globalMasterChef), _amount);
        globalMasterChef.enterStaking(_amount);

        for (uint256 j = 0; j < users.length; j++) {
            if (users[j] == msg.sender) {
                userExists = true;
                break;
            }
        }
        if (!userExists) {
            users.push(msg.sender);
        }

        totalSupply = totalSupply.add(_amount);
        principal[msg.sender] = principal[msg.sender].add(_amount);

        if (earned(msg.sender) == 0) {
            bnbEarned[msg.sender] = 0;
        }

        emit Deposited(msg.sender, _amount);
    }

    // Withdraw all only
    function withdraw() external nonReentrant {
        uint256 amount = balanceOf(msg.sender);
        uint256 earnedAmount = earned(msg.sender);

        globalMasterChef.leaveStaking(amount);
        global.safeTransfer(msg.sender, amount);
        handleRewards(earnedAmount);
        totalSupply = totalSupply.sub(amount);
        _deleteUser(msg.sender);
        delete principal[msg.sender];
        delete bnbEarned[msg.sender];

        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external nonReentrant {
        uint256 earnedAmount = earned(msg.sender);
        handleRewards(earnedAmount);
        delete bnbEarned[msg.sender];
    }

    function handleRewards(uint256 _earned) private {
        if (_earned < DUST) {
            return; // No rewards
        }

        bnb.safeTransfer(msg.sender, _earned);

        emit RewardPaid(msg.sender, _earned);
    }

    function _deleteUser(address _account) private {
        for (uint8 i = 0; i < users.length; i++) {
            if (users[i] == _account) {
                for (uint256 j = i; j < users.length - 1; j++) {
                    users[j] = users[j + 1];
                }
                users.pop();
            }
        }
    }

    function _distribute() private {
        uint256 bnbAmountToDistribute = bnbBalance;

        if (bnbAmountToDistribute < minTokenAmountToDistribute) {
            // Nothing to distribute.
            return;
        }

        for (uint256 i = 0; i < users.length; i++) {
            uint256 userPercentage = principalOf(users[i]).mul(100).div(
                totalSupply
            );
            uint256 bnbToUser = bnbAmountToDistribute.mul(userPercentage).div(
                100
            );
            bnbBalance = bnbBalance.sub(bnbToUser);

            bnbEarned[users[i]] = bnbEarned[users[i]].add(bnbToUser);
        }

        emit Distributed(bnbAmountToDistribute.sub(bnbBalance));
    }
}
