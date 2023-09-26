// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolPauseTest is ERC20StakingPoolBaseTest {
    function testPause_canBeCalledByOwner() public {
        poolContract.pause();
    }

    function testPause_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.pause();
    }

    function testUnpause_canBeCalledByOwner() public {
        poolContract.pause();
        poolContract.unpause();
    }

    function testUnpause_revertsCallerIsNotAdminRole() public {
        address sender = vm.addr(1);

        poolContract.pause();

        vm.expectRevert(notAdminRoleErrorMessage(sender));

        vm.prank(sender);

        poolContract.unpause();
    }
}
