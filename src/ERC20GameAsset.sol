// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IGuardERC20} from "./interfaces/IGuardERC20.sol";
import {IERC20MintableBurnable} from "./interfaces/IERC20MintableBurnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title ERC20GameAsset
 * @notice A mintable and burnable ERC20 token representing in-game assets with access control and transfer guards
 * @dev This contract implements an ERC20 token that can be used for game assets like weapons, armor, or consumables.
 *      It uses the proxy pattern with initialization instead of constructors for deployment efficiency.
 *      All transfers are subject to validation by a guard contract for game-specific rules.
 * @author Merc Mania Development Team
 */
contract ERC20GameAsset is AccessManaged, ERC20, Initializable, IERC20MintableBurnable {
    /// @notice The guard contract that validates all token transfers
    /// @dev This guard can implement game-specific transfer restrictions or rules
    IGuardERC20 public guard;

    /// @notice URI pointing to the token's metadata (png, jpg, gif, svg)
    /// @dev Can be used to store visual representation or additional metadata for the game asset
    string public tokenUri;

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
     * @notice Initializes the game asset token with the provided parameters
     * @dev This function replaces the constructor for proxy-based deployment
     *      Can only be called once due to the initializer modifier
     * @param _authority The access manager contract that controls permissions
     * @param _guard The guard contract that will validate all transfers
     * @param _name The human-readable name of the token (e.g., "Magic Sword")
     * @param _symbol The ticker symbol for the token (e.g., "SWORD")
     * @param _tokenUri The URI pointing to the token's metadata
     */
    function initialize(
        address _authority,
        IGuardERC20 _guard,
        string memory _name,
        string memory _symbol,
        string memory _tokenUri
    ) external initializer {
        // Initialize AccessManaged with the authority
        _setAuthority(_authority);

        // Store name and symbol for our overridden functions
        _tokenName = _name;
        _tokenSymbol = _symbol;

        guard = _guard;
        tokenUri = _tokenUri;
    }

    /**
     * @notice Returns the name of the token
     * @dev Overrides the ERC20 name() function to return our initialized value
     * @return The name of the token
     */
    function name() public view override returns (string memory) {
        return _tokenName;
    }

    /**
     * @notice Returns the symbol of the token
     * @dev Overrides the ERC20 symbol() function to return our initialized value
     * @return The symbol of the token
     */
    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    /**
     * @notice Mints new tokens to the specified address
     * @dev Only callable by addresses with the appropriate role permissions
     *      Used by game systems to create new assets for players
     * @param to The address to receive the newly minted tokens
     * @param amount The amount of tokens to mint (in wei units)
     */
    function mint(address to, uint256 amount) public restricted {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from the caller's balance
     * @dev Allows players to destroy their assets, potentially for crafting or other game mechanics
     * @param value The amount of tokens to burn from the caller's balance
     */
    function burn(uint256 value) public {
        _burn(_msgSender(), value);
    }

    /**
     * @notice Burns tokens from another address (with allowance)
     * @dev Allows burning tokens from another address if the caller has sufficient allowance
     *      Useful for game systems that need to consume assets on behalf of players
     * @param from The address to burn tokens from
     * @param value The amount of tokens to burn
     */
    function burnFrom(address from, uint256 value) public {
        if (from != _msgSender()) {
            // _spendAllowance will revert if the allowance is not sufficient
            _spendAllowance(from, _msgSender(), value);
        }
        _burn(from, value);
    }

    /**
     * @notice Internal function called on every token transfer
     * @dev Overrides ERC20's _update to add guard validation and special guard approval logic
     *      The guard contract can implement game-specific transfer rules
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
}
