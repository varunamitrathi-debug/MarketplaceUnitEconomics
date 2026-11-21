# Unit economics and customer cohort analysis for a marketplace

**Question.** Where does a Brazilian online marketplace make and lose money at the customer level, and which three moves would add the most revenue?

**Answer in one line.** Olist is almost entirely a first purchase business: 97% of customers buy once and never return, so the biggest prize is a second order programme (about BRL 127k of extra GMV for every 1 point of repeat rate), followed by a basket threshold for small orders where freight costs almost half the item price.

## Approach

* Loaded the eight public Olist tables (about 100,000 orders, September 2016 to August 2018) into SQLite.
* Wrote 12 SQL queries using CTEs and window functions: monthly cohort retention, repeat purchase rate, customer lifetime value, revenue concentration by seller and by category, delivery delay versus review score, and freight cost as a share of order value.
* Sized three recommendations using only figures from those queries. Where a recommendation needs an uplift (for example "repeat rate rises 1 point") the uplift is an assumption, stated as such and kept in one place in `run.py` so it can be changed.

Definitions: a customer is a unique customer id (one real person), only delivered orders count, and GMV is item price excluding freight. Olist's commission is not in the data, so impacts are stated in GMV, not net revenue.

## Key findings

* **Scale.** 96,478 delivered orders from 93,358 customers, BRL 13.2 million GMV plus BRL 2.2 million freight.
* **Retention is close to zero.** Only 3.0% of customers ever place a second order (2,801 people). For the 2017 cohorts, an average of 0.49% buy again in the month after their first order, and between 0.21% and 0.35% in each of the following seven months.
* **Lifetime value is basically one basket.** Average GMV per customer over the two years is BRL 141.62 against an average order of BRL 137.04. Repeat customers are worth BRL 260.05 each but make up only 5.5% of GMV.
* **Sales are concentrated in a few sellers.** The top 1% of sellers (29 shops) generate 25.5% of GMV and the top 10% generate 67.1%. The bottom half of sellers generate 3.3%. The top five categories (health and beauty, watches and gifts, bed and bath, sports, computer accessories) make up 39.8%.
* **Late delivery wrecks reviews.** 93.3% of orders arrive on or before the promised date and average 4.2 to 4.3 stars. Orders 4 to 7 days late average 2.11 stars, and 68% of them get 1 or 2 stars. Customers whose first order arrived late came back 3.13% of the time, against 4.04% for those whose first order was on time.
* **Freight eats small baskets.** Freight is 16.6% of item price overall, but 48.4% on orders under BRL 50, which are 29.8% of all orders.

![Review score by delivery delay](charts/delivery%20delay%20vs%20review.png)

## SQL highlights

Three of the twelve queries in `analysis.sql`, with the result each one returns. All results are real outputs from `run.py` on the Olist data.

### Cohort retention with a CTE and date functions

```sql
-- 02 cohort retention
-- Cohort = month of a customer's first delivered order.
-- Retention in month N = share of the cohort that ordered again N months later.
WITH d AS (
  SELECT c.customer_unique_id AS cust,
         DATE(o.order_purchase_timestamp, 'start of month') AS m
  FROM orders o JOIN customers c ON c.customer_id = o.customer_id
  WHERE o.order_status = 'delivered'
),
first AS (SELECT cust, MIN(m) AS cohort FROM d GROUP BY cust),
activity AS (
  SELECT DISTINCT f.cohort, d.cust,
         (CAST(strftime('%Y', d.m) AS INT) - CAST(strftime('%Y', f.cohort) AS INT)) * 12
       + (CAST(strftime('%m', d.m) AS INT) - CAST(strftime('%m', f.cohort) AS INT)) AS monthN
  FROM d JOIN first f USING (cust)
),
size AS (SELECT cohort, COUNT(*) AS cohortSize FROM first GROUP BY cohort)
SELECT a.cohort, s.cohortSize, a.monthN,
       COUNT(DISTINCT a.cust) AS activeCustomers,
       ROUND(100.0 * COUNT(DISTINCT a.cust) / s.cohortSize, 2) AS retentionPct
FROM activity a JOIN size s USING (cohort)
WHERE a.cohort BETWEEN '2017-01-01' AND '2018-06-01'
GROUP BY a.cohort, a.monthN
ORDER BY a.cohort, a.monthN;
```

Result (`output/03 cohort summary.csv`):

| Month n | Avg retention % |
|---|---|
| 1 | 0.49 |
| 2 | 0.35 |
| 3 | 0.25 |
| 4 | 0.32 |
| 5 | 0.25 |
| 6 | 0.27 |
| 7 | 0.21 |
| 8 | 0.21 |

Average across 2017 cohorts: under half of one percent of customers order again the month after their first purchase.

### Customer lifetime value by repeat behaviour

```sql
-- 05 customer lifetime value
-- Historical value over the data window (about 23 months), in GMV.
WITH ord AS (
  SELECT o.order_id, c.customer_unique_id AS cust, SUM(i.price) AS gmv
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
  JOIN items i ON i.order_id = o.order_id
  WHERE o.order_status = 'delivered'
  GROUP BY o.order_id
),
cust AS (SELECT cust, COUNT(*) AS nOrders, SUM(gmv) AS gmv FROM ord GROUP BY cust)
SELECT CASE WHEN nOrders = 1 THEN 'one order' ELSE 'two or more' END AS segment,
       COUNT(*) AS customers,
       ROUND(AVG(nOrders), 2) AS ordersPerCustomer,
       ROUND(SUM(gmv) / SUM(nOrders), 2) AS avgOrderValue,
       ROUND(AVG(gmv), 2) AS gmvPerCustomer,
       ROUND(100.0 * SUM(gmv) / (SELECT SUM(gmv) FROM cust), 2) AS shareOfGmvPct
FROM cust GROUP BY 1
UNION ALL
SELECT 'all customers', COUNT(*), ROUND(AVG(nOrders), 2),
       ROUND(SUM(gmv) / SUM(nOrders), 2), ROUND(AVG(gmv), 2), 100.0
FROM cust;
```

