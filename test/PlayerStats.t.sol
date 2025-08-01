// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/PlayerStats.sol";
import "../src/interfaces/IERC20MintableBurnable.sol";
import "@openzeppelin/contracts/access/manager/AccessManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @dev Mock ERC20 token for testing
 */
contract MockToken is ERC20, IERC20MintableBurnable {
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
 * @title PlayerStatsTest
 * @dev Comprehensive test suite for PlayerStats contract with 100% coverage
 */
contract PlayerStatsTest is Test {
    PlayerStats public playerStats;
    AccessManager public accessManager;
    MockToken public token1;
    MockToken public token2;
    MockToken public mercToken;

    address public admin = address(0x1);
    address public authorized = address(0x2);
    address public unauthorized = address(0x3);
    address public player1 = address(0x4);
    address public player2 = address(0x5);
    address public mine1 = address(0x6);
    address public mine2 = address(0x7);

    // Events to test
    event DepositRecorded(address indexed player, IERC20 indexed token, uint256 amount);
    event WithdrawalRecorded(address indexed player, IERC20 indexed token, uint256 amount, uint256 burned);
    event RecruitmentRecorded(address indexed player, uint256 level, uint256 amount);
    event SeizeAttemptRecorded(address indexed player, address indexed mine, bool success, uint256 attackPower);
    event AbandonRecorded(address indexed player, address indexed mine);
    event ClaimRecorded(address indexed player, IERC20 indexed resource, uint256 amount);
    event DefenseBoostRecorded(address indexed player, address indexed mine);
    event CombatStatsRecorded(address indexed player, uint256 mercsLost, uint256 mercsWon);

    function setUp() public {
        // Deploy access manager with admin
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy PlayerStats
        vm.prank(admin);
        playerStats = new PlayerStats(address(accessManager));

        // Deploy test tokens
        token1 = new MockToken("Token1", "TOK1");
        token2 = new MockToken("Token2", "TOK2");
        mercToken = new MockToken("Mercenary", "MERC");

        // Setup access control
        vm.startPrank(admin);
        uint64 roleId = accessManager.ADMIN_ROLE();
        accessManager.grantRole(roleId, authorized, 0);

        // Set function roles for restricted functions
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = bytes4(keccak256("recordDeposit(address,address,uint256)"));
        selectors[1] = bytes4(keccak256("recordWithdrawal(address,address,uint256,uint256)"));
        selectors[2] = bytes4(keccak256("recordRecruitment(address,uint256,uint256)"));
        selectors[3] = bytes4(keccak256("recordSeizeAttempt(address,address,bool,uint256,address)"));
        selectors[4] = bytes4(keccak256("recordAbandon(address,address)"));
        selectors[5] = bytes4(keccak256("recordClaim(address,address,uint256)"));
        selectors[6] = bytes4(keccak256("recordDefenseBoost(address,address)"));
        selectors[7] = bytes4(keccak256("recordCombatStats(address,uint256,uint256,uint256)"));
        accessManager.setTargetFunctionRole(address(playerStats), selectors, roleId);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        // Check that access manager is set correctly
        assertEq(playerStats.authority(), address(accessManager));

        // Check initial state
        assertEq(playerStats.getPlayerCount(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordDeposit_Success() public {
        uint256 amount = 100e18;

        vm.expectEmit(true, true, false, true);
        emit DepositRecorded(player1, IERC20(address(token1)), amount);

        vm.prank(authorized);
        playerStats.recordDeposit(player1, IERC20(address(token1)), amount);

        // Verify stats
        assertEq(playerStats.getTotalDeposited(player1, IERC20(address(token1))), amount);
        assertEq(playerStats.getDepositCount(player1), 1);
        assertEq(playerStats.getPlayerCount(), 1);
        assertTrue(playerStats.playerExists(player1));
    }

    function test_RecordDeposit_Multiple() public {
        uint256 amount1 = 100e18;
        uint256 amount2 = 50e18;

        vm.startPrank(authorized);
        playerStats.recordDeposit(player1, IERC20(address(token1)), amount1);
        playerStats.recordDeposit(player1, IERC20(address(token1)), amount2);
        playerStats.recordDeposit(player1, IERC20(address(token2)), amount1);
        vm.stopPrank();

        // Verify accumulated stats
        assertEq(playerStats.getTotalDeposited(player1, IERC20(address(token1))), amount1 + amount2);
        assertEq(playerStats.getTotalDeposited(player1, IERC20(address(token2))), amount1);
        assertEq(playerStats.getDepositCount(player1), 3);
        assertEq(playerStats.getPlayerCount(), 1); // Still one unique player
    }

    function test_RecordDeposit_MultiplePlayersUniqueTracking() public {
        uint256 amount = 100e18;

        vm.startPrank(authorized);
        playerStats.recordDeposit(player1, IERC20(address(token1)), amount);
        playerStats.recordDeposit(player2, IERC20(address(token1)), amount);
        vm.stopPrank();

        // Verify unique player tracking
        assertEq(playerStats.getPlayerCount(), 2);
        assertTrue(playerStats.playerExists(player1));
        assertTrue(playerStats.playerExists(player2));

        // Verify stats are separate
        assertEq(playerStats.getTotalDeposited(player1, IERC20(address(token1))), amount);
        assertEq(playerStats.getTotalDeposited(player2, IERC20(address(token1))), amount);
        assertEq(playerStats.getDepositCount(player1), 1);
        assertEq(playerStats.getDepositCount(player2), 1);
    }

    function test_RecordDeposit_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordDeposit(player1, IERC20(address(token1)), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                           WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordWithdrawal_Success() public {
        uint256 totalAmount = 100e18;
        uint256 burned = 50e18;
        uint256 received = totalAmount - burned;

        vm.expectEmit(true, true, false, true);
        emit WithdrawalRecorded(player1, IERC20(address(token1)), received, burned);

        vm.prank(authorized);
        playerStats.recordWithdrawal(player1, IERC20(address(token1)), totalAmount, burned);

        // Verify stats
        assertEq(playerStats.getTotalWithdrawn(player1, IERC20(address(token1))), received);
        assertEq(playerStats.getTotalBurned(player1, IERC20(address(token1))), burned);
        assertEq(playerStats.getWithdrawalCount(player1), 1);
        assertEq(playerStats.getPlayerCount(), 1);
    }

    function test_RecordWithdrawal_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordWithdrawal(player1, IERC20(address(token1)), 100e18, 50e18);
    }

    /*//////////////////////////////////////////////////////////////
                          RECRUITMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordRecruitment_Success() public {
        uint256 level = 2;
        uint256 amount = 25;

        vm.expectEmit(true, false, false, true);
        emit RecruitmentRecorded(player1, level, amount);

        vm.prank(authorized);
        playerStats.recordRecruitment(player1, level, amount);

        // Verify stats
        assertEq(playerStats.getMercsRecruitedByLevel(player1, level), amount);
        assertEq(playerStats.getTotalMercsRecruited(player1), amount);
        assertEq(playerStats.getRecruitmentCount(player1), 1);
        assertEq(playerStats.getPlayerCount(), 1);
    }

    function test_RecordRecruitment_MultipleLevels() public {
        vm.startPrank(authorized);
        playerStats.recordRecruitment(player1, 1, 10);
        playerStats.recordRecruitment(player1, 2, 20);
        playerStats.recordRecruitment(player1, 1, 5); // More level 1
        vm.stopPrank();

        // Verify stats
        assertEq(playerStats.getMercsRecruitedByLevel(player1, 1), 15);
        assertEq(playerStats.getMercsRecruitedByLevel(player1, 2), 20);
        assertEq(playerStats.getTotalMercsRecruited(player1), 35);
        assertEq(playerStats.getRecruitmentCount(player1), 3);
    }

    function test_RecordRecruitment_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordRecruitment(player1, 1, 10);
    }

    /*//////////////////////////////////////////////////////////////
                            SEIZE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordSeizeAttempt_Success() public {
        uint256 attackPower = 1000;
        address previousOwner = player2;

        vm.expectEmit(true, true, false, true);
        emit SeizeAttemptRecorded(player1, mine1, true, attackPower);

        vm.prank(authorized);
        playerStats.recordSeizeAttempt(player1, mine1, true, attackPower, previousOwner);

        // Verify stats
        (uint256 total, uint256 successful, uint256 failed) = playerStats.getSeizeStats(player1);
        assertEq(total, 1);
        assertEq(successful, 1);
        assertEq(failed, 0);
        assertEq(playerStats.getMinesSeizedFrom(player1, previousOwner), 1);
        assertEq(playerStats.getPlayerCount(), 1);
    }

    function test_RecordSeizeAttempt_Failed() public {
        uint256 attackPower = 500;

        vm.expectEmit(true, true, false, true);
        emit SeizeAttemptRecorded(player1, mine1, false, attackPower);

        vm.prank(authorized);
        playerStats.recordSeizeAttempt(player1, mine1, false, attackPower, player2);

        // Verify stats
        (uint256 total, uint256 successful, uint256 failed) = playerStats.getSeizeStats(player1);
        assertEq(total, 1);
        assertEq(successful, 0);
        assertEq(failed, 1);
        assertEq(playerStats.getMinesSeizedFrom(player1, player2), 0); // No seizure from failed attempt
    }

    function test_RecordSeizeAttempt_UnownedMine() public {
        uint256 attackPower = 800;

        vm.prank(authorized);
        playerStats.recordSeizeAttempt(player1, mine1, true, attackPower, address(0));

        // Verify stats
        (uint256 total, uint256 successful, uint256 failed) = playerStats.getSeizeStats(player1);
        assertEq(total, 1);
        assertEq(successful, 1);
        assertEq(failed, 0);
        assertEq(playerStats.getMinesSeizedFrom(player1, address(0)), 0); // No previous owner
    }

    function test_RecordSeizeAttempt_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordSeizeAttempt(player1, mine1, true, 1000, player2);
    }

    /*//////////////////////////////////////////////////////////////
                           ABANDON TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordAbandon_Success() public {
        vm.expectEmit(true, true, false, true);
        emit AbandonRecorded(player1, mine1);

        vm.prank(authorized);
        playerStats.recordAbandon(player1, mine1);

        // Verify stats
        assertEq(playerStats.getMinesAbandoned(player1), 1);
        assertEq(playerStats.getPlayerCount(), 1);
    }

    function test_RecordAbandon_Multiple() public {
        vm.startPrank(authorized);
        playerStats.recordAbandon(player1, mine1);
        playerStats.recordAbandon(player1, mine2);
        vm.stopPrank();

        assertEq(playerStats.getMinesAbandoned(player1), 2);
    }

    function test_RecordAbandon_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordAbandon(player1, mine1);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordClaim_Success() public {
        uint256 amount = 250e18;

        vm.expectEmit(true, true, false, true);
        emit ClaimRecorded(player1, IERC20(address(token1)), amount);

        vm.prank(authorized);
        playerStats.recordClaim(player1, IERC20(address(token1)), amount);

        // Verify stats
        assertEq(playerStats.getResourcesClaimed(player1, IERC20(address(token1))), amount);
        assertEq(playerStats.getClaimCount(player1), 1);
        assertEq(playerStats.getPlayerCount(), 1);
    }

    function test_RecordClaim_MultipleResources() public {
        vm.startPrank(authorized);
        playerStats.recordClaim(player1, IERC20(address(token1)), 100e18);
        playerStats.recordClaim(player1, IERC20(address(token2)), 200e18);
        playerStats.recordClaim(player1, IERC20(address(token1)), 50e18);
        vm.stopPrank();

        // Verify accumulated stats
        assertEq(playerStats.getResourcesClaimed(player1, IERC20(address(token1))), 150e18);
        assertEq(playerStats.getResourcesClaimed(player1, IERC20(address(token2))), 200e18);
        assertEq(playerStats.getClaimCount(player1), 3);
    }

    function test_RecordClaim_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordClaim(player1, IERC20(address(token1)), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        DEFENSE BOOST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordDefenseBoost_Success() public {
        vm.expectEmit(true, true, false, true);
        emit DefenseBoostRecorded(player1, mine1);

        vm.prank(authorized);
        playerStats.recordDefenseBoost(player1, mine1);

        // Verify stats
        assertEq(playerStats.getDefenseBoostsActivated(player1), 1);
        assertEq(playerStats.getPlayerCount(), 1);
    }

    function test_RecordDefenseBoost_Multiple() public {
        vm.startPrank(authorized);
        playerStats.recordDefenseBoost(player1, mine1);
        playerStats.recordDefenseBoost(player1, mine2);
        playerStats.recordDefenseBoost(player1, mine1); // Same mine again
        vm.stopPrank();

        assertEq(playerStats.getDefenseBoostsActivated(player1), 3);
    }

    function test_RecordDefenseBoost_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordDefenseBoost(player1, mine1);
    }

    /*//////////////////////////////////////////////////////////////
                         COMBAT STATS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RecordCombatStats_Success() public {
        uint256 mercsLost = 10;
        uint256 mercsWon = 25;
        uint256 defensePower = 500;

        vm.expectEmit(true, false, false, true);
        emit CombatStatsRecorded(player1, mercsLost, mercsWon);

        vm.prank(authorized);
        playerStats.recordCombatStats(player1, mercsLost, mercsWon, defensePower);

        // Verify stats
        (uint256 attackPower, uint256 defPower) = playerStats.getCombatPowerStats(player1);
        assertEq(defPower, defensePower);

        (uint256 lost, uint256 won) = playerStats.getCombatMercStats(player1);
        assertEq(lost, mercsLost);
        assertEq(won, mercsWon);
        assertEq(playerStats.getPlayerCount(), 1);
    }

    function test_RecordCombatStats_Accumulated() public {
        vm.startPrank(authorized);
        playerStats.recordCombatStats(player1, 5, 10, 300);
        playerStats.recordCombatStats(player1, 8, 15, 200);
        vm.stopPrank();

        // Verify accumulated stats
        (uint256 attackPower, uint256 defPower) = playerStats.getCombatPowerStats(player1);
        assertEq(defPower, 500);

        (uint256 lost, uint256 won) = playerStats.getCombatMercStats(player1);
        assertEq(lost, 13);
        assertEq(won, 25);
    }

    function test_RecordCombatStats_Unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        playerStats.recordCombatStats(player1, 10, 5, 300);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetPlayers() public {
        // Add some players
        vm.startPrank(authorized);
        playerStats.recordDeposit(player1, IERC20(address(token1)), 100);
        playerStats.recordDeposit(player2, IERC20(address(token1)), 200);
        vm.stopPrank();

        // Test getPlayers with different ranges
        address[] memory players;

        // Get all players
        players = playerStats.getPlayers(0, 2);
        assertEq(players.length, 2);
        assertEq(players[0], player1);
        assertEq(players[1], player2);

        // Get first player only
        players = playerStats.getPlayers(0, 1);
        assertEq(players.length, 1);
        assertEq(players[0], player1);

        // Get second player only
        players = playerStats.getPlayers(1, 1);
        assertEq(players.length, 1);
        assertEq(players[0], player2);

        // Request beyond available
        players = playerStats.getPlayers(0, 10);
        assertEq(players.length, 2);

        // Start beyond available
        players = playerStats.getPlayers(10, 5);
        assertEq(players.length, 0);
    }

    function test_ComplexScenario() public {
        // Simulate a complex game scenario for player1
        vm.startPrank(authorized);

        // Player deposits and withdraws
        playerStats.recordDeposit(player1, IERC20(address(token1)), 1000e18);
        playerStats.recordDeposit(player1, IERC20(address(token2)), 500e18);
        playerStats.recordWithdrawal(player1, IERC20(address(token1)), 200e18, 100e18);

        // Player recruits mercenaries
        playerStats.recordRecruitment(player1, 1, 50);
        playerStats.recordRecruitment(player1, 2, 25);

        // Player attempts seizures
        playerStats.recordSeizeAttempt(player1, mine1, true, 800, address(0)); // Unowned mine
        playerStats.recordSeizeAttempt(player1, mine2, false, 600, player2); // Failed attack
        playerStats.recordSeizeAttempt(player1, mine2, true, 900, player2); // Successful attack

        // Player claims resources and activates defense
        playerStats.recordClaim(player1, IERC20(address(token1)), 150e18);
        playerStats.recordDefenseBoost(player1, mine1);

        // Combat stats
        playerStats.recordCombatStats(player1, 10, 15, 400);

        // Player abandons a mine
        playerStats.recordAbandon(player1, mine2);

        vm.stopPrank();

        // Verify all stats are correctly accumulated
        assertEq(playerStats.getTotalDeposited(player1, IERC20(address(token1))), 1000e18);
        assertEq(playerStats.getTotalWithdrawn(player1, IERC20(address(token1))), 100e18);
        assertEq(playerStats.getTotalBurned(player1, IERC20(address(token1))), 100e18);
        assertEq(playerStats.getDepositCount(player1), 2);
        assertEq(playerStats.getWithdrawalCount(player1), 1);

        assertEq(playerStats.getMercsRecruitedByLevel(player1, 1), 50);
        assertEq(playerStats.getMercsRecruitedByLevel(player1, 2), 25);
        assertEq(playerStats.getTotalMercsRecruited(player1), 75);
        assertEq(playerStats.getRecruitmentCount(player1), 2);

        (uint256 total, uint256 successful, uint256 failed) = playerStats.getSeizeStats(player1);
        assertEq(total, 3);
        assertEq(successful, 2);
        assertEq(failed, 1);
        assertEq(playerStats.getMinesSeizedFrom(player1, player2), 1);

        assertEq(playerStats.getResourcesClaimed(player1, IERC20(address(token1))), 150e18);
        assertEq(playerStats.getClaimCount(player1), 1);
        assertEq(playerStats.getDefenseBoostsActivated(player1), 1);
        assertEq(playerStats.getMinesAbandoned(player1), 1);

        (uint256 attackPower, uint256 defensePower) = playerStats.getCombatPowerStats(player1);
        assertEq(defensePower, 400);

        (uint256 lost, uint256 won) = playerStats.getCombatMercStats(player1);
        assertEq(lost, 10);
        assertEq(won, 15);

        assertEq(playerStats.getPlayerCount(), 1);
        assertTrue(playerStats.playerExists(player1));
    }
}
