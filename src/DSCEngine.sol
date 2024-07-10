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
    error DSC_Engine__BrokenHealthFactor(uint256 userHealthFactor);
    error DSCEngine__DSCMintFailed();

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
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCMint);
    }

    function redeemCollateralForDSC() external {}

    function redeemCollatral() external {}
    function burnDSC() external {}

    function liquidateDSC() external {}

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
                          EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHealthFactor(address user) external view {}

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
            revert DSC_Engine__BrokenHealthFactor(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                   PUBLIC AND EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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
}
