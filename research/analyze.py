"""Print statistics for research/data/blocked-pairs.csv and research/data/totals.json.

Usage (from the repository root): python3 research/analyze.py
"""

import collections
import csv
import datetime
import json
import os

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
QUOTES = {
    "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c": "WBNB",
    "0x55d398326f99059ff775485246999027b3197955": "USDT",
    "0xe9e7cea3dedca5984780bafc599bd69add087d56": "BUSD",
    "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d": "USDC",
}

totals = json.load(open(os.path.join(DATA, "totals.json")))
rows = list(csv.DictReader(open(os.path.join(DATA, "blocked-pairs.csv"))))
scanned_at = datetime.datetime.strptime(totals["scanned_at"], "%Y-%m-%dT%H:%M:%SZ").replace(
    tzinfo=datetime.timezone.utc
)

one_sided = [r for r in rows if (r["reserve0"] == "0") != (r["reserve1"] == "0")]
both = [r for r in rows if r["reserve0"] != "0" and r["reserve1"] != "0"]

quote_side = collections.Counter()
amounts = collections.Counter()
tokens = collections.Counter()
months = collections.Counter()
last_7 = last_30 = 0
for r in one_sided:
    filled, blocked = ("token1", "token0") if r["reserve0"] == "0" else ("token0", "token1")
    amount = int(r["reserve1"] if r["reserve0"] == "0" else r["reserve0"])
    quote_side[QUOTES.get(r[filled], "other")] += 1
    amounts["1 wei" if amount == 1 else "2-1000 wei" if amount <= 1000 else "more than 1000 wei"] += 1
    tokens[r[blocked]] += 1
    synced = datetime.datetime.fromtimestamp(int(r["timestamp"]), datetime.timezone.utc)
    months[synced.strftime("%Y-%m")] += 1
    age = (scanned_at - synced).days
    last_7 += age < 7
    last_30 += age < 30

print(f"Scanned at {totals['scanned_at']}, factory {totals['factory']}")
print(f"Pairs scanned:                              {totals['pairs_scanned']:>9,}")
print(f"  with LP tokens:                           {totals['with_lp']:>9,}")
print(f"  no LP tokens, both reserves zero:         {totals['no_lp_empty']:>9,}")
print(f"  no LP tokens, exactly one reserve > 0:    {len(one_sided):>9,}  <- addLiquidity always reverts")
print(f"  no LP tokens, both reserves > 0:          {len(both):>9,}  <- addLiquidity forced to the dust ratio")
print()
print("One reserve > 0:")
print("  filled side:     ", ", ".join(f"{k} {v:,}" for k, v in quote_side.most_common()))
print("  amount:          ", ", ".join(f"{k} {v:,}" for k, v in amounts.most_common()))
print(f"  distinct tokens:  {len(tokens):,} ({sum(1 for v in tokens.values() if v > 1):,} with 2+ blocked pairs)")
print(f"  last sync() in the last 7 days: {last_7:,}, in the last 30 days: {last_30:,}")
print()
print("By month of the last sync():")
for month in sorted(months):
    print(f"  {month}  {months[month]:>5,}")
