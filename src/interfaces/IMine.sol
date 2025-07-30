// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMine {
    event MineSeized(address indexed newOwner, uint256 attackerLosses, uint256 defenderLosses);
    event MineAbandoned(address indexed owner, uint256 mercsLost);
    event ResourcesClaimed(address indexed owner, uint256 amount);
    event DefenseBoostActivated(address indexed owner, uint256 goldCost, uint256 expiresAt);

    struct MineInfo {
        IERC20 resource;
        address owner;
        uint256 lastSeized;
        uint256 createdAt;
        uint256 defenseBoostExpiry;
    }

    struct BattleLogEntry {
        uint256 timestamp;
        address attacker;
        address previousOwner;
        IERC20 attackerMercToken;
        uint256 attackerMercAmount;
        IERC20 defenderMercToken;
        uint256 defenderMercAmount;
        uint256 attackerLosses;
        uint256 defenderLosses;
        bool attackerWon;
    }

    function seize(uint256 mercLevel) external;
    function abandon() external;
    function claimResources() external;
    function activateDefenseBoost() external;
    function getMineInfo() external view returns (MineInfo memory);
    function getCurrentProduction() external view returns (uint256);
    function getAccumulatedResources() external view returns (uint256);
    function calculateBattlePower(uint256 mercLevel, uint256 mercAmount, bool isDefending)
        external
        view
        returns (uint256);
    function getBattleLogCount() external view returns (uint256);
    function getBattleLogEntry(uint256 index) external view returns (BattleLogEntry memory);
    function getBattleLogEntries(uint256 startIndex, uint256 count) external view returns (BattleLogEntry[] memory);
}
