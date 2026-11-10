// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

/// @title LaunchGuardV2
/// @author Evgeniy Lebedev
/// @notice Adds the first liquidity to a Uniswap V2 pair at an exact price, even if someone has already sent tokens
///         to the pair and called `sync()`.
/// @dev The attack: before the launch anyone can create the pair, send some dust of the quote token to it and call
///      `sync()`. One reserve becomes non-zero, the other stays zero, and `router.addLiquidity` always reverts in
///      `quote()`. With dust on both sides the router forces the dust ratio on the whole deposit.
///
///      This contract does not use the router. While the pair has no liquidity providers (`totalSupply() == 0`),
///      `pair.mint()` accepts any ratio, so the contract sends the tokens straight to the pair and mints. Tokens that
///      are already in the pair are taken into account: the contract adds `extraA` or `extraB` on top of the deposit,
///      so the final pair balances have the ratio `amountA : amountB`. All tokens in the pair, including the dust,
///      then belong to the LP tokens of `to` (except the `MINIMUM_LIQUIDITY` locked by the pair).
///
///      The contract holds no funds and has no owner. Tokens move from `msg.sender` to the pair in one transaction.
///      It works with any Uniswap V2 fork that keeps the original `mint()` logic (PancakeSwap, SushiSwap, ...).
contract LaunchGuardV2 {
    using SafeERC20 for IERC20;

    /// @notice Parameters of `addInitialLiquidity`.
    /// @param factory Uniswap V2 factory (or a fork). The pair is created if it does not exist.
    /// @param tokenA First token of the pair.
    /// @param tokenB Second token of the pair.
    /// @param amountA Amount of `tokenA` to deposit. `amountA / amountB` is the launch price.
    /// @param amountB Amount of `tokenB` to deposit.
    /// @param maxExtraA Maximum amount of `tokenA` the caller agrees to add on top of `amountA` to balance tokens
    ///        that are already in the pair.
    /// @param maxExtraB Maximum amount of `tokenB` the caller agrees to add on top of `amountB`.
    /// @param to Receiver of the LP tokens.
    /// @param deadline The transaction reverts after this timestamp.
    struct Params {
        IUniswapV2Factory factory;
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        uint256 maxExtraA;
        uint256 maxExtraB;
        address to;
        uint256 deadline;
    }

    /// @notice Emitted when the first liquidity is added to `pair`.
    /// @param pair The pair that received the liquidity.
    /// @param sender The account that paid for the deposit.
    /// @param to Receiver of the LP tokens.
    /// @param depositA Amount of `tokenA` sent to the pair (`amountA + extraA`).
    /// @param depositB Amount of `tokenB` sent to the pair (`amountB + extraB`).
    /// @param liquidity Amount of LP tokens minted to `to`.
    event InitialLiquidityAdded(
        address indexed pair,
        address indexed sender,
        address indexed to,
        uint256 depositA,
        uint256 depositB,
        uint256 liquidity
    );

    /// @notice `block.timestamp` is after `deadline`.
    error Expired();
    /// @notice `amountA` or `amountB` is zero.
    error ZeroAmount();
    /// @notice `to` is the zero address.
    error ZeroAddress();
    /// @notice The pair already has liquidity providers. Extra tokens would be shared with them.
    error PairHasLiquidity();
    /// @notice The tokens already in the pair need more compensation than `maxExtraA` / `maxExtraB` allow.
    error ExtraAboveMax(uint256 extraA, uint256 extraB);

    /// @notice Adds the first liquidity to the `tokenA`/`tokenB` pair so that its price is `amountA / amountB`.
    /// @dev The caller must approve this contract for `amountA + maxExtraA` of `tokenA` and `amountB + maxExtraB` of
    ///      `tokenB`. Fee-on-transfer and rebasing tokens are not supported.
    /// @param params See `Params`.
    /// @return pair The pair address.
    /// @return liquidity Amount of LP tokens minted to `params.to`.
    function addInitialLiquidity(Params calldata params) external returns (address pair, uint256 liquidity) {
        if (block.timestamp > params.deadline) revert Expired();
        if (params.amountA == 0 || params.amountB == 0) revert ZeroAmount();
        if (params.to == address(0)) revert ZeroAddress();

        pair = params.factory.getPair(params.tokenA, params.tokenB);
        if (pair == address(0)) pair = params.factory.createPair(params.tokenA, params.tokenB);
        if (IUniswapV2Pair(pair).totalSupply() != 0) revert PairHasLiquidity();

        (uint256 extraA, uint256 extraB) = _extra(pair, params.tokenA, params.tokenB, params.amountA, params.amountB);
        if (extraA > params.maxExtraA || extraB > params.maxExtraB) revert ExtraAboveMax(extraA, extraB);

        uint256 depositA = params.amountA + extraA;
        uint256 depositB = params.amountB + extraB;
        IERC20(params.tokenA).safeTransferFrom(msg.sender, pair, depositA);
        IERC20(params.tokenB).safeTransferFrom(msg.sender, pair, depositB);
        liquidity = IUniswapV2Pair(pair).mint(params.to);

        emit InitialLiquidityAdded(pair, msg.sender, params.to, depositA, depositB, liquidity);
    }

    /// @notice Returns how much `addInitialLiquidity` would add on top of `amountA` and `amountB` right now.
    /// @dev The result changes if someone sends tokens to the pair before the transaction. Use it to choose
    ///      `maxExtraA` / `maxExtraB` with a margin. Returns zeros if the pair does not exist.
    /// @return extraA Amount of `tokenA` added on top of `amountA`.
    /// @return extraB Amount of `tokenB` added on top of `amountB`.
    function quoteExtra(IUniswapV2Factory factory, address tokenA, address tokenB, uint256 amountA, uint256 amountB)
        external
        view
        returns (uint256 extraA, uint256 extraB)
    {
        if (amountA == 0 || amountB == 0) revert ZeroAmount();
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) return (0, 0);
        return _extra(pair, tokenA, tokenB, amountA, amountB);
    }

    /// @dev Finds the extra amounts that make the final pair balances proportional to `amountA : amountB`:
    ///      `(balanceA + amountA + extraA) / (balanceB + amountB + extraB) = amountA / amountB`.
    ///      Only one side needs extra tokens. It is rounded up, so the final balance of that side is at most 1 wei
    ///      above the exact value. Pair balances are used instead of reserves, so tokens sent without `sync()`
    ///      are counted too.
    function _extra(address pair, address tokenA, address tokenB, uint256 amountA, uint256 amountB)
        private
        view
        returns (uint256 extraA, uint256 extraB)
    {
        uint256 balanceA = IERC20(tokenA).balanceOf(pair);
        uint256 balanceB = IERC20(tokenB).balanceOf(pair);

        // Compare balanceA / balanceB with amountA / amountB without division.
        if (balanceA * amountB >= balanceB * amountA) {
            // tokenB is short (or the ratio is already exact).
            extraB = Math.mulDiv(balanceA, amountB, amountA, Math.Rounding.Ceil) - balanceB;
        } else {
            // tokenA is short.
            extraA = Math.mulDiv(balanceB, amountA, amountB, Math.Rounding.Ceil) - balanceA;
        }
    }
}
