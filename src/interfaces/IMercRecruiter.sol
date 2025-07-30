// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMercRecruiter {
    event MercsRecruited(address indexed player, uint256 level, uint256 amount, IERC20[] resources);

    function recruitMercs(IERC20[] calldata resources, uint256 amount) external;
    function getRequiredLevel(IERC20[] calldata resources) external pure returns (uint256);
    function canRecruitMercs(address player, IERC20[] calldata resources, uint256 amount)
        external
        view
        returns (bool);
}
