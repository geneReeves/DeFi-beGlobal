// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IBunnyChef {
    struct UserInfo {
        uint256 balance;
        uint256 pending;
        uint256 rewardPaid;
    }

    struct VaultInfo {
        address token;
        uint256 allocPoint; // How many allocation points assigned to this pool. BUNNYs to distribute per block.
        uint256 lastRewardBlock; // Last block number that BUNNYs distribution occurs.
        uint256 accBunnyPerShare; // Accumulated BUNNYs per share, times 1e12. See below.
    }

    function bunnyPerBlock() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function vaultInfoOf(address vault)
        external
        view
        returns (VaultInfo memory);

    function vaultUserInfoOf(address vault, address user)
        external
        view
        returns (UserInfo memory);

    function pendingBunny(address vault, address user)
        external
        view
        returns (uint256);

    function notifyDeposited(address user, uint256 amount) external;

    function notifyWithdrawn(address user, uint256 amount) external;

    function safeBunnyTransfer(address user) external returns (uint256);
}
