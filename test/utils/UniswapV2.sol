// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Full Uniswap V2 factory interface used by the tests.
interface ITestFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function createPair(address tokenA, address tokenB) external returns (address pair);
}

/// @notice Full Uniswap V2 pair interface used by the tests.
interface ITestPair {
    function token0() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function sync() external;

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

/// @notice Uniswap V2 router functions used by the tests.
interface ITestRouter {
    function factory() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

/// @notice Deploys the original Uniswap V2 factory and router from `test/fixtures` and adds pair helpers.
abstract contract UniswapV2Fixture is Test {
    function deployUniswapV2(address weth) internal returns (ITestFactory factory, ITestRouter router) {
        factory = ITestFactory(_deployFixture("UniswapV2Factory", abi.encode(address(0))));
        router = ITestRouter(_deployFixture("UniswapV2Router02", abi.encode(address(factory), weth)));
    }

    /// @dev Returns the pair reserves in the order of `tokenA`, `tokenB`.
    function reservesOf(ITestPair pair, address tokenA) internal view returns (uint256 reserveA, uint256 reserveB) {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        (reserveA, reserveB) = pair.token0() == tokenA ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _deployFixture(string memory name, bytes memory args) private returns (address deployed) {
        string memory hexCode = vm.trim(vm.readFile(string.concat("test/fixtures/", name, ".hex")));
        bytes memory initCode = abi.encodePacked(vm.parseBytes(hexCode), args);
        assembly {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), string.concat("failed to deploy ", name));
    }
}
