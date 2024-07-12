// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralisedStablecoin} from "./DecentralisedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author Rahul Gupta
 * The system is designed to be as minimal as possible and maintain a 1 Token to $1 peg.
 * This stable coin has the properties of algorithmic stablecoin and is similar to $DAI if $DAI had no governance, fees
 * and was backed by wETH and wBTC.
 * Stablecoin Properties
 * 1. Collateral: Exogenous (wBTC and wETH)
 * 2. Stability: Pegged to $1
 * 3. Minting: Algorithmic
 * Our DSC system should always be overcollaterallised and at no point should the value of collateral be <= all the DSC tokens in USD.
 * @notice This contract is core to the DSC System and handles depositing, withdrawing, minting and burning.
 * @notice This contract is loosely based on MakerDao DSS (DAI) system
 */

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__ZeroAmount();
    error DSCEngine__TokenIsNotAllowed();
    error DSCEngine__AddressArrayLengthMismatch();
    error DSCEngine__CollateralTranferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__DSCMintFailed();
    error DSCEngine__DSCTransferFailed();
    error DSCEngine__HealthFactorOk(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved(uint256 healthFactor);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address tokenAddress => address priceFeed) public s_tokenPriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) public s_collateralDeposited;
    mapping(address user => uint256 amount) public s_dscMinted;
    address[] private s_collateralTokens;

    DecentralisedStablecoin private immutable i_dscToken;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant COLLATERALISATION_THRESHOLD_FACTOR = 2; // 200% overcollateralised or 2x collateral min needed
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant BONUS_PERCENT = 10; // 10% liquidation bonus

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier amountNonZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__ZeroAmount();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_tokenPriceFeeds[token] == address(0)) {
            revert DSCEngine__TokenIsNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice ensure that tokenAddresses[i] matches the price feed for priceFeeds[i]
     * @param tokenAddresses token addresses allowed for collateral against dsc
     * @param priceFeeds price feeds in usd for tokens allowed for collateral
     * @param dscAddress dsc token address
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeeds, address dscAddress) {
        if (tokenAddresses.length != priceFeeds.length) {
            revert DSCEngine__AddressArrayLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenPriceFeeds[tokenAddresses[i]] = priceFeeds[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dscToken = DecentralisedStablecoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev this function deposits collateral and then mints dsc token to the caller
     * @param tokenCollateralAddress collateral token address to be deposited
     * @param amountCollateral amount of collateral token to be deposited
     * @param amountDSCMint amount of dsc to be minted
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCMint);
    }

    /**
     * @dev this function burns dsc first and then redeems collateral token
     * @param tokenCollateralAddress collateral token address to be redeemed
     * @param amountCollateral amount of collateral tokens to be redeemed
     * @param amountDSCBurn amount of dsc to burn against redemption
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCBurn)
        external
    {
        // burn the DSC from user
        burnDSC(amountDSCBurn);
        // redeem user collateral
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @dev this function redeems collateral to caller and does health factor check
     * @param tokenCollateralAddress collateral token address
     * @param amount collateral token amount to be redeemed
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amount)
        public
        isAllowedToken(tokenCollateralAddress)
        amountNonZero(amount)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amount) public amountNonZero(amount) nonReentrant {
        // reduce debt for caller and burn their dsc
        _burnDSC(msg.sender, msg.sender, amount);
        // revert if health factor is broken
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice liquidate the user if health factor is broken
     * @notice liquidation is done by burning the DSC tokens of the user
     * @notice liquidation is done by redeeming the collateral of the user
     * eg: user A submitted $1500 1ETH for $500 DSC = health factor of 1.5
     * if price of ETH tanks to $900, users health factor goes to 0.9 < 1
     * user B can come in and liquidate user A and is incentivised to do so
     * user B can improve user A's health factor by burning $500 DSC and take $900 ETH
     * this incentivises user B to make money
     * @notice on know bug is when no one liquidate's user A and the price of ETH falls below $500
     * it will not be worth the liquidation for user B
     * @notice can only liquidate when userA's health factor is below MIN_HEALTH_FACTOR
     * @notice can liquidate partially
     * @notice you will get liquidation bonus for executing liquidations
     * @notice this protocol needs to be 200% or 2x overcollateralised for the system to work
     * @notice Follows CEI
     * @param tokenCollateralAddress token collateral address for which the user below will get liquidated
     * @param user user who is getting liquidated
     * @param debtToBurn amount of debt to burn in usd
     */
    function liquidateDSC(address tokenCollateralAddress, address user, uint256 debtToBurn)
        external
        isAllowedToken(tokenCollateralAddress)
        amountNonZero(debtToBurn)
        nonReentrant
    {
        // verify if user is liquidatable (health factor < 1, else revert)
        uint256 startHealthFactor = _healthFactor(user);
        if (startHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk(startHealthFactor);
        }
        // get the collateral price of USD in collateral token value
        uint256 collateralToRedeemForLiquidation = getCollateralTokenAmountForUsd(tokenCollateralAddress, debtToBurn);
        // TODO: check fo insolvency before adding bonus
        // eg: if collateral in eth is 0.66ETH
        // bonus will be 10% of 0.66ETH = 0.066ETH
        uint256 bonusCollateral = collateralToRedeemForLiquidation / BONUS_PERCENT;
        // now totalcollateral = 0.66+0.066ETH
        collateralToRedeemForLiquidation += bonusCollateral;
        // redeem the collateral and burn the dsc
        _redeemCollateral(tokenCollateralAddress, collateralToRedeemForLiquidation, user, msg.sender);
        // reduce debt for user and burn msg.sender dsc
        _burnDSC(msg.sender, user, debtToBurn);
        uint256 endHealthFactor = _healthFactor(user);
        if (endHealthFactor <= startHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved(endHealthFactor);
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI pattern
     * @param amount amount of DSC token to mint
     * @notice user must have colleteralled more than minimum threshold already
     */
    function mintDSC(uint256 amount) public amountNonZero(amount) nonReentrant {
        s_dscMinted[msg.sender] += amount;
        // if health factor breaks after minting, revert
        _revertIfHealthFactorIsBroken(msg.sender);
        // else mint the tokens
        bool success = i_dscToken.mint(msg.sender, amount);
        if (!success) {
            revert DSCEngine__DSCMintFailed();
        }
    }

    /**
     * @dev this function deposits the amount of token specified as collateral
     * @param tokenCollateralAddress the collateral token address
     * @param amountCollateral amount of tokens to be put in as collateral
     * @notice follows CEI pattern
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountNonZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__CollateralTranferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice this function reduces debt of the reduceDebtFor address and burns dsc of debtPayer address
     * @notice this function should only be called from funcs which check health factor
     * @param debtPayer burn dsc from the debt payer
     * @param reduceDebtFor reduce debt for this adddress
     * @param amount amount of debt to reduce
     */
    function _burnDSC(address debtPayer, address reduceDebtFor, uint256 amount) private {
        // reduce debt for this userA
        s_dscMinted[reduceDebtFor] -= amount;
        // burn dsc from this userB
        bool success = IERC20(i_dscToken).transferFrom(debtPayer, address(this), amount);
        // assert success
        if (!success) {
            revert DSCEngine__DSCTransferFailed();
        }
        // burn dsc from this address
        i_dscToken.burn(amount);
    }

    /**
     * @notice this function redeems collateral from address and sends to address
     * @notice this func should only be called from functions which check health factors
     * @param tokenCollateralAddress collateral token address to be redeemed
     * @param amount amount of collateral token to be redeemed
     * @param from redeem collateral from this address
     * @param to send the redeemed collateral to this address
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amount, address from, address to) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);
        if (!success) {
            revert DSCEngine__CollateralTranferFailed();
        }
    }

    function _getAccountInfo(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValue)
    {
        totalDSCMinted = s_dscMinted[user];
        totalCollateralValue = getCollateralValue(user);
    }

    /**
     * @param user addres of the user to return health factor for
     * @notice if the health factor is less than 1, its broken, user can get liquidated
     * @return healthFactor how close the user is to liquidation
     */
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 dscMinted, uint256 collateralValue) = _getAccountInfo(user);
        if (dscMinted == 0) {
            // ensuring divison by 0 doesn't happen if user burnt all dsc or didn't mint any
            return type(uint256).max;
        }
        // dsc minted and collateralValue are in 1e18 multiple
        uint256 collateralAdjustedForThreshold = collateralValue / COLLATERALISATION_THRESHOLD_FACTOR;
        // collateralAdjustedForThreshold = ($1000 Collateral Value / 2) = $500
        // collateral/ dscMinted, multiplied with precision to calculate health factor
        // eg: $1000 * 1e18 actual collateral, $100 *1e18 DSC minted
        // healthfactor = ((1000 * 1e18/2) * 1e18)/100 * 1e18 = 1000/2 * 100 = 5
        // eg: $1000 * 1e18 actual collateral, $500 *1e18 DSC minted
        // healthfactor = ((1000 * 1e18/2) * 1e18)/500 * 1e18 = 1000/2 * 500 = 1
        healthFactor = (collateralAdjustedForThreshold * PRECISION) / dscMinted;
    }

    /**
     * @dev this func reverts when a health factor is < MIN_HEALTH_FACTOR
     * @param user user address for which the health factor needs to be calculated and reverted if broken
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                   PUBLIC AND EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getCollateralTokenAmountForUsd(address collateral, uint256 usdAmount)
        public
        view
        returns (uint256 value)
    {
        // get price of collateral token in usd
        // 1ETH - $3000 -> collateralToRedeem -> 3000/usdAmount
        // get collateral value in usd
        address priceFeed = s_tokenPriceFeeds[collateral];
        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            /*uint timeStamp*/
            ,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(priceFeed).latestRoundData();
        uint256 price = uint256(answer) * ADDITIONAL_FEED_PRECISION;
        // collateral token in usd = usdAmount * 1e18 / price
        // eg: price = $1500, usdAmount = $1000, collateral value = 1000/1500 = 0.66ETH
        return (usdAmount * PRECISION) / price;
    }

    function getCollateralValue(address user) public view returns (uint256 value) {
        // for this user, get the total collateral value for all the collateral tokens
        address[] memory collateralTokens = s_collateralTokens;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            value += getUsdValue(token, amount);
        }
        return value;
        // value is 1e18 multipled already
    }

    // value of token in usd
    function getUsdValue(address token, uint256 amount) public view returns (uint256 priceForAmount) {
        address priceFeed = s_tokenPriceFeeds[token];
        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            /*uint timeStamp*/
            ,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(priceFeed).latestRoundData();
        // 1 ETH = $3000
        // n ETH = (3000 * 1e10 * n)/1e18 = $3000*n; (1e8 is the precision we get from price feeds, so to make it 1e18, multipoly by 1e10)
        priceForAmount = (uint256(answer) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
        // 1e10 * 3000 * 1e8
        // 3000 * 1e18
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getAccountInfo(address user) public view returns (uint256 totalDSCMinted, uint256 totalCollateralValue) {
        (totalDSCMinted, totalCollateralValue) = _getAccountInfo(user);
    }
}
