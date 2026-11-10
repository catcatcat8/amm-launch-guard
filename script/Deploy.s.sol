// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {LaunchGuardV2} from "../src/LaunchGuardV2.sol";

/// @notice Deploys LaunchGuardV2. The contract has no owner and no constructor arguments, so one deployment per chain is
///         enough for any number of launches.
/// @dev forge script script/Deploy.s.sol --rpc-url <RPC_URL> --account <KEYSTORE_ACCOUNT> --broadcast
contract Deploy is Script {
    function run() external returns (LaunchGuardV2 guard) {
        vm.startBroadcast();
        guard = new LaunchGuardV2();
        vm.stopBroadcast();

        console.log("LaunchGuardV2 deployed at", address(guard));
    }
}
