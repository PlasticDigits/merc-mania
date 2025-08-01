// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/GameAssetFactory.sol";
import "../src/ERC20GameAsset.sol";
import "../src/GameMaster.sol";
import "../src/interfaces/IGuardERC20.sol";
import "../src/PlayerStats.sol";
import "../src/GameStats.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title MockGuard
 * @dev Mock guard contract that allows all transfers
 */
contract MockGuard is IGuardERC20 {
    function check(address, address, uint256) external pure {}
}

/**
 * @title RestrictiveGuard
 * @dev Mock guard contract that rejects specific transfers for testing
 */
contract RestrictiveGuard is IGuardERC20 {
    mapping(address => bool) public blockedAddresses;

    function blockAddress(address addr) external {
        blockedAddresses[addr] = true;
    }

    function check(address from, address to, uint256) external view {
        require(!blockedAddresses[from], "Sender blocked by guard");
        require(!blockedAddresses[to], "Recipient blocked by guard");
    }
}

/**
 * @title GameAssetFactoryTest
 * @dev Comprehensive test suite for GameAssetFactory contract with 100% coverage
 */
contract GameAssetFactoryTest is Test {
    GameAssetFactory public factory;
    AccessManager public accessManager;
    MockGuard public mockGuard;
    RestrictiveGuard public restrictiveGuard;
    GameMaster public gameMaster;

    address public admin = address(0x1);
    address public authorized = address(0x2);
    address public unauthorized = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    // Events to test
    event AssetCreated(address indexed asset, string name, string symbol);

    function setUp() public {
        // Deploy AccessManager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy guards
        mockGuard = new MockGuard();
        restrictiveGuard = new RestrictiveGuard();

        // Deploy GameMaster
        vm.prank(admin);
        // Deploy stats contracts
        PlayerStats playerStats = new PlayerStats(address(accessManager));
        GameStats gameStats = new GameStats(address(accessManager));

        gameMaster = new GameMaster(address(accessManager), playerStats, gameStats);

        // Deploy GameAssetFactory
        vm.prank(admin);
        factory = new GameAssetFactory(address(accessManager), mockGuard, gameMaster);

        // Set up permissions for authorized address to call createAsset
        vm.startPrank(admin);

        // Grant the factory contract ADMIN_ROLE so it can manage permissions for new assets
        accessManager.grantRole(0, address(factory), 0); // 0 = ADMIN_ROLE

        // Create a role for asset creation
        uint64 ASSET_CREATOR_ROLE = 2;

        // First grant the role to the authorized user
        accessManager.grantRole(ASSET_CREATOR_ROLE, authorized, 0);

        // Then set the function role on the specific factory contract
        bytes4 createAssetSelector = GameAssetFactory.createAsset.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = createAssetSelector;
        accessManager.setTargetFunctionRole(address(factory), selectors, ASSET_CREATOR_ROLE);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        // Test that constructor sets all immutable variables correctly
        assertEq(address(factory.GUARD()), address(mockGuard));
        assertEq(address(factory.GAME_MASTER()), address(gameMaster));
        assertEq(factory.authority(), address(accessManager));

        // Test that ASSET_IMPLEMENTATION is deployed and is a valid ERC20GameAsset
        address implementation = factory.ASSET_IMPLEMENTATION();
        assertTrue(implementation != address(0));

        // Verify it's an ERC20GameAsset by checking it has the expected interface
        ERC20GameAsset impl = ERC20GameAsset(implementation);
        // The implementation should be disabled (constructor calls _disableInitializers())
        vm.expectRevert();
        impl.initialize(address(accessManager), mockGuard, "Test", "TEST", "uri");
    }

    function test_Constructor_WithDifferentGuard() public {
        // Test constructor with restrictive guard
        vm.startPrank(admin);
        GameAssetFactory newFactory = new GameAssetFactory(address(accessManager), restrictiveGuard, gameMaster);

        // Grant admin role to the new factory for testing
        accessManager.grantRole(0, address(newFactory), 0);
        vm.stopPrank();

        assertEq(address(newFactory.GUARD()), address(restrictiveGuard));
        assertEq(address(newFactory.GAME_MASTER()), address(gameMaster));
        assertEq(newFactory.authority(), address(accessManager));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateAsset_UnauthorizedCaller() public {
        // Test that unauthorized caller cannot create assets
        vm.prank(unauthorized);
        vm.expectRevert();
        factory.createAsset("Sword", "SWORD", "ipfs://sword");
    }

    function test_CreateAsset_AuthorizedCaller() public {
        // Test that authorized caller can create assets
        vm.prank(authorized);
        address asset = factory.createAsset("Sword", "SWORD", "ipfs://sword");

        assertTrue(asset != address(0));
        assertEq(factory.getAssetCount(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                            CREATEASSET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateAsset_FirstAsset() public {
        // Verify initial state
        assertEq(factory.getAssetCount(), 0);

        // Create first asset
        vm.prank(authorized);
        address asset = factory.createAsset("Magic Sword", "MSWORD", "ipfs://magicsword");

        // Verify asset creation
        assertTrue(asset != address(0));
        assertEq(factory.getAssetCount(), 1);

        // Verify asset initialization
        ERC20GameAsset gameAsset = ERC20GameAsset(asset);
        assertEq(gameAsset.name(), "Magic Sword");
        assertEq(gameAsset.symbol(), "MSWORD");
        assertEq(gameAsset.tokenUri(), "ipfs://magicsword");
        assertEq(address(gameAsset.guard()), address(mockGuard));
        assertEq(gameAsset.authority(), address(accessManager));

        // Verify GameMaster has MINTER_ROLE (only granted for first asset)
        (bool hasRole,) = accessManager.hasRole(factory.MINTER_ROLE(), address(gameMaster));
        assertTrue(hasRole);

        // Verify mint function role is set for the asset
        (bool inRole, uint32 executionDelay) = accessManager.hasRole(factory.MINTER_ROLE(), address(gameMaster));
        assertTrue(inRole);
        assertEq(executionDelay, 0);
    }

    function test_CreateAsset_SubsequentAssets() public {
        // Create first asset
        vm.prank(authorized);
        address asset1 = factory.createAsset("Sword", "SWORD", "ipfs://sword");

        // Verify GameMaster has MINTER_ROLE after first asset
        (bool hasRole1,) = accessManager.hasRole(factory.MINTER_ROLE(), address(gameMaster));
        assertTrue(hasRole1);

        // Create second asset
        vm.prank(authorized);
        address asset2 = factory.createAsset("Shield", "SHIELD", "ipfs://shield");

        // Verify both assets exist
        assertEq(factory.getAssetCount(), 2);
        assertTrue(asset1 != asset2);

        // Verify GameMaster still has MINTER_ROLE (should not be granted again)
        (bool hasRole2,) = accessManager.hasRole(factory.MINTER_ROLE(), address(gameMaster));
        assertTrue(hasRole2);

        // Create third asset
        vm.prank(authorized);
        factory.createAsset("Potion", "POTION", "ipfs://potion");

        assertEq(factory.getAssetCount(), 3);
    }

    function test_CreateAsset_EmptyStrings() public {
        // Test creating asset with empty strings
        vm.prank(authorized);
        address asset = factory.createAsset("", "", "");

        assertTrue(asset != address(0));
        ERC20GameAsset gameAsset = ERC20GameAsset(asset);
        assertEq(gameAsset.name(), "");
        assertEq(gameAsset.symbol(), "");
        assertEq(gameAsset.tokenUri(), "");
    }

    function test_CreateAsset_LongStrings() public {
        // Test creating asset with very long strings
        string memory longName = "Very Long Asset Name That Exceeds Normal Length";
        string memory longSymbol = "VERYLONGSYMBOL";
        string memory longUri = "ipfs://QmVeryLongHashThatRepresentsTheMetadataForThisAsset";

        vm.prank(authorized);
        address asset = factory.createAsset(longName, longSymbol, longUri);

        assertTrue(asset != address(0));
        ERC20GameAsset gameAsset = ERC20GameAsset(asset);
        assertEq(gameAsset.name(), longName);
        assertEq(gameAsset.symbol(), longSymbol);
        assertEq(gameAsset.tokenUri(), longUri);
    }

    function test_CreateAsset_SpecialCharacters() public {
        // Test creating asset with special characters
        vm.prank(authorized);
        address asset = factory.createAsset("Sword#1", "SWORD#", "ipfs://sword-special");

        assertTrue(asset != address(0));
        ERC20GameAsset gameAsset = ERC20GameAsset(asset);
        assertEq(gameAsset.name(), "Sword#1");
        assertEq(gameAsset.symbol(), "SWORD#");
        assertEq(gameAsset.tokenUri(), "ipfs://sword-special");
    }

    function test_CreateAsset_EventEmission() public {
        // Test event emission
        vm.prank(authorized);

        // We'll capture the event data and verify it matches
        vm.recordLogs();
        address asset = factory.createAsset("Battle Axe", "AXE", "ipfs://axe");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the AssetCreated event among all the logs
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("AssetCreated(address,string,string)")) {
                // Verify the event was emitted with correct parameters
                assertEq(address(uint160(uint256(logs[i].topics[1]))), asset);
                found = true;
                break;
            }
        }
        assertTrue(found, "AssetCreated event not found");
    }

    /*//////////////////////////////////////////////////////////////
                            ENUMERATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetAssetCount_EmptyFactory() public view {
        assertEq(factory.getAssetCount(), 0);
    }

    function test_GetAssetCount_WithAssets() public {
        vm.startPrank(authorized);
        factory.createAsset("Asset1", "A1", "uri1");
        assertEq(factory.getAssetCount(), 1);

        factory.createAsset("Asset2", "A2", "uri2");
        assertEq(factory.getAssetCount(), 2);

        factory.createAsset("Asset3", "A3", "uri3");
        assertEq(factory.getAssetCount(), 3);
        vm.stopPrank();
    }

    function test_GetAllAssets_EmptyFactory() public view {
        address[] memory assets = factory.getAllAssets();
        assertEq(assets.length, 0);
    }

    function test_GetAllAssets_WithAssets() public {
        vm.startPrank(authorized);
        address asset1 = factory.createAsset("Asset1", "A1", "uri1");
        address asset2 = factory.createAsset("Asset2", "A2", "uri2");
        address asset3 = factory.createAsset("Asset3", "A3", "uri3");
        vm.stopPrank();

        address[] memory assets = factory.getAllAssets();
        assertEq(assets.length, 3);
        assertEq(assets[0], asset1);
        assertEq(assets[1], asset2);
        assertEq(assets[2], asset3);
    }

    function test_GetAssets_EmptyFactory() public view {
        address[] memory assets = factory.getAssets(0, 10);
        assertEq(assets.length, 0);
    }

    function test_GetAssets_StartIndexBeyondAssets() public {
        vm.prank(authorized);
        factory.createAsset("Asset1", "A1", "uri1");

        // Request starting from index 1 when only 1 asset exists (indices 0-0)
        address[] memory assets = factory.getAssets(1, 10);
        assertEq(assets.length, 0);

        // Request starting from index 5 when only 1 asset exists
        assets = factory.getAssets(5, 10);
        assertEq(assets.length, 0);
    }

    function test_GetAssets_NormalOperation() public {
        vm.startPrank(authorized);
        address asset1 = factory.createAsset("Asset1", "A1", "uri1"); // Index 0 in storage, will be last in reverse order
        address asset2 = factory.createAsset("Asset2", "A2", "uri2"); // Index 1 in storage, will be middle in reverse order
        address asset3 = factory.createAsset("Asset3", "A3", "uri3"); // Index 2 in storage, will be first in reverse order
        vm.stopPrank();

        // Get all assets in reverse order (most recent first)
        address[] memory assets = factory.getAssets(0, 10);
        assertEq(assets.length, 3);
        assertEq(assets[0], asset3); // Most recent
        assertEq(assets[1], asset2); // Middle
        assertEq(assets[2], asset1); // Oldest

        // Get first 2 assets in reverse order
        assets = factory.getAssets(0, 2);
        assertEq(assets.length, 2);
        assertEq(assets[0], asset3);
        assertEq(assets[1], asset2);

        // Get 1 asset starting from index 1 (skip most recent)
        assets = factory.getAssets(1, 1);
        assertEq(assets.length, 1);
        assertEq(assets[0], asset2);

        // Get assets starting from index 2 (get oldest)
        assets = factory.getAssets(2, 1);
        assertEq(assets.length, 1);
        assertEq(assets[0], asset1);
    }

    function test_GetAssets_CountExceedsAvailable() public {
        vm.startPrank(authorized);
        address asset1 = factory.createAsset("Asset1", "A1", "uri1");
        address asset2 = factory.createAsset("Asset2", "A2", "uri2");
        vm.stopPrank();

        // Request more assets than available
        address[] memory assets = factory.getAssets(0, 10);
        assertEq(assets.length, 2);
        assertEq(assets[0], asset2); // Most recent
        assertEq(assets[1], asset1); // Oldest

        // Request more assets starting from index 1
        assets = factory.getAssets(1, 10);
        assertEq(assets.length, 1);
        assertEq(assets[0], asset1);
    }

    function test_GetAssets_EdgeCases() public {
        vm.startPrank(authorized);
        address asset1 = factory.createAsset("Asset1", "A1", "uri1");
        vm.stopPrank();

        // Get 0 assets
        address[] memory assets = factory.getAssets(0, 0);
        assertEq(assets.length, 0);

        // Start from exact boundary
        assets = factory.getAssets(0, 1);
        assertEq(assets.length, 1);
        assertEq(assets[0], asset1);
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreatedAsset_Functionality() public {
        // Create an asset
        vm.prank(authorized);
        address asset = factory.createAsset("Test Token", "TEST", "ipfs://test");

        ERC20GameAsset gameAsset = ERC20GameAsset(asset);

        // Test that GameMaster can mint tokens on the created asset
        vm.prank(address(gameMaster));
        gameAsset.mint(user1, 1000);

        assertEq(gameAsset.balanceOf(user1), 1000);
        assertEq(gameAsset.totalSupply(), 1000);

        // Test that GameMaster can burn tokens (first need to approve GameMaster)
        vm.prank(user1);
        gameAsset.approve(address(gameMaster), 500);

        vm.prank(address(gameMaster));
        gameAsset.burnFrom(user1, 500);

        assertEq(gameAsset.balanceOf(user1), 500);
        assertEq(gameAsset.totalSupply(), 500);
    }

    function test_CreatedAsset_GuardFunctionality() public {
        // Create an asset with restrictive guard
        vm.prank(admin);
        GameAssetFactory restrictiveFactory = new GameAssetFactory(address(accessManager), restrictiveGuard, gameMaster);

        // Set up permissions for the new factory
        vm.startPrank(admin);

        // Grant the restrictive factory ADMIN_ROLE
        accessManager.grantRole(0, address(restrictiveFactory), 0);

        uint64 ASSET_CREATOR_ROLE_3 = 3;
        accessManager.grantRole(ASSET_CREATOR_ROLE_3, authorized, 0);

        bytes4 createAssetSelector = GameAssetFactory.createAsset.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = createAssetSelector;
        accessManager.setTargetFunctionRole(address(restrictiveFactory), selectors, ASSET_CREATOR_ROLE_3);
        vm.stopPrank();

        // Create asset
        vm.prank(authorized);
        address asset = restrictiveFactory.createAsset("Guarded Token", "GUARD", "ipfs://guard");

        ERC20GameAsset gameAsset = ERC20GameAsset(asset);

        // Mint tokens to user1
        vm.prank(address(gameMaster));
        gameAsset.mint(user1, 1000);

        // Normal transfer should work
        vm.prank(user1);
        gameAsset.transfer(user2, 100);
        assertEq(gameAsset.balanceOf(user2), 100);

        // Block user1 and test transfer fails
        restrictiveGuard.blockAddress(user1);

        vm.prank(user1);
        vm.expectRevert("Sender blocked by guard");
        gameAsset.transfer(user2, 100);
    }

    function test_MultipleFactories() public {
        // Create second factory with different guard
        vm.prank(admin);
        GameAssetFactory factory2 = new GameAssetFactory(address(accessManager), restrictiveGuard, gameMaster);

        // Set up permissions for factory2
        vm.startPrank(admin);

        // Grant factory2 ADMIN_ROLE
        accessManager.grantRole(0, address(factory2), 0);

        uint64 ASSET_CREATOR_ROLE_4 = 4;
        accessManager.grantRole(ASSET_CREATOR_ROLE_4, authorized, 0);

        bytes4 createAssetSelector = GameAssetFactory.createAsset.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = createAssetSelector;
        accessManager.setTargetFunctionRole(address(factory2), selectors, ASSET_CREATOR_ROLE_4);
        vm.stopPrank();

        // Create assets in both factories
        vm.startPrank(authorized);
        address asset1 = factory.createAsset("Factory1 Asset", "F1A", "uri1");
        address asset2 = factory2.createAsset("Factory2 Asset", "F2A", "uri2");
        vm.stopPrank();

        // Verify factories are independent
        assertEq(factory.getAssetCount(), 1);
        assertEq(factory2.getAssetCount(), 1);

        address[] memory assets1 = factory.getAllAssets();
        address[] memory assets2 = factory2.getAllAssets();

        assertEq(assets1.length, 1);
        assertEq(assets2.length, 1);
        assertEq(assets1[0], asset1);
        assertEq(assets2[0], asset2);
        assertTrue(asset1 != asset2);

        // Verify different guards
        ERC20GameAsset gameAsset1 = ERC20GameAsset(asset1);
        ERC20GameAsset gameAsset2 = ERC20GameAsset(asset2);

        assertEq(address(gameAsset1.guard()), address(mockGuard));
        assertEq(address(gameAsset2.guard()), address(restrictiveGuard));
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MinterRole_ConstantValue() public view {
        assertEq(factory.MINTER_ROLE(), 1);
    }

    function test_MinterRole_OnlyGrantedOnce() public {
        // Verify GameMaster doesn't have the role initially
        (bool hasRoleInitial,) = accessManager.hasRole(factory.MINTER_ROLE(), address(gameMaster));
        assertFalse(hasRoleInitial);

        // Create first asset - should grant role
        vm.prank(authorized);
        factory.createAsset("Asset1", "A1", "uri1");

        (bool hasRoleAfterFirst,) = accessManager.hasRole(factory.MINTER_ROLE(), address(gameMaster));
        assertTrue(hasRoleAfterFirst);

        // Create second asset - should not grant role again (no double granting)
        vm.prank(authorized);
        factory.createAsset("Asset2", "A2", "uri2");

        // Role should still be there (and not cause any reverts)
        (bool hasRoleAfterSecond,) = accessManager.hasRole(factory.MINTER_ROLE(), address(gameMaster));
        assertTrue(hasRoleAfterSecond);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_CreateAsset(string calldata name, string calldata symbol, string calldata uri) public {
        vm.assume(bytes(name).length <= 100); // Reasonable bounds
        vm.assume(bytes(symbol).length <= 20);
        vm.assume(bytes(uri).length <= 200);

        vm.prank(authorized);
        address asset = factory.createAsset(name, symbol, uri);

        assertTrue(asset != address(0));

        ERC20GameAsset gameAsset = ERC20GameAsset(asset);
        assertEq(gameAsset.name(), name);
        assertEq(gameAsset.symbol(), symbol);
        assertEq(gameAsset.tokenUri(), uri);
    }

    function testFuzz_GetAssets(uint8 numAssets, uint8 startIndex, uint8 count) public {
        vm.assume(numAssets <= 20); // Reasonable upper bound

        // Create assets with authorized user
        vm.startPrank(authorized);
        for (uint256 i = 0; i < numAssets; i++) {
            factory.createAsset(
                string(abi.encodePacked("Asset", i)),
                string(abi.encodePacked("A", i)),
                string(abi.encodePacked("uri", i))
            );
        }
        vm.stopPrank();

        // Test getAssets with fuzz parameters
        address[] memory assets = factory.getAssets(startIndex, count);

        // Verify constraints
        if (numAssets == 0 || startIndex >= numAssets) {
            assertEq(assets.length, 0);
        } else {
            uint256 available = numAssets - startIndex;
            uint256 expectedLength = count > available ? available : count;
            assertEq(assets.length, expectedLength);
        }
    }
}
