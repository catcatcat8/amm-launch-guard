// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import './interfaces/IPancakePair.sol';
import './interfaces/IPancakeRouter.sol';
import './interfaces/IPancakeFactory.sol';

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './lib/Errors.sol';

contract AntiSync is Ownable {
    using SafeERC20 for IERC20;

    struct SyncParams {
        IPancakeRouter router;
        address tokenA;
        address tokenB;
        uint256 currentReservesA;
        uint256 currentReservesB;
        uint256 amountAToSync;
        uint256 amountBToSync;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
    }

    constructor(address owner) {
        if (owner == address(0)) revert ZeroAddress();
        _transferOwnership(owner);
    }

    function syncAndAddLiquidity(SyncParams memory params) external onlyOwner {
        if (params.to == address(0)) revert ZeroAddress();

        IPancakeFactory factory = IPancakeFactory(params.router.factory());
        IPancakePair pair = IPancakePair(
            factory.getPair(params.tokenA, params.tokenB)
        );
        if (address(pair) == address(0)) revert PairNotCreated();

        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        // To prevent front-run and price changes
        if (pair.token0() == params.tokenA) {
            if (
                uint112(params.currentReservesA) != reserve0 ||
                uint112(params.currentReservesB) != reserve1
            ) revert WrongReserves();
        } else {
            if (
                uint112(params.currentReservesB) != reserve0 ||
                uint112(params.currentReservesA) != reserve1
            ) revert WrongReserves();
        }

        if (params.amountAToSync != 0)
            IERC20(params.tokenA).safeTransferFrom(
                msg.sender,
                address(pair),
                params.amountAToSync
            );
        if (params.amountBToSync != 0)
            IERC20(params.tokenB).safeTransferFrom(
                msg.sender,
                address(pair),
                params.amountBToSync
            );
        pair.sync();

        IERC20(params.tokenA).approve(
            address(params.router),
            params.amountADesired
        );
        IERC20(params.tokenB).approve(
            address(params.router),
            params.amountBDesired
        );

        IERC20(params.tokenA).safeTransferFrom(
            msg.sender,
            address(this),
            params.amountADesired
        );
        IERC20(params.tokenB).safeTransferFrom(
            msg.sender,
            address(this),
            params.amountBDesired
        );

        params.router.addLiquidity(
            params.tokenA,
            params.tokenB,
            params.amountADesired,
            params.amountBDesired,
            params.amountAMin,
            params.amountBMin,
            params.to,
            block.timestamp
        );

        uint256 balanceA = IERC20(params.tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(params.tokenB).balanceOf(address(this));
        if (balanceA != 0) IERC20(params.tokenA).transfer(msg.sender, balanceA);
        if (balanceB != 0) IERC20(params.tokenB).transfer(msg.sender, balanceB);
    }
}
