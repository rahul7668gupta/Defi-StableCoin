// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {DecentralisedStablecoin} from "../../src/DecentralisedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DecentralisedStablecoin dsc;
    DSCEngine dscEngine;
    address s_wETH;
    address s_wBTC;
    uint256 constant MAX_SIZE = type(uint96).max;
    uint256 public timesMintedDsc;
    address[] private depositedUsers;

    constructor(DecentralisedStablecoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        s_wETH = collateralTokens[0];
        s_wBTC = collateralTokens[1];
    }

    function depositCollateral(uint256 collateralTokenSeed, uint256 collateralAmount) external {
        address collateralToken = _getCollateralTokenAddressFromSeed(collateralTokenSeed);
        collateralAmount = bound(collateralAmount, 1, MAX_SIZE);
        vm.startPrank(msg.sender);
        ERC20Mock(collateralToken).mint(msg.sender, collateralAmount);
        ERC20Mock(collateralToken).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateral(collateralToken, collateralAmount);
        vm.stopPrank();
        // can have a duplicates in here, fix this
        depositedUsers.push(msg.sender);
    }

    function redeemCollateral(uint256 senderSeed, uint256 collateralTokenSeed, uint256 collateralAmount) external {
        console2.log("depositedUsers.length: ", depositedUsers.length);
        if (depositedUsers.length == 0) {
            // no need to call as no user has deposited yet
            return;
        }
        address sender = depositedUsers[senderSeed % depositedUsers.length];
        console2.log("sender: ", sender);
        address collateralToken = _getCollateralTokenAddressFromSeed(collateralTokenSeed);
        uint256 userCollateralTokenBalance = dscEngine.getCollateralBalanceOfUser(collateralToken, sender);
        collateralAmount = bound(collateralAmount, 0, userCollateralTokenBalance);
        if (collateralAmount == 0) {
            // if amount is 0, no need to proceed as amount non zero error will occur
            return;
        }
        uint256 collateralAmountValueInIsd = dscEngine.getUsdValue(collateralToken, collateralAmount);
        uint256 collateralUserTokenValueInUsd = dscEngine.getUsdValue(collateralToken, userCollateralTokenBalance);
        (uint256 dscValueInUsd, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(sender);
        if (dscValueInUsd == 0) {
            // if dsc value is 0, no need to proceed as it will cause panic: division or modulo by zero
            return;
        }
        // TODO: redeem token amount value in usd should be deposited value in usd - (minted dsc * 2)
        // if redeem token value is lt the collateral token value in usd, return;
        if (collateralValueInUsd - (dscValueInUsd * 2) < collateralAmountValueInIsd) {
            // if the collateral value is less than the redemption value, no need to proceed
            // this causes HF to break
            return;
        }
        // if redeem value is more than deposited collateral, return
        if (userCollateralTokenBalance < collateralAmount) {
            // if the collateral value is less than the redemption value, no need to proceed
            // this causes underflows
            return;
        }
        if ((collateralUserTokenValueInUsd * 1e18) / (dscValueInUsd * 2) < 1e18) {
            // if the collateral value is less than half of the dsc value, no need to proceed
            // this condition shows a broken health factor
            return;
        }
        vm.startPrank(sender);
        dscEngine.redeemCollateral(collateralToken, collateralAmount);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 senderSeed) external {
        console2.log("depositedUsers.length: ", depositedUsers.length);
        if (depositedUsers.length == 0) {
            // no need to call as no user has deposited yet
            return;
        }
        address sender = depositedUsers[senderSeed % depositedUsers.length];
        console2.log("sender: ", sender);
        // amount should be bound by the n collaral deposited value in usd
        (uint256 dscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInfo(sender);
        console2.log("sender dsc minted: ", dscMinted);
        console2.log("sender collateral value in usd: ", collateralValueInUsd);
        int256 maxDscToMint = int256(collateralValueInUsd) / 2 - int256(dscMinted);
        console2.log("max dsc to mint: ", maxDscToMint);
        if (maxDscToMint < 0) {
            // if max dsc to mint is less than zero, no need to mint and func takes a uint arg
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            // if amount is 0, no need to proceed as amount non zero error will occur
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        timesMintedDsc++;
    }

    function _getCollateralTokenAddressFromSeed(uint256 seed) private view returns (address) {
        if (seed % 2 == 0) {
            return s_wETH;
        } else {
            return s_wBTC;
        }
    }
}
