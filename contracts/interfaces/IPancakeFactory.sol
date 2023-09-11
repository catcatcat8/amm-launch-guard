// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title IPancakeFactory
 * @author gotbit
 * @dev Required the PancakeFactory contract interface
 */
interface IPancakeFactory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}
