// SPDX-License-Identifier: SEE LICENSE IN LICENSE.md
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenB is ERC20 {
    constructor() ERC20("Utonagan", "UTNG") {
        _mint(msg.sender, 1_000_000 ether);
    }
}