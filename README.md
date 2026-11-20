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
