// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./IMintNotifier.sol";
import "hardhat/console.sol";

contract MintNotifier is IMintNotifier {
    event GlobalsMinted(address vaultFor, address userFor, uint256 amount);

    function notify(
        address _vaultFor,
        address _userFor,
        uint256 _amount
    ) external override {
        emit GlobalsMinted(_vaultFor, _userFor, _amount);
    }
}
