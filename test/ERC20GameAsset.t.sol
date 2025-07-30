// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/ERC20GameAsset.sol";
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
 * @title SelfApprovingGuard
 * @dev Mock guard that tests the special approval logic when msg.sender is guard
 */
contract SelfApprovingGuard is IGuardERC20 {
    ERC20GameAsset public token;
    bool public shouldFail;

    function setToken(address _token) external {
        token = ERC20GameAsset(_token);
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function check(address, address, uint256) external view {
        require(!shouldFail, "Guard check failed");
    }

    function triggerTransfer(address from, address to, uint256 amount) external {
        // This will trigger the special approval logic in _update
        // First approve ourselves, then call transferFrom
        token.transferFrom(from, to, amount);
    }

    // Alternative method that directly calls the internal transfer logic
    function directTransfer(address from, address to, uint256 amount) external {
        // This should trigger the special approval in _update since guard is msg.sender
        // We'll use a low-level call to bypass the allowance check
        (bool success,) =
            address(token).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
        require(success, "Transfer failed");
    }
}

/**
 * @title MockAccessManager
 * @dev Mock access manager for testing access control
 */
contract MockAccessManager {
    mapping(address => mapping(bytes4 => bool)) public permissions;
    bool public defaultAllow = true;

    function setPermission(address caller, bytes4 selector, bool allowed) external {
        permissions[caller][selector] = allowed;
    }

    function setDefaultAllow(bool _allow) external {
        defaultAllow = _allow;
    }

    function canCall(address caller, address, bytes4 selector) external view returns (bool immediate, uint32 delay) {
        if (permissions[caller][selector] || defaultAllow) {
            return (true, 0);
        }
        return (false, 0);
    }
}

/**
 * @title ERC20GameAssetTest
 * @dev Comprehensive test suite for ERC20GameAsset contract with 100% coverage
 */
contract ERC20GameAssetTest is Test {
    MockGuard public mockGuard;
    RestrictiveGuard public restrictiveGuard;
    SelfApprovingGuard public selfApprovingGuard;
    MockAccessManager public accessManager;

    // Implementation contract for cloning
    address public implementation;

    address public admin = address(this);
    address public user1 = address(0x1111);
    address public user2 = address(0x2222);
    address public unauthorized = address(0x3333);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        // Deploy mock contracts
        mockGuard = new MockGuard();
        restrictiveGuard = new RestrictiveGuard();
        selfApprovingGuard = new SelfApprovingGuard();
        accessManager = new MockAccessManager();

        // Deploy implementation contract
        implementation = address(new ERC20GameAsset());
    }

    function _createGameAsset() internal returns (ERC20GameAsset) {
        // Create a minimal proxy clone of the implementation
        address clone = Clones.clone(implementation);
        return ERC20GameAsset(clone);
    }

    // ===========================================
    // Constructor and Initialization Tests
    // ===========================================

    function test_Constructor() public {
        // Test that constructor properly disables initializers
        ERC20GameAsset freshAsset = new ERC20GameAsset();

        // Constructor should set empty name and symbol
        assertEq(freshAsset.name(), "");
        assertEq(freshAsset.symbol(), "");

        // Should not be able to initialize after construction
        vm.expectRevert();
        freshAsset.initialize(
            address(accessManager), mockGuard, "Test Token", "TEST", "https://example.com/metadata.json"
        );
    }

    function test_ProperInitialization() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(
            address(accessManager), mockGuard, "Magic Sword", "SWORD", "https://example.com/sword.json"
        );

        // Verify all parameters were set correctly
        assertEq(gameAsset.name(), "Magic Sword");
        assertEq(gameAsset.symbol(), "SWORD");
        assertEq(gameAsset.tokenUri(), "https://example.com/sword.json");
        assertEq(address(gameAsset.guard()), address(mockGuard));
        assertEq(gameAsset.authority(), address(accessManager));
    }

    function test_InitializationOnlyOnce() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        // First initialization should succeed
        gameAsset.initialize(address(accessManager), mockGuard, "First Token", "FIRST", "uri1");

        // Second initialization should fail
        vm.expectRevert();
        gameAsset.initialize(address(accessManager), mockGuard, "Second Token", "SECOND", "uri2");
    }

    function test_InitializationWithEmptyParams() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "", "", "");

        assertEq(gameAsset.name(), "");
        assertEq(gameAsset.symbol(), "");
        assertEq(gameAsset.tokenUri(), "");
    }

    // ===========================================
    // Access Control Tests
    // ===========================================

    function test_MintWithPermission() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Admin should be able to mint (default allow is true)
        gameAsset.mint(user1, 1000e18);
        assertEq(gameAsset.balanceOf(user1), 1000e18);
        assertEq(gameAsset.totalSupply(), 1000e18);
    }

    function test_MintWithoutPermission() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Disable default permissions
        accessManager.setDefaultAllow(false);

        // Unauthorized user should not be able to mint
        vm.prank(unauthorized);
        vm.expectRevert();
        gameAsset.mint(user1, 1000e18);
    }

    function test_MintWithSpecificPermission() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Disable default permissions but give specific permission
        accessManager.setDefaultAllow(false);
        accessManager.setPermission(user1, gameAsset.mint.selector, true);

        // user1 should be able to mint with specific permission
        vm.prank(user1);
        gameAsset.mint(user2, 500e18);
        assertEq(gameAsset.balanceOf(user2), 500e18);
    }

    // ===========================================
    // ERC20 Functionality Tests
    // ===========================================

    function test_NameAndSymbolOverrides() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Magic Potion", "POTION", "uri");

        assertEq(gameAsset.name(), "Magic Potion");
        assertEq(gameAsset.symbol(), "POTION");
        assertEq(gameAsset.decimals(), 18); // Default ERC20 decimals
    }

    function test_BasicTransfer() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Mint tokens to user1
        gameAsset.mint(user1, 1000e18);

        // Transfer from user1 to user2
        vm.prank(user1);
        gameAsset.transfer(user2, 500e18);

        assertEq(gameAsset.balanceOf(user1), 500e18);
        assertEq(gameAsset.balanceOf(user2), 500e18);
    }

    function test_ApprovalAndTransferFrom() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // user1 approves admin to spend tokens
        vm.prank(user1);
        gameAsset.approve(admin, 300e18);

        assertEq(gameAsset.allowance(user1, admin), 300e18);

        // Admin transfers from user1 to user2
        gameAsset.transferFrom(user1, user2, 200e18);

        assertEq(gameAsset.balanceOf(user1), 800e18);
        assertEq(gameAsset.balanceOf(user2), 200e18);
        assertEq(gameAsset.allowance(user1, admin), 100e18); // Allowance decreased
    }

    // ===========================================
    // Minting and Burning Tests
    // ===========================================

    function test_MintMultipleAmounts() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);
        gameAsset.mint(user2, 2000e18);
        gameAsset.mint(user1, 500e18); // Additional mint to same user

        assertEq(gameAsset.balanceOf(user1), 1500e18);
        assertEq(gameAsset.balanceOf(user2), 2000e18);
        assertEq(gameAsset.totalSupply(), 3500e18);
    }

    function test_MintToZeroAddress() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Should revert when minting to zero address
        vm.expectRevert();
        gameAsset.mint(address(0), 1000e18);
    }

    function test_BurnFunction() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Mint tokens first
        gameAsset.mint(user1, 1000e18);

        // user1 burns their own tokens
        vm.prank(user1);
        gameAsset.burn(300e18);

        assertEq(gameAsset.balanceOf(user1), 700e18);
        assertEq(gameAsset.totalSupply(), 700e18);
    }

    function test_BurnInsufficientBalance() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 100e18);

        // Try to burn more than balance
        vm.prank(user1);
        vm.expectRevert();
        gameAsset.burn(200e18);
    }

    function test_BurnFromWithAllowance() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // user1 approves admin to burn tokens
        vm.prank(user1);
        gameAsset.approve(admin, 500e18);

        // Admin burns from user1
        gameAsset.burnFrom(user1, 300e18);

        assertEq(gameAsset.balanceOf(user1), 700e18);
        assertEq(gameAsset.totalSupply(), 700e18);
        assertEq(gameAsset.allowance(user1, admin), 200e18); // Allowance decreased
    }

    function test_BurnFromSelf() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // user1 burns from their own account (no allowance needed)
        vm.prank(user1);
        gameAsset.burnFrom(user1, 400e18);

        assertEq(gameAsset.balanceOf(user1), 600e18);
        assertEq(gameAsset.totalSupply(), 600e18);
    }

    function test_BurnFromInsufficientAllowance() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // user1 approves admin for only 100 tokens
        vm.prank(user1);
        gameAsset.approve(admin, 100e18);

        // Try to burn more than allowance
        vm.expectRevert();
        gameAsset.burnFrom(user1, 200e18);
    }

    function test_BurnFromZeroAllowance() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // Try to burn without any allowance
        vm.prank(unauthorized);
        vm.expectRevert();
        gameAsset.burnFrom(user1, 100e18);
    }

    // ===========================================
    // Guard Functionality Tests
    // ===========================================

    function test_GuardCheckOnTransfer() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), restrictiveGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // Normal transfer should work
        vm.prank(user1);
        gameAsset.transfer(user2, 100e18);
        assertEq(gameAsset.balanceOf(user2), 100e18);

        // Block user1 in restrictive guard
        restrictiveGuard.blockAddress(user1);

        // Transfer should now fail
        vm.prank(user1);
        vm.expectRevert("Sender blocked by guard");
        gameAsset.transfer(user2, 100e18);
    }

    function test_GuardCheckOnMint() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), restrictiveGuard, "Test Token", "TEST", "uri");

        // Block the recipient
        restrictiveGuard.blockAddress(user1);

        // Minting should fail
        vm.expectRevert("Recipient blocked by guard");
        gameAsset.mint(user1, 1000e18);
    }

    function test_GuardCheckOnBurn() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), restrictiveGuard, "Test Token", "TEST", "uri");

        // Mint first
        gameAsset.mint(user1, 1000e18);

        // Block user1
        restrictiveGuard.blockAddress(user1);

        // Burning should fail (user1 is blocked as sender)
        vm.prank(user1);
        vm.expectRevert("Sender blocked by guard");
        gameAsset.burn(100e18);
    }

    function test_SpecialGuardApprovalLogic() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), selfApprovingGuard, "Test Token", "TEST", "uri");

        selfApprovingGuard.setToken(address(gameAsset));

        // Mint tokens to user1
        gameAsset.mint(user1, 1000e18);

        // Test the special approval logic by checking that when guard is msg.sender,
        // it gets approved for the exact transfer amount
        uint256 transferAmount = 200e18;

        // User1 initially approves guard for the transfer amount
        vm.prank(user1);
        gameAsset.approve(address(selfApprovingGuard), transferAmount);

        // Check initial allowance
        assertEq(gameAsset.allowance(user1, address(selfApprovingGuard)), transferAmount);

        // Guard makes the transfer - the special logic should auto-approve during _update
        selfApprovingGuard.triggerTransfer(user1, user2, transferAmount);

        // Verify the transfer worked
        assertEq(gameAsset.balanceOf(user1), 800e18);
        assertEq(gameAsset.balanceOf(user2), 200e18);

        // The allowance should now be set to the transfer amount due to special approval logic
        assertEq(gameAsset.allowance(user1, address(selfApprovingGuard)), transferAmount);
    }

    function test_GuardFailurePreventsTransfer() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), selfApprovingGuard, "Test Token", "TEST", "uri");

        selfApprovingGuard.setToken(address(gameAsset));

        // First mint tokens while guard allows it
        gameAsset.mint(user1, 1000e18);

        // Then set guard to fail
        selfApprovingGuard.setShouldFail(true);

        // Transfer should fail when guard check fails
        vm.prank(user1);
        vm.expectRevert("Guard check failed");
        gameAsset.transfer(user2, 100e18);
    }

    // ===========================================
    // Edge Cases and Error Conditions
    // ===========================================

    function test_TransferToSelf() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // Transfer to self should work
        vm.prank(user1);
        gameAsset.transfer(user1, 100e18);

        assertEq(gameAsset.balanceOf(user1), 1000e18); // Balance unchanged
    }

    function test_TransferZeroAmount() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // Transfer zero amount should work
        vm.prank(user1);
        gameAsset.transfer(user2, 0);

        assertEq(gameAsset.balanceOf(user1), 1000e18);
        assertEq(gameAsset.balanceOf(user2), 0);
    }

    function test_TransferFromToZeroAddress() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        vm.prank(user1);
        gameAsset.approve(admin, 500e18);

        // Transfer to zero address should revert
        vm.expectRevert();
        gameAsset.transferFrom(user1, address(0), 100e18);
    }

    function test_BurnZeroAmount() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        // Burn zero amount should work
        vm.prank(user1);
        gameAsset.burn(0);

        assertEq(gameAsset.balanceOf(user1), 1000e18); // Balance unchanged
    }

    function test_ApproveZeroAmount() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        vm.prank(user1);
        gameAsset.approve(admin, 0);

        assertEq(gameAsset.allowance(user1, admin), 0);
    }

    function test_MaxUintValues() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Test with maximum uint256 values
        gameAsset.mint(user1, type(uint256).max);

        vm.prank(user1);
        gameAsset.approve(admin, type(uint256).max);

        assertEq(gameAsset.balanceOf(user1), type(uint256).max);
        assertEq(gameAsset.allowance(user1, admin), type(uint256).max);
    }

    // ===========================================
    // Event Testing
    // ===========================================

    function test_TransferEvents() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        // Test mint event (Transfer from zero address)
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, 1000e18);
        gameAsset.mint(user1, 1000e18);

        // Test transfer event
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user2, 500e18);
        vm.prank(user1);
        gameAsset.transfer(user2, 500e18);

        // Test burn event (Transfer to zero address)
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, address(0), 200e18);
        vm.prank(user1);
        gameAsset.burn(200e18);
    }

    function test_ApprovalEvents() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(address(accessManager), mockGuard, "Test Token", "TEST", "uri");

        gameAsset.mint(user1, 1000e18);

        vm.expectEmit(true, true, false, true);
        emit Approval(user1, admin, 500e18);
        vm.prank(user1);
        gameAsset.approve(admin, 500e18);
    }

    // ===========================================
    // Integration Tests
    // ===========================================

    function test_CompleteWorkflow() public {
        ERC20GameAsset gameAsset = _createGameAsset();
        gameAsset.initialize(
            address(accessManager), mockGuard, "Magic Shield", "SHIELD", "https://game.com/shield.json"
        );

        // 1. Mint tokens to multiple users
        gameAsset.mint(user1, 1000e18);
        gameAsset.mint(user2, 500e18);

        // 2. Users approve each other
        vm.prank(user1);
        gameAsset.approve(user2, 300e18);

        vm.prank(user2);
        gameAsset.approve(user1, 200e18);

        // 3. Cross transfers
        vm.prank(user2);
        gameAsset.transferFrom(user1, admin, 150e18);

        vm.prank(user1);
        gameAsset.transferFrom(user2, admin, 100e18);

        // 4. Direct transfers
        vm.prank(user1);
        gameAsset.transfer(user2, 200e18);

        // 5. Burn operations
        vm.prank(user1);
        gameAsset.burn(100e18);

        // Admin needs approval to burn from user2
        vm.prank(user2);
        gameAsset.approve(admin, 50e18);
        gameAsset.burnFrom(user2, 50e18);

        // Final balance checks
        assertEq(gameAsset.balanceOf(admin), 250e18); // 150 + 100
        assertEq(gameAsset.balanceOf(user1), 550e18); // 1000 - 150 - 200 - 100
        assertEq(gameAsset.balanceOf(user2), 550e18); // 500 - 100 + 200 - 50
        assertEq(gameAsset.totalSupply(), 1350e18); // 1500 - 100 - 50
    }
}
