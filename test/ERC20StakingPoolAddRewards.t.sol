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
        uint256 originalRemainingRewards = poolContract.remainingRewards();

        addRewards(500, 10);

        assertEq(poolContract.remainingRewards(), originalRemainingRewards + 500);

        addRewards(500, 10);

        assertEq(poolContract.remainingRewards(), originalRemainingRewards + 1000);
    }

    function testAddRewards_increasesRemainingSeconds() public {
        addRewards(500, 10);

        assertEq(poolContract.remainingSeconds(), 10);

        addRewards(500, 20);

        assertEq(poolContract.remainingSeconds(), 30);
    }

    function testAddRewards_transfersRewardsFromOwnerToContract() public {
        uint256 ownerOriginalBalance = rewardsToken.balanceOf(address(this));
        uint256 contractOriginalBalance = rewardsToken.balanceOf(address(poolContract));

        addRewards(500, 10);

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance - 500);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance + 500);

        addRewards(500, 10);

        assertEq(rewardsToken.balanceOf(address(this)), ownerOriginalBalance - 1000);
        assertEq(rewardsToken.balanceOf(address(poolContract)), contractOriginalBalance + 1000);
    }

    function testAddRewards_emitsAddRewards() public {
        vm.expectEmit(true, true, true, true, address(poolContract));

        emit AddRewards(address(this), 1000, 10);

        addRewards(1000, 10);
    }

    function testAddRewards_allowsOperatorRoleToAddRewards() public {
        address sender = vm.addr(1);

        poolContract.grantRole(poolContract.OPERATOR_ROLE(), sender);

        uint256 originalRemainingrewards = poolContract.remainingRewards();

        rewardsToken.transfer(sender, 500);

        vm.startPrank(sender);
        rewardsToken.approve(address(poolContract), 500);
        addRewards(500, 10);
        vm.stopPrank();

        assertEq(poolContract.remainingRewards(), originalRemainingrewards + 500);

        rewardsToken.transfer(sender, 500);

        vm.startPrank(sender);
        rewardsToken.approve(address(poolContract), 500);
        addRewards(500, 10);
        vm.stopPrank();

        assertEq(poolContract.remainingRewards(), originalRemainingrewards + 1000);
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

    function testAddRewards_revertsZeroDuration() public {
        rewardsToken.approve(address(poolContract), 1000);

        vm.expectRevert(ERC20StakingPool.ZeroDuration.selector);

        poolContract.addRewards(1000, 0);
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
