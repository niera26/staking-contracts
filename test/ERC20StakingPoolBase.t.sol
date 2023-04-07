// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ERC20StakingPool.sol";
import "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 __decimals) ERC20(name, symbol) {
        _decimals = __decimals;

        _mint(msg.sender, 10_000_000_000 * (10 ** decimals()));
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract ERC20StakingPoolBaseTest is Test {
    IERC20Metadata internal stakingToken;
    IERC20Metadata internal rewardsToken;
    ERC20StakingPool internal poolContract;

    function setUp() public {
        stakingToken = new ERC20Mock("Staking Token", "STT", 18);
        rewardsToken = new ERC20Mock("Rewards Token", "RWD", 6);
        poolContract = new ERC20StakingPool(address(stakingToken), address(rewardsToken));
    }
}
