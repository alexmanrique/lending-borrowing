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
    MockToken public testToken;

    uint256 public constant DEFAULT_COLLATERAL_FACTOR = 8000; // 80% en basis points
    uint256 public constant DEFAULT_SUPPLY_RATE = 10000; // 100% APY en basis points
    uint256 public constant DEFAULT_BORROW_RATE = 10000; // 100% APY en basis points

    uint256 public constant USER_1_PRIVATE_KEY = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 public constant USER_2_PRIVATE_KEY = 0x2222222222222222222222222222222222222222222222222222222222222222;

    address public constant INVALID_TOKEN = address(0);
    address public USER_1;
    address public USER_2;

    function setUp() public {
        USER_1 = vm.addr(USER_1_PRIVATE_KEY);
        USER_2 = vm.addr(USER_2_PRIVATE_KEY);

        lendingProtocol = new LendingProtocol();
        testToken = new MockToken("Test Token", "TEST", 18, 0);
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
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
        lendingProtocol.addMarket(address(testToken), invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarketMarketAlreadyExists() public {
        vm.expectRevert("Market already exists");
        lendingProtocol.addMarket(
            address(testToken), DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
    }

    function testAddMarket() public {
        LendingProtocol.Market memory market = lendingProtocol.getMarket(address(testToken));
        assertEq(market.isActive, true);
        assertEq(market.totalSupply, 0);
        assertEq(market.totalBorrow, 0);
        assertEq(market.supplyRate, DEFAULT_SUPPLY_RATE);
        assertEq(market.borrowRate, DEFAULT_BORROW_RATE);
        assertEq(market.collateralFactor, DEFAULT_COLLATERAL_FACTOR);
    }

    function testUpdateMarketInvalidCollateralFactor() public {
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;
        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.updateMarket(
            address(testToken), invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE
        );
    }

    function testUpdateMarket() public {
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
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.deposit(address(testToken), 0);
    }

    function testDeposit() public {
        testToken.mint(USER_1, 1000);

        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, true);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalBorrow, 0);
    }

    function testWithdrawInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.withdraw(address(testToken), 0);
    }

    function testWithdrawInsufficientDeposit() public {
        vm.expectRevert("Insufficient deposit");
        lendingProtocol.withdraw(address(testToken), 1000);
    }

    function testWithdrawalWouldMakePositionUnsafe() public {
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
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.borrow(address(testToken), 0);
    }

    function testBorrowInsufficientLiquidity() public {
        vm.expectRevert("Insufficient liquidity");
        lendingProtocol.borrow(address(testToken), 1000);
    }

    function testBorrowWouldMakePositionUnsafe() public {
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
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.repay(address(testToken), 0);
    }

    function testRepayInsufficientBorrow() public {
        vm.expectRevert("Insufficient borrow");
        lendingProtocol.repay(address(testToken), 1000);
    }

    function testRepay() public {
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
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.liquidate(USER_1, address(testToken), 0);
    }

    function testLiquidateInsufficientBorrow() public {
        vm.expectRevert("Insufficient borrow to liquidate");
        lendingProtocol.liquidate(USER_1, address(testToken), 1000);
    }

    function testLiquidatePositionNotLiquidatable() public {
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

    function testEmergencyRecoverRevertInvalidRecipient() public {
        vm.expectRevert("Invalid recipient");
        lendingProtocol.emergencyRecover(address(testToken), address(0), 1000);
    }

    function testCollateralizationRatio() public {
        testToken.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);
        lendingProtocol.deposit(address(testToken), 1000);
        lendingProtocol.borrow(address(testToken), 1000);
        vm.stopPrank();
        lendingProtocol.getCollateralizationRatio(USER_1);
        assertEq(lendingProtocol.getCollateralizationRatio(USER_1), 8000);
    }

    function testDepositWithInvalidNonce() public {
        vm.expectRevert("Invalid nonce");
        lendingProtocol.depositWithSignature(
            address(testToken), 1000, LendingProtocol.SignatureData(1, block.timestamp + 1, bytes(""))
        );
    }

    function testDepositWithSignatureInvalidAmount() public {
        vm.expectRevert("Amount must be greater than 0");
        lendingProtocol.depositWithSignature(
            address(testToken), 0, LendingProtocol.SignatureData(0, block.timestamp + 1, bytes(""))
        );
    }

    function testDepositWithSignatureExpired() public {
        vm.expectRevert("Signature expired");
        lendingProtocol.depositWithSignature(
            address(testToken), 1000, LendingProtocol.SignatureData(0, block.timestamp - 1, bytes(""))
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
            address(testToken), amount, LendingProtocol.SignatureData(nonce, deadline, signature)
        );
    }

    function testDepositWithSignatureSuccessful() public {
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1;
        uint256 amount = 1000;

        bytes memory signature = _depositSignature(USER_1_PRIVATE_KEY, amount, nonce, deadline);

        testToken.mint(USER_1, 1000);
        vm.startPrank(USER_1);
        testToken.approve(address(lendingProtocol), 1000);

        lendingProtocol.depositWithSignature(
            address(testToken), 1000, LendingProtocol.SignatureData(0, block.timestamp + 1, signature)
        );
        vm.stopPrank();

        LendingProtocol.User memory user = lendingProtocol.getUser(USER_1);
        assertEq(user.totalDeposited, 1000);
        assertEq(user.totalBorrowed, 0);
        assertEq(user.lastUpdateTime, block.timestamp);
        assertEq(user.isActive, true);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalSupply, 1000);
        assertEq(lendingProtocol.getMarket(address(testToken)).totalBorrow, 0);
    }

    function _depositSignature(
        uint256 privateKey,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked("deposit", address(testToken), amount, nonce, deadline));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
}
