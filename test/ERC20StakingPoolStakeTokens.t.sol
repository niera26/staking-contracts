// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolStakeTokensTest is ERC20StakingPoolBaseTest {
    event StakeTokens(address indexed addr, uint256 amount);

    function testStakeTokens_increasesHolderStake() public {
        address holder = vm.addr(1);

        stake(holder, 500);

        assertEq(poolContract.stakedTokens(holder), 500);

        stake(holder, 1000);

        assertEq(poolContract.stakedTokens(holder), 1500);
    }

    function testStakeTokens_increasesTotalStakedTokens() public {
        address holder = vm.addr(1);

        stake(holder, 500);

        assertEq(poolContract.totalStakedTokens(), 500);

        stake(holder, 1000);

        assertEq(poolContract.totalStakedTokens(), 1500);
    }

    function testStakeTokens_transfersTokensFromHolderToContract() public {
        address holder = vm.addr(1);

        stake(holder, 500);

        assertEq(stakingToken.balanceOf(holder), 0);
        assertEq(stakingToken.balanceOf(address(poolContract)), 500);

        stake(holder, 1000);

        assertEq(stakingToken.balanceOf(holder), 0);
        assertEq(stakingToken.balanceOf(address(poolContract)), 1500);
    }

    function testStakeTokens_emitsEvent() public {
        address holder = vm.addr(1);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit StakeTokens(holder, 1000);

        stake(holder, 1000);
    }

    function testStakeTokens_revertsZeroAmount() public {
        address holder = vm.addr(1);

        vm.expectRevert(ERC20StakingPool.ZeroAmount.selector);

        vm.prank(holder);

        poolContract.stakeTokens(0);
    }

    function testStakeTokens_revertsInsufficientAllowance() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.prank(holder);

        stakingToken.approve(address(poolContract), 999);

        vm.expectRevert("ERC20: insufficient allowance");

        vm.prank(holder);

        poolContract.stakeTokens(1000);
    }

    function testStakeTokens_revertsInsufficientBalance() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 999);

        vm.prank(holder);

        stakingToken.approve(address(poolContract), 1000);

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        vm.prank(holder);

        poolContract.stakeTokens(1000);
    }

    function testStakeTokens_revertsPaused() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        vm.prank(holder);

        stakingToken.approve(address(poolContract), 1000);

        poolContract.pause();

        vm.expectRevert("Pausable: paused");

        vm.prank(holder);

        poolContract.stakeTokens(1000);

        poolContract.unpause();

        vm.prank(holder);

        poolContract.stakeTokens(1000);
    }
}
