pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";

contract LendingProtocolTest is Test {
    LendingProtocol public lendingProtocol;

    uint256 public constant DEFAULT_COLLATERAL_FACTOR = 10000; // 100% en basis points
    uint256 public constant DEFAULT_SUPPLY_RATE = 10000; // 100% APY en basis points
    uint256 public constant DEFAULT_BORROW_RATE = 10000; // 100% APY en basis points

    address public constant INVALID_TOKEN = address(0);
    address public constant TEST_TOKEN_1 = address(1);

    function setUp() public {
        lendingProtocol = new LendingProtocol();
    }

    function testAddMarketInvalidToken() public {
        vm.expectRevert("Invalid token address");
        lendingProtocol.addMarket(INVALID_TOKEN, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarketInvalidCollateralFactor() public {
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;

        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.addMarket(TEST_TOKEN_1, invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarketMarketAlreadyExists() public {
        lendingProtocol.addMarket(TEST_TOKEN_1, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
        vm.expectRevert("Market already exists");
        lendingProtocol.addMarket(TEST_TOKEN_1, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testAddMarket() public {
        lendingProtocol.addMarket(TEST_TOKEN_1, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);

        LendingProtocol.Market memory market = lendingProtocol.getMarket(address(TEST_TOKEN_1));
        assertEq(market.isActive, true);
        assertEq(market.totalSupply, 0);
        assertEq(market.totalBorrow, 0);
        assertEq(market.supplyRate, DEFAULT_SUPPLY_RATE);
        assertEq(market.borrowRate, DEFAULT_BORROW_RATE);
        assertEq(market.collateralFactor, DEFAULT_COLLATERAL_FACTOR);
    }

    function testUpdateMarketInvalidCollateralFactor() public {
        lendingProtocol.addMarket(TEST_TOKEN_1, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;
        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.updateMarket(TEST_TOKEN_1, invalidCollateralFactor, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
    }

    function testUpdateMarket() public {
        lendingProtocol.addMarket(TEST_TOKEN_1, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE, DEFAULT_BORROW_RATE);
        lendingProtocol.updateMarket(TEST_TOKEN_1, DEFAULT_COLLATERAL_FACTOR, DEFAULT_SUPPLY_RATE + 1, DEFAULT_BORROW_RATE + 1);
        LendingProtocol.Market memory market = lendingProtocol.getMarket(address(TEST_TOKEN_1));
        assertEq(market.isActive, true);
        assertEq(market.totalSupply, 0);
        assertEq(market.totalBorrow, 0);
        assertEq(market.supplyRate, DEFAULT_SUPPLY_RATE + 1);
        assertEq(market.borrowRate, DEFAULT_BORROW_RATE + 1);
        assertEq(market.collateralFactor, DEFAULT_COLLATERAL_FACTOR);
    }
    
    
}
