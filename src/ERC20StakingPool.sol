// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControl} from "openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {ERC20StakingPoolAbstract} from "./ERC20StakingPoolAbstract.sol";

contract ERC20StakingPool is ERC20StakingPoolAbstract, AccessControl, Pausable {
    bytes32 public constant ADD_REWARDS_ROLE = keccak256("ADD_REWARDS_ROLE");

    /**
     * Grant the admin and add rewards roles to the deployer.
     */
    constructor(address _stakingToken, address _rewardToken, uint256 _maxRewardAmount, uint256 _maxRewardsDuration)
        ERC20StakingPoolAbstract(_stakingToken, _rewardToken, _maxRewardAmount, _maxRewardsDuration)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADD_REWARDS_ROLE, msg.sender);
    }

    function stake(uint256 amount) external whenNotPaused {
        _stake(amount);
    }

    function unstake(uint256 amount) external whenNotPaused {
        _unstake(amount);
    }

    function claim() external whenNotPaused {
        _claim();
    }

    function emergencyWithdraw() external {
        return _emergencyWithdraw();
    }

    function addRewards(uint256 amount, uint256 duration) external onlyRole(ADD_REWARDS_ROLE) {
        _addRewards(amount, duration);
    }

    function removeRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeRewards();
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function sweep(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _sweep(token);
    }

    function emergencyWithdrawRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _emergencyWithdrawRewards();
    }
}
