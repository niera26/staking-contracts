// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolRemoveRewardsTest is ERC20StakingPoolBaseTest {
    event RemoveRewards(address indexed addr, uint256 amount);

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

    function testRemoveRewards_transfersUndistributedRewardsFromContractToOwner() public {
        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));

        stake(vm.addr(1), 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        // no distribution occurrence.

        poolContract.removeRewards();

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 0);
    }

    function testRemoveRewards_doesNotTransferDistributedRewardsFromContractToOwner() public {
        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));

        stake(vm.addr(1), 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        // distribution occurrence.
        stake(vm.addr(1), 1000);

        poolContract.removeRewards();

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance - 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 500);
    }

    function testRemoveRewards_emitsEvent() public {
        stake(vm.addr(1), 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RemoveRewards(address(this), 1000);

        poolContract.removeRewards();
    }

    function testRemoveRewards_revertsCallerIsNotOperatorRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notOperatorRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.removeRewards();
    }
}
