// SPDX-License-Identifier: AGPL-3.0-only
// Authored by Plastic Digits
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Burnable is IERC20 {
    function burn(uint256 value) external;
    function burnFrom(address account, uint256 value) external;
}
