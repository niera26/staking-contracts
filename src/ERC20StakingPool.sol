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

    // constant used to prevent rounding rewards per staked token to zero.
    uint256 private constant precision = 1e18;

    // constants used to normalize both tokens to 18 decimals.
    uint256 private immutable stakingTokenScale;
    uint256 private immutable rewardsTokenScale;

    // amount of rewards stored in the pool (total added rewards - total claimed rewards).
    // allows to sweep accidental transfer to the contract.
    uint256 private storedRewards;

    // the last distribution values.
    Distribution private last;

    // mapping of address to stake data.
    mapping(address => Stake) private stakeholders;

    struct Stake {
        uint256 amount; // amount of staked token.
        uint256 earned; // rewards earned so far and yet to claim.
        uint256 rewardsPerStaked; // rewards per staked tokens of the last time it earned rewards.
    }

    struct Distribution {
        uint256 remainingRewards; // rewards to be distributed during remainingSeconds.
        uint256 remainingSeconds; // number of seconds remaining until end of rewards distribution.
        uint256 rewardsPerStaked; // ever growing accumulated number of rewards per staked token.
        uint256 timestamp; // time when the distribution occurred.
    }

    // errors.
    error ZeroAmount();
    error ZeroDuration();
    error InvalidTimestamp(uint256 timestamp);
    error InsufficientStakedAmount(uint256 staked, uint256 amount);
    error TokenHasMoreThan18Decimals(address token, uint8 decimals);
    error WillOverflow();

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
     * Number of tokens staked by the given address.
     */
    function stakedTokens(address addr) external view returns (uint256) {
        return stakeholders[addr].amount;
    }

    /**
     * Rewards remaining to distribute.
     */
    function remainingRewards() external view returns (uint256) {
        return _currentDistribution().remainingRewards;
    }

    /**
     * Rewards remaining to distribute to the given address.
     */
    function remainingRewards(address addr) external view returns (uint256) {
        if (totalStakedTokens == 0) return 0;

        return (_currentDistribution().remainingRewards * stakeholders[addr].amount) / totalStakedTokens;
    }

    /**
     * Seconds remaining before all rewards are distributed.
     */
    function remainingSeconds() external view returns (uint256) {
        return _currentDistribution().remainingSeconds;
    }

    /**
     * Pending rewards of the given address.
     */
    function pendingRewards(address addr) external view returns (uint256) {
        Stake memory stake = stakeholders[addr];

        return stake.earned + _earned(stake, _currentDistribution().rewardsPerStaked);
    }

    /**
     * Add tokens to the stake of the sender.
     */
    function stakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        Stake storage stake = stakeholders[msg.sender];

        _distributeAndEarnRewards(stake);

        stake.amount += amount;
        _transferStakingTokensIn(msg.sender, amount);
        emit StakeTokens(msg.sender, amount);
    }

    /**
     * Remove tokens from the stake of the sender.
     */
    function unstakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        Stake storage stake = stakeholders[msg.sender];

        if (amount > stake.amount) {
            revert InsufficientStakedAmount(stake.amount, amount);
        }

        _distributeAndEarnRewards(stake);

        stake.amount -= amount;
        _transferStakingTokensOut(msg.sender, amount);
        emit UnstakeTokens(msg.sender, amount);
    }

    /**
     * Claim pending rewards of the sender.
     */
    function claimRewards() external nonReentrant whenNotPaused {
        Stake storage stake = stakeholders[msg.sender];

        _distributeAndEarnRewards(stake);

        uint256 earned = stake.earned;

        if (earned > 0) {
            stake.earned = 0;
            _transferRewardsOut(msg.sender, earned);
            emit ClaimRewards(msg.sender, earned);
        }
    }

    /**
     * Adds the given rewards for the given duration.
     */
    function addRewards(uint256 amount, uint256 duration) external onlyRole(OPERATOR_ROLE) {
        if (amount == 0) revert ZeroAmount();

        last.remainingRewards += amount;
        last.remainingSeconds += duration;

        _overflowChecks();

        _transferRewardsIn(msg.sender, amount);
        emit AddRewards(msg.sender, amount, duration);
    }

    /**
     * Transfers back all remaining rewards to operator and end distribution.
     */
    function removeRewards() external onlyRole(OPERATOR_ROLE) {
        uint256 amount = last.remainingRewards;

        last.remainingRewards = 0;
        last.remainingSeconds = 0;

        if (amount > 0) {
            _transferRewardsOut(msg.sender, amount);
            emit RemoveRewards(msg.sender, amount);
        }
    }

    /**
     * Set the distribution remaining seconds to the given duration.
     */
    function setDuration(uint256 duration) external onlyRole(OPERATOR_ROLE) {
        if (duration == 0) revert ZeroDuration();

        last.remainingSeconds = duration;

        _overflowChecks();

        emit SetDuration(msg.sender, duration);
    }

    /**
     * Set the distribution remaining seconds so it ends at the given timestamp.
     */
    function setUntil(uint256 timestamp) external onlyRole(OPERATOR_ROLE) {
        if (block.timestamp > timestamp) revert InvalidTimestamp(timestamp);

        last.remainingSeconds = timestamp - block.timestamp;

        _overflowChecks();

        emit SetUntil(msg.sender, timestamp);
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
     * Transfer staking tokens from given address to this contract.
     */
    function _transferStakingTokensIn(address from, uint256 amount) private {
        totalStakedTokens += amount;
        stakingToken.safeTransferFrom(from, address(this), amount);
    }

    /**
     * Transfer staking tokens from this contract to given address.
     */
    function _transferStakingTokensOut(address to, uint256 amount) private {
        totalStakedTokens -= amount;
        stakingToken.safeTransfer(to, amount);
    }

    /**
     * Transfer rewards from given address to this contract.
     */
    function _transferRewardsIn(address from, uint256 amount) private {
        storedRewards += amount;
        rewardsToken.safeTransferFrom(from, address(this), amount);
    }

    /**
     * Transfer rewards from this contract to given address.
     */
    function _transferRewardsOut(address to, uint256 amount) private {
        storedRewards -= amount;
        rewardsToken.safeTransfer(to, amount);
    }

    /**
     * Number of seconds elapsed since the given distribution.
     */
    function _elapsedSeconds(Distribution memory distribution) private view returns (uint256) {
        if (block.timestamp < distribution.timestamp) {
            revert("invalid timestamp");
        }

        uint256 elapsedSeconds = block.timestamp - distribution.timestamp;

        if (elapsedSeconds > distribution.remainingSeconds) {
            elapsedSeconds = distribution.remainingSeconds;
        }

        return elapsedSeconds;
    }

    /**
     * How much the given stake earned since the last time it earned rewards.
     */
    function _earned(Stake memory stake, uint256 rewardsPerStaked) private view returns (uint256) {
        uint256 rewardsPerStakedDiff =
            rewardsPerStaked > stake.rewardsPerStaked ? rewardsPerStaked - stake.rewardsPerStaked : 0;

        return (stake.amount * stakingTokenScale * rewardsPerStakedDiff) / (rewardsTokenScale * precision);
    }

    /**
     * Distribute and earn rewards of the given stake.
     */
    function _distributeAndEarnRewards(Stake storage stake) private {
        last = _currentDistribution();

        uint256 earned = _earned(stake, last.rewardsPerStaked);

        // if rewards per staked diff is very small then the division in _earned()
        // may round to zero, so we update the stake's rewards per staked only when
        // something was earned. This way the stake will accumulate very small rewards
        // until it does not get rounded to zero anymore.
        if (earned > 0) {
            stake.earned += earned;
            stake.rewardsPerStaked = last.rewardsPerStaked;
        }
    }

    /**
     * New values of the distribution based on the current timestamp.
     */
    function _currentDistribution() private view returns (Distribution memory) {
        // theres no staked tokens, rewards cant be distributed.
        // distribution is "paused", keep the same values and update the timestamp.
        if (totalStakedTokens == 0) {
            return Distribution(last.remainingRewards, last.remainingSeconds, last.rewardsPerStaked, block.timestamp);
        }

        // theres no rewards left to distribute.
        // set remaining seconds to 0 just in case of.
        if (last.remainingRewards == 0) {
            return Distribution(0, 0, last.rewardsPerStaked, block.timestamp);
        }

        // distribution ended already.
        // keep the remaining rewards just in case of.
        if (last.remainingSeconds == 0) {
            return Distribution(last.remainingRewards, 0, last.rewardsPerStaked, block.timestamp);
        }

        // this is the first distribution, nothing to distribute.
        // set the current timestamp in case of addRewards triggers the first distribution.
        if (last.timestamp == 0) {
            return Distribution(0, 0, 0, block.timestamp);
        }

        // compute elapsed seconds since last distribution.
        uint256 elapsedSeconds = _elapsedSeconds(last);

        // 0 elapsed seconds will lead to 0 rewards to distribute.
        // it means block.timestamp == last.timestamp so the same timestamp can be returned.
        if (elapsedSeconds == 0) return last;

        // compute how much has been distributed since last update.
        // remaining rewards iand elapsed seconds are both greater than zero so this division
        // rounds to 0 only when elapsed seconds is too small vs remaining seconds.
        uint256 rewardsToDistribute = (last.remainingRewards * elapsedSeconds) / last.remainingSeconds;

        // return the same distribution when theres no rewards to distribute.
        // it means not enough seconds elapsed for the division to not round to zero.
        // by keepging the same timestamp then next time elpased seconds will get closer to
        // remaining seconds, then rewards to distribute will get closer to remaining rewards.
        // all remaining rewards are distributed when elapsed seconds == remaining seconds.
        if (rewardsToDistribute == 0) return last;

        // how much rewards to distribute per staking token.
        // should not round to zero as long as totalStakedTokens <= precision.
        uint256 rewardsPerStaked =
            (rewardsToDistribute * rewardsTokenScale * precision) / (totalStakedTokens * stakingTokenScale);

        // return the new distribution.
        return Distribution({
            remainingRewards: last.remainingRewards - rewardsToDistribute,
            remainingSeconds: last.remainingSeconds - elapsedSeconds,
            rewardsPerStaked: last.rewardsPerStaked + rewardsPerStaked,
            timestamp: block.timestamp
        });
    }

    /**
     * Ensure computations in _currentDistribution() will not revert.
     */
    function _overflowChecks() private view {
        // check rewards to distribute multiplication in worst case scenario.
        if (!tryMul(last.remainingRewards, last.remainingSeconds)) {
            revert WillOverflow();
        }

        // check rewards per staked tokens in worst case scenario.
        if (!tryMul(last.remainingRewards, rewardsTokenScale)) {
            revert WillOverflow();
        }

        if (!tryMul(last.remainingRewards * rewardsTokenScale, precision)) {
            revert WillOverflow();
        }
    }

    /**
     * Imported from openzeppelin.
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool) {
        unchecked {
            if (a == 0) return true;
            uint256 c = a * b;
            if (c / a != b) return false;
            return true;
        }
    }
}
