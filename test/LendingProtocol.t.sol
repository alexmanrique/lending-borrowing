// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";
import {MockToken} from "../src/MockToken.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract LendingProtocolTest is Test {
    LendingProtocol public lendingProtocol;
    MockToken public usdc;
    MockToken public dai;

    uint256 public constant DEFAULT_COLLATERAL_FACTOR = 8000; // 80% en basis points
    uint256 public constant DEFAULT_SUPPLY_RATE = 10000; // 100% APY en basis points
    uint256 public constant DEFAULT_BORROW_RATE = 10000; // 100% APY en basis points

    uint256 public constant DEPOSIT_AMOUNT = 1000;
    uint256 public constant BORROW_AMOUNT = 900;
    uint256 public constant SUPPLY_RATE = 10000;
    uint256 public constant BORROW_RATE = 10000;

    uint256 public constant USER_1_PRIVATE_KEY = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 public constant USER_2_PRIVATE_KEY = 0x2222222222222222222222222222222222222222222222222222222222222222;

    address public constant INVALID_TOKEN = address(0);
    address public USER_1;
    address public USER_2;
    address public liquidator;

    function setUp() public {
        USER_1 = vm.addr(USER_1_PRIVATE_KEY);
        USER_2 = vm.addr(USER_2_PRIVATE_KEY);
        liquidator = makeAddr("liquidator");

        lendingProtocol = new LendingProtocol();
        usdc = new MockToken("USDC", "USDC", 18, 0);
        dai = new MockToken("DAI", "DAI", 18, 0);
        lendingProtocol.addMarket(
            address(usdc), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
    }

    function testAddMarketInvalidToken() public {
        vm.expectRevert("Invalid token address");
        lendingProtocol.addMarket(INVALID_TOKEN, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarketInvalidCollateralFactor() public {
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;

        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.addMarket(address(usdc), invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarketMarketAlreadyExists() public {
        vm.expectRevert("Market already exists");
        lendingProtocol.addMarket(
            address(usdc), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
    }

    function testAddMarket() public {
        lendingProtocol.addMarket(address(dai), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);

        LendingProtocol.Market memory market = lendingProtocol.getMarket(address(dai));
        assertEq(market.isActive, true);
        assertEq(market.totalSupply, 0);
        assertEq(market.totalBorrow, 0);
        assertEq(market.supplyRate, DEFAULT_SUPPLY_RATE);
        assertEq(market.borrowRate, DEFAULT_BORROW_RATE);
        assertEq(market.collateralFactor, DEFAULT_COLLATERAL_FACTOR);

        assertEq(lendingProtocol.supportedTokens(0), address(usdc));
        assertEq(lendingProtocol.supportedTokens(1), address(dai));
    }

    function testUpdateMarketInvalidCollateralFactor() public {
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;
        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.updateMarket(
            address(usdc), invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
    }

    function testUpdateMarket() public {
        lendingProtocol.updateMarket(
            address(usdc), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE + 1, DEFAULT_BORROW_RATE + 1
        );
        LendingProtocol.Market memory market = lendingProtocol.getMarket(address(usdc));
        assertEq(market.isActive, true);
        assertEq(market.totalSupply, 0);
        assertEq(market.totalBorrow, 0);
        assertEq(market.supplyRate, DEFAULT_SUPPLY_RATE + 1);
        assertEq(market.borrowRate, DEFAULT_BORROW_RATE + 1);
        assertEq(market.collateralFactor, DEFAULT_COLLATERAL_FACTOR);
    }

    function testDepositInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.deposit(address(usdc), 0);
    }

    function testDeposit() public {
        usdc.mint(USER_1, 1000);

        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, true);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalBorrow, 0);
    }

    function testWithdrawInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.withdraw(address(usdc), 0);
    }

    function testWithdrawInsufficientDeposit() public {
        vm.expectRevert("Insufficient deposit");
        lendingProtocol.withdraw(address(usdc), 1000);
    }

    function testWithdrawalWouldMakePositionUnsafe() public {
        usdc.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        // Borrow against the collateral to create a position
        // With 1000 deposited and 80% collateral factor, can borrow up to 800
        // Borrowing 800 and then trying to withdraw all 1000 would make position unsafe
        lendingProtocol.borrow(address(usdc), 800);
        vm.expectRevert("Withdrawal would make position unsafe");
        lendingProtocol.withdraw(address(usdc), 1000);
        vm.stopPrank();
    }

    function testWithdraw() public {
        usdc.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        lendingProtocol.withdraw(address(usdc), 1000);
        vm.stopPrank();
        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 0);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, false);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalSupply, 0);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalBorrow, 0);
    }

    function testBorrowInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.borrow(address(usdc), 0);
    }

    function testBorrowInsufficientLiquidity() public {
        vm.expectRevert("Insufficient liquidity");
        lendingProtocol.borrow(address(usdc), 1000);
    }

    function testBorrowWouldMakePositionUnsafe() public {
        usdc.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        // With 1000 deposited and 80% collateral factor, collateral value is 800
        // Maximum total borrow allowed: 800 * 10000 / 8000 = 1000 tokens
        // Borrowing 800 tokens first
        lendingProtocol.borrow(address(usdc), 800);
        // Trying to borrow 201 more tokens (total 1001) would exceed the limit
        // Ratio would be: 800/1001 ≈ 79.9% < 80% threshold
        vm.expectRevert("Borrow would exceed collateral limit");
        lendingProtocol.borrow(address(usdc), 201);
        vm.stopPrank();
    }

    function testBorrowSuccessful() public {
        usdc.mint(USER_1, 1000);

        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        lendingProtocol.borrow(address(usdc), 1000);
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 1000);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, true);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalBorrow, 1000);
        assertEq(lendingProtocol.getUserBorrow(USER_1, address(usdc)), 1000);
    }

    function testRepayInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.repay(address(usdc), 0);
    }

    function testRepayInsufficientBorrow() public {
        vm.expectRevert("Insufficient borrow");
        lendingProtocol.repay(address(usdc), 1000);
    }

    function testRepay() public {
        usdc.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        lendingProtocol.borrow(address(usdc), 1000);

        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.repay(address(usdc), 1000);
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, false);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalBorrow, 0);
    }

    function testLiquidateInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.liquidate(USER_1, address(usdc), 0);
    }

    function testLiquidateInsufficientBorrow() public {
        vm.expectRevert("Insufficient borrow to liquidate");
        lendingProtocol.liquidate(USER_1, address(usdc), 1000);
    }

    function testLiquidatePositionNotLiquidatable() public {
        usdc.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        lendingProtocol.borrow(address(usdc), 1000);
        vm.stopPrank();
        vm.expectRevert("Position is not liquidatable");
        lendingProtocol.liquidate(USER_1, address(usdc), 1000);
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

    function testEmergencyRecoverRevertInvalidRecipient() public {
        vm.expectRevert("Invalid recipient");
        lendingProtocol.emergencyRecover(address(usdc), address(0), 1000);
    }

    function testEmergencyRecoverSuccess() public {
        uint256 amount = 1000;
        usdc.mint(address(lendingProtocol), amount);
        address recipient = USER_2;

        uint256 before = usdc.balanceOf(recipient);
        lendingProtocol.emergencyRecover(address(usdc), recipient, amount);
        assertEq(usdc.balanceOf(recipient), before + amount);
        assertEq(usdc.balanceOf(address(lendingProtocol)), 0);
    }

    function testCollateralizationRatio() public {
        usdc.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(usdc), 1000);
        lendingProtocol.borrow(address(usdc), 1000);
        vm.stopPrank();
        lendingProtocol.getCollateralizationRatio(USER_1);
        assertEq(lendingProtocol.getCollateralizationRatio(USER_1), 8000);
    }

    function testDepositWithInvalidNonce() public {
        vm.expectRevert("Invalid nonce");
        lendingProtocol.depositWithSignature(
            address(usdc), 1000, LendingProtocol.SignatureData(1, block.timestamp + 1, bytes(""))
        );
    }

    function testDepositWithSignatureInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.depositWithSignature(
            address(usdc), 0, LendingProtocol.SignatureData(0, block.timestamp + 1, bytes(""))
        );
    }

    function testDepositWithSignatureExpired() public {
        vm.expectRevert("Signature expired");
        lendingProtocol.depositWithSignature(
            address(usdc), 1000, LendingProtocol.SignatureData(0, block.timestamp - 1, bytes(""))
        );
    }

    function testDepositWithSignatureInvalidSignature() public {
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1;
        uint256 amount = 1000;
        assertEq(USER_2, vm.addr(USER_2_PRIVATE_KEY));

        bytes memory signature = _depositSignature(USER_2_PRIVATE_KEY, amount, nonce, deadline);

        // But execute the call from USER_1 (msg.sender will be USER_1, not USER_2)
        // The signature is valid but signed by USER_2, so it should fail
        vm.prank(USER_1);
        vm.expectRevert("Invalid signature");
        lendingProtocol.depositWithSignature(
            address(usdc), amount, LendingProtocol.SignatureData(nonce, deadline, signature)
        );
    }

    function testDepositWithSignatureSuccessful() public {
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1;
        uint256 amount = 1000;

        bytes memory signature = _depositSignature(USER_1_PRIVATE_KEY, amount, nonce, deadline);

        usdc.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), 1000);

        lendingProtocol.depositWithSignature(
            address(usdc), 1000, LendingProtocol.SignatureData(0, block.timestamp + 1, signature)
        );
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, true);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(usdc)).totalBorrow, 0);

        assertEq(lendingProtocol.getNonce(USER_1), 1);
    }

    function testLiquidationSuccessfull() public {

        lendingProtocol.addMarket(address(dai), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
        // User1 deposits test token
        usdc.mint(USER_1, DEPOSIT_AMOUNT);
        vm.startPrank(USER_1);
        usdc.approve(address(lendingProtocol), DEPOSIT_AMOUNT);
        lendingProtocol.deposit(address(usdc), DEPOSIT_AMOUNT);
        lendingProtocol.borrow(address(usdc), BORROW_AMOUNT);
        vm.stopPrank();

        // Make USER_! position liquidatable because we decrease the collateral factor to 3000
        lendingProtocol.updateMarket(address(usdc), 3000, SUPPLY_RATE, BORROW_RATE);

        // Liquidate
        usdc.mint(liquidator, BORROW_AMOUNT);
        vm.startPrank(liquidator);
        usdc.approve(address(lendingProtocol), BORROW_AMOUNT);
        lendingProtocol.liquidate(USER_1, address(usdc), BORROW_AMOUNT);
        vm.stopPrank();

        // Verify liquidation occurred
        assertLt(lendingProtocol.getUserDeposit(USER_1, address(usdc)), DEPOSIT_AMOUNT);
    }

    function _depositSignature(uint256 privateKey, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 messageHash = keccak256(abi.encodePacked("deposit", address(usdc), amount, nonce, deadline));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
}
