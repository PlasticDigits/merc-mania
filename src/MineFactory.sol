// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Mine} from "./Mine.sol";
import {IResourceManager} from "./interfaces/IResourceManager.sol";
import {GameMaster} from "./GameMaster.sol";
import {MercAssetFactory} from "./MercAssetFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {PlayerStats} from "./PlayerStats.sol";
import {GameStats} from "./GameStats.sol";

/**
 * @title MineFactory
 * @notice Factory contract for creating and managing resource-producing mines
 * @dev This contract uses the minimal proxy pattern (EIP-1167) to efficiently deploy mine contracts.
 *      It automatically configures access control for newly created mines to allow resource minting.
 *      The factory maintains registries for enumeration and resource-based lookups.
 * @author Merc Mania Development Team
 */
contract MineFactory is AccessManaged {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Role identifier for game contracts that can interact with GameMaster
    /// @dev Uses role ID 2 to distinguish from ADMIN_ROLE (0), MINTER_ROLE (1), and PUBLIC_ROLE (max uint64)
    ///      This role is granted to mine contracts so they can call GameMaster methods
    uint64 public constant GAME_ROLE = 2;

    /// @notice Reference to the resource manager for resource validation
    /// @dev Used to validate that resources exist before creating mines for them
    IResourceManager public immutable RESOURCE_MANAGER;

    /// @notice Reference to the game master for mine integration
    /// @dev Passed to mines during initialization for balance management
    GameMaster public immutable GAME_MASTER;

    /// @notice Reference to the mercenary factory for mine integration
    /// @dev Passed to mines during initialization for mercenary validation
    MercAssetFactory public immutable MERC_FACTORY;

    /// @notice The implementation contract address used for creating minimal proxies
    /// @dev Deployed once during factory construction to save gas on subsequent mine creation
    address public immutable MINE_IMPLEMENTATION;

    /// @notice Reference to the PlayerStats contract for tracking individual player statistics
    PlayerStats public immutable PLAYER_STATS;

    /// @notice Reference to the GameStats contract for tracking overall game statistics
    GameStats public immutable GAME_STATS;

    /// @notice Set containing addresses of all deployed mines
    /// @dev Uses EnumerableSet for efficient storage and enumeration of mine addresses
    EnumerableSet.AddressSet private _allMines;

    /// @notice Mapping from resource to set of mine addresses producing that resource
    /// @dev Allows efficient lookup of all mines producing a specific resource
    mapping(IERC20 resource => EnumerableSet.AddressSet resourceMines) private _resourceMines;

    /// @notice Emitted when a new mine is created
    /// @param mine The address of the newly created mine
    /// @param resource The resource token this mine will produce
    event MineCreated(address indexed mine, IERC20 indexed resource);

    error InvalidResource();

    /**
     * @notice Constructs the MineFactory with required contract dependencies
     * @dev Deploys the implementation contract during construction and sets up immutable references
     * @param _authority The access manager contract that controls permissions
     * @param _resourceManager The resource manager for validation
     * @param _gameMaster The game master for mine integration
     * @param _mercFactory The mercenary factory for mine integration
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

        // Deploy the implementation contract once
        MINE_IMPLEMENTATION = address(new Mine());
    }

    /**
     * @notice Creates a new mine for the specified resource
     * @dev Only callable by addresses with appropriate permissions
     *      Automatically configures access control to allow the mine to mint the resource
     *      Sets up MINTER_ROLE permissions for resource token minting
     * @param resource The resource token contract this mine will produce
     * @return The address of the newly created mine contract
     */
    function createMine(IERC20 resource, uint256 initialProductionPerDay, uint256 halvingPeriod)
        external
        restricted
        returns (address)
    {
        require(RESOURCE_MANAGER.isResource(resource), InvalidResource());

        // Create a minimal proxy clone of the implementation
        address mineAddress = Clones.clone(MINE_IMPLEMENTATION);

        // Initialize the cloned mine
        Mine(mineAddress).initialize(
            authority(),
            RESOURCE_MANAGER,
            GAME_MASTER,
            MERC_FACTORY,
            resource,
            initialProductionPerDay,
            halvingPeriod,
            PLAYER_STATS,
            GAME_STATS
        );

        // Grant game permissions to the new mine on GameMaster
        // Only set the target function roles if this is the first mine
        if (_allMines.length() == 0) {
            // Get the function selectors for GameMaster methods that mines need to call
            bytes4 spendBalanceSelector = bytes4(keccak256("spendBalance(address,address,uint256)"));
            bytes4 addBalanceSelector = bytes4(keccak256("addBalance(address,address,uint256)"));
            bytes4 transferBalanceSelector = bytes4(keccak256("transferBalance(address,address,address,uint256)"));

            bytes4[] memory selectors = new bytes4[](3);
            selectors[0] = spendBalanceSelector;
            selectors[1] = addBalanceSelector;
            selectors[2] = transferBalanceSelector;

            // Set the target function role to GAME_ROLE for mine contracts to be able to call GameMaster methods
            IAccessManager(authority()).setTargetFunctionRole(address(GAME_MASTER), selectors, GAME_ROLE);
        }

        // Grant GAME_ROLE to the new mine contract with no execution delay
        IAccessManager(authority()).grantRole(GAME_ROLE, mineAddress, 0);

        _allMines.add(mineAddress);
        _resourceMines[resource].add(mineAddress);

        emit MineCreated(mineAddress, resource);

        return mineAddress;
    }

    /**
     * @notice Returns an array of all created mine addresses
     * @dev Returns a copy of the internal set as an array for external consumption
     *      Note: This can be gas-expensive for large numbers of mines
     * @return mines Array containing addresses of all created mines
     */
    function getAllMines() external view returns (address[] memory) {
        uint256 length = _allMines.length();
        address[] memory mines = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            mines[i] = _allMines.at(i);
        }
        return mines;
    }

    /**
     * @notice Returns an array of mine addresses that produce the specified resource
     * @dev Returns a copy of the internal set as an array for external consumption
     *      Useful for finding all sources of a particular resource
     * @param resource The resource token contract to look up mines for
     * @return mines Array containing addresses of mines that produce this resource
     */
    function getMinesForResource(IERC20 resource) external view returns (address[] memory) {
        uint256 length = _resourceMines[resource].length();
        address[] memory mines = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            mines[i] = _resourceMines[resource].at(i);
        }
        return mines;
    }

    /**
     * @notice Returns the total number of created mines
     * @dev More gas-efficient than getAllMines() when only the count is needed
     * @return The total number of mines created by this factory
     */
    function getMineCount() external view returns (uint256) {
        return _allMines.length();
    }

    /**
     * @notice Returns the number of mines that produce the specified resource
     * @dev More gas-efficient than getMinesForResource() when only the count is needed
     * @param resource The resource token contract to count mines for
     * @return The number of mines that produce this resource
     */
    function getMineCountForResource(IERC20 resource) external view returns (uint256) {
        return _resourceMines[resource].length();
    }

    /**
     * @notice Returns an array of mine addresses in reverse chronological order
     * @dev Gets mines from index i to count n, where index 0 is the most recent mine
     *      Handles overflow gracefully by returning only available mines
     * @param startIndex The starting index from the end (0 = most recent)
     * @param count The number of mines to return
     * @return An array of mine addresses in reverse chronological order
     */
    function getMines(uint256 startIndex, uint256 count) external view returns (address[] memory) {
        uint256 totalMines = _allMines.length();

        // If no mines or startIndex is beyond available mines, return empty array
        if (totalMines == 0 || startIndex >= totalMines) {
            return new address[](0);
        }

        // Calculate the actual array index (reverse order)
        uint256 arrayStartIndex = totalMines - 1 - startIndex;

        // Calculate how many mines we can actually return
        uint256 availableMines = arrayStartIndex + 1; // +1 because index is inclusive
        uint256 actualCount = count > availableMines ? availableMines : count;

        // Create result array
        address[] memory result = new address[](actualCount);

        // Fill the result array going backwards through the mines
        for (uint256 i = 0; i < actualCount; i++) {
            result[i] = _allMines.at(arrayStartIndex - i);
        }

        return result;
    }

    /**
     * @notice Returns an array of mine addresses for a specific resource in reverse chronological order
     * @dev Gets mines from index i to count n, where index 0 is the most recent mine for this resource
     *      Handles overflow gracefully by returning only available mines
     * @param resource The resource token contract to get mines for
     * @param startIndex The starting index from the end (0 = most recent)
     * @param count The number of mines to return
     * @return An array of mine addresses for the resource in reverse chronological order
     */
    function getMinesForResource(IERC20 resource, uint256 startIndex, uint256 count)
        external
        view
        returns (address[] memory)
    {
        uint256 totalMines = _resourceMines[resource].length();

        // If no mines or startIndex is beyond available mines, return empty array
        if (totalMines == 0 || startIndex >= totalMines) {
            return new address[](0);
        }

        // Calculate the actual array index (reverse order)
        uint256 arrayStartIndex = totalMines - 1 - startIndex;

        // Calculate how many mines we can actually return
        uint256 availableMines = arrayStartIndex + 1; // +1 because index is inclusive
        uint256 actualCount = count > availableMines ? availableMines : count;

        // Create result array
        address[] memory result = new address[](actualCount);

        // Fill the result array going backwards through the resource mines
        for (uint256 i = 0; i < actualCount; i++) {
            result[i] = _resourceMines[resource].at(arrayStartIndex - i);
        }

        return result;
    }
}
