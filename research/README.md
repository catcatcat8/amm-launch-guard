# How common is the `sync()` attack?

A scan of every PancakeSwap V2 pair on BNB Smart Chain for the state that the [`sync()` attack](../README.md#uniswap-v2-the-sync-attack) leaves behind: a pair with **no LP tokens** and **exactly one non-zero reserve**. In this state `router.addLiquidity` always reverts, so the pair cannot be launched through the router. The attack itself is a known griefing vector; the scan measures how often it happens.

## Results

Chain state read on 2026-11-25 between 08:04 and 09:55 UTC. The scan was interrupted once and resumed from the next pair, so pairs with higher indexes were read later in that window.

| | Pairs |
|---|---:|
| All PancakeSwap V2 pairs | 3,772,897 |
| With LP tokens | 2,667,860 |
| No LP tokens, both reserves zero (created, never used) | 1,091,463 |
| **No LP tokens, exactly one reserve > 0** (`addLiquidity` always reverts) | **12,846** |
| No LP tokens, both reserves > 0 (`addLiquidity` forced to the dust ratio) | 728 |

For the 12,846 pairs with one non-zero reserve:

- **Filled side:** WBNB in 10,894 pairs, USDT in 1,872, BUSD in 13, USDC in 5, other tokens in 62.
- **Amount:** exactly **1 wei** in 11,372 pairs (89%), 2–1000 wei in 1,290, more than 1000 wei in 184. Exactly 1 wei of WBNB or USDT: 11,347 pairs (88%).
- **Tokens:** 11,693 distinct tokens on the zero side; 1,095 of them have two or more pairs in this state, and for 1,089 of those both the WBNB and the USDT pair are blocked.
- **When:** the last `sync()` was in the 7 days before the scan for 463 pairs and in the 30 days before for 1,187.

By month of the last `sync()` (only months with at least 100 pairs):

| Month | Pairs |
|---|---:|
| 2023-08 | 3,634 |
| 2023-09 | 631 |
| 2024-04 | 625 |
| 2024-05 | 349 |
| 2024-06 | 248 |
| 2024-07 | 189 |
| 2024-08 | 105 |
| 2025-07 | 101 |
| 2025-10 | 400 |
| 2025-11 | 2,089 |
| 2025-12 | 157 |
| 2026-01 | 244 |
| 2026-06 | 427 |
| 2026-08 | 278 |
| 2026-09 | 566 |
| 2026-10 | 294 |
| 2026-11 (1–25) | 1,075 |

The full list, with every month, comes from `python3 research/analyze.py`. Every pair is in [`data/blocked-pairs.csv`](data/blocked-pairs.csv) and can be checked on BscScan.

## How to read the numbers

- **A lower bound.** The scan sees only pairs that are still blocked. A pair that was attacked and launched later has LP tokens and is not counted.
- **Emptied pairs are not counted.** The first `mint` of a pair locks `MINIMUM_LIQUIDITY` (1000 LP tokens) on the zero address forever, so a pair that ever had liquidity never returns to `totalSupply() == 0`. A pair whose LPs withdrew everything and left some dust is in the "with LP tokens" group. With no LP tokens, the reserves can become non-zero only through a transfer to the pair followed by `sync()`.
- **The timestamp** is `blockTimestampLast` of the pair, the time of its last `sync()`. For a pair in this state it is the time of the attack.
- **Not the same as failed launches.** Many of these tokens may have launched in another pair or on another DEX. The data shows that the PancakeSwap V2 pair is blocked, not what happened to the token.
- **Intent is not proven.** 88% of the pairs hold exactly 1 wei of WBNB or USDT, and more than a thousand tokens have both their WBNB and USDT pairs blocked. This looks automated, but the data does not show who sent the tokens or why.

## Method

[`PairScanner.sol`](PairScanner.sol) is never deployed. [`scan.py`](scan.py) sends its creation code with the constructor arguments in an `eth_call`, and the constructor returns the result instead of contract code. One call checks a batch of pairs `[from, to)` of the factory: it counts pairs with LP tokens and empty pairs, and returns a record for every pair with no LP tokens and a non-zero reserve. The whole factory takes about 1,300 calls and about an hour through a public RPC.

## Reproduce

Requirements: Foundry and Python 3 (standard library only; the chart also needs matplotlib). From the repository root:

```bash
python3 research/scan.py scan <BSC_RPC_URL>   # about an hour; writes research/data/scan.jsonl
python3 research/scan.py export               # writes data/blocked-pairs.csv and data/totals.json
python3 research/analyze.py                   # prints the statistics above
python3 research/chart.py [out.png]           # bar chart by month; needs matplotlib
```

`scan` takes optional `from` and `to` pair indexes to scan a range. A new scan sees the chain at a later time, so the numbers will differ.
