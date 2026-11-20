"""
Step 3: draw the charts for the README from the CSVs in output/.
Run after run.py:  python charts.py   (needs matplotlib)
"""
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter
from pathlib import Path

ROOT = Path(__file__).parent
OUT, CH = ROOT / "output", ROOT / "charts"
CH.mkdir(exist_ok=True)
plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False})

d = pd.read_csv(OUT / "08 delivery delay vs review.csv")
d["label"] = d["delivery band"].str[2:]
fig, ax = plt.subplots(figsize=(8, 4))
ax.bar(d["label"], d["avg review"], color="#333333")
for x, v in zip(d["label"], d["avg review"]):
    ax.text(x, v + 0.05, f"{v:.2f}", ha="center")
ax.set_ylim(0, 5); ax.set_ylabel("Average review score")
ax.set_title("Review score collapses once an order arrives late")
plt.setp(ax.get_xticklabels(), rotation=20, ha="right")
plt.tight_layout(); plt.savefig(CH / "delivery delay vs review.png", dpi=150); plt.close()

c = pd.read_csv(OUT / "03 cohort summary.csv")
fig, ax = plt.subplots(figsize=(7, 4))
ax.plot(c["month n"], c["avg retention pct"] / 100, marker="o", color="#333333")
ax.yaxis.set_major_formatter(PercentFormatter(1.0, decimals=1))
ax.set_xlabel("Months after first order"); ax.set_ylabel("Share of cohort ordering again")
ax.set_title("Fewer than 1 in 100 customers come back in any later month (2017 cohorts)")
plt.tight_layout(); plt.savefig(CH / "cohort retention.png", dpi=150); plt.close()

f = pd.read_csv(OUT / "10 freight share by order value.csv")
f["label"] = f["order value band"].str[2:]
fig, ax = plt.subplots(figsize=(7, 4))
ax.bar(f["label"], f["freight pct of price"] / 100, color="#333333")
ax.yaxis.set_major_formatter(PercentFormatter(1.0))
ax.set_ylabel("Freight as share of item price")
ax.set_title("Freight is almost half the price of a small basket")
plt.tight_layout(); plt.savefig(CH / "freight share by order value.png", dpi=150); plt.close()
print("Charts saved")
