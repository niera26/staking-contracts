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
    IERC20Metadata public immutable stakingToken;
    IERC20Metadata public immutable rewardsToken;

    // amount tokens staked in the pool (!= contract balance).
    // allows to sweep accidental transfer to the contract.
    // stacked amount is used for the rewards per staked tokens computation.
    uint256 public totalStakedTokens;

    // amount of rewards being distributed between starting and ending times.
    uint256 private currentRewards;
    uint256 private startingTime;
    uint256 private endingTime;

    // amount of rewards stored in the pool (total distributed rewards - total claimed rewards).
    // allows to sweep accidental transfer to the contract.
    uint256 private storedRewards;

    // ever growing accumulated number of rewards per staked token.
    // at every rewards distribution, rewards per staked tokens increases.
    uint256 private rewardsPerStakedToken;

    // constant used to prevent divisions rounding to zero.
    uint256 private constant precision = 1e18;

    // constants used to normalize both tokens to 18 decimals.
    uint256 private immutable stakingTokenScale;
    uint256 private immutable rewardsTokenScale;

    // mapping of address to stake data.
    mapping(address => Stake) private stakeholders;

    struct Stake {
        uint256 amount; // amount of staked token.
        uint256 earned; // rewards earned so far and yet to claim.
        uint256 lastRewardsPerStakedToken; // rewards per staked tokens of the last claim.
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
    constructor(address _stakingTokenAddress, address _rewardsTokenAddress)
        AccessControlDefaultAdminRules(0, msg.sender)
    {
        stakingToken = IERC20Metadata(_stakingTokenAddress);
        rewardsToken = IERC20Metadata(_rewardsTokenAddress);

        uint8 stakingTokenDecimals = stakingToken.decimals();
        uint8 rewardsTokenDecimals = rewardsToken.decimals();

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
    function stakedTokens(address addr) external view returns (uint256) {
        return stakeholders[addr].amount;
    }

    /**
     * Remaining rewards of the given address.
     */
    function remainingRewards(address addr) external view returns (uint256) {
        return _remainingRewards(stakeholders[addr]);
    }

    /**
     * Pending rewards of the given address.
     */
    function pendingRewards(address addr) external view returns (uint256) {
        return _pendingRewards(stakeholders[addr], _rewardsPerStakedToken());
    }

    /**
     * Add tokens to the stake of the sender.
     */
    function stakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        Stake storage stake = stakeholders[msg.sender];

        _earnRewards(stake);

        _distributeRewards();

        stake.amount += amount;
        totalStakedTokens += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit StakeTokens(msg.sender, amount);
    }

    /**
     * Remove tokens from the stake of the sender.
     *
     * Automatically claim the pending rewards when everything is unstaked.
     */
    function unstakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        Stake storage stake = stakeholders[msg.sender];

        if (amount > stake.amount) {
            revert InsufficientStakedAmount(stake.amount, amount);
        }

        _earnRewards(stake);

        _distributeRewards();

        stake.amount -= amount;
        totalStakedTokens -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit UnstakeTokens(msg.sender, amount);

        if (stake.amount == 0) {
            _claimEarnedRewards(stake);
        }
    }

    /**
     * Claim pending rewards of the sender.
     */
    function claimRewards() external nonReentrant whenNotPaused {
        Stake storage stake = stakeholders[msg.sender];

        _earnRewards(stake);
        _claimEarnedRewards(stake);
    }

    /**
     * Adds the given rewards for the given duration.
     *
     * It *must* be used to add rewards to the pool.
     */
    function addRewards(uint256 amount, uint256 duration) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();

        _distributeRewards();

        currentRewards += amount;
        endingTime += duration;

        // transfer rewards from operator to this contract.
        storedRewards += amount;
        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);
        emit AddRewards(msg.sender, amount, duration);

        // @see _rewardsPerStakedToken()
        // max value of denominator is (totalSupply * stakingTokenScale * totalDuration)
        // max value of numerator is (currentRewards * rewardsTokenScale * precision * totalDuration)
        uint256 totalDuration = _duration();
        if (totalDuration > type(uint256).max / (stakingToken.totalSupply() * stakingTokenScale)) {
            revert DistributionTooLarge(amount, duration);
        }
        if (totalDuration > type(uint256).max / (currentRewards * rewardsTokenScale * precision)) {
            revert DistributionTooLarge(amount, duration);
        }
    }

    /**
     * Transfers back all remaining rewards.
     *
     * It *must* be used to remove rewards from the pool.
     */
    function removeRewards() external onlyRole(OPERATOR_ROLE) {
        _distributeRewards();

        uint256 amount = currentRewards;

        if (amount == 0) return;

        // end distribution.
        currentRewards = 0;
        startingTime = block.timestamp;
        endingTime = block.timestamp;

        // transfer remaining rewards from this contract to operator.
        storedRewards -= amount;
        rewardsToken.safeTransfer(msg.sender, amount);
        emit RemoveRewards(msg.sender, amount);
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
     * Staking tokens can be swept up to the amount staked in the pool.
     * Rewards tokens can be swept up to the amount stored in the pool.
     */
    function sweep(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = IERC20Metadata(token).balanceOf(address(this));

        if (token == address(stakingToken)) {
            amount -= totalStakedTokens;
        }

        if (token == address(rewardsToken)) {
            amount -= storedRewards;
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
        if (totalStakedTokens == 0) return _duration();

        if (endingTime < block.timestamp) return 0;

        return endingTime - block.timestamp;
    }

    /**
     * Amount of rewards remaining to be distributed.
     *
     * Returns total rewards when the pool is inactive (no stake).
     */
    function _remainingRewards() private view returns (uint256) {
        if (totalStakedTokens == 0) return currentRewards;

        uint256 duration = _duration();

        if (duration == 0) return 0;

        return (_remainingSeconds() * currentRewards) / duration;
    }

    /**
     * Amount of rewards remaining to be distributed to the given stake.
     */
    function _remainingRewards(Stake memory stake) private view returns (uint256) {
        if (stake.amount == 0) return 0;

        uint256 duration = _duration();

        if (duration == 0) return 0;

        return (_remainingSeconds() * currentRewards * stake.amount) / (duration * totalStakedTokens);
    }

    /**
     * The number of rewards per staked token.
     * Increases every second until end of distribution.
     * Do not use _remainingRewards() to be as precise as possible (do not divide twice by duration).
     */
    function _rewardsPerStakedToken() private view returns (uint256) {
        if (totalStakedTokens == 0) return rewardsPerStakedToken;

        uint256 duration = _duration();

        if (duration == 0) return rewardsPerStakedToken;

        uint256 locTotalRewards = currentRewards * _duration();
        uint256 locRemainingRewards = currentRewards * _remainingSeconds();

        if (locTotalRewards < locRemainingRewards) return rewardsPerStakedToken;

        uint256 locDistributedRewards = locTotalRewards - locRemainingRewards;
        uint256 scaledStakedAmount = totalStakedTokens * stakingTokenScale * duration;
        uint256 scaledDistributedRewards = locDistributedRewards * rewardsTokenScale * precision;

        return rewardsPerStakedToken + (scaledDistributedRewards / scaledStakedAmount);
    }

    /**
     * Pending rewards of the given stake, with the given rewardsPerToken.
     *
     * (allow to compute rewardsPerToken once in _earnRewards())
     */
    function _pendingRewards(Stake memory stake, uint256 rewardsPerToken) private view returns (uint256) {
        if (rewardsPerToken < stake.lastRewardsPerStakedToken) return 0;

        uint256 rewardsPerTokenDiff = rewardsPerToken - stake.lastRewardsPerStakedToken;

        uint256 stakeRewards = rewardsPerTokenDiff * stake.amount * stakingTokenScale;

        return stake.earned + (stakeRewards / (rewardsTokenScale * precision));
    }

    /**
     * Accumulate the pending rewards of the given stake.
     *
     * Set its last rewards per staked tokens to the current one so those rewards cant be earned again.
     */
    function _earnRewards(Stake storage stake) private {
        uint256 rewardsPerToken = _rewardsPerStakedToken();

        stake.earned = _pendingRewards(stake, rewardsPerToken);
        stake.lastRewardsPerStakedToken = rewardsPerToken;
    }

    /**
     * Distribute the rewards until current block timestamp.
     *
     * It *must* be used before users stake/unstake tokens or operators add/remove rewards
     * because it records the rewards per staked tokens at this point.
     *
     * - First record the current rewards per staked tokens.
     * - Set starting time to now.
     * - When the distribution is not active (= there is no token staked) just keep the same
     *   total rewards and duration.
     * - When the distribution is active (= there is staked tokens) set total rewards as the
     *   remaining rewards and duration as the remaining seconds.
     */
    function _distributeRewards() private {
        rewardsPerStakedToken = _rewardsPerStakedToken();

        bool isActive = totalStakedTokens > 0;

        if (isActive) currentRewards = _remainingRewards();

        uint256 duration = isActive ? _remainingSeconds() : _duration();

        startingTime = block.timestamp;
        endingTime = block.timestamp + duration;
    }

    /**
     * Transfers the rewards earned by the given stake.
     *
     * It *must* be used to remove stake rewards from the pool.
     */
    function _claimEarnedRewards(Stake storage stake) private {
        uint256 earned = stake.earned;

        if (earned > 0) {
            stake.earned = 0;
            storedRewards -= earned;
            rewardsToken.safeTransfer(msg.sender, earned);
            emit ClaimRewards(msg.sender, earned);
        }
    }
}
