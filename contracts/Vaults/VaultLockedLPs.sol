// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Libraries/SafeBEP20.sol";
import "../Libraries/Math.sol";
import "../Modifiers/Ownable.sol";
import "../Modifiers/Trusted.sol";
import "../Modifiers/ReentrancyGuard.sol";
import "../IGlobalMasterChef.sol";

contract VaultLockedLPs is Ownable, ReentrancyGuard, Trusted {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;
    using SafeMath for uint16;

    struct DepositInfo {
        uint256 pid;
        uint256 amount;
        uint256 lockupPeriod;
        uint256 nextWithdraw;
        uint256[] extraRewardsPercents;
    }

    mapping(address => mapping(uint256 => DepositInfo[])) public depositInfo;
    mapping(uint256 => mapping(address => uint256)) public userInfo;
    mapping(uint256 => address[]) public usersWithDeposit;

    uint256[] public extraRewardsPercents;

    IBEP20 public global; // Public vars
    IGlobalMasterChef public globalMasterChef;
    address public treasuryLP;

    bool public noFees = false;

    uint256 public lockupX = 6480000; //default lockup of 2.5 months
    uint256 public lockupY = 12960000; //default lockup of 5 months
    uint256 public lockupZ = 19440000; //default lockup of 7.5 months

    mapping(uint256 => uint256) public totalSupply;

    // Fee to withdraw the locked Lp tokens
    uint256 public rateOfWithdrawFee = 3000; // 30%
    uint256 public constant MAX_WITHDRAW_FEE = 4000;

    event Deposited(address indexed _user, uint256 _amount);
    event Withdrawn(address indexed _user, uint256 _amount);

    constructor(address _global, address _globalMasterChef) public {
        global = IBEP20(_global);
        globalMasterChef = IGlobalMasterChef(_globalMasterChef);

        extraRewardsPercents.push(1800); // 18%
        extraRewardsPercents.push(3500); // 35%
        extraRewardsPercents.push(6700); // 67%
    }

    function setNoFees(bool _noFees) public onlyOwner {
        noFees = _noFees;
    }

    function isUsersWithDeposit(uint256 _pid, address _user)
        public
        view
        returns (bool)
    {
        for (uint256 i = 0; i < usersWithDeposit[_pid].length; i++) {
            if (usersWithDeposit[_pid][i] == _user) {
                return true;
            }
        }
        return false;
    }

    function setLockupX(uint256 _lockupX) public onlyOwner {
        lockupX = _lockupX;
    }

    function setLockupY(uint256 _lockupY) public onlyOwner {
        lockupY = _lockupY;
    }

    function setLockupZ(uint256 _lockupZ) public onlyOwner {
        lockupZ = _lockupZ;
    }

    // Update treasuryLP address by the previous dev.
    function setTreasuryLP(address _treasuryLP) public onlyOwner {
        require(
            _treasuryLP != address(0),
            "[f] Dev: _treasuryLP can't be address(0)."
        );
        treasuryLP = _treasuryLP;
    }

    function balance(uint256 _pid) public view returns (uint256 amount) {
        (amount, ) = globalMasterChef.userInfo(_pid, address(this));
    }

    function setExtraRewardsPercent(uint256[] memory values) public onlyOwner {
        require(3 == values.length, "values are wrong");
        extraRewardsPercents[0] = values[0];
        extraRewardsPercents[1] = values[1];
        extraRewardsPercents[2] = values[2];
    }

    // Deposit LP tokens as user.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        uint256 _lockupPeriod
    ) public nonReentrant onlyHuman {
        require(
            _lockupPeriod == lockupX ||
                _lockupPeriod == lockupY ||
                _lockupPeriod == lockupZ,
            "LockUp period  is wrong"
        );

        uint256 beforeBalance;
        uint256 rewards;

        (IBEP20 lpToken, , , , , , , , , ) = globalMasterChef.poolInfo(_pid); // Simplified

        if (_amount > 0) {
            depositInfo[msg.sender][_pid].push(
                DepositInfo({
                    pid: _pid,
                    amount: _amount,
                    lockupPeriod: _lockupPeriod,
                    nextWithdraw: block.timestamp.add(_lockupPeriod),
                    extraRewardsPercents: extraRewardsPercents
                })
            );

            if (!isUsersWithDeposit(_pid, msg.sender)) {
                usersWithDeposit[_pid].push(msg.sender);
            }

            lpToken.safeTransferFrom(msg.sender, address(this), _amount);

            totalSupply[_pid] = totalSupply[_pid].add(_amount);
        }

        // Get rewards, recalculate the extra rewards for the user and transfer.
        beforeBalance = global.balanceOf(address(this));
        globalMasterChef.deposit(_pid, _amount);
        uint256 totalRewards = global.balanceOf(address(this)).sub(
            beforeBalance
        );
        rewards = (totalRewards.mul(amountOfUser(msg.sender, _pid))).div(
            totalSupply[_pid]
        );

        calculateTotalRewards(_pid, msg.sender, rewards);
        claimRewards(_pid);

        distributeRewards(_pid, global.balanceOf(address(this)));

        emit Deposited(msg.sender, _amount);
    }

    function distributeRewards(uint256 _pid, uint256 _amount) internal {
        uint256 rewards;
        for (uint256 i = 0; i < usersWithDeposit[_pid].length; i++) {
            rewards = (
                _amount.mul(amountOfUser(usersWithDeposit[_pid][i], _pid))
            ).div(totalSupply[_pid]);
            calculateTotalRewards(_pid, usersWithDeposit[_pid][i], rewards);
        }
    }

    // Calculate the average weight from the LP token amount deposited and lockup period.
    function calculateAverageWeight(address _user, uint256 _pid)
        public
        view
        returns (uint256)
    {
        DepositInfo[] memory myDeposits = depositInfo[_user][_pid];

        if (myDeposits.length == 0) return 0;

        uint256 totalValue = 0;
        uint256 totalCountOfTokens = 0;
        uint256 percent;

        for (uint256 i = 0; i < myDeposits.length; i++) {
            if (myDeposits[i].lockupPeriod == lockupX)
                percent = myDeposits[i].extraRewardsPercents[0];
            else if (myDeposits[i].lockupPeriod == lockupY)
                percent = myDeposits[i].extraRewardsPercents[1];
            else percent = myDeposits[i].extraRewardsPercents[2];

            totalCountOfTokens = totalCountOfTokens.add(myDeposits[i].amount);
            totalValue = totalValue.add(percent.mul(myDeposits[i].amount));
        }

        return totalValue.div(totalCountOfTokens);
    }

    // Calculate the extra rewards and total rewards.
    function calculateTotalRewards(
        uint256 _pid,
        address _user,
        uint256 rewards
    ) internal {
        uint256 averageWeight = calculateAverageWeight(_user, _pid);

        uint256 extraRewards = (rewards.mul(averageWeight)).div(10000);

        if (extraRewards > 0) {
            globalMasterChef.mintNativeTokens(extraRewards, address(this));

            uint256 totalRewards = rewards.add(extraRewards);

            userInfo[_pid][_user] = userInfo[_pid][_user].add(totalRewards);
        }
    }

    function claimRewards(uint256 _pid) internal {
        uint256 totalRewards = userInfo[_pid][msg.sender];

        SafeNativeTokenTransfer(msg.sender, totalRewards);

        userInfo[_pid][msg.sender] = 0;
    }

    function SafeNativeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 nativeTokenBal = global.balanceOf(address(this));
        if (_amount > nativeTokenBal) {
            global.transfer(_to, nativeTokenBal);
        } else {
            global.transfer(_to, _amount);
        }
    }

    function amountOfUser(address _user, uint256 _pid)
        public
        view
        returns (uint256 totalAmount)
    {
        totalAmount = 0;
        DepositInfo[] memory myDeposits = depositInfo[_user][_pid];
        for (uint256 i = 0; i < myDeposits.length; i++) {
            totalAmount = totalAmount.add(myDeposits[i].amount);
        }
    }

    function availableForWithdraw(
        uint256 _time,
        address _user,
        uint256 _pid
    ) public view returns (uint256 totalAmount) {
        totalAmount = 0;
        DepositInfo[] memory myDeposits = depositInfo[_user][_pid];
        for (uint256 i = 0; i < myDeposits.length; i++) {
            if (myDeposits[i].nextWithdraw < _time) {
                totalAmount = totalAmount.add(myDeposits[i].amount);
            }
        }
    }

    function withdraw(uint256 _pid, uint256 _amount)
        external
        nonReentrant
        onlyHuman
    {
        (IBEP20 lpToken, , , , , , , , , ) = globalMasterChef.poolInfo(_pid);

        uint256 beforeBalance;
        uint256 rewards;
        uint256 available = availableForWithdraw(
            block.timestamp,
            msg.sender,
            _pid
        );
        uint256 feeAmount = 0;

        if (_amount > available) {
            feeAmount = noFees
                ? 0
                : ((_amount.sub(available)).mul(rateOfWithdrawFee)).div(10000);
        }
        require(
            _amount <= amountOfUser(msg.sender, _pid),
            "Withdraw: you have not enough token to withdraw!"
        );

        // Get rewards, recalculate the extra rewards for the user and transfer.
        beforeBalance = global.balanceOf(address(this));
        globalMasterChef.withdraw(_pid, _amount);
        uint256 totalRewards = global.balanceOf(address(this)).sub(
            beforeBalance
        );
        rewards = (totalRewards.mul(amountOfUser(msg.sender, _pid))).div(
            totalSupply[_pid]
        );

        calculateTotalRewards(_pid, msg.sender, rewards);
        claimRewards(_pid);

        // Transfer the LP token to the user
        lpToken.safeTransfer(msg.sender, _amount.sub(feeAmount));
        if (feeAmount > 0) {
            lpToken.safeTransfer(treasuryLP, feeAmount);
        }

        // Remove desosit info in the array
        removeAmountFromDeposits(msg.sender, _pid, _amount);
        removeEmptyDeposits(msg.sender, _pid);

        totalSupply[_pid] = totalSupply[_pid].sub(_amount);

        emit Withdrawn(msg.sender, _amount);
    }

    function setRateOfWithdrawFee(uint256 _rateFee) public onlyOwner {
        require(_rateFee <= MAX_WITHDRAW_FEE, "Withdraw Fee: Fee is too high");

        rateOfWithdrawFee = _rateFee;
    }

    function removeAmountFromDeposits(
        address _user,
        uint256 _pid,
        uint256 _amount
    ) private {
        uint256 length = depositInfo[_user][_pid].length;

        for (uint256 i = 0; i < length; i++) {
            if (depositInfo[_user][_pid][i].amount <= _amount) {
                _amount = _amount.sub(depositInfo[_user][_pid][i].amount);
                depositInfo[_user][_pid][i].amount = 0;
            } else {
                depositInfo[_user][_pid][i].amount = depositInfo[_user][_pid][i]
                    .amount
                    .sub(_amount);
                _amount = 0;
            }

            if (_amount == 0) break;
        }
    }

    function removeEmptyDeposits(address _user, uint256 _pid) private {
        for (uint256 i = 0; i < depositInfo[_user][_pid].length; i++) {
            while (
                depositInfo[_user][_pid].length > 0 &&
                depositInfo[_user][_pid][i].amount == 0
            ) {
                for (
                    uint256 j = i;
                    j < depositInfo[_user][_pid].length - 1;
                    j++
                ) {
                    depositInfo[_user][_pid][j] = depositInfo[_user][_pid][
                        j + 1
                    ];
                }
                depositInfo[_user][_pid].pop();
            }
        }

        if (depositInfo[_user][_pid].length == 0) {
            for (uint256 i = 0; i < usersWithDeposit[_pid].length; i++) {
                if (usersWithDeposit[_pid][i] == _user) {
                    for (
                        uint256 j = i;
                        j < usersWithDeposit[_pid].length - 1;
                        j++
                    ) {
                        usersWithDeposit[_pid][j] = usersWithDeposit[_pid][
                            j + 1
                        ];
                    }
                    usersWithDeposit[_pid].pop();
                }
            }
        }
    }
}
