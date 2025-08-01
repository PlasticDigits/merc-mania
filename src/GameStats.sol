// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

/**
 * @title GameStats
 * @notice Contract for tracking overall game statistics and aggregated data
 * @dev This contract maintains comprehensive statistics for the entire game
 *      including total token flows, mercenary recruitment, mine operations, and combat across all players
 * @author Merc Mania Development Team
 */
contract GameStats is AccessManaged {
    /// @notice Struct containing all game-wide statistics
    struct GlobalStatistics {
        // Token Management Stats
        mapping(IERC20 => uint256) totalDeposited;
        mapping(IERC20 => uint256) totalWithdrawn;
        mapping(IERC20 => uint256) totalBurned;
        uint256 totalDepositTransactions;
        uint256 totalWithdrawalTransactions;
        uint256 uniqueDepositors;
        // Mercenary Recruitment Stats
        mapping(uint256 => uint256) totalMercsRecruitedByLevel;
        uint256 totalMercsRecruited;
        uint256 totalRecruitmentTransactions;
        uint256 uniqueRecruiters;
        // Mine Combat Stats
        uint256 totalSeizeAttempts;
        uint256 totalSuccessfulSeizes;
        uint256 totalFailedSeizes;
        uint256 totalCombatPowerUsed;
        uint256 totalMercsLostInCombat;
        // Mine Management Stats
        uint256 totalMinesAbandoned;
        mapping(IERC20 => uint256) totalResourcesClaimed;
        uint256 totalClaimTransactions;
        uint256 totalDefenseBoostsActivated;
        // Activity Metrics
        uint256 totalUniqueParticipants;
        mapping(address => bool) hasParticipated;
        uint256 firstActivityTimestamp;
        uint256 lastActivityTimestamp;
    }

    /// @notice The global game statistics
    GlobalStatistics private _gameStats;

    /// @notice Track first-time depositors
    mapping(address => bool) private _hasDeposited;

    /// @notice Track first-time recruiters
    mapping(address => bool) private _hasRecruited;

    /// @notice Events for stat updates
    event GlobalDepositRecorded(IERC20 indexed token, uint256 amount, uint256 totalTransactions);
    event GlobalWithdrawalRecorded(IERC20 indexed token, uint256 amount, uint256 burned, uint256 totalTransactions);
    event GlobalRecruitmentRecorded(uint256 level, uint256 amount, uint256 totalTransactions);
    event GlobalSeizeRecorded(bool success, uint256 totalAttempts);
    event GlobalAbandonRecorded(uint256 totalAbandoned);
    event GlobalClaimRecorded(IERC20 indexed resource, uint256 amount, uint256 totalTransactions);
    event GlobalDefenseBoostRecorded(uint256 totalActivated);
    event NewParticipantRecorded(address indexed participant, uint256 totalParticipants);

    /**
     * @notice Constructs the GameStats contract
     * @param _authority The access manager contract that controls permissions
     */
    constructor(address _authority) AccessManaged(_authority) {
        _gameStats.firstActivityTimestamp = block.timestamp;
    }

    /**
     * @notice Records a global deposit action
     * @dev Only callable by authorized contracts (GameMaster)
     * @param player The player making the deposit
     * @param token The token being deposited
     * @param amount The amount being deposited
     */
    function recordGlobalDeposit(address player, IERC20 token, uint256 amount) external restricted {
        _ensureParticipantTracked(player);

        _gameStats.totalDeposited[token] += amount;
        _gameStats.totalDepositTransactions += 1;

        // Track unique depositors
        if (!_hasDeposited[player]) {
            _hasDeposited[player] = true;
            _gameStats.uniqueDepositors += 1;
        }

        _updateActivityTimestamp();

        emit GlobalDepositRecorded(token, amount, _gameStats.totalDepositTransactions);
    }

    /**
     * @notice Records a global withdrawal action
     * @dev Only callable by authorized contracts (GameMaster)
     * @param player The player making the withdrawal
     * @param token The token being withdrawn
     * @param amount The total amount requested for withdrawal
     * @param burned The amount that was burned due to withdrawal penalty
     */
    function recordGlobalWithdrawal(address player, IERC20 token, uint256 amount, uint256 burned) external restricted {
        _ensureParticipantTracked(player);

        _gameStats.totalWithdrawn[token] += (amount - burned);
        _gameStats.totalBurned[token] += burned;
        _gameStats.totalWithdrawalTransactions += 1;

        _updateActivityTimestamp();

        emit GlobalWithdrawalRecorded(token, amount - burned, burned, _gameStats.totalWithdrawalTransactions);
    }

    /**
     * @notice Records a global mercenary recruitment action
     * @dev Only callable by authorized contracts (MercRecruiter)
     * @param player The player recruiting mercenaries
     * @param level The level of mercenaries recruited
     * @param amount The number of mercenaries recruited
     */
    function recordGlobalRecruitment(address player, uint256 level, uint256 amount) external restricted {
        _ensureParticipantTracked(player);

        _gameStats.totalMercsRecruitedByLevel[level] += amount;
        _gameStats.totalMercsRecruited += amount;
        _gameStats.totalRecruitmentTransactions += 1;

        // Track unique recruiters
        if (!_hasRecruited[player]) {
            _hasRecruited[player] = true;
            _gameStats.uniqueRecruiters += 1;
        }

        _updateActivityTimestamp();

        emit GlobalRecruitmentRecorded(level, amount, _gameStats.totalRecruitmentTransactions);
    }

    /**
     * @notice Records a global mine seizure attempt
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player attempting to seize
     * @param success Whether the seizure was successful
     * @param attackPower The total attack power used
     * @param mercsLost The number of mercenaries lost in combat
     */
    function recordGlobalSeize(address player, bool success, uint256 attackPower, uint256 mercsLost)
        external
        restricted
    {
        _ensureParticipantTracked(player);

        _gameStats.totalSeizeAttempts += 1;
        _gameStats.totalCombatPowerUsed += attackPower;
        _gameStats.totalMercsLostInCombat += mercsLost;

        if (success) {
            _gameStats.totalSuccessfulSeizes += 1;
        } else {
            _gameStats.totalFailedSeizes += 1;
        }

        _updateActivityTimestamp();

        emit GlobalSeizeRecorded(success, _gameStats.totalSeizeAttempts);
    }

    /**
     * @notice Records a global mine abandonment
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player abandoning the mine
     */
    function recordGlobalAbandon(address player) external restricted {
        _ensureParticipantTracked(player);

        _gameStats.totalMinesAbandoned += 1;

        _updateActivityTimestamp();

        emit GlobalAbandonRecorded(_gameStats.totalMinesAbandoned);
    }

    /**
     * @notice Records a global resource claim action
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player claiming resources
     * @param resource The resource being claimed
     * @param amount The amount of resources claimed
     */
    function recordGlobalClaim(address player, IERC20 resource, uint256 amount) external restricted {
        _ensureParticipantTracked(player);

        _gameStats.totalResourcesClaimed[resource] += amount;
        _gameStats.totalClaimTransactions += 1;

        _updateActivityTimestamp();

        emit GlobalClaimRecorded(resource, amount, _gameStats.totalClaimTransactions);
    }

    /**
     * @notice Records a global defense boost activation
     * @dev Only callable by authorized contracts (Mine contracts)
     * @param player The player activating the defense boost
     */
    function recordGlobalDefenseBoost(address player) external restricted {
        _ensureParticipantTracked(player);

        _gameStats.totalDefenseBoostsActivated += 1;

        _updateActivityTimestamp();

        emit GlobalDefenseBoostRecorded(_gameStats.totalDefenseBoostsActivated);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Gets total deposits for a token across all players
     */
    function getTotalDeposited(IERC20 token) external view returns (uint256) {
        return _gameStats.totalDeposited[token];
    }

    /**
     * @notice Gets total withdrawals for a token across all players
     */
    function getTotalWithdrawn(IERC20 token) external view returns (uint256) {
        return _gameStats.totalWithdrawn[token];
    }

    /**
     * @notice Gets total burned amount for a token across all players
     */
    function getTotalBurned(IERC20 token) external view returns (uint256) {
        return _gameStats.totalBurned[token];
    }

    /**
     * @notice Gets total deposit transactions
     */
    function getTotalDepositTransactions() external view returns (uint256) {
        return _gameStats.totalDepositTransactions;
    }

    /**
     * @notice Gets total withdrawal transactions
     */
    function getTotalWithdrawalTransactions() external view returns (uint256) {
        return _gameStats.totalWithdrawalTransactions;
    }

    /**
     * @notice Gets number of unique depositors
     */
    function getUniqueDepositors() external view returns (uint256) {
        return _gameStats.uniqueDepositors;
    }

    /**
     * @notice Gets total mercenaries recruited by level across all players
     */
    function getTotalMercsRecruitedByLevel(uint256 level) external view returns (uint256) {
        return _gameStats.totalMercsRecruitedByLevel[level];
    }

    /**
     * @notice Gets total mercenaries recruited across all players
     */
    function getTotalMercsRecruited() external view returns (uint256) {
        return _gameStats.totalMercsRecruited;
    }

    /**
     * @notice Gets total recruitment transactions
     */
    function getTotalRecruitmentTransactions() external view returns (uint256) {
        return _gameStats.totalRecruitmentTransactions;
    }

    /**
     * @notice Gets number of unique recruiters
     */
    function getUniqueRecruiters() external view returns (uint256) {
        return _gameStats.uniqueRecruiters;
    }

    /**
     * @notice Gets seizure statistics across all players
     */
    function getGlobalSeizeStats() external view returns (uint256 successful, uint256 failed) {
        return (_gameStats.totalSuccessfulSeizes, _gameStats.totalFailedSeizes);
    }

    /**
     * @notice Gets total combat power used across all players
     */
    function getTotalCombatPowerUsed() external view returns (uint256) {
        return _gameStats.totalCombatPowerUsed;
    }

    /**
     * @notice Gets total mercenaries lost in combat across all players
     */
    function getTotalMercsLostInCombat() external view returns (uint256) {
        return _gameStats.totalMercsLostInCombat;
    }

    /**
     * @notice Gets total mines abandoned across all players
     */
    function getTotalMinesAbandoned() external view returns (uint256) {
        return _gameStats.totalMinesAbandoned;
    }

    /**
     * @notice Gets total resources claimed for a specific resource across all players
     */
    function getTotalResourcesClaimed(IERC20 resource) external view returns (uint256) {
        return _gameStats.totalResourcesClaimed[resource];
    }

    /**
     * @notice Gets total claim transactions
     */
    function getTotalClaimTransactions() external view returns (uint256) {
        return _gameStats.totalClaimTransactions;
    }

    /**
     * @notice Gets total defense boosts activated across all players
     */
    function getTotalDefenseBoostsActivated() external view returns (uint256) {
        return _gameStats.totalDefenseBoostsActivated;
    }

    /**
     * @notice Gets the total number of unique participants
     */
    function getTotalUniqueParticipants() external view returns (uint256) {
        return _gameStats.totalUniqueParticipants;
    }

    /**
     * @notice Gets the activity timeline
     */
    function getActivityTimeline() external view returns (uint256 firstActivity, uint256 lastActivity) {
        return (_gameStats.firstActivityTimestamp, _gameStats.lastActivityTimestamp);
    }

    /**
     * @notice Checks if an address has participated in the game
     */
    function hasParticipated(address participant) external view returns (bool) {
        return _gameStats.hasParticipated[participant];
    }

    /**
     * @notice Gets comprehensive game statistics in a single call
     */
    function getGameOverview()
        external
        view
        returns (
            uint256 totalParticipants,
            uint256 totalDeposits,
            uint256 totalWithdrawals,
            uint256 totalMercs,
            uint256 totalSeizes,
            uint256 totalClaims,
            uint256 firstActivity,
            uint256 lastActivity
        )
    {
        return (
            _gameStats.totalUniqueParticipants,
            _gameStats.totalDepositTransactions,
            _gameStats.totalWithdrawalTransactions,
            _gameStats.totalMercsRecruited,
            _gameStats.totalSeizeAttempts,
            _gameStats.totalClaimTransactions,
            _gameStats.firstActivityTimestamp,
            _gameStats.lastActivityTimestamp
        );
    }

    /**
     * @notice Internal function to ensure a participant is tracked
     */
    function _ensureParticipantTracked(address participant) internal {
        if (!_gameStats.hasParticipated[participant]) {
            _gameStats.hasParticipated[participant] = true;
            _gameStats.totalUniqueParticipants += 1;
            emit NewParticipantRecorded(participant, _gameStats.totalUniqueParticipants);
        }
    }

    /**
     * @notice Internal function to update last activity timestamp
     */
    function _updateActivityTimestamp() internal {
        _gameStats.lastActivityTimestamp = block.timestamp;
    }
}
