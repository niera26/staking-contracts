// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolRemoveRewardsTest is ERC20StakingPoolBaseTest {
    event RewardsRemoved(uint256 amount);

    function testRemoveRewards_decreasesTotalRewards() public {
        stake(vm.addr(1), 1000);

        addRewards(1000, 10);

        uint256 originalRewardAmountStored = poolContract.rewardAmountStored();

        vm.warp(block.timestamp + 5);

        poolContract.removeRewards();

        assertEq(poolContract.rewardAmountStored(), originalRewardAmountStored - 500);
    }

    function testRemoveRewards_setRemainingRewardsToZero() public {
        addRewards(1000, 10);

        assertEq(poolContract.remainingRewards(), 1000);

        poolContract.removeRewards();

        assertEq(poolContract.remainingRewards(), 0);
    }

    function testRemoveRewards_setRemainingSecondsToZero() public {
        addRewards(1000, 10);

        assertEq(poolContract.remainingSeconds(), 10);

        poolContract.removeRewards();

        assertEq(poolContract.remainingSeconds(), 0);
    }

    function testRemoveRewards_transfersRewardsFromContractToOwner() public {
        stake(vm.addr(1), 1000);

        addRewards(1000, 10);

        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        vm.warp(block.timestamp + 5);

        poolContract.removeRewards();

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance + 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance - 500);
    }

    function testRemoveRewards_emitsRewardsRemoved() public {
        stake(vm.addr(1), 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsRemoved(500);

        poolContract.removeRewards();
    }

    function testRemoveRewards_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.removeRewards();
    }
}
