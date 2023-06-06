// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolEmergencyWithdrawTest is ERC20StakingPoolBaseTest {
    function testEmergencyWithdraw_allowsHolderToWithdrawTokens() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(10000, 10 days);

        vm.warp(block.timestamp + 1 days);

        stake(holder, 1000);

        assertEq(poolContract.staked(holder), 2000);
        assertEq(poolContract.pendingRewards(holder), 1000);

        vm.prank(holder);

        poolContract.emergencyWithdraw();

        assertEq(poolContract.staked(holder), 0);
        assertEq(poolContract.pendingRewards(holder), 0);
        assertEq(stakingToken.balanceOf(holder), 2000);
        assertEq(rewardsToken.balanceOf(holder), 0);
        assertEq(poolContract.stakedAmountStored(), 0);
        assertEq(stakingToken.balanceOf(address(poolContract)), 0);
        assertEq(poolContract.rewardAmountStored(), 9000);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 10000);
        assertEq(rewardsToken.balanceOf(address(this)), rewardsToken.totalSupply() - 10000);

        poolContract.sweep(address(rewardsToken));

        assertEq(rewardsToken.balanceOf(address(poolContract)), 9000);
        assertEq(rewardsToken.balanceOf(address(this)), rewardsToken.totalSupply() - 9000);
    }

    function testEmergencyWithdraw_emitsEmergencyWithdraw() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit EmergencyWithdraw(holder, 1000);

        vm.prank(holder);

        poolContract.emergencyWithdraw();
    }
}
