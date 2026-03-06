// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DeCoin} from "./DeCoin.sol";
import {OracleLib} from "./OracleLib.sol";

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
    error DSC__HealthFactorBelowThresholdAfterWithdrawingCollateral();
    error DSC__AmountMustBeLessThanOrEqualToBalance();
    error DSC__HealthFactorBelowThresholdForLiquidation();
    error DSC__HealthFactorNotImprovedAfterDebtPayed();
    error DSC__BreaksHealthFactor(uint256 userHealthFactor);

    using OracleLib for AggregatorV3Interface;

    event DepositedCollateral(address indexed user, address indexed tokenCollateral, uint256 indexed amount);

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address tokenCollateral => uint256 amountCollateral)) private
        userToAmountCollateralForDifferentTokenCollateralAddresses;
    mapping(address user => uint256 dsc_held) private amountOfDSCheld;
    address[] private s_tokenAddresses;
    address private immutable deCoin;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;

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
        bool success = IERC20(tokenCollateral).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSC__transferFailed();
        } else {
            emit DepositedCollateral(msg.sender, tokenCollateral, amount);
        }
    }

    function depositCollateralAndMint(address tokenCollateral, uint256 collateralAmount, uint256 mintAmount) external {
        //Note- this function allows users to deposit collateral and mint DSC tokens in a single transaction. It first calls the depositCollateral function to handle the collateral deposit and then calls the mint function to mint the specified amount of DSC tokens for the user.
        bytes memory payload =
            abi.encodeWithSelector(this.depositCollateral.selector, tokenCollateral, collateralAmount);
        (bool success,) = address(this).call(payload);
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
        if (_getHealthFactor(totalCol) < MINIMUM_HEALTH_FACTOR) {
            revert DSC__HealthFactorBelowThreshold();
        } else {
            return true;
        }
    }

    function redeemCollateral(address tokenCollateral, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        //Note- this function allows users to redeem their collateral only if the user has enough collateral to redeem. This will be checked by first simulating the transaction and then checking if user has enough collateral left.
        _redeemCollateral(msg.sender, tokenCollateral, amount);
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) nonReentrant {
        //Note- this function allows users to burn their DSC tokens to reduce their debt and improve their health factor. The user can only burn DSC tokens if they have enough DSC tokens to burn and if burning the specified amount of DSC tokens does not make their health factor fall below the threshold.
        _burnDSC(msg.sender, msg.sender, amount);
    }

    function redeemCollateralAndBurnDSC(address tokenCollateral, uint256 collateralAmount, uint256 burnAmount)
        external
    {
        //Note- this function allows users to redeem their collateral and burn their DSC tokens in a single transaction. It first calls the redeemCollateral function to handle the collateral redemption and then calls the burnDSC function to burn the specified amount of DSC tokens for the user.
        _burnDSC(msg.sender, msg.sender, burnAmount);
        _redeemCollateral(msg.sender, tokenCollateral, collateralAmount);
    }

    function liquidate(address tokenCollateral, address user, uint256 amount) public nonReentrant moreThanZero(amount) {
        //Note- this function allows anyone to liquidate an undercollateralized position. It checks if the user's health factor is below the threshold and if so, it allows the liquidator to redeem a portion of the user's collateral in exchange for burning a portion of the user's DSC tokens. The amount of collateral that can be redeemed and the amount of DSC tokens that need to be burned are determined based on the user's health factor and the liquidation threshold. Here, a user would be eligible for liquidation once the ratio of their collateral and their DSC falls below 2.
        uint256 totalCol = getUserCollateral(user);
        if (_getHealthFactor(totalCol) < MINIMUM_HEALTH_FACTOR) {
            revert DSC__HealthFactorBelowThresholdForLiquidation();
        }
        uint256 tokenCollateralFromDebt = getAmountFromTokens(tokenCollateral, amount);
        userToAmountCollateralForDifferentTokenCollateralAddresses[user][tokenCollateral] -= amount;
        uint256 bonus = (tokenCollateralFromDebt * LIQUIDATION_BONUS) / 100;
        bool success = IERC20(tokenCollateral).transfer(msg.sender, tokenCollateralFromDebt + bonus);
        if (!success) {
            revert DSC__transferFailed();
        }
        amountOfDSCheld[user] -= amount;
        _burnDSC(msg.sender, user, amount);

        if (!_checkHealthFactor(user)) {
            revert DSC__HealthFactorNotImprovedAfterDebtPayed();
        }
    }

    function getAmountFromTokens(address tokenCollateral, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        uint256 collateralAmount = (amount * 1e18) / ((uint256(price * 1e10) * LIQUIDATION_THRESHOLD) / 100);
        return collateralAmount;
    }

    function _burnDSC(address from, address onBehalfOf, uint256 amount) internal {
        if (amount <= 0) {
            revert DSC__AmountMustBeGreaterThanZero();
        }
        if (amount > amountOfDSCheld[onBehalfOf]) {
            revert DSC__AmountMustBeLessThanOrEqualToBalance();
        }
        amountOfDSCheld[onBehalfOf] -= amount;
        DeCoin(deCoin).burnFrom(from, amount);
        if (!_checkHealthFactor(onBehalfOf)) {
            revert DSC__HealthFactorBelowThresholdAfterWithdrawingCollateral();
        }
    }

    function _redeemCollateral(address from, address tokenCollateral, uint256 amount) internal {
        userToAmountCollateralForDifferentTokenCollateralAddresses[from][tokenCollateral] -= amount;
        bool success = IERC20(tokenCollateral).transfer(from, amount);
        if (!success) {
            revert DSC__transferFailed();
        }
        if (!_checkHealthFactor(from)) {
            revert DSC__HealthFactorBelowThresholdAfterWithdrawingCollateral();
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSC__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _getAccountInformation(address user) private view returns (uint256, uint256) {
        uint256 totalDscMinted = amountOfDSCheld[user];
        uint256 collateralValueInUsd = getUserCollateral(user);
        return (totalDscMinted, collateralValueInUsd);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAddresses() public view returns (address[] memory) {
        return s_tokenAddresses;
    }

    function getAmountOfDSCheld(address user) public view returns (uint256) {
        return amountOfDSCheld[user];
    }
}
