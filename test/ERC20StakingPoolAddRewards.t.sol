// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolAddRewardsTest is ERC20StakingPoolBaseTest {
    event AddRewards(address indexed addr, uint256 amount, uint256 duration);

    function setOwnerBalanceTo(uint256 amount) private {
        address recipient = vm.addr(1);

        rewardsToken.transfer(recipient, rewardsToken.totalSupply() - amount);
    }

    function testAddRewards_increasesRemainingRewards() public {
        addRewards(500, 0);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), 0);

        addRewards(1000, 0);

        assertEq(poolContract.remainingRewards(), 1500);
        assertEq(poolContract.remainingSeconds(), 0);
    }

    function testAddRewards_allowsToincreaseRemainingSeconds() public {
        addRewards(500, 10);

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), 10);

        addRewards(1000, 20);

        assertEq(poolContract.remainingRewards(), 1500);
        assertEq(poolContract.remainingSeconds(), 30);
    }

    function testAddRewards_transfersRewardsFromOwnerToContract() public {
        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));

        addRewards(500, 0);

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance - 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 500);

        addRewards(1000, 0);

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance - 1500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), 1500);
    }

    function testAddRewards_emitsEvent() public {
        vm.expectEmit(true, true, true, true, address(poolContract));

        emit AddRewards(address(this), 1000, 10);

        addRewards(1000, 10);
    }

    function testAddRewards_allowsOperatorRoleToAddRewards() public {
        address sender = vm.addr(1);

        poolContract.grantRole(poolContract.OPERATOR_ROLE(), sender);

        rewardsToken.transfer(sender, 500);

        vm.startPrank(sender);
        rewardsToken.approve(address(poolContract), 500);
        addRewards(500, 10);
        vm.stopPrank();

        assertEq(poolContract.remainingRewards(), 500);
        assertEq(poolContract.remainingSeconds(), 10);

        rewardsToken.transfer(sender, 1000);

        vm.startPrank(sender);
        rewardsToken.approve(address(poolContract), 1000);
        addRewards(1000, 20);
        vm.stopPrank();

        assertEq(poolContract.remainingRewards(), 1500);
        assertEq(poolContract.remainingSeconds(), 30);
    }

    function testAddRewards_allowsDurationUntilOwerflow() public {
        uint256 amount = rewardsToken.totalSupply();
        uint256 duration = type(uint256).max / amount;

        rewardsToken.approve(address(poolContract), amount);

        poolContract.addRewards(amount, duration);

        assertEq(poolContract.remainingRewards(), amount);
        assertEq(poolContract.remainingSeconds(), duration);
    }

    function testAddRewards_revertsCallerIsNotOperatorRole() public {
        address sender = vm.addr(1);

        rewardsToken.approve(address(poolContract), 1000);

        vm.expectRevert(notOperatorRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.addRewards(1000, 10);
    }

    function testAddRewards_revertsZeroAmount() public {
        vm.expectRevert(ERC20StakingPool.ZeroAmount.selector);

        poolContract.addRewards(0, 10);
    }

    function testAddRewards_revertsInsufficientAllowance() public {
        rewardsToken.approve(address(poolContract), 999);

        vm.expectRevert("ERC20: insufficient allowance");

        poolContract.addRewards(1000, 0);
    }

    function testAddRewards_revertsInsufficientBalance() public {
        setOwnerBalanceTo(1000);

        rewardsToken.approve(address(poolContract), 1001);

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        poolContract.addRewards(1001, 0);
    }

    function testAddRewards_revertsOverflow() public {
        uint256 amount = rewardsToken.totalSupply();
        uint256 duration = (type(uint256).max / amount) + 1;

        rewardsToken.approve(address(poolContract), amount);

        vm.expectRevert(ERC20StakingPool.WillOverflow.selector);

        poolContract.addRewards(amount, duration);
    }
}
