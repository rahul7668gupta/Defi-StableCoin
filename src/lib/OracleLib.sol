// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Oracle Lib
 * @author Rahul Gupta
 * @notice this lib gets latest round data from chainlink price feed and checks if the same is stale
 * if stale than threshold, revert and caller functions will never be able to execute
 * rendering the caller protocol to a halt
 */
library OracleLib {
    error OracleLib__MaxStalenessThresholdCrossed(uint256 stalenessTime);

    uint256 internal constant MAX_STALENESS_THRESHOLD = 3 hours;
    /**
     * @notice this function gets latest round data from chainlink price feed
     * and reverts if it is stale than threshold
     * @param aggregatorV3Interface chainlink price feed interface
     * @return roundID, answer, startedAt, timeStamp, answeredInRound
     */

    function staleCheckOraclePriceData(AggregatorV3Interface aggregatorV3Interface)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundID, int256 answer, uint256 startedAt, uint256 timeStamp, uint80 answeredInRound) =
            aggregatorV3Interface.latestRoundData();
        uint256 stalenessTime = (block.timestamp - timeStamp);
        if (stalenessTime > MAX_STALENESS_THRESHOLD) {
            revert OracleLib__MaxStalenessThresholdCrossed(stalenessTime);
        }
        return (roundID, answer, startedAt, timeStamp, answeredInRound);
    }
}
