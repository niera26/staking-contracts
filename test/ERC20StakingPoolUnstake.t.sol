// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolUnstakeTest is ERC20StakingPoolBaseTest {
    event TokenUnstacked(address indexed holder, uint256 amount);

    function testStake_decreasesHolderStake() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        uint256 originalHolderStake = poolContract.staked(holder);

        vm.prank(holder);

        poolContract.unstake(500);

        assertEq(poolContract.staked(holder), originalHolderStake - 500);

        vm.prank(holder);

        poolContract.unstake(500);

        assertEq(poolContract.staked(holder), originalHolderStake - 1000);
    }

    function testStake_decreasesTotalStaked() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        uint256 originalTotalStaked = poolContract.totalStaked();

        vm.prank(holder);

        poolContract.unstake(500);

        assertEq(poolContract.totalStaked(), originalTotalStaked - 500);

        vm.prank(holder);

        poolContract.unstake(500);

        assertEq(poolContract.totalStaked(), originalTotalStaked - 1000);
    }

    function testStake_transfersTokensFromContractToHolder() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        uint256 holderOriginalBalance = stakingToken.balanceOf(holder);
        uint256 contractOriginalBalance = stakingToken.balanceOf(address(poolContract));

        vm.prank(holder);

        poolContract.unstake(500);

        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance + 500);
        assertEq(stakingToken.balanceOf(address(poolContract)), contractOriginalBalance - 500);

        vm.prank(holder);

        poolContract.unstake(500);

        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance + 1000);
        assertEq(stakingToken.balanceOf(address(poolContract)), contractOriginalBalance - 1000);
    }

    function testStake_emitsTokenUnstaked() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit TokenUnstacked(holder, 1000);

        vm.prank(holder);

        poolContract.unstake(1000);
    }

    function testStake_revertsZeroAmount() public {
        address holder = vm.addr(1);

        vm.expectRevert(ERC20StakingPool.ZeroAmount.selector);

        vm.prank(holder);

        poolContract.unstake(0);
    }

    function testStake_revertsInsufficientStakedAmount() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(ERC20StakingPool.InsufficientStakedAmount.selector, 1000, 1001));

        vm.prank(holder);

        poolContract.unstake(1001);
    }

    function testStake_revertsPaused() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 1000);
        poolContract.stake(1000);
        vm.stopPrank();

        poolContract.pause();

        vm.expectRevert("Pausable: paused");

        vm.prank(holder);

        poolContract.unstake(1000);

        poolContract.unpause();

        vm.prank(holder);

        poolContract.unstake(1000);
    }
}
