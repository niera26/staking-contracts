// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC20StakingPool is Ownable {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata private immutable stakingToken;
    IERC20Metadata private immutable rewardsToken;

    uint256 private _totalStaked;
    uint256 private _totalRewards;

    uint256 private lastRewardsPerToken;

    mapping(address => StakeData) private addressToStakeData;

    uint256 private constant precision = 10 ** 18;
    uint256 private immutable stakingScale;
    uint256 private immutable rewardsScale;

    uint256 private emissionStartingPoint;
    uint256 private emissionEndingPoint;
    uint256 private rewardRate;

    struct StakeData {
        uint256 amount;
        uint256 rewardsPerTokenPaid;
        uint256 earned;
    }

    constructor(address _stakingToken, address _rewardsToken) {
        stakingToken = IERC20Metadata(_stakingToken);
        rewardsToken = IERC20Metadata(_rewardsToken);

        // get scales normalizing both tokens to 18 decimals.
        uint8 stakingTokenDecimals = stakingToken.decimals();
        uint8 rewardsTokenDecimals = rewardsToken.decimals();

        require(stakingTokenDecimals <= 18, "staking token must have less than 18 decimals");
        require(rewardsTokenDecimals <= 18, "rewards token must have less than 18 decimals");

        stakingScale = 10 ** (18 - stakingTokenDecimals);
        rewardsScale = 10 ** (18 - rewardsTokenDecimals);
    }

    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    function totalRewards() external view returns (uint256) {
        return _totalRewards;
    }

    function stakedAmount(address addr) external view returns (uint256) {
        return addressToStakeData[addr].amount;
    }

    function pendingRewards(address addr) external view returns (uint256) {
        StakeData memory stakeData = addressToStakeData[addr];

        return _currentPendingRewards(stakeData);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "cannot stake zero");

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _increaseTotalStaked(stakeData, amount);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "cannot unstake zero");

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _decreaseTotalStaked(stakeData, amount);

        stakingToken.safeTransfer(msg.sender, amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
    }

    function claim() external {
        StakeData storage stakeData = addressToStakeData[msg.sender];

        _claimPendingRewards(stakeData);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
    }

    function addRewards(uint256 amount, uint256 duration) external onlyOwner {
        require(amount > 0, "cannot distribute zero");
        require(duration > 0, "duration must be at least 1s");

        _newEmissionStartingPoint();

        _totalRewards += amount;

        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);

        rewardRate = ((amount + _currentRemainingRewards()) * precision) / duration;
        emissionEndingPoint = block.timestamp + duration;
        emissionStartingPoint = block.timestamp;

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
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

    function _increaseTotalStaked(StakeData storage stakeData, uint256 amount) internal {
        _earnRewards(stakeData);

        _totalStaked += amount;
        stakeData.amount += amount;
    }

    function _decreaseTotalStaked(StakeData storage stakeData, uint256 amount) internal {
        _earnRewards(stakeData);

        _totalStaked -= amount;
        stakeData.amount -= amount;
    }

    function _claimPendingRewards(StakeData storage stakeData) internal {
        _earnRewards(stakeData);

        _totalRewards -= stakeData.earned;

        if (stakeData.earned > 0) {
            rewardsToken.safeTransfer(msg.sender, stakeData.earned);
            stakeData.earned = 0;
        }
    }
}
