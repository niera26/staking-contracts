// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolClaimTest is ERC20StakingPoolBaseTest {
    uint256 duration = 365 days;

    event RewardsClaimed(address indexed holder, uint256 amount);

    function testClaim_transfersTokensFromContractToHolder() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, duration);

        uint256 holderOriginalBalance = rewardsToken.balanceOf(holder);
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        vm.warp(block.timestamp + duration / 2);

        vm.prank(holder);

        poolContract.claim();

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance + 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance - 500);

        vm.warp(block.timestamp + duration / 2);

        vm.prank(holder);

        poolContract.claim();

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance + 1000);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance - 1000);
    }

    function testFailClaim_emitsRewardsClaimedWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        poolContract.addRewards(1000, 10);

        vm.warp(block.timestamp + 10);

        // here we dont go in future.

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsClaimed(holder, 1000);

        vm.prank(holder);

        poolContract.claim();
    }

    function testClaim_emitsRewardsClaimedWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, 10);

        vm.warp(block.timestamp + 10);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsClaimed(holder, 1000);

        vm.prank(holder);

        poolContract.claim();
    }
}
