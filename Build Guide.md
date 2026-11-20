# Build guide: marketplace unit economics in SQL

Two evenings. You need Python 3 (for loading and charts) and, if you like clicking around, DB Browser for SQLite.

## Evening 1: data and the first queries

**1. Get the data**

* Sign in to Kaggle and open [Brazilian E Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).
* Click Download and unzip. Put the files in `data/` and rename each one to a short name: `customers.csv`, `orders.csv`, `order items.csv`, `payments.csv`, `reviews.csv`, `products.csv`, `sellers.csv`, and `category names.csv` for the product category translation file. Leave out the geolocation file; it is not used.

**2. Load into SQLite**

```
pip install pandas matplotlib
python load.py
```

This creates `olist.db`, one file holding eight tables. Check the row counts it prints: 99,441 orders, 112,650 order items, 99,224 reviews.

**3. Learn the shape of the data**

The tables join like this:

* Orders join to customers on the customer id. Each order gets a new customer id, so to follow a real person across orders use the customer unique id column in the customers table instead. This is the most common mistake people make with this dataset.
* Items join to orders on the order id. There is one row per item, with its price and freight value.
* Items join to products on the product id, and products join to the categories table for English category names.
* Reviews join to orders on the order id.

In `load.py` the tables are called `customers`, `orders`, `items`, `payments`, `reviews`, `products`, `sellers` and `categories`. The column names inside them come from the original dataset, so they keep its own spelling.

**4. Run the queries one by one**

Open `analysis.sql`. Each block starting with `-- name:` is one query. Paste them into DB Browser (Execute SQL tab) in order and read the result before moving on. What each one teaches you:

* **01 base facts.** A sanity check: totals and the date range.
* **02 cohort retention.** The key technique. Step 1 gives each customer their first month (`MIN` grouped by customer). Step 2 works out, for every later order, how many months after that first month it happened. Step 3 counts distinct customers per cohort and month and divides by the cohort size.
* **03 cohort summary.** Averages the 2017 cohorts so you get one retention curve instead of 18 rows of noise.
* **04 repeat purchase rate.** Customers with two or more orders divided by all customers. `SUM(orders >= 2)` works because SQLite treats TRUE as 1.
* **05 customer lifetime value.** Splits customers into one order and two or more, then compares orders, order value and GMV per customer.

## Evening 2: concentration, delivery, freight and sizing

* **06 seller concentration.** The ROW NUMBER window function, ordered by GMV, ranks sellers; `COUNT(*) OVER ()` gives the total number so you can cut at the top 1%, 10% and 20%.
* **07 category concentration.** `SUM(gmv) OVER (ORDER BY gmv DESC)` gives a running total, which turns into a Pareto curve.
* **08 delivery delay versus review.** `JULIANDAY(delivered) minus JULIANDAY(estimated)` gives days late. A `CASE` statement groups them into bands, then you average the review score per band.
* **09 late first order versus repeat.** Finds each customer's first order with ROW NUMBER partitioned by customer and ordered by date, and compares repeat rates. Only first orders before March 2018 count, so everyone had at least six months to come back.
* **10 and 11 freight share.** Freight divided by item price, by order size band and overall.
* **12 recommendation sizing.** Pulls the handful of numbers the three recommendations need.

Then run the whole pipeline so every result is saved and the impact table is built:

```
python run.py
python charts.py
```

`run.py` ends by sizing the recommendations. The two uplift assumptions sit at the top of that step:

```
assumeRepeatLiftPts = 1.0
assumeSmallBasketAdd = 0.10
```

Change them, rerun, and the impact table updates. When you present, say clearly that these two numbers are assumptions and everything else is from the data.

## Publish

* Check the README numbers against `output/` (every figure in the README is in one of those CSVs).
* Commit everything except `data/` and `olist.db` (both are in `.gitignore`).
