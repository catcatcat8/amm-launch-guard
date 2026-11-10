// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice Uniswap V3 pool functions used by LaunchGuardV3. PancakeSwap V3 pools have them too.
 * @dev `slot0` returns more values; only the first two are decoded, so the interface also fits PancakeSwap V3,
 *      whose `slot0` has a different type for `feeProtocol`.
 */
interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}
