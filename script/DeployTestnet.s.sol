// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/ERC20RewardTest.sol";
import "../src/ERC20StakedTest.sol";
import "../src/ERC20StakingPool.sol";

contract DeployTestnet is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY_TESTNET");

        vm.startBroadcast(deployerPrivateKey);

        ERC20StakedTest stakingToken = new ERC20StakedTest();
        ERC20RewardTest rewardsToken = new ERC20RewardTest();

        new ERC20StakingPool(address(stakingToken), address(rewardsToken));

        vm.stopBroadcast();
    }
}
