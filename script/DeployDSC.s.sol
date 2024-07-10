// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralisedStablecoin} from "../src/DecentralisedStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeeds;

    function run() external returns (DecentralisedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wETHUsdPriceFeed, address wBTCUsdPriceFeed, address wETH, address wBTC) =
            helperConfig.activeNetworkConfig();
        priceFeeds = [wETHUsdPriceFeed, wBTCUsdPriceFeed];
        tokenAddresses = [wETH, wBTC];
        vm.startBroadcast();
        DecentralisedStablecoin dsc = new DecentralisedStablecoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeeds, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine, helperConfig);
    }
}
