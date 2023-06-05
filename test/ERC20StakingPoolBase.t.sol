// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "openzeppelin/contracts/token/ERC20/ERC20.sol";
import "openzeppelin/contracts/utils/Strings.sol";
import "../src/ERC20StakedTest.sol";
import "../src/ERC20RewardTest.sol";
import "../src/ERC20StakingPool.sol";
import "../src/ERC20StakingPoolEvents.sol";

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
    ERC20StakedTest internal stakingToken;
    IERC20Metadata internal rewardsToken;
    IERC20Metadata internal randomToken;
    ERC20StakingPool internal poolContract;

    function setUp() public {
        stakingToken = new ERC20StakedTest();
        rewardsToken = new ERC20RewardTest();
        randomToken = new ERC20Mock("Random token", "RDTT", 18);
        poolContract = new ERC20StakingPool(address(stakingToken), address(rewardsToken), 1_000_000_000, 365 days);
        stakingToken.mint(1_000_000 * (10 ** stakingToken.decimals()));

        poolContract.grantRole(poolContract.OPERATOR_ROLE(), address(this));
    }

    function stake(address holder, uint256 amount) internal {
        stakingToken.transfer(holder, amount);
        vm.startPrank(holder);
        stakingToken.approve(address(poolContract), amount);
        poolContract.stake(amount);
        vm.stopPrank();
    }

    function unstake(address holder, uint256 amount) internal {
        vm.prank(holder);

        poolContract.unstake(amount);
    }

    function addRewards(uint256 amount, uint256 duration) internal {
        rewardsToken.approve(address(poolContract), amount);

        poolContract.addRewards(amount, duration);
    }

    function claim(address holder) internal {
        vm.prank(holder);

        poolContract.claim();
    }

    function notAdminRoleErrorMessage(address sender) internal view returns (bytes memory) {
        return bytes(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(sender),
                " is missing role ",
                Strings.toHexString(uint256(poolContract.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
    }

    function notOperatorRoleErrorMessage(address sender) internal view returns (bytes memory) {
        return bytes(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(sender),
                " is missing role ",
                Strings.toHexString(uint256(poolContract.OPERATOR_ROLE()), 32)
            )
        );
    }
}
