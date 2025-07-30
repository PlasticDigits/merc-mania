// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.23;

interface IPausable {
    function pause() external;

    function unpause() external;
}
