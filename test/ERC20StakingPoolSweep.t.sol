// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolSweepTest is ERC20StakingPoolBaseTest {
    event Sweep(address indexed addr, address token, uint256 amount);

    function testSweep_transfersStakingTokenToOwnerUpToTotalStakedTokens() public {
        stake(vm.addr(1), 1000);

        uint256 ownerOriginalBalance = stakingToken.balanceOf(address(this));

        stakingToken.transfer(address(poolContract), 10000);

        poolContract.sweep(address(stakingToken));

        assertEq(poolContract.totalStakedTokens(), 1000);
        assertEq(stakingToken.balanceOf(address(this)), ownerOriginalBalance);
        assertEq(stakingToken.balanceOf(address(poolContract)), 1000);
    }

    function testSweep_emitsEventForStakingToken() public {
        stake(vm.addr(1), 1000);

        stakingToken.transfer(address(poolContract), 10000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit Sweep(address(this), address(stakingToken), 10000);

        poolContract.sweep(address(stakingToken));
    }

    function testSweep_transfersRewardsTokenToOwnerUpToStoredRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        claim(holder);

        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));

        rewardsToken.transfer(address(poolContract), 10000);

        poolContract.sweep(address(rewardsToken));

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 500);
    }

    function testSweep_emitsEventForRewardsToken() public {
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

    function testSweep_transfersRandomTokenBalanceToOwner() public {
        uint256 ownerOriginalBalance = randomToken.balanceOf(address(this));

        randomToken.transfer(address(poolContract), 1000);

        poolContract.sweep(address(randomToken));

        assertEq(randomToken.balanceOf(address(this)), ownerOriginalBalance);
    }

    function testSweep_emitsEventForRandomToken() public {
        randomToken.transfer(address(poolContract), 1000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit Sweep(address(this), address(randomToken), 1000);

        poolContract.sweep(address(randomToken));
    }

    function testSweep_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.sweep(address(randomToken));
    }
}
