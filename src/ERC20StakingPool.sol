// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC20StakingPool is Ownable {
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

    // number of token to emit per second between starting and ending points.
    uint256 private rewardRate;
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
    function stake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _increaseStaked(stakeData, amount);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit TokenStacked(msg.sender, amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
    }

    /**
     * Remove tokens from the stake of the holder.
     */
    function unstake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _decreaseStaked(stakeData, amount);

        stakingToken.safeTransfer(msg.sender, amount);

        emit TokenUnstacked(msg.sender, amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
    }

    /**
     * Claim all rewards acumulated by the holder.
     */
    function claim() external {
        StakeData storage stakeData = addressToStakeData[msg.sender];

        _earnRewards(stakeData);

        uint256 earned = stakeData.earned;

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

        _newEmissionStartingPoint();

        _totalRewards += amount;

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 newAmount = _currentRemainingRewards() + amount;

        rewardRate = (newAmount * precision) / duration;
        emissionEndingPoint = block.timestamp + duration;
        emissionStartingPoint = block.timestamp;

        emit RewardsAdded(amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardToken.balanceOf(address(this)) >= _totalRewards);
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

    function _lastEmissionTimestamp() internal view returns (uint256) {
        return block.timestamp < emissionEndingPoint ? block.timestamp : emissionEndingPoint;
    }

    function _secondsSinceEmissionStartingPoint() internal view returns (uint256) {
        return _lastEmissionTimestamp() - emissionStartingPoint;
    }

    function _secondsUntilEmissionEndingPoint() internal view returns (uint256) {
        return emissionEndingPoint - _lastEmissionTimestamp();
    }

    function _currentRewardAmountFor(uint256 duration) internal view returns (uint256) {
        return (duration * rewardRate) / precision;
    }

    function _currentDistributedRewards() internal view returns (uint256) {
        return _currentRewardAmountFor(_secondsSinceEmissionStartingPoint());
    }

    function _currentRemainingRewards() internal view returns (uint256) {
        return _currentRewardAmountFor(_secondsUntilEmissionEndingPoint());
    }

    function _currentRewardsPerToken() internal view returns (uint256) {
        if (_totalStaked == 0) {
            return lastRewardsPerToken;
        }

        uint256 numerator = _currentDistributedRewards() * rewardsScale * precision;
        uint256 denominator = _totalStaked * stakingScale;

        return lastRewardsPerToken + (numerator / denominator);
    }

    function _currentPendingRewards(StakeData memory stakeData) internal view returns (uint256) {
        uint256 rewardsPerToken = _currentRewardsPerToken() - stakeData.rewardsPerTokenPaid;
        uint256 numerator = rewardsPerToken * stakeData.amount * stakingScale;
        uint256 denominator = rewardsScale * precision;

        return stakeData.earned + (numerator / denominator);
    }

    function _newEmissionStartingPoint() internal {
        lastRewardsPerToken = _currentRewardsPerToken();
        emissionStartingPoint = _lastEmissionTimestamp();
    }

    function _earnRewards(StakeData storage stakeData) internal {
        _newEmissionStartingPoint();

        stakeData.earned = _currentPendingRewards(stakeData);
        stakeData.rewardsPerTokenPaid = _currentRewardsPerToken();
    }

    function _increaseStaked(StakeData storage stakeData, uint256 amount) internal {
        _earnRewards(stakeData);

        _totalStaked += amount;
        stakeData.amount += amount;
    }

    function _decreaseStaked(StakeData storage stakeData, uint256 amount) internal {
        _earnRewards(stakeData);

        _totalStaked -= amount;
        stakeData.amount -= amount;
    }
}
