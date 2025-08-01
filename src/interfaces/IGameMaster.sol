// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGameMaster {
    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 burned);
    event WithdrawalRateLimitUpdated(uint256 indexed oldLimit, uint256 indexed newLimit);

    function deposit(IERC20 token, uint256 amount) external;
    function withdraw(IERC20 token, uint256 amount) external;
    function getBalance(address user, IERC20 token) external view returns (uint256);
    function spendBalance(address user, IERC20 token, uint256 amount) external;
    function addBalance(address user, IERC20 token, uint256 amount) external;
    function transferBalance(address userFrom, address userTo, IERC20 token, uint256 amount) external;

    // Rate limiting functions
    function withdrawalRateLimitBps() external view returns (uint256);
    function setWithdrawalRateLimit(uint256 _rateLimitBps) external;
    function getWithdrawalWindowData(IERC20 token)
        external
        view
        returns (uint256 windowStart, uint256 amountWithdrawn, uint256 rateLimit);
}
