// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./ERC20StakingPoolBase.t.sol";

contract ERC20StakingPoolGettersTest is ERC20StakingPoolBaseTest {
    function testStakingToken() public {
        assertEq(address(poolContract.stakingToken()), address(stakingToken));
    }

    function testRewardsTokenAddress() public {
        assertEq(address(poolContract.rewardsToken()), address(rewardsToken));
    }

    function testTotalStakedAmount() public {
        address holder = vm.addr(1);

        stake(holder, 1000);

        assertEq(poolContract.totalStakedTokens(), 1000);

        stake(holder, 1000);

        assertEq(poolContract.totalStakedTokens(), 2000);
    }
}
