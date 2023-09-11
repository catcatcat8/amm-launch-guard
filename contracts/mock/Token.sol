// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/**
 * @title Token
 * @author gotbit
 */
contract Token is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_
    ) ERC20(name_, symbol_) {
        _mint(msg.sender, totalSupply_ * 10**18);
    }
}
