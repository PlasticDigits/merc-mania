// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {GameMaster} from "./GameMaster.sol";
import {ResourceManager} from "./ResourceManager.sol";
import {MineFactory} from "./MineFactory.sol";
import {MercAssetFactory} from "./MercAssetFactory.sol";
import {Mine} from "./Mine.sol";
import {IMine} from "./interfaces/IMine.sol";
import {PlayerStats} from "./PlayerStats.sol";
import {GameStats} from "./GameStats.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MercManiaView
 * @notice Aggregated view contract for efficient webapp data fetching
 * @dev This contract provides batch read operations to minimize RPC calls for the webapp.
 *      All methods are view-only and optimized for frontend consumption.
 * @author Merc Mania Development Team
 */
contract MercManiaView {
    /// @notice Reference to the GameMaster contract for balance queries
    GameMaster public immutable GAME_MASTER;

    /// @notice Reference to the ResourceManager for resource enumeration
    ResourceManager public immutable RESOURCE_MANAGER;

    /// @notice Reference to the MineFactory for mine discovery
    MineFactory public immutable MINE_FACTORY;

    /// @notice Reference to the MercAssetFactory for mercenary enumeration
    MercAssetFactory public immutable MERC_FACTORY;

    /// @notice Reference to the PlayerStats contract for individual player analytics
    PlayerStats public immutable PLAYER_STATS;

    /// @notice Reference to the GameStats contract for global game analytics
    GameStats public immutable GAME_STATS;

    /// @notice Complete player data snapshot
    struct PlayerSnapshot {
        address player;
        ResourceBalance[] resourceBalances;
        MercenaryBalance[] mercenaryBalances;
        address[] controlledMines;
        uint256 totalResourceValue; // Sum of all resource balances (in Gold equivalent)
        uint256 totalMercenaryCount; // Total mercenaries across all levels
    }

    /// @notice Player's balance of a specific resource
    struct ResourceBalance {
        IERC20 token;
        uint256 balance;
    }

    /// @notice Player's balance of mercenaries at a specific level
    struct MercenaryBalance {
        uint256 level;
        IERC20 token;
        uint256 balance;
        uint256 powerPerUnit; // Battle power calculation for 1 unit
    }

    /// @notice Complete mine state snapshot
    struct MineSnapshot {
        address mineAddress;
        IERC20 resource;
        address owner;
        uint256 currentProduction;
        uint256 accumulatedResources;
        uint256 lastSeized;
        uint256 createdAt;
        bool defenseBoostActive;
        uint256 defenseBoostExpiry;
        uint256 daysSinceCreation;
        uint256 halvingCount; // How many halvings have occurred
        IERC20 defenderMercToken;
        uint256 defenderMercLevel;
    }

    /// @notice Battle power comparison for UI previews
    struct BattlePowerPreview {
        address mineAddress;
        uint256 attackerPower;
        uint256 defenderPower;
        uint256 attackerMercLevel;
        uint256 defenderMercLevel;
        uint256 attackerMercAmount;
        uint256 defenderMercAmount;
        bool defenseBoostActive;
        uint256 winProbabilityPercent; // 0-100
    }

    /// @notice Game-wide statistics
    struct GameStatsSnapshot {
        uint256 totalMines;
        uint256 totalPlayers; // Unique players with any balance
        uint256 totalResources;
        uint256 totalMercenaryLevels;
        uint256 activeBattles24h; // Battles in last 24 hours
        address goldToken;
        uint256 totalGoldSupply; // Total Gold held in GameMaster
    }

    /// @notice Token metadata helper struct
    struct TokenMetadata {
        string name;
        string symbol;
        string tokenUri;
    }

    /// @notice Mercenary metadata with level information
    struct MercenaryMetadata {
        IERC20 token;
        string name;
        string symbol;
        string tokenUri;
        uint256 level;
    }

    /// @notice Enhanced player statistics aggregation
    struct PlayerStatsSnapshot {
        address player;
        // Token Management Stats
        uint256 depositCount;
        uint256 withdrawalCount;
        // Combat Stats
        uint256 totalSeizeAttempts;
        uint256 successfulSeizes;
        uint256 failedSeizes;
        uint256 winRate; // Calculated percentage
        uint256 totalAttackPowerUsed;
        uint256 totalDefensePowerUsed;
        uint256 totalMercsLost;
        uint256 totalMercsWon;
        // Mine Management Stats
        uint256 minesAbandoned;
        uint256 claimCount;
        uint256 defenseBoostsActivated;
        // Recruitment Stats
        uint256 totalMercsRecruited;
        uint256 recruitmentCount;
    }

    /// @notice Global game analytics aggregation
    struct GlobalStatsSnapshot {
        // Overview metrics
        uint256 totalParticipants;
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        uint256 totalMercsRecruited;
        uint256 totalSeizeAttempts;
        uint256 totalClaims;
        uint256 gameAge; // days since first activity
        // Combat analytics
        uint256 totalSuccessfulSeizes;
        uint256 totalFailedSeizes;
        uint256 totalCombatPowerUsed;
        uint256 totalMercsLost;
        // Activity metrics
        uint256 uniqueDepositors;
        uint256 firstActivityTimestamp;
        uint256 lastActivityTimestamp;
    }

    /**
     * @notice Constructs the MercManiaView with references to core contracts
     * @param _gameMaster The GameMaster contract for balance queries
     * @param _resourceManager The ResourceManager for resource enumeration
     * @param _mineFactory The MineFactory for mine discovery
     * @param _mercFactory The MercAssetFactory for mercenary enumeration
     * @param _playerStats The PlayerStats contract for individual player analytics
     * @param _gameStats The GameStats contract for global game analytics
     */
    constructor(
        GameMaster _gameMaster,
        ResourceManager _resourceManager,
        MineFactory _mineFactory,
        MercAssetFactory _mercFactory,
        PlayerStats _playerStats,
        GameStats _gameStats
    ) {
        GAME_MASTER = _gameMaster;
        RESOURCE_MANAGER = _resourceManager;
        MINE_FACTORY = _mineFactory;
        MERC_FACTORY = _mercFactory;
        PLAYER_STATS = _playerStats;
        GAME_STATS = _gameStats;
    }

    /**
     * @notice Gets complete player data in a single call
     * @dev Fetches all resource balances, mercenary balances, and controlled mines
     * @param player The player address to query
     * @return snapshot Complete player data
     */
    function getPlayerSnapshot(address player) public view returns (PlayerSnapshot memory snapshot) {
        // Get all resource balances
        IERC20[] memory resources = RESOURCE_MANAGER.getAllResources();
        ResourceBalance[] memory resourceBalances = new ResourceBalance[](resources.length);
        uint256 totalResourceValue = 0;

        for (uint256 i = 0; i < resources.length; i++) {
            uint256 balance = GAME_MASTER.getBalance(player, resources[i]);
            resourceBalances[i] = ResourceBalance({token: resources[i], balance: balance});
            totalResourceValue += balance; // Simple sum for now
        }

        // Get all mercenary balances
        uint256 highestLevel = MERC_FACTORY.highestLevel();
        MercenaryBalance[] memory mercBalances = new MercenaryBalance[](highestLevel);
        uint256 totalMercenaryCount = 0;

        for (uint256 level = 1; level <= highestLevel; level++) {
            address mercToken = MERC_FACTORY.getMercByLevel(level);
            if (mercToken != address(0)) {
                uint256 balance = GAME_MASTER.getBalance(player, IERC20(mercToken));
                totalMercenaryCount += balance;

                mercBalances[level - 1] = MercenaryBalance({
                    level: level,
                    token: IERC20(mercToken),
                    balance: balance,
                    powerPerUnit: _calculateMercPowerPerUnit(level)
                });
            }
        }

        // Get controlled mines
        address[] memory controlledMines = _getControlledMines(player);

        return PlayerSnapshot({
            player: player,
            resourceBalances: resourceBalances,
            mercenaryBalances: mercBalances,
            controlledMines: controlledMines,
            totalResourceValue: totalResourceValue,
            totalMercenaryCount: totalMercenaryCount
        });
    }

    /**
     * @notice Gets all mine states in a single call
     * @dev Optimized for displaying mine map with all current information
     * @return snapshots Array of all mine states
     */
    function getAllMineSnapshots() external view returns (MineSnapshot[] memory snapshots) {
        address[] memory mineAddresses = MINE_FACTORY.getAllMines();
        snapshots = new MineSnapshot[](mineAddresses.length);

        for (uint256 i = 0; i < mineAddresses.length; i++) {
            snapshots[i] = _getMineSnapshot(mineAddresses[i]);
        }

        return snapshots;
    }

    /**
     * @notice Gets mine snapshots for a specific resource type
     * @param resource The resource token to filter by
     * @return snapshots Array of mine states producing the specified resource
     */
    function getMineSnapshotsByResource(IERC20 resource) external view returns (MineSnapshot[] memory snapshots) {
        address[] memory mineAddresses = MINE_FACTORY.getMinesForResource(resource);
        snapshots = new MineSnapshot[](mineAddresses.length);

        for (uint256 i = 0; i < mineAddresses.length; i++) {
            snapshots[i] = _getMineSnapshot(mineAddresses[i]);
        }

        return snapshots;
    }

    /**
     * @notice Calculates battle power for multiple scenarios
     * @dev Used for UI battle previews and power comparisons
     * @param mines Array of mine addresses to calculate for
     * @param mercLevels Array of mercenary levels to use
     * @param mercAmounts Array of mercenary amounts to deploy
     * @return previews Array of battle power calculations
     */
    function getBattlePowerPreviews(
        address[] calldata mines,
        uint256[] calldata mercLevels,
        uint256[] calldata mercAmounts
    ) external view returns (BattlePowerPreview[] memory previews) {
        require(mines.length == mercLevels.length && mines.length == mercAmounts.length, "Array length mismatch");

        previews = new BattlePowerPreview[](mines.length);

        for (uint256 i = 0; i < mines.length; i++) {
            previews[i] = _getBattlePowerPreview(mines[i], mercLevels[i], mercAmounts[i]);
        }

        return previews;
    }

    /**
     * @notice Gets game-wide statistics for dashboard display
     * @return stats Current game state statistics
     */
    function getGameStats() external view returns (GameStatsSnapshot memory stats) {
        IERC20 goldToken = RESOURCE_MANAGER.GOLD();

        return GameStatsSnapshot({
            totalMines: MINE_FACTORY.getMineCount(),
            totalPlayers: 0, // Would need to track separately
            totalResources: RESOURCE_MANAGER.getResourceCount(),
            totalMercenaryLevels: MERC_FACTORY.highestLevel(),
            activeBattles24h: 0, // Would need event tracking
            goldToken: address(goldToken),
            totalGoldSupply: goldToken.balanceOf(address(GAME_MASTER))
        });
    }

    /**
     * @notice Gets multiple player snapshots efficiently
     * @param players Array of player addresses to query
     * @return snapshots Array of player data
     */
    function getMultiplePlayerSnapshots(address[] calldata players)
        external
        view
        returns (PlayerSnapshot[] memory snapshots)
    {
        snapshots = new PlayerSnapshot[](players.length);

        for (uint256 i = 0; i < players.length; i++) {
            snapshots[i] = getPlayerSnapshot(players[i]);
        }

        return snapshots;
    }

    /**
     * @notice Gets recent battle history across all mines
     * @param startIndex Starting index for pagination
     * @param count Number of battles to return
     * @return battles Array of recent battle log entries
     */
    function getRecentBattles(uint256 startIndex, uint256 count)
        external
        view
        returns (IMine.BattleLogEntry[] memory battles)
    {
        address[] memory mineAddresses = MINE_FACTORY.getAllMines();

        // This is a simplified implementation - in production you'd want
        // a more sophisticated aggregation system
        uint256 totalBattles = 0;
        for (uint256 i = 0; i < mineAddresses.length; i++) {
            totalBattles += IMine(mineAddresses[i]).getBattleLogCount();
        }

        if (totalBattles == 0 || startIndex >= totalBattles) {
            return new IMine.BattleLogEntry[](0);
        }

        uint256 actualCount = count;
        if (startIndex + count > totalBattles) {
            actualCount = totalBattles - startIndex;
        }

        battles = new IMine.BattleLogEntry[](actualCount);

        // Aggregate battles from all mines (simplified)
        uint256 battleIndex = 0;
        for (uint256 i = 0; i < mineAddresses.length && battleIndex < actualCount; i++) {
            IMine mine = IMine(mineAddresses[i]);
            uint256 mineLogCount = mine.getBattleLogCount();

            for (uint256 j = 0; j < mineLogCount && battleIndex < actualCount; j++) {
                if (battleIndex >= startIndex) {
                    battles[battleIndex - startIndex] = mine.getBattleLogEntry(j);
                }
                battleIndex++;
            }
        }

        return battles;
    }

    /**
     * @notice Gets metadata for all resources
     * @dev Since metadata never changes, this can be cached indefinitely
     * @return metadata Array of resource metadata
     */
    function getAllResourceMetadata() external view returns (TokenMetadata[] memory metadata) {
        IERC20[] memory resources = RESOURCE_MANAGER.getAllResources();
        metadata = new TokenMetadata[](resources.length);

        for (uint256 i = 0; i < resources.length; i++) {
            metadata[i] = _getTokenMetadata(resources[i]);
        }

        return metadata;
    }

    /**
     * @notice Gets metadata for all mercenary tokens
     * @dev Since metadata never changes, this can be cached indefinitely
     * @return metadata Array of mercenary metadata with levels
     */
    function getAllMercenaryMetadata() external view returns (MercenaryMetadata[] memory metadata) {
        address[] memory allMercs = MERC_FACTORY.getAllMercs();
        metadata = new MercenaryMetadata[](allMercs.length);

        for (uint256 i = 0; i < allMercs.length; i++) {
            TokenMetadata memory baseMetadata = _getTokenMetadata(IERC20(allMercs[i]));

            // Get the level for this mercenary
            uint256 level = 0;
            for (uint256 lvl = 1; lvl <= MERC_FACTORY.highestLevel(); lvl++) {
                if (MERC_FACTORY.getMercByLevel(lvl) == allMercs[i]) {
                    level = lvl;
                    break;
                }
            }

            metadata[i] = MercenaryMetadata({
                token: IERC20(allMercs[i]),
                name: baseMetadata.name,
                symbol: baseMetadata.symbol,
                tokenUri: baseMetadata.tokenUri,
                level: level
            });
        }

        return metadata;
    }

    // ==================== INTERNAL HELPER FUNCTIONS ====================

    /**
     * @notice Internal function to get a complete mine snapshot
     */
    function _getMineSnapshot(address mineAddress) internal view returns (MineSnapshot memory) {
        Mine mine = Mine(mineAddress);

        uint256 daysSinceCreation = (block.timestamp - mine.createdAt()) / 1 days;
        uint256 halvingCount = daysSinceCreation / (mine.halvingPeriod() / 1 days);

        // Get defender mercenary information
        IERC20 defenderMercToken = mine.defenderMercToken();
        uint256 defenderMercLevel = 0;

        if (address(defenderMercToken) != address(0)) {
            // Find the level for this mercenary token
            for (uint256 level = 1; level <= MERC_FACTORY.highestLevel(); level++) {
                if (MERC_FACTORY.getMercByLevel(level) == address(defenderMercToken)) {
                    defenderMercLevel = level;
                    break;
                }
            }
        }

        return MineSnapshot({
            mineAddress: mineAddress,
            resource: mine.resource(),
            owner: mine.owner(),
            currentProduction: mine.getCurrentProduction(),
            accumulatedResources: mine.getAccumulatedResources(),
            lastSeized: mine.lastSeized(),
            createdAt: mine.createdAt(),
            defenseBoostActive: mine.defenseBoostExpiry() > block.timestamp,
            defenseBoostExpiry: mine.defenseBoostExpiry(),
            daysSinceCreation: daysSinceCreation,
            halvingCount: halvingCount,
            defenderMercToken: defenderMercToken,
            defenderMercLevel: defenderMercLevel
        });
    }

    /**
     * @notice Internal function to get battle power preview
     */
    function _getBattlePowerPreview(address mineAddress, uint256 mercLevel, uint256 mercAmount)
        internal
        view
        returns (BattlePowerPreview memory)
    {
        Mine mine = Mine(mineAddress);

        uint256 attackerPower = mine.calculateBattlePower(mercLevel, mercAmount, false);
        uint256 defenderPower = 0;
        uint256 defenderMercLevel = 0;
        uint256 defenderMercAmount = 0;

        // Calculate defender power if mine is owned
        if (mine.owner() != address(0)) {
            IERC20 defenderMercToken = mine.defenderMercToken();
            if (address(defenderMercToken) != address(0)) {
                defenderMercAmount = GAME_MASTER.getBalance(mine.owner(), defenderMercToken);
                if (defenderMercAmount > 0) {
                    // Find defender mercenary level
                    for (uint256 level = 1; level <= MERC_FACTORY.highestLevel(); level++) {
                        if (MERC_FACTORY.getMercByLevel(level) == address(defenderMercToken)) {
                            defenderMercLevel = level;
                            break;
                        }
                    }
                    defenderPower = mine.calculateBattlePower(defenderMercLevel, defenderMercAmount, true);
                }
            }
        }

        // Calculate win probability (simplified)
        uint256 winProbabilityPercent = 50; // Default 50-50
        if (attackerPower + defenderPower > 0) {
            winProbabilityPercent = (attackerPower * 100) / (attackerPower + defenderPower);
        }

        return BattlePowerPreview({
            mineAddress: mineAddress,
            attackerPower: attackerPower,
            defenderPower: defenderPower,
            attackerMercLevel: mercLevel,
            defenderMercLevel: defenderMercLevel,
            attackerMercAmount: mercAmount,
            defenderMercAmount: defenderMercAmount,
            defenseBoostActive: mine.defenseBoostExpiry() > block.timestamp,
            winProbabilityPercent: winProbabilityPercent
        });
    }

    /**
     * @notice Internal function to get mines controlled by a player
     */
    function _getControlledMines(address player) internal view returns (address[] memory) {
        address[] memory allMines = MINE_FACTORY.getAllMines();
        address[] memory controlledMines = new address[](allMines.length);
        uint256 controlledCount = 0;

        for (uint256 i = 0; i < allMines.length; i++) {
            if (Mine(allMines[i]).owner() == player) {
                controlledMines[controlledCount] = allMines[i];
                controlledCount++;
            }
        }

        // Resize array to actual count
        address[] memory result = new address[](controlledCount);
        for (uint256 i = 0; i < controlledCount; i++) {
            result[i] = controlledMines[i];
        }

        return result;
    }

    /**
     * @notice Internal function to calculate mercenary power per unit
     */
    function _calculateMercPowerPerUnit(uint256 level) internal pure returns (uint256) {
        // Simplified power calculation - should match the actual Mine contract logic
        return level * level * 100; // Example: Level 1 = 100, Level 2 = 400, etc.
    }

    /**
     * @notice Internal function to get complete token metadata (with fallbacks)
     */
    function _getTokenMetadata(IERC20 token) internal view returns (TokenMetadata memory) {
        TokenMetadata memory metadata;

        // Get name
        metadata.name = _tryGetTokenName(token);
        metadata.symbol = _tryGetTokenSymbol(token);
        metadata.tokenUri = _tryGetTokenUri(token);

        return metadata;
    }

    /**
     * @notice Internal function to safely get token name
     */
    function _tryGetTokenName(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("name()"));

        if (success && data.length >= 32) {
            return abi.decode(data, (string));
        }

        return "Unknown Token";
    }

    /**
     * @notice Internal function to safely get token symbol
     */
    function _tryGetTokenSymbol(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("symbol()"));

        if (success && data.length >= 32) {
            return abi.decode(data, (string));
        }

        return "UNKNOWN";
    }

    /**
     * @notice External function to safely get token URI
     * @dev This needs to be external to use try/catch
     */
    function _tryGetTokenUri(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("tokenUri()"));

        if (success && data.length >= 32) {
            return abi.decode(data, (string));
        }

        return "";
    }

    // ==================== STATISTICS METHODS ====================

    /**
     * @notice Gets comprehensive player statistics in one call
     * @param player The player address to query
     * @return stats Complete player statistics aggregation
     */
    function getPlayerStatsSnapshot(address player) external view returns (PlayerStatsSnapshot memory stats) {
        stats.player = player;

        // Token statistics
        stats.depositCount = PLAYER_STATS.getDepositCount(player);
        stats.withdrawalCount = PLAYER_STATS.getWithdrawalCount(player);

        // Combat statistics
        (uint256 totalSeizes, uint256 successful, uint256 failed) = PLAYER_STATS.getSeizeStats(player);
        stats.totalSeizeAttempts = totalSeizes;
        stats.successfulSeizes = successful;
        stats.failedSeizes = failed;
        stats.winRate = totalSeizes > 0 ? (successful * 100) / totalSeizes : 0;

        (uint256 attackPower, uint256 defensePower) = PLAYER_STATS.getCombatPowerStats(player);
        stats.totalAttackPowerUsed = attackPower;
        stats.totalDefensePowerUsed = defensePower;

        (uint256 mercsLost, uint256 mercsWon) = PLAYER_STATS.getCombatMercStats(player);
        stats.totalMercsLost = mercsLost;
        stats.totalMercsWon = mercsWon;

        // Mine management statistics
        stats.minesAbandoned = PLAYER_STATS.getMinesAbandoned(player);
        stats.claimCount = PLAYER_STATS.getClaimCount(player);
        stats.defenseBoostsActivated = PLAYER_STATS.getDefenseBoostsActivated(player);

        // Recruitment statistics
        stats.totalMercsRecruited = PLAYER_STATS.getTotalMercsRecruited(player);
        stats.recruitmentCount = PLAYER_STATS.getRecruitmentCount(player);

        return stats;
    }

    /**
     * @notice Gets global game statistics aggregation
     * @return stats Complete global statistics
     */
    function getGlobalStatsSnapshot() external view returns (GlobalStatsSnapshot memory stats) {
        // Get overview from GameStats
        (
            uint256 totalParticipants,
            uint256 totalDeposits,
            uint256 totalWithdrawals,
            uint256 totalMercs,
            uint256 totalSeizes,
            uint256 totalClaims,
            uint256 firstActivity,
            uint256 lastActivity
        ) = GAME_STATS.getGameOverview();

        stats.totalParticipants = totalParticipants;
        stats.totalDeposits = totalDeposits;
        stats.totalWithdrawals = totalWithdrawals;
        stats.totalMercsRecruited = totalMercs;
        stats.totalSeizeAttempts = totalSeizes;
        stats.totalClaims = totalClaims;
        stats.firstActivityTimestamp = firstActivity;
        stats.lastActivityTimestamp = lastActivity;

        // Calculate game age in days
        stats.gameAge = lastActivity > firstActivity ? (lastActivity - firstActivity) / 86400 : 0;

        // Get detailed statistics
        stats.uniqueDepositors = GAME_STATS.getUniqueDepositors();

        // Combat analytics
        (uint256 successful, uint256 failed) = GAME_STATS.getGlobalSeizeStats();
        stats.totalSuccessfulSeizes = successful;
        stats.totalFailedSeizes = failed;
        stats.totalCombatPowerUsed = GAME_STATS.getTotalCombatPowerUsed();
        stats.totalMercsLost = GAME_STATS.getTotalMercsLostInCombat();

        return stats;
    }
}
