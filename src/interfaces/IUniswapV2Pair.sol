// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Uniswap V2 pair functions used by LaunchGuardV2. Any V2 fork (PancakeSwap, SushiSwap, ...) has them.
interface IUniswapV2Pair {
    function totalSupply() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);
}
