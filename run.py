"""
Step 2: run every query in analysis.sql and save each result to output/.
Run after load.py:  python run.py
"""
import re
import sqlite3
import pandas as pd
from pathlib import Path

ROOT = Path(__file__).parent
OUT = ROOT / "output"
OUT.mkdir(exist_ok=True)

sql = (ROOT / "analysis.sql").read_text()
blocks = re.split(r"^-- name: (.+)$", sql, flags=re.M)[1:]
con = sqlite3.connect(ROOT / "olist.db")

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 20)


def spaced(name):
    """avgReview becomes 'avg review' so saved files have plain headers."""
    return re.sub(r"([a-z])([A-Z0-9])", r"\1 \2", name).lower()


def save(df, name):
    out = df.copy()
    out.columns = [spaced(c) for c in out.columns]
    out.to_csv(OUT / f"{name}.csv", index=False)


results = {}
for name, query in zip(blocks[0::2], blocks[1::2]):
    df = pd.read_sql_query(query, con)
    results[name.strip()] = df
    save(df, name.strip())
    print(f"\n=== {name.strip()} ===")
    print(df.head(25).to_string(index=False))
con.close()

# Step 3: size the three recommendations.
# Every input comes from the query results above. The uplift percentages
# are ASSUMPTIONS, set here so you can change them and rerun.
assumeRepeatLiftPts = 1.0      # recommendation 2: repeat rate +1 point
assumeSmallBasketAdd = 0.10    # recommendation 3: 10% of small orders add one item

s = results["12 recommendation sizing"].iloc[0]
late = results["09 late first order vs repeat"].set_index("firstOrder")["repeatRatePct"]
clv = results["05 customer lifetime value"].set_index("segment")

extraOrdersPerRepeater = clv.loc["two or more", "ordersPerCustomer"] - 1
valuePerNewRepeater = extraOrdersPerRepeater * s["avgRepeatOrderGmv"]

gap = (late["first order on time"] - late["first order late"]) / 100
r1 = s["lateFirstOrders"] * gap * valuePerNewRepeater
r2 = s["customers"] * assumeRepeatLiftPts / 100 * valuePerNewRepeater
r3 = s["ordersUnder50"] * assumeSmallBasketAdd * s["avgGmvUnder50"]

sizing = pd.DataFrame({
    "recommendation": ["1 second order programme (repeat rate up 1 point, assumption)",
                       "2 free freight threshold for small baskets (10% add an item, assumption)",
                       "3 protect the delivery promise on first orders"],
    "gmvImpactBrl": [round(r2), round(r3), round(r1)],
})
sizing["pctOfTotalGmv"] = (100 * sizing["gmvImpactBrl"] / s["totalGmv"]).round(2)
save(sizing, "13 recommendation impact")
print("\n=== 13 recommendation impact (GMV over the data window) ===")
print(f"Value of one new repeat customer: {valuePerNewRepeater:.2f} BRL")
print(sizing.to_string(index=False))
