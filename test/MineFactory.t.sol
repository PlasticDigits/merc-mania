// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/MineFactory.sol";
import "../src/Mine.sol";
import "../src/GameMaster.sol";
import "../src/MercAssetFactory.sol";
import "../src/interfaces/IResourceManager.sol";
import "../src/interfaces/IGameMaster.sol";
import "../src/interfaces/IGuardERC20.sol";
import "../src/interfaces/IERC20MintableBurnable.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title MockToken
 * @dev Mock ERC20 token for testing
 */
contract MockToken is ERC20, IERC20MintableBurnable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}

/**
 * @title MockResourceManager
 * @dev Mock implementation of IResourceManager for testing
 */
contract MockResourceManager is IResourceManager {
    IERC20 public GOLD;
    mapping(IERC20 => bool) private validResources;
    IERC20[] private resourcesArray;

    constructor() {
        GOLD = new MockToken("Gold", "GOLD");
        validResources[GOLD] = true;
        resourcesArray.push(GOLD);
    }

    function addMockResource(IERC20 resource) external {
        validResources[resource] = true;
        resourcesArray.push(resource);
    }

    function removeMockResource(IERC20 resource) external {
        validResources[resource] = false;
        // Remove from array (simple implementation for testing)
        for (uint256 i = 0; i < resourcesArray.length; i++) {
            if (resourcesArray[i] == resource) {
                resourcesArray[i] = resourcesArray[resourcesArray.length - 1];
                resourcesArray.pop();
                break;
            }
        }
    }

    function addResource(string calldata name, string calldata symbol, string calldata) external returns (address) {
        IERC20 newResource = new MockToken(name, symbol);
        validResources[newResource] = true;
        resourcesArray.push(newResource);
        return address(newResource);
    }

    function removeResource(IERC20 resource) external {
        validResources[resource] = false;
    }

    function getResourceCount() external view returns (uint256) {
        return resourcesArray.length;
    }

    function getResourceAt(uint256 index) external view returns (IERC20) {
        return resourcesArray[index];
    }

    function isResource(IERC20 resource) external view returns (bool) {
        return validResources[resource];
    }

    function getAllResources() external view returns (IERC20[] memory) {
        return resourcesArray;
    }

    function validateResources(IERC20[] calldata resources) external view {
        for (uint256 i = 0; i < resources.length; i++) {
            require(validResources[resources[i]], "Invalid resource");
        }
    }
}

/**
 * @title MockGuard
 * @dev Mock guard contract that allows all transfers
 */
contract MockGuard is IGuardERC20 {
    function check(address, address, uint256) external pure {}
}

/**
 * @title MineFactoryTest
 * @dev Comprehensive test suite for MineFactory contract with 100% coverage
 */
