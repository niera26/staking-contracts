// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolUnstakeTest is ERC20StakingPoolBaseTest {
    event TokenUnstacked(address indexed addr, uint256 amount);
    event RewardsClaimed(address indexed addr, uint256 amount);

    function testUnstake_decreasesHolderStake() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        uint256 originalHolderStake = poolContract.staked(holder);

        unstake(holder, 500);

        assertEq(poolContract.staked(holder), originalHolderStake - 500);

        unstake(holder, 500);

        assertEq(poolContract.staked(holder), originalHolderStake - 1000);
    }

    function testUnstake_decreasesTotalStaked() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        uint256 originalStakedAmountStored = poolContract.stakedAmountStored();

        unstake(holder, 500);

        assertEq(poolContract.stakedAmountStored(), originalStakedAmountStored - 500);

        unstake(holder, 500);

        assertEq(poolContract.stakedAmountStored(), originalStakedAmountStored - 1000);
    }

    function testUnstake_transfersTokensFromContractToHolder() public {
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

    function testUnstake_emitsTokenUnstaked() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit TokenUnstacked(holder, 1000);

        unstake(holder, 1000);
    }

    function testUnstakeSome_doesNotReduceTotalRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 originalRewardAmountStored = poolContract.rewardAmountStored();

        vm.warp(block.timestamp + 5);

        unstake(holder, 500);

        assertEq(poolContract.rewardAmountStored(), originalRewardAmountStored);
    }

    function testUnstakeAll_doesNotReduceTotalRewardsWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 originalRewardAmountStored = poolContract.rewardAmountStored();

        unstake(holder, 1000);

        assertEq(poolContract.rewardAmountStored(), originalRewardAmountStored);
    }

    function testUnstakeAll_reducesTotalRewardsWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 originalRewardAmountStored = poolContract.rewardAmountStored();

        vm.warp(block.timestamp + 5);

        unstake(holder, 1000);

        assertEq(poolContract.rewardAmountStored(), originalRewardAmountStored - 500);
    }

    function testUnstakeSome_doesNotTransferTokenFromContractToHolder() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 holderOriginalBalance = rewardsToken.balanceOf(holder);
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        vm.warp(block.timestamp + 5);

        unstake(holder, 500);

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance);
    }

    function testUnstakeAll_doesNotTransferTokenFromContractToHolderWhenHolderHasNoRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 holderOriginalBalance = rewardsToken.balanceOf(holder);
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        unstake(holder, 1000);

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance);
    }

    function testUnstakeAll_transfersTokensFromContractToHolderWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 holderOriginalBalance = rewardsToken.balanceOf(holder);
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        vm.warp(block.timestamp + 5);

        unstake(holder, 1000);

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance + 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance - 500);
    }

    function testFailUnstakeSome_emitsRewardsClaimed() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsClaimed(holder, 0);

        unstake(holder, 500);
    }

    function testFailUnstakeAll_emitsRewardsClaimedWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        // here we dont go in future.

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsClaimed(holder, 0);

        unstake(holder, 1000);
    }

    function testUnstakeAll_emitsRewardsClaimedWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 10);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsClaimed(holder, 1000);

        unstake(holder, 1000);
    }

    function testUnstake_revertsZeroAmount() public {
        address holder = vm.addr(1);

        vm.expectRevert(ERC20StakingPoolBase.ZeroAmount.selector);

        vm.prank(holder);

        poolContract.unstake(0);
    }

    function testUnstake_revertsInsufficientStakedAmount() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        vm.expectRevert(abi.encodeWithSelector(ERC20StakingPoolBase.InsufficientStakedAmount.selector, 1000, 1001));

        vm.prank(holder);

        poolContract.unstake(1001);
    }

    function testUnstake_revertsPaused() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        poolContract.pause();

        vm.expectRevert("Pausable: paused");

        vm.prank(holder);

        poolContract.unstake(1000);

        poolContract.unpause();

        vm.prank(holder);

        poolContract.unstake(1000);
    }
}
