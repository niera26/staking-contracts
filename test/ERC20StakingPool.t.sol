// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ERC20StakingPool.sol";
import "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * (10 ** decimals()));
    }
}

contract ERC20StakingPoolTest is Test {
    IERC20Metadata private stakingToken;
    IERC20Metadata private rewardsToken;
    ERC20StakingPool private poolContract;

    function setUp() public {
        stakingToken = new ERC20Mock("Staking Token", "STT");
        rewardsToken = new ERC20Mock("Rewards Token", "RWD");
        poolContract = new ERC20StakingPool(address(stakingToken), address(rewardsToken));
    }

    function testHolderCanStakeAndUnstake() public {
        address holder = vm.addr(1);

        stakingToken.transfer(holder, 1000);

        uint256 holderOriginalBalance = stakingToken.balanceOf(holder);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 300);
        poolContract.stake(300);
        vm.stopPrank();

        assertEq(poolContract.totalStaked(), 300);
        assertEq(poolContract.stakedAmount(holder), 300);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance - 300);
        assertEq(stakingToken.balanceOf(address(poolContract)), 300);

        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), 700);
        poolContract.stake(700);
        vm.stopPrank();

        assertEq(poolContract.totalStaked(), 1000);
        assertEq(poolContract.stakedAmount(holder), 1000);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance - 1000);
        assertEq(stakingToken.balanceOf(address(poolContract)), 1000);

        vm.prank(holder);

        poolContract.unstake(200);

        assertEq(poolContract.totalStaked(), 800);
        assertEq(poolContract.stakedAmount(holder), 800);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance - 800);
        assertEq(stakingToken.balanceOf(address(poolContract)), 800);

        vm.prank(holder);

        poolContract.unstake(800);

        assertEq(poolContract.totalStaked(), 0);
        assertEq(poolContract.stakedAmount(holder), 0);
        assertEq(stakingToken.balanceOf(holder), holderOriginalBalance);
        assertEq(stakingToken.balanceOf(address(poolContract)), 0);
    }

    function testHoldersGetProportionalRewards() public {
        address holder1 = vm.addr(1);
        address holder2 = vm.addr(2);

        uint256 holder1OriginalBalance = rewardsToken.balanceOf(holder1);
        uint256 holder2OriginalBalance = rewardsToken.balanceOf(holder2);

        stakingToken.transfer(holder1, 1000);
        stakingToken.transfer(holder2, 1000);

        vm.startPrank(holder1);
        stakingToken.approve(address(poolContract), 300);
        poolContract.stake(300);
        vm.stopPrank();

        vm.startPrank(holder2);
        stakingToken.approve(address(poolContract), 700);
        poolContract.stake(700);
        vm.stopPrank();

        rewardsToken.approve(address(poolContract), 1000);

        poolContract.addRewards(1000);

        assertEq(poolContract.pendingRewards(holder1), 300);
        assertEq(poolContract.pendingRewards(holder2), 700);

        vm.prank(holder1);

        poolContract.claim();

        vm.prank(holder2);

        poolContract.claim();

        assertEq(rewardsToken.balanceOf(holder1), holder1OriginalBalance + 300);
        assertEq(rewardsToken.balanceOf(holder2), holder2OriginalBalance + 700);
    }
}
