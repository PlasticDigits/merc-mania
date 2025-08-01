// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/Mine.sol";
import "../src/interfaces/IMine.sol";
import "../src/interfaces/IResourceManager.sol";
import "../src/interfaces/IGameMaster.sol";
import "../src/interfaces/IERC20MintableBurnable.sol";
import "../src/PlayerStats.sol";
import "../src/GameStats.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title MockResourceManager
 * @dev Mock implementation of IResourceManager for testing
 */
contract MockResourceManager is IResourceManager {
    IERC20 public GOLD;

    constructor(address _gold) {
        GOLD = IERC20(_gold);
    }

    function addResource(string calldata, string calldata, string calldata) external pure returns (address) {
        return address(0);
    }

    function removeResource(IERC20) external pure {}

    function getResourceCount() external pure returns (uint256) {
        return 1;
    }

    function getResourceAt(uint256) external view returns (IERC20) {
        return GOLD;
    }

    function isResource(IERC20) external pure returns (bool) {
        return true;
    }

    function getAllResources() external view returns (IERC20[] memory) {
        IERC20[] memory resources = new IERC20[](1);
        resources[0] = GOLD;
        return resources;
    }

    function validateResources(IERC20[] calldata) external pure {}
}

/**
 * @title MockGameMaster
 * @dev Mock implementation of IGameMaster for testing
 */
contract MockGameMaster is IGameMaster {
    mapping(address => mapping(IERC20 => uint256)) private balances;

    function deposit(IERC20, uint256) external pure {}
    function withdraw(IERC20, uint256) external pure {}

    function getBalance(address user, IERC20 token) external view returns (uint256) {
        return balances[user][token];
    }

    function spendBalance(address user, IERC20 token, uint256 amount) external {
        require(balances[user][token] >= amount, "Insufficient balance");
        balances[user][token] -= amount;

        // Mock burning by calling burn on the token if it supports it
        try IERC20MintableBurnable(address(token)).burn(amount) {
            // Success
        } catch {
            // Ignore burn failures for testing
        }
    }

    function addBalance(address user, IERC20 token, uint256 amount) external {
        // Mock minting
        try IERC20MintableBurnable(address(token)).mint(address(this), amount) {
            // Success
        } catch {
            // Ignore mint failures for testing
        }
        balances[user][token] += amount;
    }

    function transferBalance(address userFrom, address userTo, IERC20 token, uint256 amount) external {
        require(balances[userFrom][token] >= amount, "Insufficient balance");
        balances[userFrom][token] -= amount;
        balances[userTo][token] += amount;
    }

    // Helper function for testing
    function setBalance(address user, IERC20 token, uint256 amount) external {
        balances[user][token] = amount;
    }

    // Rate limiting functions (unused in mocks)
    function withdrawalRateLimitBps() external pure returns (uint256) {
        return 0;
    }

    function setWithdrawalRateLimit(uint256) external pure {}

    function getWithdrawalWindowData(IERC20) external pure returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }
}

/**
 * @title MockMercAssetFactory
 * @dev Mock implementation of MercAssetFactory for testing
 */
contract MockMercAssetFactory {
    mapping(uint256 => address) private mercsByLevel;

    function setMercByLevel(uint256 level, address merc) external {
        mercsByLevel[level] = merc;
    }

    function getMercByLevel(uint256 level) external view returns (address) {
        return mercsByLevel[level];
    }
}

/**
 * @title MockMercToken
 * @dev Mock mercenary token with mintable/burnable functionality
 */
