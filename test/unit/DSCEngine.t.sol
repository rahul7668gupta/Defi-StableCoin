// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DecentralisedStablecoin} from "../../src/DecentralisedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    address User2 = makeAddr("User2");

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
        vm.prank(user);
        ERC20Mock(s_wETH).mint(user, COLLATERAL_AMOUNT); // 10 weth
        _;
    }

    modifier mintWbtcToUser(address user) {
        vm.prank(user);
        ERC20Mock(s_wBTC).mint(user, COLLATERAL_AMOUNT); // 10 wbtc
        _;
    }

    modifier depositWethCollateral(address user) {
        vm.startPrank(user);
        ERC20Mock(s_wETH).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateral(s_wETH, COLLATERAL_AMOUNT); //10 weth deposit or 30k usd
        vm.stopPrank();
        _;
    }

    modifier depositWbtcCollateral(address user) {
        vm.startPrank(user);
        ERC20Mock(s_wBTC).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateral(s_wBTC, COLLATERAL_AMOUNT); // 10 btc deposit or 600k usd
        vm.stopPrank();
        _;
    }

    modifier mintDSC(address user, uint256 amount) {
        vm.startPrank(user);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        _;
    }
    /*//////////////////////////////////////////////////////////////
                 DEPOSIT COLLATERAL AND MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                    REDEEM COLLATERAL FOR DSC TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                          LIQUIDATE DSC TESTS
    //////////////////////////////////////////////////////////////*/
    // TODO: test non-reentrancy
    function testLiquidateDscFailsIfAmountIsZero()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 5000 ether) //5k usd, HF = 3
        mintWethToUser(User2)
        depositWethCollateral(User2)
        mintDSC(User2, 15000 ether) //15k usd, HF = 1
    {
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        vm.startPrank(User2);
        dscEngine.liquidateDSC(s_wETH, User1, 0);
        vm.stopPrank();
    }

    function testLiquidateDscFailsIfTokenNotAllowed()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 5000 ether) //5k usd, HF = 3
        mintWethToUser(User2)
        depositWethCollateral(User2)
        mintDSC(User2, 15000 ether) //15k usd, HF = 1
    {
        vm.expectRevert(DSCEngine.DSCEngine__TokenIsNotAllowed.selector);
        vm.startPrank(User2);
        dscEngine.liquidateDSC(address(0x01), User1, 100 ether);
        vm.stopPrank();
    }

    function testLiquidateDscFailsIfHealthFactorIsOkForUser1()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
        mintWethToUser(User2)
        depositWethCollateral(User2)
        mintDSC(User2, 15000 ether) //15k usd, HF = 1
    {
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorOk.selector, 1e18));
        vm.startPrank(User2);
        dscEngine.liquidateDSC(s_wETH, User1, 10000 ether); // liquidate 10k usd dsc
        vm.stopPrank();
    }

    function testLiquidateDscFailsIfUser1DoesntHaveEnoughCollateral()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
        mintWethToUser(User2)
        depositWethCollateral(User2)
        mintDSC(User2, 3000 ether) //3k usd, HF = 5
    {
        // redeem collateral from user2
        vm.startPrank(User2);
        dscEngine.redeemCollateral(s_wETH, 8 ether); // 8 weth or 24k usd, HF = 1
        vm.stopPrank();
        // HF User2 = 1, bal = 6k usd
        assertEq(dscEngine.getHealthFactor(User2), 1e18);
        // price tank from 3k usd to 2.5k usd
        MockV3Aggregator(wETHUsdPriceFeed).updateAnswer(2500e8);
        // HF User1 = 0.833, collateral val = 25k usd, dsc = 15k
        // HF User2 = 0.833, collateral val = 5k usd, dsc = 3k
        vm.expectRevert(); // arithmetic underflow revert
        vm.startPrank(User2);
        dscEngine.liquidateDSC(s_wETH, User1, 25001 ether); // liquidate 25001 usd worth of weth
        vm.stopPrank();
    }

    function testLiquidateDscFailsIfUser2DoesntHaveEnoughDsc()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
        mintWethToUser(User2)
        depositWethCollateral(User2)
        mintDSC(User2, 3000 ether) //3k usd, HF = 5
    {
        // burn all user 2 debt
        vm.startPrank(User2);
        ERC20Mock(address(dsc)).approve(address(dscEngine), 3000 ether);
        dscEngine.burnDSC(3000 ether);
        vm.stopPrank();
        // price tank
        MockV3Aggregator(wETHUsdPriceFeed).updateAnswer(2500e8);
        // HF User1 = 0.833, collateral val = 25k usd, dsc = 15k
        // HF User2 = uint256.max, collateral val = 5k usd, dsc = 0
        vm.startPrank(User2);
        ERC20Mock(address(dsc)).approve(address(dscEngine), 15000 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, User2, 0, 15000 ether)); // fails as user2 dsc bal is 0
        dscEngine.liquidateDSC(s_wETH, User1, 15000 ether); // liquidate 15000 usd worth of debt
        vm.stopPrank();
    }

    function testLiquidateDscSuccessForUser2Partially()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
        mintWethToUser(User2)
        depositWethCollateral(User2)
        mintDSC(User2, 3000 ether) //3k usd, HF = 5
    {
        // price tank
        MockV3Aggregator(wETHUsdPriceFeed).updateAnswer(2500e8);
        // HF User1 = 0.833, collateral val = 25k usd, dsc = 15k
        // HF User2 = 4.166, collateral val = 25k usd, dsc = 3k
        vm.startPrank(User2);
        ERC20Mock(address(dsc)).approve(address(dscEngine), 15000 ether);
        dscEngine.redeemCollateral(s_wETH, 7.6 ether);
        // HF User2 = 1, collateral val = 6k usd, dsc = 3k
        assertEq(dscEngine.getHealthFactor(User2), 1e18);
        dscEngine.liquidateDSC(s_wETH, User1, 3000 ether); // liquidate 3000 usd worth of debt of user 1 as user 2 is paying user 1 debt and liquidating them
        vm.stopPrank();
        (uint256 dscMintedUser1, uint256 collateralValueInUsdUser1) = dscEngine.getAccountInfo(User1);
        assertEq(collateralValueInUsdUser1, 21700 ether); // $3300 was liquidated and redeemed to user 2 (3k+0.3k (10% bonus))
        assertEq(dscMintedUser1, 12000 ether); // 15k - 3k
        assertEq(dscEngine.getHealthFactor(User1), (collateralValueInUsdUser1 * 1e18 / (dscMintedUser1 * 2)));
        (uint256 dscMintedUser2, uint256 collateralValueInUsdUser2) = dscEngine.getAccountInfo(User2);
        assertEq(collateralValueInUsdUser2, 6000 ether);
        assertEq(dscMintedUser2, 3000 ether); // user 2 debt doenst reduce when liquidating user1
        assertEq(dscEngine.getHealthFactor(User2), 1e18);
    }

    function testLiquidateDscSuccessForUser2Fully()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
        mintWethToUser(User2)
        mintWethToUser(User2) // done purpose fully
        depositWethCollateral(User2)
        depositWethCollateral(User2) // done purpose fully
        mintDSC(User2, 15000 ether) //15k usd, HF = 2
    {
        // price tank
        MockV3Aggregator(wETHUsdPriceFeed).updateAnswer(2500e8);
        // HF User1 = 0.833, collateral val = 25k usd, dsc = 15k
        // HF User2 = 4.166, collateral val = 50k usd, dsc = 15k
        vm.startPrank(User2);
        ERC20Mock(address(dsc)).approve(address(dscEngine), 15000 ether);
        dscEngine.redeemCollateral(s_wETH, 8 ether); // 20k or 8 weth redeemed
        // HF User2 = 1, collateral val = 30k usd, dsc = 15k
        assertEq(dscEngine.getHealthFactor(User2), 1e18);
        dscEngine.liquidateDSC(s_wETH, User1, 15000 ether); // liquidate 15000 usd worth of debt as user 2 has that much debt only to pay
        vm.stopPrank();
        (uint256 dscMintedUser1, uint256 collateralValueInUsdUser1) = dscEngine.getAccountInfo(User1);
        assertEq(collateralValueInUsdUser1, 8500 ether); // $25k - ($16500 was liquidated and redeemed to user 2 (15k+1.5k (10% bonus)))
        assertEq(dscMintedUser1, 0 ether); // 15k - 15k
        assertEq(dscEngine.getHealthFactor(User1), type(uint256).max);
        (uint256 dscMintedUser2, uint256 collateralValueInUsdUser2) = dscEngine.getAccountInfo(User2);
        assertEq(collateralValueInUsdUser2, 30000 ether); //30k usd
        assertEq(dscMintedUser2, 15000 ether); // user2 debt doenst reduce when liquidating user1
        assertEq(dscEngine.getHealthFactor(User2), (collateralValueInUsdUser2 * 1e18) / (dscMintedUser2 * 2));
    }

    /*//////////////////////////////////////////////////////////////
                            BURN DSC TESTS
    //////////////////////////////////////////////////////////////*/
    function testBurnDscFailsIfAmountIsZero()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
    {
        vm.startPrank(User1);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function testBurnDscFailsIfAmountIsGreaterThanDscMinted()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
    {
        vm.startPrank(User1);
        vm.expectRevert();
        dscEngine.burnDSC(15001 ether);
        vm.stopPrank();
    }

    function testBurnDscSuccessForPartialAmount()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
    {
        uint256 expectedCollateralValueInUsd = 10 ether * 3000; // 10 weth * $3000 = 30k usd
        uint256 expectedHealthFactor = (expectedCollateralValueInUsd * 1e18) / (12000 ether * 2); // (collateral value * PRECISION)/ (dsc value * COLLATERALISATION_THRESHOLD_FACTOR)
        vm.startPrank(User1);
        ERC20Mock(address(dsc)).approve(address(dscEngine), 3000 ether);
        dscEngine.burnDSC(3000 ether); // 3k dsc, ups the HF
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        assertEq(dscMinted, 12000 ether); // 12k usd left
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
        assertEq(IERC20(address(dsc)).balanceOf(address(dscEngine)), 0);
        assertEq(IERC20(address(dsc)).balanceOf(address(User1)), 12000 ether);
    }

    function testBurnDscSuccessForAllDsc()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1) // 30k usd
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
    {
        uint256 expectedCollateralValueInUsd = 10 ether * 3000; // 10 weth * $3000 = 30k usd
        uint256 expectedHealthFactor = type(uint256).max;
        vm.startPrank(User1);
        ERC20Mock(address(dsc)).approve(address(dscEngine), 15000 ether);
        dscEngine.burnDSC(15000 ether); // 15k dsc, ups the HF
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        assertEq(dscMinted, 0); // 0 usd left
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
        assertEq(IERC20(address(dsc)).balanceOf(address(dscEngine)), 0);
        assertEq(IERC20(address(dsc)).balanceOf(address(User1)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/
    function testRedeemCollateralFailsWhenAmountIsZero()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1)
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
    {
        vm.startPrank(User1);
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAmount.selector);
        dscEngine.redeemCollateral(s_wETH, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralFailsWhenTokenIsNotAllowed()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1) //30k usd
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
    {
        vm.startPrank(User1);
        vm.expectRevert(DSCEngine.DSCEngine__TokenIsNotAllowed.selector);
        dscEngine.redeemCollateral(address(0x01), 100 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralFailsWhenHealthFactorBreaks()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1) // 30k usd
        mintDSC(User1, 15000 ether) //15k usd, HF = 1
    {
        uint256 expectedHealthFactor = 1 ether / 2; //5e17 or 0.5
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        vm.startPrank(User1);
        dscEngine.redeemCollateral(s_wETH, 5 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralFailsWhenRedeemAmountIsGtDepositedCollateral()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1) //30k usd
        mintDSC(User1, 10000 ether) //10k usd, HF = 1.5
    {
        vm.expectRevert();
        vm.startPrank(User1);
        dscEngine.redeemCollateral(s_wETH, 10.1 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralSuccessForPartialAmountTillHealthFactorIsOk()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1) //30k usd
        mintDSC(User1, 10000 ether) //10k usd, HF = 1.5
    {
        uint256 expectedCollateralValueInUsd = (10 ether - 3.33 ether) * 3000; // (10 weth - 3.33 weth) * $3000 = 20,010 usd
        uint256 expectedHealthFactor = (expectedCollateralValueInUsd * 1e18) / (10000 ether * 2); // (collateral value * PRECISION)/ (dsc value * COLLATERALISATION_THRESHOLD_FACTOR)
        vm.startPrank(User1);
        dscEngine.redeemCollateral(s_wETH, 3.33 ether); // redeem to bring HF to 1
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        assertEq(dscMinted, 10000 ether); // 10k usd
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
    }

    function testRedeemCollateralSuccessForFullAmountTillHealthFactorIsOk()
        external
        mintWethToUser(User1)
        depositWethCollateral(User1) //30k usd
        mintDSC(User1, 5000 ether) //5k usd, HF = 6
    {
        uint256 expectedCollateralValueInUsd = (10 ether - 6.66 ether) * 3000;
        uint256 expectedHealthFactor = (expectedCollateralValueInUsd * 1e18) / (5000 ether * 2); // (collateral value * PRECISION)/ (dsc value * COLLATERALISATION_THRESHOLD_FACTOR)
        vm.startPrank(User1);
        dscEngine.redeemCollateral(s_wETH, 6.66 ether); // redeem to bring HF to ~ 1
        vm.stopPrank();
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(User1);
        assertEq(dscMinted, 5000 ether); // 5k usd
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        assertEq(dscEngine.getHealthFactor(User1), expectedHealthFactor);
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
        uint256 expectedHealthFactor = 0; // since user will ultimately have never minted any dsc after revert
        console2.log(expectedHealthFactor);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        vm.startPrank(User1);
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
        uint256 expectedHealthFactor = type(uint256).max; // since tx reverted, user didnt't mint any dsc
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
