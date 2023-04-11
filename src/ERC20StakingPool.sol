// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC20StakingPool is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 private immutable stakingToken;
    IERC20 private immutable rewardToken;

    // numbers of both tokens stored in the pool (differs from contract balance).
    // allows to sweep accidental transfer to the contract.
    // also stacked amount is used for the rewards per token computation.
    uint256 private stakedAmountStored;
    uint256 private rewardAmountStored;

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
    uint256 public constant maxRewardsAmount = 1_000_000_000 * 1e18;
    uint256 public constant maxRewardsDuration = 365 days;

    // map address to stake data.
    mapping(address => StakeData) private addressToStakeData;

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

    // custom errors.
    error ZeroAmount();
    error ZeroDuration();
    error TooMuchDecimals(address token, uint8 decimals);
    error RewardsAmountTooLarge(uint256 max, uint256 amount);
    error RewardsDurationTooLarge(uint256 max, uint256 amount);
    error InsufficientStakedAmount(uint256 staked, uint256 amount);

    /**
     * Both tokens must have decimals exposed.
     */
    constructor(address _stakingToken, address _rewardToken) {
        uint8 stakingTokenDecimals = IERC20Metadata(_stakingToken).decimals();
        uint8 rewardTokenDecimals = IERC20Metadata(_rewardToken).decimals();

        if (stakingTokenDecimals > 18) revert TooMuchDecimals(_stakingToken, stakingTokenDecimals);
        if (rewardTokenDecimals > 18) revert TooMuchDecimals(_rewardToken, rewardTokenDecimals);

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);

        stakingScale = 10 ** (18 - stakingTokenDecimals);
        rewardsScale = 10 ** (18 - rewardTokenDecimals);
    }

    /**
     * Current number of staked token stored in the pool (going in stake and out of unstake)
     */
    function totalStaked() external view returns (uint256) {
        return stakedAmountStored;
    }

    /**
     * Current number of rewards token stored in the pool (going in addRewards and out of claim)
     */
    function totalRewards() external view returns (uint256) {
        return rewardAmountStored;
    }

    /**
     * Amount of rewards remaining to distribute.
     */
    function remainingRewards() external view returns (uint256) {
        return _remainingRewards() / rewardsScale;
    }

    /**
     * Return whether the rewards are being distributed.
     */
    function isDistributing() external view returns (bool) {
        return stakedAmountStored > 0 && _remainingRewards() > 0;
    }

    /**
     * Timestamp of when distribution ends.
     */
    function endOfDistribution() external view returns (uint256) {
        return distributionEndingTime;
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
     * If Everything is unstaked, automatically claim the rewards.
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        if (amount > stakeData.amount) revert InsufficientStakedAmount(stakeData.amount, amount);

        _earnRewards(stakeData);
        _decreaseTotalStaked(stakeData, amount);

        if (stakeData.amount == 0) {
            _claimEarnedRewards(stakeData);
        }

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
    function addRewards(uint256 amount, uint256 duration) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();

        uint256 maxRewardsAmountScaled = maxRewardsAmount / rewardsScale;

        if (amount > maxRewardsAmountScaled) revert RewardsAmountTooLarge(maxRewardsAmountScaled, amount);
        if (duration > maxRewardsDuration) revert RewardsDurationTooLarge(maxRewardsDuration, duration);

        _addRewards(amount, duration);

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }

    /**
     * Remove currently distributed rewards from the pool and transfer it back to owner.
     */
    function removeRewards() external onlyOwner {
        _removeRewards();

        assert(stakingToken.balanceOf(address(this)) >= stakedAmountStored);
        assert(rewardToken.balanceOf(address(this)) >= rewardAmountStored);
    }

    /**
     * Pause the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * Unpause the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * Allow owner to sweep any token accidently sent to this contract.
     * Staked token and rewards token can be sweeped up to the amount stored in the pool.
     */
    function sweep(address token) external onlyOwner {
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

    /**
     * Make sure the given timestamp is not greater than last distribution ending time.
     */
    function _cappedByEndingTime(uint256 timestamp) internal view returns (uint256) {
        return timestamp < distributionEndingTime ? timestamp : distributionEndingTime;
    }

    /**
     * Returns the duration of the current distribution.
     */
    function _duration() internal view returns (uint256) {
        return distributionEndingTime - _cappedByEndingTime(distributionStartingTime);
    }

    /**
     * Amount of rewards for the given duration.
     * Doing this way causes less dust than a rewards rate.
     */
    function _rewardAmountFor(uint256 duration) internal view returns (uint256) {
        uint256 totalDuration = _duration();

        return totalDuration == 0 ? 0 : (duration * rewardsAmount) / totalDuration;
    }

    /**
     * Amount of rewards that has been distributed so far for the current distribution.
     */
    function _distributedRewards() internal view returns (uint256) {
        return _rewardAmountFor(_cappedByEndingTime(block.timestamp) - distributionStartingTime);
    }

    /**
     * Amount of rewards yet to be distributed for the current distribution.
     */
    function _remainingRewards() internal view returns (uint256) {
        return _rewardAmountFor(distributionEndingTime - _cappedByEndingTime(block.timestamp));
    }

    /**
     * The number of rewards per staked token.
     * Increases every second until end of current distribution.
     */
    function _rewardsPerToken() internal view returns (uint256) {
        if (stakedAmountStored == 0) return rewardsPerTokenAcc;

        uint256 distributedRewards = _distributedRewards() * precision;

        return rewardsPerTokenAcc + (distributedRewards / (stakedAmountStored * stakingScale));
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
     * Starts a new distribution.
     * Accumulates the current rewards per tokens.
     * If theres no staked tokens, translate the last distribution times to now.
     * If theres staked tokens, starts a new distribution with the remaining rewards.
     */
    function _startNewDistribution() internal {
        rewardsPerTokenAcc = _rewardsPerToken();

        if (stakedAmountStored == 0) {
            // translate any unfinished distribution to now.
            uint256 duration = _duration();
            distributionStartingTime = block.timestamp;
            distributionEndingTime = block.timestamp + duration;
        } else {
            // distribute the remaining rewards from now to end of distribution.
            rewardsAmount = _remainingRewards();
            distributionStartingTime = _cappedByEndingTime(block.timestamp);
        }
    }

    /**
     * Starts a new distribution and increase the total amount of staked tokens.
     *
     * It *must* be used to increase the amount tokens staked in the pool.
     */
    function _increaseTotalStaked(StakeData storage stakeData, uint256 amount) internal {
        _startNewDistribution();

        stakedAmountStored += amount;
        stakeData.amount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit TokenStacked(msg.sender, amount);
    }

    /**
     * Starts a new distribution and increase the total amount of staked tokens.
     *
     * It *must* be used to increase the amount tokens staked in the pool.
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

        rewardsAmount += (amount * rewardsScale);
        distributionEndingTime += duration;

        rewardAmountStored += amount;
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsAdded(amount, duration);

        // should never happend but why not.
        assert(rewardsAmount <= (type(uint256).max / duration));
        assert(rewardsAmount <= (type(uint256).max / precision));
    }

    /**
     * Transfers back all currently distributed rewards.
     *
     * It *must* be used to remove rewards from the pool.
     */
    function _removeRewards() internal {
        _startNewDistribution();

        uint256 amount = rewardsAmount / rewardsScale;

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
