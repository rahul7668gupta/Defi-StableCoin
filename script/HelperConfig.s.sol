// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wETHUsdPriceFeed;
        address wBTCUsdPriceFeed;
        address wETH;
        address wBTC;
    }

    uint8 public DECIMALS = 8;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            wETHUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063
        });
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wETH != address(0)) {
            return activeNetworkConfig;
        }
        // deploy mocks
        vm.startBroadcast();
        MockV3Aggregator mockV3AggregatorWETH = new MockV3Aggregator(DECIMALS, 3000e8);
        MockV3Aggregator mockV3AggregatorWBTC = new MockV3Aggregator(DECIMALS, 60000e8);
        ERC20Mock mockWETH = new ERC20Mock();
        ERC20Mock mockWBTC = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wETHUsdPriceFeed: address(mockV3AggregatorWETH),
            wBTCUsdPriceFeed: address(mockV3AggregatorWBTC),
            wETH: address(mockWETH),
            wBTC: address(mockWBTC)
        });
    }
}
