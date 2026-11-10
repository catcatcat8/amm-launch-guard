# Uniswap bytecode fixtures

The local tests run against the original Uniswap V2 and V3 contracts. They are compiled with old Solidity versions (0.5.16, 0.6.6, 0.7.6) and cannot be built together with this project, so the creation bytecode is taken from the official npm packages:

| File | Package | Artifact |
|---|---|---|
| `v2/UniswapV2Factory.hex` | `@uniswap/v2-core@1.0.1` | `build/UniswapV2Factory.json` |
| `v2/UniswapV2Router02.hex` | `@uniswap/v2-periphery@1.1.0-beta.0` | `build/UniswapV2Router02.json` |
| `v3/UniswapV3Factory.hex` | `@uniswap/v3-core@1.0.0` | `artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json` |
| `v3/NonfungiblePositionManager.hex` | `@uniswap/v3-periphery@1.0.0` | `artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json` |

The official builds are needed because the periphery contracts compute pair and pool addresses with hard-coded init code hashes: `0x96e8ac42…845f` in `UniswapV2Router02` and `0xe34f199b…8b54` in `NonfungiblePositionManager`. Contracts compiled locally would have different hashes.

Licenses: Uniswap V2 is GPL-3.0-or-later. Uniswap V3 periphery is GPL-2.0-or-later. Uniswap V3 core was released under BUSL-1.1 with a change date of 2023-04-01, after which it is GPL-2.0-or-later. The bytecode is used only in tests and is not part of the `LaunchGuardV2` / `LaunchGuardV3` contracts.
