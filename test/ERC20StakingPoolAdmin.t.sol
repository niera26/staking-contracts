// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolAdminTest is ERC20StakingPoolBaseTest {
    function testPause_canBeCalledByOwner() public {
        poolContract.pause();
    }

    function testPause_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.pause();
    }

    function testUnpause_canBeCalledByOwner() public {
        poolContract.pause();
        poolContract.unpause();
    }

    function testUnpause_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        poolContract.pause();

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.unpause();
    }

    function testSweep_transfersRandomTokenToOwnerUpToTotalStaked() public {
        randomToken.transfer(address(poolContract), 1000);

        uint256 ownerOriginalBalance = randomToken.balanceOf(address(this));

        poolContract.sweep(address(randomToken));

        assertEq(randomToken.balanceOf(address(this)), ownerOriginalBalance + 1000);
    }

    function testSweep_emitsSweepForRandomToken() public {
        randomToken.transfer(address(poolContract), 1000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit Sweep(address(this), address(randomToken), 1000);

        poolContract.sweep(address(randomToken));
    }

    function testSweep_transfersStakingTokenToOwnerUpToTotalStaked() public {
        stake(vm.addr(1), 1000);

        stakingToken.transfer(address(poolContract), 10000);

        uint256 ownerOriginalBalance = stakingToken.balanceOf(address(this));
        uint256 contractOriginalBalance = stakingToken.balanceOf(address(poolContract));

        poolContract.sweep(address(stakingToken));

        assertEq(poolContract.stakedAmountStored(), 1000);
        assertEq(stakingToken.balanceOf(address(this)), ownerOriginalBalance + 10000);
        assertEq(stakingToken.balanceOf(address(poolContract)), contractOriginalBalance - 10000);
    }

    function testSweep_emitsSweepForStakingToken() public {
        stake(vm.addr(1), 1000);

        stakingToken.transfer(address(poolContract), 10000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit Sweep(address(this), address(stakingToken), 10000);

        poolContract.sweep(address(stakingToken));
    }

    function testSweep_transfersRewardsTokenToOwnerUpToTotalRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        claim(holder);

        rewardsToken.transfer(address(poolContract), 10000);

        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        poolContract.sweep(address(rewardsToken));

        assertEq(poolContract.rewardAmountStored(), 500);
        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance + 10000);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance - 10000);
    }

    function testSweep_emitsSweepForRewardsToken() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        claim(holder);

        rewardsToken.transfer(address(poolContract), 10000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit Sweep(address(this), address(rewardsToken), 10000);

        poolContract.sweep(address(rewardsToken));
    }

    function testSweep_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.sweep(address(randomToken));
    }
}
