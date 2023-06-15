// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessControlEnumerable} from "openzeppelin/access/IAccessControlEnumerable.sol";

interface IERC20StakingPoolEvents {
    event Stake(address indexed addr, uint256 amount);
    event Unstake(address indexed addr, uint256 amount);
    event EmergencyWithdraw(address indexed addr, uint256 amount);
    event AddRewards(address indexed addr, uint256 amount, uint256 duration);
    event RemoveRewards(address indexed addr, uint256 amount);
    event Claim(address indexed addr, uint256 amount);
    event Sweep(address indexed addr, address token, uint256 amount);
}

interface IERC20StakingPool is IERC20StakingPoolEvents, IAccessControlEnumerable {
    function maxRewardAmount() external view returns (uint256);
    function maxRewardDuration() external view returns (uint256);
    function stakingTokenAddress() external view returns (address);
    function rewardsTokenAddress() external view returns (address);
    function stakedAmountStored() external view returns (uint256);
    function rewardAmountStored() external view returns (uint256);
    function remainingRewards() external view returns (uint256);
    function remainingSeconds() external view returns (uint256);
    function staked(address addr) external view returns (uint256);
    function pendingRewards(address addr) external view returns (uint256);
    function remainingRewards(address addr) external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim() external;
    function emergencyWithdraw() external;
    function addRewards(uint256 amount, uint256 duration) external;
    function removeRewards() external;
}
