// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/* What are the invariants of DSCEngine.sol */
/*
  1. Dsc minted should always be 1/2 of total value of collateral
  2. Getter view functions should never revert
*/

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console2} from "forge-std/Test.sol";
import {DecentralisedStablecoin} from "../../src/DecentralisedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DecentralisedStablecoin dsc;
    DSCEngine dscEngine;
    address wETHUsdPriceFeed;
    address wBTCUsdPriceFeed;
    HelperConfig config;
    address s_wETH;
    address s_wBTC;
    Handler handler;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wETHUsdPriceFeed, wBTCUsdPriceFeed, s_wETH, s_wBTC) = config.activeNetworkConfig();
        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    function invariant_protocolMustRemainSolvent() public view {
        uint256 dscTotalSupply = dsc.totalSupply();
        uint256 wethDscEngineBalance = IERC20(s_wETH).balanceOf(address(dscEngine));
        uint256 wbtcDscEngineBalance = IERC20(s_wBTC).balanceOf(address(dscEngine));
        uint256 wethValue = dscEngine.getUsdValue(s_wETH, wethDscEngineBalance);
        uint256 wbtcValue = dscEngine.getUsdValue(s_wBTC, wbtcDscEngineBalance);
        uint256 dscEngineTotalCollateralValue = wethValue + wbtcValue;
        console2.log("wethValue: ", wethValue);
        console2.log("wbtcValue: ", wbtcValue);
        console2.log("dscTotalSupply: ", dscTotalSupply);
        console2.log("timesMintedDsc: ", handler.timesMintedDsc());
        assert(dscTotalSupply <= dscEngineTotalCollateralValue);
    }

    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getCollateralTokens();
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getPrecision();
        dscEngine.getCollateralisationThresholdFactor();
        dscEngine.getMinHealthFactor();
        dscEngine.getBonusPercent();
        dscEngine.getDSCAddress();
    }
}
