// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolAddRewardsTest is ERC20StakingPoolBaseTest {
    event RewardsAdded(address indexed addr, uint256 amount);

    function setOwnerBalanceTo(uint256 amount) private {
        address recipient = vm.addr(1);

        rewardsToken.transfer(recipient, rewardsToken.totalSupply() - amount);
    }

    function testAddRewards_allowsToAddExactOwnerBalance() public {
        setOwnerBalanceTo(1000);

        uint256 originalTotalRewards = poolContract.totalRewards();

        addRewards(1000, 10);

        assertEq(poolContract.totalRewards(), originalTotalRewards + 1000);
    }

    function testAddRewards_allowsToAddExactMaxRewardsAmount() public {
        uint256 amount = poolContract.maxRewardsAmount();
        console.log(amount);
        uint256 originalTotalRewards = poolContract.totalRewards();

        addRewards(amount, 10);

        assertEq(poolContract.totalRewards(), originalTotalRewards + amount);
    }

    function testAddRewards_allowsToAddExactMaxRewardsDuration() public {
        uint256 duration = poolContract.maxRewardsDuration();

        uint256 originalTotalRewards = poolContract.totalRewards();

        addRewards(1000, duration);

        assertEq(poolContract.totalRewards(), originalTotalRewards + 1000);
    }

    function testAddRewards_increasesTotalRewards() public {
        uint256 originalTotalRewards = poolContract.totalRewards();

        addRewards(500, 10);

        assertEq(poolContract.totalRewards(), originalTotalRewards + 500);

        vm.warp(block.timestamp + 5);

        addRewards(500, 10);

        assertEq(poolContract.totalRewards(), originalTotalRewards + 1000);
    }

    function testAddRewards_increasesRemainingRewards() public {
        uint256 originalRemainingRewards = poolContract.totalRewards();

        addRewards(500, 10);

        assertEq(poolContract.remainingRewards(), originalRemainingRewards + 500);

        addRewards(500, 10);

        assertEq(poolContract.remainingRewards(), originalRemainingRewards + 1000);
    }

    function testAddRewards_updatesRemainingSeconds() public {
        addRewards(500, 10);

        assertEq(poolContract.remainingSeconds(), 10);

        addRewards(500, 20);

        assertEq(poolContract.remainingSeconds(), 30);
    }

    function testAddRewards_revertsCallerIsNotTheOwner() public {
        address sender = vm.addr(1);

        rewardsToken.approve(address(poolContract), 1000);

        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(sender);

        poolContract.addRewards(1000, 10);
    }

    function testAddRewards_revertsZeroAmount() public {
        vm.expectRevert(ERC20StakingPool.ZeroAmount.selector);

        poolContract.addRewards(0, 10);
    }

    function testAddRewards_revertsZeroDuration() public {
        rewardsToken.approve(address(poolContract), 1000);

        vm.expectRevert(ERC20StakingPool.ZeroDuration.selector);

        poolContract.addRewards(1000, 0);
    }

    function testAddRewards_revertsRewardsAmountTooLarge() public {
        uint256 amount = poolContract.maxRewardsAmount();

        rewardsToken.approve(address(poolContract), amount + 1);

        vm.expectRevert(abi.encodeWithSelector(ERC20StakingPool.RewardsAmountTooLarge.selector, amount, amount + 1));

        poolContract.addRewards(amount + 1, 10);
    }

    function testAddRewards_revertsRewardsDurationTooLarge() public {
        uint256 duration = poolContract.maxRewardsDuration();

        rewardsToken.approve(address(poolContract), 1000);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20StakingPool.RewardsDurationTooLarge.selector, duration, duration + 1)
        );

        poolContract.addRewards(1000, duration + 1);
    }

    function testAddRewards_revertsInsufficientAllowance() public {
        rewardsToken.approve(address(poolContract), 999);

        vm.expectRevert("ERC20: insufficient allowance");

        poolContract.addRewards(1000, 10);
    }

    function testAddRewards_revertsInsufficientBalance() public {
        setOwnerBalanceTo(1000);

        rewardsToken.approve(address(poolContract), 1001);

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        poolContract.addRewards(1001, 10);
    }
}
