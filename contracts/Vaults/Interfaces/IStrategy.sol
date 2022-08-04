// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IStrategy {
    function deposit(uint256 _amount) external;

    function depositAll() external;

    function withdraw(uint256 _amount) external;

    function withdrawAll() external;

    function withdrawUnderlying(uint256 _amount) external;

    function getReward() external;

    function harvest() external;

    function totalSupply() external view returns (uint256);

    function balanceMC() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function sharesOf(address account) external view returns (uint256);

    function principalOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function withdrawableBalanceOf(address account)
        external
        view
        returns (uint256);

    function priceShare() external view returns (uint256);

    function depositedAt(address account) external view returns (uint256);

    function rewardsToken() external view returns (address);

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(
        address indexed user,
        uint256 amount,
        uint256 withdrawalFee
    );
    event ProfitPaid(address indexed user, uint256 amount);
    event Harvested(uint256 profit);
    event Recovered(address token, uint256 amount);
}
