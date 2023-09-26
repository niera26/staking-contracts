// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolSetDurationUntilTest is ERC20StakingPoolBaseTest {
    event SetDurationUntil(address indexed addr, uint256 timestamp, uint256 duration);

    function testSetDurationUntil_doesNotUpdateRemainingRewards() public {
        vm.warp(1000);

        addRewards(1000, 0);

        assertEq(poolContract.remainingRewards(), 1000);

        poolContract.setDurationUntil(1100);

        assertEq(poolContract.remainingRewards(), 1000);
    }

    function testSetDurationUntil_setRemainingSecondsUntilTheGivenTime() public {
        vm.warp(1000);

        poolContract.setDurationUntil(1100);

        assertEq(poolContract.remainingSeconds(), 100);
    }

    function testSetDurationUntil_emitsEvent() public {
        vm.warp(1000);

        vm.expectEmit(true, true, true, true, address(poolContract));

        emit SetDurationUntil(address(this), 1100, 100);

        poolContract.setDurationUntil(1100);
    }

    function testSetDurationUntil_allowsToSetDurationUntilCurrentTime() public {
        vm.warp(1000);

        poolContract.setDurationUntil(1000);

        assertEq(poolContract.remainingSeconds(), 0);
    }

    function testSetDurationUntil_allowsDurationUntilOwerflow() public {
        vm.warp(1000);

        uint256 amount = rewardsToken.totalSupply();
        uint256 duration = type(uint256).max / amount;

        addRewards(amount, 0);

        poolContract.setDurationUntil(1000 + duration);

        assertEq(poolContract.remainingRewards(), amount);
        assertEq(poolContract.remainingSeconds(), duration);
    }

    function testSetDurationUntil_revertsCallerIsNotOperatorRole() public {
        vm.warp(1000);

        address sender = vm.addr(1);

        vm.expectRevert(notOperatorRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.setDurationUntil(1100);
    }

    function testSetDurationUntil_revertsInvalidTimestamp() public {
        vm.warp(1000);

        vm.expectRevert(abi.encodeWithSelector(ERC20StakingPool.InvalidTimestamp.selector, 999));

        poolContract.setDurationUntil(999);
    }

    function testSetDurationUntil_revertsOverflow() public {
        vm.warp(1000);

        uint256 amount = rewardsToken.totalSupply();
        uint256 duration = (type(uint256).max / amount) + 1;

        addRewards(amount, 0);

        vm.expectRevert(ERC20StakingPool.WillOverflow.selector);

        poolContract.setDurationTo(1000 + duration);
    }
}
