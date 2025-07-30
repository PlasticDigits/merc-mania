// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IResourceManager {
    event ResourceAdded(address indexed resource, string name);
    event ResourceRemoved(address indexed resource);

    function addResource(string calldata name, string calldata symbol, string calldata tokenURI)
        external
        returns (address);
    function removeResource(IERC20 resource) external;
    function getResourceCount() external view returns (uint256);
    function getResourceAt(uint256 index) external view returns (IERC20);
    function isResource(IERC20 resource) external view returns (bool);
    function getAllResources() external view returns (IERC20[] memory);
    function validateResources(IERC20[] calldata resources) external view;
    function GOLD() external view returns (IERC20);
}
