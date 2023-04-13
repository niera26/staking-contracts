// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20StakingPoolBase} from "./ERC20StakingPoolBase.sol";
import {AccessControlEnumerable} from "openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC20StakingPool is AccessControlEnumerable, Pausable, ReentrancyGuard, ERC20StakingPoolBase {
    using SafeERC20 for IERC20;

    bytes32 public constant ADD_REWARDS_ROLE = keccak256("ADD_REWARDS_ROLE");

    error ZeroAmount();
    error ZeroDuration();
    error RewardsAmountTooLarge(uint256 max, uint256 amount);
    error RewardsDurationTooLarge(uint256 max, uint256 amount);
    error InsufficientStakedAmount(uint256 staked, uint256 amount);

    /**
     * Call the base constructor with the two tokens.
     */
    constructor(address _stakingToken, address _rewardToken)
        ERC20StakingPoolBase(_stakingToken, _rewardToken, 1_000_000_000, 365 days)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADD_REWARDS_ROLE, msg.sender);
    }

    /**
     * Current number of staked token stored in the pool (going in stake and out of unstake)
     */
    function totalStaked() external view returns (uint256) {
        return stakedAmountStored;
    }

    /**
     * Current number of rewards token stored in the pool (going in addRewards and out of removeRewards/claim)
     */
    function totalRewards() external view returns (uint256) {
        return rewardAmountStored;
    }

    /**
     * Amount of rewards remaining to distribute.
     */
    function remainingRewards() external view returns (uint256) {
        return _remainingRewards();
    }

    /**
     * Time remaining for this distribution.
     */
    function remainingSeconds() external view returns (uint256) {
        return _remainingSeconds();
    }

    /**
     * Staked amount of the given holder.
     */
    function staked(address addr) external view returns (uint256) {
        return addressToStakeData[addr].amount;
    }

    /**
     * Pending rewards of the given holder.
     */
    function pendingRewards(address addr) external view returns (uint256) {
        return _pendingRewards(addressToStakeData[addr]);
    }

    /**
     * Add tokens to the stake of the holder.
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);
        _increaseTotalStaked(stakeData, amount);

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }

    /**
     * Remove tokens from the stake of the holder.
     *
     * Automatically claim the rewards when everything is unstaked.
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        if (amount > stakeData.amount) revert InsufficientStakedAmount(stakeData.amount, amount);

        _earnRewards(stakeData);
        _decreaseTotalStaked(stakeData, amount);

        if (stakeData.amount == 0) _claimEarnedRewards(stakeData);

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }

    /**
     * Claim all rewards earned by the holder.
     */
    function claim() external nonReentrant whenNotPaused {
        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);
        _claimEarnedRewards(stakeData);

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }

    /**
     * Add the given amount of rewards and distribute it over the given duration.
     */
    function addRewards(uint256 amount, uint256 duration) external onlyRole(ADD_REWARDS_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();
        if (amount > maxRewardsAmount) revert RewardsAmountTooLarge(maxRewardsAmount, amount);
        if (duration > maxRewardsDuration) revert RewardsDurationTooLarge(maxRewardsDuration, duration);

        _addRewards(amount, duration);

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }

    /**
     * Remove currently distributed rewards from the pool and transfer it back to owner.
     */
    function removeRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeRewards();

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }

    /**
     * Pause the contract.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * Unpause the contract.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * Allow owner to sweep any token accidently sent to this contract.
     * Staked token and rewards token can be sweeped up to the amount stored in the pool.
     */
    function sweep(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(stakingToken)) {
            stakingToken.safeTransfer(msg.sender, stakingToken.balanceOf(address(this)) - stakedAmountStored);
        } else if (token == address(rewardToken)) {
            rewardToken.safeTransfer(msg.sender, rewardToken.balanceOf(address(this)) - rewardAmountStored);
        } else {
            IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
        }

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }
}
