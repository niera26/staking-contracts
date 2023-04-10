// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolTest is ERC20StakingPoolBaseTest {
    uint256 duration = 365 days;

    function testHolderCanStakeAndUnstake() public {
        address holder = vm.addr(1);

        uint256 holderOriginalBalance = stakingToken.balanceOf(holder);

        stake(holder, 300);

        assertEq(poolContract.totalStaked(), 300);
        assertEq(poolContract.staked(holder), 300);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance);
        assertEq(stakingToken.balanceOf(address(poolContract)), 300);

        stake(holder, 700);

        assertEq(poolContract.totalStaked(), 1000);
        assertEq(poolContract.staked(holder), 1000);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance);
        assertEq(stakingToken.balanceOf(address(poolContract)), 1000);

        unstake(holder, 200);

        assertEq(poolContract.totalStaked(), 800);
        assertEq(poolContract.staked(holder), 800);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance + 200);
        assertEq(stakingToken.balanceOf(address(poolContract)), 800);

        unstake(holder, 800);

        assertEq(poolContract.totalStaked(), 0);
        assertEq(poolContract.staked(holder), 0);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance + 1000);
        assertEq(stakingToken.balanceOf(address(poolContract)), 0);
    }

    function testHoldersGetProportionalRewards() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stake(holder1, 300);
        stake(holder2, 700);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);

        // holder1 claim his rewards.
        claim(holder1);

        assertEq(poolContract.totalRewards(), 850);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 150);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.totalRewards(), 850);
        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 700);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.totalRewards(), 700);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 300);

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.totalRewards(), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 700);
    }

    function testStakingUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stake(holder1, 200);
        stake(holder2, 300);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // holder1 stake more.
        stake(holder1, 100);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1) + 1, 450);
        assertEq(poolContract.pendingRewards(holder2) + 1, 550);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.totalRewards(), 550 + 1); // theres dust.
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 450 - 1);

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.totalRewards(), 0 + 2); // theres dust.
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 550 - 1);
    }

    function testUnstakingUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stake(holder1, 200);
        stake(holder2, 300);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // holder2 unstake some.
        unstake(holder2, 100);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1), 450);
        assertEq(poolContract.pendingRewards(holder2), 550);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.totalRewards(), 550);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 450);

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.totalRewards(), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 550);
    }

    function testAddRewardsUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stake(holder1, 300);
        stake(holder2, 700);

        // add rewards.
        addRewards(1000, duration);

        // at first nobody has rewards.
        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + duration / 2);

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration / 2);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);

        // add second rewards.
        addRewards(1000, duration);

        // more remaining rewards andend of distribution increased.
        assertEq(poolContract.totalRewards(), 2000);
        assertEq(poolContract.remainingRewards(), 1500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + duration);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);

        // at end of second distribution, holders have all their rewards.
        vm.warp(block.timestamp + duration);

        assertEq(poolContract.totalRewards(), 2000);
        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1), 600);
        assertEq(poolContract.pendingRewards(holder2), 1400);

        // holder1 claim all.
        claim(holder1);

        assertEq(poolContract.totalRewards(), 1400);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 600);

        // holder2 claim all.
        claim(holder2);

        assertEq(poolContract.totalRewards(), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 1400);
    }
}
