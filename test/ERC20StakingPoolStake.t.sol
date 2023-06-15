// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolStakeTest is ERC20StakingPoolBaseTest {
    function testStake_increasesHolderStake() public {
        address holder = vm.addr(1);

        uint256 originalHolderStake = poolContract.staked(holder);

        stake(holder, 500);

        assertEq(poolContract.staked(holder), originalHolderStake + 500);

        stake(holder, 500);

        assertEq(poolContract.staked(holder), originalHolderStake + 1000);
    }

    function testStake_increasesTotalStaked() public {
        address holder = vm.addr(1);

        uint256 originalStakedAmountStored = poolContract.stakedAmountStored();

        stake(holder, 500);

        assertEq(poolContract.stakedAmountStored(), originalStakedAmountStored + 500);

        stake(holder, 500);

        assertEq(poolContract.stakedAmountStored(), originalStakedAmountStored + 1000);
    }

    function testStake_transfersTokensFromHolderToContract() public {
        address holder = vm.addr(1);

        uint256 holderOriginalBalance = stakingToken.balanceOf(holder);
        uint256 contractOriginalBalance = stakingToken.balanceOf(address(poolContract));

        stake(holder, 500);

        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance);
        assertEq(stakingToken.balanceOf(address(poolContract)), contractOriginalBalance + 500);

        stake(holder, 500);

        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance);
        assertEq(stakingToken.balanceOf(address(poolContract)), contractOriginalBalance + 1000);
    }

    function testStake_emitsStake() public {
        address holder = vm.addr(1);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit Stake(holder, 1000);

        stake(holder, 1000);
    }

    function testStake_revertsZeroAmount() public {
        address holder = vm.addr(1);

        vm.expectRevert(ERC20StakingPool.ZeroAmount.selector);

        vm.prank(holder);

        poolContract.stake(0);
    }

    function testStake_revertsInsufficientAllowance() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.prank(holder);

        stakingToken.approve(address(poolContract), 999);

        vm.expectRevert("ERC20: insufficient allowance");

        vm.prank(holder);

        poolContract.stake(1000);
    }

    function testStake_revertsInsufficientBalance() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 999);

        vm.prank(holder);

        stakingToken.approve(address(poolContract), 1000);

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        vm.prank(holder);

        poolContract.stake(1000);
    }

    function testStake_revertsPaused() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.prank(holder);

        stakingToken.approve(address(poolContract), 1000);

        poolContract.pause();

        vm.expectRevert("Pausable: paused");

        vm.prank(holder);

        poolContract.stake(1000);

        poolContract.unpause();

        vm.prank(holder);

        poolContract.stake(1000);
    }
}
