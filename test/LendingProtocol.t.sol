pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {MockToken} from "../src/MockToken.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract LendingProtocolTest is Test {
    LendingProtocol public lendingProtocol;
    MockToken public testToken;

    uint256 public constant DEFAULT_COLLATERAL_FACTOR = 8000; // 80% en basis points
    uint256 public constant DEFAULT_SUPPLY_RATE = 10000; // 100% APY en basis points
    uint256 public constant DEFAULT_BORROW_RATE = 10000; // 100% APY en basis points

    address public constant INVALID_TOKEN = address(0);
    address public constant USER_1 = address(2);
    address public constant USER_2 = address(3);

    function setUp() public {
        lendingProtocol = new LendingProtocol();
        testToken = new MockToken("Test Token", "TEST", 18, 0);
    }

    function testAddMarketInvalidToken() public {
        vm.expectRevert("Invalid token address");
        lendingProtocol.addMarket(INVALID_TOKEN, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarketInvalidCollateralFactor() public {
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;

        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.addMarket(address(testToken), invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarketMarketAlreadyExists() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Market already exists");
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
    }

    function testAddMarket() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );

        LendingProtocol.Market memory market = lendingProtocol.getMarket(address(testToken));
        assertEq(market.isActive, true);
        assertEq(market.totalSupply, 0);
        assertEq(market.totalBorrow, 0);
        assertEq(market.supplyRate, DEFAULT_SUPPLY_RATE);
        assertEq(market.borrowRate, DEFAULT_BORROW_RATE);
        assertEq(market.collateralFactor, DEFAULT_COLLATERAL_FACTOR);
    }

    function testUpdateMarketInvalidCollateralFactor() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;
        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.updateMarket(
            address(testToken), invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
    }

    function testUpdateMarket() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        lendingProtocol.updateMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE + 1, DEFAULT_BORROW_RATE + 1
        );
        LendingProtocol.Market memory market = lendingProtocol.getMarket(address(testToken));
        assertEq(market.isActive, true);
        assertEq(market.totalSupply, 0);
        assertEq(market.totalBorrow, 0);
        assertEq(market.supplyRate, DEFAULT_SUPPLY_RATE + 1);
        assertEq(market.borrowRate, DEFAULT_BORROW_RATE + 1);
        assertEq(market.collateralFactor, DEFAULT_COLLATERAL_FACTOR);
    }

    function testDepositInvalidAmount() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.deposit(address(testToken), 0);
    }

    function testDeposit() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );

        testToken.mint(USER_1, 1000);

        vm.prank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);

        vm.prank(USER_1);
        lendingProtocol.deposit(address(testToken), 1000);

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, true);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalBorrow, 0);
    }

    function testWithdrawInvalidAmount() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.withdraw(address(testToken), 0);
    }

    function testWithdrawInsufficientDeposit() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Insufficient deposit");
        lendingProtocol.withdraw(address(testToken), 1000);
    }

    function testWithdrawalWouldMakePositionUnsafe() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        testToken.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        // Borrow against the collateral to create a position
        // With 1000 deposited and 80% collateral factor, can borrow up to 800
        // Borrowing 800 and then trying to withdraw all 1000 would make position unsafe
        lendingProtocol.borrow(address(testToken), 800);
        vm.expectRevert("Withdrawal would make position unsafe");
        lendingProtocol.withdraw(address(testToken), 1000);
        vm.stopPrank();
    }

    function testWithdraw() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        testToken.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        lendingProtocol.withdraw(address(testToken), 1000);
        vm.stopPrank();
        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 0);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, false);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalSupply, 0);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalBorrow, 0);
    }

    function testBorrowInvalidAmount() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.borrow(address(testToken), 0);
    }

    function testBorrowInsufficientLiquidity() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Insufficient liquidity");
        lendingProtocol.borrow(address(testToken), 1000);
    }

    function testBorrowWouldMakePositionUnsafe() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        testToken.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        // With 1000 deposited and 80% collateral factor, collateral value is 800
        // Maximum total borrow allowed: 800 * 10000 / 8000 = 1000 tokens
        // Borrowing 800 tokens first
        lendingProtocol.borrow(address(testToken), 800);
        // Trying to borrow 201 more tokens (total 1001) would exceed the limit
        // Ratio would be: 800/1001 ≈ 79.9% < 80% threshold
        vm.expectRevert("Borrow would exceed collateral limit");
        lendingProtocol.borrow(address(testToken), 201);
        vm.stopPrank();
    }

    function testBorrowSuccessful() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        testToken.mint(USER_1, 1000);

        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        lendingProtocol.borrow(address(testToken), 1000);
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 1000);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, true);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalBorrow, 1000);
    }

    function testRepayInvalidAmount() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.repay(address(testToken), 0);
    }

    function testRepayInsufficientBorrow() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Insufficient borrow");
        lendingProtocol.repay(address(testToken), 1000);
    }

    function testRepay() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        testToken.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        lendingProtocol.borrow(address(testToken), 1000);

        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.repay(address(testToken), 1000);
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, false);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalBorrow, 0);
    }

    function testLiquidateInvalidAmount() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.liquidate(USER_1, address(testToken), 0);
    }

    function testLiquidateInsufficientBorrow() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        vm.expectRevert("Insufficient borrow to liquidate");
        lendingProtocol.liquidate(USER_1, address(testToken), 1000);
    }

    function testLiquidatePositionNotLiquidatable() public {
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
        testToken.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        lendingProtocol.borrow(address(testToken), 1000);
        vm.stopPrank();
        vm.expectRevert("Position is not liquidatable");
        lendingProtocol.liquidate(USER_1, address(testToken), 1000);
    }

    function testPause() public {
        lendingProtocol.pause();
        assertTrue(lendingProtocol.paused());
    }

    function testUnpause() public {
        lendingProtocol.pause();
        lendingProtocol.unpause();
        assertFalse(lendingProtocol.paused());
    }
}
