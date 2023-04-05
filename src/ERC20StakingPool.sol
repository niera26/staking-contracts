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

    // exact numbers of both tokens managed by the contract.
    // allows to sweep dust and accidental transfer to the contract.
    uint256 private _totalStaked;
    uint256 private _totalRewards;

    // constants used for the computation.
    // scales allow not normalize both tokens to 18 decimals.
    uint256 private constant precision = 10 ** 18;
    uint256 private immutable stakingScale;
    uint256 private immutable rewardsScale;

    // number of token to distribute per second between starting and ending points.
    uint256 private rewardsToDistribute;
    uint256 private emissionStartingPoint;
    uint256 private emissionEndingPoint;

    // reward token per staked token since last stake/unstake/claim/addRewards.
    uint256 private lastRewardsPerToken;

    // map address to stake data.
    mapping(address => StakeData) private addressToStakeData;

    struct StakeData {
        uint256 amount; // amount of staked token.
        uint256 earned; // rewards earned so far and yet to claim.
        uint256 rewardsPerTokenPaid; // rewards per staked token of the last claim.
    }

    event TokenStacked(address indexed holder, uint256 amount);
    event TokenUnstacked(address indexed holder, uint256 amount);

    event RewardsAdded(uint256 amount);
    event RewardsClaimed(address indexed holder, uint256 amount);

    error ZeroAmount();
    error ZeroDuration();
    error TooMuchDecimals(address token, uint8 decimals);

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
     * Total number of staked token managed by the contract (going in stake and out of unstake)
     */
    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    /**
     * Total number of rewards token managed by the contract (going in addRewards and out of claim)
     */
    function totalRewards() external view returns (uint256) {
        return _totalRewards;
    }

    /**
     * Number of rewards yet to be distributed.
     */
    function remainingRewards() external view returns (uint256) {
        return _currentRemainingRewards();
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
        StakeData memory stakeData = addressToStakeData[addr];

        return _currentPendingRewards(stakeData);
    }

    /**
     * Add tokens to the stake of the holder.
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);
        _updateTotalStaked(_totalStaked + amount);

        stakeData.amount += amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit TokenStacked(msg.sender, amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
    }

    /**
     * Remove tokens from the stake of the holder.
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);
        _updateTotalStaked(_totalStaked - amount);

        stakeData.amount -= amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit TokenUnstacked(msg.sender, amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
    }

    /**
     * Claim all rewards acumulated by the holder.
     */
    function claim() external nonReentrant whenNotPaused {
        StakeData storage stakeData = addressToStakeData[msg.sender];

        uint256 earned = _earnRewards(stakeData);

        if (earned > 0) {
            _totalRewards -= earned;
            stakeData.earned = 0;
            rewardToken.safeTransfer(msg.sender, earned);

            emit RewardsClaimed(msg.sender, earned);
        }

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
    }

    /**
     * Add the given amount of rewards and distribute it over the given duration.
     *
     * Accumulates the remaining rewards of the current distribution.
     */
    function addRewards(uint256 amount, uint256 duration) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();

        _updateRewardsToDistribute(amount, duration);

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsAdded(amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
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
     *
     * Staked token and rewards token can be sweeped up to the amount managed by the contract.
     */
    function sweep(address token) external onlyOwner {
        if (token == address(stakingToken)) {
            stakingToken.safeTransfer(msg.sender, stakingToken.balanceOf(address(this)) - _totalStaked);
        } else if (token == address(rewardToken)) {
            rewardToken.safeTransfer(msg.sender, rewardToken.balanceOf(address(this)) - _totalRewards);
        } else {
            IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
        }

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
    }

    /**
     * Amount of rewards to distribute for the given number of seconds.
     */
    function _currentRewardAmount(uint256 from, uint256 to) internal view returns (uint256) {
        if (from >= to) return 0;
        if (emissionStartingPoint >= emissionEndingPoint) return 0;

        return ((to - from) * rewardsToDistribute) / (emissionEndingPoint - emissionStartingPoint);
    }

    /**
     * Number of rewards that has been distributed so far for the current distribution.
     */
    function _currentDistributedRewards() internal view returns (uint256) {
        return _currentRewardAmount(emissionStartingPoint, block.timestamp);
    }

    /**
     * Number of rewards yet to be distributed for the current distribution.
     */
    function _currentRemainingRewards() internal view returns (uint256) {
        return _currentRewardAmount(block.timestamp, emissionEndingPoint);
    }

    /**
     * The number of rewards to give per staked token.
     *
     * Increases every second until end of current distribution.
     */
    function _currentRewardsPerToken() internal view returns (uint256) {
        if (_totalStaked == 0) {
            return lastRewardsPerToken;
        }

        uint256 numerator = _currentDistributedRewards() * rewardsScale * precision;
        uint256 denominator = _totalStaked * stakingScale;

        return lastRewardsPerToken + (numerator / denominator);
    }

    /**
     * Pending rewards of the given stake.
     *
     * Increases every second until end of current distribution.
     */
    function _currentPendingRewards(StakeData memory stakeData) internal view returns (uint256) {
        uint256 rewardsPerToken = _currentRewardsPerToken() - stakeData.rewardsPerTokenPaid;
        uint256 numerator = rewardsPerToken * stakeData.amount * stakingScale;
        uint256 denominator = rewardsScale * precision;

        return stakeData.earned + (numerator / denominator);
    }

    /**
     * Accumulate the given stake pending rewards and set its rewards per token
     * to the current reward per token so those rewards cant be earned again.
     */
    function _earnRewards(StakeData storage stakeData) internal returns (uint256) {
        stakeData.earned = _currentPendingRewards(stakeData);
        stakeData.rewardsPerTokenPaid = _currentRewardsPerToken();
        return stakeData.earned;
    }

    function _updateTotalStaked(uint256 __totalStaked) internal {
        lastRewardsPerToken = _currentRewardsPerToken();

        _totalStaked = __totalStaked;
        rewardsToDistribute = _currentRemainingRewards();
        emissionStartingPoint = block.timestamp;
    }

    function _updateRewardsToDistribute(uint256 amount, uint256 duration) internal {
        lastRewardsPerToken = _currentRewardsPerToken();

        _totalRewards += amount;
        rewardsToDistribute = _currentRemainingRewards() + amount;
        emissionStartingPoint = block.timestamp;
        emissionEndingPoint = block.timestamp + duration;
    }
}
