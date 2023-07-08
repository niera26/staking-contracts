// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControlDefaultAdminRules} from "openzeppelin/access/AccessControlDefaultAdminRules.sol";
import {AccessControlEnumerable} from "openzeppelin/access/AccessControlEnumerable.sol";
import {IERC20Metadata} from "openzeppelin/interfaces/IERC20Metadata.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20StakingPool} from "./IERC20StakingPool.sol";

contract ERC20StakingPool is IERC20StakingPool, AccessControlDefaultAdminRules, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // staking and rewards tokens.
    IERC20Metadata private immutable STAKING_TOKEN;
    IERC20Metadata private immutable REWARDS_TOKEN;

    // amount of both tokens stored in the pool (!= contract balance).
    // allows to sweep accidental transfer to the contract.
    // stacked amount is used for the rewards per token computation.
    uint256 private _stakedAmountStored;
    uint256 private _rewardAmountStored;

    // constant used to prevent divisions rounding to zero.
    uint256 private constant precision = 1e18;

    // constants used to normalize both tokens to 18 decimals.
    uint256 private immutable stakingTokenScale;
    uint256 private immutable rewardsTokenScale;

    // ever growing accumulated number of rewards per staked token.
    // at every checkpoint, the distributed rewards per staked tokens is added to this value.
    uint256 private rewardsPerTokenStored;

    // amount of rewards being distributed between starting and ending times.
    uint256 private totalRewards;
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
    error DistributionTooLarge(uint256 amount, uint256 duration);
    error InsufficientStakedAmount(uint256 staked, uint256 amount);
    error TokenHasMoreThan18Decimals(address token, uint8 decimals);

    /**
     * - deployer gets granted admin role.
     * - both tokens must have 18 decimals at most.
     */
    constructor(address _stakingTokenAddress, address _rewardsTokenAddress, uint48 initialDelay)
        AccessControlDefaultAdminRules(initialDelay, msg.sender)
    {
        STAKING_TOKEN = IERC20Metadata(_stakingTokenAddress);
        REWARDS_TOKEN = IERC20Metadata(_rewardsTokenAddress);

        uint8 stakingTokenDecimals = STAKING_TOKEN.decimals();
        uint8 rewardsTokenDecimals = REWARDS_TOKEN.decimals();

        if (stakingTokenDecimals > 18) {
            revert TokenHasMoreThan18Decimals(_stakingTokenAddress, stakingTokenDecimals);
        }

        if (rewardsTokenDecimals > 18) {
            revert TokenHasMoreThan18Decimals(_rewardsTokenAddress, rewardsTokenDecimals);
        }

        stakingTokenScale = 10 ** (18 - stakingTokenDecimals);
        rewardsTokenScale = 10 ** (18 - rewardsTokenDecimals);
    }

    /**
     * The address of the staking token.
     */
    function stakingTokenAddress() external view returns (address) {
        return address(STAKING_TOKEN);
    }

    /**
     * The address of the rewards token.
     */
    function rewardsTokenAddress() external view returns (address) {
        return address(REWARDS_TOKEN);
    }

    /**
     * The staked amount stored.
     */
    function stakedAmountStored() external view returns (uint256) {
        return _stakedAmountStored;
    }

    /**
     * The reward amount stored.
     */
    function rewardAmountStored() external view returns (uint256) {
        return _rewardAmountStored;
    }

    /**
     * Amount of rewards remaining to distribute.
     */
    function remainingRewards() external view returns (uint256) {
        return _remainingRewards();
    }

    /**
     * Seconds remaining before end of distribution.
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
     * Pending rewards of the given address.
     */
    function pendingRewards(address addr) external view returns (uint256) {
        return _pendingRewards(addressToStakeData[addr], _rewardsPerToken());
    }

    /**
     * Remaining rewards of the given address.
     */
    function remainingRewards(address addr) external view returns (uint256) {
        return _remainingRewards(addressToStakeData[addr]);
    }

    /**
     * Add tokens to the stake of the sender.
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);
        _increaseTotalStaked(stakeData, amount);
    }

    /**
     * Remove tokens from the stake of the sender.
     *
     * Automatically claim the pending rewards when everything is unstaked.
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
     * Claim pending rewards of the sender.
     */
    function claim() external nonReentrant whenNotPaused {
        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);
        _claimEarnedRewards(stakeData);
    }

    /**
     * Adds the given rewards for the given duration.
     *
     * It *must* be used to add rewards to the pool.
     */
    function addRewards(uint256 amount, uint256 duration) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();

        _checkpoint();

        totalRewards += amount;
        endingTime += duration;

        // @see _rewardsPerToken()
        // max value of denominator is (totalSupply * stakingTokenScale * totalDuration)
        // max value of numerator is (totalRewards * rewardsTokenScale * precision * totalDuration)
        uint256 totalDuration = _duration();
        if (totalDuration > type(uint256).max / (STAKING_TOKEN.totalSupply() * stakingTokenScale)) {
            revert DistributionTooLarge(amount, duration);
        }
        if (totalDuration > type(uint256).max / (totalRewards * rewardsTokenScale * precision)) {
            revert DistributionTooLarge(amount, duration);
        }

        _rewardAmountStored += amount;
        REWARDS_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        emit AddRewards(msg.sender, amount, duration);
    }

    /**
     * Transfers back all remaining rewards.
     *
     * It *must* be used to remove rewards from the pool.
     */
    function removeRewards() external onlyRole(OPERATOR_ROLE) {
        _checkpoint();

        uint256 amount = totalRewards;

        if (amount > 0) {
            totalRewards = 0;
            startingTime = block.timestamp;
            endingTime = block.timestamp;

            _rewardAmountStored -= amount;
            REWARDS_TOKEN.safeTransfer(msg.sender, amount);
            emit RemoveRewards(msg.sender, amount);
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
     * Sweep balance of any token accidently sent to this contract.
     *
     * Staking and rewards tokens can be swept up to the amount stored in the pool.
     */
    function sweep(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = IERC20Metadata(token).balanceOf(address(this));

        if (token == address(STAKING_TOKEN)) {
            amount -= _stakedAmountStored;
        }

        if (token == address(REWARDS_TOKEN)) {
            amount -= _rewardAmountStored;
        }

        IERC20Metadata(token).safeTransfer(msg.sender, amount);

        emit Sweep(msg.sender, token, amount);
    }

    /**
     * The duration of the distribution.
     */
    function _duration() private view returns (uint256) {
        if (endingTime < startingTime) return 0;

        return endingTime - startingTime;
    }

    /**
     * The number of seconds until the end of the distribution.
     *
     * Returns duration when the pool is inactive (no stake).
     */
    function _remainingSeconds() private view returns (uint256) {
        if (_stakedAmountStored == 0) return _duration();

        if (endingTime < block.timestamp) return 0;

        return endingTime - block.timestamp;
    }

    /**
     * Amount of rewards remaining to be distributed.
     *
     * Returns total rewards when the pool is inactive (no stake).
     */
    function _remainingRewards() private view returns (uint256) {
        if (_stakedAmountStored == 0) return totalRewards;

        uint256 duration = _duration();

        if (duration == 0) return 0;

        return (_remainingSeconds() * totalRewards) / duration;
    }

    /**
     * Amount of rewards remaining to be distributed to the given stake.
     */
    function _remainingRewards(StakeData memory stakeData) private view returns (uint256) {
        if (stakeData.amount == 0) return 0;

        uint256 duration = _duration();

        if (duration == 0) return 0;

        return (_remainingSeconds() * totalRewards * stakeData.amount) / (duration * _stakedAmountStored);
    }

    /**
     * The number of rewards per staked token.
     * Increases every second until end of distribution.
     * Do not use _remainingRewards() to be as precise as possible (do not divide twice by duration).
     */
    function _rewardsPerToken() private view returns (uint256) {
        if (_stakedAmountStored == 0) return rewardsPerTokenStored;

        uint256 duration = _duration();

        if (duration == 0) return rewardsPerTokenStored;

        uint256 locTotalRewards = totalRewards * _duration();
        uint256 locRemainingRewards = totalRewards * _remainingSeconds();

        if (locTotalRewards < locRemainingRewards) return rewardsPerTokenStored;

        uint256 distributedRewards = locTotalRewards - locRemainingRewards;
        uint256 scaledStakedAmount = _stakedAmountStored * stakingTokenScale * duration;
        uint256 scaledDistributedRewards = distributedRewards * rewardsTokenScale * precision;

        return rewardsPerTokenStored + (scaledDistributedRewards / scaledStakedAmount);
    }

    /**
     * Pending rewards of the given stake, with the given rewardsPerToken.
     *
     * (allow to compute rewardsPerToken once in _earnRewards())
     */
    function _pendingRewards(StakeData memory stakeData, uint256 rewardsPerToken) private view returns (uint256) {
        if (rewardsPerToken < stakeData.lastRewardsPerToken) return 0;

        uint256 rewardsPerTokenDiff = rewardsPerToken - stakeData.lastRewardsPerToken;

        uint256 stakeRewards = rewardsPerTokenDiff * stakeData.amount * stakingTokenScale;

        return stakeData.earned + (stakeRewards / (rewardsTokenScale * precision));
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
     * Checkpoint the distribution.
     *
     * It *must* be used before users stake/unstake tokens or operators add/remove rewards
     * because it records the rewards per token at this point.
     *
     * - First record the current rewards per token.
     * - Set starting time to now.
     * - When the distribution is not active (= there is no token staked) just keep the same
     *   total rewards and duration.
     * - When the distribution is active (= there is staked tokens) set total rewards as the
     *   remaining rewards and duration as the remaining seconds.
     */
    function _checkpoint() private {
        rewardsPerTokenStored = _rewardsPerToken();

        bool isActive = _stakedAmountStored > 0;

        if (isActive) totalRewards = _remainingRewards();

        uint256 duration = isActive ? _remainingSeconds() : _duration();

        startingTime = block.timestamp;
        endingTime = block.timestamp + duration;
    }

    /**
     * Increases the total amount of staked tokens.
     *
     * It *must* be used to add staking tokens to the pool.
     */
    function _increaseTotalStaked(StakeData storage stakeData, uint256 amount) private {
        _checkpoint();

        stakeData.amount += amount;
        _stakedAmountStored += amount;
        STAKING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        emit Stake(msg.sender, amount);
    }

    /**
     * Decreases the total amount of staked tokens.
     *
     * It *must* be used to remove staking tokens from the pool.
     */
    function _decreaseTotalStaked(StakeData storage stakeData, uint256 amount) private {
        _checkpoint();

        stakeData.amount -= amount;
        _stakedAmountStored -= amount;
        STAKING_TOKEN.safeTransfer(msg.sender, amount);
        emit Unstake(msg.sender, amount);
    }

    /**
     * Transfers the rewards earned by the given stake.
     *
     * It *must* be used to remove stake rewards from the pool.
     */
    function _claimEarnedRewards(StakeData storage stakeData) private {
        uint256 earned = stakeData.earned;

        if (earned > 0) {
            stakeData.earned = 0;
            _rewardAmountStored -= earned;
            REWARDS_TOKEN.safeTransfer(msg.sender, earned);
            emit Claim(msg.sender, earned);
        }
    }
}
