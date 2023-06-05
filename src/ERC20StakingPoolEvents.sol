// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library ERC20StakingPoolEvents {
    event TokenStacked(address indexed addr, uint256 amount);
    event TokenUnstacked(address indexed addr, uint256 amount);
    event EmergencyWithdraw(address indexed addr, uint256 amount);
    event RewardsAdded(address indexed addr, uint256 amount, uint256 duration);
    event RewardsRemoved(address indexed addr, uint256 amount);
    event RewardsClaimed(address indexed addr, uint256 amount);
    event Swept(address indexed addr, address token, uint256 amount);
}
