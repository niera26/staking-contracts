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

    // current distribution remaining rewards and seconds.
    uint256 private lastRemainingRewards;
    uint256 private lastRemainingSeconds;

    // last time rewards were distributed.
    uint256 private lastUpdate;

    // ever growing accumulated number of rewards per staked token.
    // at every rewards distribution, rewards per staked tokens increases.
    uint256 private lastRewardsPerStaked;

    // amount of rewards stored in the pool (total distributed rewards - total claimed rewards).
    // allows to sweep accidental transfer to the contract.
    uint256 private storedRewards;

    // constant used to prevent rounding rewards per staked token to zero.
    uint256 private constant precision = 1e18;

    // maximum number of seconds a distribution can last.
    uint256 private constant maxSeconds = 1e9;

    // constants used to normalize both tokens to 18 decimals.
    uint256 private immutable stakingTokenScale;
    uint256 private immutable rewardsTokenScale;

    // mapping of address to stake data.
    mapping(address => Stake) private stakeholders;

    struct Stake {
        uint256 amount; // amount of staked token.
        uint256 earned; // rewards earned so far and yet to claim.
        uint256 rewardsPerStaked; // rewards per staked tokens of the last claim.
    }

    struct PoolValues {
        uint256 remainingRewards;
        uint256 remainingSeconds;
        uint256 rewardsPerStaked;
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
        return _currentValues().remainingRewards;
    }

    /**
     * Seconds remaining before end of distribution.
     */
    function remainingSeconds() external view returns (uint256) {
        return _currentValues().remainingSeconds;
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
        if (totalStakedTokens == 0) return 0;

        return (_currentValues().remainingRewards * stakeholders[addr].amount) / totalStakedTokens;
    }

    /**
     * Pending rewards of the given address.
     */
    function pendingRewards(address addr) external view returns (uint256) {
        return _earned(stakeholders[addr], _currentValues().rewardsPerStaked);
    }

    /**
     * Add tokens to the stake of the sender.
     */
    function stakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        Stake storage stake = stakeholders[msg.sender];

        _distributeAndEarnRewards(stake);

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

        _distributeAndEarnRewards(stake);

        stake.amount -= amount;
        totalStakedTokens -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit UnstakeTokens(msg.sender, amount);
    }

    /**
     * Claim pending rewards of the sender.
     */
    function claimRewards() external nonReentrant whenNotPaused {
        Stake storage stake = stakeholders[msg.sender];

        _distributeAndEarnRewards(stake);

        uint256 earned = stake.earned;

        if (earned == 0) return;

        stake.earned = 0;
        storedRewards -= earned;
        rewardsToken.safeTransfer(msg.sender, earned);
        emit ClaimRewards(msg.sender, earned);
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

        lastRemainingRewards += amount;
        lastRemainingSeconds += duration;

        // transfer rewards from operator to this contract.
        storedRewards += amount;
        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);
        emit AddRewards(msg.sender, amount, duration);
    }

    /**
     * Transfers back all remaining rewards.
     *
     * It *must* be used to remove rewards from the pool.
     */
    function removeRewards() external onlyRole(OPERATOR_ROLE) {
        _distributeRewards();

        uint256 amount = lastRemainingRewards;

        if (amount == 0) return;

        // end distribution.
        lastRemainingRewards = 0;
        lastRemainingSeconds = 0;

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
     * Values of the pool based on current timestamp.
     */
    function _currentValues() private view returns (PoolValues memory) {
        if (block.timestamp < lastUpdate) {
            revert("invalid timestamp");
        }

        // nothing has been distributed yet.
        if (lastUpdate == 0) {
            return PoolValues(0, 0, 0);
        }

        // distribute nothing when no tokens are staked.
        if (totalStakedTokens == 0) {
            return PoolValues(lastRemainingRewards, lastRemainingSeconds, lastRewardsPerStaked);
        }

        // distribute nothing when distribution ended.
        if (lastRemainingSeconds == 0) {
            return PoolValues(lastRemainingRewards, lastRemainingSeconds, lastRewardsPerStaked);
        }

        // compute elapsed seconds since last update.
        uint256 elapsedSeconds = block.timestamp - lastUpdate;

        if (elapsedSeconds > lastRemainingSeconds) {
            elapsedSeconds = lastRemainingSeconds;
        }

        // compute how much has been distributed since last update.
        // should not round to zero as lastRemainingSeconds is bounded by maxSeconds.
        uint256 distributedRewards = (lastRemainingRewards * elapsedSeconds * maxSeconds) / lastRemainingSeconds;

        // how much rewards has been distributed per staking token.
        // should not round to zero as long as totalStakedTokens <= precision.
        uint256 rewardsPerStaked =
            (distributedRewards * rewardsTokenScale * precision) / (totalStakedTokens * stakingTokenScale);

        // return the new pool values.
        return PoolValues({
            remainingRewards: ((lastRemainingRewards * maxSeconds) - distributedRewards) / maxSeconds,
            remainingSeconds: lastRemainingSeconds - elapsedSeconds,
            rewardsPerStaked: lastRewardsPerStaked + rewardsPerStaked
        });
    }

    /**
     * How much the given stake earned according to the given rewardsPerToken.
     */
    function _earned(Stake memory stake, uint256 rewardsPerStaked) private view returns (uint256) {
        uint256 rewardsPerStakedDiff =
            rewardsPerStaked > stake.rewardsPerStaked ? rewardsPerStaked - stake.rewardsPerStaked : 0;

        uint256 numerator = stake.amount * stakingTokenScale * rewardsPerStakedDiff;
        uint256 denominator = rewardsTokenScale * maxSeconds * precision;

        return stake.earned + (numerator / denominator);
    }

    /**
     * Distribute rewards of the pool until the current timestamp.
     */
    function _distributeRewards() private returns (PoolValues memory) {
        PoolValues memory current = _currentValues();

        lastRemainingRewards = current.remainingRewards;
        lastRemainingSeconds = current.remainingSeconds;
        lastRewardsPerStaked = current.rewardsPerStaked;
        lastUpdate = block.timestamp;

        return current;
    }

    /**
     * Distribute rewards until current timestamp and earn rewards of the given stake.
     */
    function _distributeAndEarnRewards(Stake storage stake) private {
        PoolValues memory current = _distributeRewards();

        stake.earned = _earned(stake, current.rewardsPerStaked);
        stake.rewardsPerStaked = current.rewardsPerStaked;
    }
}
