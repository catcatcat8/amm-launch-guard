// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Deploys contracts from the creation bytecode stored in `test/fixtures/<name>.hex`.
abstract contract Fixtures is Test {
    function deployFixture(string memory name, bytes memory args) internal returns (address deployed) {
        string memory hexCode = vm.trim(vm.readFile(string.concat("test/fixtures/", name, ".hex")));
        bytes memory initCode = abi.encodePacked(vm.parseBytes(hexCode), args);
        assembly {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), string.concat("failed to deploy ", name));
    }
}
