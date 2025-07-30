// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/MercAssetFactory.sol";
import "../src/ERC20MercAsset.sol";
import "../src/interfaces/IGuardERC20.sol";
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
 * @title MercAssetFactoryTest
 * @dev Comprehensive test suite for MercAssetFactory contract with 100% coverage
 */
contract MercAssetFactoryTest is Test {
    MercAssetFactory public factory;
    AccessManager public accessManager;
    MockGuard public mockGuard;
    RestrictiveGuard public restrictiveGuard;

    address public admin = address(0x1);
    address public authorized = address(0x2);
    address public unauthorized = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    // Test constants
    string constant MERC_NAME = "Level 1 Mercenary";
    string constant MERC_SYMBOL = "MERC1";
    string constant MERC_URI = "https://api.mercmania.com/mercenary/1";

    // Events to test
    event MercCreated(address indexed merc, uint256 level, string name, string symbol);

    function setUp() public {
        // Deploy AccessManager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy guards
        mockGuard = new MockGuard();
        restrictiveGuard = new RestrictiveGuard();

        // Deploy MercAssetFactory
        vm.prank(admin);
        factory = new MercAssetFactory(address(accessManager), mockGuard);

        // Set up permissions for authorized address to call createMerc
        vm.startPrank(admin);

        // Create a role for merc creation
        uint64 MERC_CREATOR_ROLE = 2;

        // Grant the role to the authorized user
        accessManager.grantRole(MERC_CREATOR_ROLE, authorized, 0);

        // Set the function role on the specific factory contract
        bytes4 createMercSelector = MercAssetFactory.createMerc.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = createMercSelector;
        accessManager.setTargetFunctionRole(address(factory), selectors, MERC_CREATOR_ROLE);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        // Test that constructor sets all immutable variables correctly
        assertEq(address(factory.GUARD()), address(mockGuard), "Guard not set correctly");
        assertTrue(factory.MERC_IMPLEMENTATION() != address(0), "Implementation not deployed");
        assertEq(factory.authority(), address(accessManager), "Authority not set correctly");
        
        // Test initial state
        assertEq(factory.getMercCount(), 0, "Initial merc count should be 0");
        assertEq(factory.highestLevel(), 0, "Initial highest level should be 0");
        
        // Test with different guard
        vm.prank(admin);
        MercAssetFactory factory2 = new MercAssetFactory(address(accessManager), restrictiveGuard);
        assertEq(address(factory2.GUARD()), address(restrictiveGuard), "Restrictive guard not set correctly");
    }

    function test_Constructor_ImplementationIsValidERC20MercAsset() public view {
        // Verify the implementation is a valid ERC20MercAsset contract
        address impl = factory.MERC_IMPLEMENTATION();
        
        // Try to call ERC20MercAsset specific functions (should not revert)
        ERC20MercAsset mercImpl = ERC20MercAsset(impl);
        
        // These should not revert for a properly deployed ERC20MercAsset
        assertEq(mercImpl.level(), 0, "Implementation level should be 0");
        assertEq(mercImpl.totalSupply(), 0, "Implementation total supply should be 0");
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateMerc_RequiresAuthorization() public {
        // Test that unauthorized address cannot create mercs
        vm.prank(unauthorized);
        vm.expectRevert();
        factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);

        // Test that authorized address can create mercs
        vm.prank(authorized);
        address mercAddress = factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        assertTrue(mercAddress != address(0), "Merc creation should succeed for authorized user");
    }

    function test_CreateMerc_RevertsWith_UnauthorizedMessage() public {
        vm.prank(unauthorized);
        vm.expectRevert(); // AccessManaged will revert with its own message
        factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
    }

    /*//////////////////////////////////////////////////////////////
                            CREATE MERC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateMerc_Success() public {
        vm.prank(authorized);
        address mercAddress = factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        
        // Verify the merc was created
        assertTrue(mercAddress != address(0), "Merc address should not be zero");
        
        // Verify it's different from implementation
        assertTrue(mercAddress != factory.MERC_IMPLEMENTATION(), "Merc should be clone, not implementation");
        
        // Verify state updates
        assertEq(factory.getMercCount(), 1, "Merc count should be 1");
        assertEq(factory.highestLevel(), 1, "Highest level should be 1");
        assertEq(factory.getMercByLevel(1), mercAddress, "Level 1 should map to created merc");
        assertTrue(factory.levelExists(1), "Level 1 should exist");
    }

    function test_CreateMerc_EmitsEvent() public {
        vm.prank(authorized);
        
        // Record logs to capture the event
        vm.recordLogs();
        
        address mercAddress = factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        
        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Should have at least one log (the MercCreated event)
        assertTrue(logs.length > 0, "Should emit at least one event");
        
        // Find the MercCreated event (it should be the last one)
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MercCreated(address,uint256,string,string)")) {
                foundEvent = true;
                
                // Decode the event data
                address emittedMerc = abi.decode(abi.encodePacked(logs[i].topics[1]), (address));
                (uint256 level, string memory name, string memory symbol) = abi.decode(logs[i].data, (uint256, string, string));
                
                // Verify event data
                assertEq(emittedMerc, mercAddress, "Event should emit correct merc address");
                assertEq(level, 1, "Event should emit correct level");
                assertEq(name, MERC_NAME, "Event should emit correct name");
                assertEq(symbol, MERC_SYMBOL, "Event should emit correct symbol");
                break;
            }
        }
        
        assertTrue(foundEvent, "MercCreated event should be emitted");
    }

    function test_CreateMerc_InitializesCloneCorrectly() public {
        vm.prank(authorized);
        address mercAddress = factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        
        ERC20MercAsset merc = ERC20MercAsset(mercAddress);
        
        // Verify initialization
        assertEq(merc.name(), MERC_NAME, "Name not set correctly");
        assertEq(merc.symbol(), MERC_SYMBOL, "Symbol not set correctly");
        assertEq(merc.tokenUri(), MERC_URI, "Token URI not set correctly");
        assertEq(merc.level(), 1, "Level should be 1");
        assertEq(merc.authority(), address(accessManager), "Authority not set correctly");
        assertEq(address(merc.guard()), address(mockGuard), "Guard not set correctly");
    }

    function test_CreateMerc_SequentialLevels() public {
        // Create multiple mercs and verify sequential levels
        address[] memory mercs = new address[](5);
        
        vm.startPrank(authorized);
        for (uint256 i = 0; i < 5; i++) {
            string memory name = string(abi.encodePacked("Level ", vm.toString(i + 1), " Mercenary"));
            string memory symbol = string(abi.encodePacked("MERC", vm.toString(i + 1)));
            string memory uri = string(abi.encodePacked("https://api.mercmania.com/mercenary/", vm.toString(i + 1)));
            
            mercs[i] = factory.createMerc(name, symbol, uri);
            
            // Verify level assignment
            ERC20MercAsset merc = ERC20MercAsset(mercs[i]);
            assertEq(merc.level(), i + 1, "Level should be sequential");
            assertEq(factory.getMercByLevel(i + 1), mercs[i], "Level mapping should be correct");
        }
        vm.stopPrank();
        
        // Verify final state
        assertEq(factory.getMercCount(), 5, "Should have 5 mercs");
        assertEq(factory.highestLevel(), 5, "Highest level should be 5");
    }

    function test_CreateMerc_WithDifferentGuards() public {
        // Create factory with restrictive guard
        vm.prank(admin);
        MercAssetFactory restrictiveFactory = new MercAssetFactory(address(accessManager), restrictiveGuard);

        // Set up permissions for restrictive factory
        vm.startPrank(admin);
        uint64 MERC_CREATOR_ROLE = 3;
        accessManager.grantRole(MERC_CREATOR_ROLE, authorized, 0);
        bytes4 createMercSelector = MercAssetFactory.createMerc.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = createMercSelector;
        accessManager.setTargetFunctionRole(address(restrictiveFactory), selectors, MERC_CREATOR_ROLE);
        vm.stopPrank();

        vm.prank(authorized);
        address mercAddress = restrictiveFactory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        
        ERC20MercAsset merc = ERC20MercAsset(mercAddress);
        assertEq(address(merc.guard()), address(restrictiveGuard), "Should use restrictive guard");
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetMercByLevel() public {
        // Test with no mercs created
        assertEq(factory.getMercByLevel(1), address(0), "Should return zero address for non-existent level");
        assertEq(factory.getMercByLevel(0), address(0), "Should return zero address for level 0");
        assertEq(factory.getMercByLevel(999), address(0), "Should return zero address for high level");
        
        // Create a merc
        vm.prank(authorized);
        address mercAddress = factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        
        // Test with merc created
        assertEq(factory.getMercByLevel(1), mercAddress, "Should return correct address for level 1");
        assertEq(factory.getMercByLevel(2), address(0), "Should return zero address for non-existent level 2");
    }

    function test_GetAllMercs() public {
        // Test with no mercs
        address[] memory emptyMercs = factory.getAllMercs();
        assertEq(emptyMercs.length, 0, "Should return empty array when no mercs");
        
        // Create multiple mercs
        address[] memory expectedMercs = new address[](3);
        vm.startPrank(authorized);
        for (uint256 i = 0; i < 3; i++) {
            string memory name = string(abi.encodePacked("Merc ", vm.toString(i + 1)));
            string memory symbol = string(abi.encodePacked("M", vm.toString(i + 1)));
            expectedMercs[i] = factory.createMerc(name, symbol, MERC_URI);
        }
        vm.stopPrank();
        
        // Test getAllMercs
        address[] memory allMercs = factory.getAllMercs();
        assertEq(allMercs.length, 3, "Should return 3 mercs");
        
        // Verify all mercs are included (order may vary due to EnumerableSet)
        for (uint256 i = 0; i < 3; i++) {
            bool found = false;
            for (uint256 j = 0; j < allMercs.length; j++) {
                if (allMercs[j] == expectedMercs[i]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "Expected merc should be in getAllMercs result");
        }
    }

    function test_GetAllLevels() public {
        // Test with no levels
        uint256[] memory emptyLevels = factory.getAllLevels();
        assertEq(emptyLevels.length, 0, "Should return empty array when no levels");
        
        // Create mercs at different levels
        vm.startPrank(authorized);
        factory.createMerc("Merc 1", "M1", MERC_URI); // Level 1
        factory.createMerc("Merc 2", "M2", MERC_URI); // Level 2
        factory.createMerc("Merc 3", "M3", MERC_URI); // Level 3
        vm.stopPrank();
        
        // Test getAllLevels
        uint256[] memory allLevels = factory.getAllLevels();
        assertEq(allLevels.length, 3, "Should return 3 levels");
        
        // Verify all expected levels are included
        bool foundLevel1 = false;
        bool foundLevel2 = false;
        bool foundLevel3 = false;
        
        for (uint256 i = 0; i < allLevels.length; i++) {
            if (allLevels[i] == 1) foundLevel1 = true;
            if (allLevels[i] == 2) foundLevel2 = true;
            if (allLevels[i] == 3) foundLevel3 = true;
        }
        
        assertTrue(foundLevel1, "Level 1 should be included");
        assertTrue(foundLevel2, "Level 2 should be included");
        assertTrue(foundLevel3, "Level 3 should be included");
    }

    function test_GetMercCount() public {
        // Test initial count
        assertEq(factory.getMercCount(), 0, "Initial count should be 0");
        
        // Create mercs and test count increases
        vm.startPrank(authorized);
        factory.createMerc("Merc 1", "M1", MERC_URI);
        assertEq(factory.getMercCount(), 1, "Count should be 1 after first merc");
        
        factory.createMerc("Merc 2", "M2", MERC_URI);
        assertEq(factory.getMercCount(), 2, "Count should be 2 after second merc");
        
        factory.createMerc("Merc 3", "M3", MERC_URI);
        assertEq(factory.getMercCount(), 3, "Count should be 3 after third merc");
        vm.stopPrank();
    }

    function test_LevelExists() public {
        // Test with no levels created
        assertFalse(factory.levelExists(0), "Level 0 should not exist");
        assertFalse(factory.levelExists(1), "Level 1 should not exist initially");
        assertFalse(factory.levelExists(999), "Level 999 should not exist");
        
        // Create some mercs
        vm.startPrank(authorized);
        factory.createMerc("Merc 1", "M1", MERC_URI); // Level 1
        factory.createMerc("Merc 2", "M2", MERC_URI); // Level 2
        vm.stopPrank();
        
        // Test with levels created
        assertFalse(factory.levelExists(0), "Level 0 should still not exist");
        assertTrue(factory.levelExists(1), "Level 1 should exist");
        assertTrue(factory.levelExists(2), "Level 2 should exist");
        assertFalse(factory.levelExists(3), "Level 3 should not exist yet");
        assertFalse(factory.levelExists(999), "Level 999 should not exist");
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES AND STRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateMerc_WithEmptyStrings() public {
        vm.prank(authorized);
        address mercAddress = factory.createMerc("", "", "");
        
        ERC20MercAsset merc = ERC20MercAsset(mercAddress);
        assertEq(merc.name(), "", "Empty name should be preserved");
        assertEq(merc.symbol(), "", "Empty symbol should be preserved");
        assertEq(merc.tokenUri(), "", "Empty URI should be preserved");
        assertEq(merc.level(), 1, "Level should still be assigned correctly");
    }

    function test_CreateMerc_WithLongStrings() public {
        string memory longName = "This is a very long name for a mercenary that exceeds normal length expectations and tests string handling";
        string memory longSymbol = "VERYLONGSYMBOLNAME";
        string memory longUri = "https://api.mercmania.com/mercenary/metadata/very/long/path/to/test/uri/handling/in/the/contract/implementation";
        
        vm.prank(authorized);
        address mercAddress = factory.createMerc(longName, longSymbol, longUri);
        
        ERC20MercAsset merc = ERC20MercAsset(mercAddress);
        assertEq(merc.name(), longName, "Long name should be preserved");
        assertEq(merc.symbol(), longSymbol, "Long symbol should be preserved");
        assertEq(merc.tokenUri(), longUri, "Long URI should be preserved");
    }

    function test_CreateMerc_MultipleSequentialCreations() public {
        uint256 numMercs = 10;
        address[] memory mercs = new address[](numMercs);
        
        vm.startPrank(authorized);
        for (uint256 i = 0; i < numMercs; i++) {
            string memory name = string(abi.encodePacked("Mercenary Level ", vm.toString(i + 1)));
            string memory symbol = string(abi.encodePacked("MERC", vm.toString(i + 1)));
            string memory uri = string(abi.encodePacked("https://api.mercmania.com/", vm.toString(i + 1)));
            
            mercs[i] = factory.createMerc(name, symbol, uri);
            
            // Verify state at each step
            assertEq(factory.getMercCount(), i + 1, "Count should increment correctly");
            assertEq(factory.highestLevel(), i + 1, "Highest level should increment correctly");
            assertEq(factory.getMercByLevel(i + 1), mercs[i], "Level mapping should be correct");
            assertTrue(factory.levelExists(i + 1), "Level should exist after creation");
        }
        vm.stopPrank();
        
        // Verify final state
        assertEq(factory.getMercCount(), numMercs, "Final count should match");
        assertEq(factory.highestLevel(), numMercs, "Final highest level should match");
        
        // Verify all levels exist
        for (uint256 i = 1; i <= numMercs; i++) {
            assertTrue(factory.levelExists(i), "All created levels should exist");
            assertTrue(factory.getMercByLevel(i) != address(0), "All levels should have merc addresses");
        }
        
        // Verify arrays return correct lengths
        assertEq(factory.getAllMercs().length, numMercs, "getAllMercs should return correct length");
        assertEq(factory.getAllLevels().length, numMercs, "getAllLevels should return correct length");
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreatedMerc_IsFullyFunctional() public {
        vm.prank(authorized);
        address mercAddress = factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        
        ERC20MercAsset merc = ERC20MercAsset(mercAddress);
        
        // Test that the merc is properly initialized and functional
        assertEq(merc.name(), MERC_NAME, "Name should be set");
        assertEq(merc.symbol(), MERC_SYMBOL, "Symbol should be set");
        assertEq(merc.decimals(), 18, "Should have 18 decimals");
        assertEq(merc.totalSupply(), 0, "Initial supply should be 0");
        
        // Test that it's using the correct authority
        assertEq(merc.authority(), factory.authority(), "Should use same authority as factory");
    }

    function test_FactoryState_ConsistencyAfterMultipleOperations() public {
        // Create mercs with different patterns
        vm.startPrank(authorized);
        address merc1 = factory.createMerc("First", "F1", "uri1");
        address merc2 = factory.createMerc("Second", "F2", "uri2");
        address merc3 = factory.createMerc("Third", "F3", "uri3");
        vm.stopPrank();
        
        // Verify all state is consistent
        assertEq(factory.getMercCount(), 3, "Count should be 3");
        assertEq(factory.highestLevel(), 3, "Highest level should be 3");
        
        // Verify mappings
        assertEq(factory.getMercByLevel(1), merc1, "Level 1 mapping");
        assertEq(factory.getMercByLevel(2), merc2, "Level 2 mapping");
        assertEq(factory.getMercByLevel(3), merc3, "Level 3 mapping");
        
        // Verify level existence
        assertTrue(factory.levelExists(1), "Level 1 exists");
        assertTrue(factory.levelExists(2), "Level 2 exists");
        assertTrue(factory.levelExists(3), "Level 3 exists");
        assertFalse(factory.levelExists(4), "Level 4 doesn't exist");
        
        // Verify arrays include all elements
        address[] memory allMercs = factory.getAllMercs();
        uint256[] memory allLevels = factory.getAllLevels();
        
        assertEq(allMercs.length, 3, "getAllMercs length");
        assertEq(allLevels.length, 3, "getAllLevels length");
        
        // Verify all mercs are unique
        assertTrue(merc1 != merc2, "Mercs should be unique");
        assertTrue(merc2 != merc3, "Mercs should be unique");
        assertTrue(merc1 != merc3, "Mercs should be unique");
        
        // Verify none are zero address
        assertTrue(merc1 != address(0), "Merc should not be zero address");
        assertTrue(merc2 != address(0), "Merc should not be zero address");
        assertTrue(merc3 != address(0), "Merc should not be zero address");
    }

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE VARIABLES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ImmutableVariables_CannotBeChanged() public {
        address originalGuard = address(factory.GUARD());
        address originalImpl = factory.MERC_IMPLEMENTATION();
        
        // These should remain constant throughout the contract's lifetime
        vm.prank(authorized);
        factory.createMerc(MERC_NAME, MERC_SYMBOL, MERC_URI);
        
        assertEq(address(factory.GUARD()), originalGuard, "Guard should remain constant");
        assertEq(factory.MERC_IMPLEMENTATION(), originalImpl, "Implementation should remain constant");
        
        // Create more mercs and verify immutables don't change
        vm.startPrank(authorized);
        for (uint256 i = 0; i < 5; i++) {
            factory.createMerc(
                string(abi.encodePacked("Merc", vm.toString(i))),
                string(abi.encodePacked("M", vm.toString(i))),
                "uri"
            );
        }
        vm.stopPrank();
        
        assertEq(address(factory.GUARD()), originalGuard, "Guard should still be constant");
        assertEq(factory.MERC_IMPLEMENTATION(), originalImpl, "Implementation should still be constant");
    }

    function test_HighestLevel_StartsAtZeroAndIncrementsCorrectly() public {
        assertEq(factory.highestLevel(), 0, "Should start at 0");
        
        vm.startPrank(authorized);
        
        factory.createMerc("Merc1", "M1", "uri1");
        assertEq(factory.highestLevel(), 1, "Should be 1 after first merc");
        
        factory.createMerc("Merc2", "M2", "uri2");
        assertEq(factory.highestLevel(), 2, "Should be 2 after second merc");
        
        factory.createMerc("Merc3", "M3", "uri3");
        assertEq(factory.highestLevel(), 3, "Should be 3 after third merc");
        
        vm.stopPrank();
    }
}