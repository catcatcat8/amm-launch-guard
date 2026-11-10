// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "./MockERC20.sol";

/// @notice ERC20 that calls `target` with `data` on its next transfer, to test re-entrancy.
contract ReentrantERC20 is MockERC20 {
    address internal target;
    bytes internal data;

    constructor() MockERC20("Reentrant Token", "REENTER") {}

    function arm(address target_, bytes calldata data_) external {
        target = target_;
        data = data_;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        address callTarget = target;
        if (callTarget == address(0)) return;
        target = address(0);
        (bool ok, bytes memory result) = callTarget.call(data);
        if (!ok) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
