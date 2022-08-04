// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Vaults/Interfaces/IDistributable.sol";

contract BeneficiaryMock is IDistributable {
    function triggerDistribute(uint256 _amount) external override {
        emit Distributed(1e18);
    }

    function balance() external view override returns (uint256 amount) {
        amount = 1;
    }
}
