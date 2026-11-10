// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LaunchGuardV2} from "../../src/LaunchGuardV2.sol";
import {IUniswapV2Factory} from "../../src/interfaces/IUniswapV2Factory.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ITestFactory, ITestPair, ITestRouter} from "../utils/UniswapV2.sol";

/// @notice The attack and the fix on the real PancakeSwap V2 deployment on BNB Smart Chain.
/// @dev Needs `BSC_RPC_URL`; without it the tests are skipped. `BSC_FORK_BLOCK` pins the block (needs an archive
///      node); by default the latest block is used.
contract LaunchGuardV2ForkTest is Test {
    ITestFactory internal constant PANCAKE_FACTORY = ITestFactory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);
    ITestRouter internal constant PANCAKE_ROUTER = ITestRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IERC20 internal constant WBNB = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    uint256 internal constant AMOUNT_NEW = 1_000_000e18;
    uint256 internal constant AMOUNT_WBNB = 37e18; // 1 NEW = 0.000037 WBNB

    LaunchGuardV2 internal guard;
    MockERC20 internal newToken;
    ITestPair internal pair;

    address internal team = makeAddr("team");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        string memory rpcUrl = vm.envOr("BSC_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true, "BSC_RPC_URL is not set");
            return;
        }
        uint256 forkBlock = vm.envOr("BSC_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpcUrl);
        else vm.createSelectFork(rpcUrl, forkBlock);

        assertEq(PANCAKE_ROUTER.factory(), address(PANCAKE_FACTORY));

        guard = new LaunchGuardV2();
        newToken = new MockERC20("New Token", "NEW");
        newToken.mint(team, AMOUNT_NEW * 2);
        deal(address(WBNB), team, AMOUNT_WBNB * 2);
        deal(address(WBNB), attacker, 1e18);

        // The attack: create the pair, send 2 wei of WBNB and call sync().
        vm.startPrank(attacker);
        pair = ITestPair(PANCAKE_FACTORY.createPair(address(newToken), address(WBNB)));
        WBNB.transfer(address(pair), 2);
        pair.sync();
        vm.stopPrank();
    }

    function test_Fork_AttackBreaksRouterLaunch() public {
        vm.startPrank(team);
        newToken.approve(address(PANCAKE_ROUTER), AMOUNT_NEW);
        WBNB.approve(address(PANCAKE_ROUTER), AMOUNT_WBNB);
        vm.expectRevert(bytes("PancakeLibrary: INSUFFICIENT_LIQUIDITY"));
        PANCAKE_ROUTER.addLiquidity(
            address(newToken), address(WBNB), AMOUNT_NEW, AMOUNT_WBNB, 0, 0, team, block.timestamp
        );
        vm.stopPrank();
    }

    function test_Fork_GuardLaunchesAtTargetPrice() public {
        vm.startPrank(team);
        newToken.approve(address(guard), type(uint256).max);
        WBNB.approve(address(guard), type(uint256).max);
        (address launched, uint256 liquidity) = guard.addInitialLiquidity(
            LaunchGuardV2.Params({
                factory: IUniswapV2Factory(address(PANCAKE_FACTORY)),
                tokenA: address(newToken),
                tokenB: address(WBNB),
                amountA: AMOUNT_NEW,
                amountB: AMOUNT_WBNB,
                maxExtraA: 1e18,
                maxExtraB: 0,
                to: team,
                deadline: block.timestamp
            })
        );
        vm.stopPrank();

        assertEq(launched, address(pair));
        assertEq(pair.balanceOf(team), liquidity);

        // 2 wei of WBNB need ceil(2 * 1_000_000 / 37) = 54055 wei of extra NEW.
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        (uint256 reserveNew, uint256 reserveWbnb) =
            pair.token0() == address(newToken) ? (reserve0, reserve1) : (reserve1, reserve0);
        assertEq(reserveNew, AMOUNT_NEW + 54055);
        assertEq(reserveWbnb, AMOUNT_WBNB + 2);
    }
}
