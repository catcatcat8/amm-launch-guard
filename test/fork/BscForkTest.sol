// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Base for the BNB Smart Chain fork tests.
/// @dev Needs `BSC_RPC_URL`; without it the tests are skipped. `BSC_FORK_BLOCK` pins the block (needs an archive
///      node); by default the latest block is used.
abstract contract BscForkTest is Test {
    IERC20 internal constant WBNB = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    address internal team = makeAddr("team");
    address internal attacker = makeAddr("attacker");

    /// @dev Selects the fork. Returns false (and marks the tests as skipped) if `BSC_RPC_URL` is not set.
    function selectBscFork() internal returns (bool) {
        string memory rpcUrl = vm.envOr("BSC_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true, "BSC_RPC_URL is not set");
            return false;
        }
        uint256 forkBlock = vm.envOr("BSC_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpcUrl);
        else vm.createSelectFork(rpcUrl, forkBlock);
        return true;
    }
}
