// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "lib/forge-std/src/Test.sol";
import {DeCoin} from "src/DeCoin.sol";
import {DSC} from "src/DSC.sol";
import {HelperConfig} from "script/helperConfig.s.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {ERC20Mock} from "test/Mocks/ERC20Mock.sol";

contract TestDSC is Test {
    DeCoin public deCoin;
    DSC public dsc;
    DeployDSC public deployer;
    HelperConfig public helperConfig;

    address immutable USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, deCoin, helperConfig) = deployer.run();
    }

    address[] tokenCollateral;
    address[] priceFeeds;

    function testConstructor() public {
        (address wethPriceFeed,, address weth, address wbtc,) = helperConfig.activeNetworkConfig();
        tokenCollateral.push(weth);
        tokenCollateral.push(wbtc);
        priceFeeds.push(wethPriceFeed);
        vm.expectRevert(DSC.DSC__tokenAddrLenMustMatchPriceFeedLen.selector);
        new DSC(tokenCollateral, priceFeeds, deCoin);
    }
}
