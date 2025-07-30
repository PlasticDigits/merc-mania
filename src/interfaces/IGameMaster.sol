// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGameMaster {
    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 burned);

    function deposit(IERC20 token, uint256 amount) external;
    function withdraw(IERC20 token, uint256 amount) external;
    function getBalance(address user, IERC20 token) external view returns (uint256);
    function spendBalance(address user, IERC20 token, uint256 amount) external;
    function addBalance(address user, IERC20 token, uint256 amount) external;
    function transferBalance(address userFrom, address userTo, IERC20 token, uint256 amount) external;
}
