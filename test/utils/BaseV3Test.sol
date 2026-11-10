// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "../mocks/MockERC20.sol";
import {ITestPositionManager, ITestV3Factory, ITestV3Pool, UniswapV3Fixture} from "./UniswapV3.sol";

/// @notice Common setup for the V3 tests: a new token (NEW), a quote token (WBNB), Uniswap V3, the team and an
///         attacker. NEW is always token0, so the V3 price (token1 per token0) is the WBNB price of 1 NEW.
abstract contract BaseV3Test is UniswapV3Fixture {
    uint24 internal constant FEE = 3000;
    /// @dev The widest range for the 0.3% fee tier (tick spacing 60).
    int24 internal constant FULL_RANGE_LOWER = -887220;
    int24 internal constant FULL_RANGE_UPPER = 887220;

    /// @dev The team wants to launch NEW at 1 NEW = 0.37 WBNB.
    uint256 internal constant AMOUNT_NEW = 1_000e18;
    uint256 internal constant AMOUNT_WBNB = 370e18;

    /// @dev The attacker's price: 1 NEW = 1,000,000 WBNB.
    uint160 internal constant ATTACKER_PRICE = uint160(1000 << 96);

    uint160 internal targetPrice;

    MockERC20 internal newToken;
    MockERC20 internal wbnb;
    ITestV3Factory internal factory;
    ITestPositionManager internal positionManager;

    address internal team = makeAddr("team");
    address internal attacker = makeAddr("attacker");

    function setUp() public virtual {
        wbnb = new MockERC20("Wrapped BNB", "WBNB");
        do {
            newToken = new MockERC20("New Token", "NEW");
        } while (address(newToken) > address(wbnb));

        (factory, positionManager) = deployUniswapV3(address(wbnb));
        targetPrice = sqrtPriceX96Of(AMOUNT_WBNB, AMOUNT_NEW);

        newToken.mint(team, 1_000_000e18);
        wbnb.mint(team, 1_000e18);
        wbnb.mint(attacker, 1_000e18);
    }

    /// @dev The attack: create the pool and initialize it at `sqrtPriceX96`.
    function attack(uint160 sqrtPriceX96) internal returns (address pool) {
        vm.startPrank(attacker);
        pool = factory.createPool(address(newToken), address(wbnb), FEE);
        ITestV3Pool(pool).initialize(sqrtPriceX96);
        vm.stopPrank();
    }

    function poolOf() internal view returns (address) {
        return factory.getPool(address(newToken), address(wbnb), FEE);
    }

    /// @dev A full-range position with the team's amounts.
    function fullRangeMint(address recipient) internal view returns (ITestPositionManager.MintParams memory) {
        return ITestPositionManager.MintParams({
            token0: address(newToken),
            token1: address(wbnb),
            fee: FEE,
            tickLower: FULL_RANGE_LOWER,
            tickUpper: FULL_RANGE_UPPER,
            amount0Desired: AMOUNT_NEW,
            amount1Desired: AMOUNT_WBNB,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: block.timestamp
        });
    }
}
