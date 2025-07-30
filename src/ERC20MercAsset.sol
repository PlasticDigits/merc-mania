// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {IERC20MintableBurnable} from "./interfaces/IERC20MintableBurnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title ERC20MercAsset
 * @notice A leveled mercenary token that represents mercenaries of different power levels in the game
 * @dev This contract extends ERC20GameAsset functionality with level-based mechanics for mercenaries.
 *      Each mercenary token has an associated level that determines its combat effectiveness.
 *      Uses proxy pattern with initialization for efficient deployment via factory contracts.
 * @author Merc Mania Development Team
 */
contract ERC20MercAsset is AccessManaged, ERC20, Initializable, IERC20MintableBurnable {
    /// @notice The guard contract that validates all token transfers
    /// @dev This guard can implement game-specific transfer restrictions or combat rules
    IGuardERC20 public guard;

    /// @notice URI pointing to the mercenary's metadata (png, jpg, gif, svg)
    /// @dev Can store visual representation, stats, or lore for the mercenary type
    string public tokenUri;

    /// @notice The power level of this mercenary type
    /// @dev Higher levels indicate more powerful mercenaries with greater combat effectiveness
    ///      Level is set during initialization and cannot be changed
    uint256 public level;

    /// @notice Internal storage for the token name since ERC20 doesn't support initialization
    /// @dev Required because OpenZeppelin's ERC20 sets name in constructor, but we use proxy pattern
    string private _tokenName;

    /// @notice Internal storage for the token symbol since ERC20 doesn't support initialization
    /// @dev Required because OpenZeppelin's ERC20 sets symbol in constructor, but we use proxy pattern
    string private _tokenSymbol;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC20("", "") AccessManaged(address(0)) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the mercenary token with the provided parameters
     * @dev This function replaces the constructor for proxy-based deployment
     *      Can only be called once due to the initializer modifier
     * @param _authority The access manager contract that controls permissions
     * @param _guard The guard contract that will validate all transfers
     * @param _name The human-readable name of the mercenary (e.g., "Level 3 Merc")
     * @param _symbol The ticker symbol for the mercenary (e.g., "MERC3")
     * @param _tokenUri The URI pointing to the mercenary's metadata
     * @param _level The power level of this mercenary type (1-based)
     */
    function initialize(
        address _authority,
        IGuardERC20 _guard,
        string memory _name,
        string memory _symbol,
        string memory _tokenUri,
        uint256 _level
    ) external initializer {
        // Initialize AccessManaged with the authority
        _setAuthority(_authority);

        // Store name and symbol for our overridden functions
        _tokenName = _name;
        _tokenSymbol = _symbol;

        guard = _guard;
        tokenUri = _tokenUri;
        level = _level;
    }

    /**
     * @notice Returns the name of the token
     * @dev Overrides the ERC20 name() function to return our initialized value
     * @return The name of the mercenary token
     */
    function name() public view override returns (string memory) {
        return _tokenName;
    }

    /**
     * @notice Returns the symbol of the token
     * @dev Overrides the ERC20 symbol() function to return our initialized value
     * @return The symbol of the mercenary token
     */
    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    /**
     * @notice Mints new mercenary tokens to the specified address
     * @dev Only callable by addresses with the appropriate role permissions
     *      Used by recruitment systems to create new mercenaries for players
     * @param to The address to receive the newly minted mercenary tokens
     * @param amount The amount of mercenary tokens to mint
     */
    function mint(address to, uint256 amount) public restricted {
        _mint(to, amount);
    }

    /**
     * @notice Burns mercenary tokens from the caller's balance
     * @dev Allows players to destroy their mercenaries, typically when they die in combat
     * @param value The amount of mercenary tokens to burn from the caller's balance
     */
    function burn(uint256 value) public {
        _burn(_msgSender(), value);
    }

    /**
     * @notice Burns mercenary tokens from another address (with allowance)
     * @dev Allows burning mercenaries from another address if the caller has sufficient allowance
     *      Used by game systems when mercenaries die in combat or are sacrificed
     * @param from The address to burn mercenary tokens from
     * @param value The amount of mercenary tokens to burn
     */
    function burnFrom(address from, uint256 value) public {
        if (from != _msgSender()) {
            _spendAllowance(from, _msgSender(), value);
        }
        _burn(from, value);
    }

    /**
     * @notice Internal function called on every token transfer
     * @dev Overrides ERC20's _update to add guard validation and special guard approval logic
     *      The guard contract can implement combat-specific transfer rules
     * @param from The address tokens are being transferred from (address(0) for minting)
     * @param to The address tokens are being transferred to (address(0) for burning)
     * @param value The amount of tokens being transferred
     */
    function _update(address from, address to, uint256 value) internal override {
        if (msg.sender == address(guard)) {
            _approve(from, address(guard), value);
        }
        guard.check(from, to, value);
        super._update(from, to, value);
    }

    /**
     * @notice Returns the power level of this mercenary type
     * @dev External getter function for the level, used by combat and recruitment systems
     * @return The level of this mercenary type
     */
    function getLevel() external view returns (uint256) {
        return level;
    }
}
