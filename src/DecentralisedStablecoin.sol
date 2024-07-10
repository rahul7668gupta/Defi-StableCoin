// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralised Stablecoin
 * @author Rahul Gupta
 * @notice This contract is a ERC20 implementation of our Decentralised stablecoin
 * and is meant to be governed by the DSCEngine.sol contract.
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * Collateral: Exogeneous (wBTC and wETH)
 */
contract DecentralisedStablecoin is ERC20Burnable, Ownable {
    error DecentralisedStablecoin__BurnMoreThanZeroTokens();
    error DecentralisedStablecoin__InsufficientBalanceOfCaller();
    error DecentralisedStablecoin__CannotMintToNullAddress();
    error DecentralisedStablecoin__CannotMintZeroTokens();

    constructor() ERC20("DecentralisedStablecoin", "DSC") Ownable(msg.sender) {}

    // burn
    // burn only if user has enough balance > 0
    // burn more than 0 tokens only
    // mint
    // mint to non 0 addresses
    // mint amount should be gt 0

    /**
     * @dev this function burns the amount of tokens from msg.sender, onlyOwner
     * @param _amount amount of tokens to be burnt
     */
    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert DecentralisedStablecoin__BurnMoreThanZeroTokens();
        }
        if (balanceOf(msg.sender) <= 0) {
            revert DecentralisedStablecoin__InsufficientBalanceOfCaller();
        }
        super._burn(msg.sender, _amount);
    }

    /**
     * @dev this function mints the specified amount of tokens to the _to address, onlyOwner
     * @param _to receiver of the minted tokens
     * @param _amount amount of tokens to be minted
     * @return returns true when minted successfully
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStablecoin__CannotMintToNullAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStablecoin__CannotMintZeroTokens();
        }
        _mint(_to, _amount);
        return true;
    }
}
