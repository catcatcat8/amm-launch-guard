// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";

/// @title LaunchGuardV3
/// @author Evgeniy Lebedev
/// @notice Creates the first liquidity position in a Uniswap V3 pool at an exact price, even if someone has already
///         created the pool and initialized it at a wrong price.
/// @dev The attack: anyone can create a V3 pool and call `initialize(sqrtPriceX96)` once. An attacker initializes
///      the pool of a token that has not launched yet at an absurd price. `createAndInitializePoolIfNecessary` then
///      skips the initialization, and the team's position is created at the attacker's price.
///
///      The fix: while a pool has no liquidity, a swap moves its price to `sqrtPriceLimitX96` and costs nothing,
///      because there is nothing to trade against. The contract swaps the pool back to the target price and mints the
///      position in the same transaction, so nobody can move the price in between.
///
///      If the attacker added liquidity, the swap trades against it. These trades happen at prices between the
///      attacker's price and the target, that is, at prices better than the target for the caller, but they need
///      tokens. `maxSwapIn0` / `maxSwapIn1` cap the amounts the caller agrees to spend. The tokens received from the
///      swap go to the caller.
///
///      The contract has no owner and keeps no tokens between calls. While it holds the caller's tokens during the
///      mint, re-entering `addInitialLiquidity` is blocked. It works with Uniswap V3 and PancakeSwap V3.
contract LaunchGuardV3 is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice Parameters of `addInitialLiquidity`. The token, fee and tick fields follow
    ///         `INonfungiblePositionManager.MintParams`.
    /// @param positionManager Uniswap V3 (or PancakeSwap V3) NonfungiblePositionManager.
    /// @param token0 The token with the lower address.
    /// @param token1 The token with the higher address.
    /// @param fee Pool fee tier, for example 3000 for 0.3%.
    /// @param sqrtPriceX96 Target price: sqrt(token1 / token0) as a Q64.96 number.
    /// @param tickLower Lower tick of the position.
    /// @param tickUpper Upper tick of the position.
    /// @param amount0Desired Amount of `token0` to deposit at most.
    /// @param amount1Desired Amount of `token1` to deposit at most.
    /// @param amount0Min Minimum amount of `token0` the position must take.
    /// @param amount1Min Minimum amount of `token1` the position must take.
    /// @param maxSwapIn0 Maximum amount of `token0` the caller agrees to spend to move the price down to the target.
    /// @param maxSwapIn1 Maximum amount of `token1` the caller agrees to spend to move the price up to the target.
    /// @param recipient Receiver of the position NFT.
    /// @param deadline The transaction reverts after this timestamp.
    struct Params {
        INonfungiblePositionManager positionManager;
        address token0;
        address token1;
        uint24 fee;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 maxSwapIn0;
        uint256 maxSwapIn1;
        address recipient;
        uint256 deadline;
    }

    /// @notice Emitted when the pool price was not at the target and the contract swapped it back.
    /// @param pool The pool.
    /// @param fromSqrtPriceX96 The price before the swap.
    /// @param toSqrtPriceX96 The price after the swap (the target).
    /// @param amount0 Amount of `token0` paid (positive) or received (negative) by the caller.
    /// @param amount1 Amount of `token1` paid (positive) or received (negative) by the caller.
    event PriceRestored(
        address indexed pool, uint160 fromSqrtPriceX96, uint160 toSqrtPriceX96, int256 amount0, int256 amount1
    );

    /// @notice Emitted when the position is minted.
    /// @param pool The pool.
    /// @param sender The account that paid for the position.
    /// @param recipient Receiver of the position NFT.
    /// @param tokenId The position NFT id.
    /// @param liquidity Liquidity of the position.
    /// @param amount0 Amount of `token0` deposited.
    /// @param amount1 Amount of `token1` deposited.
    event InitialPositionMinted(
        address indexed pool,
        address indexed sender,
        address indexed recipient,
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice `block.timestamp` is after `deadline`.
    error Expired();
    /// @notice `recipient` is the zero address.
    error ZeroAddress();
    /// @notice `token0` is not lower than `token1`.
    error UnsortedTokens();
    /// @notice The swap callback was not called by the pool this contract is swapping in.
    error UnexpectedCallback();
    /// @notice Moving the price needs more tokens than `maxSwapIn0` / `maxSwapIn1` allow.
    error SwapInAboveMax(uint256 amountIn, uint256 maxAmountIn);
    /// @notice The swap did not bring the pool to the target price.
    error PriceNotRestored(uint160 sqrtPriceX96);

    /// @dev The pool this contract is swapping in, set only for the duration of the swap.
    address private transient _swapPool;
    /// @dev The account that pays for the swap. It is stored here and not passed through the callback data, so a fake
    ///      pool returned by a fake position manager cannot make the contract pull tokens from another account.
    address private transient _swapPayer;

    /// @notice Creates and initializes the pool if needed, moves its price to `sqrtPriceX96` if someone has changed
    ///         it, and mints a position.
    /// @dev The caller must approve this contract for `amount0Desired + maxSwapIn0` of `token0` and
    ///      `amount1Desired + maxSwapIn1` of `token1`. Unused tokens are returned to the caller.
    ///      Fee-on-transfer and rebasing tokens are not supported.
    /// @param params See `Params`.
    /// @return pool The pool address.
    /// @return tokenId The position NFT id.
    /// @return liquidity Liquidity of the position.
    /// @return amount0 Amount of `token0` deposited into the position.
    /// @return amount1 Amount of `token1` deposited into the position.
    function addInitialLiquidity(Params calldata params)
        external
        nonReentrant
        returns (address pool, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (block.timestamp > params.deadline) revert Expired();
        if (params.recipient == address(0)) revert ZeroAddress();
        if (params.token0 >= params.token1) revert UnsortedTokens();

        pool = params.positionManager
            .createAndInitializePoolIfNecessary(params.token0, params.token1, params.fee, params.sqrtPriceX96);
        _restorePrice(pool, params);
        (tokenId, liquidity, amount0, amount1) = _mint(params);

        emit InitialPositionMinted(pool, msg.sender, params.recipient, tokenId, liquidity, amount0, amount1);
    }

    /// @notice Uniswap V3 swap callback. Pays the pool for the price-restoring swap.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _paySwap(amount0Delta, amount1Delta, data);
    }

    /// @notice PancakeSwap V3 swap callback. Same as `uniswapV3SwapCallback`.
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _paySwap(amount0Delta, amount1Delta, data);
    }

    /// @dev Swaps the pool to the target price if it is somewhere else. The swap is exact-input with a huge amount and
    ///      the target as the price limit, so it stops exactly at the target. The cost is checked in the callback.
    function _restorePrice(address pool, Params calldata params) private {
        (uint160 current,) = IUniswapV3Pool(pool).slot0();
        if (current == params.sqrtPriceX96) return;

        // token1 per token0 is too high: sell token0 to move the price down. Otherwise sell token1.
        bool zeroForOne = params.sqrtPriceX96 < current;

        _swapPool = pool;
        _swapPayer = msg.sender;
        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool)
            .swap(
                msg.sender,
                zeroForOne,
                type(int128).max,
                params.sqrtPriceX96,
                abi.encode(params.token0, params.token1, params.maxSwapIn0, params.maxSwapIn1)
            );
        _swapPool = address(0);
        _swapPayer = address(0);

        (uint160 restored,) = IUniswapV3Pool(pool).slot0();
        if (restored != params.sqrtPriceX96) revert PriceNotRestored(restored);

        emit PriceRestored(pool, current, restored, amount0, amount1);
    }

    function _paySwap(int256 amount0Delta, int256 amount1Delta, bytes calldata data) private {
        if (msg.sender != _swapPool) revert UnexpectedCallback();
        (address token0, address token1, uint256 maxSwapIn0, uint256 maxSwapIn1) =
            abi.decode(data, (address, address, uint256, uint256));

        if (amount0Delta > 0) _pay(token0, uint256(amount0Delta), maxSwapIn0);
        if (amount1Delta > 0) _pay(token1, uint256(amount1Delta), maxSwapIn1);
    }

    function _pay(address token, uint256 amount, uint256 maxAmount) private {
        if (amount > maxAmount) revert SwapInAboveMax(amount, maxAmount);
        IERC20(token).safeTransferFrom(_swapPayer, msg.sender, amount);
    }

    /// @dev Pulls the desired amounts, mints the position through the position manager and returns what is left.
    function _mint(Params calldata params)
        private
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        IERC20 token0 = IERC20(params.token0);
        IERC20 token1 = IERC20(params.token1);
        address positionManager = address(params.positionManager);

        token0.safeTransferFrom(msg.sender, address(this), params.amount0Desired);
        token1.safeTransferFrom(msg.sender, address(this), params.amount1Desired);
        token0.forceApprove(positionManager, params.amount0Desired);
        token1.forceApprove(positionManager, params.amount1Desired);

        (tokenId, liquidity, amount0, amount1) = params.positionManager
            .mint(
                INonfungiblePositionManager.MintParams({
                    token0: params.token0,
                    token1: params.token1,
                    fee: params.fee,
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    amount0Desired: params.amount0Desired,
                    amount1Desired: params.amount1Desired,
                    amount0Min: params.amount0Min,
                    amount1Min: params.amount1Min,
                    recipient: params.recipient,
                    deadline: params.deadline
                })
            );

        token0.forceApprove(positionManager, 0);
        token1.forceApprove(positionManager, 0);
        _refund(token0);
        _refund(token1);
    }

    function _refund(IERC20 token) private {
        uint256 balance = token.balanceOf(address(this));
        if (balance != 0) token.safeTransfer(msg.sender, balance);
    }
}
