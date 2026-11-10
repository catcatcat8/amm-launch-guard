// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFactory {
    function allPairs(uint256 index) external view returns (address);
}

interface IPair {
    function totalSupply() external view returns (uint256);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

/**
 * @title PairScanner
 * @notice Finds Uniswap V2 pairs that have no LP tokens but non-zero reserves: the state left by the `sync()` attack.
 * @dev Never deployed. `research/scan.py` sends the creation code with the constructor arguments in an `eth_call`,
 *      and the constructor returns the result instead of the contract code. One call scans the pairs
 *      `[from, to)` of the factory.
 *
 *      Output, tightly packed:
 *      - header: `uint32 scanned`, `uint32 withLp`, `uint32 empty` (no LP tokens and both reserves zero);
 *      - one 96-byte record per pair with no LP tokens and at least one non-zero reserve:
 *        `uint32 index`, `address pair`, `address token0`, `address token1`, `uint112 reserve0`,
 *        `uint112 reserve1`, `uint32 blockTimestampLast`.
 */
contract PairScanner {
    constructor(IFactory factory, uint256 from, uint256 to) {
        uint32 withLp;
        uint32 empty;
        bytes memory records;
        for (uint256 i = from; i < to; i++) {
            IPair pair = IPair(factory.allPairs(i));
            if (pair.totalSupply() != 0) {
                withLp++;
                continue;
            }
            (uint112 reserve0, uint112 reserve1, uint32 timestamp) = pair.getReserves();
            if (reserve0 == 0 && reserve1 == 0) {
                empty++;
                continue;
            }
            records = abi.encodePacked(
                records, uint32(i), address(pair), pair.token0(), pair.token1(), reserve0, reserve1, timestamp
            );
        }
        bytes memory result = abi.encodePacked(uint32(to - from), withLp, empty, records);
        assembly {
            return(add(result, 32), mload(result))
        }
    }
}
