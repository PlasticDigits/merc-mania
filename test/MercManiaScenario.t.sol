// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/GameMaster.sol";
import "../src/MercRecruiter.sol";
import "../src/Mine.sol";
import "../src/MineFactory.sol";
import "../src/MercAssetFactory.sol";
import "../src/GameAssetFactory.sol";
import "../src/ResourceManager.sol";
import "../src/interfaces/IMine.sol";
import "../src/interfaces/IResourceManager.sol";
import "../src/interfaces/IGameMaster.sol";
import "../src/interfaces/IERC20MintableBurnable.sol";
import "../src/interfaces/IGuardERC20.sol";
import "../src/PlayerStats.sol";
import "../src/GameStats.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockGuard
 * @dev Mock implementation of IGuardERC20 for testing
 */
contract MockGuard is IGuardERC20 {
    function check(address, address, uint256) external pure {
        // No restrictions for testing
    }
}

/**
 * @title MercManiaScenario
 * @notice A comprehensive 30-day simulation test of the Merc Mania game featuring:
 *         - 4 competing players (Atlas Corp, Yamato Industries, Crimson Phoenix, Independent Mercs)
 *         - AI-controlled mine and resource deployment
 *         - Complex player interactions including mine seizures, abandonment, and mercenary recruitment
 *         - Realistic time progression over 30 days
 * @dev This test validates the complete game ecosystem under realistic competitive conditions
 */
