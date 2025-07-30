// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

interface IGuardERC20 {
    function check(address sender, address recipient, uint256 amount) external;
}
