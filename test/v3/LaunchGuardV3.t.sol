// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {LaunchGuardV3} from "../../src/LaunchGuardV3.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3Pool.sol";
import {FakePositionManager, FakeV3Pool, SilentV3Pool} from "../mocks/FakeV3.sol";
import {ReentrantERC20} from "../mocks/ReentrantERC20.sol";
import {BaseV3Test} from "../utils/BaseV3Test.sol";
import {ITestPositionManager} from "../utils/UniswapV3.sol";

contract LaunchGuardV3Test is BaseV3Test {
    LaunchGuardV3 internal guard;

    function setUp() public override {
        super.setUp();
        guard = new LaunchGuardV3();

        vm.startPrank(team);
        newToken.approve(address(guard), type(uint256).max);
        wbnb.approve(address(guard), type(uint256).max);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Launch
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * @notice After the attack the guard swaps the empty pool back to the target price for free and mints.
     */
    function test_GuardRestoresTargetPrice() public {
        address pool = attack(ATTACKER_PRICE);
        uint256 teamNewBefore = newToken.balanceOf(team);
        uint256 teamWbnbBefore = wbnb.balanceOf(team);

        vm.expectEmit(address(guard));
        emit LaunchGuardV3.PriceRestored(pool, ATTACKER_PRICE, targetPrice, 0, 0);
        (address launched, uint256 tokenId,, uint256 amount0, uint256 amount1) = _launch(_params());

        assertEq(launched, pool);
        assertEq(priceOf(pool), targetPrice);
        assertEq(positionManager.ownerOf(tokenId), team);
        assertApproxEqRel(amount0, AMOUNT_NEW, 1e12);
        assertApproxEqRel(amount1, AMOUNT_WBNB, 1e12);

        // The team paid only for the position. The guard keeps no tokens and no approvals.
        assertEq(newToken.balanceOf(team), teamNewBefore - amount0);
        assertEq(wbnb.balanceOf(team), teamWbnbBefore - amount1);
        _assertGuardIsClean();
    }

    /**
     * @notice Without the attack the guard creates and initializes the pool at the target price.
     */
    function test_CreatesAndInitializesPool() public {
        assertEq(poolOf(), address(0));

        (address pool,,,,) = _launch(_params());

        assertEq(pool, poolOf());
        assertEq(priceOf(pool), targetPrice);
    }

    /**
     * @notice A pool that was created but not initialized is initialized at the target price.
     */
    function test_InitializesCreatedPool() public {
        vm.prank(attacker);
        address pool = factory.createPool(address(newToken), address(wbnb), FEE);

        _launch(_params());

        assertEq(priceOf(pool), targetPrice);
    }

    /**
     * @notice A pool initialized below the target price is moved up.
     */
    function test_PriceBelowTarget() public {
        uint160 lowPrice = sqrtPriceX96Of(1, 1e9); // 1 NEW = 0.000000001 WBNB
        address pool = attack(lowPrice);

        vm.expectEmit(address(guard));
        emit LaunchGuardV3.PriceRestored(pool, lowPrice, targetPrice, 0, 0);
        _launch(_params());

        assertEq(priceOf(pool), targetPrice);
    }

    /**
     * @notice A pool already at the target price needs no swap.
     */
    function test_PriceAlreadyAtTarget() public {
        address pool = attack(targetPrice);

        _launch(_params());

        assertEq(priceOf(pool), targetPrice);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Attacker liquidity
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * @notice The attacker adds WBNB-only liquidity between the target and the attacker's price. The guard has to
     *         swap through it: the team pays a little NEW and receives the attacker's WBNB.
     */
    function test_BuysAttackerLiquidity() public {
        address pool = attack(ATTACKER_PRICE);
        _addAttackerLiquidity(10e18);

        LaunchGuardV3.Params memory params = _params();
        params.maxSwapIn0 = 1e18;

        uint256 teamNewBefore = newToken.balanceOf(team);
        uint256 teamWbnbBefore = wbnb.balanceOf(team);
        (,,, uint256 amount0, uint256 amount1) = _launch(params);

        assertEq(priceOf(pool), targetPrice);

        // The swap took some NEW, within the limit.
        uint256 spentOnSwap = teamNewBefore - amount0 - newToken.balanceOf(team);
        assertGt(spentOnSwap, 0);
        assertLe(spentOnSwap, params.maxSwapIn0);
        // The team got the attacker's 10 WBNB, minus a few wei of rounding inside the pool.
        assertApproxEqAbs(wbnb.balanceOf(team), teamWbnbBefore - amount1 + 10e18, 1e6);
        _assertGuardIsClean();
    }

    /**
     * @notice If the attacker has some NEW, they can set a low price and add NEW-only liquidity above it. The guard
     *         moves the price up through it: the team pays a little WBNB and receives the attacker's NEW.
     */
    function test_BuysAttackerLiquidityAbovePrice() public {
        vm.prank(team);
        newToken.transfer(attacker, 10e18);

        address pool = attack(sqrtPriceX96Of(1, 1e9)); // 1 NEW = 0.000000001 WBNB, tick about -207233
        _addAttackerLiquidityAbove(10e18);

        LaunchGuardV3.Params memory params = _params();
        params.maxSwapIn1 = 1e18;

        uint256 teamNewBefore = newToken.balanceOf(team);
        uint256 teamWbnbBefore = wbnb.balanceOf(team);
        (,,, uint256 amount0, uint256 amount1) = _launch(params);

        assertEq(priceOf(pool), targetPrice);
        uint256 spentOnSwap = teamWbnbBefore - amount1 - wbnb.balanceOf(team);
        assertGt(spentOnSwap, 0);
        assertLe(spentOnSwap, params.maxSwapIn1);
        assertApproxEqAbs(newToken.balanceOf(team), teamNewBefore - amount0 + 10e18, 1e6);
        _assertGuardIsClean();
    }

    /**
     * @notice If moving the price costs more than the caller allowed, the call reverts.
     */
    function test_RevertWhen_SwapInAboveMax() public {
        attack(ATTACKER_PRICE);
        _addAttackerLiquidity(10e18);

        vm.expectPartialRevert(LaunchGuardV3.SwapInAboveMax.selector);
        _launch(_params());
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Quote
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * @notice Moving the price of an empty pool costs nothing, and the quote says so.
     */
    function test_QuoteEmptyPool() public {
        address pool = attack(ATTACKER_PRICE);

        (int256 amount0, int256 amount1) = guard.quoteRestorePrice(IUniswapV3Pool(pool), targetPrice);

        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(priceOf(pool), ATTACKER_PRICE);
    }

    /**
     * @notice An uninitialized pool and a pool at the target price need no swap.
     */
    function test_QuoteNoSwapNeeded() public {
        vm.prank(attacker);
        address uninitialized = factory.createPool(address(newToken), address(wbnb), FEE);
        (int256 amount0, int256 amount1) = guard.quoteRestorePrice(IUniswapV3Pool(uninitialized), targetPrice);
        assertEq(amount0, 0);
        assertEq(amount1, 0);

        vm.prank(attacker);
        ITestV3PoolInit(uninitialized).initialize(targetPrice);
        (amount0, amount1) = guard.quoteRestorePrice(IUniswapV3Pool(uninitialized), targetPrice);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    /**
     * @notice The quote equals what `addInitialLiquidity` then pays (token0) and returns (token1) when it moves the
     *         price down through the attacker's liquidity.
     */
    function test_QuoteMatchesSwapDown() public {
        address pool = attack(ATTACKER_PRICE);
        _addAttackerLiquidity(10e18);

        (int256 quote0, int256 quote1) = guard.quoteRestorePrice(IUniswapV3Pool(pool), targetPrice);
        assertGt(quote0, 0);
        assertLt(quote1, 0);
        assertEq(priceOf(pool), ATTACKER_PRICE);

        LaunchGuardV3.Params memory params = _params();
        params.maxSwapIn0 = uint256(quote0);

        uint256 teamNewBefore = newToken.balanceOf(team);
        uint256 teamWbnbBefore = wbnb.balanceOf(team);
        vm.expectEmit(address(guard));
        emit LaunchGuardV3.PriceRestored(pool, ATTACKER_PRICE, targetPrice, quote0, quote1);
        (,,, uint256 amount0, uint256 amount1) = _launch(params);

        assertEq(teamNewBefore - amount0 - newToken.balanceOf(team), uint256(quote0));
        assertEq(wbnb.balanceOf(team) + amount1 - teamWbnbBefore, uint256(-quote1));
    }

    /**
     * @notice The same in the other direction: the price moves up through NEW-only liquidity.
     */
    function test_QuoteMatchesSwapUp() public {
        vm.prank(team);
        newToken.transfer(attacker, 10e18);
        uint160 lowPrice = sqrtPriceX96Of(1, 1e9);
        address pool = attack(lowPrice);
        _addAttackerLiquidityAbove(10e18);

        (int256 quote0, int256 quote1) = guard.quoteRestorePrice(IUniswapV3Pool(pool), targetPrice);
        assertLt(quote0, 0);
        assertGt(quote1, 0);

        LaunchGuardV3.Params memory params = _params();
        params.maxSwapIn1 = uint256(quote1);

        vm.expectEmit(address(guard));
        emit LaunchGuardV3.PriceRestored(pool, lowPrice, targetPrice, quote0, quote1);
        _launch(params);
    }

    /**
     * @notice Errors from the pool reach the caller unchanged.
     */
    function test_QuoteBubblesPoolErrors() public {
        address pool = attack(ATTACKER_PRICE);

        // A price limit below the V3 minimum: the pool reverts with "SPL".
        vm.expectRevert(bytes("SPL"));
        guard.quoteRestorePrice(IUniswapV3Pool(pool), 1);
    }

    /**
     * @notice A pool that does not call the callback cannot produce a quote.
     */
    function test_RevertWhen_QuoteFailed() public {
        SilentV3Pool pool = new SilentV3Pool();

        vm.expectRevert(LaunchGuardV3.QuoteFailed.selector);
        guard.quoteRestorePrice(IUniswapV3Pool(address(pool)), targetPrice);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Input validation and access
    // ---------------------------------------------------------------------------------------------------------------

    function test_RevertWhen_Expired() public {
        LaunchGuardV3.Params memory params = _params();
        vm.warp(params.deadline + 1);

        vm.expectRevert(LaunchGuardV3.Expired.selector);
        _launch(params);
    }

    function test_RevertWhen_RecipientIsZeroAddress() public {
        LaunchGuardV3.Params memory params = _params();
        params.recipient = address(0);

        vm.expectRevert(LaunchGuardV3.ZeroAddress.selector);
        _launch(params);
    }

    function test_RevertWhen_UnsortedTokens() public {
        LaunchGuardV3.Params memory params = _params();
        (params.token0, params.token1) = (params.token1, params.token0);

        vm.expectRevert(LaunchGuardV3.UnsortedTokens.selector);
        _launch(params);
    }

    /**
     * @notice Only the pool the guard is swapping in can call the callbacks.
     */
    function test_RevertWhen_CallbackFromUnknownCaller() public {
        bytes memory data = abi.encode(address(newToken), address(wbnb), type(uint256).max, type(uint256).max);

        vm.startPrank(attacker);
        vm.expectRevert(LaunchGuardV3.UnexpectedCallback.selector);
        guard.uniswapV3SwapCallback(1e18, 0, data);
        vm.expectRevert(LaunchGuardV3.UnexpectedCallback.selector);
        guard.pancakeV3SwapCallback(1e18, 0, data);
        vm.stopPrank();
    }

    /**
     * @notice A fake position manager returns a fake pool that calls the callback with its own data. The guard pays
     *         only from the account that called it, so the team's approval to the guard cannot be used.
     */
    function test_FakePoolCannotSpendOtherApprovals() public {
        FakeV3Pool fakePool = new FakeV3Pool(address(newToken), 100e18);
        FakePositionManager fakeManager = new FakePositionManager(address(fakePool));

        LaunchGuardV3.Params memory params = _params();
        params.positionManager = INonfungiblePositionManager(address(fakeManager));
        params.recipient = attacker;

        uint256 teamNewBefore = newToken.balanceOf(team);
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(guard), 0, 100e18)
        );
        guard.addInitialLiquidity(params);

        assertEq(newToken.balanceOf(team), teamNewBefore);
    }

    /**
     * @notice A pool whose swap does not reach the target price is rejected.
     */
    function test_RevertWhen_PriceNotRestored() public {
        FakeV3Pool fakePool = new FakeV3Pool(address(newToken), 0);
        LaunchGuardV3.Params memory params = _params();
        params.positionManager = INonfungiblePositionManager(address(new FakePositionManager(address(fakePool))));

        vm.expectRevert(abi.encodeWithSelector(LaunchGuardV3.PriceNotRestored.selector, uint160(1 << 96)));
        _launch(params);
    }

    /**
     * @notice A token that calls `addInitialLiquidity` again from inside a transfer cannot reach the tokens the
     *         guard holds during the mint.
     */
    function test_RevertWhen_Reentered() public {
        ReentrantERC20 token1;
        do {
            token1 = new ReentrantERC20();
        } while (address(token1) < address(newToken));
        token1.mint(team, AMOUNT_WBNB);
        vm.prank(team);
        token1.approve(address(guard), type(uint256).max);

        LaunchGuardV3.Params memory params = _params();
        params.token1 = address(token1);
        token1.arm(address(guard), abi.encodeCall(LaunchGuardV3.addInitialLiquidity, (params)));

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _launch(params);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * @notice Whatever price the attacker sets, the pool ends exactly at the target price.
     */
    function testFuzz_RestoresAnyAttackerPrice(uint256 attackerPrice) public {
        attackerPrice = bound(attackerPrice, MIN_SQRT_RATIO, MAX_SQRT_RATIO - 1);
        address pool = attack(uint160(attackerPrice));

        (, uint256 tokenId,,,) = _launch(_params());

        assertEq(priceOf(pool), targetPrice);
        assertEq(positionManager.ownerOf(tokenId), team);
        _assertGuardIsClean();
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------------

    function _params() internal view returns (LaunchGuardV3.Params memory) {
        return LaunchGuardV3.Params({
            positionManager: INonfungiblePositionManager(address(positionManager)),
            token0: address(newToken),
            token1: address(wbnb),
            fee: FEE,
            sqrtPriceX96: targetPrice,
            tickLower: FULL_RANGE_LOWER,
            tickUpper: FULL_RANGE_UPPER,
            amount0Desired: AMOUNT_NEW,
            amount1Desired: AMOUNT_WBNB,
            amount0Min: AMOUNT_NEW * 99 / 100,
            amount1Min: AMOUNT_WBNB * 99 / 100,
            maxSwapIn0: 0,
            maxSwapIn1: 0,
            recipient: team,
            deadline: block.timestamp
        });
    }

    function _launch(LaunchGuardV3.Params memory params)
        internal
        returns (address pool, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        vm.prank(team);
        return guard.addInitialLiquidity(params);
    }

    /**
     * @dev The attacker adds a WBNB-only position between the target (tick about -9943) and the attacker's price
     *      (tick about 138162). The attacker does not need NEW for it.
     */
    function _addAttackerLiquidity(uint256 amountWbnb) internal {
        vm.startPrank(attacker);
        wbnb.approve(address(positionManager), amountWbnb);
        positionManager.mint(
            ITestPositionManager.MintParams({
                token0: address(newToken),
                token1: address(wbnb),
                fee: FEE,
                tickLower: 60000,
                tickUpper: 120000,
                amount0Desired: 0,
                amount1Desired: amountWbnb,
                amount0Min: 0,
                amount1Min: 0,
                recipient: attacker,
                deadline: block.timestamp
            })
        );
        vm.stopPrank();
    }

    /**
     * @dev The attacker adds a NEW-only position above a low price (tick about -207233) and below the target.
     */
    function _addAttackerLiquidityAbove(uint256 amountNew) internal {
        vm.startPrank(attacker);
        newToken.approve(address(positionManager), amountNew);
        positionManager.mint(
            ITestPositionManager.MintParams({
                token0: address(newToken),
                token1: address(wbnb),
                fee: FEE,
                tickLower: -180000,
                tickUpper: -60000,
                amount0Desired: amountNew,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                recipient: attacker,
                deadline: block.timestamp
            })
        );
        vm.stopPrank();
    }

    function _assertGuardIsClean() internal view {
        assertEq(newToken.balanceOf(address(guard)), 0);
        assertEq(wbnb.balanceOf(address(guard)), 0);
        assertEq(newToken.allowance(address(guard), address(positionManager)), 0);
        assertEq(wbnb.allowance(address(guard), address(positionManager)), 0);
    }
}

interface ITestV3PoolInit {
    function initialize(uint160 sqrtPriceX96) external;
}
