// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20StakingPool {
    function remainingRewards() external view returns (uint256);
    function remainingSeconds() external view returns (uint256);
    function staked(address addr) external view returns (uint256);
    function pendingRewards(address addr) external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim() external;
    function emergencyWithdraw() external;
    function addRewards(uint256 amount, uint256 duration) external;
}
