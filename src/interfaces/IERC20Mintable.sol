// SPDX-License-Identifier: AGPL-3.0-only
// Authored by Plastic Digits
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;
}
