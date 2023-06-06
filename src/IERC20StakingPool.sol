// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20StakingPoolEvents {
    event TokenStacked(address indexed addr, uint256 amount);
    event TokenUnstacked(address indexed addr, uint256 amount);
    event EmergencyWithdraw(address indexed addr, uint256 amount);
    event RewardsAdded(address indexed addr, uint256 amount, uint256 duration);
    event RewardsRemoved(address indexed addr, uint256 amount);
    event RewardsClaimed(address indexed addr, uint256 amount);
    event Swept(address indexed addr, address token, uint256 amount);
}

interface IERC20StakingPool is IERC20StakingPoolEvents {
    function remainingRewards() external view returns (uint256);
    function remainingSeconds() external view returns (uint256);
    function staked(address addr) external view returns (uint256);
    function pendingRewards(address addr) external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim() external;
    function emergencyWithdraw() external;
    function addRewards(uint256 amount, uint256 duration) external;
    function removeRewards() external;
    function pause() external;
    function unpause() external;
    function sweep(address token) external;
}
