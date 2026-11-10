# Uniswap V2 bytecode fixtures

The local tests run against the original Uniswap V2 contracts. They are compiled with Solidity 0.5.16 / 0.6.6 and cannot be built together with this project, so the creation bytecode is taken from the official npm packages:

| File | Package | Artifact |
|---|---|---|
| `UniswapV2Factory.hex` | `@uniswap/v2-core@1.0.1` | `build/UniswapV2Factory.json` |
| `UniswapV2Router02.hex` | `@uniswap/v2-periphery@1.1.0-beta.0` | `build/UniswapV2Router02.json` |

The official build is needed because `UniswapV2Router02` computes pair addresses with a hard-coded init code hash (`0x96e8ac42…845f`). A pair compiled locally would have a different hash.

Uniswap V2 is licensed under GPL-3.0-or-later. The bytecode is used only in tests and is not part of the `AntiSync` contract.
