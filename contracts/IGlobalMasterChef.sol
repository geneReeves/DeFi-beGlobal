// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
import "./Tokens/IBEP20.sol";

interface IGlobalMasterChef {
    function userInfo(uint256 _pid, address _account)
        external
        view
        returns (uint256 amount, uint256 rewardDebt);

    function poolInfo(uint256 _id)
        external
        view
        returns (
            IBEP20 lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accNativeTokenPerShare,
            uint256 harvestInterval,
            uint256 maxWithdrawalInterval,
            uint16 withDrawalFeeOfLpsBurn,
            uint16 withDrawalFeeOfLpsTeam,
            uint16 performanceFeesOfNativeTokensBurn,
            uint16 performanceFeesOfNativeTokensToLockedVault
        );

    function mintNativeTokens(uint256 _quantityToMint, address userFor)
        external;

    // Staking into CAKE pools (pid = 0)
    function enterStaking(uint256 _amount) external;

    function leaveStaking(uint256 _amount) external;

    // Staking other tokens or LP (pid != 0)
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;
}
