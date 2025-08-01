// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

/**
 * @title PlayerStats
 * @notice Contract for tracking individual player statistics across all game actions
 * @dev This contract maintains comprehensive statistics for each player's activities
 *      including token deposits/withdrawals, mercenary recruitment, mine operations, and combat
 * @author Merc Mania Development Team
 */
contract PlayerStats is AccessManaged {
    /// @notice Struct containing all statistics for a specific player
    struct PlayerStatistics {
        // Token Management Stats
        mapping(IERC20 => uint256) totalDeposited;
        mapping(IERC20 => uint256) totalWithdrawn;
        mapping(IERC20 => uint256) totalBurned; // From withdrawals
        uint256 depositCount;
        uint256 withdrawalCount;
        // Mercenary Recruitment Stats
        mapping(uint256 => uint256) mercsRecruitedByLevel; // level -> count
        uint256 totalMercsRecruited;
        uint256 recruitmentCount;
        // Mine Combat Stats
        uint256 totalSeizeAttempts;
        uint256 successfulSeizes;
        uint256 failedSeizes;
        mapping(address => uint256) minesSeizedFrom; // previous owner -> count
        // Mine Management Stats
        uint256 minesAbandoned;
        mapping(IERC20 => uint256) resourcesClaimed; // resource -> amount
        uint256 claimCount;
        uint256 defenseBoostsActivated;
        // Combat Power Stats
        uint256 totalAttackPowerUsed;
        uint256 totalDefensePowerUsed;
        uint256 totalMercsLostInCombat;
        uint256 totalMercsWonInCombat;
    }

    /// @notice Mapping from player address to their statistics
    mapping(address => PlayerStatistics) private _playerStats;

    /// @notice List of all players who have any stats
    address[] public allPlayers;

    /// @notice Mapping to track if a player has been added to allPlayers array
    mapping(address => bool) public playerExists;

    /// @notice Events for stat updates
    event DepositRecorded(address indexed player, IERC20 indexed token, uint256 amount);
    event WithdrawalRecorded(address indexed player, IERC20 indexed token, uint256 amount, uint256 burned);
    event RecruitmentRecorded(address indexed player, uint256 level, uint256 amount);
    event SeizeAttemptRecorded(address indexed player, address indexed mine, bool success, uint256 attackPower);
    event AbandonRecorded(address indexed player, address indexed mine);
    event ClaimRecorded(address indexed player, IERC20 indexed resource, uint256 amount);
    event DefenseBoostRecorded(address indexed player, address indexed mine);
    event CombatStatsRecorded(address indexed player, uint256 mercsLost, uint256 mercsWon);

    /**
     * @notice Constructs the PlayerStats contract
     * @param _authority The access manager contract that controls permissions
     */
    constructor(address _authority) AccessManaged(_authority) {}

    /**
     * @notice Records a player deposit action
     * @dev Only callable by authorized contracts (GameMaster)
     * @param player The player making the deposit
     * @param token The token being deposited
     * @param amount The amount being deposited
     */
    function recordDeposit(address player, IERC20 token, uint256 amount) external restricted {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.totalDeposited[token] += amount;
        stats.depositCount += 1;

        emit DepositRecorded(player, token, amount);
    }

    /**
     * @notice Records a player withdrawal action
     * @dev Only callable by authorized contracts (GameMaster)
     * @param player The player making the withdrawal
     * @param token The token being withdrawn
     * @param amount The total amount requested for withdrawal
     * @param burned The amount that was burned due to withdrawal penalty
     */
    function recordWithdrawal(address player, IERC20 token, uint256 amount, uint256 burned) external restricted {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.totalWithdrawn[token] += (amount - burned); // Actual amount received
        stats.totalBurned[token] += burned;
        stats.withdrawalCount += 1;

        emit WithdrawalRecorded(player, token, amount - burned, burned);
    }

    /**
     * @notice Records a mercenary recruitment action
     * @dev Only callable by authorized contracts (MercRecruiter)
     * @param player The player recruiting mercenaries
     * @param level The level of mercenaries recruited
     * @param amount The number of mercenaries recruited
     */
    function recordRecruitment(address player, uint256 level, uint256 amount) external restricted {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.mercsRecruitedByLevel[level] += amount;
        stats.totalMercsRecruited += amount;
        stats.recruitmentCount += 1;

        emit RecruitmentRecorded(player, level, amount);
    }

    /**
     * @notice Records a mine seizure attempt
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player attempting to seize
     * @param mine The mine being targeted
     * @param success Whether the seizure was successful
     * @param attackPower The total attack power used
     * @param previousOwner The previous owner of the mine (if any)
     */
    function recordSeizeAttempt(address player, address mine, bool success, uint256 attackPower, address previousOwner)
        external
        restricted
    {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.totalSeizeAttempts += 1;
        stats.totalAttackPowerUsed += attackPower;

        if (success) {
            stats.successfulSeizes += 1;
            if (previousOwner != address(0)) {
                stats.minesSeizedFrom[previousOwner] += 1;
            }
        } else {
            stats.failedSeizes += 1;
        }

        emit SeizeAttemptRecorded(player, mine, success, attackPower);
    }

    /**
     * @notice Records a mine abandonment
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player abandoning the mine
     * @param mine The mine being abandoned
     */
    function recordAbandon(address player, address mine) external restricted {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.minesAbandoned += 1;

        emit AbandonRecorded(player, mine);
    }

    /**
     * @notice Records a resource claim action
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player claiming resources
     * @param resource The resource being claimed
     * @param amount The amount of resources claimed
     */
    function recordClaim(address player, IERC20 resource, uint256 amount) external restricted {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.resourcesClaimed[resource] += amount;
        stats.claimCount += 1;

        emit ClaimRecorded(player, resource, amount);
    }

    /**
     * @notice Records a defense boost activation
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player activating the defense boost
     * @param mine The mine where the boost is activated
     */
    function recordDefenseBoost(address player, address mine) external restricted {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.defenseBoostsActivated += 1;

        emit DefenseBoostRecorded(player, mine);
    }

    /**
     * @notice Records combat statistics
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player involved in combat
     * @param mercsLost The number of mercenaries lost
     * @param mercsWon The number of mercenaries won/gained
     * @param defensePowerUsed The defensive power used (if defending)
     */
    function recordCombatStats(address player, uint256 mercsLost, uint256 mercsWon, uint256 defensePowerUsed)
        external
        restricted
    {
        _ensurePlayerExists(player);
        PlayerStatistics storage stats = _playerStats[player];

        stats.totalMercsLostInCombat += mercsLost;
        stats.totalMercsWonInCombat += mercsWon;
        stats.totalDefensePowerUsed += defensePowerUsed;

        emit CombatStatsRecorded(player, mercsLost, mercsWon);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Gets total deposits for a player and token
     */
    function getTotalDeposited(address player, IERC20 token) external view returns (uint256) {
        return _playerStats[player].totalDeposited[token];
    }

    /**
     * @notice Gets total withdrawals for a player and token
     */
    function getTotalWithdrawn(address player, IERC20 token) external view returns (uint256) {
        return _playerStats[player].totalWithdrawn[token];
    }

    /**
     * @notice Gets total burned amount for a player and token
     */
    function getTotalBurned(address player, IERC20 token) external view returns (uint256) {
        return _playerStats[player].totalBurned[token];
    }

    /**
     * @notice Gets deposit count for a player
     */
    function getDepositCount(address player) external view returns (uint256) {
        return _playerStats[player].depositCount;
    }

    /**
     * @notice Gets withdrawal count for a player
     */
    function getWithdrawalCount(address player) external view returns (uint256) {
        return _playerStats[player].withdrawalCount;
    }

    /**
     * @notice Gets mercenaries recruited by level for a player
     */
    function getMercsRecruitedByLevel(address player, uint256 level) external view returns (uint256) {
        return _playerStats[player].mercsRecruitedByLevel[level];
    }

    /**
     * @notice Gets total mercenaries recruited for a player
     */
    function getTotalMercsRecruited(address player) external view returns (uint256) {
        return _playerStats[player].totalMercsRecruited;
    }

    /**
     * @notice Gets recruitment count for a player
     */
    function getRecruitmentCount(address player) external view returns (uint256) {
        return _playerStats[player].recruitmentCount;
    }

    /**
     * @notice Gets seize statistics for a player
     */
    function getSeizeStats(address player) external view returns (uint256 total, uint256 successful, uint256 failed) {
        PlayerStatistics storage stats = _playerStats[player];
        return (stats.totalSeizeAttempts, stats.successfulSeizes, stats.failedSeizes);
    }

    /**
     * @notice Gets mines seized from a specific previous owner
     */
    function getMinesSeizedFrom(address player, address previousOwner) external view returns (uint256) {
        return _playerStats[player].minesSeizedFrom[previousOwner];
    }

    /**
     * @notice Gets mines abandoned by a player
     */
    function getMinesAbandoned(address player) external view returns (uint256) {
        return _playerStats[player].minesAbandoned;
    }

    /**
     * @notice Gets resources claimed by a player for a specific resource
     */
    function getResourcesClaimed(address player, IERC20 resource) external view returns (uint256) {
        return _playerStats[player].resourcesClaimed[resource];
    }

    /**
     * @notice Gets claim count for a player
     */
    function getClaimCount(address player) external view returns (uint256) {
        return _playerStats[player].claimCount;
    }

    /**
     * @notice Gets defense boosts activated by a player
     */
    function getDefenseBoostsActivated(address player) external view returns (uint256) {
        return _playerStats[player].defenseBoostsActivated;
    }

    /**
     * @notice Gets combat power statistics for a player
     */
    function getCombatPowerStats(address player) external view returns (uint256 attackPower, uint256 defensePower) {
        PlayerStatistics storage stats = _playerStats[player];
        return (stats.totalAttackPowerUsed, stats.totalDefensePowerUsed);
    }

    /**
     * @notice Gets combat mercenary statistics for a player
     */
    function getCombatMercStats(address player) external view returns (uint256 lost, uint256 won) {
        PlayerStatistics storage stats = _playerStats[player];
        return (stats.totalMercsLostInCombat, stats.totalMercsWonInCombat);
    }

    /**
     * @notice Gets the total number of players with statistics
     */
    function getPlayerCount() external view returns (uint256) {
        return allPlayers.length;
    }

    /**
     * @notice Gets a range of players from the allPlayers array
     */
    function getPlayers(uint256 startIndex, uint256 count) external view returns (address[] memory) {
        if (startIndex >= allPlayers.length) {
            return new address[](0);
        }

        uint256 endIndex = startIndex + count;
        if (endIndex > allPlayers.length) {
            endIndex = allPlayers.length;
        }

        address[] memory result = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = allPlayers[i];
        }

        return result;
    }

    /**
     * @notice Internal function to ensure a player exists in the tracking system
     */
    function _ensurePlayerExists(address player) internal {
        if (!playerExists[player]) {
            allPlayers.push(player);
            playerExists[player] = true;
        }
    }
}
