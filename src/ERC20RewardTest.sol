// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20RewardTest is ERC20 {
    constructor() ERC20("Reward Test Token", "RWTT") {
        _mint(msg.sender, 1_000_000_000 * (10 ** decimals()));
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
