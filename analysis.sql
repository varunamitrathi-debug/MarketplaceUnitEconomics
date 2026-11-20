-- Marketplace unit economics and customer cohort analysis (Olist, SQLite)
-- Each block starting with "-- name:" is one query. run.py runs them all and
-- saves each result to output/<name>.csv. You can also paste any block into
-- DB Browser for SQLite and run it on its own.
--
-- Definitions used everywhere
--   Customer  = customer_unique_id (one real person can have many customer_id values)
--   Order     = delivered orders only (order_status = 'delivered')
--   GMV       = sum of item price, freight excluded. Olist's commission is not in
--               the data, so revenue impacts below are stated in GMV.


-- name: 01 base facts
WITH d AS (
  SELECT o.order_id, c.customer_unique_id
  FROM orders o JOIN customers c ON c.customer_id = o.customer_id
  WHERE o.order_status = 'delivered'
)
SELECT
  (SELECT COUNT(*) FROM d)                                   AS deliveredOrders,
  (SELECT COUNT(DISTINCT customer_unique_id) FROM d)         AS customers,
  (SELECT ROUND(SUM(i.price), 0) FROM items i JOIN d USING (order_id)) AS gmvBrl,
  (SELECT ROUND(SUM(i.freight_value), 0) FROM items i JOIN d USING (order_id)) AS freightBrl,
  (SELECT MIN(order_purchase_timestamp) FROM orders WHERE order_status = 'delivered') AS firstOrder,
  (SELECT MAX(order_purchase_timestamp) FROM orders WHERE order_status = 'delivered') AS lastOrder;


-- name: 02 cohort retention
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


-- name: 03 cohort summary
-- Average retention across 2017 cohorts (all have at least 8 months of follow up)
WITH r AS (
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
  size AS (SELECT cohort, COUNT(*) AS n FROM first GROUP BY cohort)
  SELECT a.cohort, a.monthN, 100.0 * COUNT(DISTINCT a.cust) / s.n AS pct
  FROM activity a JOIN size s USING (cohort)
  GROUP BY a.cohort, a.monthN
)
SELECT monthN, ROUND(AVG(pct), 2) AS avgRetentionPct
FROM r
WHERE cohort BETWEEN '2017-01-01' AND '2017-12-01' AND monthN BETWEEN 1 AND 8
GROUP BY monthN ORDER BY monthN;


-- name: 04 repeat purchase rate
WITH perCust AS (
  SELECT c.customer_unique_id AS cust, COUNT(DISTINCT o.order_id) AS orders
  FROM orders o JOIN customers c ON c.customer_id = o.customer_id
  WHERE o.order_status = 'delivered'
  GROUP BY 1
)
SELECT COUNT(*) AS customers,
       SUM(orders >= 2) AS repeatCustomers,
       ROUND(100.0 * SUM(orders >= 2) / COUNT(*), 2) AS repeatRatePct,
       ROUND(AVG(orders), 3) AS ordersPerCustomer
FROM perCust;


-- name: 05 customer lifetime value
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


-- name: 06 seller concentration
WITH s AS (
  SELECT i.seller_id, SUM(i.price) AS gmv
  FROM items i JOIN orders o ON o.order_id = i.order_id
  WHERE o.order_status = 'delivered'
  GROUP BY i.seller_id
),
ranked AS (
  SELECT seller_id, gmv,
         ROW_NUMBER() OVER (ORDER BY gmv DESC) AS rk,
         COUNT(*) OVER () AS n,
         SUM(gmv) OVER () AS total
  FROM s
)
SELECT 'top 1 percent of sellers' AS slice, COUNT(*) AS sellers, ROUND(100.0 * SUM(gmv) / MAX(total), 1) AS shareOfGmvPct FROM ranked WHERE rk <= n * 0.01
UNION ALL SELECT 'top 10 percent of sellers', COUNT(*), ROUND(100.0 * SUM(gmv) / MAX(total), 1) FROM ranked WHERE rk <= n * 0.10
UNION ALL SELECT 'top 20 percent of sellers', COUNT(*), ROUND(100.0 * SUM(gmv) / MAX(total), 1) FROM ranked WHERE rk <= n * 0.20
UNION ALL SELECT 'bottom 50 percent of sellers', COUNT(*), ROUND(100.0 * SUM(gmv) / MAX(total), 1) FROM ranked WHERE rk > n * 0.50;


