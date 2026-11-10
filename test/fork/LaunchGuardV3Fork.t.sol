// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {LaunchGuardV3} from "../../src/LaunchGuardV3.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ITestPositionManager, ITestV3Factory, ITestV3Pool} from "../utils/UniswapV3.sol";
import {BscForkTest} from "./BscForkTest.sol";

/**
 * @notice The attack and the fix on the real PancakeSwap V3 deployment on BNB Smart Chain.
 */
contract LaunchGuardV3ForkTest is BscForkTest {
    ITestPositionManager internal constant POSITION_MANAGER =
        ITestPositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    ITestV3Factory internal constant V3_FACTORY = ITestV3Factory(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865);

    /**
     * @dev The 0.25% fee tier and its widest range (tick spacing 50).
     */
    uint24 internal constant FEE = 2500;
    int24 internal constant FULL_RANGE_LOWER = -887250;
    int24 internal constant FULL_RANGE_UPPER = 887250;

    uint256 internal constant AMOUNT_NEW = 1_000_000e18;
    uint256 internal constant AMOUNT_WBNB = 37e18; // 1 NEW = 0.000037 WBNB

    /**
     * @dev A wrong price set by the attacker: 1 token0 = 1,000,000 token1.
     */
    uint160 internal constant ATTACKER_PRICE = uint160(1000 << 96);

    LaunchGuardV3 internal guard;
    MockERC20 internal newToken;
    address internal token0;
    address internal token1;
    uint256 internal amount0;
    uint256 internal amount1;
    uint160 internal targetPrice;
    address internal pool;

    function setUp() public {
        if (!selectBscFork()) return;

        assertEq(POSITION_MANAGER.factory(), address(V3_FACTORY));

        guard = new LaunchGuardV3();
        newToken = new MockERC20("New Token", "NEW");
        newToken.mint(team, AMOUNT_NEW * 2);
        deal(address(WBNB), team, AMOUNT_WBNB * 2);

        // The V3 price is token1 per token0, so it depends on which token has the lower address.
        bool newIsToken0 = address(newToken) < address(WBNB);
        (token0, token1) = newIsToken0 ? (address(newToken), address(WBNB)) : (address(WBNB), address(newToken));
        (amount0, amount1) = newIsToken0 ? (AMOUNT_NEW, AMOUNT_WBNB) : (AMOUNT_WBNB, AMOUNT_NEW);
        targetPrice = uint160(Math.sqrt(Math.mulDiv(amount1, 1 << 192, amount0)));

        // The attack: create the pool and initialize it at a wrong price.
        vm.startPrank(attacker);
        pool = V3_FACTORY.createPool(token0, token1, FEE);
        ITestV3Pool(pool).initialize(ATTACKER_PRICE);
        vm.stopPrank();
    }

    function test_Fork_AttackKeepsWrongPrice() public {
        vm.prank(team);
        address returned = POSITION_MANAGER.createAndInitializePoolIfNecessary(token0, token1, FEE, targetPrice);

        assertEq(returned, pool);
        assertEq(_price(), ATTACKER_PRICE);
    }

    function test_Fork_GuardLaunchesAtTargetPrice() public {
        // The pool has no liquidity, so moving the price back costs nothing.
        (int256 quote0, int256 quote1) = guard.quoteRestorePrice(IUniswapV3Pool(pool), targetPrice);
        assertEq(quote0, 0);
        assertEq(quote1, 0);

        vm.startPrank(team);
        newToken.approve(address(guard), type(uint256).max);
        WBNB.approve(address(guard), type(uint256).max);
        (address launched, uint256 tokenId,, uint256 used0, uint256 used1) = guard.addInitialLiquidity(
            LaunchGuardV3.Params({
                positionManager: INonfungiblePositionManager(address(POSITION_MANAGER)),
                token0: token0,
                token1: token1,
                fee: FEE,
                sqrtPriceX96: targetPrice,
                tickLower: FULL_RANGE_LOWER,
                tickUpper: FULL_RANGE_UPPER,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0 * 99 / 100,
                amount1Min: amount1 * 99 / 100,
                maxSwapIn0: 0,
                maxSwapIn1: 0,
                recipient: team,
                deadline: block.timestamp
            })
        );
        vm.stopPrank();

        assertEq(launched, pool);
        assertEq(_price(), targetPrice);
        assertEq(POSITION_MANAGER.ownerOf(tokenId), team);
        assertApproxEqRel(used0, amount0, 1e12);
        assertApproxEqRel(used1, amount1, 1e12);
    }

    function _price() internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,) = ITestV3Pool(pool).slot0();
    }
}
