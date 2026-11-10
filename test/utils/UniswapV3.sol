// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Fixtures} from "./Fixtures.sol";

/**
 * @notice Uniswap V3 factory functions used by the tests.
 */
interface ITestV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/**
 * @notice Uniswap V3 pool functions used by the tests.
 */
interface ITestV3Pool {
    function initialize(uint160 sqrtPriceX96) external;

    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick);

    function liquidity() external view returns (uint128);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

/**
 * @notice Uniswap V3 NonfungiblePositionManager functions used by the tests.
 */
interface ITestPositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function factory() external view returns (address);

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @notice Deploys the original Uniswap V3 factory and position manager from `test/fixtures` and adds helpers.
 */
abstract contract UniswapV3Fixture is Fixtures {
    /**
     * @dev Limits of `sqrtPriceX96` in Uniswap V3 (TickMath.MIN_SQRT_RATIO and MAX_SQRT_RATIO).
     */
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function deployUniswapV3(address weth) internal returns (ITestV3Factory factory, ITestPositionManager manager) {
        factory = ITestV3Factory(deployFixture("v3/UniswapV3Factory", ""));
        manager = ITestPositionManager(
            deployFixture("v3/NonfungiblePositionManager", abi.encode(address(factory), weth, address(0)))
        );
    }

    /**
     * @dev sqrt(amount1 / amount0) as a Q64.96 number: the V3 price at which `amount1` of token1 equals `amount0` of
     *      token0.
     */
    function sqrtPriceX96Of(uint256 amount1, uint256 amount0) internal pure returns (uint160) {
        return uint160(Math.sqrt(Math.mulDiv(amount1, 1 << 192, amount0)));
    }

    function priceOf(address pool) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,) = ITestV3Pool(pool).slot0();
    }

    /**
     * @dev Swaps in `pool` from this test contract. With no liquidity in the pool, the swap only moves the price and
     *      both amounts are zero.
     */
    function swapTo(address pool, uint160 sqrtPriceLimitX96) internal returns (int256 amount0, int256 amount1) {
        bool zeroForOne = sqrtPriceLimitX96 < priceOf(pool);
        return ITestV3Pool(pool).swap(address(this), zeroForOne, type(int128).max, sqrtPriceLimitX96, "");
    }

    /**
     * @dev Pays for `swapTo`. The tests that call `swapTo` on a pool with liquidity fund this contract first.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        (bool ok0, bytes memory token0) = msg.sender.staticcall(abi.encodeWithSignature("token0()"));
        (bool ok1, bytes memory token1) = msg.sender.staticcall(abi.encodeWithSignature("token1()"));
        require(ok0 && ok1, "not a pool");
        if (amount0Delta > 0) IERC20(abi.decode(token0, (address))).transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) IERC20(abi.decode(token1, (address))).transfer(msg.sender, uint256(amount1Delta));
    }
}
