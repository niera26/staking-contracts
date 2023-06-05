// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/ERC20RewardTest.sol";
import "../src/ERC20StakedTest.sol";
import "../src/ERC20StakingPool.sol";

contract DeployTest is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address rewardsTokenAddress = vm.envAddress("REWARDS_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        ERC20StakedTest stakingToken = new ERC20StakedTest();

        new ERC20StakingPool(address(stakingToken), rewardsTokenAddress, 1_000_000_000, 365 days);

        vm.stopBroadcast();
    }
}
