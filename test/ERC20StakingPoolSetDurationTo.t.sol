// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolSetDurationToTest is ERC20StakingPoolBaseTest {
    event SetDurationTo(address indexed addr, uint256 duration);

    function testSetDurationTo_doesNotUpdateRemainingRewards() public {
        addRewards(1000, 0);

        assertEq(poolContract.remainingRewards(), 1000);

        poolContract.setDurationTo(100);

        assertEq(poolContract.remainingRewards(), 1000);
    }

    function testSetDurationTo_setRemainingSecondsToTheGivenValue() public {
        poolContract.setDurationTo(100);

        assertEq(poolContract.remainingSeconds(), 100);
    }

    function testSetDurationTo_emitsSetDurationTo() public {
        vm.expectEmit(true, true, true, true, address(poolContract));

        emit SetDurationTo(address(this), 100);

        poolContract.setDurationTo(100);
    }

    function testSetDurationTo_allowsDurationUntilOwerflow() public {
        uint256 amount = rewardsToken.totalSupply();
        uint256 duration = type(uint256).max / amount;

        addRewards(amount, 0);

        poolContract.setDurationTo(duration);

        assertEq(poolContract.remainingRewards(), amount);
        assertEq(poolContract.remainingSeconds(), duration);
    }

    function testSetDurationTo_revertsCallerIsNotOperatorRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notOperatorRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.setDurationTo(100);
    }

    function testSetDurationTo_revertsOverflow() public {
        uint256 amount = rewardsToken.totalSupply();
        uint256 duration = (type(uint256).max / amount) + 1;

        addRewards(amount, 0);

        vm.expectRevert(ERC20StakingPool.WillOverflow.selector);

        poolContract.setDurationTo(duration);
    }
}
