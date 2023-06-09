// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolGettersTest is ERC20StakingPoolBaseTest {
    function testStakingTokenAddress() public {
        assertEq(poolContract.stakingTokenAddress(), address(stakingToken));
    }

    function testRewardsTokenAddress() public {
        assertEq(poolContract.rewardsTokenAddress(), address(rewardsToken));
    }

    function testMaxRewardAmount() public {
        assertEq(poolContract.maxRewardAmount(), 1_000_000_000 * (10 ** rewardsToken.decimals()));
    }

    function testMaxRewardDuration() public {
        assertEq(poolContract.maxRewardDuration(), 365 days);
    }

    function testStakedAmountStored() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        assertEq(poolContract.stakedAmountStored(), 1000);

        stake(holder, 1000);

        assertEq(poolContract.stakedAmountStored(), 2000);
    }

    function testRewardAmountStored() public {
        addRewards(1000, 10 days);

        assertEq(poolContract.rewardAmountStored(), 1000);

        addRewards(1000, 10 days);

        assertEq(poolContract.rewardAmountStored(), 2000);
    }
}
