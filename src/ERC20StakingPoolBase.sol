// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract ERC20StakingPoolBase {
    using SafeERC20 for IERC20;

    IERC20 internal immutable stakingToken;
    IERC20 internal immutable rewardToken;

    // numbers of both tokens stored in the pool (differs from contract balance).
    // allows to sweep accidental transfer to the contract.
    // also stacked amount is used for the rewards per token computation.
    uint256 internal stakedAmountStored;
    uint256 internal rewardAmountStored;

    // map address to stake data.
    mapping(address => StakeData) internal addressToStakeData;

    // ever growing accumulated value of rewards per token.
    // every time distribiton computation is updated the current rewards per
    // token value is added to this.
    uint256 private rewardsPerTokenAcc;

    // amount of rewards to distribute between starting and ending points.
    uint256 private rewardsAmount;
    uint256 private distributionStartingTime;
    uint256 private distributionEndingTime;

    // constants used for the computation.
    // scales allow to normalize both tokens to 18 decimals.
    uint256 private constant precision = 1e18;
    uint256 private immutable stakingScale;
    uint256 private immutable rewardsScale;

    // some constant for max distribution amount and duration.
    uint256 public constant maxRewardsAmountBase = 1_000_000_000;
    uint256 public constant maxRewardsDuration = 365 days;
    uint256 public immutable maxRewardsAmount;

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
    constructor(address _stakingToken, address _rewardToken) {
        uint8 stakingTokenDecimals = IERC20Metadata(_stakingToken).decimals();
        uint8 rewardTokenDecimals = IERC20Metadata(_rewardToken).decimals();

        require(stakingTokenDecimals <= 18, "staking token has too much decimals (> 18)");
        require(rewardTokenDecimals <= 18, "rewards token has too much decimals (> 18)");

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);

        stakingScale = 10 ** (18 - stakingTokenDecimals);
        rewardsScale = 10 ** (18 - rewardTokenDecimals);

        maxRewardsAmount = maxRewardsAmountBase * (10 ** rewardTokenDecimals);
    }

    /**
     * The duration of the current distribution.
     */
    function _duration() internal view returns (uint256) {
        if (distributionStartingTime > distributionEndingTime) return 0;

        return distributionEndingTime - distributionStartingTime;
    }

    /**
     * The number of seconds until the end of the distribution.
     */
    function _remainingSeconds() internal view returns (uint256) {
        if (distributionEndingTime < block.timestamp) return 0;

        return distributionEndingTime - block.timestamp;
    }

    /**
     * Amount of rewards remaining to be distributed for the current distribution.
     */
    function _remainingRewards() internal view returns (uint256) {
        uint256 duration = _duration();

        if (duration == 0) return 0;

        return (_remainingSeconds() * rewardsAmount) / duration;
    }

    /**
     * The number of rewards per staked token.
     * Increases every second until end of current distribution.
     * Doing all computations here to be as precise as possible.
     */
    function _rewardsPerToken() internal view returns (uint256) {
        if (stakedAmountStored == 0) return rewardsPerTokenAcc;

        uint256 duration = _duration();

        if (duration == 0) return rewardsPerTokenAcc;

        uint256 total = rewardsAmount * _duration();
        uint256 remaining = rewardsAmount * _remainingSeconds();

        if (total < remaining) return rewardsPerTokenAcc;

        uint256 distributed = total - remaining;
        uint256 scaledStakedAmount = stakedAmountStored * stakingScale * duration;
        uint256 scaledDistributedRewards = distributed * rewardsScale * precision;

        return rewardsPerTokenAcc + (scaledDistributedRewards / scaledStakedAmount);
    }

    /**
     * Pending rewards of the given stake.
     */
    function _pendingRewards(StakeData memory stakeData) internal view returns (uint256) {
        uint256 rewardsPerToken = _rewardsPerToken() - stakeData.lastRewardsPerToken;

        uint256 stakeRewards = rewardsPerToken * stakeData.amount * stakingScale;

        return stakeData.earned + (stakeRewards / (rewardsScale * precision));
    }

    /**
     * Accumulate the pending rewards of the given stake.
     * Set its last rewards per token to the current value so those rewards cant be earned again.
     * Returns the value earned by the stake.
     */
    function _earnRewards(StakeData storage stakeData) internal {
        stakeData.earned = _pendingRewards(stakeData);
        stakeData.lastRewardsPerToken = _rewardsPerToken();
    }

    /**
     * Starts a new distribution from now.
     * - First accumulates the current rewards per tokens.
     * - When the distribution is not active (= there is no token staked) just keep the same
     *   rewards amount and duration and translate start and stop to now.
     * - When the distribution is active (= there is staked tokens) then start a new distribution
     *   starting now with remaining rewards and remaining seconds.
     */
    function _startNewDistribution() internal {
        rewardsPerTokenAcc = _rewardsPerToken();

        bool isActive = stakedAmountStored > 0;

        if (isActive) rewardsAmount = _remainingRewards();

        uint256 duration = isActive ? _remainingSeconds() : _duration();

        distributionStartingTime = block.timestamp;
        distributionEndingTime = block.timestamp + duration;
    }

    /**
     * Starts a new distribution and increase the total amount of staked tokens.
     *
     * It *must* be used to add staking tokens to the pool.
     */
    function _increaseTotalStaked(StakeData storage stakeData, uint256 amount) internal {
        _startNewDistribution();

        stakedAmountStored += amount;
        stakeData.amount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit TokenStacked(msg.sender, amount);

        // should never happend but why not make sure.
        uint256 totalDuration = _duration();

        require(totalDuration == 0 || stakedAmountStored <= (type(uint256).max / (stakingScale * totalDuration)));
    }

    /**
     * Starts a new distribution and increase the total amount of staked tokens.
     *
     * It *must* be used to remove staking tokens from the pool.
     */
    function _decreaseTotalStaked(StakeData storage stakeData, uint256 amount) internal {
        _startNewDistribution();

        stakedAmountStored -= amount;
        stakeData.amount -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit TokenUnstacked(msg.sender, amount);
    }

    /**
     * Starts a new distribution and adds the given amount and duration.
     *
     * It *must* be used to add rewards to the pool.
     */
    function _addRewards(uint256 amount, uint256 duration) internal {
        _startNewDistribution();

        rewardsAmount += amount;
        distributionEndingTime += duration;

        rewardAmountStored += amount;
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsAdded(amount, duration);

        // should never happend but why not make sure.
        uint256 totalDuration = _duration();

        assert(totalDuration == 0 || rewardsAmount <= (type(uint256).max / (rewardsScale * totalDuration * precision)));
    }

    /**
     * Transfers back all currently distributed rewards.
     *
     * It *must* be used to remove rewards from the pool.
     */
    function _removeRewards() internal {
        _startNewDistribution();

        uint256 amount = rewardsAmount;

        if (amount > 0) {
            rewardsAmount = 0;
            distributionStartingTime = block.timestamp;
            distributionEndingTime = block.timestamp;

            rewardAmountStored -= amount;
            rewardToken.safeTransfer(msg.sender, amount);
            emit RewardsRemoved(amount);
        }
    }

    /**
     * Transfers to the given stake the rewards it earned.
     *
     * It *must* be used to to remove stake rewards from the pool.
     */
    function _claimEarnedRewards(StakeData storage stakeData) internal {
        uint256 earned = stakeData.earned;

        if (earned > 0) {
            stakeData.earned = 0;
            rewardAmountStored -= earned;
            rewardToken.safeTransfer(msg.sender, earned);
            emit RewardsClaimed(msg.sender, earned);
        }
    }
}
