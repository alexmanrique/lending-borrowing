pragma solidity ^0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {LendingProtocol} from "../src/LendingProtocol.sol";

contract LendingProtocolTest is Test {
    LendingProtocol public lendingProtocol;
    address public owner;

    function setUp() public {
        lendingProtocol = new LendingProtocol();
    }

    function testAddMarketInvalidToken() public {
        vm.expectRevert("Invalid token address");
        lendingProtocol.addMarket(address(0), 10000, 10000, 10000);
    }

    function testAddMarketInvalidCollateralFactor() public {
        uint256 basisPoints = lendingProtocol.BASIS_POINTS();
        uint256 invalidCollateralFactor = basisPoints + 1;
   
        vm.expectRevert("Invalid collateral factor");
        lendingProtocol.addMarket(address(1), invalidCollateralFactor, 10000, 10000);
    }

    function testAddMarketMarketAlreadyExists() public {
        lendingProtocol.addMarket(address(1), 10000, 10000, 10000);
        vm.expectRevert("Market already exists");
        lendingProtocol.addMarket(address(1), 10000, 10000, 10000);
    }

    /*function testAddMarket() public {
        lendingProtocol.addMarket(address(0), 10000, 10000, 10000);
    }*/

}