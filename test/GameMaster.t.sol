// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/GameMaster.sol";
import "../src/PlayerStats.sol";
import "../src/GameStats.sol";
import "../src/interfaces/IERC20MintableBurnable.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockMintableBurnableToken
 * @dev Mock ERC20 token that supports minting and burning
 */
contract MockMintableBurnableToken is ERC20, IERC20MintableBurnable {
    bool public shouldFailBurn = false;
    bool public shouldFailMint = false;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external override {
        require(!shouldFailMint, "Mint failed");
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        require(!shouldFailBurn, "Burn failed");
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external override {
        require(!shouldFailBurn, "Burn failed");
        _burn(from, amount);
    }

    function setShouldFailBurn(bool _shouldFail) external {
        shouldFailBurn = _shouldFail;
    }

    function setShouldFailMint(bool _shouldFail) external {
        shouldFailMint = _shouldFail;
    }
}

/**
 * @title MockNonBurnableToken
 * @dev Mock ERC20 token that does not support burning (for fallback testing)
 */
contract MockNonBurnableToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockReentrantToken
 * @dev Mock token that attempts reentrancy on transfer
 */
contract MockReentrantToken is ERC20, IERC20MintableBurnable {
    GameMaster public gameMaster;
    bool public shouldReentrancy = false;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function setGameMaster(address _gameMaster) external {
        gameMaster = GameMaster(_gameMaster);
    }

    function setShouldReentrancy(bool _shouldReentrancy) external {
        shouldReentrancy = _shouldReentrancy;
    }

    function mint(address to, uint256 amount) external override {
        _mint(to, amount);
        if (shouldReentrancy && address(gameMaster) != address(0)) {
            // Attempt reentrancy during mint
            try gameMaster.deposit(IERC20(address(this)), 1) {} catch {}
        }
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
        if (shouldReentrancy && address(gameMaster) != address(0)) {
            // Attempt reentrancy during burn
            try gameMaster.deposit(IERC20(address(this)), 1) {} catch {}
        }
    }

    function burnFrom(address from, uint256 amount) external override {
        _burn(from, amount);
        if (shouldReentrancy && address(gameMaster) != address(0)) {
            // Attempt reentrancy during burnFrom
            try gameMaster.deposit(IERC20(address(this)), 1) {} catch {}
        }
    }

    function transfer(address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (shouldReentrancy && address(gameMaster) != address(0)) {
            // Attempt reentrancy on deposit
            try gameMaster.deposit(IERC20(address(this)), 1) {} catch {}
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (shouldReentrancy && address(gameMaster) != address(0)) {
            // Attempt reentrancy on deposit
            try gameMaster.deposit(IERC20(address(this)), 1) {} catch {}
        }
        return super.transferFrom(from, to, amount);
    }
}

/**
 * @title GameMasterTest
 * @dev Comprehensive test suite for GameMaster contract with 100% coverage
 */
contract GameMasterTest is Test {
    GameMaster public gameMaster;
    AccessManager public accessManager;
    PlayerStats public playerStats;
    GameStats public gameStats;
    MockMintableBurnableToken public burnableToken;
    MockNonBurnableToken public nonBurnableToken;
    MockReentrantToken public reentrantToken;

    address public admin = address(0x1);
    address public authorized = address(0x2);
    address public unauthorized = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    // Constants
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Events to test
    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 burned);
    event WithdrawalRateLimitUpdated(uint256 indexed oldLimit, uint256 indexed newLimit);

    function setUp() public {
        // Deploy access manager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy PlayerStats and GameStats
        vm.prank(admin);
        playerStats = new PlayerStats(address(accessManager));

        vm.prank(admin);
        gameStats = new GameStats(address(accessManager));

        // Deploy GameMaster
        gameMaster = new GameMaster(address(accessManager), playerStats, gameStats);

        // Deploy test tokens
        burnableToken = new MockMintableBurnableToken("Burnable Token", "BURN");
        nonBurnableToken = new MockNonBurnableToken("Non-Burnable Token", "NOBURN");
        reentrantToken = new MockReentrantToken("Reentrant Token", "RENT");

        // Setup access control
        vm.startPrank(admin);
        uint64 roleId = accessManager.ADMIN_ROLE();
        accessManager.grantRole(roleId, authorized, 0);

        // Set function roles for restricted functions
        bytes4[] memory spendSelector = new bytes4[](1);
        spendSelector[0] = bytes4(keccak256("spendBalance(address,address,uint256)"));
        accessManager.setTargetFunctionRole(address(gameMaster), spendSelector, roleId);

        bytes4[] memory addSelector = new bytes4[](1);
        addSelector[0] = bytes4(keccak256("addBalance(address,address,uint256)"));
        accessManager.setTargetFunctionRole(address(gameMaster), addSelector, roleId);

        bytes4[] memory transferSelector = new bytes4[](1);
        transferSelector[0] = bytes4(keccak256("transferBalance(address,address,address,uint256)"));
        accessManager.setTargetFunctionRole(address(gameMaster), transferSelector, roleId);

        bytes4[] memory pauseSelector = new bytes4[](1);
        pauseSelector[0] = bytes4(keccak256("pause()"));
        accessManager.setTargetFunctionRole(address(gameMaster), pauseSelector, roleId);

        bytes4[] memory unpauseSelector = new bytes4[](1);
        unpauseSelector[0] = bytes4(keccak256("unpause()"));
        accessManager.setTargetFunctionRole(address(gameMaster), unpauseSelector, roleId);

        // Grant GameMaster permission to call PlayerStats and GameStats functions
        // First grant the GameMaster contract the ADMIN_ROLE
        accessManager.grantRole(roleId, address(gameMaster), 0);

        bytes4[] memory playerStatsSelectors = new bytes4[](8);
        playerStatsSelectors[0] = bytes4(keccak256("recordDeposit(address,address,uint256)"));
        playerStatsSelectors[1] = bytes4(keccak256("recordWithdrawal(address,address,uint256,uint256)"));
        playerStatsSelectors[2] = bytes4(keccak256("recordRecruitment(address,uint256,uint256)"));
        playerStatsSelectors[3] = bytes4(keccak256("recordSeizeAttempt(address,address,bool,uint256,address)"));
        playerStatsSelectors[4] = bytes4(keccak256("recordAbandon(address,address)"));
        playerStatsSelectors[5] = bytes4(keccak256("recordClaim(address,address,uint256)"));
        playerStatsSelectors[6] = bytes4(keccak256("recordDefenseBoost(address,address)"));
        playerStatsSelectors[7] = bytes4(keccak256("recordCombatStats(address,uint256,uint256,uint256)"));
        accessManager.setTargetFunctionRole(address(playerStats), playerStatsSelectors, roleId);

        bytes4[] memory gameStatsSelectors = new bytes4[](6);
        gameStatsSelectors[0] = bytes4(keccak256("recordGlobalDeposit(address,address,uint256)"));
        gameStatsSelectors[1] = bytes4(keccak256("recordGlobalWithdrawal(address,address,uint256,uint256)"));
        gameStatsSelectors[2] = bytes4(keccak256("recordGlobalRecruitment(address,uint256,uint256)"));
        gameStatsSelectors[3] = bytes4(keccak256("recordGlobalSeize(address,bool,uint256,uint256)"));
        gameStatsSelectors[4] = bytes4(keccak256("recordGlobalAbandon(address)"));
        gameStatsSelectors[5] = bytes4(keccak256("recordGlobalClaim(address,address,uint256)"));
        accessManager.setTargetFunctionRole(address(gameStats), gameStatsSelectors, roleId);
        vm.stopPrank();

        // Mint tokens to users for testing
        burnableToken.mint(user1, 1000e18);
        burnableToken.mint(user2, 1000e18);
        nonBurnableToken.mint(user1, 1000e18);
        nonBurnableToken.mint(user2, 1000e18);
        reentrantToken.mint(user1, 1000e18);

        // Set up reentrancy token
        reentrantToken.setGameMaster(address(gameMaster));
    }

    // Helper function to disable rate limiting for legacy tests
    function _disableRateLimit() internal {
        vm.prank(admin);
        gameMaster.setWithdrawalRateLimit(0); // Disable rate limiting
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        // Check that access manager is set correctly
        assertEq(gameMaster.authority(), address(accessManager));
        // Check that stats contracts are set correctly
        assertEq(address(gameMaster.PLAYER_STATS()), address(playerStats));
        assertEq(address(gameMaster.GAME_STATS()), address(gameStats));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_Success() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);

        // Expect Deposited event
        vm.expectEmit(true, true, false, true);
        emit Deposited(user1, address(burnableToken), depositAmount);

        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Check balances
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount);
        assertEq(burnableToken.balanceOf(address(gameMaster)), depositAmount);
        assertEq(burnableToken.balanceOf(user1), 1000e18 - depositAmount);

        // Verify statistics were recorded
        assertEq(
            playerStats.getTotalDeposited(user1, IERC20(address(burnableToken))),
            depositAmount,
            "Player stats not recorded"
        );
        assertEq(playerStats.getDepositCount(user1), 1, "Player deposit count not recorded");
        assertEq(gameStats.getTotalDeposited(IERC20(address(burnableToken))), depositAmount, "Game stats not recorded");
        assertEq(gameStats.getTotalDepositTransactions(), 1, "Game deposit transaction count not recorded");
    }

    function test_Deposit_Multiple() public {
        uint256 firstDeposit = 50e18;
        uint256 secondDeposit = 75e18;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), firstDeposit + secondDeposit);

        gameMaster.deposit(IERC20(address(burnableToken)), firstDeposit);
        gameMaster.deposit(IERC20(address(burnableToken)), secondDeposit);
        vm.stopPrank();

        // Check accumulated balance
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), firstDeposit + secondDeposit);
    }

    function test_Deposit_DifferentTokens() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        nonBurnableToken.approve(address(gameMaster), depositAmount);

        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        gameMaster.deposit(IERC20(address(nonBurnableToken)), depositAmount);
        vm.stopPrank();

        // Check balances for different tokens
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount);
        assertEq(gameMaster.getBalance(user1, IERC20(address(nonBurnableToken))), depositAmount);
    }

    function test_Deposit_RevertOnZeroAmount() public {
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), 1000e18);

        vm.expectRevert("Amount must be greater than 0");
        gameMaster.deposit(IERC20(address(burnableToken)), 0);
        vm.stopPrank();
    }

    function test_Deposit_RevertOnInsufficientAllowance() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        // Don't approve or approve less than needed
        burnableToken.approve(address(gameMaster), depositAmount - 1);

        vm.expectRevert();
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();
    }

    function test_Deposit_RevertOnInsufficientBalance() public {
        uint256 depositAmount = 2000e18; // More than user has

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);

        vm.expectRevert();
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();
    }

    function test_Deposit_ReentrancyProtection() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        reentrantToken.approve(address(gameMaster), depositAmount);
        reentrantToken.setShouldReentrancy(true);

        // Should not revert due to reentrancy guard
        gameMaster.deposit(IERC20(address(reentrantToken)), depositAmount);
        vm.stopPrank();

        // Check that deposit still worked
        assertEq(gameMaster.getBalance(user1, IERC20(address(reentrantToken))), depositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw_SuccessWithBurn() public {
        _disableRateLimit();
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 80e18;

        // First deposit
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        uint256 expectedWithdraw = withdrawAmount / 2;
        uint256 expectedBurn = withdrawAmount - expectedWithdraw;
        uint256 initialBalance = burnableToken.balanceOf(user1);

        vm.startPrank(user1);

        // Expect Withdrawn event
        vm.expectEmit(true, true, false, true);
        emit Withdrawn(user1, address(burnableToken), expectedWithdraw, expectedBurn);

        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);
        vm.stopPrank();

        // Check balances
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount - withdrawAmount);
        assertEq(burnableToken.balanceOf(user1), initialBalance + expectedWithdraw);
        // Check that tokens were burned (total supply decreased)
        assertEq(burnableToken.balanceOf(address(gameMaster)), depositAmount - withdrawAmount);

        // Verify statistics were recorded
        assertEq(
            playerStats.getTotalWithdrawn(user1, IERC20(address(burnableToken))),
            expectedWithdraw,
            "Player withdrawal stats not recorded"
        );
        assertEq(
            playerStats.getTotalBurned(user1, IERC20(address(burnableToken))),
            expectedBurn,
            "Player burn stats not recorded"
        );
        assertEq(playerStats.getWithdrawalCount(user1), 1, "Player withdrawal count not recorded");
        assertEq(
            gameStats.getTotalWithdrawn(IERC20(address(burnableToken))),
            expectedWithdraw,
            "Game withdrawal stats not recorded"
        );
        assertEq(gameStats.getTotalBurned(IERC20(address(burnableToken))), expectedBurn, "Game burn stats not recorded");
        assertEq(gameStats.getTotalWithdrawalTransactions(), 1, "Game withdrawal transaction count not recorded");
    }

    function test_Withdraw_SuccessWithDeadAddress() public {
        _disableRateLimit();
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 80e18;

        // First deposit
        vm.startPrank(user1);
        nonBurnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(nonBurnableToken)), depositAmount);
        vm.stopPrank();

        uint256 expectedWithdraw = withdrawAmount / 2;
        uint256 expectedBurn = withdrawAmount - expectedWithdraw;
        uint256 initialBalance = nonBurnableToken.balanceOf(user1);
        uint256 initialDeadBalance = nonBurnableToken.balanceOf(DEAD_ADDRESS);

        vm.startPrank(user1);
        gameMaster.withdraw(IERC20(address(nonBurnableToken)), withdrawAmount);
        vm.stopPrank();

        // Check balances
        assertEq(gameMaster.getBalance(user1, IERC20(address(nonBurnableToken))), depositAmount - withdrawAmount);
        assertEq(nonBurnableToken.balanceOf(user1), initialBalance + expectedWithdraw);
        assertEq(nonBurnableToken.balanceOf(DEAD_ADDRESS), initialDeadBalance + expectedBurn);
    }

    function test_Withdraw_SuccessWithBurnFail() public {
        _disableRateLimit();
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 80e18;

        // First deposit
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Make burn fail
        burnableToken.setShouldFailBurn(true);

        uint256 expectedWithdraw = withdrawAmount / 2;
        uint256 expectedBurn = withdrawAmount - expectedWithdraw;
        uint256 initialBalance = burnableToken.balanceOf(user1);
        uint256 initialDeadBalance = burnableToken.balanceOf(DEAD_ADDRESS);

        vm.startPrank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);
        vm.stopPrank();

        // Check balances - should fallback to dead address
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount - withdrawAmount);
        assertEq(burnableToken.balanceOf(user1), initialBalance + expectedWithdraw);
        assertEq(burnableToken.balanceOf(DEAD_ADDRESS), initialDeadBalance + expectedBurn);
    }

    function test_Withdraw_FullBalance() public {
        _disableRateLimit();
        uint256 depositAmount = 100e18;

        // First deposit
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);

        gameMaster.withdraw(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Check that balance is zero
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), 0);
    }

    function test_Withdraw_OddAmount() public {
        _disableRateLimit();
        uint256 depositAmount = 101e18; // Odd number
        uint256 withdrawAmount = 101e18;

        // First deposit
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);

        uint256 expectedWithdraw = withdrawAmount / 2; // 50e18
        uint256 expectedBurn = withdrawAmount - expectedWithdraw; // 51e18
        uint256 initialBalance = burnableToken.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit Withdrawn(user1, address(burnableToken), expectedWithdraw, expectedBurn);

        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);
        vm.stopPrank();

        assertEq(burnableToken.balanceOf(user1), initialBalance + expectedWithdraw);
    }

    function test_Withdraw_RevertOnZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("Amount must be greater than 0");
        gameMaster.withdraw(IERC20(address(burnableToken)), 0);
        vm.stopPrank();
    }

    function test_Withdraw_RevertOnInsufficientBalance() public {
        uint256 depositAmount = 50e18;
        uint256 withdrawAmount = 100e18;

        // First deposit less than withdraw amount
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);

        vm.expectRevert("Insufficient balance");
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);
        vm.stopPrank();
    }

    function test_Withdraw_RevertOnNoBalance() public {
        vm.startPrank(user1);
        vm.expectRevert("Insufficient balance");
        gameMaster.withdraw(IERC20(address(burnableToken)), 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            GET BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetBalance_InitiallyZero() public view {
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), 0);
        assertEq(gameMaster.getBalance(user2, IERC20(address(nonBurnableToken))), 0);
    }

    function test_GetBalance_AfterDeposit() public {
        uint256 depositAmount = 123e18;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount);
        assertEq(gameMaster.getBalance(user2, IERC20(address(burnableToken))), 0); // Different user
        assertEq(gameMaster.getBalance(user1, IERC20(address(nonBurnableToken))), 0); // Different token
    }

    /*//////////////////////////////////////////////////////////////
                        SPEND BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SpendBalance_Success() public {
        uint256 depositAmount = 100e18;
        uint256 spendAmount = 30e18;

        // Setup: deposit tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        uint256 initialSupply = burnableToken.totalSupply();

        // Authorized contract spends balance
        vm.prank(authorized);
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), spendAmount);

        // Check balances
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount - spendAmount);
        assertEq(burnableToken.totalSupply(), initialSupply - spendAmount); // Tokens burned
        assertEq(burnableToken.balanceOf(address(gameMaster)), depositAmount - spendAmount);
    }

    function test_SpendBalance_RevertOnUnauthorized() public {
        uint256 depositAmount = 100e18;
        uint256 spendAmount = 30e18;

        // Setup: deposit tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Unauthorized call should revert
        vm.prank(unauthorized);
        vm.expectRevert();
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), spendAmount);
    }

    function test_SpendBalance_RevertOnInsufficientBalance() public {
        uint256 depositAmount = 50e18;
        uint256 spendAmount = 100e18;

        // Setup: deposit tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Spend more than available - should now revert with our custom error
        vm.prank(authorized);
        vm.expectRevert("Insufficient balance");
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), spendAmount);
    }

    function test_SpendBalance_RevertOnBurnFailure() public {
        uint256 depositAmount = 100e18;
        uint256 spendAmount = 30e18;

        // Setup: deposit tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Make burn fail
        burnableToken.setShouldFailBurn(true);

        // Should revert when burn fails
        vm.prank(authorized);
        vm.expectRevert("Burn failed");
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), spendAmount);
    }

    /*//////////////////////////////////////////////////////////////
                         ADD BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddBalance_Success() public {
        uint256 addAmount = 50e18;
        uint256 initialSupply = burnableToken.totalSupply();

        // Authorized contract adds balance
        vm.prank(authorized);
        gameMaster.addBalance(user1, IERC20(address(burnableToken)), addAmount);

        // Check balances
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), addAmount);
        assertEq(burnableToken.totalSupply(), initialSupply + addAmount); // Tokens minted
        assertEq(burnableToken.balanceOf(address(gameMaster)), addAmount);
    }

    function test_AddBalance_MultipleAdds() public {
        uint256 firstAdd = 30e18;
        uint256 secondAdd = 20e18;

        vm.startPrank(authorized);
        gameMaster.addBalance(user1, IERC20(address(burnableToken)), firstAdd);
        gameMaster.addBalance(user1, IERC20(address(burnableToken)), secondAdd);
        vm.stopPrank();

        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), firstAdd + secondAdd);
    }

    function test_AddBalance_RevertOnUnauthorized() public {
        uint256 addAmount = 50e18;

        vm.prank(unauthorized);
        vm.expectRevert();
        gameMaster.addBalance(user1, IERC20(address(burnableToken)), addAmount);
    }

    function test_AddBalance_RevertOnMintFailure() public {
        uint256 addAmount = 50e18;

        // Make mint fail
        burnableToken.setShouldFailMint(true);

        vm.prank(authorized);
        vm.expectRevert("Mint failed");
        gameMaster.addBalance(user1, IERC20(address(burnableToken)), addAmount);
    }

    /*//////////////////////////////////////////////////////////////
                      TRANSFER BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferBalance_Success() public {
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 40e18;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Authorized contract transfers balance
        vm.prank(authorized);
        gameMaster.transferBalance(user1, user2, IERC20(address(burnableToken)), transferAmount);

        // Check balances
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount - transferAmount);
        assertEq(gameMaster.getBalance(user2, IERC20(address(burnableToken))), transferAmount);
        assertEq(burnableToken.balanceOf(address(gameMaster)), depositAmount); // Total unchanged
    }

    function test_TransferBalance_FullBalance() public {
        uint256 depositAmount = 100e18;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Transfer full balance
        vm.prank(authorized);
        gameMaster.transferBalance(user1, user2, IERC20(address(burnableToken)), depositAmount);

        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), 0);
        assertEq(gameMaster.getBalance(user2, IERC20(address(burnableToken))), depositAmount);
    }

    function test_TransferBalance_RevertOnUnauthorized() public {
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 40e18;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        vm.prank(unauthorized);
        vm.expectRevert();
        gameMaster.transferBalance(user1, user2, IERC20(address(burnableToken)), transferAmount);
    }

    function test_TransferBalance_RevertOnInsufficientBalance() public {
        uint256 depositAmount = 50e18;
        uint256 transferAmount = 100e18;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        vm.prank(authorized);
        vm.expectRevert();
        gameMaster.transferBalance(user1, user2, IERC20(address(burnableToken)), transferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        TOTAL MISMATCH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CheckTotal_PassesWhenBalanceMatches() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // This should not revert as totals match
        assertEq(burnableToken.balanceOf(address(gameMaster)), depositAmount);
    }

    function test_CheckTotal_PassesWhenTokensSentDirectly() public {
        _disableRateLimit();
        uint256 depositAmount = 100e18;
        uint256 directAmount = 50e18;

        // Normal deposit
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Send tokens directly to GameMaster (should be allowed but not recommended)
        burnableToken.mint(address(gameMaster), directAmount);

        // Contract balance should be higher than internal total, which is allowed
        assertGt(burnableToken.balanceOf(address(gameMaster)), depositAmount);

        // Withdraw should still work
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), depositAmount);
    }

    function test_CheckTotal_RevertOnTotalMismatch() public {
        uint256 depositAmount = 100e18;

        // Setup: deposit tokens
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Simulate a scenario where contract balance becomes less than internal total
        // This shouldn't happen in normal operation, but we need to test the check
        // We'll transfer tokens out of the GameMaster contract directly to create this scenario
        vm.prank(address(gameMaster));
        burnableToken.transfer(address(0xdead), depositAmount - 1);

        // Now internal total (100e18) > contract balance (1), so _checkTotal should fail
        // Any operation that calls _checkTotal should revert
        vm.prank(authorized);
        vm.expectRevert("Total mismatch");
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleUsersAndTokens() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 200e18;

        // User1 deposits burnable token
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), amount1);
        gameMaster.deposit(IERC20(address(burnableToken)), amount1);
        vm.stopPrank();

        // User2 deposits non-burnable token
        vm.startPrank(user2);
        nonBurnableToken.approve(address(gameMaster), amount2);
        gameMaster.deposit(IERC20(address(nonBurnableToken)), amount2);
        vm.stopPrank();

        // Check isolated balances
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), amount1);
        assertEq(gameMaster.getBalance(user1, IERC20(address(nonBurnableToken))), 0);
        assertEq(gameMaster.getBalance(user2, IERC20(address(burnableToken))), 0);
        assertEq(gameMaster.getBalance(user2, IERC20(address(nonBurnableToken))), amount2);
    }

    function test_WithdrawAmountOfOne() public {
        _disableRateLimit();
        uint256 depositAmount = 3;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);

        // Withdraw amount of 1 should give 0 withdrawn, 1 burned
        uint256 withdrawAmount = 1;
        uint256 expectedWithdraw = withdrawAmount / 2; // 0
        uint256 expectedBurn = withdrawAmount - expectedWithdraw; // 1

        vm.expectEmit(true, true, false, true);
        emit Withdrawn(user1, address(burnableToken), expectedWithdraw, expectedBurn);

        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);
        vm.stopPrank();

        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount - withdrawAmount);
    }

    function test_ZeroBurnAndWithdrawAmounts() public {
        _disableRateLimit();
        // Test edge case where both burn and withdraw amounts are 0
        // This happens when withdrawing amount 0, but that's already tested to revert

        // Test the internal case where we might have 0 amounts due to calculation
        uint256 depositAmount = 1;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);

        // Withdrawing 1 will result in withdrawAmount = 0, burnAmount = 1
        gameMaster.withdraw(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), 0);
    }

    function test_Withdraw_ZeroBurnAmount() public {
        _disableRateLimit();
        // Test edge case where burnAmount = 0 (withdrawing amount 0 is already tested to revert)
        // This is impossible with current logic since amount must be > 0 and burnAmount = amount - withdrawAmount
        // where withdrawAmount = amount / 2, so burnAmount is always > 0 unless amount = 0
        // But let's test with amount = 1 which gives burnAmount = 1, withdrawAmount = 0
        uint256 depositAmount = 1;

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);

        uint256 initialUserBalance = burnableToken.balanceOf(user1);

        // This should hit the case where withdrawAmount = 0 (so transfer branch isn't taken)
        gameMaster.withdraw(IERC20(address(burnableToken)), 1);
        vm.stopPrank();

        // User should get 0 tokens back (withdrawAmount = 0)
        assertEq(burnableToken.balanceOf(user1), initialUserBalance);
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SpendBalance_ReentrancyProtection() public {
        uint256 depositAmount = 100e18;
        uint256 spendAmount = 30e18;

        // Setup: deposit tokens
        vm.startPrank(user1);
        reentrantToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(reentrantToken)), depositAmount);
        vm.stopPrank();

        // Enable reentrancy attempts
        reentrantToken.setShouldReentrancy(true);

        // Should not revert due to reentrancy guard protecting spendBalance
        vm.prank(authorized);
        gameMaster.spendBalance(user1, IERC20(address(reentrantToken)), spendAmount);

        // Check that spend still worked
        assertEq(gameMaster.getBalance(user1, IERC20(address(reentrantToken))), depositAmount - spendAmount);
    }

    function test_AddBalance_ReentrancyProtection() public {
        uint256 addAmount = 50e18;

        // Enable reentrancy attempts
        reentrantToken.setShouldReentrancy(true);

        // Should not revert due to reentrancy guard protecting addBalance
        vm.prank(authorized);
        gameMaster.addBalance(user1, IERC20(address(reentrantToken)), addAmount);

        // Check that add still worked
        assertEq(gameMaster.getBalance(user1, IERC20(address(reentrantToken))), addAmount);
    }

    function test_TransferBalance_ReentrancyProtection() public {
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 40e18;

        // Setup: user1 deposits tokens
        vm.startPrank(user1);
        reentrantToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(reentrantToken)), depositAmount);
        vm.stopPrank();

        // Enable reentrancy attempts
        reentrantToken.setShouldReentrancy(true);

        // Should not revert due to reentrancy guard protecting transferBalance
        vm.prank(authorized);
        gameMaster.transferBalance(user1, user2, IERC20(address(reentrantToken)), transferAmount);

        // Check that transfer still worked
        assertEq(gameMaster.getBalance(user1, IERC20(address(reentrantToken))), depositAmount - transferAmount);
        assertEq(gameMaster.getBalance(user2, IERC20(address(reentrantToken))), transferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSABLE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_Success() public {
        // Initially the contract should not be paused
        assertFalse(gameMaster.paused());

        // Authorized user should be able to pause
        vm.prank(authorized);
        gameMaster.pause();

        // Contract should now be paused
        assertTrue(gameMaster.paused());
    }

    function test_Unpause_Success() public {
        // First pause the contract
        vm.prank(authorized);
        gameMaster.pause();
        assertTrue(gameMaster.paused());

        // Authorized user should be able to unpause
        vm.prank(authorized);
        gameMaster.unpause();

        // Contract should no longer be paused
        assertFalse(gameMaster.paused());
    }

    function test_Pause_RevertOnUnauthorized() public {
        // Unauthorized user should not be able to pause
        vm.prank(unauthorized);
        vm.expectRevert();
        gameMaster.pause();
    }

    function test_Unpause_RevertOnUnauthorized() public {
        // First pause the contract with authorized user
        vm.prank(authorized);
        gameMaster.pause();

        // Unauthorized user should not be able to unpause
        vm.prank(unauthorized);
        vm.expectRevert();
        gameMaster.unpause();
    }

    function test_Deposit_WhenPaused() public {
        uint256 depositAmount = 100e18;

        // Pause the contract
        vm.prank(authorized);
        gameMaster.pause();

        // Deposit should revert when paused
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        vm.expectRevert();
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();
    }

    function test_Withdraw_WhenPaused() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // First deposit while not paused
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Pause the contract
        vm.prank(authorized);
        gameMaster.pause();

        // Withdraw should revert when paused
        vm.prank(user1);
        vm.expectRevert();
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);
    }

    function test_SpendBalance_WhenPaused() public {
        uint256 depositAmount = 100e18;
        uint256 spendAmount = 30e18;

        // First deposit while not paused
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Pause the contract
        vm.prank(authorized);
        gameMaster.pause();

        // SpendBalance should revert when paused
        vm.prank(authorized);
        vm.expectRevert();
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), spendAmount);
    }

    function test_AddBalance_WhenPaused() public {
        uint256 addAmount = 50e18;

        // Pause the contract
        vm.prank(authorized);
        gameMaster.pause();

        // AddBalance should revert when paused
        vm.prank(authorized);
        vm.expectRevert();
        gameMaster.addBalance(user1, IERC20(address(burnableToken)), addAmount);
    }

    function test_TransferBalance_WhenPaused() public {
        uint256 depositAmount = 100e18;
        uint256 transferAmount = 40e18;

        // First deposit while not paused
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Pause the contract
        vm.prank(authorized);
        gameMaster.pause();

        // TransferBalance should revert when paused
        vm.prank(authorized);
        vm.expectRevert();
        gameMaster.transferBalance(user1, user2, IERC20(address(burnableToken)), transferAmount);
    }

    function test_GetBalance_WhenPaused() public {
        uint256 depositAmount = 100e18;

        // First deposit while not paused
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Pause the contract
        vm.prank(authorized);
        gameMaster.pause();

        // GetBalance should still work when paused (view function)
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount);
    }

    function test_FullWorkflow_WithPauseUnpause() public {
        _disableRateLimit();
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // Initial deposit should work
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Pause the contract
        vm.prank(authorized);
        gameMaster.pause();

        // Operations should fail
        vm.prank(user1);
        vm.expectRevert();
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);

        // Unpause the contract
        vm.prank(authorized);
        gameMaster.unpause();

        // Operations should work again
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);

        // Check final balance
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount - withdrawAmount);
    }

    function test_EmergencyScenario() public {
        _disableRateLimit();
        uint256 depositAmount = 1000e18;

        // Multiple users deposit
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Emergency pause to stop all activity
        vm.prank(authorized);
        gameMaster.pause();

        // No operations should work
        vm.expectRevert();
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), 100e18);

        vm.expectRevert();
        vm.prank(user2);
        gameMaster.withdraw(IERC20(address(burnableToken)), 100e18);

        vm.expectRevert();
        vm.prank(authorized);
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), 100e18);

        // Balances should remain unchanged
        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount);
        assertEq(gameMaster.getBalance(user2, IERC20(address(burnableToken))), depositAmount);

        // After unpausing, operations work normally
        vm.prank(authorized);
        gameMaster.unpause();

        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), 100e18);

        assertEq(gameMaster.getBalance(user1, IERC20(address(burnableToken))), depositAmount - 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_DepositAndWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        _disableRateLimit();
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1, 1000e18);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Setup
        burnableToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);

        uint256 balanceBefore = gameMaster.getBalance(user1, IERC20(address(burnableToken)));
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);
        uint256 balanceAfter = gameMaster.getBalance(user1, IERC20(address(burnableToken)));
        vm.stopPrank();

        assertEq(balanceAfter, balanceBefore - withdrawAmount);
    }

    function testFuzz_SpendBalance(uint256 depositAmount, uint256 spendAmount) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 1, 1000e18);
        spendAmount = bound(spendAmount, 1, depositAmount);

        // Setup
        burnableToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        uint256 balanceBefore = gameMaster.getBalance(user1, IERC20(address(burnableToken)));

        vm.prank(authorized);
        gameMaster.spendBalance(user1, IERC20(address(burnableToken)), spendAmount);

        uint256 balanceAfter = gameMaster.getBalance(user1, IERC20(address(burnableToken)));
        assertEq(balanceAfter, balanceBefore - spendAmount);
    }

    function testFuzz_TransferBalance(uint256 depositAmount, uint256 transferAmount) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 1, 1000e18);
        transferAmount = bound(transferAmount, 1, depositAmount);

        // Setup
        burnableToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        uint256 balance1Before = gameMaster.getBalance(user1, IERC20(address(burnableToken)));
        uint256 balance2Before = gameMaster.getBalance(user2, IERC20(address(burnableToken)));

        vm.prank(authorized);
        gameMaster.transferBalance(user1, user2, IERC20(address(burnableToken)), transferAmount);

        uint256 balance1After = gameMaster.getBalance(user1, IERC20(address(burnableToken)));
        uint256 balance2After = gameMaster.getBalance(user2, IERC20(address(burnableToken)));

        assertEq(balance1After, balance1Before - transferAmount);
        assertEq(balance2After, balance2Before + transferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWAL RATE LIMITING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DefaultWithdrawalRateLimit() public view {
        // Default rate limit should be 100 basis points (1%)
        assertEq(gameMaster.withdrawalRateLimitBps(), 100);
    }

    function test_SetWithdrawalRateLimit_Success() public {
        uint256 newLimit = 500; // 5%

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit WithdrawalRateLimitUpdated(100, newLimit);
        gameMaster.setWithdrawalRateLimit(newLimit);

        assertEq(gameMaster.withdrawalRateLimitBps(), newLimit);
    }

    function test_SetWithdrawalRateLimit_RevertOnExceedingMax() public {
        vm.prank(admin);
        vm.expectRevert("Rate limit cannot exceed 100%");
        gameMaster.setWithdrawalRateLimit(10001); // > 100%
    }

    function test_SetWithdrawalRateLimit_RevertOnUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        gameMaster.setWithdrawalRateLimit(500);
    }

    function test_WithdrawalRateLimit_EnforcementBasic() public {
        uint256 depositAmount = 1000e18;
        uint256 rateLimitBps = 100; // 1% (default)

        // Deposit tokens
        burnableToken.mint(user1, depositAmount);
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Calculate rate limit: 1% of 1000e18 = 10e18
        uint256 rateLimit = (depositAmount * rateLimitBps) / 10000;

        // First withdrawal within limit should succeed
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), rateLimit);

        // Second withdrawal should fail (would exceed rate limit)
        vm.prank(user1);
        vm.expectRevert("Withdrawal rate limit exceeded");
        gameMaster.withdraw(IERC20(address(burnableToken)), 1);
    }

    function test_WithdrawalRateLimit_MultipleWithdrawalsAccumulation() public {
        uint256 depositAmount = 1000e18;
        uint256 rateLimitBps = 100; // 1% (default)

        // Deposit tokens
        burnableToken.mint(user1, depositAmount);
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Calculate initial rate limit: 1% of 1000e18 = 10e18
        uint256 firstWithdraw = 5e18; // 5e18

        // First withdrawal
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), firstWithdraw);

        // The rate limit is now based on current holdings: 995e18 * 1% = 9.95e18
        // But we already withdrew 5e18, so remaining = 9.95e18 - 5e18 = 4.95e18
        uint256 currentTotal = depositAmount - firstWithdraw; // 995e18
        uint256 currentRateLimit = (currentTotal * rateLimitBps) / 10000; // 9.95e18
        uint256 remainingInWindow = currentRateLimit - firstWithdraw; // 4.95e18

        // Second withdrawal should succeed if within remaining limit
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), remainingInWindow);

        // Third withdrawal should fail (exceeds window limit)
        vm.prank(user1);
        vm.expectRevert("Withdrawal rate limit exceeded");
        gameMaster.withdraw(IERC20(address(burnableToken)), 1);
    }

    function test_WithdrawalRateLimit_WindowReset() public {
        uint256 depositAmount = 1000e18;
        uint256 rateLimitBps = 100; // 1% (default)

        // Deposit tokens
        burnableToken.mint(user1, depositAmount);
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Calculate rate limit: 1% of 1000e18 = 10e18
        uint256 rateLimit = (depositAmount * rateLimitBps) / 10000;

        // Withdraw up to the limit
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), rateLimit);

        // Fast forward 24 hours + 1 second
        vm.warp(block.timestamp + 1 days + 1);

        // Now should be able to withdraw again (new window)
        // Note: need to recalculate limit based on new total held after previous withdrawal
        uint256 newTotalHeld = depositAmount - rateLimit;
        uint256 newRateLimit = (newTotalHeld * rateLimitBps) / 10000;

        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), newRateLimit);
    }

    function test_WithdrawalRateLimit_DifferentTokensSeparateTracking() public {
        uint256 depositAmount = 1000e18;
        uint256 rateLimitBps = 100; // 1% (default)

        // Deposit both tokens
        burnableToken.mint(user1, depositAmount);
        nonBurnableToken.mint(user1, depositAmount);

        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        nonBurnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        gameMaster.deposit(IERC20(address(nonBurnableToken)), depositAmount);
        vm.stopPrank();

        uint256 rateLimit = (depositAmount * rateLimitBps) / 10000;

        // Withdraw full limit from burnable token
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), rateLimit);

        // Should still be able to withdraw from non-burnable token (separate tracking)
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(nonBurnableToken)), rateLimit);

        // But no more from either token in this window
        vm.prank(user1);
        vm.expectRevert("Withdrawal rate limit exceeded");
        gameMaster.withdraw(IERC20(address(burnableToken)), 1);

        vm.prank(user1);
        vm.expectRevert("Withdrawal rate limit exceeded");
        gameMaster.withdraw(IERC20(address(nonBurnableToken)), 1);
    }

    function test_WithdrawalRateLimit_DisabledWhenZero() public {
        uint256 depositAmount = 1000e18;

        // Set rate limit to 0 (disabled)
        vm.prank(admin);
        gameMaster.setWithdrawalRateLimit(0);

        // Deposit tokens
        burnableToken.mint(user1, depositAmount);
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Should be able to withdraw the entire amount (no rate limiting)
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), depositAmount);
    }

    function test_GetWithdrawalWindowData() public {
        uint256 depositAmount = 1000e18;
        uint256 rateLimitBps = 100; // 1% (default)

        // Deposit tokens
        burnableToken.mint(user1, depositAmount);
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Check initial window data
        (uint256 windowStart, uint256 amountWithdrawn, uint256 rateLimit) =
            gameMaster.getWithdrawalWindowData(IERC20(address(burnableToken)));

        assertEq(windowStart, 0); // No window started yet
        assertEq(amountWithdrawn, 0);
        assertEq(rateLimit, (depositAmount * rateLimitBps) / 10000);

        // Make a withdrawal (within the 1% rate limit)
        uint256 withdrawAmount = 5e18; // Well within the 10e18 limit
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);

        // Check window data after withdrawal
        (windowStart, amountWithdrawn, rateLimit) = gameMaster.getWithdrawalWindowData(IERC20(address(burnableToken)));

        assertEq(windowStart, block.timestamp);
        assertEq(amountWithdrawn, withdrawAmount);
        // Rate limit is now based on remaining holdings after withdrawal
        uint256 remainingHoldings = depositAmount - withdrawAmount; // 995e18
        assertEq(rateLimit, (remainingHoldings * rateLimitBps) / 10000);
    }

    function test_GetWithdrawalWindowData_NoLimit() public {
        // Set rate limit to 0 (disabled)
        vm.prank(admin);
        gameMaster.setWithdrawalRateLimit(0);

        (,, uint256 rateLimit) = gameMaster.getWithdrawalWindowData(IERC20(address(burnableToken)));
        assertEq(rateLimit, type(uint256).max);
    }

    function test_WithdrawalRateLimit_ExactlyAtLimit() public {
        uint256 depositAmount = 1000e18;
        uint256 rateLimitBps = 100; // 1% (default)

        // Deposit tokens
        burnableToken.mint(user1, depositAmount);
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Calculate exact rate limit
        uint256 rateLimit = (depositAmount * rateLimitBps) / 10000;

        // Withdraw exactly at the limit should succeed
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), rateLimit);

        // One more wei should fail
        vm.prank(user1);
        vm.expectRevert("Withdrawal rate limit exceeded");
        gameMaster.withdraw(IERC20(address(burnableToken)), 1);
    }

    function test_WithdrawalRateLimit_UpdateDuringActiveWindow() public {
        uint256 depositAmount = 1000e18;
        uint256 newRateLimit = 500; // 5%

        // Deposit tokens
        burnableToken.mint(user1, depositAmount);
        vm.startPrank(user1);
        burnableToken.approve(address(gameMaster), depositAmount);
        gameMaster.deposit(IERC20(address(burnableToken)), depositAmount);
        vm.stopPrank();

        // Make a withdrawal to start the window
        uint256 withdrawAmount = 5e18; // Small amount within 1% limit
        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), withdrawAmount);

        // Change rate limit to be less restrictive (1% -> 5%)
        vm.prank(admin);
        gameMaster.setWithdrawalRateLimit(newRateLimit);

        // Check that new limit is applied immediately
        (,, uint256 currentLimit) = gameMaster.getWithdrawalWindowData(IERC20(address(burnableToken)));
        uint256 expectedNewLimit = ((depositAmount - withdrawAmount) * newRateLimit) / 10000;
        assertEq(currentLimit, expectedNewLimit);

        // Should be able to withdraw more since limit is now higher (5% vs 1%)
        uint256 remainingInNewLimit = expectedNewLimit - withdrawAmount;
        uint256 additionalWithdraw = remainingInNewLimit; // Use up the new higher limit

        vm.prank(user1);
        gameMaster.withdraw(IERC20(address(burnableToken)), additionalWithdraw);

        // Now should hit the limit
        vm.prank(user1);
        vm.expectRevert("Withdrawal rate limit exceeded");
        gameMaster.withdraw(IERC20(address(burnableToken)), 1);
    }
}
