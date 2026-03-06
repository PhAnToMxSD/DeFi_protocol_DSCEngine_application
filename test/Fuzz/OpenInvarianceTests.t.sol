// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DSC} from "src/DSC.sol";
import {DeCoin} from "src/DeCoin.sol";
import {HelperConfig} from "script/helperConfig.s.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {Handler} from "test/Fuzz/Handler.t.sol";

contract DSCTest is StdInvariant, Test {
    DeCoin public deCoin;
    DSC public dsc;
    DeployDSC public deployer;
    HelperConfig public config;
    Handler handler;
    address weth;
    address wbtc;

    address immutable USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, deCoin, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(deCoin, dsc);

        targetContract(address(handler));
    }
}
