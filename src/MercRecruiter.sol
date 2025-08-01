// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IMercRecruiter} from "./interfaces/IMercRecruiter.sol";
import {IResourceManager} from "./interfaces/IResourceManager.sol";
import {GameMaster} from "./GameMaster.sol";
import {MercAssetFactory} from "./MercAssetFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20MintableBurnable} from "./interfaces/IERC20MintableBurnable.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {PlayerStats} from "./PlayerStats.sol";
import {GameStats} from "./GameStats.sol";

/**
 * @title MercRecruiter
 * @notice Contract for recruiting mercenaries using game resources with level-based mechanics
 * @dev This contract allows players to spend various combinations of resources to recruit mercenaries.
 *      The level of mercenaries recruited depends on the number of different resource types used.
 *      All resource combinations must include Gold, and mercenary tokens are created dynamically if needed.
 * @author Merc Mania Development Team
 */
contract MercRecruiter is IMercRecruiter, AccessManaged {
    /// @notice Reference to the resource manager for validation and Gold access
    /// @dev Used to validate resource combinations and ensure Gold is included
    IResourceManager public immutable RESOURCE_MANAGER;

    /// @notice Reference to the game master for balance management
    /// @dev Used to spend player resources and validate sufficient balances
    GameMaster public immutable GAME_MASTER;

    /// @notice Reference to the mercenary factory for creating new mercenary types
    /// @dev Used to create new mercenary tokens when needed and check existing levels
    MercAssetFactory public immutable MERC_FACTORY;

    /// @notice Reference to the PlayerStats contract for tracking individual player statistics
    PlayerStats public immutable PLAYER_STATS;

    /// @notice Reference to the GameStats contract for tracking overall game statistics
    GameStats public immutable GAME_STATS;

    error MercTokenDoesNotExist();
    error InsufficientResources();
    error AmountMustBeGreaterThanZero();

    /**
     * @notice Constructs the MercRecruiter with required contract dependencies
     * @dev Sets up immutable references to other system contracts
     * @param _authority The access manager contract that controls permissions
     * @param _resourceManager The resource manager for validation and Gold access
     * @param _gameMaster The game master for balance management
     * @param _mercFactory The mercenary factory for token creation
     * @param _playerStats The PlayerStats contract for individual player tracking
     * @param _gameStats The GameStats contract for overall game tracking
     */
    constructor(
        address _authority,
        IResourceManager _resourceManager,
        GameMaster _gameMaster,
        MercAssetFactory _mercFactory,
        PlayerStats _playerStats,
        GameStats _gameStats
    ) AccessManaged(_authority) {
        RESOURCE_MANAGER = _resourceManager;
        GAME_MASTER = _gameMaster;
        MERC_FACTORY = _mercFactory;
        PLAYER_STATS = _playerStats;
        GAME_STATS = _gameStats;
    }

    /**
     * @notice Recruits mercenaries by spending the specified resources
     * @dev The level of recruited mercenaries equals the number of resource types used.
     *      Requires that a mercenary token already exists for the calculated level.
     *      All resource combinations must include Gold and be valid registered resources.
     * @param resources Array of resource token contracts to spend (must include Gold, no duplicates)
     * @param amount The number of mercenaries to recruit (must be > 0)
     */
    function recruitMercs(IERC20[] calldata resources, uint256 amount) external {
        require(amount > 0, AmountMustBeGreaterThanZero());

        // Validate resources (includes Gold check and duplicate check)
        RESOURCE_MANAGER.validateResources(resources);

        // Determine merc level based on resource count
        uint256 level = resources.length;

        // Check if player has sufficient resources
        require(canRecruitMercs(msg.sender, resources, amount), InsufficientResources());

        // Spend resources from GameMaster balances
        for (uint256 i = 0; i < resources.length; i++) {
            GAME_MASTER.spendBalance(msg.sender, resources[i], amount);
        }

        // Ensure merc token exists for this level, revert if not
        address mercToken = MERC_FACTORY.getMercByLevel(level);
        require(mercToken != address(0), MercTokenDoesNotExist());

        // Mint mercs to game master and add to player's balance
        IERC20MintableBurnable(mercToken).mint(address(GAME_MASTER), amount);
        GAME_MASTER.addBalance(msg.sender, IERC20(mercToken), amount);

        emit MercsRecruited(msg.sender, level, amount, resources);

        // Record statistics
        PLAYER_STATS.recordRecruitment(msg.sender, level, amount);
        GAME_STATS.recordGlobalRecruitment(msg.sender, level, amount);
    }

    /**
     * @notice Calculates the mercenary level for a given resource combination
     * @dev The level simply equals the number of different resource types provided
     * @param resources Array of resource token contracts
     * @return The level of mercenaries that would be recruited with these resources
     */
    function getRequiredLevel(IERC20[] calldata resources) external pure returns (uint256) {
        return resources.length;
    }

    /**
     * @notice Checks if a player can recruit mercenaries with the specified resources and amount
     * @dev Validates both resource combination rules and player balance sufficiency
     * @param player The address of the player attempting to recruit
     * @param resources Array of resource token contracts to check
     * @param amount The number of mercenaries to recruit
     * @return True if the player can recruit the specified mercenaries, false otherwise
     */
    function canRecruitMercs(address player, IERC20[] calldata resources, uint256 amount) public view returns (bool) {
        // Check basic requirements
        if (resources.length == 0 || amount == 0) {
            return false;
        }

        // Check if Gold is included
        bool goldIncluded = false;
        for (uint256 i = 0; i < resources.length; i++) {
            if (resources[i] == RESOURCE_MANAGER.GOLD()) {
                goldIncluded = true;
            }
            if (!RESOURCE_MANAGER.isResource(resources[i])) {
                return false;
            }
            for (uint256 j = i + 1; j < resources.length; j++) {
                if (resources[i] == resources[j]) {
                    return false;
                }
            }
            if (GAME_MASTER.getBalance(player, resources[i]) < amount) {
                return false;
            }
        }
        if (!goldIncluded) {
            return false;
        }

        return true;
    }
}
