// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {LaunchGuardV2} from "../src/LaunchGuardV2.sol";
import {LaunchGuardV3} from "../src/LaunchGuardV3.sol";

/**
 * @notice Deploys LaunchGuardV2 and LaunchGuardV3. The contracts have no owner and no constructor arguments, so one
 *         deployment per chain is enough for any number of launches.
 * @dev forge script script/Deploy.s.sol --rpc-url <RPC_URL> --account <KEYSTORE_ACCOUNT> --broadcast
 */
contract Deploy is Script {
    function run() external returns (LaunchGuardV2 guardV2, LaunchGuardV3 guardV3) {
        vm.startBroadcast();
        guardV2 = new LaunchGuardV2();
        guardV3 = new LaunchGuardV3();
        vm.stopBroadcast();

        console.log("LaunchGuardV2 deployed at", address(guardV2));
        console.log("LaunchGuardV3 deployed at", address(guardV3));
    }
}
