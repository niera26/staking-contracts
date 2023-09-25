// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolStakeTokensTest is ERC20StakingPoolBaseTest {
    event StakeTokens(address indexed addr, uint256 amount);

    function testStakeTokens_increasesHolderStake() public {
        address holder = vm.addr(1);

        uint256 originalStakedTokens = poolContract.stakedTokens(holder);

        stake(holder, 500);

        assertEq(poolContract.stakedTokens(holder), originalStakedTokens + 500);

        stake(holder, 500);

        assertEq(poolContract.stakedTokens(holder), originalStakedTokens + 1000);
    }

    function testStakeTokens_increasesTotalStakedTokens() public {
        address holder = vm.addr(1);

        uint256 originalTotalStakedTokens = poolContract.totalStakedTokens();

        stake(holder, 500);

        assertEq(poolContract.totalStakedTokens(), originalTotalStakedTokens + 500);

        stake(holder, 500);

        assertEq(poolContract.totalStakedTokens(), originalTotalStakedTokens + 1000);
    }

    function testStakeTokens_transfersTokensFromHolderToContract() public {
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

    function testStakeTokens_emitsStakeTokens() public {
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
