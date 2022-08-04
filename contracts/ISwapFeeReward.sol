// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface ISwapFeeReward {
    function swap(
        address account,
        address input,
        address output,
        uint256 amount
    ) external returns (bool);
}
