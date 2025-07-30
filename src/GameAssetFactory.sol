// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {ERC20GameAsset} from "./ERC20GameAsset.sol";
import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {GameMaster} from "./GameMaster.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title GameAssetFactory
 * @notice Factory contract for creating and managing game asset tokens
 * @dev This contract uses the minimal proxy pattern (EIP-1167) to efficiently deploy new game asset tokens.
 *      It maintains a registry of all created assets and provides enumeration capabilities.
 *      Only authorized addresses can create new assets through access control.
 * @author Merc Mania Development Team
 */
contract GameAssetFactory is AccessManaged {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Role identifier for contracts that can mint asset tokens
    /// @dev Uses role ID 1 to distinguish from ADMIN_ROLE (0) and PUBLIC_ROLE (max uint64)
    ///      This role is granted to GameMaster so it can mint/burn assets
    uint64 public constant MINTER_ROLE = 1;

    /// @notice The guard contract that will be applied to all created assets
    /// @dev Immutable after deployment, ensures consistent transfer validation across all assets
    IGuardERC20 public immutable GUARD;

    /// @notice Reference to the GameMaster contract for granting mint permissions
    /// @dev GameMaster needs to mint/burn tokens for game mechanics
    GameMaster public immutable GAME_MASTER;

    /// @notice The implementation contract address used for creating minimal proxies
    /// @dev Deployed once during factory construction to save gas on subsequent asset creation
    address public immutable ASSET_IMPLEMENTATION;

    /// @notice Set containing addresses of all deployed game assets
    /// @dev Uses EnumerableSet for efficient storage and enumeration of asset addresses
    EnumerableSet.AddressSet private _allAssets;

    /// @notice Emitted when a new game asset is created
    /// @param asset The address of the newly created asset
    /// @param name The name of the new asset
    /// @param symbol The symbol of the new asset
    event AssetCreated(address indexed asset, string name, string symbol);

    /**
     * @notice Constructs the GameAssetFactory with the specified authority, guard, and game master
     * @dev Deploys the implementation contract during construction for use in cloning
     * @param _authority The access manager contract that controls permissions
     * @param _guard The guard contract that will validate transfers for all created assets
     * @param _gameMaster The GameMaster contract that will need mint permissions on assets
     */
    constructor(address _authority, IGuardERC20 _guard, GameMaster _gameMaster) AccessManaged(_authority) {
        GUARD = _guard;
        GAME_MASTER = _gameMaster;

        // Deploy the implementation contract once
        ASSET_IMPLEMENTATION = address(new ERC20GameAsset());
    }

    /**
     * @notice Creates a new game asset token using the minimal proxy pattern
     * @dev Only callable by addresses with appropriate permissions
     *      Creates a minimal proxy clone of the implementation contract for gas efficiency
     * @param name The human-readable name of the asset (e.g., "Magic Sword")
     * @param symbol The ticker symbol for the asset (e.g., "SWORD")
     * @param tokenURI The URI pointing to the asset's metadata
     * @return The address of the newly created asset contract
     */
    function createAsset(string calldata name, string calldata symbol, string calldata tokenURI)
        external
        restricted
        returns (address)
    {
        // Create a minimal proxy clone of the implementation
        address assetAddress = Clones.clone(ASSET_IMPLEMENTATION);

        // Initialize the cloned asset
        ERC20GameAsset(assetAddress).initialize(authority(), GUARD, name, symbol, tokenURI);

        // Grant mint permissions to GameMaster on the new asset
        // Get the mint function selector for ERC20MintableBurnable.mint(address,uint256)
        bytes4 mintSelector = bytes4(keccak256("mint(address,uint256)"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = mintSelector;

        // Set the target function role to MINTER_ROLE for GameMaster to be able to mint the asset
        IAccessManager(authority()).setTargetFunctionRole(address(assetAddress), selectors, MINTER_ROLE);

        // Grant MINTER_ROLE to GameMaster with no execution delay (only if this is the first asset)
        if (_allAssets.length() == 0) {
            IAccessManager(authority()).grantRole(MINTER_ROLE, address(GAME_MASTER), 0);
        }

        _allAssets.add(assetAddress);

        emit AssetCreated(assetAddress, name, symbol);

        return assetAddress;
    }

    /**
     * @notice Returns an array of all created game asset addresses
     * @dev Returns a copy of the internal set as an array for external consumption
     *      Note: This can be gas-expensive for large numbers of assets
     * @return assets Array containing addresses of all created game assets
     */
    function getAllAssets() external view returns (address[] memory) {
        uint256 length = _allAssets.length();
        address[] memory assets = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            assets[i] = _allAssets.at(i);
        }
        return assets;
    }

    /**
     * @notice Returns the total number of created game assets
     * @dev More gas-efficient than getAllAssets() when only the count is needed
     * @return The total number of game assets created by this factory
     */
    function getAssetCount() external view returns (uint256) {
        return _allAssets.length();
    }

    /**
     * @notice Returns an array of game asset addresses in reverse chronological order
     * @dev Gets assets from index i to count n, where index 0 is the most recent asset
     *      Handles overflow gracefully by returning only available assets
     * @param startIndex The starting index from the end (0 = most recent)
     * @param count The number of assets to return
     * @return An array of game asset addresses in reverse chronological order
     */
    function getAssets(uint256 startIndex, uint256 count) external view returns (address[] memory) {
        uint256 totalAssets = _allAssets.length();

        // If no assets or startIndex is beyond available assets, return empty array
        if (totalAssets == 0 || startIndex >= totalAssets) {
            return new address[](0);
        }

        // Calculate the actual array index (reverse order)
        uint256 arrayStartIndex = totalAssets - 1 - startIndex;

        // Calculate how many assets we can actually return
        uint256 availableAssets = arrayStartIndex + 1; // +1 because index is inclusive
        uint256 actualCount = count > availableAssets ? availableAssets : count;

        // Create result array
        address[] memory result = new address[](actualCount);

        // Fill the result array going backwards through the assets
        for (uint256 i = 0; i < actualCount; i++) {
            result[i] = _allAssets.at(arrayStartIndex - i);
        }

        return result;
    }
}
