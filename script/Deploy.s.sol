// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {AntiSync} from "../src/AntiSync.sol";

/// @notice Deploys AntiSync. The contract has no owner and no constructor arguments, so one deployment per chain is
///         enough for any number of launches.
/// @dev forge script script/Deploy.s.sol --rpc-url <RPC_URL> --account <KEYSTORE_ACCOUNT> --broadcast
contract Deploy is Script {
    function run() external returns (AntiSync antiSync) {
        vm.startBroadcast();
        antiSync = new AntiSync();
        vm.stopBroadcast();

        console.log("AntiSync deployed at", address(antiSync));
    }
}
