// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LaunchGuardV3} from "../../src/LaunchGuardV3.sol";

/**
 * @notice A malicious pool. On `swap` it calls the guard's callback with data that tries to make the guard pay
 *         `amount` of `token` with no limit.
 */
contract FakeV3Pool {
    address internal immutable token;
    uint256 internal immutable amount;

    constructor(address token_, uint256 amount_) {
        token = token_;
        amount = amount_;
    }

    function slot0() external pure returns (uint160, int24) {
        return (1 << 96, 0);
    }

    function swap(address, bool, int256, uint160, bytes calldata) external returns (int256, int256) {
        bytes memory data = abi.encode(token, token, type(uint256).max, type(uint256).max);
        LaunchGuardV3(msg.sender).uniswapV3SwapCallback(int256(amount), 0, data);
        return (int256(amount), 0);
    }
}

/**
 * @notice A malicious position manager that returns `FakeV3Pool` as the pool.
 */
contract FakePositionManager {
    address internal immutable pool;

    constructor(address pool_) {
        pool = pool_;
    }

    function createAndInitializePoolIfNecessary(address, address, uint24, uint160) external view returns (address) {
        return pool;
    }
}

/**
 * @notice A pool whose `swap` returns without calling the callback.
 */
contract SilentV3Pool {
    function slot0() external pure returns (uint160, int24) {
        return (1 << 96, 0);
    }

    function swap(address, bool, int256, uint160, bytes calldata) external pure returns (int256, int256) {
        return (0, 0);
    }
}