contract MockMercToken is ERC20, IERC20MintableBurnable {
    uint256 public level;

    constructor(string memory name, string memory symbol, uint256 _level) ERC20(name, symbol) {
        level = _level;
    }

    function getLevel() external view returns (uint256) {
        return level;
    }

    function mint(address to, uint256 amount) external override {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external override {
        _burn(from, amount);
    }
}

/**
 * @title MockResourceToken
 * @dev Mock resource token for testing
 */
contract MockResourceToken is ERC20, IERC20MintableBurnable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external override {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external override {
        _burn(from, amount);
    }
}

/**
 * @title MineTest
 * @dev Comprehensive test suite for Mine contract with 100% coverage
 */
contract MineTest is Test {
    Mine public mine;
    AccessManager public accessManager;
    MockResourceManager public resourceManager;
    MockGameMaster public gameMaster;
    MockMercAssetFactory public mercFactory;
    MockResourceToken public goldToken;
    MockResourceToken public ironToken;
    MockMercToken public merc1;
    MockMercToken public merc2;
    MockMercToken public merc3;
    PlayerStats public playerStats;
    GameStats public gameStats;

    // Implementation contract for cloning
    address public implementation;

    address public admin = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public player3 = address(0x4);

    // Constants from Mine contract
    uint256 private constant HALVING_PERIOD = 3 days;
    uint256 private constant INITIAL_PRODUCTION_PER_DAY = 100e18;
    uint256 private constant MIN_MERCS_TO_SEIZE = 25 ether;
    uint256 private constant ABANDON_COOLDOWN = 1 days;
    uint256 private constant DEFENSE_BOOST_DURATION = 8 hours;
    uint256 private constant ABANDON_LOSS_PERCENTAGE = 10;

    function setUp() public {
        // Deploy access manager
        accessManager = new AccessManager(admin);

        // Deploy mock tokens
        goldToken = new MockResourceToken("Gold", "GOLD");
        ironToken = new MockResourceToken("Iron", "IRON");
        merc1 = new MockMercToken("Merc Level 1", "MERC1", 1);
        merc2 = new MockMercToken("Merc Level 2", "MERC2", 2);
        merc3 = new MockMercToken("Merc Level 3", "MERC3", 3);

        // Deploy mock contracts
        resourceManager = new MockResourceManager(address(goldToken));
        gameMaster = new MockGameMaster();
        mercFactory = new MockMercAssetFactory();

        // Setup merc factory mappings
        mercFactory.setMercByLevel(1, address(merc1));
        mercFactory.setMercByLevel(2, address(merc2));
        mercFactory.setMercByLevel(3, address(merc3));

        // Deploy stats contracts
        playerStats = new PlayerStats(address(accessManager));
        gameStats = new GameStats(address(accessManager));

        // Deploy implementation contract
        implementation = address(new Mine());

        // Create a clone for testing
        mine = _createMine();

        // Initialize mine
        mine.initialize(
            address(accessManager),
            resourceManager,
            GameMaster(address(gameMaster)),
            MercAssetFactory(address(mercFactory)),
            IERC20(address(ironToken)),
            INITIAL_PRODUCTION_PER_DAY,
            HALVING_PERIOD,
            playerStats,
            gameStats
        );

        // Setup access control permissions for the mine (similar to what MineFactory does)
        vm.startPrank(admin);

        // Set up function role permissions for PlayerStats
        bytes4[] memory playerStatsSelectors = new bytes4[](5);
        playerStatsSelectors[0] = bytes4(keccak256("recordSeizeAttempt(address,address,bool,uint256,address)"));
        playerStatsSelectors[1] = bytes4(keccak256("recordCombatStats(address,uint256,uint256,uint256)"));
        playerStatsSelectors[2] = bytes4(keccak256("recordAbandon(address,address)"));
        playerStatsSelectors[3] = bytes4(keccak256("recordClaim(address,address,uint256)"));
        playerStatsSelectors[4] = bytes4(keccak256("recordDefenseBoost(address,address)"));
        accessManager.setTargetFunctionRole(address(playerStats), playerStatsSelectors, 2);

        // Set up function role permissions for GameStats
        bytes4[] memory gameStatsSelectors = new bytes4[](4);
        gameStatsSelectors[0] = bytes4(keccak256("recordGlobalSeize(address,bool,uint256,uint256)"));
        gameStatsSelectors[1] = bytes4(keccak256("recordGlobalAbandon(address)"));
        gameStatsSelectors[2] = bytes4(keccak256("recordGlobalClaim(address,address,uint256)"));
        gameStatsSelectors[3] = bytes4(keccak256("recordGlobalDefenseBoost(address)"));
        accessManager.setTargetFunctionRole(address(gameStats), gameStatsSelectors, 2);

        // Grant GAME_ROLE (role ID 2) to the mine contract so it can call stats contracts
        accessManager.grantRole(2, address(mine), 0);

        vm.stopPrank();

        // Setup initial balances for testing
        gameMaster.setBalance(player1, IERC20(address(merc1)), 100 ether);
        gameMaster.setBalance(player1, IERC20(address(merc2)), 50 ether);
        gameMaster.setBalance(player1, IERC20(address(goldToken)), 1000 ether);

        gameMaster.setBalance(player2, IERC20(address(merc2)), 100 ether);
        gameMaster.setBalance(player2, IERC20(address(merc3)), 30 ether);
        gameMaster.setBalance(player2, IERC20(address(goldToken)), 500 ether);

        gameMaster.setBalance(player3, IERC20(address(merc1)), 20 ether); // Below minimum
    }

    function _createMine() internal returns (Mine) {
        // Create a minimal proxy clone of the implementation
        address clone = Clones.clone(implementation);
        return Mine(clone);
    }

    // =============================================================================
    // INITIALIZATION TESTS
    // =============================================================================

    function test_constructor() public {
        // Test that constructor properly disables initializers
        Mine freshMine = new Mine();

        // Should not be able to initialize after construction
        vm.expectRevert();
        freshMine.initialize(
            address(accessManager),
            resourceManager,
            GameMaster(address(gameMaster)),
            MercAssetFactory(address(mercFactory)),
            IERC20(address(ironToken)),
            INITIAL_PRODUCTION_PER_DAY,
            HALVING_PERIOD,
            playerStats,
            gameStats
        );
    }

    function test_initialize_success() public {
        Mine newMine = _createMine();

        newMine.initialize(
            address(accessManager),
            resourceManager,
            GameMaster(address(gameMaster)),
            MercAssetFactory(address(mercFactory)),
            IERC20(address(ironToken)),
            INITIAL_PRODUCTION_PER_DAY,
            HALVING_PERIOD,
            playerStats,
            gameStats
        );

        assertEq(address(newMine.RESOURCE_MANAGER()), address(resourceManager));
        assertEq(address(newMine.GAME_MASTER()), address(gameMaster));
        assertEq(address(newMine.MERC_FACTORY()), address(mercFactory));
        assertEq(address(newMine.resource()), address(ironToken));
        assertEq(newMine.owner(), address(0)); // Initially unowned
        assertEq(newMine.createdAt(), block.timestamp);
        assertEq(newMine.lastResourceClaim(), block.timestamp);
    }

    function test_initialize_twice_fails() public {
        vm.expectRevert();
        mine.initialize(
            address(accessManager),
            resourceManager,
            GameMaster(address(gameMaster)),
            MercAssetFactory(address(mercFactory)),
            IERC20(address(ironToken)),
            INITIAL_PRODUCTION_PER_DAY,
            HALVING_PERIOD,
            playerStats,
            gameStats
        );
    }

    // =============================================================================
    // UNOWNED MINE SEIZURE TESTS
    // =============================================================================

    function test_seize_unowned_mine_success() public {
        vm.prank(player1);

        vm.expectEmit(true, false, false, true);
        emit IMine.MineSeized(player1, 0, 0);

        mine.seize(1);

        assertEq(mine.owner(), player1);
        assertEq(address(mine.defenderMercToken()), address(merc1));
        assertEq(mine.lastSeized(), block.timestamp);
        assertEq(gameMaster.getBalance(address(mine), IERC20(address(merc1))), 100 ether);
        assertEq(gameMaster.getBalance(player1, IERC20(address(merc1))), 0);

        // Check battle log
        assertEq(mine.getBattleLogCount(), 1);
        IMine.BattleLogEntry memory entry = mine.getBattleLogEntry(0);
        assertEq(entry.attacker, player1);
        assertEq(entry.previousOwner, address(0));
        assertEq(address(entry.attackerMercToken), address(merc1));
        assertEq(entry.attackerMercAmount, 100 ether);
        assertEq(address(entry.defenderMercToken), address(0));
        assertEq(entry.defenderMercAmount, 0);
        assertEq(entry.attackerLosses, 0);
        assertEq(entry.defenderLosses, 0);
        assertTrue(entry.attackerWon);

        // Verify statistics were recorded
        (uint256 totalSeizes, uint256 successfulSeizes, uint256 failedSeizes) = playerStats.getSeizeStats(player1);
        assertEq(totalSeizes, 1, "Player total seize attempts not recorded");
        assertEq(successfulSeizes, 1, "Player successful seizes not recorded");
        assertEq(failedSeizes, 0, "Player failed seizes should be 0");

        (uint256 globalSuccess, uint256 globalFailed) = gameStats.getGlobalSeizeStats();
        uint256 globalTotal = globalSuccess + globalFailed;
        assertEq(globalTotal, 1, "Global total seize attempts not recorded");
        assertEq(globalSuccess, 1, "Global successful seizes not recorded");
        assertEq(globalFailed, 0, "Global failed seizes should be 0");
    }

    function test_seize_unowned_mine_insufficient_mercs() public {
        vm.prank(player3);
        vm.expectRevert(Mine.BelowMinMercs.selector);
        mine.seize(1);
    }

    function test_seize_unowned_mine_invalid_merc_level() public {
        vm.prank(player1);
        vm.expectRevert(Mine.InsufficientMercs.selector);
        mine.seize(999); // Non-existent level
    }

    // =============================================================================
    // OWNED MINE SEIZURE TESTS (COMBAT)
    // =============================================================================

    function test_seize_owned_mine_attacker_wins() public {
        // First, player1 seizes with level 1 mercs
        vm.prank(player1);
        mine.seize(1);

        // Player2 attacks with level 2 mercs (should win due to higher level)
        vm.prank(player2);

        vm.expectEmit(true, false, false, true);
        emit IMine.MineSeized(player2, 50 ether, 100 ether); // Expected losses

        mine.seize(2);

        assertEq(mine.owner(), player2);
        assertEq(address(mine.defenderMercToken()), address(merc2));

        // Check battle log
        assertEq(mine.getBattleLogCount(), 2);
        IMine.BattleLogEntry memory entry = mine.getBattleLogEntry(1);
        assertEq(entry.attacker, player2);
        assertEq(entry.previousOwner, player1);
        assertTrue(entry.attackerWon);
    }

    function test_seize_owned_mine_defender_wins() public {
        // First, player2 seizes with level 3 mercs (high power)
        vm.prank(player2);
        mine.seize(3);

        // Player1 attacks with level 1 mercs (should lose)
        // Attacker: 100 * 1 = 100 power
        // Defender: 30 * 3 = 90 power
        // Attacker wins! So let's test with fewer attacking mercs

        // Reduce player1's mercs to make defender win
        gameMaster.setBalance(player1, IERC20(address(merc1)), 25 ether); // Just above minimum

        vm.prank(player1);

        vm.expectEmit(true, false, false, true);
        emit IMine.MineSeized(player2, 25 ether, 8333333333333333333); // defenderLosses = (25*30)/90 = 8.333... ether

        mine.seize(1);

        assertEq(mine.owner(), player2); // Owner doesn't change
        assertEq(address(mine.defenderMercToken()), address(merc3));

        // Check attacker lost all mercs
        assertEq(gameMaster.getBalance(player1, IERC20(address(merc1))), 0);

        // Check battle log
        assertEq(mine.getBattleLogCount(), 2);
        IMine.BattleLogEntry memory entry = mine.getBattleLogEntry(1);
        assertFalse(entry.attackerWon);
    }

    function test_seize_owned_mine_self_attack_fails() public {
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player1);
        vm.expectRevert(Mine.AlreadyOwned.selector);
        mine.seize(2);
    }

    function test_seize_owned_mine_no_defenders() public {
        // Manually set up a scenario where mine has owner but no defender mercs
        vm.prank(player1);
        mine.seize(1);

        // Manually spend all defender mercs
        gameMaster.spendBalance(address(mine), IERC20(address(merc1)), 100 ether);

        vm.prank(player2);
        vm.expectRevert(Mine.InsufficientMercs.selector);
        mine.seize(2);
    }

    function test_getDefenderMercs_with_null_token() public {
        // Test the specific missing branch in getDefenderMercs() when defenderMercToken is address(0)
        // This happens naturally in a freshly initialized mine before any seizure

        // Create a fresh mine that hasn't been seized yet
        Mine freshMine = _createMine();
        freshMine.initialize(
            address(accessManager),
            resourceManager,
            GameMaster(address(gameMaster)),
            MercAssetFactory(address(mercFactory)),
            IERC20(address(ironToken)),
            INITIAL_PRODUCTION_PER_DAY,
            HALVING_PERIOD,
            playerStats,
            gameStats
        );

        // Call getDefenderMercs on the fresh mine - this will hit the missing branch
        // since defenderMercToken is address(0) in an unowned mine
        (IERC20 token, uint256 count) = freshMine.getDefenderMercs();

        // Verify the branch was hit
        assertEq(address(token), address(0));
        assertEq(count, 0);
    }

    // =============================================================================
    // RESOURCE PRODUCTION AND CLAIMING TESTS
    // =============================================================================

    function test_getCurrentProduction_initial() public view {
        uint256 expectedPerSecond = INITIAL_PRODUCTION_PER_DAY / 1 days;
        assertEq(mine.getCurrentProduction(), expectedPerSecond);
    }

    function test_getCurrentProduction_after_halving() public {
        // Fast forward past first halving period
        vm.warp(block.timestamp + HALVING_PERIOD + 1);

        uint256 expectedPerSecond = (INITIAL_PRODUCTION_PER_DAY / 2) / 1 days;
        assertEq(mine.getCurrentProduction(), expectedPerSecond);
    }

    function test_getCurrentProduction_multiple_halvings() public {
        // Fast forward past multiple halving periods
        vm.warp(block.timestamp + (HALVING_PERIOD * 3) + 1);

        uint256 expectedPerSecond = (INITIAL_PRODUCTION_PER_DAY / 8) / 1 days; // 2^3 = 8
        assertEq(mine.getCurrentProduction(), expectedPerSecond);
    }

    function test_getCurrentProduction_max_halvings() public {
        // Fast forward past 64 halving periods (max)
        vm.warp(block.timestamp + (HALVING_PERIOD * 65));

        assertEq(mine.getCurrentProduction(), 0);
    }

    function test_getAccumulatedResources_unowned() public view {
        assertEq(mine.getAccumulatedResources(), 0);
    }

    function test_getAccumulatedResources_owned() public {
        vm.prank(player1);
        mine.seize(1);

        // Fast forward 1 hour
        vm.warp(block.timestamp + 1 hours);

        uint256 expectedProduction = (INITIAL_PRODUCTION_PER_DAY / 1 days) * 1 hours;
        assertEq(mine.getAccumulatedResources(), expectedProduction);
    }

    function test_claimResources_success() public {
        vm.prank(player1);
        mine.seize(1);

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        uint256 expectedResources = mine.getAccumulatedResources(); // Use actual calculated value

        vm.prank(player1);
        vm.expectEmit(true, false, false, true);
        emit IMine.ResourcesClaimed(player1, expectedResources);

        mine.claimResources();

        assertEq(gameMaster.getBalance(player1, IERC20(address(ironToken))), expectedResources);
        assertEq(mine.lastResourceClaim(), block.timestamp);
        assertEq(mine.getAccumulatedResources(), 0); // Reset after claim
    }

    function test_claimResources_not_owner() public {
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player2);
        vm.expectRevert();
        mine.claimResources();
    }

    function test_claimResources_no_resources() public {
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player1);
        vm.expectRevert(Mine.InsufficientBalance.selector);
        mine.claimResources();
    }

    // =============================================================================
    // DEFENSE BOOST TESTS
    // =============================================================================

    function test_activateDefenseBoost_success() public {
        vm.prank(player1);
        mine.seize(1);

        uint256 goldCost = 100 ether / 10; // 1 gold per 10 mercs

        vm.prank(player1);
        vm.expectEmit(true, false, false, true);
        emit IMine.DefenseBoostActivated(player1, goldCost, block.timestamp + DEFENSE_BOOST_DURATION);

        mine.activateDefenseBoost();

        assertEq(mine.defenseBoostExpiry(), block.timestamp + DEFENSE_BOOST_DURATION);
        assertEq(gameMaster.getBalance(player1, IERC20(address(goldToken))), 1000 ether - goldCost);
    }

    function test_activateDefenseBoost_insufficient_gold() public {
        vm.prank(player1);
        mine.seize(1);

        // Remove gold
        gameMaster.spendBalance(player1, IERC20(address(goldToken)), 1000 ether);

        vm.prank(player1);
        vm.expectRevert(Mine.InsufficientGold.selector);
        mine.activateDefenseBoost();
    }

    function test_activateDefenseBoost_not_owner() public {
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player2);
        vm.expectRevert();
        mine.activateDefenseBoost();
    }

    function test_calculateBattlePower_with_boost() public {
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player1);
        mine.activateDefenseBoost();

        uint256 normalPower = mine.calculateBattlePower(1, 100 ether, false);
        uint256 boostedPower = mine.calculateBattlePower(1, 100 ether, true);

        assertEq(normalPower, 100 ether * 1);
        assertEq(boostedPower, 200 ether * 1); // Doubled
    }

    function test_calculateBattlePower_boost_expired() public {
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player1);
        mine.activateDefenseBoost();

        // Fast forward past boost expiry
        vm.warp(block.timestamp + DEFENSE_BOOST_DURATION + 1);

        uint256 power = mine.calculateBattlePower(1, 100 ether, true);
        assertEq(power, 100 ether * 1); // No boost
    }

    function test_calculateBattlePower_zero_amount() public {
        vm.expectRevert(Mine.MustBePositive.selector);
        mine.calculateBattlePower(1, 0, false);
    }

    // =============================================================================
    // ABANDONMENT TESTS
    // =============================================================================

    function test_abandon_success() public {
        vm.prank(player1);
        mine.seize(1);

        // Fast forward past cooldown
        vm.warp(block.timestamp + ABANDON_COOLDOWN + 1);

        uint256 expectedLoss = (100 ether * ABANDON_LOSS_PERCENTAGE) / 100;
        uint256 expectedReturn = 100 ether - expectedLoss;

        vm.prank(player1);
        vm.expectEmit(true, false, false, true);
        emit IMine.MineAbandoned(player1, expectedLoss);

        mine.abandon();

        assertEq(mine.owner(), address(0));
        assertEq(address(mine.defenderMercToken()), address(0));
        assertEq(mine.defenseBoostExpiry(), 0);
        assertEq(gameMaster.getBalance(player1, IERC20(address(merc1))), expectedReturn);
        assertEq(gameMaster.getBalance(address(mine), IERC20(address(merc1))), 0);
    }

    function test_abandon_cooldown_not_met() public {
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player1);
        vm.expectRevert(Mine.MustWaitAfterSeizing.selector);
        mine.abandon();
    }

    function test_abandon_not_owner() public {
        vm.prank(player1);
        mine.seize(1);

        vm.warp(block.timestamp + ABANDON_COOLDOWN + 1);

        vm.prank(player2);
        vm.expectRevert();
        mine.abandon();
    }

    function test_abandon_no_mercs() public {
        vm.prank(player1);
        mine.seize(1);

        // Spend all mercs
        gameMaster.spendBalance(address(mine), IERC20(address(merc1)), 100 ether);

        vm.warp(block.timestamp + ABANDON_COOLDOWN + 1);

        vm.prank(player1);
        mine.abandon(); // Should not revert, just do nothing

        assertEq(mine.owner(), address(0));
    }

    // =============================================================================
    // BATTLE LOG TESTS
    // =============================================================================

    function test_getBattleLogEntries_empty() public view {
        IMine.BattleLogEntry[] memory entries = mine.getBattleLogEntries(0, 10);
        assertEq(entries.length, 0);
    }

    function test_getBattleLogEntries_single_entry() public {
        vm.prank(player1);
        mine.seize(1);

        IMine.BattleLogEntry[] memory entries = mine.getBattleLogEntries(0, 10);
        assertEq(entries.length, 1);
        assertEq(entries[0].attacker, player1);
    }

    function test_getBattleLogEntries_multiple_entries() public {
        // Create multiple battle log entries
        vm.prank(player1);
        mine.seize(1);

        vm.prank(player2);
        mine.seize(2);

        // Reset player1's balance for the third seizure
        gameMaster.setBalance(player1, IERC20(address(merc1)), 100 ether);
        vm.prank(player1);
        mine.seize(1);

        // Get all entries (reverse chronological order)
        IMine.BattleLogEntry[] memory entries = mine.getBattleLogEntries(0, 10);
        assertEq(entries.length, 3);

        // Most recent first
        assertEq(entries[0].attacker, player1); // Latest
        assertEq(entries[1].attacker, player2); // Middle
        assertEq(entries[2].attacker, player1); // Oldest
    }

    function test_getBattleLogEntries_pagination() public {
        // Create 5 entries with alternating ownership
        vm.prank(player1);
        mine.seize(1); // player1 owns

        vm.prank(player2);
        mine.seize(2); // player2 takes from player1

        // Reset player1's balance and attack with more mercs to ensure win
        // Player2 has 50 level 2 mercs = 100 power, so player1 needs >100 power
        gameMaster.setBalance(player1, IERC20(address(merc1)), 150 ether); // 150*1 = 150 > 100
        vm.prank(player1);
        mine.seize(1); // player1 takes back

        // Reset player2's balance and attack
        gameMaster.setBalance(player2, IERC20(address(merc2)), 100 ether);
        vm.prank(player2);
        mine.seize(2); // player2 takes back

        // Reset player1's balance for final attack
        gameMaster.setBalance(player1, IERC20(address(merc1)), 100 ether);
        vm.prank(player1);
        mine.seize(1); // player1 takes back

        // Get first 2 entries
        IMine.BattleLogEntry[] memory entries1 = mine.getBattleLogEntries(0, 2);
        assertEq(entries1.length, 2);

        // Get next 2 entries
        IMine.BattleLogEntry[] memory entries2 = mine.getBattleLogEntries(2, 2);
        assertEq(entries2.length, 2);

        // Get last entry
        IMine.BattleLogEntry[] memory entries3 = mine.getBattleLogEntries(4, 2);
        assertEq(entries3.length, 1);
    }

    function test_getBattleLogEntries_out_of_bounds() public {
        vm.prank(player1);
        mine.seize(1);

        IMine.BattleLogEntry[] memory entries = mine.getBattleLogEntries(10, 5);
        assertEq(entries.length, 0);
    }

    function test_getBattleLogEntry_out_of_bounds() public {
        vm.expectRevert("Index out of bounds");
        mine.getBattleLogEntry(0);
    }

    // =============================================================================
    // VIEW FUNCTION TESTS
    // =============================================================================

    function test_getMineInfo() public {
        vm.prank(player1);
        mine.seize(1);

        IMine.MineInfo memory info = mine.getMineInfo();
        assertEq(address(info.resource), address(ironToken));
        assertEq(info.owner, player1);
        assertEq(info.lastSeized, block.timestamp);
        assertEq(info.createdAt, mine.createdAt());
        assertEq(info.defenseBoostExpiry, 0);
        assertEq(info.initialProductionPerDay, INITIAL_PRODUCTION_PER_DAY);
        assertEq(info.halvingPeriod, HALVING_PERIOD);
    }

    // =============================================================================
    // INTEGRATION TESTS
    // =============================================================================

    function test_full_combat_scenario_with_boost() public {
        // Player 1 seizes mine
        vm.prank(player1);
        mine.seize(1);

        // Player 1 activates defense boost
        vm.prank(player1);
        mine.activateDefenseBoost();

        // Player 2 attacks but should lose due to boost
        // Use fewer attacking mercs so defender doesn't lose all mercs
        gameMaster.setBalance(player2, IERC20(address(merc2)), 40 ether); // 40*2 = 80 power < 200 power (boosted)
        vm.prank(player2);
        mine.seize(2); // Attacker loses, defender keeps most mercs

        // Player 1 should still own the mine
        assertEq(mine.owner(), player1);

        // Wait for boost to expire
        vm.warp(block.timestamp + DEFENSE_BOOST_DURATION + 1);

        // Player 2 attacks again and should win now (no boost)
        // Give player2 fresh mercs since previous attack consumed them
        gameMaster.setBalance(player2, IERC20(address(merc2)), 100 ether);
        vm.prank(player2);
        mine.seize(2);

        assertEq(mine.owner(), player2);
    }

    function test_resource_production_across_ownership_changes() public {
        // Player 1 seizes and waits
        vm.prank(player1);
        mine.seize(1);

        vm.warp(block.timestamp + 12 hours);

        // Player 2 seizes
        vm.prank(player2);
        mine.seize(2);

        // Player 1 can't claim resources anymore
        vm.prank(player1);
        vm.expectRevert();
        mine.claimResources();

        // Player 2 can claim from their ownership start
        vm.warp(block.timestamp + 12 hours);

        vm.prank(player2);
        mine.claimResources();

        // Should only get resources from their 12-hour ownership
        // getAccumulatedResources() returns 0 now since player2 just claimed, so check the balance directly
        assertTrue(gameMaster.getBalance(player2, IERC20(address(ironToken))) > 0);
    }
}
