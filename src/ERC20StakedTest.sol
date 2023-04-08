// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20StakedTest is ERC20 {
    constructor() ERC20("Staking Test Token", "SKTT") {}

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
