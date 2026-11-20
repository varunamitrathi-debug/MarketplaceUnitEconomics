"""
Step 1: load the Olist CSV files into one SQLite database file (olist.db).
Run once:  python load.py
Needs: pandas (pip install pandas). SQLite comes with Python.
"""
import sqlite3
import pandas as pd
from pathlib import Path

ROOT = Path(__file__).parent
DATA = ROOT / "data"

tables = {
    "customers": "customers.csv",
    "orders": "orders.csv",
    "items": "order items.csv",
    "payments": "payments.csv",
    "reviews": "reviews.csv",
    "products": "products.csv",
    "sellers": "sellers.csv",
    "categories": "category names.csv",
}

con = sqlite3.connect(ROOT / "olist.db")
for table, file in tables.items():
    df = pd.read_csv(DATA / file, encoding="utf-8-sig")
    df.to_sql(table, con, if_exists="replace", index=False)
    print(f"{table:15s} {len(df):>8,} rows")

# Indexes make the joins fast
for sql in [
    "CREATE INDEX IF NOT EXISTS i1 ON orders(order_id)",
    "CREATE INDEX IF NOT EXISTS i2 ON orders(customer_id)",
    "CREATE INDEX IF NOT EXISTS i3 ON items(order_id)",
    "CREATE INDEX IF NOT EXISTS i4 ON customers(customer_id)",
    "CREATE INDEX IF NOT EXISTS i5 ON reviews(order_id)",
    "CREATE INDEX IF NOT EXISTS i6 ON products(product_id)",
]:
    con.execute(sql)
con.commit()
con.close()
print("Saved olist.db")
