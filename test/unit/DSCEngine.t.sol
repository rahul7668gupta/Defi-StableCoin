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
    address wETHUsdPriceFeed;
    address wBTCUsdPriceFeed;
    HelperConfig config;
    address s_wETH;
    address s_wBTC;

    uint256 constant COLLATERAL_AMOUNT = 10 ether;
    address User1 = makeAddr("User1");

    address[] public tokenAddresses;
    address[] public priceFeeds;

    /**
     * forge-config: default.fuzz.runs = 1024
     * forge-config: default.fuzz.max-test-rejects = 500
     */
    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wETHUsdPriceFeed, wBTCUsdPriceFeed, s_wETH, s_wBTC) = config.activeNetworkConfig();
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function testDSCEngineDeployRevertsIfInputLenghtsDontMatch() external {
        tokenAddresses.push(s_wBTC);
        priceFeeds.push(wETHUsdPriceFeed);
        priceFeeds.push(wBTCUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__AddressArrayLengthMismatch.selector);
        new DSCEngine(tokenAddresses, priceFeeds, address(0));
    }

    modifier mintWethToUser(address user) {
        vm.prank(User1);
        ERC20Mock(s_wETH).mint(User1, COLLATERAL_AMOUNT); // 10 weth
        _;
    }

    modifier mintWbtcToUser(address user) {
        vm.prank(User1);
        ERC20Mock(s_wBTC).mint(User1, COLLATERAL_AMOUNT); // 10 wbtc
        _;
    }

    modifier depositWethCollateral(address user) {
        vm.startPrank(User1);
        ERC20Mock(s_wETH).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateral(s_wETH, COLLATERAL_AMOUNT); //10 weth deposit
        vm.stopPrank();
        _;
    }

    modifier depositWbtcCollateral(address user) {
        vm.startPrank(User1);
        ERC20Mock(s_wBTC).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateral(s_wBTC, COLLATERAL_AMOUNT); // 10 btc deposit
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testMintDSCIfAmountIsZero() external mintWethToUser(User1) {
        vm.startPrank(User1);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.mintDSC(0);
        vm.stopPrank();
    }

    // TODO: implement a reentrancy test

    function testMintDSCBreaksHealthFactorWithoutCollateral() external mintWethToUser(User1) {
        vm.startPrank(User1);
        uint256 expectedHealthFactor = dscEngine.getHealthFactor(User1);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDSC(100 ether);
        vm.stopPrank();
    }

    function testMintDSCBreaksHealthFactorWithCollateral()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
    {
        vm.startPrank(User1);
        uint256 expectedHealthFactor = 1 ether / 2; //5e17 or 0.5
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDSC(30000 ether); // 10weth * 3000 USD, minting same worth of tokens as deposit value
        vm.stopPrank();
    }

    function testMintDSCSuccessFor100USDMint() external mintWethToUser(User1) depositWethCollateral(User1) {
        uint256 amount = 100 ether; // $100 DSC
        vm.startPrank(User1);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        uint256 expectedHealthFactor = (collateralValueInUsd * 1e18) / (amount * 2); // 300 in this case
        assertEq(dscMinted, amount);
        assertEq(collateralValueInUsd, 30000 ether); // 10 weth * 3000 USD
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
    }

    function testMintDSCSuccessFor1000USDMint() external mintWethToUser(User1) depositWethCollateral(User1) {
        uint256 amount = 1000 ether; // $1000 DSC
        vm.startPrank(User1);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        uint256 expectedHealthFactor = (collateralValueInUsd * 1e18) / (amount * 2); // 30 in this case
        assertEq(dscMinted, amount);
        assertEq(collateralValueInUsd, 30000 ether); // 10 weth * 3000 USD
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
    }

    function testMintDSCSuccessFor10000USDMint() external mintWethToUser(User1) depositWethCollateral(User1) {
        uint256 amount = 10000 ether; // $10000 DSC
        vm.startPrank(User1);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        uint256 expectedHealthFactor = (collateralValueInUsd * 1e18) / (amount * 2); // 3 in this case
        assertEq(dscMinted, amount);
        assertEq(collateralValueInUsd, 30000 ether); // 10 weth * 3000 USD
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
    }

    function testMintDSCSuccessFor15000USDMint() external mintWethToUser(User1) depositWethCollateral(User1) {
        uint256 amount = 15000 ether; // $15000 DSC
        vm.startPrank(User1);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        uint256 expectedHealthFactor = (collateralValueInUsd * 1e18) / (amount * 2); // 1 in this case
        assertEq(dscMinted, amount);
        assertEq(collateralValueInUsd, 30000 ether); // 10 weth * 3000 USD
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
    }

    function testMintDSCFailsFor15001USDMint() external mintWethToUser(User1) depositWethCollateral(User1) {
        uint256 amount = 15001 ether; // $15001 DSC
        uint256 expectedHealthFactorRevert = (30000 ether * 1e18) / (amount * 2);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactorRevert)
        );
        vm.startPrank(User1);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        uint256 expectedHealthFactor = 0; // since tx reverted
        assertEq(dscMinted, 0); // since tx reverted
        assertEq(collateralValueInUsd, 30000 ether); // 10 weth * 3000 USD
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepostiCollateralIfAmountIsZero() external mintWethToUser(User1) {
        // approve token
        // run deposit collateral
        vm.startPrank(User1);
        ERC20Mock(s_wETH).approve(address(dscEngine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.depositCollateral(s_wETH, 0);
        vm.stopPrank();
    }

    function testDepositCollateralIfTokenIsNotAllowed() external mintWethToUser(User1) {
        address randonToken = address(0x01);
        vm.startPrank(User1);
        vm.expectRevert(DSCEngine.DSCEngine__TokenIsNotAllowed.selector);
        dscEngine.depositCollateral(randonToken, COLLATERAL_AMOUNT);
    }

    // TODO: implement a reentrancy test

    function testDepositCollateralSuccess() external mintWethToUser(User1) depositWethCollateral(User1) {
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        uint256 expectedDSCMinted = 0;
        uint256 collateralAmountInWeth = dscEngine.getCollateralTokenAmountForUsd(s_wETH, collateralValueInUsd);
        assertEq(COLLATERAL_AMOUNT, collateralAmountInWeth);
        assertEq(dscMinted, expectedDSCMinted);
    }

    /*//////////////////////////////////////////////////////////////
                     GET COLLATERAL TOKEN AMOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetCollateralTokenAmountForUsdForWeth() external view {
        uint256 amount = 100 ether; // $100 DSC
        uint256 expectedCollateralAmount = (1 ether * amount) / 3000e18; // 1eth * usd amount / price
        uint256 collateralToRedeem = dscEngine.getCollateralTokenAmountForUsd(s_wETH, amount);
        assertEq(expectedCollateralAmount, collateralToRedeem);
    }

    function testGetCollateralTokenAmountForUsdForWbtc() external view {
        uint256 amount = 1000 ether; // $1000 DSC
        uint256 expectedCollateralAmount = (1 ether * amount) / 60000e18; // 1wbtc * usd amount / price
        uint256 collateralToRedeem = dscEngine.getCollateralTokenAmountForUsd(s_wBTC, amount);
        assertEq(expectedCollateralAmount, collateralToRedeem);
    }

    function testGetCollateralTokenAmountForUsdForNotAllowedToken() external {
        uint256 amount = 1000 ether; // $1000 DSC
        vm.expectRevert();
        dscEngine.getCollateralTokenAmountForUsd(address(0x01), amount);
    }

    /*//////////////////////////////////////////////////////////////
                       GET COLLATERAL VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetCollateralValueOnlyBtc() external mintWbtcToUser(User1) depositWbtcCollateral(User1) {
        uint256 collateralValueInUsd = dscEngine.getCollateralValue(User1);
        uint256 expectedCollateralValue = COLLATERAL_AMOUNT * 60000e18 / 1e18;
        assertEq(collateralValueInUsd, expectedCollateralValue);
    }

    function testGetCollateralValueOnlyEth() external mintWethToUser(User1) depositWethCollateral(User1) {
        uint256 collateralValueInUsd = dscEngine.getCollateralValue(User1);
        uint256 expectedCollateralValue = COLLATERAL_AMOUNT * 3000e18 / 1e18;
        assertEq(collateralValueInUsd, expectedCollateralValue);
    }

    function testGetCollateralValueBtcAndEth()
        external
        mintWethToUser(User1)
        mintWbtcToUser(User1)
        depositWethCollateral(User1)
        depositWbtcCollateral(User1)
    {
        uint256 collateralValueInUsd = dscEngine.getCollateralValue(User1);
        uint256 expectedCollateralValue = (COLLATERAL_AMOUNT * 3000e18 / 1e18) + (COLLATERAL_AMOUNT * 60000e18 / 1e18);
        assertEq(collateralValueInUsd, expectedCollateralValue);
    }

    function testGetCollateralValueNoTokenDeposited() external view {
        uint256 collateralValueInUsd = dscEngine.getCollateralValue(User1);
        assertEq(collateralValueInUsd, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           TEST GET USD VALUE
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValueForWeth() external view {
        uint256 amount = 15e18; // 15ETH
        uint256 expectedPrice = 45000e18; //15e18 * 3000
        uint256 wEthUsdValue = dscEngine.getUsdValue(s_wETH, amount);
        assertEq(expectedPrice, wEthUsdValue);
    }

    function testGetUsdValueForWbtc() external view {
        uint256 amount = 1e18; // 1WBTC
        uint256 expectedPrice = 60000e18; //1e18 * 60000
        uint256 wBtcUsdValue = dscEngine.getUsdValue(s_wBTC, amount);
        assertEq(expectedPrice, wBtcUsdValue);
    }

    function testGetUsdValueForNotAllowedToken() external {
        uint256 amount = 1e18; // 1WBTC
        vm.expectRevert();
        dscEngine.getUsdValue(address(0x01), amount);
    }
}
