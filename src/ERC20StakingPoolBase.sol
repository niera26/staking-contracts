// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract ERC20StakingPoolBase {
    using SafeERC20 for IERC20;

    // staking and rewards tokens managed by the contract.
    IERC20 internal immutable STAKING_TOKEN;
    IERC20 internal immutable REWARDS_TOKEN;

    // constants for max reward distribution amount and duration.
    uint256 public immutable maxRewardAmount;
    uint256 public immutable maxRewardsDuration;

    // both tokens decimals - could be used by other contracts.
    uint256 public immutable stakingTokenDecimals;
    uint256 public immutable rewardsTokenDecimals;

    // numbers of both tokens stored in the pool (!= contract balance).
    // allows to sweep accidental transfer to the contract.
    // stacked amount is used for the rewards per token computation.
    uint256 public stakedAmountStored;
    uint256 public rewardAmountStored;

    // constant used to prevent divisions result in zero.
    uint256 private constant precision = 1e18;

    // constant used to normalize both tokens to 18 decimals.
    uint256 private immutable stakingScale;
    uint256 private immutable rewardsScale;

    // ever growing accumulated number of rewards per staked token.
    // every time a new distribiton starts the current rewards per token
    // value is added to this.
    uint256 private rewardsPerTokenAcc;

    // amount of rewards to distribute between starting and ending times.
    uint256 private rewardAmount;
    uint256 private startingTime;
    uint256 private endingTime;

    // mapping of address to stake data.
    mapping(address => StakeData) internal addressToStakeData;

    struct StakeData {
        uint256 amount; // amount of staked token.
        uint256 earned; // rewards earned so far and yet to claim.
        uint256 lastRewardsPerToken; // rewards per token of the last claim.
    }

    // staking events.
    event TokenStacked(address indexed addr, uint256 amount);
    event TokenUnstacked(address indexed addr, uint256 amount);

    // rewards events.
    event RewardsAdded(uint256 amount, uint256 duration);
    event RewardsRemoved(uint256 amount);
    event RewardsClaimed(address indexed addr, uint256 amount);

    /**
     * Both tokens must have decimals exposed.
     */
    constructor(address _stakingToken, address _rewardsToken, uint256 _maxRewardAmount, uint256 _maxRewardsDuration) {
        stakingTokenDecimals = IERC20Metadata(_stakingToken).decimals();
        rewardsTokenDecimals = IERC20Metadata(_rewardsToken).decimals();

        require(stakingTokenDecimals <= 18, "staking token has too much decimals (> 18)");
        require(rewardsTokenDecimals <= 18, "rewards token has too much decimals (> 18)");

        STAKING_TOKEN = IERC20(_stakingToken);
        REWARDS_TOKEN = IERC20(_rewardsToken);

        maxRewardAmount = _maxRewardAmount * (10 ** rewardsTokenDecimals);
        maxRewardsDuration = _maxRewardsDuration;

        stakingScale = 10 ** (18 - stakingTokenDecimals);
        rewardsScale = 10 ** (18 - rewardsTokenDecimals);
    }

    /**
     * The duration of the current distribution.
     */
    function _duration() internal view returns (uint256) {
        if (endingTime < startingTime) return 0;

        return endingTime - startingTime;
    }

    /**
     * The number of seconds until the end of the current distribution.
     */
    function _remainingSeconds() internal view returns (uint256) {
        if (endingTime < block.timestamp) return 0;

        return endingTime - block.timestamp;
    }

    /**
     * Amount of rewards remaining to be distributed for the current distribution.
     */
    function _remainingRewards() internal view returns (uint256) {
        uint256 duration = _duration();

        if (duration == 0) return 0;

        return (_remainingSeconds() * rewardAmount) / duration;
    }

    /**
     * The number of rewards per staked token.
     * Increases every second until end of current distribution.
     * Do not use _remainingRewards() to be as precise as possible.
     */
    function _rewardsPerToken() internal view returns (uint256) {
        if (stakedAmountStored == 0) return rewardsPerTokenAcc;

        uint256 duration = _duration();

        if (duration == 0) return rewardsPerTokenAcc;

        uint256 totalRewards = rewardAmount * _duration();
        uint256 remainingRewards = rewardAmount * _remainingSeconds();

        if (totalRewards < remainingRewards) return rewardsPerTokenAcc;

        uint256 distributedRewards = totalRewards - remainingRewards;
        uint256 scaledStakedAmount = stakedAmountStored * stakingScale * duration;
        uint256 scaledDistributedRewards = distributedRewards * rewardsScale * precision;

        return rewardsPerTokenAcc + (scaledDistributedRewards / scaledStakedAmount);
    }

    /**
     * Pending rewards of the given stake.
     */
    function _pendingRewards(StakeData memory stakeData) internal view returns (uint256) {
        uint256 rewardsPerToken = _rewardsPerToken();

        if (rewardsPerToken < stakeData.lastRewardsPerToken) return 0;

        uint256 rewardsPerTokenDiff = rewardsPerToken - stakeData.lastRewardsPerToken;

        uint256 stakeRewards = rewardsPerTokenDiff * stakeData.amount * stakingScale;

        return stakeData.earned + (stakeRewards / (rewardsScale * precision));
    }

    /**
     * Accumulate the pending rewards of the given stake.
     * Set its last rewards per token to the current one so those rewards cant be earned again.
     */
    function _earnRewards(StakeData storage stakeData) internal {
        stakeData.earned = _pendingRewards(stakeData);
        stakeData.lastRewardsPerToken = _rewardsPerToken();
    }

    /**
     * Starts a new distribution from now.
     * - First accumulates the current rewards per token.
     * - When the distribution is not active (= there is no token staked) just keep the same
     *   rewards amount and duration and translate start and stop to now.
     * - When the distribution is active (= there is staked tokens) then start a new distribution
     *   starting now with remaining rewards and remaining seconds.
     */
    function _startNewDistribution() internal {
        rewardsPerTokenAcc = _rewardsPerToken();

        bool isActive = stakedAmountStored > 0;

        if (isActive) rewardAmount = _remainingRewards();

        uint256 duration = isActive ? _remainingSeconds() : _duration();

        startingTime = block.timestamp;
        endingTime = block.timestamp + duration;
    }

    /**
     * Starts a new distribution and increase the total amount of staked tokens.
     *
     * It *must* be used to add staking tokens to the pool.
     */
    function _increaseTotalStaked(StakeData storage stakeData, uint256 amount) internal {
        _startNewDistribution();

        stakeData.amount += amount;
        stakedAmountStored += amount;
        STAKING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        emit TokenStacked(msg.sender, amount);

        // should never happend but why not make sure.
        uint256 totalDuration = _duration();

        require(totalDuration == 0 || stakedAmountStored <= (type(uint256).max / (stakingScale * totalDuration)));
    }

    /**
     * Starts a new distribution and decrease the total amount of staked tokens.
     *
     * It *must* be used to remove staking tokens from the pool.
     */
    function _decreaseTotalStaked(StakeData storage stakeData, uint256 amount) internal {
        _startNewDistribution();

        stakeData.amount -= amount;
        stakedAmountStored -= amount;
        STAKING_TOKEN.safeTransfer(msg.sender, amount);
        emit TokenUnstacked(msg.sender, amount);
    }

    /**
     * Starts a new distribution and adds the given rewards for the given duration.
     *
     * It *must* be used to add rewards to the pool.
     */
    function _addRewards(uint256 amount, uint256 duration) internal {
        _startNewDistribution();

        rewardAmount += amount;
        endingTime += duration;

        rewardAmountStored += amount;
        REWARDS_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsAdded(amount, duration);

        // should never happend but why not make sure.
        uint256 totalDuration = _duration();

        assert(totalDuration == 0 || rewardAmount <= (type(uint256).max / (rewardsScale * totalDuration * precision)));
    }

    /**
     * Transfers back all currently distributed rewards.
     *
     * It *must* be used to remove rewards from the pool.
     */
    function _removeRewards() internal {
        _startNewDistribution();

        uint256 amount = rewardAmount;

        if (amount > 0) {
            rewardAmount = 0;
            startingTime = block.timestamp;
            endingTime = block.timestamp;

            rewardAmountStored -= amount;
            REWARDS_TOKEN.safeTransfer(msg.sender, amount);
            emit RewardsRemoved(amount);
        }
    }

    /**
     * Transfers to the given stake the rewards it earned.
     *
     * It *must* be used to remove stake rewards from the pool.
     */
    function _claimEarnedRewards(StakeData storage stakeData) internal {
        uint256 earned = stakeData.earned;

        if (earned > 0) {
            stakeData.earned = 0;
            rewardAmountStored -= earned;
            REWARDS_TOKEN.safeTransfer(msg.sender, earned);
            emit RewardsClaimed(msg.sender, earned);
        }
    }
}
