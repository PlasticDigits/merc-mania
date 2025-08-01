// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {IGameMaster} from "./interfaces/IGameMaster.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20MintableBurnable} from "./interfaces/IERC20MintableBurnable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PlayerStats} from "./PlayerStats.sol";
import {GameStats} from "./GameStats.sol";

/**
 * @title GameMaster
 * @notice Central contract for managing player token deposits and withdrawals with game-specific mechanics
 * @dev This contract acts as a secure escrow for all game tokens, implementing a withdrawal penalty system
 *      where 50% of withdrawn tokens are burned to maintain token economics. Authorized contracts can
 *      manipulate balances for game mechanics like combat, crafting, and resource consumption.
 * @author Merc Mania Development Team
 */
contract GameMaster is IGameMaster, AccessManaged, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Dead address used when tokens cannot be burned through the standard burn interface
    /// @dev Tokens sent here are effectively removed from circulation
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Nested mapping to track user balances for each token
    /// @dev Structure: user address => token contract => balance amount
    ///      This allows the GameMaster to maintain separate accounting from token contracts
    mapping(address user => mapping(IERC20 token => uint256 balance)) private _balances;

    /// @notice Mapping to track total held tokens for each token contract, prevents mismatch between GameMaster and token contracts
    /// @dev Structure: token contract => total amount held
    mapping(IERC20 token => uint256 totalHeld) private _totals;

    /// @notice Reference to the PlayerStats contract for tracking individual player statistics
    PlayerStats public immutable PLAYER_STATS;

    /// @notice Reference to the GameStats contract for tracking overall game statistics
    GameStats public immutable GAME_STATS;

    /// @notice Basis points for withdrawal rate limit (10,000 = 100%)
    uint256 public withdrawalRateLimitBps;

    /// @notice Struct to track withdrawal data within a 24-hour window
    struct WithdrawalWindow {
        uint256 windowStart; // Timestamp when the current window started
        uint256 amountWithdrawn; // Total amount withdrawn in current window
    }

    /// @notice Mapping to track withdrawal windows per token
    mapping(IERC20 token => WithdrawalWindow) private withdrawalWindows;

    /**
     * @notice Constructs the GameMaster with the specified access authority and stats contracts
     * @dev Sets up access control for the contract and connects to statistics tracking
     * @param _authority The access manager contract that controls permissions
     * @param _playerStats The PlayerStats contract for individual player tracking
     * @param _gameStats The GameStats contract for overall game tracking
     */
    constructor(address _authority, PlayerStats _playerStats, GameStats _gameStats) AccessManaged(_authority) {
        PLAYER_STATS = _playerStats;
        GAME_STATS = _gameStats;
        withdrawalRateLimitBps = 100; // Default to 1% daily withdrawal limit
    }

    /**
     * @notice Internal function to check and update withdrawal rate limits
     * @dev Resets window if more than 24 hours have passed, then checks if withdrawal would exceed limit
     * @param token The token being withdrawn
     * @param amount The amount being withdrawn (total amount, before burn calculation)
     */
    function _checkWithdrawalRateLimit(IERC20 token, uint256 amount) internal {
        if (withdrawalRateLimitBps == 0) {
            return; // No rate limit if set to 0
        }

        WithdrawalWindow storage window = withdrawalWindows[token];

        // Reset window if more than 24 hours have passed or if it's the first withdrawal
        if (window.windowStart == 0 || block.timestamp >= window.windowStart + 1 days) {
            window.windowStart = block.timestamp;
            window.amountWithdrawn = 0;
        }

        // Calculate rate limit based on total token supply held by GameMaster
        uint256 totalHeld = _totals[token];
        uint256 rateLimit = (totalHeld * withdrawalRateLimitBps) / 10000;

        // Check if this withdrawal would exceed the rate limit
        require(window.amountWithdrawn + amount <= rateLimit, "Withdrawal rate limit exceeded");

        // Update the withdrawal amount for this window
        window.amountWithdrawn += amount;
    }

    /**
     * @notice Allows users to deposit tokens into the GameMaster for use in game mechanics
     * @dev Transfers tokens from the user to this contract and updates internal balance accounting
     *      Tokens deposited here can be used by authorized game contracts
     * @param token The ERC20 token contract to deposit
     * @param amount The amount of tokens to deposit (must be > 0)
     */
    function deposit(IERC20 token, uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        // Transfer tokens from user to this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Update user balance
        _balances[msg.sender][token] += amount;

        _totals[token] += amount;

        emit Deposited(msg.sender, address(token), amount);
        _checkTotal(token);

        // Record statistics
        PLAYER_STATS.recordDeposit(msg.sender, token, amount);
        GAME_STATS.recordGlobalDeposit(msg.sender, token, amount);
    }

    /**
     * @notice Allows users to withdraw tokens with a 50% burn penalty
     * @dev Implements the game's tokenomics by burning half of withdrawn tokens
     *      If burning fails (non-burnable tokens), sends them to the dead address instead
     * @param token The ERC20 token contract to withdraw from
     * @param amount The total amount to withdraw (before penalty calculation)
     */
    function withdraw(IERC20 token, uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(_balances[msg.sender][token] >= amount, "Insufficient balance");

        // Check withdrawal rate limits
        _checkWithdrawalRateLimit(token, amount);

        // Calculate amounts: 50% burned, 50% withdrawn
        uint256 withdrawAmount = amount / 2;
        uint256 burnAmount = amount - withdrawAmount;

        // Update user balance
        _balances[msg.sender][token] -= amount;
        _totals[token] -= amount;
        // Try to burn tokens if the token supports it
        if (burnAmount > 0) {
            try IERC20MintableBurnable(address(token)).burn(burnAmount) {
                // Burn successful
            } catch {
                // If burn fails, send tokens to dead address
                token.safeTransfer(DEAD_ADDRESS, burnAmount);
            }
        }

        // Transfer remaining tokens to user
        if (withdrawAmount > 0) {
            token.safeTransfer(msg.sender, withdrawAmount);
        }

        emit Withdrawn(msg.sender, address(token), withdrawAmount, burnAmount);
        _checkTotal(token);

        // Record statistics
        PLAYER_STATS.recordWithdrawal(msg.sender, token, amount, burnAmount);
        GAME_STATS.recordGlobalWithdrawal(msg.sender, token, amount, burnAmount);
    }

    /**
     * @notice Returns the GameMaster balance for a specific user and token
     * @dev These balances are separate from the user's actual token balances
     * @param user The address to check the balance for
     * @param token The token contract to check the balance of
     * @return The amount of tokens the user has deposited in the GameMaster
     */
    function getBalance(address user, IERC20 token) external view returns (uint256) {
        return _balances[user][token];
    }

    /**
     * @notice Internal function for reducing user balances within game mechanics
     * @dev Used internally and by authorized external contracts for game operations
     * @param user The user whose balance will be reduced
     * @param token The token to deduct from
     * @param amount The amount to deduct from the user's balance
     */
    function _spendBalance(address user, IERC20 token, uint256 amount) internal {
        require(_balances[user][token] >= amount, "Insufficient balance");
        _balances[user][token] -= amount;
        _totals[token] -= amount;
    }

    /**
     * @notice Internal function for increasing user balances within game mechanics
     * @dev Used internally and by authorized external contracts for game rewards
     * @param user The user whose balance will be increased
     * @param token The token to add to the user's balance
     * @param amount The amount to add to the user's balance
     */
    function _addBalance(address user, IERC20 token, uint256 amount) internal {
        _balances[user][token] += amount;
        _totals[token] += amount;
    }

    /**
     * @notice Internal function for transferring balances between users
     * @dev Used internally and by authorized external contracts for game operations
     * @param userFrom The user whose balance will be reduced
     * @param userTo The user whose balance will be increased
     * @param token The token to transfer
     * @param amount The amount to transfer
     */
    function _transferBalance(address userFrom, address userTo, IERC20 token, uint256 amount) internal {
        _balances[userFrom][token] -= amount;
        _balances[userTo][token] += amount;
        _checkTotal(token);
    }

    /**
     * @notice Allows authorized contracts to spend (burn) user balances for game mechanics
     * @dev Only callable by contracts with appropriate permissions (e.g., combat, crafting systems)
     * @param user The user whose balance will be spent
     * @param token The token to spend from the user's balance
     * @param amount The amount to spend from the user's balance
     */
    function spendBalance(address user, IERC20 token, uint256 amount) external restricted nonReentrant whenNotPaused {
        _spendBalance(user, token, amount);
        IERC20MintableBurnable(address(token)).burn(amount);
        _checkTotal(token);
    }

    /**
     * @notice Allows authorized contracts to add to user balances for game mechanics
     * @dev Only callable by contracts with appropriate permissions (e.g., mining rewards, quest completions)
     * @param user The user whose balance will be increased
     * @param token The token to add to the user's balance
     * @param amount The amount to add to the user's balance
     */
    function addBalance(address user, IERC20 token, uint256 amount) external restricted nonReentrant whenNotPaused {
        IERC20MintableBurnable(address(token)).mint(address(this), amount);
        _addBalance(user, token, amount);
        _checkTotal(token);
    }

    /**
     * @notice Allows authorized contracts to transfer balances between users
     * @dev Only callable by contracts with appropriate permissions (e.g., combat, crafting systems)
     * @param userFrom The user whose balance will be reduced
     * @param userTo The user whose balance will be increased
     * @param token The token to transfer
     * @param amount The amount to transfer
     */
    function transferBalance(address userFrom, address userTo, IERC20 token, uint256 amount)
        external
        restricted
        nonReentrant
        whenNotPaused
    {
        _transferBalance(userFrom, userTo, token, amount);
    }

    /**
     * @notice Pauses all critical operations including deposits, withdrawals, and balance modifications
     * @dev Only callable by authorized addresses with appropriate permissions
     */
    function pause() external restricted {
        _pause();
    }

    /**
     * @notice Unpauses all critical operations
     * @dev Only callable by authorized addresses with appropriate permissions
     */
    function unpause() external restricted {
        _unpause();
    }

    /**
     * @notice Sets the withdrawal rate limit in basis points
     * @dev Only callable by authorized addresses with appropriate permissions
     * @param _rateLimitBps New rate limit in basis points (10,000 = 100%, 0 = no limit)
     */
    function setWithdrawalRateLimit(uint256 _rateLimitBps) external restricted {
        require(_rateLimitBps <= 10000, "Rate limit cannot exceed 100%");
        uint256 oldLimit = withdrawalRateLimitBps;
        withdrawalRateLimitBps = _rateLimitBps;
        emit WithdrawalRateLimitUpdated(oldLimit, _rateLimitBps);
    }

    /**
     * @notice Gets withdrawal data for a specific token's current window
     * @param token The token to check withdrawal data for
     * @return windowStart The timestamp when the current window started
     * @return amountWithdrawn The amount withdrawn in the current window
     * @return rateLimit The current rate limit for this token
     */
    function getWithdrawalWindowData(IERC20 token)
        external
        view
        returns (uint256 windowStart, uint256 amountWithdrawn, uint256 rateLimit)
    {
        WithdrawalWindow storage window = withdrawalWindows[token];
        windowStart = window.windowStart;
        amountWithdrawn = window.amountWithdrawn;

        if (withdrawalRateLimitBps == 0) {
            rateLimit = type(uint256).max; // No limit
        } else {
            uint256 totalHeld = _totals[token];
            rateLimit = (totalHeld * withdrawalRateLimitBps) / 10000;
        }
    }

    function _checkTotal(IERC20 token) internal view {
        // could be high if someone sends tokens to the game master directly, which they should not do
        require(_totals[token] <= token.balanceOf(address(this)), "Total mismatch");
    }
}
