// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolClaimRewardsTest is ERC20StakingPoolBaseTest {
    event ClaimRewards(address indexed addr, uint256 amount);

    function testClaimRewards_doesNotTransferTokenFromContractToHolderWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        uint256 holderOriginalBalance = rewardsToken.balanceOf(holder);
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        claim(holder);

        assertEq(rewardsToken.balanceOf(holder), holderOriginalBalance);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance);
    }

    function testClaimRewards_transfersTokensFromContractToHolderWhenHolderHasRewards() public {
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

    function testFailClaimRewards_emitsClaimRewardsWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        // here we dont go in future.

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit ClaimRewards(holder, 0);

        claim(holder);
    }

    function testClaimRewards_emitsClaimRewardsWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 10);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit ClaimRewards(holder, 1000);

        claim(holder);
    }

    function testClaimRewards_revertsPaused() public {
        address holder = vm.addr(1);

        poolContract.pause();

        vm.expectRevert("Pausable: paused");

        claim(holder);

        poolContract.unpause();

        claim(holder);
    }
}
