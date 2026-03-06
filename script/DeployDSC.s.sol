// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "lib/forge-std/src/Script.sol";
import {DeCoin} from "src/DeCoin.sol";
import {DSC} from "src/DSC.sol";
import {HelperConfig} from "script/helperConfig.s.sol";

contract DeployDSC is Script {
    struct NetworkConfig {
        address wethPriceFeed;
        address wbtcPriceFeed;
        address weth;
        address wbtc;
        uint256 key;
    }

    function run() public returns (DSC dsc, DeCoin deCoin, HelperConfig config) {
        config = new HelperConfig();
        (address wethPriceFeed, address wbtcPriceFeed, address weth, address wbtc, uint256 key) =
            config.activeNetworkConfig();
        address[] memory tokenCollateral = new address[](2);
        tokenCollateral[0] = weth;
        tokenCollateral[1] = wbtc;
        address[] memory priceFeeds = new address[](2);
        priceFeeds[0] = wethPriceFeed;
        priceFeeds[1] = wbtcPriceFeed;
        vm.startBroadcast(key);
        deCoin = new DeCoin();
        dsc = new DSC(tokenCollateral, priceFeeds, deCoin);
        vm.stopBroadcast();
        return (dsc, deCoin, config);
    }
}
