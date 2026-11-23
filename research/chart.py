"""Bar chart of blocked PancakeSwap V2 pairs by month, from research/data/.

Counts the pairs with no LP tokens and exactly one non-zero reserve, by the month of their last
sync() (blockTimestampLast). The last month is shown lighter if the scan ended before it was over.

Usage (from the repository root, needs matplotlib):
    python3 research/chart.py [output.png]      # default: notes/blocked-pairs-by-month.png
"""

import collections
import csv
import datetime
import json
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import FancyBboxPatch, Rectangle  # noqa: E402

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
OUT = sys.argv[1] if len(sys.argv) > 1 else "notes/blocked-pairs-by-month.png"
SOURCE = "Scan of all PancakeSwap V2 pairs, github.com/catcatcat8/amm-launch-guard"

# 1200 x 675 px.
WIDTH, HEIGHT, DPI = 12, 6.75, 100

SURFACE = "#fcfcfb"
SERIES = "#2a78d6"
SERIES_PARTIAL = "#9fc2ec"  # the same blue, lighter: the month is not over
TEXT = "#0b0b0b"
TEXT_SECONDARY = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
BASELINE = "#c3c2b7"
CORNER_PX = 4

totals = json.load(open(os.path.join(DATA, "totals.json")))
scanned_at = datetime.datetime.strptime(totals["scanned_at"], "%Y-%m-%dT%H:%M:%SZ")

counts = collections.Counter()
for row in csv.DictReader(open(os.path.join(DATA, "blocked-pairs.csv"))):
    if (row["reserve0"] == "0") != (row["reserve1"] == "0"):
        synced = datetime.datetime.fromtimestamp(int(row["timestamp"]), datetime.timezone.utc)
        counts[(synced.year, synced.month)] += 1

# Every month from the first one with a blocked pair to the month of the scan, zeros included.
months = []
year, month = min(counts)
while (year, month) <= (scanned_at.year, scanned_at.month):
    months.append((year, month))
    year, month = (year + 1, 1) if month == 12 else (year, month + 1)
values = [counts[m] for m in months]
partial_last = scanned_at.day < 28  # the scan ended early in its month

fig = plt.figure(figsize=(WIDTH, HEIGHT), dpi=DPI, facecolor=SURFACE)
ax = fig.add_axes((0.075, 0.17, 0.9, 0.6), facecolor=SURFACE)

top = max(values) * 1.12
ax.set_xlim(-0.8, len(months) - 0.2)
ax.set_ylim(0, top)

# Columns with a rounded data end and a square base. The radius is set in pixels, so it is converted to
# data units on each axis.
fig.canvas.draw()
box = ax.get_window_extent()
px_per_x = box.width / (len(months) - 0.2 + 0.8)
px_per_y = box.height / top
radius_x = CORNER_PX / px_per_x
radius_y = CORNER_PX / px_per_y
bar_width = min(0.72, 24 / px_per_x)
for i, value in enumerate(values):
    if value == 0:
        continue
    color = SERIES_PARTIAL if partial_last and i == len(values) - 1 else SERIES
    left = i - bar_width / 2
    if value > 2 * radius_y:
        ax.add_patch(FancyBboxPatch(
            (left, 0), bar_width, value, boxstyle=f"round,pad=0,rounding_size={radius_x}",
            mutation_aspect=radius_y / radius_x, linewidth=0, facecolor=color,
        ))
    ax.add_patch(Rectangle((left, 0), bar_width, min(value, radius_y), linewidth=0, facecolor=color))

# Recessive axes: hairline gridlines, a baseline, no frame.
ax.yaxis.grid(True, color=GRID, linewidth=1)
ax.set_axisbelow(True)
for side in ("top", "right", "left"):
    ax.spines[side].set_visible(False)
ax.spines["bottom"].set_color(BASELINE)
ax.tick_params(axis="both", length=0, labelsize=17, labelcolor=MUTED, pad=8)
ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"))
ax.yaxis.set_major_locator(matplotlib.ticker.MaxNLocator(4, steps=[1, 2, 5, 10]))

# One label per year, under January.
ticks = [i for i, (y, m) in enumerate(months) if m == 1]
ax.set_xticks(ticks, [str(months[i][0]) for i in ticks])

# Direct labels only for the two largest months and for the last month.
labelled = sorted(range(len(values)), key=lambda i: values[i], reverse=True)[:2]
names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
for i in labelled:
    y, m = months[i]
    ax.annotate(f"{values[i]:,}\n{names[m - 1]} {y}", (i, values[i]), xytext=(0, 8), textcoords="offset points",
                ha="center", va="bottom", fontsize=16, color=TEXT, linespacing=1.2)
last = len(values) - 1
if partial_last and last not in labelled:
    y, m = months[last]
    # Above the neighbouring columns, so the label does not cover them.
    clear = max(values[-4:])
    ax.annotate(f"{values[last]:,}\n{names[m - 1]} 1–{scanned_at.day}", (last, clear), xytext=(4, 8),
                textcoords="offset points", ha="right", va="bottom", fontsize=16, color=TEXT_SECONDARY,
                linespacing=1.2)


def fitted_text(y, text, size, **style):
    """Places text at the left margin and shrinks it until it fits the figure width."""
    item = fig.text(0.075, y, text, fontsize=size, va="center", **style)
    limit = fig.bbox.width * (1 - 0.075 - 0.025)
    renderer = fig.canvas.get_renderer()
    while item.get_window_extent(renderer).width > limit:
        size -= 0.5
        item.set_fontsize(size)
    return item


total = sum(values)
fitted_text(0.915, "PancakeSwap V2 pairs blocked by the sync() attack", 30, color=TEXT, fontweight="bold")
fitted_text(0.845, f"{total:,} pairs with no LP tokens and one non-zero reserve, by month of the last sync()", 19,
            color=TEXT_SECONDARY)
fitted_text(0.045, f"{SOURCE}  ·  data as of {scanned_at:%b} {scanned_at.day}, {scanned_at.year}", 15, color=MUTED)

os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
fig.savefig(OUT, dpi=DPI, facecolor=SURFACE)
print(f"{OUT}: {len(months)} months, {total:,} pairs")
