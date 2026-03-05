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

    function run() public returns (DSC dsc, DeCoin deCoin) {
        HelperConfig helperConfig = new HelperConfig();

        NetworkConfig memory activeNetworkConfig = helperConfig.activeNetworkConfig;
        address[] memory tokenCollateral = [activeNetworkConfig.weth, activeNetworkConfig.wbtc];
        address[] memory priceFeeds = [activeNetworkConfig.wethPriceFeed, activeNetworkConfig.wbtcPriceFeed];
        vm.startBroadcast();
        deCoin = new DeCoin();
        dsc = new DSC(tokenCollateral, priceFeeds, address(deCoin));
        vm.stopBroadcast();
        return (dsc, deCoin);
    }
}
