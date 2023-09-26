// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolTest is ERC20StakingPoolBaseTest {
    uint256 duration = 365 days;

    function testHolderCanStakeAndUnstake() public {
        address holder = vm.addr(1);

        stake(holder, 300);

        assertEq(poolContract.totalStakedTokens(), 300);
        assertEq(poolContract.stakedTokens(holder), 300);
        assertEq(stakingToken.balanceOf(holder), 0);
        assertEq(stakingToken.balanceOf(address(poolContract)), 300);

        stake(holder, 700);

        assertEq(poolContract.totalStakedTokens(), 1000);
        assertEq(poolContract.stakedTokens(holder), 1000);
        assertEq(stakingToken.balanceOf(holder), 0);
        assertEq(stakingToken.balanceOf(address(poolContract)), 1000);

        unstake(holder, 200);

        assertEq(poolContract.totalStakedTokens(), 800);
        assertEq(poolContract.stakedTokens(holder), 800);
        assertEq(stakingToken.balanceOf(holder), 200);
        assertEq(stakingToken.balanceOf(address(poolContract)), 800);

        unstake(holder, 800);

        assertEq(poolContract.totalStakedTokens(), 0);
        assertEq(poolContract.stakedTokens(holder), 0);
        assertEq(stakingToken.balanceOf(holder), 1000);
        assertEq(stakingToken.balanceOf(address(poolContract)), 0);
    }

    function testHoldersGetProportionalRewards() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        stake(holder1, 300);
        stake(holder2, 700);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.remainingSeconds(), duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder1), 300);
        assertEq(poolContract.remainingRewards(holder2), 700);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);
        assertEq(poolContract.remainingRewards(holder1), 150);
        assertEq(poolContract.remainingRewards(holder2), 350);

        // holder1 claim his rewards.
        claim(holder1);

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder1), 150);
        assertEq(rewardsToken.balanceOf(holder1), 150);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.remainingSeconds(), 0);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 700);
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), 300);

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), 700);
    }

    function testStakingUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        stake(holder1, 200);
        stake(holder2, 300);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.remainingSeconds(), duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder1), 400);
        assertEq(poolContract.remainingRewards(holder2), 600);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);
        assertEq(poolContract.remainingRewards(holder1), 200);
        assertEq(poolContract.remainingRewards(holder2), 300);

        // holder1 stake more.
        stake(holder1, 100);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);
        assertEq(poolContract.remainingRewards(holder1), 250);
        assertEq(poolContract.remainingRewards(holder2), 250);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.remainingSeconds(), 0);
        assertEq(poolContract.pendingRewards(holder1), 449); // theres some dust
        assertEq(poolContract.pendingRewards(holder2), 549); // theres some dust
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), 449); // theres some dust

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), 549); // theres some dust
    }

    function testUnstakingUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        stake(holder1, 200);
        stake(holder2, 300);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.remainingSeconds(), duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder1), 400);
        assertEq(poolContract.remainingRewards(holder2), 600);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);
        assertEq(poolContract.remainingRewards(holder1), 200);
        assertEq(poolContract.remainingRewards(holder2), 300);

        // holder2 unstake some.
        unstake(holder2, 100);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);
        assertEq(poolContract.remainingRewards(holder1), 250);
        assertEq(poolContract.remainingRewards(holder2), 250);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.remainingSeconds(), 0);
        assertEq(poolContract.pendingRewards(holder1), 450);
        assertEq(poolContract.pendingRewards(holder2), 550);
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), 450);

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), 550);
    }

    function testAddRewardsUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        stake(holder1, 300);
        stake(holder2, 700);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.remainingSeconds(), duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder1), 300);
        assertEq(poolContract.remainingRewards(holder2), 700);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);
        assertEq(poolContract.remainingRewards(holder1), 150);
        assertEq(poolContract.remainingRewards(holder2), 350);

        // add second rewards.
        addRewards(1000, duration);

        // more remaining rewards andend of distribution increased.
        assertEq(poolContract.remainingRewards(), 1500);
        assertEq(poolContract.remainingSeconds(), (duration / 2) + duration);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);
        assertEq(poolContract.remainingRewards(holder1), 450);
        assertEq(poolContract.remainingRewards(holder2), 1050);

        // at end of second distribution, holders have all their rewards.
        vm.warp(block.timestamp + (duration / 2) + duration);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.remainingSeconds(), 0);
        assertEq(poolContract.pendingRewards(holder1), 600);
        assertEq(poolContract.pendingRewards(holder2), 1400);
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.remainingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), 600);

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(poolContract.remainingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), 1400);
    }

    function testDistributionRestartsWithTheFirstStake() public {
        address holder = vm.addr(1);

        addRewards(1000, duration);

        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.remainingSeconds(), duration);
        assertEq(poolContract.pendingRewards(holder), 0);
        assertEq(poolContract.remainingRewards(holder), 0);

        // half the time pass with no stake.
        vm.warp(block.timestamp + duration / 2);

        // add the first stake.
        stake(holder, 1000);

        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.remainingSeconds(), duration);
        assertEq(poolContract.pendingRewards(holder), 0);
        assertEq(poolContract.remainingRewards(holder), 1000);

        // half the time pass with a stake.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), (duration / 2));
        assertEq(poolContract.pendingRewards(holder), 500);
        assertEq(poolContract.remainingRewards(holder), 500);

        // staker unstakes all.
        unstake(holder, 1000);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), (duration / 2));
        assertEq(poolContract.pendingRewards(holder), 500);
        assertEq(poolContract.remainingRewards(holder), 0);

        // half the time pass with no stake.
        vm.warp(block.timestamp + duration / 2);

        // add the first stake again.
        stake(holder, 1000);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), (duration / 2));
        assertEq(poolContract.pendingRewards(holder), 500);
        assertEq(poolContract.remainingRewards(holder), 500);

        // half the time pass with a stake.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.remainingSeconds(), 0);
        assertEq(poolContract.pendingRewards(holder), 1000);
        assertEq(poolContract.remainingRewards(holder), 0);

        // holder claim all.
        claim(holder);

        assertEq(poolContract.pendingRewards(holder), 0);
        assertEq(poolContract.remainingRewards(holder), 0);
        assertEq(rewardsToken.balanceOf(holder), 1000);
    }

    function testRewardsCanBeRemoved() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, duration);

        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.remainingSeconds(), duration);
        assertEq(poolContract.pendingRewards(holder), 0);
        assertEq(poolContract.remainingRewards(holder), 1000);

        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), (duration / 2));
        assertEq(poolContract.pendingRewards(holder), 500);
        assertEq(poolContract.remainingRewards(holder), 500);

        poolContract.removeRewards();

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.remainingSeconds(), 0);
        assertEq(poolContract.pendingRewards(holder), 0);
        assertEq(poolContract.remainingRewards(holder), 0);

        claim(holder);

        assertEq(poolContract.pendingRewards(holder), 0);
        assertEq(poolContract.remainingRewards(holder), 0);
        assertEq(rewardsToken.balanceOf(holder), 0);
    }

    function testReturnsTheFullAmountWhenNoStake() public {
        addRewards(1000, duration);

        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 1000);

        stake(vm.addr(1), 1000);

        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingRewards(), 500);
    }

    function testReturnsTheFullDurationWhenNoStake() public {
        addRewards(1000, duration);

        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingSeconds(), duration);

        stake(vm.addr(1), 1000);

        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.remainingSeconds(), duration / 2);
    }
}
