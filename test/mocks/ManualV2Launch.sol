// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITestPair, ITestRouter} from "../utils/UniswapV2.sol";

/**
 * @notice The correct manual workaround for the `sync()` attack, without LaunchGuardV2: in one transaction, send
 *         large amounts of both tokens to the pair at the target ratio, call `sync()`, then add the rest through the
 *         router. A contract is needed because an account cannot make several calls atomically.
 */
contract ManualV2Launch {
    function launch(
        ITestRouter router,
        ITestPair pair,
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 seedA,
        uint256 seedB,
        uint256 restA,
        uint256 restB
    ) external {
        tokenA.transferFrom(msg.sender, address(pair), seedA);
        tokenB.transferFrom(msg.sender, address(pair), seedB);
        pair.sync();

        tokenA.transferFrom(msg.sender, address(this), restA);
        tokenB.transferFrom(msg.sender, address(this), restB);
        tokenA.approve(address(router), restA);
        tokenB.approve(address(router), restB);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            restA,
            restB,
            restA * 99 / 100,
            restB * 99 / 100,
            msg.sender,
            block.timestamp
        );
    }
}
