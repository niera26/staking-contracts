// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessControlDefaultAdminRules} from "openzeppelin/access/IAccessControlDefaultAdminRules.sol";

interface IERC20StakingPool is IAccessControlDefaultAdminRules {
    event Stake(address indexed addr, uint256 amount);
    event Unstake(address indexed addr, uint256 amount);
    event EmergencyWithdraw(address indexed addr, uint256 amount);
    event AddRewards(address indexed addr, uint256 amount, uint256 duration);
    event RemoveRewards(address indexed addr, uint256 amount);
    event Claim(address indexed addr, uint256 amount);
    event Sweep(address indexed addr, address token, uint256 amount);

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
