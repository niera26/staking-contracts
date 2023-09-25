// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolUnstakeTest is ERC20StakingPoolBaseTest {
    event UnstakeTokens(address indexed addr, uint256 amount);
    event ClaimRewards(address indexed addr, uint256 amount);

    function testUnstakeTokens_decreasesHolderStake() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        uint256 originalStakedTokens = poolContract.stakedTokens(holder);

        unstake(holder, 500);

        assertEq(poolContract.stakedTokens(holder), originalStakedTokens - 500);

        unstake(holder, 500);

        assertEq(poolContract.stakedTokens(holder), originalStakedTokens - 1000);
    }

    function testUnstakeTokens_decreasesTotalStakedTokens() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        uint256 originalTotalStakedTokens = poolContract.totalStakedTokens();

        unstake(holder, 500);

        assertEq(poolContract.totalStakedTokens(), originalTotalStakedTokens - 500);

        unstake(holder, 500);

        assertEq(poolContract.totalStakedTokens(), originalTotalStakedTokens - 1000);
    }

    function testUnstakeTokens_transfersTokensFromContractToHolder() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        uint256 holderOriginalBalance = stakingToken.balanceOf(holder);
        uint256 contractOriginalBalance = stakingToken.balanceOf(address(poolContract));

        unstake(holder, 500);

        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance + 500);
        assertEq(stakingToken.balanceOf(address(poolContract)), contractOriginalBalance - 500);

        unstake(holder, 500);

        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance + 1000);
        assertEq(stakingToken.balanceOf(address(poolContract)), contractOriginalBalance - 1000);
    }

    function testUnstakeTokens_emitsUnstakeTokens() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit UnstakeTokens(holder, 1000);

        unstake(holder, 1000);
    }

    function testUnstakeTokens_revertsZeroAmount() public {
        address holder = vm.addr(1);

        vm.expectRevert(ERC20StakingPool.ZeroAmount.selector);

        vm.prank(holder);

        poolContract.unstakeTokens(0);
    }

    function testUnstakeTokens_revertsInsufficientStakedAmount() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        vm.expectRevert(abi.encodeWithSelector(ERC20StakingPool.InsufficientStakedAmount.selector, 1000, 1001));

        vm.prank(holder);

        poolContract.unstakeTokens(1001);
    }

    function testUnstakeTokens_revertsPaused() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        poolContract.pause();

        vm.expectRevert("Pausable: paused");

        vm.prank(holder);

        poolContract.unstakeTokens(1000);

        poolContract.unpause();

        vm.prank(holder);

        poolContract.unstakeTokens(1000);
    }
}
