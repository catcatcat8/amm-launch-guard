// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LaunchGuardV2} from "../../src/LaunchGuardV2.sol";
import {IUniswapV2Factory} from "../../src/interfaces/IUniswapV2Factory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {BaseV2Test} from "../utils/BaseV2Test.sol";
import {ITestPair} from "../utils/UniswapV2.sol";

contract LaunchGuardV2Test is BaseV2Test {
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    LaunchGuardV2 internal guard;

    function setUp() public override {
        super.setUp();
        guard = new LaunchGuardV2();

        vm.startPrank(team);
        newToken.approve(address(guard), type(uint256).max);
        wbnb.approve(address(guard), type(uint256).max);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Launch
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * @notice After the attack the guard launches the pair at the target price.
     */
    function test_GuardRestoresTargetPrice() public {
        ITestPair pair = attack(2);

        // 2 wei of WBNB need 2 * 1000 / 370 = 5.4 wei of NEW, rounded up to 6.
        (uint256 extraNew, uint256 extraWbnb) = _quote();
        assertEq(extraNew, 6);
        assertEq(extraWbnb, 0);

        uint256 teamNewBefore = newToken.balanceOf(team);
        uint256 teamWbnbBefore = wbnb.balanceOf(team);

        vm.expectEmit(address(guard));
        emit LaunchGuardV2.InitialLiquidityAdded(
            address(pair), team, team, AMOUNT_NEW + 6, AMOUNT_WBNB, _expectedLiquidity(6, 0)
        );
        (address launched, uint256 liquidity) = _launch(_params());

        assertEq(launched, address(pair));
        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        assertEq(reserveNew, AMOUNT_NEW + 6);
        assertEq(reserveWbnb, AMOUNT_WBNB + 2);
        _assertTargetPrice(pair, AMOUNT_NEW, AMOUNT_WBNB);

        // The team paid exactly the deposit and got all LP tokens. The guard keeps nothing.
        assertEq(newToken.balanceOf(team), teamNewBefore - AMOUNT_NEW - 6);
        assertEq(wbnb.balanceOf(team), teamWbnbBefore - AMOUNT_WBNB);
        assertEq(pair.balanceOf(team), liquidity);
        assertEq(pair.totalSupply(), liquidity + MINIMUM_LIQUIDITY);
        _assertNoBalances();
    }

    /**
     * @notice Without the attack the guard creates the pair and adds the exact amounts.
     */
    function test_CreatesPairIfMissing() public {
        assertEq(address(pairOf()), address(0));

        (address pair,) = _launch(_params());

        assertEq(pair, address(pairOf()));
        (uint256 reserveNew, uint256 reserveWbnb) = reserves(ITestPair(pair));
        assertEq(reserveNew, AMOUNT_NEW);
        assertEq(reserveWbnb, AMOUNT_WBNB);
    }

    /**
     * @notice A pair that was created in advance but is empty needs no extra tokens.
     */
    function test_EmptyPairCreatedInAdvance() public {
        vm.prank(attacker);
        factory.createPair(address(newToken), address(wbnb));

        (uint256 extraNew, uint256 extraWbnb) = _quote();
        assertEq(extraNew, 0);
        assertEq(extraWbnb, 0);

        _launch(_params());
        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pairOf());
        assertEq(reserveNew, AMOUNT_NEW);
        assertEq(reserveWbnb, AMOUNT_WBNB);
    }

    /**
     * @notice Dust on both sides at the attacker's 1:1 ratio is balanced to the target ratio.
     */
    function test_DustOnBothSides() public {
        vm.prank(team);
        newToken.transfer(attacker, 1);
        vm.startPrank(attacker);
        ITestPair pair = ITestPair(factory.createPair(address(newToken), address(wbnb)));
        newToken.transfer(address(pair), 1);
        wbnb.transfer(address(pair), 1);
        pair.sync();
        vm.stopPrank();

        _launch(_params());

        _assertTargetPrice(pair, AMOUNT_NEW, AMOUNT_WBNB);
    }

    /**
     * @notice Tokens sent to the pair without `sync()` are counted too, because the guard reads balances.
     */
    function test_CountsTokensSentWithoutSync() public {
        vm.startPrank(attacker);
        ITestPair pair = ITestPair(factory.createPair(address(newToken), address(wbnb)));
        wbnb.transfer(address(pair), 0.1e18);
        vm.stopPrank();

        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        assertEq(reserveNew + reserveWbnb, 0);

        _launch(_params());

        _assertTargetPrice(pair, AMOUNT_NEW, AMOUNT_WBNB);
    }

    /**
     * @notice The token order in the call does not matter.
     */
    function test_ReversedTokenOrder() public {
        ITestPair pair = attack(2);

        LaunchGuardV2.Params memory params = _params();
        (params.tokenA, params.tokenB) = (address(wbnb), address(newToken));
        (params.amountA, params.amountB) = (AMOUNT_WBNB, AMOUNT_NEW);
        (params.maxExtraA, params.maxExtraB) = (params.maxExtraB, params.maxExtraA);
        _launch(params);

        _assertTargetPrice(pair, AMOUNT_NEW, AMOUNT_WBNB);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Front-running
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * @notice A front-run donation within `maxExtra` does not change the price. The donation goes to the team.
     */
    function test_FrontRunDonationGoesToTheTeam() public {
        ITestPair pair = attack(2);

        // The team prepares the call with a margin for front-running.
        LaunchGuardV2.Params memory params = _params();
        params.maxExtraA = 100e18;

        // The attacker front-runs the launch with 10 WBNB.
        vm.prank(attacker);
        wbnb.transfer(address(pair), 10e18);

        uint256 teamNewBefore = newToken.balanceOf(team);
        uint256 teamWbnbBefore = wbnb.balanceOf(team);
        (, uint256 liquidity) = _launch(params);
        _assertTargetPrice(pair, AMOUNT_NEW, AMOUNT_WBNB);

        // The team burns all LP tokens and gets its deposit back plus the attacker's WBNB
        // (minus the share of MINIMUM_LIQUIDITY that stays locked in the pair).
        vm.startPrank(team);
        pair.transfer(address(pair), liquidity);
        pair.burn(team);
        vm.stopPrank();

        assertGt(wbnb.balanceOf(team), teamWbnbBefore + 10e18 - 1e9);
        assertGt(newToken.balanceOf(team), teamNewBefore - 1e9);
    }

    /**
     * @notice A front-run that needs more extra tokens than the caller allowed makes the call revert.
     */
    function test_RevertWhen_ExtraAboveMax() public {
        ITestPair pair = attack(2);

        // Allowed: the quoted 6 wei of NEW plus a small margin.
        LaunchGuardV2.Params memory params = _params();
        params.maxExtraA = 1e6;
        params.maxExtraB = 0;

        vm.prank(attacker);
        wbnb.transfer(address(pair), 1e18);

        (uint256 extraNew,) = _quote();
        vm.expectRevert(abi.encodeWithSelector(LaunchGuardV2.ExtraAboveMax.selector, extraNew, 0));
        _launch(params);
    }

    /**
     * @notice If someone already provided liquidity, extra tokens would go to them. the guard reverts.
     */
    function test_RevertWhen_PairHasLiquidity() public {
        _launch(_params());

        vm.expectRevert(LaunchGuardV2.PairHasLiquidity.selector);
        _launch(_params());
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Input validation
    // ---------------------------------------------------------------------------------------------------------------

    function test_RevertWhen_Expired() public {
        LaunchGuardV2.Params memory params = _params();
        vm.warp(params.deadline + 1);

        vm.expectRevert(LaunchGuardV2.Expired.selector);
        _launch(params);
    }

    function test_RevertWhen_ZeroAmount() public {
        LaunchGuardV2.Params memory params = _params();
        params.amountA = 0;
        vm.expectRevert(LaunchGuardV2.ZeroAmount.selector);
        _launch(params);

        params = _params();
        params.amountB = 0;
        vm.expectRevert(LaunchGuardV2.ZeroAmount.selector);
        _launch(params);

        vm.expectRevert(LaunchGuardV2.ZeroAmount.selector);
        guard.quoteExtra(_factory(), address(newToken), address(wbnb), 0, AMOUNT_WBNB);
    }

    function test_RevertWhen_ToIsZeroAddress() public {
        LaunchGuardV2.Params memory params = _params();
        params.to = address(0);

        vm.expectRevert(LaunchGuardV2.ZeroAddress.selector);
        _launch(params);
    }

    function test_QuoteExtraWithoutPair() public view {
        (uint256 extraNew, uint256 extraWbnb) = _quote();
        assertEq(extraNew, 0);
        assertEq(extraWbnb, 0);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * @notice For any target price and any tokens already in the pair (synced or not), the final pair balances
     *         match the target ratio up to 1 wei.
     */
    function testFuzz_FinalPriceMatchesTarget(
        uint256 amountNew,
        uint256 amountWbnb,
        uint256 donatedNew,
        uint256 donatedWbnb,
        bool synced
    ) public {
        amountNew = bound(amountNew, 1e9, 1e30);
        amountWbnb = bound(amountWbnb, 1e9, 1e30);
        donatedNew = bound(donatedNew, 0, 1e24);
        donatedWbnb = bound(donatedWbnb, 0, 1e24);

        vm.startPrank(attacker);
        ITestPair pair = ITestPair(factory.createPair(address(newToken), address(wbnb)));
        newToken.mint(address(pair), donatedNew);
        wbnb.mint(address(pair), donatedWbnb);
        if (synced) pair.sync();
        vm.stopPrank();

        (uint256 extraNew, uint256 extraWbnb) =
            guard.quoteExtra(_factory(), address(newToken), address(wbnb), amountNew, amountWbnb);
        // A Uniswap V2 pair cannot hold more than 2^112 - 1 of a token.
        vm.assume(donatedNew + amountNew + extraNew < type(uint112).max);
        vm.assume(donatedWbnb + amountWbnb + extraWbnb < type(uint112).max);

        newToken.mint(team, amountNew + extraNew);
        wbnb.mint(team, amountWbnb + extraWbnb);

        LaunchGuardV2.Params memory params = _params();
        (params.amountA, params.amountB) = (amountNew, amountWbnb);
        (params.maxExtraA, params.maxExtraB) = (extraNew, extraWbnb);
        _launch(params);

        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        assertEq(reserveNew, donatedNew + amountNew + extraNew);
        assertEq(reserveWbnb, donatedWbnb + amountWbnb + extraWbnb);
        _assertTargetPrice(pair, amountNew, amountWbnb);
        _assertNoBalances();
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------------

    function _factory() internal view returns (IUniswapV2Factory) {
        return IUniswapV2Factory(address(factory));
    }

    function _params() internal view returns (LaunchGuardV2.Params memory) {
        return LaunchGuardV2.Params({
            factory: _factory(),
            tokenA: address(newToken),
            tokenB: address(wbnb),
            amountA: AMOUNT_NEW,
            amountB: AMOUNT_WBNB,
            maxExtraA: 1e18,
            maxExtraB: 1e18,
            to: team,
            deadline: block.timestamp
        });
    }

    function _launch(LaunchGuardV2.Params memory params) internal returns (address pair, uint256 liquidity) {
        vm.prank(team);
        return guard.addInitialLiquidity(params);
    }

    function _quote() internal view returns (uint256 extraNew, uint256 extraWbnb) {
        return guard.quoteExtra(_factory(), address(newToken), address(wbnb), AMOUNT_NEW, AMOUNT_WBNB);
    }

    /**
     * @dev LP minted for the first deposit: sqrt(deposit0 * deposit1) - MINIMUM_LIQUIDITY. Only the attack dust
     *      (2 wei of WBNB, already in the reserves) is excluded from the deposit.
     */
    function _expectedLiquidity(uint256 extraNew, uint256 extraWbnb) internal pure returns (uint256) {
        return _sqrt((AMOUNT_NEW + extraNew) * (AMOUNT_WBNB + extraWbnb)) - MINIMUM_LIQUIDITY;
    }

    /**
     * @dev The side that got extra tokens is the smallest whole amount at or above the exact target:
     *      `reserveWbnb = ceil(reserveNew * amountWbnb / amountNew)` or the same with the sides swapped.
     */
    function _assertTargetPrice(ITestPair pair, uint256 amountNew, uint256 amountWbnb) internal view {
        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        if (reserveWbnb * amountNew >= reserveNew * amountWbnb) {
            assertEq(reserveWbnb, _ceilDiv(reserveNew * amountWbnb, amountNew), "WBNB reserve off target");
        } else {
            assertEq(reserveNew, _ceilDiv(reserveWbnb * amountNew, amountWbnb), "NEW reserve off target");
        }
    }

    function _assertNoBalances() internal view {
        assertEq(newToken.balanceOf(address(guard)), 0);
        assertEq(wbnb.balanceOf(address(guard)), 0);
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
