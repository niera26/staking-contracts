// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ERC20StakingPool is Ownable {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata public stakingToken;
    IERC20Metadata public rewardsToken;

    uint256 private rewardsPerToken;

    mapping(address => StakeData) private addressToStakeData;

    uint256 private constant precision = 10 ** 18;
    uint256 private immutable stakingScale;
    uint256 private immutable rewardsScale;

    uint256 private _totalStaked;
    uint256 private _totalRewards;

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

        _totalStaked += amount;
        stakeData.amount += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "cannot unstake zero");

        StakeData storage stakeData = addressToStakeData[msg.sender];

        _claimPendingRewards(stakeData);

        _totalStaked -= amount;
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

    function addRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "cannot distribute zero");
        require(_totalStaked > 0, "no token to reward");

        _totalRewards += amount;

        rewardsPerToken += (amount * rewardsScale * precision) / (_totalStaked * stakingScale);

        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);

        assert(stakingToken.balanceOf(address(this)) >= _totalStaked);
        assert(rewardsToken.balanceOf(address(this)) >= _totalRewards);
    }

    function _computePendingRewards(StakeData memory stakeData) internal view returns (uint256) {
        if (stakeData.amount == 0) {
            return 0;
        }

        uint256 delta = rewardsPerToken - stakeData.rewardsPerTokenPaid;

        return (delta * stakeData.amount * stakingScale) / (rewardsScale * precision);
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
