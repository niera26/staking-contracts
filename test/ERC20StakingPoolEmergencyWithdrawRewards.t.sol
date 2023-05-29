// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolEmergencyWithdrawRewardsTest is ERC20StakingPoolBaseTest {
    function testEmergencyWithdrawRewards_allowsOwnerToWithdrawRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(10000, 10 days);

        vm.warp(block.timestamp + 1 days);

        stake(holder, 1000);

        poolContract.emergencyWithdrawRewards();

        assertEq(rewardsToken.balanceOf(address(poolContract)), 0);
        assertEq(rewardsToken.balanceOf(address(this)), rewardsToken.totalSupply());
    }

    function testEmergencyWithdrawRewards_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.removeRewards();
    }
}