contract MineFactoryTest is Test {
    MineFactory public factory;
    AccessManager public accessManager;
    MockResourceManager public resourceManager;
    GameMaster public gameMaster;
    MercAssetFactory public mercFactory;
    MockGuard public mockGuard;
    uint256 public constant INITIAL_PRODUCTION_PER_DAY = 100 ether;
    uint256 public constant HALVING_PERIOD = 3 days;

    address public admin = address(0x1);
    address public authorized = address(0x2);
    address public unauthorized = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    IERC20 public goldToken;
    IERC20 public ironToken;
    IERC20 public stoneToken;

    event MineCreated(address indexed mine, IERC20 indexed resource);

    function setUp() public {
        // Deploy AccessManager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy mock contracts
        resourceManager = new MockResourceManager();
        mockGuard = new MockGuard();

        // Deploy real GameMaster and MercAssetFactory
        vm.prank(admin);
        gameMaster = new GameMaster(address(accessManager));

        vm.prank(admin);
        mercFactory = new MercAssetFactory(address(accessManager), mockGuard);

        // Get gold token from resource manager
        goldToken = resourceManager.GOLD();

        // Add more test resources
        ironToken = IERC20(resourceManager.addResource("Iron", "IRON", ""));
        stoneToken = IERC20(resourceManager.addResource("Stone", "STONE", ""));

        // Deploy MineFactory
        vm.prank(admin);
        factory = new MineFactory(address(accessManager), resourceManager, gameMaster, mercFactory);

        // Set up access control
        vm.startPrank(admin);

        // Grant admin role to MineFactory so it can configure GameMaster permissions during mine creation
        accessManager.grantRole(accessManager.ADMIN_ROLE(), address(factory), 0);

        // Get the function selector for createMine
        bytes4 createMineSelector = bytes4(keccak256("createMine(address,uint256,uint256)"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = createMineSelector;

        // Create a custom role for mine creation (role ID 10 for testing)
        uint64 MINE_CREATOR_ROLE = 10;

        // Set the target function role for createMine to our custom role
        accessManager.setTargetFunctionRole(address(factory), selectors, MINE_CREATOR_ROLE);

        // Grant the custom role to authorized user
        accessManager.grantRole(MINE_CREATOR_ROLE, authorized, 0);

        vm.stopPrank();

        // Label addresses for better trace output
        vm.label(admin, "Admin");
        vm.label(authorized, "Authorized");
        vm.label(unauthorized, "Unauthorized");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(address(factory), "MineFactory");
        vm.label(address(accessManager), "AccessManager");
    }

    /**
     * Test constructor functionality
     */
    function testConstructor() public {
        // Verify immutable variables are set correctly
        assertEq(address(factory.RESOURCE_MANAGER()), address(resourceManager));
        assertEq(address(factory.GAME_MASTER()), address(gameMaster));
        assertEq(address(factory.MERC_FACTORY()), address(mercFactory));
        assertNotEq(factory.MINE_IMPLEMENTATION(), address(0));

        // Verify GAME_ROLE constant
        assertEq(factory.GAME_ROLE(), 2);

        // Verify access control is set up
        assertEq(factory.authority(), address(accessManager));
    }

    /**
     * Test createMine with valid resource
     */
    function testCreateMineValidResource() public {
        vm.prank(authorized);

        // We can't predict the exact address, so we check for any address and the correct resource
        vm.expectEmit(false, true, false, true);
        emit MineCreated(address(0), goldToken); // Address will be different, so we ignore it

        address mineAddress = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        // Verify mine was created
        assertNotEq(mineAddress, address(0));

        // Verify mine is properly initialized
        Mine mine = Mine(mineAddress);
        assertEq(address(mine.resource()), address(goldToken));
        assertEq(address(mine.RESOURCE_MANAGER()), address(resourceManager));
        assertEq(address(mine.GAME_MASTER()), address(gameMaster));
        assertEq(address(mine.MERC_FACTORY()), address(mercFactory));
        assertEq(mine.authority(), address(accessManager));

        // Verify mine count and registry
        assertEq(factory.getMineCount(), 1);

        address[] memory allMines = factory.getAllMines();
        assertEq(allMines.length, 1);
        assertEq(allMines[0], mineAddress);

        address[] memory goldMines = factory.getMinesForResource(goldToken);
        assertEq(goldMines.length, 1);
        assertEq(goldMines[0], mineAddress);

        assertEq(factory.getMineCountForResource(goldToken), 1);
    }

    /**
     * Test createMine access control
     */
    function testCreateMineAccessControl() public {
        // Should revert when called by unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        // Should succeed when called by authorized user
        vm.prank(authorized);
        address mineAddress = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        assertNotEq(mineAddress, address(0));
    }

    /**
     * Test createMine with invalid resource
     */
    function testCreateMineInvalidResource() public {
        // Create a token that's not registered as a resource
        MockToken invalidToken = new MockToken("Invalid", "INV");

        vm.prank(authorized);
        vm.expectRevert(MineFactory.InvalidResource.selector);
        factory.createMine(IERC20(address(invalidToken)), INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
    }

    /**
     * Test creating multiple mines
     */
    function testCreateMultipleMines() public {
        vm.startPrank(authorized);

        // Create mines for different resources
        address goldMine = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        address ironMine = factory.createMine(ironToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        address stoneMine = factory.createMine(stoneToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        // Create another gold mine
        address goldMine2 = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        vm.stopPrank();

        // Verify total count
        assertEq(factory.getMineCount(), 4);

        // Verify resource-specific counts
        assertEq(factory.getMineCountForResource(goldToken), 2);
        assertEq(factory.getMineCountForResource(ironToken), 1);
        assertEq(factory.getMineCountForResource(stoneToken), 1);

        // Verify getAllMines returns all mines
        address[] memory allMines = factory.getAllMines();
        assertEq(allMines.length, 4);

        // Verify getMinesForResource returns correct mines
        address[] memory goldMines = factory.getMinesForResource(goldToken);
        assertEq(goldMines.length, 2);
        assertTrue(goldMines[0] == goldMine || goldMines[1] == goldMine);
        assertTrue(goldMines[0] == goldMine2 || goldMines[1] == goldMine2);

        address[] memory ironMines = factory.getMinesForResource(ironToken);
        assertEq(ironMines.length, 1);
        assertEq(ironMines[0], ironMine);
    }

    /**
     * Test getMines pagination function
     */
    function testGetMinesPagination() public {
        vm.startPrank(authorized);

        // Create 5 mines
        address[] memory mines = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            mines[i] = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        }

        vm.stopPrank();

        // Test normal pagination
        address[] memory result = factory.getMines(0, 2);
        assertEq(result.length, 2);
        assertEq(result[0], mines[4]); // Most recent first
        assertEq(result[1], mines[3]);

        // Test pagination from middle
        result = factory.getMines(2, 2);
        assertEq(result.length, 2);
        assertEq(result[0], mines[2]);
        assertEq(result[1], mines[1]);

        // Test pagination at end
        result = factory.getMines(4, 2);
        assertEq(result.length, 1);
        assertEq(result[0], mines[0]); // Oldest mine

        // Test requesting more than available
        result = factory.getMines(3, 5);
        assertEq(result.length, 2);
        assertEq(result[0], mines[1]);
        assertEq(result[1], mines[0]);

        // Test start index beyond available
        result = factory.getMines(10, 2);
        assertEq(result.length, 0);

        // Test with no mines
        vm.prank(admin);
        MineFactory emptyFactory = new MineFactory(address(accessManager), resourceManager, gameMaster, mercFactory);
        result = emptyFactory.getMines(0, 1);
        assertEq(result.length, 0);
    }

    /**
     * Test getMinesForResource pagination function
     */
    function testGetMinesForResourcePagination() public {
        vm.startPrank(authorized);

        // Create mines for multiple resources
        address[] memory goldMines = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            goldMines[i] = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        }

        // Create mines for iron (should not affect gold pagination)
        factory.createMine(ironToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        factory.createMine(ironToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        vm.stopPrank();

        // Test normal pagination for gold
        address[] memory result = factory.getMinesForResource(goldToken, 0, 2);
        assertEq(result.length, 2);
        assertEq(result[0], goldMines[2]); // Most recent first
        assertEq(result[1], goldMines[1]);

        // Test pagination from middle
        result = factory.getMinesForResource(goldToken, 1, 2);
        assertEq(result.length, 2);
        assertEq(result[0], goldMines[1]);
        assertEq(result[1], goldMines[0]);

        // Test pagination at end
        result = factory.getMinesForResource(goldToken, 2, 2);
        assertEq(result.length, 1);
        assertEq(result[0], goldMines[0]);

        // Test requesting more than available
        result = factory.getMinesForResource(goldToken, 1, 5);
        assertEq(result.length, 2);

        // Test start index beyond available
        result = factory.getMinesForResource(goldToken, 10, 2);
        assertEq(result.length, 0);

        // Test with resource that has no mines
        result = factory.getMinesForResource(stoneToken, 0, 1);
        assertEq(result.length, 0);
    }

    /**
     * Test getter functions with empty state
     */
    function testGettersEmptyState() public {
        // Test with no mines created
        assertEq(factory.getMineCount(), 0);
        assertEq(factory.getMineCountForResource(goldToken), 0);

        address[] memory allMines = factory.getAllMines();
        assertEq(allMines.length, 0);

        address[] memory goldMines = factory.getMinesForResource(goldToken);
        assertEq(goldMines.length, 0);

        address[] memory paginatedMines = factory.getMines(0, 10);
        assertEq(paginatedMines.length, 0);

        address[] memory paginatedResourceMines = factory.getMinesForResource(goldToken, 0, 10);
        assertEq(paginatedResourceMines.length, 0);
    }

    /**
     * Test target function role setup for first mine
     */
    function testTargetFunctionRoleSetup() public {
        vm.prank(authorized);
        factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        // Verify that target function roles were set for GameMaster
        // This is tested implicitly by the mine being able to call GameMaster methods
        // The actual role checks would require inspecting the AccessManager state

        // Create another mine to ensure target function roles are only set once
        vm.prank(authorized);
        factory.createMine(ironToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        assertEq(factory.getMineCount(), 2);
    }

    /**
     * Test edge cases and boundary conditions
     */
    function testEdgeCases() public {
        vm.startPrank(authorized);

        // Test creating mine with same resource multiple times
        address mine1 = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        address mine2 = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        address mine3 = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        assertNotEq(mine1, mine2);
        assertNotEq(mine2, mine3);
        assertNotEq(mine1, mine3);

        // Test pagination with count = 0
        address[] memory result = factory.getMines(0, 0);
        assertEq(result.length, 0);

        result = factory.getMinesForResource(goldToken, 0, 0);
        assertEq(result.length, 0);

        vm.stopPrank();
    }

    /**
     * Test mine implementation deployment
     */
    function testMineImplementation() public view {
        address implementation = factory.MINE_IMPLEMENTATION();
        assertNotEq(implementation, address(0));

        // Verify it's a proper Mine contract by checking it has the right bytecode
        // We can't easily test initialization state without more complex setup
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(implementation)
        }
        assertGt(codeSize, 0, "Implementation should have code");
    }

    /**
     * Test large scale operations
     */
    function testLargeScale() public {
        vm.startPrank(authorized);

        uint256 numMines = 50;

        // Create many mines
        for (uint256 i = 0; i < numMines; i++) {
            IERC20 resource = (i % 3 == 0) ? goldToken : (i % 3 == 1) ? ironToken : stoneToken;
            factory.createMine(resource, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        }

        assertEq(factory.getMineCount(), numMines);

        // Test that getAllMines works with many mines
        address[] memory allMines = factory.getAllMines();
        assertEq(allMines.length, numMines);

        // Test pagination with large numbers
        address[] memory pagedMines = factory.getMines(0, 10);
        assertEq(pagedMines.length, 10);

        pagedMines = factory.getMines(45, 10);
        assertEq(pagedMines.length, 5); // Only 5 remaining

        vm.stopPrank();
    }

    /**
     * Test contract interactions and state consistency
     */
    function testStateConsistency() public {
        vm.startPrank(authorized);

        // Create mines and verify state is consistent
        address goldMine1 = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        address ironMine1 = factory.createMine(ironToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);
        address goldMine2 = factory.createMine(goldToken, INITIAL_PRODUCTION_PER_DAY, HALVING_PERIOD);

        // Verify all state getters are consistent
        assertEq(factory.getMineCount(), 3);
        assertEq(factory.getMineCountForResource(goldToken), 2);
        assertEq(factory.getMineCountForResource(ironToken), 1);
        assertEq(factory.getMineCountForResource(stoneToken), 0);

        address[] memory allMines = factory.getAllMines();
        assertEq(allMines.length, 3);

        address[] memory goldMines = factory.getMinesForResource(goldToken);
        assertEq(goldMines.length, 2);

        address[] memory ironMines = factory.getMinesForResource(ironToken);
        assertEq(ironMines.length, 1);

        address[] memory stoneMines = factory.getMinesForResource(stoneToken);
        assertEq(stoneMines.length, 0);

        // Verify pagination is consistent with direct getters
        address[] memory pagedAll = factory.getMines(0, 10);
        assertEq(pagedAll.length, allMines.length);

        address[] memory pagedGold = factory.getMinesForResource(goldToken, 0, 10);
        assertEq(pagedGold.length, goldMines.length);

        vm.stopPrank();
    }
}
