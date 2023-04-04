// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC20StakingPool is Ownable {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata private immutable stakingToken;
    IERC20Metadata private immutable rewardsToken;

    uint256 private rewardsPerToken;

    mapping(address => StakeData) private addressToStakeData;

    uint256 private constant precision = 10 ** 18;
    uint256 private immutable stakingScale;
    uint256 private immutable rewardsScale;

    uint256 private _totalStaked;
    uint256 private _totalRewards;

    uint256 private lastDistributionTimestamp;
    uint256 private endOfEmissionTimestamp;
    uint256 private rewardRate;

    struct StakeData {
        uint256 amount;
        uint256 rewardsPerTokenPaid;
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

    function stakedAmount(address addr) external view returns (uint256) {
        return addressToStakeData[addr].amount;
    }

    function pendingRewards(address addr) external view returns (uint256) {
        StakeData memory stakeData = addressToStakeData[addr];

        return _computePendingRewards(stakeData);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "cannot stake zero");

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _claimPendingRewards(stakeData);
        _increaseTotalStaked(amount);

        stakeData.amount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "cannot unstake zero");

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _claimPendingRewards(stakeData);
        _decreaseTotalStaked(amount);

        stakeData.amount -= amount;
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

        _totalRewards += amount;

        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);

        rewardRate = (amount * precision) / duration;
        endOfEmissionTimestamp = block.timestamp + duration;
        lastDistributionTimestamp = block.timestamp;

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
    }

    function _secondsSinceLastDistribution() internal view returns (uint256) {
        return (block.timestamp < endOfEmissionTimestamp ? block.timestamp : endOfEmissionTimestamp)
            - lastDistributionTimestamp;
    }

    function _currentTotalRewards() internal view returns (uint256) {
        return (_secondsSinceLastDistribution() * rewardRate) / precision;
    }

    function _currentRewardsPerToken() internal view returns (uint256) {
        if (_totalStaked == 0) {
            return rewardsPerToken;
        }

        uint256 totalRewards = _currentTotalRewards();

        return rewardsPerToken + (totalRewards * rewardsScale * precision) / (_totalStaked * stakingScale);
    }

    function _computePendingRewards(StakeData memory stakeData) internal view returns (uint256) {
        if (stakeData.amount == 0) {
            return 0;
        }

        uint256 unclaimedRewardsPerToken = _currentRewardsPerToken() - stakeData.rewardsPerTokenPaid;

        return (unclaimedRewardsPerToken * stakeData.amount * stakingScale) / (rewardsScale * precision);
    }

    function _increaseTotalStaked(uint256 amount) internal {
        _totalStaked += amount;
        rewardsPerToken = _currentRewardsPerToken();
    }

    function _decreaseTotalStaked(uint256 amount) internal {
        _totalStaked -= amount;
        rewardsPerToken = _currentRewardsPerToken();
    }

    function _claimPendingRewards(StakeData storage stakeData) internal {
        uint256 _pendingRewards = _computePendingRewards(stakeData);

        _totalRewards -= _pendingRewards;

        stakeData.rewardsPerTokenPaid = rewardsPerToken;

        if (_pendingRewards > 0) {
            rewardsToken.safeTransfer(msg.sender, _pendingRewards);
        }
    }
}