-- name: 07 category concentration
WITH c AS (
  SELECT REPLACE(COALESCE(t.product_category_name_english, 'unknown'), char(95), ' ') AS category,
         SUM(i.price) AS gmv, COUNT(DISTINCT i.order_id) AS orders,
         SUM(i.freight_value) AS freight
  FROM items i
  JOIN orders o ON o.order_id = i.order_id
  JOIN products p ON p.product_id = i.product_id
  LEFT JOIN categories t ON t.product_category_name = p.product_category_name
  WHERE o.order_status = 'delivered'
  GROUP BY 1
)
SELECT category, orders, ROUND(gmv, 0) AS gmvBrl,
       ROUND(100.0 * gmv / SUM(gmv) OVER (), 2) AS shareOfGmvPct,
       ROUND(100.0 * SUM(gmv) OVER (ORDER BY gmv DESC) / SUM(gmv) OVER (), 2) AS cumulativePct,
       ROUND(100.0 * freight / gmv, 1) AS freightPctOfPrice
FROM c ORDER BY gmv DESC;


-- name: 08 delivery delay vs review
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


-- name: 09 late first order vs repeat
-- Does a late first delivery make a customer less likely to come back?
WITH d AS (
  SELECT c.customer_unique_id AS cust, o.order_id, o.order_purchase_timestamp AS ts,
         o.order_delivered_customer_date > DATE(o.order_estimated_delivery_date, '+1 day') AS late
  FROM orders o JOIN customers c ON c.customer_id = o.customer_id
  WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
),
ranked AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY cust ORDER BY ts) AS rn,
                     COUNT(*) OVER (PARTITION BY cust) AS n FROM d)
SELECT CASE WHEN late THEN 'first order late' ELSE 'first order on time' END AS firstOrder,
       COUNT(*) AS customers,
       ROUND(100.0 * AVG(n >= 2), 2) AS repeatRatePct
FROM ranked WHERE rn = 1 AND ts < '2018-03-01'   -- leave at least 6 months to come back
GROUP BY 1;


-- name: 10 freight share by order value
WITH ord AS (
  SELECT i.order_id, SUM(i.price) AS price, SUM(i.freight_value) AS freight
  FROM items i JOIN orders o ON o.order_id = i.order_id
  WHERE o.order_status = 'delivered'
  GROUP BY i.order_id
),
r AS (SELECT order_id, AVG(review_score) AS score FROM reviews GROUP BY order_id)
SELECT CASE
         WHEN price < 50  THEN '1 under 50 BRL'
         WHEN price < 100 THEN '2 50 to 99 BRL'
         WHEN price < 200 THEN '3 100 to 199 BRL'
         WHEN price < 500 THEN '4 200 to 499 BRL'
         ELSE                  '5 500 BRL plus' END AS orderValueBand,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS shareOfOrdersPct,
       ROUND(100.0 * SUM(freight) / SUM(price), 1) AS freightPctOfPrice,
       ROUND(AVG(r.score), 2) AS avgReview
FROM ord LEFT JOIN r USING (order_id)
GROUP BY 1 ORDER BY 1;


-- name: 11 freight share overall
SELECT ROUND(100.0 * SUM(freight_value) / SUM(price), 2) AS freightPctOfPrice,
       ROUND(100.0 * SUM(freight_value) / (SUM(price) + SUM(freight_value)), 2) AS freightPctOfOrderValue
FROM items i JOIN orders o ON o.order_id = i.order_id
WHERE o.order_status = 'delivered';


-- name: 12 recommendation sizing
-- Inputs for the three recommendations. The uplift percentages themselves are
-- assumptions and are written into the README as such.
WITH ord AS (
  SELECT o.order_id, c.customer_unique_id AS cust, o.order_purchase_timestamp AS ts,
         SUM(i.price) AS gmv,
         o.order_delivered_customer_date > DATE(o.order_estimated_delivery_date, '+1 day') AS late
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
  JOIN items i ON i.order_id = o.order_id
  WHERE o.order_status = 'delivered'
  GROUP BY o.order_id
),
ranked AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY cust ORDER BY ts) AS rn FROM ord)
SELECT
  (SELECT COUNT(DISTINCT cust) FROM ord)                         AS customers,
  (SELECT ROUND(AVG(gmv), 2) FROM ranked WHERE rn >= 2)          AS avgRepeatOrderGmv,
  (SELECT COUNT(*) FROM ranked WHERE rn = 1 AND late = 1)        AS lateFirstOrders,
  (SELECT COUNT(*) FROM ranked WHERE rn = 1)                     AS firstOrders,
  (SELECT COUNT(*) FROM ord WHERE gmv < 50)                      AS ordersUnder50,
  (SELECT ROUND(AVG(gmv), 2) FROM ord WHERE gmv < 50)            AS avgGmvUnder50,
  (SELECT ROUND(SUM(gmv), 0) FROM ord)                           AS totalGmv;
