// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/MercRecruiter.sol";
import "../src/interfaces/IResourceManager.sol";
import "../src/interfaces/IGameMaster.sol";
import "../src/interfaces/IERC20MintableBurnable.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20Token
 * @dev Mock ERC20 token for testing
 */
contract MockERC20Token is ERC20, IERC20MintableBurnable {
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
 * @title MockResourceManager
 * @dev Mock resource manager for testing
 */
contract MockResourceManager is IResourceManager {
    IERC20 public immutable override GOLD;
    mapping(address => bool) public validResources;
    bool public shouldRevertValidation = false;
    string public validationRevertMessage = "Invalid resources";

    constructor() {
        GOLD = new MockERC20Token("Gold", "GOLD");
        validResources[address(GOLD)] = true;
    }

    function addValidResource(address resource) external {
        validResources[resource] = true;
    }

    function setShouldRevertValidation(bool shouldRevert, string memory message) external {
        shouldRevertValidation = shouldRevert;
        validationRevertMessage = message;
    }

    function validateResources(IERC20[] calldata resources) external view override {
        if (shouldRevertValidation) {
            revert(validationRevertMessage);
        }

        require(resources.length > 0, "Must include at least one resource");

        // Check Gold is included
        bool goldIncluded = false;
        for (uint256 i = 0; i < resources.length; i++) {
            if (resources[i] == GOLD) {
                goldIncluded = true;
                break;
            }
        }
        require(goldIncluded, "Must include Gold");

        // Check for duplicates and valid resources
        for (uint256 i = 0; i < resources.length; i++) {
            require(validResources[address(resources[i])], "Invalid resource");
            for (uint256 j = i + 1; j < resources.length; j++) {
                require(resources[i] != resources[j], "Duplicate resources not allowed");
            }
        }
    }

    // Unused interface functions - just return empty/zero values
    function addResource(string calldata, string calldata, string calldata) external pure override returns (address) {
        return address(0);
    }

    function removeResource(IERC20) external pure override {}

    function getResourceCount() external pure override returns (uint256) {
        return 0;
    }

    function getResourceAt(uint256) external pure override returns (IERC20) {
        return IERC20(address(0));
    }

    function isResource(IERC20) external pure override returns (bool) {
        return false;
    }

    function getAllResources() external pure override returns (IERC20[] memory) {
        return new IERC20[](0);
    }
}

/**
 * @title MockGameMaster
 * @dev Mock game master for testing
 */
contract MockGameMaster is IGameMaster {
    mapping(address => mapping(IERC20 => uint256)) public balances;
    bool public shouldRevertSpend = false;
    bool public shouldRevertAdd = false;

    function setBalance(address user, IERC20 token, uint256 amount) external {
        balances[user][token] = amount;
    }

    function setShouldRevertSpend(bool shouldRevert) external {
        shouldRevertSpend = shouldRevert;
    }

    function setShouldRevertAdd(bool shouldRevert) external {
        shouldRevertAdd = shouldRevert;
    }

    function getBalance(address user, IERC20 token) external view override returns (uint256) {
        return balances[user][token];
    }

    function spendBalance(address user, IERC20 token, uint256 amount) external override {
        require(!shouldRevertSpend, "Spend failed");
        require(balances[user][token] >= amount, "Insufficient balance");
        balances[user][token] -= amount;
    }

    function addBalance(address user, IERC20 token, uint256 amount) external override {
        require(!shouldRevertAdd, "Add balance failed");
        balances[user][token] += amount;
    }

    // Unused interface functions
    function deposit(IERC20, uint256) external pure override {}
    function withdraw(IERC20, uint256) external pure override {}
    function transferBalance(address, address, IERC20, uint256) external pure override {}
}

/**
 * @title MockMercAssetFactory
 * @dev Mock mercenary asset factory for testing
 */
contract MockMercAssetFactory {
    mapping(uint256 => address) public levelToMerc;
    bool public shouldReturnZeroAddress = false;
    uint256 public nextLevel = 1;
    bool public shouldRevertCreateMercLevel = false;

    function setMercForLevel(uint256 level, address merc) external {
        levelToMerc[level] = merc;
        if (level >= nextLevel) {
            nextLevel = level + 1;
        }
    }

    function setShouldReturnZeroAddress(bool shouldReturn) external {
        shouldReturnZeroAddress = shouldReturn;
    }

    function setShouldRevertCreateMercLevel(bool shouldRevert) external {
        shouldRevertCreateMercLevel = shouldRevert;
    }

    function getMercByLevel(uint256 level) external view returns (address) {
        if (shouldReturnZeroAddress) {
            return address(0);
        }
        return levelToMerc[level];
    }

    function createMercLevel(string calldata name, string calldata symbol, string calldata tokenURI)
        external
        returns (address)
    {
        require(!shouldRevertCreateMercLevel, "CreateMercLevel failed");

        // Create a mock mercenary token
        MockERC20Token newMerc = new MockERC20Token(name, symbol);
        address mercAddress = address(newMerc);

        // Set it for the next level
        levelToMerc[nextLevel] = mercAddress;
        nextLevel++;

        return mercAddress;
    }
}

/**
 * @title MercRecruiterTest
 * @dev Comprehensive test suite for MercRecruiter contract with 100% coverage
 */
contract MercRecruiterTest is Test {
    MercRecruiter public mercRecruiter;
    MockResourceManager public resourceManager;
    MockGameMaster public gameMaster;
    MockMercAssetFactory public mercFactory;
    AccessManager public accessManager;

    MockERC20Token public gold;
    MockERC20Token public iron;
    MockERC20Token public wood;
    MockERC20Token public level1Merc;
    MockERC20Token public level2Merc;
    MockERC20Token public level3Merc;

    address public admin = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public unauthorized = address(0x4);
    address public aiUser = address(0x5);

    // Events to test
    event MercsRecruited(address indexed player, uint256 level, uint256 amount, IERC20[] resources);

    function setUp() public {
        // Deploy AccessManager
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy mock contracts
        resourceManager = new MockResourceManager();
        gameMaster = new MockGameMaster();
        mercFactory = new MockMercAssetFactory();

        // Get gold from resource manager
        gold = MockERC20Token(address(resourceManager.GOLD()));

        // Deploy additional resource tokens
        iron = new MockERC20Token("Iron", "IRON");
        wood = new MockERC20Token("Wood", "WOOD");

        // Deploy mercenary tokens
        level1Merc = new MockERC20Token("Level 1 Merc", "MERC1");
        level2Merc = new MockERC20Token("Level 2 Merc", "MERC2");
        level3Merc = new MockERC20Token("Level 3 Merc", "MERC3");

        // Set up valid resources
        resourceManager.addValidResource(address(iron));
        resourceManager.addValidResource(address(wood));

        // Set up mercenary levels
        mercFactory.setMercForLevel(1, address(level1Merc));
        mercFactory.setMercForLevel(2, address(level2Merc));
        mercFactory.setMercForLevel(3, address(level3Merc));

        // Deploy MercRecruiter
        vm.prank(admin);
        mercRecruiter = new MercRecruiter(
            address(accessManager),
            resourceManager,
            GameMaster(address(gameMaster)),
            MercAssetFactory(address(mercFactory))
        );
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(address(mercRecruiter.RESOURCE_MANAGER()), address(resourceManager), "Resource manager not set");
        assertEq(address(mercRecruiter.GAME_MASTER()), address(gameMaster), "Game master not set");
        assertEq(address(mercRecruiter.MERC_FACTORY()), address(mercFactory), "Merc factory not set");
        assertEq(mercRecruiter.authority(), address(accessManager), "Authority not set");
    }

    /*//////////////////////////////////////////////////////////////
                        GET REQUIRED LEVEL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetRequiredLevel_SingleResource() public {
        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        uint256 level = mercRecruiter.getRequiredLevel(resources);
        assertEq(level, 1, "Single resource should return level 1");
    }

    function test_GetRequiredLevel_MultipleResources() public {
        IERC20[] memory resources = new IERC20[](3);
        resources[0] = gold;
        resources[1] = iron;
        resources[2] = wood;

        uint256 level = mercRecruiter.getRequiredLevel(resources);
        assertEq(level, 3, "Three resources should return level 3");
    }

    function test_GetRequiredLevel_EmptyArray() public {
        IERC20[] memory resources = new IERC20[](0);

        uint256 level = mercRecruiter.getRequiredLevel(resources);
        assertEq(level, 0, "Empty array should return level 0");
    }

    function test_GetRequiredLevel_FuzzTest(uint8 resourceCount) public {
        vm.assume(resourceCount <= 10); // Reasonable limit

        IERC20[] memory resources = new IERC20[](resourceCount);
        for (uint256 i = 0; i < resourceCount; i++) {
            resources[i] = IERC20(address(uint160(i + 1))); // Dummy addresses
        }

        uint256 level = mercRecruiter.getRequiredLevel(resources);
        assertEq(level, resourceCount, "Level should equal resource count");
    }

    /*//////////////////////////////////////////////////////////////
                        CAN RECRUIT MERCS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CanRecruitMercs_ValidResourcesSufficientBalance() public {
        // Set up player balances
        gameMaster.setBalance(player1, gold, 100);
        gameMaster.setBalance(player1, iron, 100);

        IERC20[] memory resources = new IERC20[](2);
        resources[0] = gold;
        resources[1] = iron;

        bool canRecruit = mercRecruiter.canRecruitMercs(player1, resources, 50);
        assertTrue(canRecruit, "Should be able to recruit with sufficient resources");
    }

    function test_CanRecruitMercs_ValidResourcesInsufficientBalance() public {
        // Set up player balances (insufficient)
        gameMaster.setBalance(player1, gold, 10);
        gameMaster.setBalance(player1, iron, 100);

        IERC20[] memory resources = new IERC20[](2);
        resources[0] = gold;
        resources[1] = iron;

        bool canRecruit = mercRecruiter.canRecruitMercs(player1, resources, 50);
        assertFalse(canRecruit, "Should not be able to recruit with insufficient gold");
    }

    function test_CanRecruitMercs_InvalidResources() public {
        // Set up resource manager to revert validation
        resourceManager.setShouldRevertValidation(true, "Invalid resources");

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        bool canRecruit = mercRecruiter.canRecruitMercs(player1, resources, 50);
        assertFalse(canRecruit, "Should return false when validation reverts");
    }

    function test_CanRecruitMercs_EmptyResources() public {
        IERC20[] memory resources = new IERC20[](0);

        bool canRecruit = mercRecruiter.canRecruitMercs(player1, resources, 50);
        assertFalse(canRecruit, "Should return false for empty resources");
    }

    function test_CanRecruitMercs_NoGold() public {
        IERC20[] memory resources = new IERC20[](1);
        resources[0] = iron; // No gold

        bool canRecruit = mercRecruiter.canRecruitMercs(player1, resources, 50);
        assertFalse(canRecruit, "Should return false when Gold is not included");
    }

    function test_CanRecruitMercs_DuplicateResources() public {
        IERC20[] memory resources = new IERC20[](2);
        resources[0] = gold;
        resources[1] = gold; // Duplicate

        bool canRecruit = mercRecruiter.canRecruitMercs(player1, resources, 50);
        assertFalse(canRecruit, "Should return false for duplicate resources");
    }

    /*//////////////////////////////////////////////////////////////
                        RECRUIT MERCS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecruitMercs_Success_Level1() public {
        // Set up player balances
        gameMaster.setBalance(player1, gold, 100);

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit MercsRecruited(player1, 1, 50, resources);

        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);

        // Verify balance changes
        assertEq(gameMaster.getBalance(player1, gold), 50, "Gold should be spent");
        assertEq(gameMaster.getBalance(player1, IERC20(address(level1Merc))), 50, "Level 1 mercs should be added");
    }

    function test_RecruitMercs_Success_Level2() public {
        // Set up player balances
        gameMaster.setBalance(player1, gold, 100);
        gameMaster.setBalance(player1, iron, 100);

        IERC20[] memory resources = new IERC20[](2);
        resources[0] = gold;
        resources[1] = iron;

        vm.expectEmit(true, true, true, true);
        emit MercsRecruited(player1, 2, 25, resources);

        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 25);

        // Verify balance changes
        assertEq(gameMaster.getBalance(player1, gold), 75, "Gold should be spent");
        assertEq(gameMaster.getBalance(player1, iron), 75, "Iron should be spent");
        assertEq(gameMaster.getBalance(player1, IERC20(address(level2Merc))), 25, "Level 2 mercs should be added");
    }

    function test_RecruitMercs_Success_Level3() public {
        // Set up player balances
        gameMaster.setBalance(player1, gold, 100);
        gameMaster.setBalance(player1, iron, 100);
        gameMaster.setBalance(player1, wood, 100);

        IERC20[] memory resources = new IERC20[](3);
        resources[0] = gold;
        resources[1] = iron;
        resources[2] = wood;

        vm.expectEmit(true, true, true, true);
        emit MercsRecruited(player1, 3, 10, resources);

        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 10);

        // Verify balance changes
        assertEq(gameMaster.getBalance(player1, gold), 90, "Gold should be spent");
        assertEq(gameMaster.getBalance(player1, iron), 90, "Iron should be spent");
        assertEq(gameMaster.getBalance(player1, wood), 90, "Wood should be spent");
        assertEq(gameMaster.getBalance(player1, IERC20(address(level3Merc))), 10, "Level 3 mercs should be added");
    }

    function test_RecruitMercs_RevertAmountZero() public {
        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        vm.expectRevert(MercRecruiter.AmountMustBeGreaterThanZero.selector);
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 0);
    }

    function test_RecruitMercs_RevertInvalidResources() public {
        // Set up resource manager to revert validation
        resourceManager.setShouldRevertValidation(true, "Invalid resources");

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        vm.expectRevert("Invalid resources");
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);
    }

    function test_RecruitMercs_RevertInsufficientResources() public {
        // Set up insufficient balances
        gameMaster.setBalance(player1, gold, 10);

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        vm.expectRevert(MercRecruiter.InsufficientResources.selector);
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);
    }

    function test_RecruitMercs_RevertMercTokenDoesNotExist() public {
        // Set up sufficient balances
        gameMaster.setBalance(player1, gold, 100);

        // Set factory to return zero address (merc doesn't exist)
        mercFactory.setShouldReturnZeroAddress(true);

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        vm.expectRevert(MercRecruiter.MercTokenDoesNotExist.selector);
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);
    }

    function test_RecruitMercs_RevertNoGold() public {
        gameMaster.setBalance(player1, iron, 100);

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = iron; // No gold

        vm.expectRevert("Must include Gold");
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);
    }

    function test_RecruitMercs_RevertDuplicateResources() public {
        gameMaster.setBalance(player1, gold, 100);

        IERC20[] memory resources = new IERC20[](2);
        resources[0] = gold;
        resources[1] = gold; // Duplicate

        vm.expectRevert("Duplicate resources not allowed");
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);
    }

    function test_RecruitMercs_RevertEmptyResources() public {
        IERC20[] memory resources = new IERC20[](0);

        vm.expectRevert("Must include at least one resource");
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecruitMercs_MultiplePlayersIndependentBalances() public {
        // Set up different balances for different players
        gameMaster.setBalance(player1, gold, 100);
        gameMaster.setBalance(player2, gold, 50);

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        // Player 1 recruits
        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 30);

        // Player 2 recruits
        vm.prank(player2);
        mercRecruiter.recruitMercs(resources, 20);

        // Verify independent balance tracking
        assertEq(gameMaster.getBalance(player1, gold), 70, "Player 1 gold should be reduced independently");
        assertEq(gameMaster.getBalance(player2, gold), 30, "Player 2 gold should be reduced independently");
        assertEq(gameMaster.getBalance(player1, IERC20(address(level1Merc))), 30, "Player 1 should have 30 mercs");
        assertEq(gameMaster.getBalance(player2, IERC20(address(level1Merc))), 20, "Player 2 should have 20 mercs");
    }

    function test_RecruitMercs_ExactBalanceUsage() public {
        // Set up exact balance needed
        gameMaster.setBalance(player1, gold, 50);
        gameMaster.setBalance(player1, iron, 50);

        IERC20[] memory resources = new IERC20[](2);
        resources[0] = gold;
        resources[1] = iron;

        vm.prank(player1);
        mercRecruiter.recruitMercs(resources, 50);

        // Verify all balance is used
        assertEq(gameMaster.getBalance(player1, gold), 0, "All gold should be spent");
        assertEq(gameMaster.getBalance(player1, iron), 0, "All iron should be spent");
    }

    function test_CanRecruitMercs_BorderlineBalance() public {
        // Set up exact balance needed
        gameMaster.setBalance(player1, gold, 50);

        IERC20[] memory resources = new IERC20[](1);
        resources[0] = gold;

        assertTrue(
            mercRecruiter.canRecruitMercs(player1, resources, 50), "Should be able to recruit with exact balance"
        );
        assertFalse(
            mercRecruiter.canRecruitMercs(player1, resources, 51),
            "Should not be able to recruit with insufficient balance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecruitMercs_FullWorkflowMultipleResources() public {
        // Set up comprehensive scenario
        gameMaster.setBalance(player1, gold, 1000);
        gameMaster.setBalance(player1, iron, 1000);
        gameMaster.setBalance(player1, wood, 1000);

        // Test level 1 recruitment
        IERC20[] memory level1Resources = new IERC20[](1);
        level1Resources[0] = gold;

        vm.prank(player1);
        mercRecruiter.recruitMercs(level1Resources, 100);

        // Test level 2 recruitment
        IERC20[] memory level2Resources = new IERC20[](2);
        level2Resources[0] = gold;
        level2Resources[1] = iron;

        vm.prank(player1);
        mercRecruiter.recruitMercs(level2Resources, 200);

        // Test level 3 recruitment
        IERC20[] memory level3Resources = new IERC20[](3);
        level3Resources[0] = gold;
        level3Resources[1] = iron;
        level3Resources[2] = wood;

        vm.prank(player1);
        mercRecruiter.recruitMercs(level3Resources, 300);

        // Verify final balances
        assertEq(gameMaster.getBalance(player1, gold), 400, "Gold balance after all recruitments"); // 1000 - 100 - 200 - 300
        assertEq(gameMaster.getBalance(player1, iron), 500, "Iron balance after level 2 and 3"); // 1000 - 200 - 300
        assertEq(gameMaster.getBalance(player1, wood), 700, "Wood balance after level 3"); // 1000 - 300
        assertEq(gameMaster.getBalance(player1, IERC20(address(level1Merc))), 100, "Level 1 mercs");
        assertEq(gameMaster.getBalance(player1, IERC20(address(level2Merc))), 200, "Level 2 mercs");
        assertEq(gameMaster.getBalance(player1, IERC20(address(level3Merc))), 300, "Level 3 mercs");
    }
}
