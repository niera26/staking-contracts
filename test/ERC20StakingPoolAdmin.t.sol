// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolAdminTest is ERC20StakingPoolBaseTest {
    function testPause_canBeCalledByOwner() public {
        poolContract.pause();
    }

    function testPause_revertsCallerIsNotTheOwner() public {
        address sender = vm.addr(1);

        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(sender);

        poolContract.pause();
    }

    function testUnpause_canBeCalledByOwner() public {
        poolContract.pause();
        poolContract.unpause();
    }

    function testUnpause_revertsCallerIsNotTheOwner() public {
        address sender = vm.addr(1);

        poolContract.pause();

        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(sender);

        poolContract.unpause();
    }

    function testSweep_transfersContractBalanceOfGivenTokenToOwner() public {
        randomToken.transfer(address(poolContract), 1000);

        uint256 ownerOriginalBalance = randomToken.balanceOf(address(this));

        poolContract.sweep(address(randomToken));

        assertEq(randomToken.balanceOf(address(this)), ownerOriginalBalance + 1000);
    }

    function testSweep_transfersStakingTokenToOwnerUpToTotalStaked() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        stakingToken.transfer(address(poolContract), 10000);

        uint256 ownerOriginalBalance = stakingToken.balanceOf(address(this));

        poolContract.sweep(address(stakingToken));

        assertEq(poolContract.totalStaked(), 1000);
        assertEq(stakingToken.balanceOf(address(poolContract)), 1000);
        assertEq(stakingToken.balanceOf(address(this)), ownerOriginalBalance + 10000);
    }

    function testSweep_transfersRewardsTokenToOwnerUpToTotalRewards() public {
        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000, 10);

        rewardsToken.transfer(address(poolContract), 10000);

        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));

        poolContract.sweep(address(rewardsToken));

        assertEq(poolContract.totalRewards(), 1000);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 1000);
        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance + 10000);
    }

    function testSweep_revertsCallerIsNotTheOwner() public {
        address sender = vm.addr(1);

        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(sender);

        poolContract.sweep(address(randomToken));
    }
}
