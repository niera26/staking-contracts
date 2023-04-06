// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolTest is ERC20StakingPoolBaseTest {
    function testHolderCanStakeAndUnstake() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        uint256 holderOriginalBalance = stakingToken.balanceOf(holder);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 300);
        poolContract.stake(300);
        vm.stopPrank();

        assertEq(poolContract.totalStaked(), 300);
        assertEq(poolContract.staked(holder), 300);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance - 300);
        assertEq(stakingToken.balanceOf(address(poolContract)), 300);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 700);
        poolContract.stake(700);
        vm.stopPrank();

        assertEq(poolContract.totalStaked(), 1000);
        assertEq(poolContract.staked(holder), 1000);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance - 1000);
        assertEq(stakingToken.balanceOf(address(poolContract)), 1000);

        vm.prank(holder);

        poolContract.unstake(200);

        assertEq(poolContract.totalStaked(), 800);
        assertEq(poolContract.staked(holder), 800);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance - 800);
        assertEq(stakingToken.balanceOf(address(poolContract)), 800);

        vm.prank(holder);

        poolContract.unstake(800);

        assertEq(poolContract.totalStaked(), 0);
        assertEq(poolContract.staked(holder), 0);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance);
        assertEq(stakingToken.balanceOf(address(poolContract)), 0);
    }

    function testHoldersGetProportionalRewards() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stakingToken.transfer(holder1, 1000);
        stakingToken.transfer(holder2, 1000);

        vm.startPrank(holder1);
        stakingToken.approve(address(poolContract), 300);
        poolContract.stake(300);
        vm.stopPrank();

        vm.startPrank(holder2);
        stakingToken.approve(address(poolContract), 700);
        poolContract.stake(700);
        vm.stopPrank();

        // add rewards.
        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, 10);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 10);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + 5);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 5);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);

        // holder1 claim his rewards.
        vm.prank(holder1);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 150);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + 5);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 700);

        // holder1 claim all.
        vm.prank(holder1);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 300);

        // holder2 claim all.
        vm.prank(holder2);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 700);
    }

    function testStakingUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stakingToken.transfer(holder1, 1000);
        stakingToken.transfer(holder2, 1000);

        vm.startPrank(holder1);
        stakingToken.approve(address(poolContract), 200);
        poolContract.stake(200);
        vm.stopPrank();

        vm.startPrank(holder2);
        stakingToken.approve(address(poolContract), 300);
        poolContract.stake(300);
        vm.stopPrank();

        // add rewards.
        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, 10);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 10);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + 5);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 5);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // holder1 stake more.
        vm.startPrank(holder1);
        stakingToken.approve(address(poolContract), 100);
        poolContract.stake(100);
        vm.stopPrank();

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 5);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + 5);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1) + 1, 450);
        assertEq(poolContract.pendingRewards(holder2) + 1, 550);

        // holder1 claim all.
        vm.prank(holder1);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1) + 1, holder1OriginalBalance + 450);

        // holder2 claim all.
        vm.prank(holder2);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2) + 1, holder2OriginalBalance + 550);
    }

    function testUnstakingUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stakingToken.transfer(holder1, 1000);
        stakingToken.transfer(holder2, 1000);

        vm.startPrank(holder1);
        stakingToken.approve(address(poolContract), 200);
        poolContract.stake(200);
        vm.stopPrank();

        vm.startPrank(holder2);
        stakingToken.approve(address(poolContract), 300);
        poolContract.stake(300);
        vm.stopPrank();

        // add rewards.
        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, 10);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 10);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + 5);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 5);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // holder2 unstake some.
        vm.startPrank(holder2);
        stakingToken.approve(address(poolContract), 100);
        poolContract.unstake(100);
        vm.stopPrank();

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 5);
        assertEq(poolContract.pendingRewards(holder1), 200);
        assertEq(poolContract.pendingRewards(holder2), 300);

        // at full time they should have all their rewards.
        vm.warp(block.timestamp + 5);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1), 450);
        assertEq(poolContract.pendingRewards(holder2), 550);

        // holder1 claim all.
        vm.prank(holder1);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 450);

        // holder2 claim all.
        vm.prank(holder2);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 550);
    }

    function testAddRewardsUpdatesDistribution() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stakingToken.transfer(holder1, 1000);
        stakingToken.transfer(holder2, 1000);

        vm.startPrank(holder1);
        stakingToken.approve(address(poolContract), 300);
        poolContract.stake(300);
        vm.stopPrank();

        vm.startPrank(holder2);
        stakingToken.approve(address(poolContract), 700);
        poolContract.stake(700);
        vm.stopPrank();

        // add rewards.
        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, 10);

        // at first nobody has rewards.
        assertEq(poolContract.remainingRewards(), 1000);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 10);
        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(poolContract.pendingRewards(holder2), 0);

        // at half time they have half their rewards.
        vm.warp(block.timestamp + 5);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 5);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);

        // add second rewards.
        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, 10);

        // more remaining rewards andend of distribution increased.
        assertEq(poolContract.remainingRewards(), 1500);
        assertEq(poolContract.endOfDistribution(), block.timestamp + 10);
        assertEq(poolContract.pendingRewards(holder1), 150);
        assertEq(poolContract.pendingRewards(holder2), 350);

        // at end of second distribution, holders have all their rewards.
        vm.warp(block.timestamp + 10);

        assertEq(poolContract.remainingRewards(), 0);
        assertEq(poolContract.endOfDistribution(), block.timestamp);
        assertEq(poolContract.pendingRewards(holder1), 600);
        assertEq(poolContract.pendingRewards(holder2), 1400);

        // holder1 claim all.
        vm.prank(holder1);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder1), 0);
        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 600);

        // holder2 claim all.
        vm.prank(holder2);

        poolContract.claim();

        assertEq(poolContract.pendingRewards(holder2), 0);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 1400);
    }
}
