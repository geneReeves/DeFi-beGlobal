// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IDistributable {
    function triggerDistribute(uint256 _amount) external;

    function balance() external view returns (uint256 amount);

    event Distributed(uint256 _distributedAmount);
}
