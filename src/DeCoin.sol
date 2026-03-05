// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title DeCoin - a decentralized stablecoin
 * @author PhAnToMxSD
 * @dev This contract implements a simple ERC20 token with minting and burning capabilities.
 */

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract DeCoin is ERC20, ERC20Burnable {
    error DeCoin__BurnAmountExceedsLimit();
    error DeCoin__BurnAmountMustBeGreaterThanZero();
    error DeCoin__MintAmountMustBeGreaterThanZero();
    error DeCoin__NoMintToZeroAddress();

    constructor() ERC20("DeCoin", "DECOIN") {}

    function burn(uint256 amount) public override{
        if (amount > balanceOf(msg.sender)) {
            revert DeCoin__BurnAmountExceedsLimit();
        } else if (amount <= 0) {
            revert DeCoin__BurnAmountMustBeGreaterThanZero();
        }
        super.burn(amount);
    }

    function mint(address to, uint256 amount) public {
        if (to == address(0)) {
            revert DeCoin__NoMintToZeroAddress();
        } else if (amount <= 0) {
            revert DeCoin__MintAmountMustBeGreaterThanZero();
        }
        _mint(to, amount);
    }
}
