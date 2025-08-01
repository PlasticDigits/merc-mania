// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IMine} from "./interfaces/IMine.sol";
import {IResourceManager} from "./interfaces/IResourceManager.sol";
import {GameMaster} from "./GameMaster.sol";
import {MercAssetFactory} from "./MercAssetFactory.sol";
import {ERC20MercAsset} from "./ERC20MercAsset.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20MintableBurnable} from "./interfaces/IERC20MintableBurnable.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Mine
 * @notice A capturable resource-producing facility that can be seized and defended using mercenaries
 * @dev This contract represents a mine that produces a specific resource over time with diminishing returns.
 *      Mines can be seized through combat using mercenaries, and owners can claim accumulated resources.
 *      The production rate halves every 3 days to prevent infinite resource generation.
 *      Uses proxy pattern with initialization for efficient deployment via factory contracts.
 * @author Merc Mania Development Team
 */
contract Mine is IMine, AccessManaged, Initializable, Ownable {
    /// @notice Reference to the resource manager for accessing Gold token
    /// @dev Used for defense boost mechanics that require Gold payments
    IResourceManager public RESOURCE_MANAGER;

    /// @notice Reference to the game master for balance management during combat
    /// @dev Used to transfer mercenaries and manage token balances during battles
    GameMaster public GAME_MASTER;

    /// @notice Reference to the mercenary factory for validating mercenary tokens
    /// @dev Used to verify mercenary tokens used in combat are legitimate
    MercAssetFactory public MERC_FACTORY;

    /// @notice The type of resource this mine produces
    /// @dev Set during initialization and cannot be changed
    IERC20 public resource;

    /// @notice The type of mercenary token used by the current defender
    /// @dev Updated when the mine is seized, determines combat power calculation
    IERC20 public defenderMercToken;

    /// @notice Timestamp when the mine was last seized
    /// @dev Used for abandonment cooldown calculations
    uint256 public lastSeized;

    /// @notice Timestamp when the mine was created
    /// @dev Used for production calculations and halving mechanics
    uint256 public createdAt;

    /// @notice Timestamp when the current defense boost expires
    /// @dev Defense boost doubles defensive power when active
    uint256 public defenseBoostExpiry;

    /// @notice Timestamp of the last resource claim
    /// @dev Used to calculate accumulated resources since last claim
    uint256 public lastResourceClaim;

    /// @notice Period after which production rate halves (in seconds)
    /// @dev Prevents infinite resource accumulation by implementing diminishing returns
    uint256 public halvingPeriod;

    /// @notice Initial production rate per day, in wei
    /// @dev Starting production rate that decreases over time
    uint256 public initialProductionPerDay;

    /// @notice Minimum number of mercenaries required to attempt a seizure
    /// @dev Prevents spam attacks with tiny mercenary amounts
    uint256 private constant MIN_MERCS_TO_SEIZE = 25 ether;

    /// @notice Cooldown period before a mine can be abandoned (1 day)
    /// @dev Prevents immediate abandonment after seizure to encourage strategic play
    uint256 private constant ABANDON_COOLDOWN = 1 days;

    /// @notice Duration of defense boost effect (8 hours)
    /// @dev Time period during which defensive power is doubled
    uint256 private constant DEFENSE_BOOST_DURATION = 8 hours;

    /// @notice Percentage of mercenaries lost when abandoning a mine (10%)
    /// @dev Penalty for abandoning to prevent risk-free mining
    uint256 private constant ABANDON_LOSS_PERCENTAGE = 10;

    /// @notice Array to store all battle log entries for historical tracking
    /// @dev Allows enumeration of all mine seizure events without requiring indexing
    BattleLogEntry[] public battleLog;

    error InsufficientGold();
    error InsufficientMercs();
    error InsufficientBalance();
    error BelowMinMercs();
    error MustWaitAfterSeizing();
    error MustBePositive();
    error AlreadyOwned();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() AccessManaged(address(0)) Ownable(0x000000000000000000000000000000000000dEaD) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the mine with the provided parameters
     * @dev This function replaces the constructor for proxy-based deployment
     *      Can only be called once due to the initializer modifier
     * @param _authority The access manager contract that controls permissions
     * @param _resourceManager The resource manager for Gold access
     * @param _gameMaster The game master for balance management
     * @param _mercFactory The mercenary factory for token validation
     * @param _resource The resource token this mine will produce
     * @param _initialProductionPerDay The initial production rate per day
     */
    function initialize(
        address _authority,
        IResourceManager _resourceManager,
        GameMaster _gameMaster,
        MercAssetFactory _mercFactory,
        IERC20 _resource,
        uint256 _initialProductionPerDay,
        uint256 _halvingPeriod
    ) external initializer {
        // Initialize AccessManaged with the authority
        _setAuthority(_authority);

        RESOURCE_MANAGER = _resourceManager;
        GAME_MASTER = _gameMaster;
        MERC_FACTORY = _mercFactory;
        resource = _resource;
        createdAt = block.timestamp;
        lastResourceClaim = block.timestamp;
        initialProductionPerDay = _initialProductionPerDay;
        halvingPeriod = _halvingPeriod;
    }

    /**
     * @notice Attempts to seize control of the mine using mercenaries
     * @dev If the mine is unowned, takes control immediately. If owned, initiates combat.
     *      Automatically uses the caller's full balance of the specified mercenary level.
     *      Requires at least 25 mercenaries and sufficient balance in GameMaster.
     * @param mercLevel The level of mercenary to use for the attack
     */
    function seize(uint256 mercLevel) external {
        address mercTokenAddress = MERC_FACTORY.getMercByLevel(mercLevel);
        require(mercTokenAddress != address(0), InsufficientMercs());

        IERC20 mercToken = IERC20(mercTokenAddress);
        uint256 mercAmount = GAME_MASTER.getBalance(msg.sender, mercToken);

        require(mercAmount >= MIN_MERCS_TO_SEIZE, BelowMinMercs());

        if (owner() == address(0)) {
            _seizeUnownedMine(mercToken, mercAmount);
        } else {
            _seizeBattle(mercToken, mercAmount);
        }
    }

    /**
     * @notice Internal function to handle seizure of an unowned mine
     * @dev Transfers mercenaries to the mine and sets the caller as owner
     * @param mercToken The mercenary token contract being used
     * @param mercAmount The number of mercenaries being stationed
     */
    function _seizeUnownedMine(IERC20 mercToken, uint256 mercAmount) private {
        // Transfer mercs from user to mine via GameMaster
        GAME_MASTER.transferBalance(msg.sender, address(this), mercToken, mercAmount);

        // Record battle log entry for unowned mine seizure
        battleLog.push(
            BattleLogEntry({
                timestamp: block.timestamp,
                attacker: msg.sender,
                previousOwner: address(0),
                attackerMercToken: mercToken,
                attackerMercAmount: mercAmount,
                defenderMercToken: IERC20(address(0)),
                defenderMercAmount: 0,
                attackerLosses: 0,
                defenderLosses: 0,
                attackerWon: true
            })
        );

        _transferOwnership(msg.sender);
        defenderMercToken = mercToken;
        lastSeized = block.timestamp;
        emit MineSeized(msg.sender, 0, 0);
    }

    /**
     * @notice Internal function to handle combat when seizing an owned mine
     * @dev Calculates battle power for both sides and determines the outcome
     * @param mercToken The attacker's mercenary token contract
     * @param mercAmount The number of attacking mercenaries
     */
    function _seizeBattle(IERC20 mercToken, uint256 mercAmount) private {
        require(msg.sender != owner(), AlreadyOwned());

        uint256 attackerLevel = ERC20MercAsset(address(mercToken)).getLevel();
        uint256 attackerPower = this.calculateBattlePower(attackerLevel, mercAmount, false);

        // Get defender's merc data
        (IERC20 currentDefenderToken, uint256 currentDefenderCount) = getDefenderMercs();
        require(currentDefenderCount > 0, InsufficientMercs());

        uint256 defenderLevel = ERC20MercAsset(address(currentDefenderToken)).getLevel();
        uint256 defenderPower = this.calculateBattlePower(defenderLevel, currentDefenderCount, true);

        if (attackerPower > defenderPower) {
            _handleAttackerVictory(
                mercToken, mercAmount, currentDefenderToken, currentDefenderCount, attackerPower, defenderPower
            );
        } else {
            _handleDefenderVictory(
                mercToken, mercAmount, currentDefenderToken, currentDefenderCount, attackerPower, defenderPower
            );
        }
    }

    /**
     * @notice Internal function to get the current defender's mercenary data
     * @dev Returns the token type and count of mercenaries defending the mine
     * @return The defender's mercenary token contract and the number of defending mercenaries
     */
    function getDefenderMercs() public view returns (IERC20, uint256) {
        if (address(defenderMercToken) == address(0)) {
            return (IERC20(address(0)), 0);
        }

        uint256 defenderMercCount = GAME_MASTER.getBalance(address(this), defenderMercToken);
        return (defenderMercToken, defenderMercCount);
    }

    /**
     * @notice Internal function to handle the outcome when the attacker wins
     * @dev Burns defender mercenaries, calculates attacker losses, transfers ownership
     * @param mercToken The attacker's mercenary token contract
     * @param mercAmount The number of attacking mercenaries
     * @param currentDefenderToken The defender's mercenary token contract
     * @param currentDefenderCount The number of defending mercenaries
     * @param attackerPower The calculated attacker power
     * @param defenderPower The calculated defender power
     */
    function _handleAttackerVictory(
        IERC20 mercToken,
        uint256 mercAmount,
        IERC20 currentDefenderToken,
        uint256 currentDefenderCount,
        uint256 attackerPower,
        uint256 defenderPower
    ) private {
        uint256 attackerLosses = (defenderPower * mercAmount) / attackerPower;
        uint256 defenderLosses = currentDefenderCount;

        // Record battle log entry for attacker victory
        battleLog.push(
            BattleLogEntry({
                timestamp: block.timestamp,
                attacker: msg.sender,
                previousOwner: owner(),
                attackerMercToken: mercToken,
                attackerMercAmount: mercAmount,
                defenderMercToken: currentDefenderToken,
                defenderMercAmount: currentDefenderCount,
                attackerLosses: attackerLosses,
                defenderLosses: defenderLosses,
                attackerWon: true
            })
        );

        // Burn attacker losses from attacker's GameMaster balance
        if (attackerLosses > 0) {
            GAME_MASTER.spendBalance(msg.sender, mercToken, attackerLosses);
        }

        // Burn all defender mercs from Mine's GameMaster balance
        if (currentDefenderCount > 0) {
            GAME_MASTER.spendBalance(address(this), currentDefenderToken, currentDefenderCount);
        }

        // Transfer remaining attacker mercs from user to Mine via GameMaster
        uint256 remainingMercs = mercAmount - attackerLosses;
        if (remainingMercs > 0) {
            GAME_MASTER.transferBalance(msg.sender, address(this), mercToken, remainingMercs);
        }

        _transferOwnership(msg.sender);
        defenderMercToken = mercToken; // Update defender merc type
        lastSeized = block.timestamp;
        defenseBoostExpiry = 0;

        emit MineSeized(msg.sender, attackerLosses, defenderLosses);
    }

    /**
     * @notice Internal function to handle the outcome when the defender wins
     * @dev Burns all attacking mercenaries, calculates defender losses
     * @param mercToken The attacker's mercenary token contract
     * @param mercAmount The number of attacking mercenaries
     * @param currentDefenderToken The defender's mercenary token contract
     * @param currentDefenderCount The number of defending mercenaries
     * @param attackerPower The calculated attacker power
     * @param defenderPower The calculated defender power
     */
    function _handleDefenderVictory(
        IERC20 mercToken,
        uint256 mercAmount,
        IERC20 currentDefenderToken,
        uint256 currentDefenderCount,
        uint256 attackerPower,
        uint256 defenderPower
    ) private {
        uint256 defenderLosses = (attackerPower * currentDefenderCount) / defenderPower;
        uint256 attackerLosses = mercAmount;

        // Record battle log entry for defender victory
        battleLog.push(
            BattleLogEntry({
                timestamp: block.timestamp,
                attacker: msg.sender,
                previousOwner: owner(),
                attackerMercToken: mercToken,
                attackerMercAmount: mercAmount,
                defenderMercToken: currentDefenderToken,
                defenderMercAmount: currentDefenderCount,
                attackerLosses: attackerLosses,
                defenderLosses: defenderLosses,
                attackerWon: false
            })
        );

        // Burn all attacker mercs from attacker's GameMaster balance
        GAME_MASTER.spendBalance(msg.sender, mercToken, mercAmount);

        // Burn defender losses from Mine's GameMaster balance
        if (defenderLosses > 0) {
            GAME_MASTER.spendBalance(address(this), currentDefenderToken, defenderLosses);
        }

        emit MineSeized(owner(), attackerLosses, defenderLosses);
    }

    /**
     * @notice Allows the owner to abandon the mine, returning most mercenaries
     * @dev Imposes a 10% penalty on mercenaries and requires 1-day cooldown after seizure
     *      Prevents risk-free mining by ensuring some cost to abandonment
     */
    function abandon() external onlyOwner {
        require(block.timestamp >= lastSeized + ABANDON_COOLDOWN, MustWaitAfterSeizing());

        // Get defender merc balance from Mine's GameMaster balance
        (IERC20 currentDefenderToken, uint256 currentDefenderCount) = getDefenderMercs();

        if (currentDefenderCount > 0) {
            uint256 mercsLost = (currentDefenderCount * ABANDON_LOSS_PERCENTAGE) / 100;

            // Burn 10% of mercs from Mine's GameMaster balance
            if (mercsLost > 0) {
                GAME_MASTER.spendBalance(address(this), currentDefenderToken, mercsLost);
            }

            // Transfer remaining mercs back to user via GameMaster
            uint256 remainingMercs = currentDefenderCount - mercsLost;
            if (remainingMercs > 0) {
                GAME_MASTER.transferBalance(address(this), msg.sender, currentDefenderToken, remainingMercs);
            }

            emit MineAbandoned(msg.sender, mercsLost);
        }

        _transferOwnership(address(0));
        defenderMercToken = IERC20(address(0));
        defenseBoostExpiry = 0;
    }

    /**
     * @notice Allows the owner to claim accumulated resources from the mine
     * @dev Uses GameMaster to mint new resource tokens and credit the owner's balance
     *      Resets the last claim timestamp to prevent double-claiming
     */
    function claimResources() external onlyOwner {
        uint256 accumulatedResources = getAccumulatedResources();
        require(accumulatedResources > 0, InsufficientBalance());

        lastResourceClaim = block.timestamp;

        // Use GameMaster to mint tokens and add to user's balance
        GAME_MASTER.addBalance(msg.sender, resource, accumulatedResources);

        emit ResourcesClaimed(msg.sender, accumulatedResources);
    }

    /**
     * @notice Activates a temporary defense boost by spending Gold
     * @dev Doubles defensive power for 8 hours, costs 1 Gold per 10 mercenaries
     *      Only the owner can activate and only using their defender mercenary type
     */
    function activateDefenseBoost() external onlyOwner {
        uint256 goldCost = (GAME_MASTER.getBalance(address(this), defenderMercToken)) / 10; // 1 gold per 10 mercs
        IERC20 gold = RESOURCE_MANAGER.GOLD();
        require(GAME_MASTER.getBalance(msg.sender, gold) >= goldCost, InsufficientGold());

        // Spend gold
        GAME_MASTER.spendBalance(msg.sender, gold, goldCost);

        // Activate defense boost
        defenseBoostExpiry = block.timestamp + DEFENSE_BOOST_DURATION;

        emit DefenseBoostActivated(msg.sender, goldCost, defenseBoostExpiry);
    }

    /**
     * @notice Returns comprehensive information about the mine's current state
     * @dev Provides all key data about the mine in a single call for efficiency
     * @return A MineInfo struct containing resource, owner, timestamps, and boost status
     */
    function getMineInfo() external view returns (MineInfo memory) {
        return MineInfo({
            resource: resource,
            owner: owner(),
            lastSeized: lastSeized,
            createdAt: createdAt,
            defenseBoostExpiry: defenseBoostExpiry
        });
    }

    /**
     * @notice Calculates the current production rate per second
     * @dev Production halves every 3 days, capped at 64 halving periods to prevent underflow
     * @return The current production rate in tokens per second
     */
    function getCurrentProduction() external view returns (uint256) {
        uint256 timeElapsed = block.timestamp - createdAt;
        uint256 halvingPeriods = timeElapsed / halvingPeriod;

        // Production halves every period: production = initial / (2^periods)
        // To avoid underflow, we cap at 64 periods
        if (halvingPeriods >= 64) {
            return 0;
        }

        uint256 currentDailyProduction = initialProductionPerDay >> halvingPeriods;
        return currentDailyProduction / 1 days; // Per second production
    }

    /**
     * @notice Calculates the total resources that can be claimed since the last claim
     * @dev Returns 0 if the mine is unowned, otherwise calculates based on time elapsed and current production
     * @return The amount of resources available for claiming
     */
    function getAccumulatedResources() public view returns (uint256) {
        if (owner() == address(0)) return 0;

        uint256 timeElapsed = block.timestamp - lastResourceClaim;
        uint256 currentProduction = this.getCurrentProduction();

        return currentProduction * timeElapsed;
    }

    /**
     * @notice Calculates the battle power for a given mercenary force
     * @dev Power is based on mercenary level and quantity, with potential defense boost
     *      Defense boost doubles power when active and the calculation is for defending
     * @param mercLevel The level of the mercenaries
     * @param mercAmount The number of mercenaries
     * @param isDefending Whether this calculation is for the defending force
     * @return The total battle power of the mercenary force
     */
    function calculateBattlePower(uint256 mercLevel, uint256 mercAmount, bool isDefending)
        external
        view
        returns (uint256)
    {
        require(mercAmount > 0, MustBePositive());

        uint256 power = mercAmount * mercLevel;

        // Apply defense boost if active and defending
        if (isDefending && block.timestamp <= defenseBoostExpiry) {
            power *= 2;
        }

        return power;
    }

    /**
     * @notice Returns the total number of battle log entries
     * @dev Allows clients to enumerate through all historical seizure events
     * @return The count of battle log entries stored in the contract
     */
    function getBattleLogCount() external view returns (uint256) {
        return battleLog.length;
    }

    /**
     * @notice Returns a specific battle log entry by index
     * @dev Used to retrieve historical battle information for display purposes
     * @param index The index of the battle log entry to retrieve
     * @return The BattleLogEntry struct containing all battle details
     */
    function getBattleLogEntry(uint256 index) external view returns (BattleLogEntry memory) {
        require(index < battleLog.length, "Index out of bounds");
        return battleLog[index];
    }

    /**
     * @notice Returns an array of battle log entries in reverse chronological order
     * @dev Gets entries from index i to count n, where index 0 is the most recent entry
     *      Handles overflow gracefully by returning only available entries
     * @param startIndex The starting index from the end (0 = most recent)
     * @param count The number of entries to return
     * @return An array of BattleLogEntry structs in reverse chronological order
     */
    function getBattleLogEntries(uint256 startIndex, uint256 count) external view returns (BattleLogEntry[] memory) {
        uint256 totalEntries = battleLog.length;

        // If no entries or startIndex is beyond available entries, return empty array
        if (totalEntries == 0 || startIndex >= totalEntries) {
            return new BattleLogEntry[](0);
        }

        // Calculate the actual array index (reverse order)
        uint256 arrayStartIndex = totalEntries - 1 - startIndex;

        // Calculate how many entries we can actually return
        uint256 availableEntries = arrayStartIndex + 1; // +1 because index is inclusive
        uint256 actualCount = count > availableEntries ? availableEntries : count;

        // Create result array
        BattleLogEntry[] memory result = new BattleLogEntry[](actualCount);

        // Fill the result array going backwards through the battleLog
        for (uint256 i = 0; i < actualCount; i++) {
            result[i] = battleLog[arrayStartIndex - i];
        }

        return result;
    }
}