Result (`output/05 customer lifetime value.csv`):

| Segment | Customers | Orders per customer | Avg order value | GMV per customer | Share of GMV % |
|---|---|---|---|---|---|
| one order | 90,557 | 1 | 137.96 | 137.96 | 94.49 |
| two or more | 2,801 | 2.11 | 123.02 | 260.05 | 5.51 |
| all customers | 93,358 | 1.03 | 137.04 | 141.62 | 100 |

Repeat customers are 3% of customers and 5.5% of GMV, so growth here depends on winning new customers rather than retention.

### Late delivery against review score

```sql
-- 08 delivery delay vs review
-- Days late = actual delivery date minus the estimated date promised at checkout.
WITH o AS (
  SELECT o.order_id,
         JULIANDAY(DATE(o.order_delivered_customer_date)) - JULIANDAY(DATE(o.order_estimated_delivery_date)) AS daysLate
  FROM orders o
  WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
),
r AS (SELECT order_id, AVG(review_score) AS score FROM reviews GROUP BY order_id)
SELECT CASE
         WHEN daysLate <= -7 THEN '1 early by 7 plus days'
         WHEN daysLate <= 0  THEN '2 early or on time'
         WHEN daysLate <= 3  THEN '3 late 1 to 3 days'
         WHEN daysLate <= 7  THEN '4 late 4 to 7 days'
         WHEN daysLate <= 14 THEN '5 late 8 to 14 days'
         ELSE                      '6 late 15 plus days' END AS deliveryBand,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS shareOfOrdersPct,
       ROUND(AVG(r.score), 2) AS avgReview,
       ROUND(100.0 * AVG(r.score <= 2), 1) AS pctOneOrTwoStars
FROM o JOIN r USING (order_id)
GROUP BY 1 ORDER BY 1;
```

Result (`output/08 delivery delay vs review.csv`):

| Delivery band | Orders | Share of orders % | Avg review | Pct one or two stars |
|---|---|---|---|---|
| 1 early by 7 plus days | 75,744 | 79.04 | 4.31 | 9 |
| 2 early or on time | 13,699 | 14.3 | 4.17 | 10.7 |
| 3 late 1 to 3 days | 1,852 | 1.93 | 3.29 | 32.2 |
| 4 late 4 to 7 days | 1,748 | 1.82 | 2.11 | 67.6 |
| 5 late 8 to 14 days | 1,446 | 1.51 | 1.67 | 80.1 |
| 6 late 15 plus days | 1,335 | 1.39 | 1.73 | 78.2 |

Average review falls from 4.31 for early deliveries to 1.73 for deliveries 15 or more days late.

## Recommendations and estimated impact

GMV over the same 23 month window. Value of one extra repeat customer = 1.11 extra orders x BRL 122.89 average repeat order = BRL 136.41, all from the data.

| # | Recommendation | How the impact is estimated | GMV impact | Share of GMV |
|---|---|---|---|---|
| 1 | **Second order programme**: a voucher or reminder timed to land within 30 days of first delivery | 93,358 customers x 1 point repeat lift (**assumption**) x BRL 136.41 | BRL 127,348 | 0.96% |
| 2 | **Free freight threshold for small baskets**, nudging orders under BRL 50 to add a second item | 28,791 small orders x 10% adding one item (**assumption**) x BRL 31.84 average small order | BRL 91,671 | 0.69% |
| 3 | **Protect the delivery promise on first orders**: pad estimated dates for sellers with a history of lateness | 6,355 late first orders x 0.91 point repeat gap (data) x BRL 136.41 | BRL 7,889 | 0.06% |

The third recommendation is small in direct GMV because so few customers return in any case. Its real value is in reviews: late orders are 6.7% of deliveries but account for about a third (32%) of all 1 and 2 star reviews, and public ratings shape conversion for every future buyer. That effect is not measurable in this dataset, so it is not counted here.

## Files

```
MarketplaceUnitEconomics/
  README.md          this summary
  Build Guide.md     step by step instructions
  load.py            loads the CSV files into olist.db
  analysis.sql       all 12 queries, commented
  run.py             runs every query, saves results, sizes the recommendations
  charts.py          draws the charts
  output/            one CSV per query
  charts/            PNG charts used above
  data/              put the Kaggle CSV files here (not committed)
```

## Tools

SQL (SQLite: CTEs, window functions such as ROW NUMBER and SUM OVER, date functions), Python (pandas, matplotlib) only to load data, run queries and draw charts.

## How to run

1. Download the [Brazilian E Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) from Kaggle, unzip it, and rename the files to the short names listed in the Build Guide (for example `orders.csv`, `order items.csv`) inside `data/`.
2. Run:

```
pip install pandas matplotlib
python load.py
python run.py
python charts.py
```

Everything runs in under a minute. To explore by hand, open `olist.db` in [DB Browser for SQLite](https://sqlitebrowser.org) and paste any query from `analysis.sql`.

Data: Olist, Brazilian E Commerce Public Dataset, published on Kaggle under CC BY NC SA 4.0.
