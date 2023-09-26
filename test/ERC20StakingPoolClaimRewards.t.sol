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

        claim(holder);

        assertEq(rewardsToken.balanceOf(holder), 0);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 1000);
    }

    function testClaimRewards_transfersTokensFromContractToHolderWhenHolderHasRewards() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        vm.warp(block.timestamp + 5);

        claim(holder);

        assertEq(rewardsToken.balanceOf(holder), 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 500);

        vm.warp(block.timestamp + 5);

        claim(holder);

        assertEq(rewardsToken.balanceOf(holder), 1000);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 0);
    }

    function testFailClaimRewards_emitsEventWhenHolderHasNoReward() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        addRewards(1000, 10);

        // here we dont go in future.

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit ClaimRewards(holder, 0);

        claim(holder);
    }

    function testClaimRewards_emitsEventWhenHolderHasRewards() public {
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
