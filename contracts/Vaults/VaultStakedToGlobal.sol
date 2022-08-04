// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import "../Modifiers/ReentrancyGuard.sol";
import "../Modifiers/RewarderRestriction.sol";
import "../IGlobalMasterChef.sol";
import "../IRouterV2.sol";
import "./Interfaces/IDistributable.sol";

contract VaultStakedToGlobal is
    IDistributable,
    ReentrancyGuard,
    RewarderRestriction
{
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;
    using SafeMath for uint16;

    IBEP20 public global;
    IBEP20 public wbnb;
    IGlobalMasterChef public globalMasterChef;
    IRouterV2 public globalRouter;

    uint256 public constant DUST = 1000;
    uint256 private constant SLIPPAGE = 9500;

    uint256 public pid;
    uint256 public minTokenAmountToDistribute;
    address[] public users;
    mapping(address => uint256) public principal;
    mapping(address => uint256) public wbnbEarned;
    uint256 public totalSupply;
    uint256 public wbnbBalance;

    event Deposited(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount);
    event RewardPaid(address indexed _user, uint256 _amount);

    constructor(
        address _global,
        address _wbnb,
        address _globalMasterChef,
        address _globalRouter
    ) public {
        pid = 0;

        global = IBEP20(_global);
        wbnb = IBEP20(_wbnb);
        wbnbBalance = 0;

        globalMasterChef = IGlobalMasterChef(_globalMasterChef);

        minTokenAmountToDistribute = 1e18; // 1 BEP20 Token

        globalRouter = IRouterV2(_globalRouter);
    }

    function triggerDistribute(uint256 _amount)
        external
        override
        nonReentrant
        onlyRewarders
    {
        wbnbBalance = wbnbBalance.add(_amount);

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

    function getUsersLength() public view returns (uint256) {
        return users.length;
    }

    function earned(address _account) public view returns (uint256) {
        if (principalOf(_account) > 0) {
            return wbnbEarned[_account];
        } else {
            return 0;
        }
    }

    function stakingToken() external view returns (address) {
        return address(global);
    }

    function rewardsToken() external view returns (address) {
        return address(wbnb);
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
            wbnbEarned[msg.sender] = 0;
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
        delete wbnbEarned[msg.sender];

        emit Withdrawn(msg.sender, amount);
    }

    function getReward() external nonReentrant {
        uint256 earnedAmount = earned(msg.sender);
        handleRewards(earnedAmount);
        delete wbnbEarned[msg.sender];
    }

    function handleRewards(uint256 _earned) private {
        if (_earned < DUST) {
            return; // No rewards
        }

        address[] memory pathToGlobal = new address[](2);
        pathToGlobal[0] = address(wbnb);
        pathToGlobal[1] = address(global);

        // Swaps BNB to GLOBAL and sends to user
        uint256[] memory amountsPredicted = globalRouter.getAmountsOut(
            _earned,
            pathToGlobal
        );
        uint256[] memory amounts = globalRouter.swapExactTokensForTokens(
            _earned,
            (amountsPredicted[amountsPredicted.length - 1].mul(SLIPPAGE)).div(
                10000
            ),
            pathToGlobal,
            msg.sender,
            block.timestamp
        );

        emit RewardPaid(msg.sender, amounts[amounts.length - 1]);
    }

    function _deleteUser(address _account) private {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == _account) {
                for (uint256 j = i; j < users.length - 1; j++) {
                    users[j] = users[j + 1];
                }
                users.pop();
            }
        }
    }

    function _distribute() private {
        uint256 wbnbAmountToDistribute = wbnbBalance;

        if (wbnbAmountToDistribute < minTokenAmountToDistribute) {
            // Nothing to distribute.
            return;
        }

        for (uint256 i = 0; i < users.length; i++) {
            uint256 userPercentage = principalOf(users[i]).mul(100).div(
                totalSupply
            );
            uint256 wbnbToUser = wbnbAmountToDistribute.mul(userPercentage).div(
                100
            );
            wbnbBalance = wbnbBalance.sub(wbnbToUser);

            wbnbEarned[users[i]] = wbnbEarned[users[i]].add(wbnbToUser);
        }

        emit Distributed(wbnbAmountToDistribute.sub(wbnbBalance));
    }
}
