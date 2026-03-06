// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DSC} from "src/DSC.sol";
import {DeCoin} from "src/DeCoin.sol";
import {ERC20Mock} from "test/Mocks/ERC20Mock.sol";

contract Handler is Test {
    DeCoin public deCoin;
    DSC public dsc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    address[] tokenAdd = dsc.getTokenAddresses();

    ERC20Mock weth = ERC20Mock(tokenAdd[0]);
    ERC20Mock wbtc = ERC20Mock(tokenAdd[1]);

    constructor(DeCoin _deCoin, DSC _dsc) {
        deCoin = _deCoin;
        dsc = _dsc;
    }

    function depositCollateral(uint256 tokenColSeed, uint256 amount) public {
        ERC20Mock tokenColAdd = tokenColRand(tokenColSeed);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        tokenColAdd.mint(msg.sender, amount);
        tokenColAdd.approve(address(dsc), amount);
        dsc.depositCollateral(address(tokenColAdd), amount);
        vm.stopPrank();
    }

    function tokenColRand(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 1) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function redeemCollateral(uint256 seed, uint256 amount) public {
        ERC20Mock tokenColAdd = tokenColRand(seed);
        amount = bound(amount, 0, dsc.getUserCollateral(msg.sender));
        vm.startPrank(msg.sender);
        dsc.redeemCollateral(address(tokenColAdd), amount);
        vm.stopPrank();
    }

    function mintDSC(uint256 amount) public {
        uint256 col = dsc.getUserCollateral(msg.sender);
        uint256 totaldsc = dsc.getAmountOfDSCheld(msg.sender);
        uint256 maxc = col / 2 - totaldsc;
        amount = bound(amount, 0, maxc);
        vm.startPrank(msg.sender);
        dsc.mint(amount);
        vm.stopPrank();
    }
}