contract MercManiaScenario is Test {
    // ==================== STATE VARIABLES ====================

    // Core game contracts
    AccessManager public accessManager;
    GameMaster public gameMaster;
    ResourceManager public resourceManager;
    MercRecruiter public mercRecruiter;
    MineFactory public mineFactory;
    MercAssetFactory public mercAssetFactory;
    GameAssetFactory public gameAssetFactory;
    PlayerStats public playerStats;
    GameStats public gameStats;
    MockGuard public guard;

    // Player addresses
    address public atlasCorp = makeAddr("AtlasCorp");
    address public yamatoIndustries = makeAddr("YamatoIndustries");
    address public crimsonPhoenix = makeAddr("CrimsonPhoenix");
    address public independentMercs = makeAddr("IndependentMercs");
    address public aiController = makeAddr("AIController");

    // Resource tokens
    IERC20 public goldToken;
    IERC20 public ironToken;
    IERC20 public copperToken;
    IERC20 public tantalumToken;
    IERC20 public lithiumToken;
    IERC20 public uraniumToken;

    // Mercenary tokens (Level 1-6)
    IERC20 public mercsLevel1;
    IERC20 public mercsLevel2;
    IERC20 public mercsLevel3;
    IERC20 public mercsLevel4;
    IERC20 public mercsLevel5;
    IERC20 public mercsLevel6;

    uint256 public constant INITIAL_PRODUCTION_PER_DAY = 100 ether;
    uint256 public constant HALVING_PERIOD = 3 days;

    // Game state tracking
    address[] public allMines;
    uint256 public constant SIMULATION_DAYS = 30;
    uint256 public constant DAY_DURATION = 1 days;
    uint256 public startTime;

    // Player strategies and behaviors
    struct PlayerStrategy {
        uint256 aggressionLevel; // 1-10 scale
        uint256 expansionPreference; // 1-10 scale
        uint256 defensiveStance; // 1-10 scale
        uint256 resourceFocus; // Preferred resource type index
    }

    mapping(address => PlayerStrategy) public playerStrategies;
    mapping(address => string) public playerNames;

    // Events for logging scenario progress
    event DayProgressed(uint256 day, uint256 timestamp);
    event AIAction(string actionType, address target, uint256 amount);
    event PlayerAction(address player, string actionType, address target, uint256 amount);
    event BattleOccurred(address attacker, address defender, address mine, bool attackerWon);
    event ScenarioComplete(uint256 totalDays, address[] topPlayers);

    // ==================== SETUP ====================

    function setUp() public {
        // Initialize timestamp
        startTime = block.timestamp;
        vm.warp(startTime);

        // Deploy access management
        accessManager = new AccessManager(address(this));

        // Grant game role to test contract
        accessManager.grantRole(2, address(this), 0); // GAME_ROLE

        // Deploy guard
        guard = new MockGuard();

        // Deploy core game contracts in correct dependency order
        // Deploy stats contracts
        playerStats = new PlayerStats(address(accessManager));
        gameStats = new GameStats(address(accessManager));

        gameMaster = new GameMaster(address(accessManager), playerStats, gameStats);
        gameAssetFactory = new GameAssetFactory(address(accessManager), guard, gameMaster);

        // Set up initial access control permissions BEFORE creating ResourceManager
        setupInitialAccessControl();

        // Temporarily make createAsset function available to all for ResourceManager construction
        bytes4[] memory createAssetSelectors = new bytes4[](1);
        createAssetSelectors[0] = bytes4(keccak256("createAsset(string,string,string)"));
        accessManager.setTargetFunctionRole(
            address(gameAssetFactory), createAssetSelectors, accessManager.PUBLIC_ROLE()
        );

        // Now create ResourceManager
        resourceManager = new ResourceManager(address(accessManager), gameAssetFactory);

        // Set up permissions for ResourceManager methods BEFORE using them
        bytes4[] memory initGoldSelectors = new bytes4[](1);
        initGoldSelectors[0] = bytes4(keccak256("initializeGold(string)"));
        accessManager.setTargetFunctionRole(address(resourceManager), initGoldSelectors, accessManager.ADMIN_ROLE());

        // Grant ResourceManager permission to create assets (needed for initializeGold)
        accessManager.grantRole(accessManager.ADMIN_ROLE(), address(resourceManager), 0);

        // Grant GameAssetFactory ADMIN_ROLE to set up access control for new assets
        accessManager.grantRole(accessManager.ADMIN_ROLE(), address(gameAssetFactory), 0);

        // Restore access control for createAsset
        accessManager.setTargetFunctionRole(address(gameAssetFactory), createAssetSelectors, accessManager.ADMIN_ROLE());
        mercAssetFactory = new MercAssetFactory(address(accessManager), guard);
        mercRecruiter = new MercRecruiter(
            address(accessManager), resourceManager, gameMaster, mercAssetFactory, playerStats, gameStats
        );
        mineFactory = new MineFactory(
            address(accessManager), resourceManager, gameMaster, mercAssetFactory, playerStats, gameStats
        );

        // Set up remaining access control permissions
        setupRemainingAccessControl();

        // Create game resources
        createGameResources();

        // Create mercenary tokens
        createMercenaryTokens();

        // Initialize player strategies
        initializePlayerStrategies();

        // Initial resource distribution
        distributeInitialResources();

        console.log("=== MERC MANIA 30-DAY SCENARIO BEGINS ===");
        console.log(string.concat("Starting simulation at timestamp: ", vm.toString(block.timestamp)));
    }

    function setupInitialAccessControl() internal {
        // Grant access to asset creation for ResourceManager constructor
        bytes4[] memory createAssetSelectors = new bytes4[](1);
        createAssetSelectors[0] = bytes4(keccak256("createAsset(string,string,string)"));
        accessManager.setTargetFunctionRole(address(gameAssetFactory), createAssetSelectors, accessManager.ADMIN_ROLE());

        // Grant access to merc creation
        bytes4[] memory createMercSelectors = new bytes4[](1);
        createMercSelectors[0] = bytes4(keccak256("createMerc(string,string,string)"));
        accessManager.setTargetFunctionRole(address(mercAssetFactory), createMercSelectors, accessManager.ADMIN_ROLE());
    }

    function setupRemainingAccessControl() internal {
        // Set up game roles
        uint64 GAME_ROLE = 2;
        uint64 MINTER_ROLE = 1;

        // Grant permissions to game contracts
        accessManager.grantRole(GAME_ROLE, address(mercRecruiter), 0);
        accessManager.grantRole(GAME_ROLE, address(mineFactory), 0);
        accessManager.grantRole(GAME_ROLE, address(aiController), 0);

        // Grant MineFactory ADMIN permissions to set up access control for new mines
        accessManager.grantRole(accessManager.ADMIN_ROLE(), address(mineFactory), 0);
        accessManager.grantRole(MINTER_ROLE, address(gameAssetFactory), 0);
        accessManager.grantRole(MINTER_ROLE, address(mercAssetFactory), 0);
        // Grant test contract permission to mint tokens for initial distribution
        accessManager.grantRole(MINTER_ROLE, address(this), 0);

        // Grant access to resource creation
        bytes4[] memory createResourceSelectors = new bytes4[](1);
        createResourceSelectors[0] = bytes4(keccak256("addResource(string,string,string)"));
        accessManager.setTargetFunctionRole(
            address(resourceManager), createResourceSelectors, accessManager.ADMIN_ROLE()
        );

        // Grant access to mine creation - fix function signature
        bytes4[] memory createMineSelectors = new bytes4[](1);
        createMineSelectors[0] = bytes4(keccak256("createMine(address,uint256,uint256)"));
        accessManager.setTargetFunctionRole(address(mineFactory), createMineSelectors, GAME_ROLE);

        // Set up mint function permissions for all created tokens (will be applied when tokens are created)
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = bytes4(keccak256("mint(address,uint256)"));
        // Note: This will need to be applied to each token after creation
    }

    function setupTokenMintPermissions() internal {
        // Set up mint function permissions for all tokens
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = bytes4(keccak256("mint(address,uint256)"));

        uint64 MINTER_ROLE = 1;

        // Set mint permissions for resource tokens
        address[] memory tokenAddresses = new address[](6);
        tokenAddresses[0] = address(goldToken);
        tokenAddresses[1] = address(ironToken);
        tokenAddresses[2] = address(copperToken);
        tokenAddresses[3] = address(tantalumToken);
        tokenAddresses[4] = address(lithiumToken);
        tokenAddresses[5] = address(uraniumToken);

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (tokenAddresses[i] != address(0)) {
                accessManager.setTargetFunctionRole(tokenAddresses[i], mintSelectors, MINTER_ROLE);
            }
        }
    }

    function setupMercenaryTokenMintPermissions() internal {
        // Set up mint function permissions for mercenary tokens
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = bytes4(keccak256("mint(address,uint256)"));

        uint64 MINTER_ROLE = 1;

        // Set mint permissions for mercenary tokens
        address[] memory mercTokenAddresses = new address[](6);
        mercTokenAddresses[0] = address(mercsLevel1);
        mercTokenAddresses[1] = address(mercsLevel2);
        mercTokenAddresses[2] = address(mercsLevel3);
        mercTokenAddresses[3] = address(mercsLevel4);
        mercTokenAddresses[4] = address(mercsLevel5);
        mercTokenAddresses[5] = address(mercsLevel6);

        for (uint256 i = 0; i < mercTokenAddresses.length; i++) {
            if (mercTokenAddresses[i] != address(0)) {
                accessManager.setTargetFunctionRole(mercTokenAddresses[i], mintSelectors, MINTER_ROLE);
            }
        }
    }

    function createGameResources() internal {
        // Initialize Gold through ResourceManager
        resourceManager.initializeGold("The primary currency of mercenary operations");
        goldToken = resourceManager.GOLD();

        // Create other resources through ResourceManager
        ironToken = IERC20(resourceManager.addResource("Iron", "IRON", "Essential for weapon manufacturing"));
        copperToken = IERC20(resourceManager.addResource("Copper", "COPPER", "Crucial for electronics and wiring"));
        tantalumToken =
            IERC20(resourceManager.addResource("Tantalum", "TANT", "Rare earth element for advanced technology"));
        lithiumToken = IERC20(resourceManager.addResource("Lithium", "LITH", "Power source for modern equipment"));
        uraniumToken = IERC20(resourceManager.addResource("Uranium", "URAN", "Strategic nuclear material"));

        // Set up mint permissions for all resource tokens
        setupTokenMintPermissions();

        console.log("Created 6 game resources");
    }

    function createMercenaryTokens() internal {
        mercsLevel1 = IERC20(mercAssetFactory.createMerc("Basic Mercenaries", "MERC1", ""));
        mercsLevel2 = IERC20(mercAssetFactory.createMerc("Trained Mercenaries", "MERC2", ""));
        mercsLevel3 = IERC20(mercAssetFactory.createMerc("Veteran Mercenaries", "MERC3", ""));
        mercsLevel4 = IERC20(mercAssetFactory.createMerc("Elite Mercenaries", "MERC4", ""));
        mercsLevel5 = IERC20(mercAssetFactory.createMerc("Special Forces", "MERC5", ""));
        mercsLevel6 = IERC20(mercAssetFactory.createMerc("Legendary Operatives", "MERC6", ""));

        // Set up mint permissions for mercenary tokens
        setupMercenaryTokenMintPermissions();

        console.log("Created 6 mercenary levels");
    }

    function initializePlayerStrategies() internal {
        // Atlas Corp - Aggressive expansionist
        playerStrategies[atlasCorp] = PlayerStrategy({
            aggressionLevel: 8,
            expansionPreference: 9,
            defensiveStance: 4,
            resourceFocus: 0 // Gold focus
        });
        playerNames[atlasCorp] = "Atlas-Helix Consortium";

        // Yamato Industries - Balanced technological approach
        playerStrategies[yamatoIndustries] = PlayerStrategy({
            aggressionLevel: 6,
            expansionPreference: 7,
            defensiveStance: 7,
            resourceFocus: 3 // Tantalum focus
        });
        playerNames[yamatoIndustries] = "Yamato-Nordstrom Alliance";

        // Crimson Phoenix - Defensive resource hoarder
        playerStrategies[crimsonPhoenix] = PlayerStrategy({
            aggressionLevel: 5,
            expansionPreference: 5,
            defensiveStance: 9,
            resourceFocus: 5 // Uranium focus
        });
        playerNames[crimsonPhoenix] = "Crimson Phoenix Federation";

        // Independent Mercs - Opportunistic raiders
        playerStrategies[independentMercs] = PlayerStrategy({
            aggressionLevel: 10,
            expansionPreference: 3,
            defensiveStance: 2,
            resourceFocus: 1 // Iron focus
        });
        playerNames[independentMercs] = "Independent Contractors Alliance";

        console.log("Initialized player strategies for 4 factions");
    }

    function distributeInitialResources() internal {
        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        IERC20[] memory resources = new IERC20[](6);
        resources[0] = goldToken;
        resources[1] = ironToken;
        resources[2] = copperToken;
        resources[3] = tantalumToken;
        resources[4] = lithiumToken;
        resources[5] = uraniumToken;

        // Give each player starting resources
        for (uint256 i = 0; i < players.length; i++) {
            for (uint256 j = 0; j < resources.length; j++) {
                uint256 amount = 1000e18 + (i * 100e18) + (j * 50e18); // Varied starting amounts

                // Mint to GameMaster and add to player balance
                IERC20MintableBurnable(address(resources[j])).mint(address(gameMaster), amount);
                gameMaster.addBalance(players[i], resources[j], amount);
            }

            console.log(string.concat("Distributed initial resources to: ", playerNames[players[i]]));
        }
    }

    // ==================== CORE SCENARIO TEST ====================

    /**
     * @notice Main scenario test simulating 30 days of competitive gameplay
     */
    function test_30DayMercManiaScenario() public {
        console.log("\n=== BEGINNING 30-DAY SIMULATION ===");

        // Day 0: Initial setup and first moves
        executeDay0();

        // Days 1-29: Main simulation loop
        for (uint256 day = 1; day <= SIMULATION_DAYS; day++) {
            advanceToDay(day);
            executeDailyActions(day);
            logDayStatus(day);
        }

        // Final analysis
        concludeScenario();

        // Verify scenario completed successfully
        assertTrue(allMines.length > 0, "No mines were created during scenario");
        assertTrue(block.timestamp >= startTime + (SIMULATION_DAYS * DAY_DURATION), "Scenario duration incorrect");

        console.log("\n=== SCENARIO COMPLETED SUCCESSFULLY ===");
    }

    function executeDay0() internal {
        console.log("\n--- DAY 0: THE SCRAMBLE BEGINS ---");

        // AI creates initial mines
        aiCreateInitialMines();

        // Players recruit initial mercenaries
        playersRecruitInitialMercenaries();

        // First territorial claims
        playersAttemptInitialClaims();

        emit DayProgressed(0, block.timestamp);
    }

    function advanceToDay(uint256 day) internal {
        uint256 targetTime = startTime + (day * DAY_DURATION);
        vm.warp(targetTime);
        emit DayProgressed(day, block.timestamp);
    }

    function executeDailyActions(uint256 day) internal {
        console.log(string.concat("\n--- DAY ", vm.toString(day), " ---"));

        // AI actions (new mines, resource adjustments)
        executeAIActions(day);

        // Player actions based on strategies
        executePlayerActions(day);

        // Random events and market forces
        executeRandomEvents(day);
    }

    // ==================== AI BEHAVIOR ====================

    function aiCreateInitialMines() internal {
        console.log("AI Controller deploying initial mining infrastructure...");

        IERC20[] memory resources = new IERC20[](6);
        resources[0] = goldToken;
        resources[1] = ironToken;
        resources[2] = copperToken;
        resources[3] = tantalumToken;
        resources[4] = lithiumToken;
        resources[5] = uraniumToken;

        // Create 2-3 mines per resource type
        for (uint256 i = 0; i < resources.length; i++) {
            uint256 mineCount = 2 + (i % 2); // 2 or 3 mines per resource
            for (uint256 j = 0; j < mineCount; j++) {
                vm.prank(aiController);
                address newMine = mineFactory.createMine(resources[i], INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
                allMines.push(newMine);

                emit AIAction("CreateMine", newMine, i);
            }
        }

        console.log(string.concat("AI created ", vm.toString(allMines.length), " initial mines"));
    }

    function executeAIActions(uint256 day) internal {
        // AI creates new mines periodically
        if (day % 5 == 0 && day <= 20) {
            aiCreateAdditionalMines(day);
        }

        // AI adjusts resource availability
        if (day % 7 == 0) {
            aiAdjustResourceAvailability(day);
        }

        // AI responds to market conditions
        if (day % 10 == 0) {
            aiMarketResponse(day);
        }
    }

    function aiCreateAdditionalMines(uint256 day) internal {
        console.log("AI expanding mining operations...");

        // Create 1-2 new mines
        uint256 newMines = 1 + (day % 2);
        IERC20[] memory resources = new IERC20[](6);
        resources[0] = goldToken;
        resources[1] = ironToken;
        resources[2] = copperToken;
        resources[3] = tantalumToken;
        resources[4] = lithiumToken;
        resources[5] = uraniumToken;

        for (uint256 i = 0; i < newMines; i++) {
            uint256 resourceIndex = (day + i) % 6;
            vm.prank(aiController);
            address newMine =
                mineFactory.createMine(resources[resourceIndex], INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
            allMines.push(newMine);

            emit AIAction("CreateMine", newMine, resourceIndex);
        }

        console.log(string.concat("AI created ", vm.toString(newMines), " additional mines on day ", vm.toString(day)));
    }

    function aiAdjustResourceAvailability(uint256 day) internal {
        console.log("AI adjusting resource market conditions...");

        // Simulate market fluctuations by distributing bonus resources
        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        // Random resource bonus
        uint256 bonusResourceIndex = day % 6;
        IERC20 bonusResource = getBonusResource(bonusResourceIndex);
        uint256 bonusAmount = 200e18 + (day * 10e18);

        for (uint256 i = 0; i < players.length; i++) {
            IERC20MintableBurnable(address(bonusResource)).mint(address(gameMaster), bonusAmount);
            gameMaster.addBalance(players[i], bonusResource, bonusAmount);
        }

        emit AIAction("ResourceBonus", address(bonusResource), bonusAmount);
    }

    function getBonusResource(uint256 index) internal view returns (IERC20) {
        if (index == 0) return goldToken;
        if (index == 1) return ironToken;
        if (index == 2) return copperToken;
        if (index == 3) return tantalumToken;
        if (index == 4) return lithiumToken;
        return uraniumToken;
    }

    function aiMarketResponse(uint256 day) internal {
        console.log("AI implementing market response protocols...");

        // AI could implement more sophisticated market responses here
        // For now, just log the event
        emit AIAction("MarketResponse", address(0), day);
    }

    // ==================== PLAYER BEHAVIOR ====================

    function playersRecruitInitialMercenaries() internal {
        console.log("Corporate factions recruiting initial mercenary forces...");

        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        for (uint256 i = 0; i < players.length; i++) {
            playerRecruitMercenaries(players[i], 1, 100); // Start with level 1 mercs
            console.log(string.concat(playerNames[players[i]], " recruited initial mercenaries"));
        }
    }

    function playersAttemptInitialClaims() internal {
        console.log("Factions moving to secure initial territorial claims...");

        // Each player attempts to claim 1-2 mines
        if (allMines.length >= 4) {
            playerAttemptSeizure(atlasCorp, allMines[0], 1);
            playerAttemptSeizure(yamatoIndustries, allMines[1], 1);
            playerAttemptSeizure(crimsonPhoenix, allMines[2], 1);
            playerAttemptSeizure(independentMercs, allMines[3], 1);
        }
    }

    function executePlayerActions(uint256 day) internal {
        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        for (uint256 i = 0; i < players.length; i++) {
            executePlayerStrategy(players[i], day);
        }
    }

    function executePlayerStrategy(address player, uint256 day) internal {
        PlayerStrategy memory strategy = playerStrategies[player];

        // Claim resources from owned mines
        playerClaimResources(player);

        // Recruitment decisions
        if (day % 3 == 0) {
            uint256 recruitLevel = determineRecruitmentLevel(player, day);
            if (recruitLevel > 0) {
                playerRecruitMercenaries(player, recruitLevel, 50 + (strategy.expansionPreference * 10));
            }
        }

        // Combat decisions
        if (shouldPlayerAttack(player, day)) {
            executePlayerCombat(player, day);
        }

        // Defensive decisions
        if (strategy.defensiveStance > 6 && day % 2 == 0) {
            playerActivateDefenses(player);
        }

        // Strategic abandonment (if low on resources or strategic repositioning)
        if (day > 10 && shouldPlayerAbandon(player, day)) {
            executePlayerAbandonment(player);
        }
    }

    function playerClaimResources(address player) internal {
        // Find mines owned by player and claim resources
        for (uint256 i = 0; i < allMines.length; i++) {
            Mine mine = Mine(allMines[i]);
            IMine.MineInfo memory info = mine.getMineInfo();

            if (info.owner == player) {
                uint256 accumulated = mine.getAccumulatedResources();
                if (accumulated > 0) {
                    vm.prank(player);
                    mine.claimResources();
                    emit PlayerAction(player, "ClaimResources", allMines[i], accumulated);
                }
            }
        }
    }

    function determineRecruitmentLevel(address player, uint256 day) internal view returns (uint256) {
        PlayerStrategy memory strategy = playerStrategies[player];

        // Higher expansion preference leads to higher level recruitment
        uint256 baseLevel = 1 + (strategy.expansionPreference / 3);

        // Increase level as days progress
        uint256 timeBonus = day / 10;

        uint256 finalLevel = baseLevel + timeBonus;
        return finalLevel > 6 ? 6 : finalLevel; // Cap at level 6
    }

    function shouldPlayerAttack(address player, uint256 day) internal view returns (bool) {
        PlayerStrategy memory strategy = playerStrategies[player];

        // More aggressive players attack more frequently
        uint256 attackChance = strategy.aggressionLevel * 10; // 10-100% chance
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(player, day, block.timestamp))) % 100;

        return randomSeed < attackChance;
    }

    function executePlayerCombat(address player, uint256 day) internal {
        // Find enemy mines to attack
        address targetMine = findTargetMine(player, day);
        if (targetMine != address(0)) {
            uint256 mercLevel = getPlayerBestMercLevel(player);
            if (mercLevel > 0) {
                playerAttemptSeizure(player, targetMine, mercLevel);
            }
        }
    }

    function findTargetMine(address player, uint256 /* day */ ) internal view returns (address) {
        PlayerStrategy memory strategy = playerStrategies[player];

        // Find mines owned by other players
        for (uint256 i = 0; i < allMines.length; i++) {
            Mine mine = Mine(allMines[i]);
            IMine.MineInfo memory info = mine.getMineInfo();

            if (info.owner != player && info.owner != address(0)) {
                // Check if this mine produces the preferred resource
                if (strategy.resourceFocus < 6) {
                    IERC20 preferredResource = getResourceByIndex(strategy.resourceFocus);
                    if (info.resource == preferredResource) {
                        return allMines[i];
                    }
                }

                // Otherwise return first enemy mine found
                return allMines[i];
            }
        }

        return address(0);
    }

    function getResourceByIndex(uint256 index) internal view returns (IERC20) {
        if (index == 0) return goldToken;
        if (index == 1) return ironToken;
        if (index == 2) return copperToken;
        if (index == 3) return tantalumToken;
        if (index == 4) return lithiumToken;
        return uraniumToken;
    }

    function getPlayerBestMercLevel(address player) internal view returns (uint256) {
        IERC20[] memory mercTokens = new IERC20[](6);
        mercTokens[0] = mercsLevel1;
        mercTokens[1] = mercsLevel2;
        mercTokens[2] = mercsLevel3;
        mercTokens[3] = mercsLevel4;
        mercTokens[4] = mercsLevel5;
        mercTokens[5] = mercsLevel6;

        // Find highest level with sufficient balance
        for (uint256 i = 5; i > 0; i--) {
            uint256 balance = gameMaster.getBalance(player, mercTokens[i]);
            if (balance >= 25e18) {
                // Minimum required for seizure
                return i + 1;
            }
        }

        return 1; // Default to level 1
    }

    function playerActivateDefenses(address player) internal {
        // Find mines owned by player and activate defenses
        for (uint256 i = 0; i < allMines.length; i++) {
            Mine mine = Mine(allMines[i]);
            IMine.MineInfo memory info = mine.getMineInfo();

            if (info.owner == player && info.defenseBoostExpiry <= block.timestamp) {
                // Check if player has enough gold
                uint256 goldBalance = gameMaster.getBalance(player, goldToken);
                if (goldBalance >= 500e18) {
                    // Assuming defense boost costs 500 gold
                    vm.prank(player);
                    try mine.activateDefenseBoost() {
                        emit PlayerAction(player, "ActivateDefense", allMines[i], 500e18);
                    } catch {
                        // Defense activation failed, continue
                    }
                }
            }
        }
    }

    function shouldPlayerAbandon(address player, uint256 day) internal view returns (bool) {
        PlayerStrategy memory strategy = playerStrategies[player];

        // Defensive players rarely abandon, aggressive players abandon more readily
        uint256 abandonChance = (10 - strategy.defensiveStance) * 2; // 0-18% chance
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(player, day, "abandon"))) % 100;

        return randomSeed < abandonChance;
    }

    function executePlayerAbandonment(address player) internal {
        // Find a mine to potentially abandon (lowest production or most vulnerable)
        for (uint256 i = 0; i < allMines.length; i++) {
            Mine mine = Mine(allMines[i]);
            IMine.MineInfo memory info = mine.getMineInfo();

            if (info.owner == player) {
                uint256 production = mine.getCurrentProduction();
                if (production < 10e18) {
                    // Abandon if production is very low
                    vm.prank(player);
                    try mine.abandon() {
                        emit PlayerAction(player, "AbandonMine", allMines[i], 0);
                        break; // Only abandon one mine per turn
                    } catch {
                        // Abandonment failed, continue
                    }
                }
            }
        }
    }

    function playerRecruitMercenaries(address player, uint256 level, uint256 amount) internal {
        IERC20[] memory resources = new IERC20[](level);
        resources[0] = goldToken; // Always include gold

        if (level > 1) resources[1] = ironToken;
        if (level > 2) resources[2] = copperToken;
        if (level > 3) resources[3] = tantalumToken;
        if (level > 4) resources[4] = lithiumToken;
        if (level > 5) resources[5] = uraniumToken;

        // Check if player has sufficient resources
        bool canRecruit = true;
        for (uint256 i = 0; i < resources.length; i++) {
            if (gameMaster.getBalance(player, resources[i]) < amount) {
                canRecruit = false;
                break;
            }
        }

        if (canRecruit) {
            vm.prank(player);
            try mercRecruiter.recruitMercs(resources, amount) {
                emit PlayerAction(player, "RecruitMercs", address(0), amount);
                console.log(
                    string.concat(
                        playerNames[player],
                        " recruited ",
                        vm.toString(amount),
                        " level ",
                        vm.toString(level),
                        " mercenaries"
                    )
                );
            } catch {
                // Recruitment failed
            }
        }
    }

    function playerAttemptSeizure(address player, address mineAddress, uint256 mercLevel) internal {
        Mine mine = Mine(mineAddress);
        IMine.MineInfo memory info = mine.getMineInfo();

        // Check if player has enough mercenaries
        IERC20 mercToken = getMercTokenByLevel(mercLevel);
        uint256 mercBalance = gameMaster.getBalance(player, mercToken);

        if (mercBalance >= 25e18 && info.owner != player) {
            vm.prank(player);
            try mine.seize(mercLevel) {
                IMine.MineInfo memory newInfo = mine.getMineInfo();
                bool success = newInfo.owner == player;
                emit BattleOccurred(player, info.owner, mineAddress, success);

                if (success) {
                    console.log(
                        string.concat(
                            playerNames[player],
                            " successfully seized mine from ",
                            info.owner == address(0) ? "neutral" : playerNames[info.owner]
                        )
                    );
                } else {
                    console.log(
                        string.concat(playerNames[player], " failed to seize mine from ", playerNames[info.owner])
                    );
                }
            } catch {
                console.log(string.concat(playerNames[player], " seizure attempt failed due to contract error"));
            }
        }
    }

    function getMercTokenByLevel(uint256 level) internal view returns (IERC20) {
        if (level == 1) return mercsLevel1;
        if (level == 2) return mercsLevel2;
        if (level == 3) return mercsLevel3;
        if (level == 4) return mercsLevel4;
        if (level == 5) return mercsLevel5;
        return mercsLevel6;
    }

    // ==================== RANDOM EVENTS ====================

    function executeRandomEvents(uint256 day) internal {
        // Simulate random events that affect the game world
        uint256 eventSeed = uint256(keccak256(abi.encodePacked(day, block.timestamp, "events"))) % 100;

        if (eventSeed < 10) {
            // Resource shortage event (10% chance)
            executeResourceShortage(day);
        } else if (eventSeed < 20) {
            // Mercenary uprising event (10% chance)
            executeMercenaryUprising(day);
        } else if (eventSeed < 25) {
            // Technology breakthrough (5% chance)
            executeTechnologyBreakthrough(day);
        }
    }

    function executeResourceShortage(uint256 day) internal {
        console.log("RANDOM EVENT: Resource shortage affects the region!");

        // Reduce resource availability temporarily
        // This could be implemented as reduced mine production or increased costs
        emit AIAction("ResourceShortage", address(0), day);
    }

    function executeMercenaryUprising(uint256 day) internal {
        console.log("RANDOM EVENT: Mercenary uprising disrupts operations!");

        // Cause some players to lose mercenaries
        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        for (uint256 i = 0; i < players.length; i++) {
            uint256 losses = 10e18; // Small mercenary losses
            uint256 balance = gameMaster.getBalance(players[i], mercsLevel1);
            if (balance >= losses) {
                gameMaster.spendBalance(players[i], mercsLevel1, losses);
            }
        }

        emit AIAction("MercenaryUprising", address(0), day);
    }

    function executeTechnologyBreakthrough(uint256 /* day */ ) internal {
        console.log("RANDOM EVENT: Technology breakthrough enhances operations!");

        // Bonus resources for all players
        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        uint256 bonusAmount = 500e18;
        for (uint256 i = 0; i < players.length; i++) {
            IERC20MintableBurnable(address(goldToken)).mint(address(gameMaster), bonusAmount);
            gameMaster.addBalance(players[i], goldToken, bonusAmount);
        }

        emit AIAction("TechnologyBreakthrough", address(goldToken), bonusAmount);
    }

    // ==================== LOGGING AND ANALYSIS ====================

    function logDayStatus(uint256 day) internal view {
        if (day % 5 == 0) {
            console.log(string.concat("=== DAY ", vm.toString(day), " STATUS REPORT ==="));
            logPlayerStatus();
            logMineStatus();
        }
    }

    function logPlayerStatus() internal view {
        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        console.log("Player Status:");
        for (uint256 i = 0; i < players.length; i++) {
            uint256 goldBalance = gameMaster.getBalance(players[i], goldToken);
            uint256 minesOwned = countMinesOwnedBy(players[i]);
            console.log(
                string.concat(
                    playerNames[players[i]],
                    " - Gold: ",
                    vm.toString(goldBalance / 1e18),
                    " - Mines: ",
                    vm.toString(minesOwned)
                )
            );
        }
    }

    function logMineStatus() internal view {
        uint256 activeMines = 0;
        uint256 neutralMines = 0;

        for (uint256 i = 0; i < allMines.length; i++) {
            Mine mine = Mine(allMines[i]);
            IMine.MineInfo memory info = mine.getMineInfo();

            if (info.owner != address(0)) {
                activeMines++;
            } else {
                neutralMines++;
            }
        }

        console.log(
            string.concat(
                "Mine Status - Total: ",
                vm.toString(allMines.length),
                " Active: ",
                vm.toString(activeMines),
                " Neutral: ",
                vm.toString(neutralMines)
            )
        );
    }

    function countMinesOwnedBy(address player) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < allMines.length; i++) {
            Mine mine = Mine(allMines[i]);
            IMine.MineInfo memory info = mine.getMineInfo();

            if (info.owner == player) {
                count++;
            }
        }
        return count;
    }

    function concludeScenario() internal {
        console.log("\n=== SCENARIO CONCLUSION ===");

        // Determine final rankings
        address[] memory players = new address[](4);
        players[0] = atlasCorp;
        players[1] = yamatoIndustries;
        players[2] = crimsonPhoenix;
        players[3] = independentMercs;

        // Calculate scores (gold balance + mines owned * 1000)
        uint256[] memory scores = new uint256[](4);
        for (uint256 i = 0; i < players.length; i++) {
            uint256 goldBalance = gameMaster.getBalance(players[i], goldToken);
            uint256 minesOwned = countMinesOwnedBy(players[i]);
            scores[i] = goldBalance + (minesOwned * 1000e18);
        }

        // Find winner
        uint256 maxScore = 0;
        address winner = address(0);
        for (uint256 i = 0; i < players.length; i++) {
            if (scores[i] > maxScore) {
                maxScore = scores[i];
                winner = players[i];
            }
        }

        console.log(string.concat("SCENARIO WINNER: ", playerNames[winner]));
        console.log(string.concat("Final Score: ", vm.toString(maxScore / 1e18)));

        // Log final statistics
        console.log(string.concat("Total mines created: ", vm.toString(allMines.length)));
        console.log(string.concat("Simulation completed over ", vm.toString(SIMULATION_DAYS), " days"));

        emit ScenarioComplete(SIMULATION_DAYS, players);
    }
}
