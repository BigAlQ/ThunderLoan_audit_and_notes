// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// q Why are we only using the price of a pool token in WETH? Shouldn't we also have USD prices?
interface ITSwapPool {
    function getPriceOfOnePoolTokenInWeth() external view returns (uint256);
}
