// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import { ITSwapPool } from "../interfaces/ITSwapPool.sol";
import { IPoolFactory } from "../interfaces/IPoolFactory.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract OracleUpgradeable is Initializable {
    // @audit -gas maybe make immutable
    address private s_poolFactory;
    /** notes
    storage -> proxy
    logic -> implementation
    the constructor will run in the implementation
    but there is not storage allowed in the implementation
    so we use `Initializable` to help initilize storage in proxies

    onlyInitializing allowed you to only call the function only once


    */
    // @notes This function is a replacement for the constructor header
    // onlyInitializing means this function can only be called once
    function __Oracle_init(address poolFactoryAddress) internal onlyInitializing {
        __Oracle_init_unchained(poolFactoryAddress);
    }
    //@notes this function is a replacement for the constructors logic
    function __Oracle_init_unchained(address poolFactoryAddress) internal onlyInitializing {
        // @audit ADERYN -info No zero address check
        s_poolFactory = poolFactoryAddress;
    }

    function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
        return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }

    function getPrice(address token) external view returns (uint256) {
        return getPriceInWeth(token);
    }

    function getPoolFactoryAddress() external view returns (address) {
        return s_poolFactory;
    }
}
