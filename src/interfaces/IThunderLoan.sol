// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @audit -info The IThunderLoan contract should be implemented by the ThunderLoan contract!
interface IThunderLoan {
    // @audit -low/info The repay function takes an IERC20 token address as an argument rather than an address type in
    // ThunderLoan.sol
    function repay(address token, uint256 amount) external;
}
