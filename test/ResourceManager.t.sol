// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/ResourceManager.sol";
import "../src/GameAssetFactory.sol";
import "../src/ERC20GameAsset.sol";
import "../src/GameMaster.sol";
import "../src/interfaces/IResourceManager.sol";
import "../src/interfaces/IGuardERC20.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockGuard
 * @dev Mock guard contract that allows all transfers
 */
contract MockGuard is IGuardERC20 {
    function check(address, address, uint256) external pure {}
}

/**
 * @title MockERC20
 * @dev Mock ERC20 token for testing invalid resources
 */
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
}

/**
 * @title ResourceManagerTest
 * @dev Comprehensive test suite for ResourceManager contract with 100% coverage
 */
contract ResourceManagerTest is Test {
    ResourceManager public resourceManager;
    GameAssetFactory public assetFactory;
    GameMaster public gameMaster;
    AccessManager public accessManager;
    MockGuard public mockGuard;

    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    address public unauthorizedUser = makeAddr("unauthorized");

    IERC20 public gold;
    IERC20 public iron;
    IERC20 public wood;
    MockERC20 public invalidToken;

    // Events to test
    event ResourceAdded(address indexed resource, string name);
    event ResourceRemoved(address indexed resource);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy access manager
        accessManager = new AccessManager(admin);

        // Deploy mock guard
        mockGuard = new MockGuard();

        // Deploy game master (needs access manager)
        gameMaster = new GameMaster(address(accessManager));

        // Deploy asset factory
        assetFactory = new GameAssetFactory(address(accessManager), mockGuard, gameMaster);

        // Grant the factory ADMIN_ROLE so it can manage permissions for new assets
        accessManager.grantRole(0, address(assetFactory), 0); // 0 = ADMIN_ROLE

        // Create a role for asset creation and grant it to ResourceManager
        uint64 assetCreatorRole = 2;
        accessManager.grantRole(assetCreatorRole, address(0), 0); // Grant to future ResourceManager

        bytes4 createAssetSelector = GameAssetFactory.createAsset.selector;
        bytes4[] memory createAssetSelectors = new bytes4[](1);
        createAssetSelectors[0] = createAssetSelector;
        accessManager.setTargetFunctionRole(address(assetFactory), createAssetSelectors, assetCreatorRole);

        // Deploy resource manager - it will be granted the role during deployment
        // We need to predict the ResourceManager address and grant it the role
        address predictedResourceManager = vm.computeCreateAddress(admin, vm.getNonce(admin));
        accessManager.grantRole(assetCreatorRole, predictedResourceManager, 0);

        resourceManager = new ResourceManager(address(accessManager), assetFactory);

        // Get Gold reference (automatically created in constructor)
        gold = resourceManager.GOLD();

        // Grant permissions to user for testing restricted functions
        bytes4 addResourceSelector = ResourceManager.addResource.selector;
        bytes4 removeResourceSelector = ResourceManager.removeResource.selector;

        uint64 resourceManagerRole = 1;

        bytes4[] memory addResourceSelectors = new bytes4[](1);
        addResourceSelectors[0] = addResourceSelector;
        accessManager.setTargetFunctionRole(address(resourceManager), addResourceSelectors, resourceManagerRole);

        bytes4[] memory removeResourceSelectors = new bytes4[](1);
        removeResourceSelectors[0] = removeResourceSelector;
        accessManager.setTargetFunctionRole(address(resourceManager), removeResourceSelectors, resourceManagerRole);

        accessManager.grantRole(resourceManagerRole, user, 0);

        // Create some test tokens for comprehensive testing
        invalidToken = new MockERC20("Invalid", "INV");

        vm.stopPrank();
    }

    /// @dev Test constructor functionality
    function test_Constructor() public {
        // Verify Gold was created and added
        assertTrue(address(gold) != address(0), "Gold should be created");
        assertTrue(resourceManager.isResource(gold), "Gold should be registered");
        assertEq(resourceManager.getResourceCount(), 1, "Should have 1 resource initially");
        assertEq(address(resourceManager.getResourceAt(0)), address(gold), "First resource should be Gold");

        // Verify factory reference
        assertEq(address(resourceManager.ASSET_FACTORY()), address(assetFactory), "Factory reference should be set");
    }

    /// @dev Test constructor emits ResourceAdded event for Gold
    function test_ConstructorEmitsEvent() public {
        vm.startPrank(admin);

        // Setup permissions for a new ResourceManager instance
        uint64 assetCreatorRole = 2;
        address predictedResourceManager = vm.computeCreateAddress(admin, vm.getNonce(admin));
        accessManager.grantRole(assetCreatorRole, predictedResourceManager, 0);

        // Deploy new instance to test event emission
        vm.expectEmit(false, false, false, true);
        emit ResourceAdded(address(0), "Gold"); // Don't check Gold address since it will be different

        new ResourceManager(address(accessManager), assetFactory);

        vm.stopPrank();
    }

    /// @dev Test successful resource addition
    function test_AddResource_Success() public {
        vm.startPrank(user);

        vm.expectEmit(false, false, false, true);
        emit ResourceAdded(address(0), "Iron"); // Don't check address since it's determined by factory

        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");

        assertTrue(ironAddress != address(0), "Iron address should be valid");
        assertTrue(resourceManager.isResource(IERC20(ironAddress)), "Iron should be registered");
        assertEq(resourceManager.getResourceCount(), 2, "Should have 2 resources");

        vm.stopPrank();
    }

    /// @dev Test adding resource with empty name fails
    function test_AddResource_EmptyName() public {
        vm.startPrank(user);

        vm.expectRevert("Name cannot be empty");
        resourceManager.addResource("", "IRON", "ipfs://iron");

        vm.stopPrank();
    }

    /// @dev Test adding resource with empty symbol fails
    function test_AddResource_EmptySymbol() public {
        vm.startPrank(user);

        vm.expectRevert("Symbol cannot be empty");
        resourceManager.addResource("Iron", "", "ipfs://iron");

        vm.stopPrank();
    }

    /// @dev Test adding duplicate resource fails
    function test_AddResource_Duplicate() public {
        vm.startPrank(user);

        // Add iron first time
        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        assertTrue(resourceManager.isResource(IERC20(ironAddress)), "Iron should be registered");

        // Mock the factory to return the same address for duplicate test
        // Note: In practice, the factory would create a new address, but for this test
        // we need to test the logic where the same address is returned
        vm.mockCall(
            address(assetFactory),
            abi.encodeWithSelector(GameAssetFactory.createAsset.selector, "Iron2", "IRON2", "ipfs://iron2"),
            abi.encode(ironAddress)
        );

        vm.expectRevert("Resource already exists");
        resourceManager.addResource("Iron2", "IRON2", "ipfs://iron2");

        vm.stopPrank();
    }

    /// @dev Test unauthorized access to addResource
    function test_AddResource_Unauthorized() public {
        vm.startPrank(unauthorizedUser);

        vm.expectRevert();
        resourceManager.addResource("Iron", "IRON", "ipfs://iron");

        vm.stopPrank();
    }

    /// @dev Test successful resource removal
    function test_RemoveResource_Success() public {
        vm.startPrank(user);

        // Add a resource first
        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        iron = IERC20(ironAddress);

        assertTrue(resourceManager.isResource(iron), "Iron should be registered before removal");
        assertEq(resourceManager.getResourceCount(), 2, "Should have 2 resources before removal");

        vm.expectEmit(true, false, false, false);
        emit ResourceRemoved(address(iron));

        resourceManager.removeResource(iron);

        assertFalse(resourceManager.isResource(iron), "Iron should not be registered after removal");
        assertEq(resourceManager.getResourceCount(), 1, "Should have 1 resource after removal");

        vm.stopPrank();
    }

    /// @dev Test cannot remove Gold
    function test_RemoveResource_CannotRemoveGold() public {
        vm.startPrank(user);

        vm.expectRevert("Cannot remove Gold");
        resourceManager.removeResource(gold);

        vm.stopPrank();
    }

    /// @dev Test removing non-existent resource fails
    function test_RemoveResource_NonExistent() public {
        vm.startPrank(user);

        vm.expectRevert("Resource does not exist");
        resourceManager.removeResource(IERC20(address(invalidToken)));

        vm.stopPrank();
    }

    /// @dev Test unauthorized access to removeResource
    function test_RemoveResource_Unauthorized() public {
        vm.startPrank(unauthorizedUser);

        vm.expectRevert();
        resourceManager.removeResource(IERC20(address(invalidToken)));

        vm.stopPrank();
    }

    /// @dev Test getResourceCount returns correct count
    function test_GetResourceCount() public {
        assertEq(resourceManager.getResourceCount(), 1, "Should start with 1 resource (Gold)");

        vm.startPrank(user);

        // Add two more resources
        resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        assertEq(resourceManager.getResourceCount(), 2, "Should have 2 resources");

        resourceManager.addResource("Wood", "WOOD", "ipfs://wood");
        assertEq(resourceManager.getResourceCount(), 3, "Should have 3 resources");

        vm.stopPrank();
    }

    /// @dev Test getResourceAt returns correct resource
    function test_GetResourceAt() public {
        vm.startPrank(user);

        // Add iron and wood
        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        address woodAddress = resourceManager.addResource("Wood", "WOOD", "ipfs://wood");

        // Check all resources at their indices
        assertEq(address(resourceManager.getResourceAt(0)), address(gold), "Index 0 should be Gold");
        assertEq(address(resourceManager.getResourceAt(1)), ironAddress, "Index 1 should be Iron");
        assertEq(address(resourceManager.getResourceAt(2)), woodAddress, "Index 2 should be Wood");

        vm.stopPrank();
    }

    /// @dev Test getResourceAt with invalid index
    function test_GetResourceAt_InvalidIndex() public {
        // EnumerableSet.at() will revert with "EnumerableSet: index out of bounds"
        vm.expectRevert();
        resourceManager.getResourceAt(999);
    }

    /// @dev Test isResource returns correct values
    function test_IsResource() public {
        // Gold should be valid
        assertTrue(resourceManager.isResource(gold), "Gold should be valid resource");

        // Invalid token should not be valid
        assertFalse(resourceManager.isResource(IERC20(address(invalidToken))), "Invalid token should not be valid");

        vm.startPrank(user);

        // Add iron and test
        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        iron = IERC20(ironAddress);

        assertTrue(resourceManager.isResource(iron), "Iron should be valid after addition");

        // Remove iron and test again
        resourceManager.removeResource(iron);
        assertFalse(resourceManager.isResource(iron), "Iron should not be valid after removal");

        vm.stopPrank();
    }

    /// @dev Test getAllResources returns correct array
    function test_GetAllResources() public {
        IERC20[] memory resources = resourceManager.getAllResources();
        assertEq(resources.length, 1, "Should return 1 resource initially");
        assertEq(address(resources[0]), address(gold), "Should return Gold");

        vm.startPrank(user);

        // Add more resources
        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        address woodAddress = resourceManager.addResource("Wood", "WOOD", "ipfs://wood");

        resources = resourceManager.getAllResources();
        assertEq(resources.length, 3, "Should return 3 resources");

        // Verify all resources are included
        bool goldFound = false;
        bool ironFound = false;
        bool woodFound = false;

        for (uint256 i = 0; i < resources.length; i++) {
            if (address(resources[i]) == address(gold)) goldFound = true;
            if (address(resources[i]) == ironAddress) ironFound = true;
            if (address(resources[i]) == woodAddress) woodFound = true;
        }

        assertTrue(goldFound, "Gold should be in resources array");
        assertTrue(ironFound, "Iron should be in resources array");
        assertTrue(woodFound, "Wood should be in resources array");

        vm.stopPrank();
    }

    /// @dev Test requireGoldIncluded with Gold present
    function test_RequireGoldIncluded_Success() public {
        vm.startPrank(user);

        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        iron = IERC20(ironAddress);

        IERC20[] memory validResources = new IERC20[](2);
        validResources[0] = gold;
        validResources[1] = iron;

        // Should not revert
        resourceManager.requireGoldIncluded(validResources);

        vm.stopPrank();
    }

    /// @dev Test requireGoldIncluded without Gold fails
    function test_RequireGoldIncluded_MissingGold() public {
        vm.startPrank(user);

        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        iron = IERC20(ironAddress);

        IERC20[] memory invalidResources = new IERC20[](1);
        invalidResources[0] = iron; // No Gold

        vm.expectRevert("Must include Gold");
        resourceManager.requireGoldIncluded(invalidResources);

        vm.stopPrank();
    }

    /// @dev Test requireGoldIncluded with empty array
    function test_RequireGoldIncluded_EmptyArray() public {
        IERC20[] memory emptyResources = new IERC20[](0);

        vm.expectRevert("Must include Gold");
        resourceManager.requireGoldIncluded(emptyResources);
    }

    /// @dev Test validateResources with valid resources
    function test_ValidateResources_Success() public {
        vm.startPrank(user);

        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        address woodAddress = resourceManager.addResource("Wood", "WOOD", "ipfs://wood");
        iron = IERC20(ironAddress);
        wood = IERC20(woodAddress);

        IERC20[] memory validResources = new IERC20[](3);
        validResources[0] = gold;
        validResources[1] = iron;
        validResources[2] = wood;

        // Should not revert
        resourceManager.validateResources(validResources);

        vm.stopPrank();
    }

    /// @dev Test validateResources with empty array fails
    function test_ValidateResources_EmptyArray() public {
        IERC20[] memory emptyResources = new IERC20[](0);

        vm.expectRevert("Must include at least one resource");
        resourceManager.validateResources(emptyResources);
    }

    /// @dev Test validateResources without Gold fails
    function test_ValidateResources_MissingGold() public {
        vm.startPrank(user);

        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        iron = IERC20(ironAddress);

        IERC20[] memory invalidResources = new IERC20[](1);
        invalidResources[0] = iron; // No Gold

        vm.expectRevert("Must include Gold");
        resourceManager.validateResources(invalidResources);

        vm.stopPrank();
    }

    /// @dev Test validateResources with invalid resource fails
    function test_ValidateResources_InvalidResource() public {
        IERC20[] memory invalidResources = new IERC20[](2);
        invalidResources[0] = gold;
        invalidResources[1] = IERC20(address(invalidToken)); // Not registered

        vm.expectRevert("Invalid resource");
        resourceManager.validateResources(invalidResources);
    }

    /// @dev Test validateResources with duplicate resources fails
    function test_ValidateResources_Duplicates() public {
        vm.startPrank(user);

        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        iron = IERC20(ironAddress);

        IERC20[] memory duplicateResources = new IERC20[](3);
        duplicateResources[0] = gold;
        duplicateResources[1] = iron;
        duplicateResources[2] = gold; // Duplicate Gold

        vm.expectRevert("Duplicate resources not allowed");
        resourceManager.validateResources(duplicateResources);

        vm.stopPrank();
    }

    /// @dev Test validateResources catches duplicates in different positions
    function test_ValidateResources_DuplicatesAtEnd() public {
        vm.startPrank(user);

        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        iron = IERC20(ironAddress);

        IERC20[] memory duplicateResources = new IERC20[](3);
        duplicateResources[0] = gold;
        duplicateResources[1] = iron;
        duplicateResources[2] = iron; // Duplicate Iron

        vm.expectRevert("Duplicate resources not allowed");
        resourceManager.validateResources(duplicateResources);

        vm.stopPrank();
    }

    /// @dev Test edge case: single Gold resource is valid
    function test_ValidateResources_OnlyGold() public {
        IERC20[] memory onlyGold = new IERC20[](1);
        onlyGold[0] = gold;

        // Should not revert
        resourceManager.validateResources(onlyGold);
    }

    /// @dev Test complex scenario with multiple operations
    function test_ComplexScenario() public {
        vm.startPrank(user);

        // Add multiple resources
        address ironAddress = resourceManager.addResource("Iron", "IRON", "ipfs://iron");
        address woodAddress = resourceManager.addResource("Wood", "WOOD", "ipfs://wood");
        address stoneAddress = resourceManager.addResource("Stone", "STONE", "ipfs://stone");

        iron = IERC20(ironAddress);
        wood = IERC20(woodAddress);
        IERC20 stone = IERC20(stoneAddress);

        // Verify count
        assertEq(resourceManager.getResourceCount(), 4, "Should have 4 resources");

        // Validate complex resource array
        IERC20[] memory complexResources = new IERC20[](4);
        complexResources[0] = stone;
        complexResources[1] = gold;
        complexResources[2] = iron;
        complexResources[3] = wood;

        resourceManager.validateResources(complexResources);

        // Remove a resource
        resourceManager.removeResource(stone);
        assertEq(resourceManager.getResourceCount(), 3, "Should have 3 resources after removal");

        // Verify stone is no longer valid
        assertFalse(resourceManager.isResource(stone), "Stone should no longer be valid");

        // Try to validate array with removed resource - should fail
        vm.expectRevert("Invalid resource");
        resourceManager.validateResources(complexResources);

        vm.stopPrank();
    }

    /// @dev Test gas usage for getAllResources with many resources
    function test_GetAllResources_GasUsage() public {
        vm.startPrank(user);

        // Add several resources to test gas usage
        for (uint256 i = 0; i < 10; i++) {
            string memory name = string(abi.encodePacked("Resource", vm.toString(i)));
            string memory symbol = string(abi.encodePacked("RES", vm.toString(i)));
            resourceManager.addResource(name, symbol, "");
        }

        uint256 gasBefore = gasleft();
        IERC20[] memory allResources = resourceManager.getAllResources();
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(allResources.length, 11, "Should have 11 resources (Gold + 10 added)");

        // Log gas usage for reference (this will show in test output)
        emit log_named_uint("Gas used for getAllResources with 11 resources", gasUsed);

        vm.stopPrank();
    }
}
