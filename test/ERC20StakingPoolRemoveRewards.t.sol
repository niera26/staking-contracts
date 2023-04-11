// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolRemoveRewardsTest is ERC20StakingPoolBaseTest {
    function testRemoveRewards_revertsCallerIsNotTheOwner() public {
        address sender = vm.addr(1);

        vm.expectRevert("Ownable: caller is not the owner");

        vm.prank(sender);

        poolContract.removeRewards();
    }
}
