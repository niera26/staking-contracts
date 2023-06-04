// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControl} from "openzeppelin/contracts/access/AccessControl.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20StakingPool} from "./IERC20StakingPool.sol";

contract ERC20StakingPool is IERC20StakingPool, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // staking and rewards tokens managed by the contract.
    IERC20Metadata private immutable STAKING_TOKEN;
    IERC20Metadata private immutable REWARDS_TOKEN;

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

    // errors.
    error ZeroAmount();
    error ZeroDuration();
    error RewardsAmountTooLarge(uint256 max, uint256 amount);
    error RewardsDurationTooLarge(uint256 max, uint256 amount);
    error InsufficientStakedAmount(uint256 staked, uint256 amount);

    /**
     * Both tokens must have decimals exposed.
     */
    constructor(address _stakingToken, address _rewardsToken, uint256 _maxRewardAmount, uint256 _maxRewardsDuration) {
        STAKING_TOKEN = IERC20Metadata(_stakingToken);
        REWARDS_TOKEN = IERC20Metadata(_rewardsToken);

        stakingTokenDecimals = STAKING_TOKEN.decimals();
        rewardsTokenDecimals = REWARDS_TOKEN.decimals();

        require(stakingTokenDecimals <= 18, "staking token has too much decimals (> 18)");
        require(rewardsTokenDecimals <= 18, "rewards token has too much decimals (> 18)");

        maxRewardAmount = _maxRewardAmount * (10 ** rewardsTokenDecimals);
        maxRewardsDuration = _maxRewardsDuration;

        stakingScale = 10 ** (18 - stakingTokenDecimals);
        rewardsScale = 10 ** (18 - rewardsTokenDecimals);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * Amount of rewards remaining to distribute.
     */
    function remainingRewards() external view returns (uint256) {
        return _remainingRewards();
    }

    /**
     * Seconds remaining for this distribution.
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
    }

    /**
     * Claim all rewards earned by the holder.
     */
    function claim() external nonReentrant whenNotPaused {
        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);
        _claimEarnedRewards(stakeData);
    }

    /**
     * Allow to withdraw staked tokens without claming rewards, in case of emergency.
     */
    function emergencyWithdraw() external nonReentrant whenNotPaused {
        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);

        uint256 amount = stakeData.amount;
        uint256 earned = stakeData.earned;

        stakeData.amount = 0;
        stakeData.earned = 0;

        // unchecked so user can withdraw even if there's a problem with the accounting of those values.
        unchecked {
            stakedAmountStored -= amount;
            rewardAmountStored -= earned;
        }

        STAKING_TOKEN.safeTransfer(msg.sender, amount);
    }

    /**
     * Starts a new distribution and adds the given rewards for the given duration.
     *
     * It *must* be used to add rewards to the pool.
     */
    function addRewards(uint256 amount, uint256 duration) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();
        if (amount > maxRewardAmount) revert RewardsAmountTooLarge(maxRewardAmount, amount);
        if (duration > maxRewardsDuration) revert RewardsDurationTooLarge(maxRewardsDuration, duration);

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
    function removeRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
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
     * Pause the contract.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * Uppause the contract.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * Sweep any token accidently sent to this contract.
     * Staked token and rewards token can be sweeped up to the amount stored in the pool.
     */
    function sweep(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(STAKING_TOKEN)) {
            STAKING_TOKEN.safeTransfer(msg.sender, STAKING_TOKEN.balanceOf(address(this)) - stakedAmountStored);
        } else if (token == address(REWARDS_TOKEN)) {
            REWARDS_TOKEN.safeTransfer(msg.sender, REWARDS_TOKEN.balanceOf(address(this)) - rewardAmountStored);
        } else {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        }
    }

    /**
     * Remove all rewards, in case of emergency.
     */
    function emergencyWithdrawRewards() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = REWARDS_TOKEN.balanceOf(address(this));

        REWARDS_TOKEN.safeTransfer(msg.sender, balance);
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
     *
     * Returns current duration when the pool is inactive (no stake).
     */
    function _remainingSeconds() internal view returns (uint256) {
        if (stakedAmountStored == 0) return _duration();

        if (endingTime < block.timestamp) return 0;

        return endingTime - block.timestamp;
    }

    /**
     * Amount of rewards remaining to be distributed for the current distribution.
     *
     * Returns current reward amount when the pool is inactive (no stake).
     */
    function _remainingRewards() internal view returns (uint256) {
        if (stakedAmountStored == 0) return rewardAmount;

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

        uint256 locTotalRewards = rewardAmount * _duration();
        uint256 locRemainingRewards = rewardAmount * _remainingSeconds();

        if (locTotalRewards < locRemainingRewards) return rewardsPerTokenAcc;

        uint256 distributedRewards = locTotalRewards - locRemainingRewards;
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
