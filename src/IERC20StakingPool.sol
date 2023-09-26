// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessControlDefaultAdminRules} from "openzeppelin/access/IAccessControlDefaultAdminRules.sol";
import {IERC20Metadata} from "openzeppelin/interfaces/IERC20Metadata.sol";

interface IERC20StakingPool is IAccessControlDefaultAdminRules {
    event StakeTokens(address indexed addr, uint256 amount);
    event UnstakeTokens(address indexed addr, uint256 amount);
    event ClaimRewards(address indexed addr, uint256 amount);
    event AddRewards(address indexed addr, uint256 amount, uint256 duration);
    event RemoveRewards(address indexed addr, uint256 amount);
    event SetDurationTo(address indexed addr, uint256 duration);
    event SetDurationUntil(address indexed addr, uint256 timestamp, uint256 duration);
    event Sweep(address indexed addr, address token, uint256 amount);

    function OPERATOR_ROLE() external view returns (bytes32);
    function stakingToken() external view returns (IERC20Metadata);
    function rewardsToken() external view returns (IERC20Metadata);
    function totalStakedTokens() external view returns (uint256);
    function remainingRewards() external view returns (uint256);
    function remainingSeconds() external view returns (uint256);
    function stakedTokens(address addr) external view returns (uint256);
    function remainingRewards(address addr) external view returns (uint256);
    function pendingRewards(address addr) external view returns (uint256);
    function stakeTokens(uint256 amount) external;
    function unstakeTokens(uint256 amount) external;
    function claimRewards() external;
    function addRewards(uint256 amount, uint256 duration) external;
    function removeRewards() external;
    function setDurationTo(uint256 duration) external;
    function setDurationUntil(uint256 timestamp) external;
}
