// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControl} from "openzeppelin/access/AccessControl.sol";
import {IERC20Metadata} from "openzeppelin/interfaces/IERC20Metadata.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20StakingPool} from "./IERC20StakingPool.sol";
import {ERC20StakingPoolEvents} from "./ERC20StakingPoolEvents.sol";

contract ERC20StakingPool is IERC20StakingPool, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // constant used to prevent divisions rounding to zero.
    uint256 private constant precision = 1e18;

    // staking and rewards tokens.
    IERC20Metadata private immutable STAKING_TOKEN;
    IERC20Metadata private immutable REWARDS_TOKEN;

    // both tokens decimals.
    uint256 public immutable stakingTokenDecimals;
    uint256 public immutable rewardsTokenDecimals;

    // constants used to normalize both tokens to 18 decimals.
    uint256 private immutable stakingScale;
    uint256 private immutable rewardsScale;

    // max amount and duration for a distribution.
    uint256 public immutable maxRewardAmount;
    uint256 public immutable maxRewardDuration;

    // numbers of both tokens stored in the pool (!= contract balance).
    // allows to sweep accidental transfer to the contract.
    // stacked amount is used for the rewards per token computation.
    uint256 public stakedAmountStored;
    uint256 public rewardAmountStored;

    // ever growing accumulated number of rewards per staked token.
    // every time a new distribiton starts, its rewards per token value
    // is added to this.
    uint256 private rewardsPerTokenAcc;

    // amount of rewards being distributed between starting and ending times.
    uint256 private rewardAmount;
    uint256 private startingTime;
    uint256 private endingTime;

    // mapping of address to stake data.
    mapping(address => StakeData) private addressToStakeData;

    struct StakeData {
        uint256 amount; // amount of staked token.
        uint256 earned; // rewards earned so far and yet to claim.
        uint256 lastRewardsPerToken; // rewards per token of the last claim.
    }

    // errors.
    error ZeroAmount();
    error ZeroDuration();
    error RewardAmountTooLarge(uint256 max, uint256 amount);
    error RewardDurationTooLarge(uint256 max, uint256 amount);
    error InsufficientStakedAmount(uint256 staked, uint256 amount);

    /**
     * - deployer gets granted admin role.
     * - both tokens must have less than 18 decimals.
     */
    constructor(address _stakingToken, address _rewardsToken, uint256 _maxRewardAmount, uint256 _maxRewardDuration) {
        STAKING_TOKEN = IERC20Metadata(_stakingToken);
        REWARDS_TOKEN = IERC20Metadata(_rewardsToken);

        stakingTokenDecimals = STAKING_TOKEN.decimals();
        rewardsTokenDecimals = REWARDS_TOKEN.decimals();

        require(stakingTokenDecimals <= 18, "staking token has too much decimals (> 18)");
        require(rewardsTokenDecimals <= 18, "rewards token has too much decimals (> 18)");

        stakingScale = 10 ** (18 - stakingTokenDecimals);
        rewardsScale = 10 ** (18 - rewardsTokenDecimals);

        maxRewardAmount = _maxRewardAmount * (10 ** rewardsTokenDecimals);
        maxRewardDuration = _maxRewardDuration;

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
        return _pendingRewards(addressToStakeData[addr], _rewardsPerToken());
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

        if (amount > stakeData.amount) {
            revert InsufficientStakedAmount(stakeData.amount, amount);
        }

        _earnRewards(stakeData);
        _decreaseTotalStaked(stakeData, amount);

        if (stakeData.amount == 0) {
            _claimEarnedRewards(stakeData);
        }
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

        stakedAmountStored -= amount;
        rewardAmountStored -= earned;

        STAKING_TOKEN.safeTransfer(msg.sender, amount);

        emit ERC20StakingPoolEvents.EmergencyWithdraw(msg.sender, amount);
    }

    /**
     * Starts a new distribution and adds the given rewards for the given duration.
     *
     * It *must* be used to add rewards to the pool.
     */
    function addRewards(uint256 amount, uint256 duration) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();
        if (amount > maxRewardAmount) revert RewardAmountTooLarge(maxRewardAmount, amount);
        if (duration > maxRewardDuration) revert RewardDurationTooLarge(maxRewardDuration, duration);

        _startNewDistribution();

        rewardAmount += amount;
        endingTime += duration;

        rewardAmountStored += amount;
        REWARDS_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        emit ERC20StakingPoolEvents.RewardsAdded(msg.sender, amount, duration);
    }

    /**
     * Transfers back all currently distributed rewards.
     *
     * It *must* be used to remove rewards from the pool.
     */
    function removeRewards() external onlyRole(OPERATOR_ROLE) {
        _startNewDistribution();

        uint256 amount = rewardAmount;

        if (amount > 0) {
            rewardAmount = 0;
            startingTime = block.timestamp;
            endingTime = block.timestamp;

            rewardAmountStored -= amount;
            REWARDS_TOKEN.safeTransfer(msg.sender, amount);
            emit ERC20StakingPoolEvents.RewardsRemoved(msg.sender, amount);
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
     * Staking and rewards tokens can be sweeped up to the amount stored in the pool.
     */
    function sweep(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 locked;
        uint256 balance = IERC20Metadata(token).balanceOf(address(this));

        if (token == address(STAKING_TOKEN)) {
            locked = stakedAmountStored;
        } else if (token == address(REWARDS_TOKEN)) {
            locked = rewardAmountStored;
        } else {
            locked = 0;
        }

        uint256 amount = balance - locked;

        IERC20Metadata(token).safeTransfer(msg.sender, amount);

        emit ERC20StakingPoolEvents.Swept(msg.sender, token, amount);
    }

    /**
     * The duration of the current distribution.
     */
    function _duration() private view returns (uint256) {
        if (endingTime < startingTime) return 0;

        return endingTime - startingTime;
    }

    /**
     * The number of seconds until the end of the current distribution.
     *
     * Returns current duration when the pool is inactive (no stake).
     */
    function _remainingSeconds() private view returns (uint256) {
        if (stakedAmountStored == 0) return _duration();

        if (endingTime < block.timestamp) return 0;

        return endingTime - block.timestamp;
    }

    /**
     * Amount of rewards remaining to be distributed for the current distribution.
     *
     * Returns current reward amount when the pool is inactive (no stake).
     */
    function _remainingRewards() private view returns (uint256) {
        if (stakedAmountStored == 0) return rewardAmount;

        uint256 duration = _duration();

        if (duration == 0) return 0;

        return (_remainingSeconds() * rewardAmount) / duration;
    }

    /**
     * The number of rewards per staked token.
     * Increases every second until end of current distribution.
     * Do not use _remainingRewards() to be as precise as possible (do not divide twice by duration).
     */
    function _rewardsPerToken() private view returns (uint256) {
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
     * Pending rewards of the given stake, with the given rewardsPerToken.
     *
     * (allow to compute rewardsPerToken once in _earnRewards())
     */
    function _pendingRewards(StakeData memory stakeData, uint256 rewardsPerToken) private view returns (uint256) {
        if (rewardsPerToken < stakeData.lastRewardsPerToken) return 0;

        uint256 rewardsPerTokenDiff = rewardsPerToken - stakeData.lastRewardsPerToken;

        uint256 stakeRewards = rewardsPerTokenDiff * stakeData.amount * stakingScale;

        return stakeData.earned + (stakeRewards / (rewardsScale * precision));
    }

    /**
     * Accumulate the pending rewards of the given stake.
     *
     * Set its last rewards per token to the current one so those rewards cant be earned again.
     */
    function _earnRewards(StakeData storage stakeData) private {
        uint256 rewardsPerToken = _rewardsPerToken();

        stakeData.earned = _pendingRewards(stakeData, rewardsPerToken);
        stakeData.lastRewardsPerToken = rewardsPerToken;
    }

    /**
     * Starts a new distribution from now.
     *
     * It *must* be used before users stake/unstake tokens or operators add/remove rewards
     * because it records the rewards per token at this point.
     *
     * - First record the current rewards per token.
     * - Set starting time to now.
     * - When the distribution is not active (= there is no token staked) just keep the same
     *   rewards amount and duration.
     * - When the distribution is active (= there is staked tokens) set rewards amount as
     *   remaining rewards and duration as remaining seconds.
     */
    function _startNewDistribution() private {
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
    function _increaseTotalStaked(StakeData storage stakeData, uint256 amount) private {
        _startNewDistribution();

        stakeData.amount += amount;
        stakedAmountStored += amount;
        STAKING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        emit ERC20StakingPoolEvents.TokenStacked(msg.sender, amount);
    }

    /**
     * Starts a new distribution and decrease the total amount of staked tokens.
     *
     * It *must* be used to remove staking tokens from the pool.
     */
    function _decreaseTotalStaked(StakeData storage stakeData, uint256 amount) private {
        _startNewDistribution();

        stakeData.amount -= amount;
        stakedAmountStored -= amount;
        STAKING_TOKEN.safeTransfer(msg.sender, amount);
        emit ERC20StakingPoolEvents.TokenUnstacked(msg.sender, amount);
    }

    /**
     * Transfers to the given stake the rewards it earned.
     *
     * It *must* be used to remove stake rewards from the pool.
     */
    function _claimEarnedRewards(StakeData storage stakeData) private {
        uint256 earned = stakeData.earned;

        if (earned > 0) {
            stakeData.earned = 0;
            rewardAmountStored -= earned;
            REWARDS_TOKEN.safeTransfer(msg.sender, earned);
            emit ERC20StakingPoolEvents.RewardsClaimed(msg.sender, earned);
        }
    }
}
