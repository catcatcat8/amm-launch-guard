# How common is the `sync()` attack?

A scan of every PancakeSwap V2 pair on BNB Smart Chain for the state that the [`sync()` attack](../README.md#uniswap-v2-the-sync-attack) leaves behind: a pair with **no LP tokens** and **exactly one non-zero reserve**. In this state `router.addLiquidity` always reverts, so the pair cannot be launched through the router.

## Results

Snapshot of the latest chain state, finished at 2026-11-10 14:25 UTC.

| | Pairs |
|---|---:|
| All PancakeSwap V2 pairs | 3,671,255 |
| With LP tokens | 2,641,900 |
| No LP tokens, both reserves zero (created, never used) | 1,016,641 |
| **No LP tokens, exactly one reserve > 0** (`addLiquidity` always reverts) | **11,991** |
| No LP tokens, both reserves > 0 (`addLiquidity` forced to the dust ratio) | 723 |

For the 11,991 pairs with one non-zero reserve:

- **Filled side:** WBNB in 10,439 pairs, USDT in 1,473, BUSD in 13, USDC in 5, other tokens in 61.
- **Amount:** exactly **1 wei** in 10,528 pairs (88%), 2–1000 wei in 1,291, more than 1000 wei in 172.
- **Tokens:** 11,208 distinct tokens on the zero side; 726 of them have two or more pairs in this state, usually with WBNB and USDT.
- **When:** the last `sync()` was in the 7 days before the scan for 170 pairs and in the 30 days before for 462.

By month of the last `sync()` (only months with at least 100 pairs):

| Month | Pairs |
|---|---:|
| 2023-08 | 3,635 |
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
| 2026-11 (1–10) | 219 |

The full list, with every month, comes from `python3 research/analyze.py`. Every pair is in [`data/blocked-pairs.csv`](data/blocked-pairs.csv) and can be checked on BscScan.

## How to read the numbers

- **A lower bound.** The scan sees only pairs that are still blocked. A pair that was attacked and launched later has LP tokens and is not counted.
- **The timestamp** is `blockTimestampLast` of the pair, the time of its last `sync()`. For a pair in this state it is the time of the attack.
- **Not the same as failed launches.** Many of these tokens may have launched in another pair or on another DEX. The data shows that the PancakeSwap V2 pair is blocked, not what happened to the token.
- **Intent is not proven.** 88% of the pairs hold exactly 1 wei of WBNB or USDT, and hundreds of tokens have both their WBNB and USDT pairs blocked. This looks automated, but the data does not show who sent the tokens or why.

## Method

[`PairScanner.sol`](PairScanner.sol) is never deployed. [`scan.py`](scan.py) sends its creation code with the constructor arguments in an `eth_call`, and the constructor returns the result instead of contract code. One call checks a batch of pairs `[from, to)` of the factory: it counts pairs with LP tokens and empty pairs, and returns a record for every pair with no LP tokens and a non-zero reserve. The whole factory takes about 1,250 calls through a public RPC.

## Reproduce

Requirements: Foundry and Python 3 (standard library only). From the repository root:

```bash
python3 research/scan.py scan <BSC_RPC_URL>   # about an hour; writes research/data/scan.jsonl
python3 research/scan.py export               # writes data/blocked-pairs.csv and data/totals.json
python3 research/analyze.py                   # prints the statistics above
```

`scan` takes optional `from` and `to` pair indexes to scan a range. A new scan sees the chain at a later time, so the numbers will differ.
