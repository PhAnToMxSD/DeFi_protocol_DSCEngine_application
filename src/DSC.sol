// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DeCoin} from "./DeCoin.sol";

/**
 * @title DSC Engine
 * @author PhAnToMxSD
 *
 * This contract implements the core logic for a decentralized stablecoin (DSC) system. It allows users to deposit collateral, mint stablecoins, and manage their positions. The contract also includes functionality for liquidating undercollateralized positions and redeeming stablecoins for collateral.
 *
 * The DeCoin will be very basic and -
 * 1. will be pegged to the value of Ethereum.
 * 2. will be minted by depositing wETH and wBTC as collateral.
 * 3. the total circulation of the DeCoin supply will be determined by the total value of the collateral deposited in the system.
 *
 * We should always have more collateral than the total supply of DeCoin to ensure  the stability of the system. This means that the value of the collateral should always be greater than the value of the DeCoin in circulation.
 */

contract DSC is ReentrancyGuard {
    error DSC__AmountMustBeGreaterThanZero();
    error DSC__tokenAddrLenMustMatchPriceFeedLen();
    error DSC__TokenAddressIsNotMappedHenceNotAllowed();
    error DSC__transferFailed();
    error DSC__HealthFactorBelowThreshold();

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address tokenCollateral => uint256 amountCollateral)) private
        userToAmountCollateralForDifferentTokenCollateralAddresses;
    mapping(address user => uint256 dsc_held) private amountOfDSCheld;
    address[] private s_tokenAddresses;
    address private immutable deCoin;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;

    constructor(address[] memory tokenCollateral, address[] memory priceFeeds, DeCoin _deCoin) {
        if (tokenCollateral.length != priceFeeds.length) {
            revert DSC__tokenAddrLenMustMatchPriceFeedLen();
        }
        for (uint256 i = 0; i < tokenCollateral.length; i++) {
            s_priceFeeds[tokenCollateral[i]] = priceFeeds[i];
            s_tokenAddresses.push(tokenCollateral[i]);
        }
        deCoin = address(_deCoin);
    }

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSC__AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenCollateral) {
        if (s_priceFeeds[tokenCollateral] == address(0)) {
            revert DSC__TokenAddressIsNotMappedHenceNotAllowed();
        }
        _;
    }

    function depositCollateral(address tokenCollateral, uint256 amount)
        external
        moreThanZero(amount)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        //Note- tokenCollateral is the address of the collateral token (wETH or wBTC) and amount is the quantity of the collateral token being deposited.
        userToAmountCollateralForDifferentTokenCollateralAddresses[msg.sender][tokenCollateral] += amount;
        bool success = IERC20(tokenCollateral).transfer(msg.sender, amount);
        if (!success) {
            revert DSC__transferFailed();
        }
    }

    function depositCollateralAndMint(address tokenCollateral, uint256 collateralAmount, uint256 mintAmount) external {
        //Note- this function allows users to deposit collateral and mint DSC tokens in a single transaction. It first calls the depositCollateral function to handle the collateral deposit and then calls the mint function to mint the specified amount of DSC tokens for the user.
        bytes memory payload = abi.encodeWithSelector(this.depositCollateral.selector, tokenCollateral, collateralAmount);
        (bool success, ) = address(this).call(payload);
        if (!success) {
            revert DSC__transferFailed();
        }
        mint(mintAmount);
    }

    function mint(uint256 amount) public moreThanZero(amount) nonReentrant {
        //Note- this function mints the user the amount of tokes the user needs based on the health factor of the user, ie minting will happen only if the total DSC tokens the user will own after this mint does not make the user overcollaterzied
        amountOfDSCheld[msg.sender] += amount;
        _checkHealthFactor(msg.sender);
        DeCoin(deCoin).mint(msg.sender, amount);
    }

    function getUserCollateral(address user) public view returns (uint256) {
        //Note- this function calculates the total value of the collateral deposited by the user in USD by fetching the price of each collateral token from the respective Chainlink price feeds and multiplying it by the amount of that token deposited by the user.
        uint256 totalCollateralValue;
        for (uint256 i = 0; i < s_tokenAddresses.length; i++) {
            uint256 amount = userToAmountCollateralForDifferentTokenCollateralAddresses[user][s_tokenAddresses[i]];
            uint256 getval = _getPriceFeedData(s_tokenAddresses[i], amount);
            totalCollateralValue += getval;
        }
        return totalCollateralValue;
    }

    function _getPriceFeedData(address token, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(token);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price * 1e10) * amount) / 1e18;
    }

    function _getHealthFactor(uint256 totalCol) private view returns (uint256) {
        //Note- this function calculates the health factor of the user
        uint256 xyz;
        xyz = ((totalCol * LIQUIDATION_THRESHOLD) / 100) * 1e18 / amountOfDSCheld[msg.sender];
        return xyz;
    }

    function _checkHealthFactor(address user) internal view returns (bool) {
        //Note- this function checks if the health factor of the user is above a certain threshold (e.g., 1) to ensure that the user is not overcollateralized after minting new DSC tokens. If the health factor is below the threshold, the function reverts with an error. Otherwise, it returns true.
        uint256 totalCol = getUserCollateral(user);
        if (_getHealthFactor(totalCol) < 1) {
            revert DSC__HealthFactorBelowThreshold();
        } else {
            return true;
        }
    }
}
