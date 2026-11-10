"""Scan all PancakeSwap V2 pairs for the state left by the sync() attack.

The scan runs research/PairScanner.sol through eth_call (the contract is never deployed) and
writes the raw batches to research/data/scan.jsonl. `export` turns them into the files that are
committed: research/data/blocked-pairs.csv and research/data/totals.json.

Usage (from the repository root):
    python3 research/scan.py scan <rpc_url> [from] [to]
    python3 research/scan.py export

Only the Python standard library and Foundry (`forge`) are needed.
"""

import csv
import datetime
import json
import os
import subprocess
import sys
import time
import urllib.request

FACTORY = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"  # PancakeSwap V2 factory on BNB Smart Chain
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
RAW = os.path.join(DATA, "scan.jsonl")
BATCH = 3000
GAS = 45_000_000  # below the eth_call gas cap of common public RPCs
RECORD = 96


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(url, body, {"content-type": "application/json", "user-agent": "pair-scan/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        reply = json.load(response)
    if "error" in reply:
        raise RuntimeError(reply["error"])
    return reply["result"]


def scanner_bytecode():
    out = subprocess.run(
        ["forge", "inspect", "research/PairScanner.sol:PairScanner", "bytecode"],
        check=True, capture_output=True, text=True,
    )
    return out.stdout.strip()


def word(value):
    return format(value, "064x")


def scan_batch(url, code, start, end):
    data = code + word(int(FACTORY, 16)) + word(start) + word(end)
    raw = bytes.fromhex(rpc(url, "eth_call", [{"data": data, "gas": hex(GAS)}, "latest"])[2:])
    scanned, with_lp, empty = (int.from_bytes(raw[i:i + 4], "big") for i in (0, 4, 8))
    records = []
    for offset in range(12, len(raw), RECORD):
        r = raw[offset:offset + RECORD]
        records.append({
            "index": int.from_bytes(r[0:4], "big"),
            "pair": "0x" + r[4:24].hex(),
            "token0": "0x" + r[24:44].hex(),
            "token1": "0x" + r[44:64].hex(),
            "reserve0": int.from_bytes(r[64:78], "big"),
            "reserve1": int.from_bytes(r[78:92], "big"),
            "timestamp": int.from_bytes(r[92:96], "big"),
        })
    return {"from": start, "to": end, "scanned": scanned, "with_lp": with_lp, "empty": empty, "records": records}


def scan(url, start, end):
    code = scanner_bytecode()
    if end is None:
        end = int(rpc(url, "eth_call", [{"to": FACTORY, "data": "0x574f2ba3"}, "latest"]), 16)  # allPairsLength()
    os.makedirs(DATA, exist_ok=True)
    print(f"scanning pairs [{start}, {end}) from block {int(rpc(url, 'eth_blockNumber', []), 16)}", flush=True)
    with open(RAW, "a") as out:
        i = start
        while i < end:
            j = min(i + BATCH, end)
            attempt = 0
            while True:
                try:
                    batch = scan_batch(url, code, i, j)
                    break
                except Exception as error:
                    # Too many results for one call: split the batch. Rate limits and timeouts: back off.
                    message = str(error)
                    if ("out of gas" in message or "CreateContractSizeLimit" in message) and j - i > 1:
                        j = i + (j - i) // 2
                        continue
                    attempt += 1
                    if attempt == 6:
                        raise SystemExit(f"giving up at pair {i}: {message}")
                    time.sleep(2 ** attempt)
            out.write(json.dumps(batch) + "\n")
            out.flush()
            print(f"[{i}, {j}) found {len(batch['records'])}", flush=True)
            i = j
    print(f"done at block {int(rpc(url, 'eth_blockNumber', []), 16)}; now run: python3 research/scan.py export")


def export():
    batches = sorted((json.loads(line) for line in open(RAW)), key=lambda b: b["from"])
    position = 0
    for b in batches:
        if b["from"] != position:
            raise SystemExit(f"gap or overlap in {RAW} at pair {position}")
        position = b["to"]

    totals = {
        "factory": FACTORY,
        "pairs_scanned": position,
        "with_lp": sum(b["with_lp"] for b in batches),
        "no_lp_empty": sum(b["empty"] for b in batches),
        "no_lp_with_reserves": sum(len(b["records"]) for b in batches),
        "scanned_at": datetime.datetime.fromtimestamp(os.path.getmtime(RAW), datetime.timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    with open(os.path.join(DATA, "totals.json"), "w") as out:
        json.dump(totals, out, indent=2)
        out.write("\n")

    columns = ["index", "pair", "token0", "token1", "reserve0", "reserve1", "timestamp"]
    with open(os.path.join(DATA, "blocked-pairs.csv"), "w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        for b in batches:
            writer.writerows(b["records"])
    print(json.dumps(totals, indent=2))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "scan":
        scan(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0, int(sys.argv[4]) if len(sys.argv) > 4 else None)
    elif sys.argv[1:] == ["export"]:
        export()
    else:
        raise SystemExit(__doc__)
