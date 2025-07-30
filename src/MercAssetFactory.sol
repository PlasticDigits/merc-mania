// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20MercAsset} from "./ERC20MercAsset.sol";
import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title MercAssetFactory
 * @notice Factory contract for creating and managing leveled mercenary tokens
 * @dev This contract uses the minimal proxy pattern (EIP-1167) to efficiently deploy mercenary tokens.
 *      Each mercenary token has a unique level, and only one token can exist per level.
 *      The factory maintains registries for enumeration and level-based lookups.
 * @author Merc Mania Development Team
 */
contract MercAssetFactory is AccessManaged {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice The guard contract that will be applied to all created mercenary tokens
    /// @dev Immutable after deployment, ensures consistent transfer validation across all mercenaries
    IGuardERC20 public immutable GUARD;

    /// @notice The implementation contract address used for creating minimal proxies
    /// @dev Deployed once during factory construction to save gas on subsequent mercenary creation
    address public immutable MERC_IMPLEMENTATION;

    /// @notice Set containing addresses of all deployed mercenary tokens
    /// @dev Uses EnumerableSet for efficient storage and enumeration of mercenary addresses
    EnumerableSet.AddressSet private _allMercs;

    /// @notice Mapping from level to mercenary token address
    /// @dev Ensures only one mercenary token exists per level
    ///      Level 0 is invalid, levels start from 1
    mapping(uint256 level => address mercToken) public levelToMerc;

    /// @notice Set containing all levels that have been created
    /// @dev Used for efficient enumeration of existing levels
    EnumerableSet.UintSet private _levels;

    /// @notice The highest level that has been created
    /// @dev Used for efficient enumeration of existing levels
    uint256 public highestLevel;

    /// @notice Emitted when a new mercenary token is created
    /// @param merc The address of the newly created mercenary token
    /// @param level The level of the new mercenary
    /// @param name The name of the new mercenary
    /// @param symbol The symbol of the new mercenary
    event MercCreated(address indexed merc, uint256 level, string name, string symbol);

    /**
     * @notice Constructs the MercAssetFactory with the specified authority and guard
     * @dev Deploys the implementation contract during construction for use in cloning
     * @param _authority The access manager contract that controls permissions
     * @param _guard The guard contract that will validate transfers for all created mercenaries
     */
    constructor(address _authority, IGuardERC20 _guard) AccessManaged(_authority) {
        GUARD = _guard;

        // Deploy the implementation contract once
        MERC_IMPLEMENTATION = address(new ERC20MercAsset());
    }

    /**
     * @notice Creates a new mercenary token with the highest level +1
     * @dev Only callable by addresses with appropriate permissions
     *      Each level can only have one mercenary token associated with it
     * @param name The human-readable name of the mercenary (e.g., "Level 3 Merc")
     * @param symbol The ticker symbol for the mercenary (e.g., "MERC3")
     * @param tokenURI The URI pointing to the mercenary's metadata
     * @return The address of the newly created mercenary contract
     */
    function createMerc(string calldata name, string calldata symbol, string calldata tokenURI)
        external
        restricted
        returns (address)
    {
        uint256 level = highestLevel + 1;

        // Create a minimal proxy clone of the implementation
        address mercAddress = Clones.clone(MERC_IMPLEMENTATION);

        // Initialize the cloned merc
        ERC20MercAsset(mercAddress).initialize(authority(), GUARD, name, symbol, tokenURI, level);

        _allMercs.add(mercAddress);
        _levels.add(level);

        levelToMerc[level] = mercAddress;
        highestLevel = level;

        emit MercCreated(mercAddress, level, name, symbol);

        return mercAddress;
    }

    /**
     * @notice Returns the mercenary token address for a specific level
     * @dev Returns address(0) if no mercenary exists for the given level
     * @param level The level to look up
     * @return The address of the mercenary token for this level, or address(0) if none exists
     */
    function getMercByLevel(uint256 level) external view returns (address) {
        return levelToMerc[level];
    }

    /**
     * @notice Returns an array of all created mercenary addresses
     * @dev Returns a copy of the internal set as an array for external consumption
     *      Note: This can be gas-expensive for large numbers of mercenaries
     * @return mercs Array containing addresses of all created mercenaries
     */
    function getAllMercs() external view returns (address[] memory) {
        uint256 length = _allMercs.length();
        address[] memory mercs = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            mercs[i] = _allMercs.at(i);
        }
        return mercs;
    }

    /**
     * @notice Returns an array of all levels that have mercenary tokens
     * @dev Returns a copy of the internal set as an array for external consumption
     *      Useful for iterating through available mercenary levels
     * @return levels Array containing all levels that have associated mercenary tokens
     */
    function getAllLevels() external view returns (uint256[] memory) {
        uint256 length = _levels.length();
        uint256[] memory levels = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            levels[i] = _levels.at(i);
        }
        return levels;
    }

    /**
     * @notice Returns the total number of created mercenary tokens
     * @dev More gas-efficient than getAllMercs() when only the count is needed
     * @return The total number of mercenary tokens created by this factory
     */
    function getMercCount() external view returns (uint256) {
        return _allMercs.length();
    }

    /**
     * @notice Checks if a mercenary token exists for the specified level
     * @dev Useful for validation before attempting operations on specific levels
     * @param level The level to check for existence
     * @return True if a mercenary token exists for this level, false otherwise
     */
    function levelExists(uint256 level) external view returns (bool) {
        return _levels.contains(level);
    }
}
