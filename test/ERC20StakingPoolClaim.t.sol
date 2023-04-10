// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolClaimTest is ERC20StakingPoolBaseTest {
    event RewardsClaimed(address indexed holder, uint256 amount);

    function testClaim_doesNotReduceTotalRewardsWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 originalTotalRewards = poolContract.totalRewards();

        claim(holder);

        assertEq(poolContract.totalRewards(), originalTotalRewards);
    }

    function testClaim_reducesTotalRewardsWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 originalTotalRewards = poolContract.totalRewards();

        vm.warp(block.timestamp + 5);

        claim(holder);

        assertEq(poolContract.totalRewards(), originalTotalRewards - 500);
    }

    function testClaim_doesNotTransferTokenFromContractToHolderWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 holderOriginalBalance = rewardsToken.balanceOf(holder);
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        claim(holder);

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance);
    }

    function testClaim_transfersTokensFromContractToHolderWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 holderOriginalBalance = rewardsToken.balanceOf(holder);
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        vm.warp(block.timestamp + 5);

        claim(holder);

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance + 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance - 500);

        vm.warp(block.timestamp + 5);

        claim(holder);

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance + 1000);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance - 1000);
    }

    function testFailClaim_emitsRewardsClaimedWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        // here we dont go in future.

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsClaimed(holder, 0);

        claim(holder);
    }

    function testClaim_emitsRewardsClaimedWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 10);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit RewardsClaimed(holder, 1000);

        claim(holder);
    }

    function testClaim_revertsPaused() public {
        address holder = vm.addr(1);

        poolContract.pause();

        vm.expectRevert("Pausable: paused");

        claim(holder);

        poolContract.unpause();

        claim(holder);
    }
}
