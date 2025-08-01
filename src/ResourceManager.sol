// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IResourceManager} from "./interfaces/IResourceManager.sol";
import {GameAssetFactory} from "./GameAssetFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ResourceManager
 * @notice Central registry and management contract for all game resources
 * @dev This contract maintains the authoritative list of valid game resources and enforces
 *      resource validation rules. Gold is treated as a special required resource that must
 *      be included in all resource combinations. The contract uses a factory pattern to
 *      create new resource tokens and maintains metadata about each resource.
 * @author Merc Mania Development Team
 */
contract ResourceManager is IResourceManager, AccessManaged {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The game asset factory used to create new resource tokens
    /// @dev Immutable reference set during construction, used for creating standardized resource tokens
    GameAssetFactory public immutable ASSET_FACTORY;

    /// @notice Set containing addresses of all valid game resources
    /// @dev Uses EnumerableSet for efficient storage, enumeration, and membership testing
    EnumerableSet.AddressSet private _resources;

    /// @notice The Gold token, which is required in all resource combinations
    /// @dev Special constant resource that serves as the base currency for the game
    ///      Automatically created during contract construction
    IERC20 public GOLD;

    /**
     * @notice Constructs the ResourceManager
     * @dev Gold must be initialized separately using initializeGold() after deployment
     * @param _authority The access manager contract that controls permissions
     * @param _assetFactory The factory contract used to create resource tokens
     */
    constructor(address _authority, GameAssetFactory _assetFactory) AccessManaged(_authority) {
        ASSET_FACTORY = _assetFactory;
        // GOLD is initialized to address(0) and must be set via initializeGold()
    }

    // initialize gold as the first resource
    function initializeGold(string calldata goldTokenUri) external restricted {
        // only allow initialization once
        require(GOLD == IERC20(address(0)), "Gold already initialized");

        address goldAddress = ASSET_FACTORY.createAsset("Gold", "GOLD", goldTokenUri);
        GOLD = IERC20(goldAddress);
        _resources.add(goldAddress);
        emit ResourceAdded(goldAddress, "Gold");
    }

    /**
     * @notice Creates and registers a new game resource
     * @dev Only callable by addresses with appropriate permissions
     *      Creates a new ERC20 token through the asset factory and registers it as a valid resource
     * @param name The human-readable name of the resource (e.g., "Iron Ore")
     * @param symbol The ticker symbol for the resource (e.g., "IRON")
     * @param tokenURI The URI pointing to the resource's metadata
     * @return The address of the newly created resource token
     */
    function addResource(string calldata name, string calldata symbol, string calldata tokenURI)
        external
        restricted
        returns (address)
    {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");

        address resourceAddress = ASSET_FACTORY.createAsset(name, symbol, tokenURI);
        require(_resources.add(resourceAddress), "Resource already exists");

        emit ResourceAdded(resourceAddress, name);
        return resourceAddress;
    }

    /**
     * @notice Removes a resource from the valid resource registry
     * @dev Only callable by addresses with appropriate permissions
     *      Gold cannot be removed as it's a core game currency
     * @param resource The resource token contract to remove from the registry
     */
    function removeResource(IERC20 resource) external restricted {
        require(resource != GOLD, "Cannot remove Gold");
        require(_resources.remove(address(resource)), "Resource does not exist");

        emit ResourceRemoved(address(resource));
    }

    /**
     * @notice Returns the total number of registered resources
     * @dev More gas-efficient than getAllResources() when only the count is needed
     * @return The total number of valid resources in the system
     */
    function getResourceCount() external view returns (uint256) {
        return _resources.length();
    }

    /**
     * @notice Returns the resource at the specified index
     * @dev Used for iteration when combined with getResourceCount()
     *      Index must be less than the total resource count
     * @param index The zero-based index of the resource to retrieve
     * @return The resource token contract at the given index
     */
    function getResourceAt(uint256 index) external view returns (IERC20) {
        return IERC20(_resources.at(index));
    }

    /**
     * @notice Checks if a token is a valid registered resource
     * @dev Used throughout the system to validate resource token usage
     * @param resource The token contract to check
     * @return True if the token is a registered resource, false otherwise
     */
    function isResource(IERC20 resource) public view returns (bool) {
        return _resources.contains(address(resource));
    }

    /**
     * @notice Returns an array of all registered resource token contracts
     * @dev Returns a copy of the internal set as an array for external consumption
     *      Note: This can be gas-expensive for large numbers of resources
     * @return resources Array containing all registered resource token contracts
     */
    function getAllResources() external view returns (IERC20[] memory) {
        uint256 length = _resources.length();
        IERC20[] memory resources = new IERC20[](length);
        for (uint256 i = 0; i < length; i++) {
            resources[i] = IERC20(_resources.at(i));
        }
        return resources;
    }

    /**
     * @notice Validates that Gold is included in a resource array
     * @dev Internal validation helper that enforces Gold requirement
     *      Used by other validation functions to ensure Gold inclusion
     * @param resources Array of resource token contracts to check
     */
    function requireGoldIncluded(IERC20[] calldata resources) public view {
        bool goldIncluded = false;
        for (uint256 i = 0; i < resources.length; i++) {
            if (resources[i] == GOLD) {
                goldIncluded = true;
                break;
            }
        }
        require(goldIncluded, "Must include Gold");
    }

    /**
     * @notice Comprehensive validation of a resource array
     * @dev Validates that:
     *      1. At least one resource is provided
     *      2. All resources are valid registered resources
     *      3. Gold is included in the array
     *      4. No duplicate resources are present
     *      Used by recruitment and other systems that require resource combinations
     * @param resources Array of resource token contracts to validate
     */
    function validateResources(IERC20[] calldata resources) external view {
        require(resources.length > 0, "Must include at least one resource");

        requireGoldIncluded(resources);

        // Validate all resources are registered
        for (uint256 i = 0; i < resources.length; i++) {
            require(isResource(resources[i]), "Invalid resource");
        }

        // Check for duplicates
        for (uint256 i = 0; i < resources.length; i++) {
            for (uint256 j = i + 1; j < resources.length; j++) {
                require(resources[i] != resources[j], "Duplicate resources not allowed");
            }
        }
    }
}
