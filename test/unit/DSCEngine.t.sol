// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DecentralisedStablecoin} from "../../src/DecentralisedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralisedStablecoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address s_wETH;
    address s_wBTC;

    uint256 constant COLLATERAL_AMOUNT = 10 ether;
    address User1 = makeAddr("User1");

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (address wETHUsdPriceFeed, address wBTCUsdPriceFeed, address wETH, address wBTC) = config.activeNetworkConfig();
        s_wETH = wETH;
        s_wBTC = wBTC;
    }

    function testGetUsdValue() external view {
        uint256 amount = 15e18; // 15ETH
        uint256 expectedPrice = 45000e18; //15e18 * 3000
        uint256 wEthUsdValue = dscEngine.getUsdValue(s_wETH, amount);
        assertEq(expectedPrice, wEthUsdValue);
    }

    modifier mintWethToUser(address user) {
        ERC20Mock(s_wETH).mint(User1, COLLATERAL_AMOUNT);
        _;
    }

    modifier mintWbtcToUser(address user) {
        ERC20Mock(s_wBTC).mint(User1, COLLATERAL_AMOUNT);
        _;
    }

    function testDepostiCollateralIfAmountIsZero() external mintWethToUser(User1) {
        // approve token
        // run deposit collateral
        vm.startPrank(User1);
        ERC20Mock(s_wETH).approve(address(dscEngine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.depositCollateral(s_wETH, 0);
        vm.stopPrank();
    }

    function testDepostiCollateralIfTokenIsNotAllowed() external mintWethToUser(User1) {
        // TODO: implement
    }
}
